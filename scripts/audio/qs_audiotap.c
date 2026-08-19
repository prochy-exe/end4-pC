// qs-audiotap: minimal-latency audio analysis for the Quickshell wallpaper
// effect.
//
// Connects straight to PipeWire, captures either the default sink monitor or
// one specific application's output stream, and prints one line per analysis
// hop:
//
//     bass mid treble volume beat bar0 bar1 ... barN-1\n
//
// All values are 0..1. The first five are the scalars the wallpaper shader
// wants; the rest is a log-spaced spectrum over --range (50Hz..16kHz by
// default), which is what the bar visualisers consume - this replaces cava
// outright rather than running alongside it.
//
// Everything - windowing, FFT, band split, auto gain, beat detection - happens
// here so the QML side does no DSP and adds no smoothing latency. The FFT is
// hand-rolled radix-2 to keep the dependency list at libpipewire + libm.
//
// Build: scripts/audio/build.sh

#define _GNU_SOURCE
#include <math.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>

#define FFT_N 1024 // 21.3ms window at 48kHz - enough resolution for bass
#define HOP 256    // analyse every 5.3ms
#define HIST 48    // ~0.25s of bass history for beat detection
#define MAXBARS 256

struct data {
    struct pw_main_loop *loop;
    struct pw_context *context;
    struct pw_core *core;
    struct pw_registry *registry;
    struct spa_hook registry_listener;
    struct spa_hook core_listener;

    struct pw_stream *stream;
    struct spa_hook stream_listener;

    struct spa_audio_info_raw format;

    // Which application to follow, and the node we are currently attached to.
    const char *app_filter;
    bool mic; // capture the default input instead of the speakers
    const char *source_name; // explicit PipeWire node to capture from
    uint32_t target_serial; // 0 = default sink monitor
    uint32_t attached_serial;
    uint32_t target_id;     // registry id of that node, for removal tracking
    uint32_t attached_id;
    bool reconnect_pending;

    // Rolling analysis window, written continuously by the capture callback.
    float ring[FFT_N];
    int ring_pos;
    int since_hop;

    float window[FFT_N]; // precomputed Hann

    float peak[3];      // per-band auto gain reference
    float vpeak;        // auto gain for overall level
    float bass_hist[HIST];
    int hist_pos;
    float beat;         // decaying envelope, computed here to avoid QML lag
    bool armed;         // re-arm hysteresis, stops one kick firing twice
    double last_beat;

    // Log-spaced spectrum bars.
    int bars;
    float bar_lo_hz, bar_hi_hz;
    int bar_bin[MAXBARS + 1]; // bin edges, rebuilt when the sample rate changes
    int bar_rate;             // rate the edges were built for
    float bar_val[MAXBARS];   // smoothed output
    float bar_peak;           // shared auto gain for the spectrum
    float bar_decay;          // fall per hop

    double last_emit;
    double emit_interval;
    double beat_decay;
    double beat_min_gap;
    float beat_sensitivity; // how far above its average bass must jump
    float beat_floor;       // bass below this never counts as a beat
    float gain_release;     // auto gain release per hop, 0..1
    bool verbose;
};

static struct data g_data;
static volatile sig_atomic_t g_stop = 0;

static void on_signal(int sig)
{
    (void)sig;
    g_stop = 1;
    if (g_data.loop)
        pw_main_loop_quit(g_data.loop);
}

static double now_seconds(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

// In-place iterative radix-2 Cooley-Tukey.
static void fft(float *re, float *im, int n)
{
    for (int i = 1, j = 0; i < n; i++) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1)
            j ^= bit;
        j ^= bit;
        if (i < j) {
            float t = re[i]; re[i] = re[j]; re[j] = t;
            t = im[i]; im[i] = im[j]; im[j] = t;
        }
    }
    for (int len = 2; len <= n; len <<= 1) {
        float ang = -2.0f * (float)M_PI / (float)len;
        float wr = cosf(ang), wi = sinf(ang);
        for (int i = 0; i < n; i += len) {
            float cr = 1.0f, ci = 0.0f;
            int half = len / 2;
            for (int k = 0; k < half; k++) {
                float ur = re[i + k], ui = im[i + k];
                float xr = re[i + k + half], xi = im[i + k + half];
                float vr = xr * cr - xi * ci;
                float vi = xr * ci + xi * cr;
                re[i + k] = ur + vr;
                im[i + k] = ui + vi;
                re[i + k + half] = ur - vr;
                im[i + k + half] = ui - vi;
                float ncr = cr * wr - ci * wi;
                ci = cr * wi + ci * wr;
                cr = ncr;
            }
        }
    }
}

static float clamp01(float v)
{
    return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v);
}

// Sum FFT magnitudes across a frequency range.
static float band(const float *re, const float *im, float rate, float lo, float hi)
{
    int b0 = (int)(lo * FFT_N / rate);
    int b1 = (int)(hi * FFT_N / rate);
    if (b0 < 1) b0 = 1;
    if (b1 > FFT_N / 2) b1 = FFT_N / 2;
    if (b1 <= b0) return 0.0f;
    float sum = 0.0f;
    for (int i = b0; i < b1; i++)
        sum += sqrtf(re[i] * re[i] + im[i] * im[i]);
    return sum / (float)(b1 - b0);
}

// Log-spaced bin edges. Rebuilt only when the negotiated sample rate changes.
static void build_bars(struct data *d, float rate)
{
    d->bar_rate = (int)rate;
    float lo = logf(d->bar_lo_hz), hi = logf(fminf(d->bar_hi_hz, rate * 0.5f - 1.0f));
    for (int i = 0; i <= d->bars; i++) {
        float f = expf(lo + (hi - lo) * (float)i / (float)d->bars);
        int bin = (int)(f * FFT_N / rate);
        if (bin < 1) bin = 1;
        if (bin > FFT_N / 2) bin = FFT_N / 2;
        d->bar_bin[i] = bin;
    }
}

static void analyse(struct data *d)
{
    float rate = d->format.rate > 0 ? (float)d->format.rate : 48000.0f;
    if ((int)rate != d->bar_rate)
        build_bars(d, rate);
    static float re[FFT_N], im[FFT_N];

    float rms = 0.0f;
    for (int i = 0; i < FFT_N; i++) {
        int idx = (d->ring_pos + i) % FFT_N;
        float s = d->ring[idx];
        rms += s * s;
        re[i] = s * d->window[i];
        im[i] = 0.0f;
    }
    rms = sqrtf(rms / (float)FFT_N);

    fft(re, im, FFT_N);

    float raw_bass = band(re, im, rate, 20.0f, 160.0f);
    float raw_mid = band(re, im, rate, 160.0f, 2000.0f);
    float raw_treble = band(re, im, rate, 2000.0f, 12000.0f);

    // Per-band auto gain, instant attack and slow release. This has to be per
    // band: music carries far more energy at low frequencies, so a single
    // shared reference is pinned by the bass and leaves treble stuck near zero.
    // A silence gate keeps the gain from amplifying room noise into a light show.
    float raw[3] = { raw_bass, raw_mid, raw_treble };
    float out[3];
    for (int i = 0; i < 3; i++) {
        d->peak[i] = fmaxf(raw[i], d->peak[i] * d->gain_release);
        out[i] = clamp01(raw[i] / fmaxf(d->peak[i], 1e-5f));
    }
    d->vpeak = fmaxf(rms, d->vpeak * d->gain_release);

    float gate = clamp01((rms - 0.0008f) * 400.0f);
    float bass = out[0] * gate;
    float mid = out[1] * gate;
    float treble = out[2] * gate;
    float volume = clamp01(rms / fmaxf(d->vpeak, 1e-5f)) * gate;

    // Spectrum bars. A shared gain plus a gentle upward tilt: raw magnitudes
    // follow music's 1/f slope, so without the tilt everything above a few kHz
    // is a flat line. Per-bar gain was tried and looks like noise - quiet high
    // bars get slammed to full.
    float bar_raw[MAXBARS];
    float bar_loud = 0.0f;
    for (int i = 0; i < d->bars; i++) {
        int b0 = d->bar_bin[i], b1 = d->bar_bin[i + 1];
        if (b1 <= b0) b1 = b0 + 1;
        float sum = 0.0f;
        for (int k = b0; k < b1 && k < FFT_N / 2; k++)
            sum += sqrtf(re[k] * re[k] + im[k] * im[k]);
        float mag = sum / (float)(b1 - b0);
        float centre = (float)(b0 + b1) * 0.5f * rate / (float)FFT_N;
        bar_raw[i] = mag * powf(centre / 120.0f, 0.45f);
        bar_loud = fmaxf(bar_loud, bar_raw[i]);
    }
    d->bar_peak = fmaxf(bar_loud, d->bar_peak * d->gain_release);
    float bar_gain = fmaxf(d->bar_peak, 1e-5f);
    for (int i = 0; i < d->bars; i++) {
        float v = clamp01(bar_raw[i] / bar_gain) * gate;
        // Instant attack, gentle fall - keeps transients immediate while
        // stopping the bars from strobing between frames.
        d->bar_val[i] = v > d->bar_val[i] ? v : fmaxf(v, d->bar_val[i] - d->bar_decay);
    }

    double t = now_seconds();

    // Beat: bass well above its own recent average. Done here rather than in
    // QML so the pulse reaches the shader on the very next frame.
    float mean = 0.0f;
    for (int i = 0; i < HIST; i++)
        mean += d->bass_hist[i];
    mean /= (float)HIST;
    d->bass_hist[d->hist_pos] = bass;
    d->hist_pos = (d->hist_pos + 1) % HIST;

    // Hysteresis: bass has to fall back near its average before another beat
    // can fire. Without it a single kick's decay tail crosses the threshold
    // again a few hops later and every beat lands twice.
    if (bass < mean * 1.10f)
        d->armed = true;

    bool fired = false;
    if (d->armed && bass > d->beat_floor && bass > mean * d->beat_sensitivity + 0.05f
            && (t - d->last_beat) > d->beat_min_gap) {
        d->last_beat = t;
        d->beat = 1.0f;
        d->armed = false;
        fired = true;
    } else {
        double dt = t - d->last_emit;
        if (dt > 0 && d->beat_decay > 0)
            d->beat = fmaxf(0.0f, d->beat - (float)(dt / d->beat_decay));
    }

    // Rate-limit output, but never delay a beat.
    if (!fired && (t - d->last_emit) < d->emit_interval)
        return;
    d->last_emit = t;

    char line[16 + MAXBARS * 6];
    int n = snprintf(line, sizeof(line), "%.3f %.3f %.3f %.3f %.3f",
        bass, mid, treble, volume, d->beat);
    for (int i = 0; i < d->bars && n < (int)sizeof(line) - 8; i++)
        n += snprintf(line + n, sizeof(line) - n, " %.3f", d->bar_val[i]);
    puts(line);
    fflush(stdout);
}

static void on_process(void *userdata)
{
    struct data *d = userdata;
    struct pw_buffer *b = pw_stream_dequeue_buffer(d->stream);
    if (!b)
        return;

    struct spa_buffer *buf = b->buffer;
    float *samples = buf->datas[0].data;
    if (samples && d->format.channels > 0) {
        uint32_t stride = sizeof(float) * d->format.channels;
        uint32_t n = buf->datas[0].chunk->size / stride;
        for (uint32_t i = 0; i < n; i++) {
            float mono = 0.0f;
            for (uint32_t c = 0; c < d->format.channels; c++)
                mono += samples[i * d->format.channels + c];
            mono /= (float)d->format.channels;

            d->ring[d->ring_pos] = mono;
            d->ring_pos = (d->ring_pos + 1) % FFT_N;
            if (++d->since_hop >= HOP) {
                d->since_hop = 0;
                analyse(d);
            }
        }
    }
    pw_stream_queue_buffer(d->stream, b);
}

static void on_param_changed(void *userdata, uint32_t id, const struct spa_pod *param)
{
    struct data *d = userdata;
    if (!param || id != SPA_PARAM_Format)
        return;
    struct spa_audio_info info = { 0 };
    if (spa_format_parse(param, &info.media_type, &info.media_subtype) < 0)
        return;
    if (info.media_type != SPA_MEDIA_TYPE_audio || info.media_subtype != SPA_MEDIA_SUBTYPE_raw)
        return;
    if (spa_format_audio_raw_parse(param, &info.info.raw) < 0)
        return;
    d->format = info.info.raw;
    if (d->verbose)
        fprintf(stderr, "[qs-audiotap] format: %u ch @ %u Hz\n", d->format.channels, d->format.rate);
}

static const struct pw_stream_events stream_events = {
    PW_VERSION_STREAM_EVENTS,
    .param_changed = on_param_changed,
    .process = on_process,
};

// (Re)build the capture stream against the currently chosen target.
static void connect_stream(struct data *d)
{
    if (d->stream) {
        spa_hook_remove(&d->stream_listener);
        pw_stream_destroy(d->stream);
        d->stream = NULL;
    }

    char target[32];
    struct pw_properties *props = pw_properties_new(
        PW_KEY_MEDIA_TYPE, "Audio",
        PW_KEY_MEDIA_CATEGORY, "Capture",
        PW_KEY_MEDIA_ROLE, "Music",
        PW_KEY_NODE_NAME, "qs-audiotap",
        // Ask for a small quantum; this is the main latency knob on our side.
        PW_KEY_NODE_LATENCY, "256/48000",
        NULL);

    if (d->target_serial != 0) {
        // An application's own output stream node.
        snprintf(target, sizeof(target), "%u", d->target_serial);
        pw_properties_set(props, PW_KEY_TARGET_OBJECT, target);
    } else {
        // Anything that is not an app stream and not the microphone has to say
        // so explicitly: a Capture stream attaches to the default *input*
        // otherwise, which is how this ended up listening to the mic.
        if (!d->mic)
            pw_properties_set(props, PW_KEY_STREAM_CAPTURE_SINK, "true");

        if (d->source_name) {
            // The Settings pickers store PulseAudio-compatibility source names
            // like "alsa_output.<card>.analog-stereo.monitor". A sink's monitor
            // is not a separate node in PipeWire - it is the sink node's monitor
            // ports - so target.object has to name the sink itself. Left as-is
            // the target matched nothing and autoconnect fell back to the mic.
            const char *suffix = strstr(d->source_name, ".monitor");
            if (!d->mic && suffix && suffix[8] == '\0') {
                char sink[256];
                size_t len = (size_t)(suffix - d->source_name);
                if (len >= sizeof(sink))
                    len = sizeof(sink) - 1;
                memcpy(sink, d->source_name, len);
                sink[len] = '\0';
                pw_properties_set(props, PW_KEY_TARGET_OBJECT, sink);
            } else {
                pw_properties_set(props, PW_KEY_TARGET_OBJECT, d->source_name);
            }
        }
    }

    d->stream = pw_stream_new(d->core, "qs-audiotap", props);
    pw_stream_add_listener(d->stream, &d->stream_listener, &stream_events, d);

    uint8_t buffer[1024];
    struct spa_pod_builder bldr = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
    struct spa_audio_info_raw raw = { .format = SPA_AUDIO_FORMAT_F32 };
    const struct spa_pod *params[1];
    params[0] = spa_format_audio_raw_build(&bldr, SPA_PARAM_EnumFormat, &raw);

    pw_stream_connect(d->stream, PW_DIRECTION_INPUT, PW_ID_ANY,
        PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS, params, 1);

    d->attached_serial = d->target_serial;
    d->attached_id = d->target_id;
    if (d->verbose)
        fprintf(stderr, "[qs-audiotap] capturing %s\n",
            d->target_serial ? "application stream"
                : d->source_name ? d->source_name
                : (d->mic ? "default input" : "default sink monitor"));
}

static bool contains_ci(const char *haystack, const char *needle)
{
    return haystack && needle && strcasestr(haystack, needle) != NULL;
}

static void on_registry_global(void *userdata, uint32_t id, uint32_t permissions,
    const char *type, uint32_t version, const struct spa_dict *props)
{
    (void)permissions; (void)version;
    struct data *d = userdata;
    if (!d->app_filter || !props || strcmp(type, PW_TYPE_INTERFACE_Node) != 0)
        return;

    const char *media_class = spa_dict_lookup(props, PW_KEY_MEDIA_CLASS);
    if (!media_class || strcmp(media_class, "Stream/Output/Audio") != 0)
        return;

    // Match generously: MPRIS identities and PipeWire node names rarely agree
    // exactly ("Spotify" vs "spotify"), so any of these containing the filter
    // as a substring counts.
    const char *app = spa_dict_lookup(props, PW_KEY_APP_NAME);
    const char *node = spa_dict_lookup(props, PW_KEY_NODE_NAME);
    const char *desc = spa_dict_lookup(props, PW_KEY_NODE_DESCRIPTION);
    const char *binary = spa_dict_lookup(props, PW_KEY_APP_PROCESS_BINARY);
    if (!(contains_ci(app, d->app_filter) || contains_ci(node, d->app_filter)
            || contains_ci(desc, d->app_filter) || contains_ci(binary, d->app_filter)))
        return;

    const char *serial = spa_dict_lookup(props, PW_KEY_OBJECT_SERIAL);
    if (!serial)
        return;
    uint32_t s = (uint32_t)strtoul(serial, NULL, 10);
    if (s == d->attached_serial || s == d->target_serial)
        return;

    if (d->verbose)
        fprintf(stderr, "[qs-audiotap] found '%s' (serial %u)\n", app ? app : node, s);
    d->target_serial = s;
    d->target_id = id;
    d->reconnect_pending = true;
}

static void on_registry_global_remove(void *userdata, uint32_t id)
{
    struct data *d = userdata;
    // Only fall back when the exact node we attached to disappears. Reacting to
    // any removal meant our own reconnect churn - ports of the previous stream
    // going away - immediately knocked us back to the sink monitor, so an app
    // target never survived more than a moment.
    if (d->app_filter && d->attached_id != 0 && id == d->attached_id) {
        if (d->verbose)
            fprintf(stderr, "[qs-audiotap] target went away, back to sink monitor\n");
        d->target_serial = 0;
        d->target_id = 0;
        d->reconnect_pending = true;
    }
}

static const struct pw_registry_events registry_events = {
    PW_VERSION_REGISTRY_EVENTS,
    .global = on_registry_global,
    .global_remove = on_registry_global_remove,
};

// Reconnects happen on a timer rather than inside the registry callback, so a
// burst of registry events collapses into a single reconnect.
static void on_reconnect_timer(void *userdata, uint64_t expirations)
{
    (void)expirations;
    struct data *d = userdata;
    if (d->reconnect_pending) {
        d->reconnect_pending = false;
        connect_stream(d);
    }
}

static void usage(const char *argv0)
{
    fprintf(stderr,
        "usage: %s [--app NAME] [--rate HZ] [--beat-decay S] [--beat-gap S] [-v]\n"
        "  --app NAME     capture only this application's stream (substring, case-insensitive)\n"
        "                 omit to capture everything the speakers play\n"
        "  --bars N       spectrum bars appended to each line (default 50)\n"
        "  --range LO HI  spectrum range in Hz (default 50 16000)\n"
        "  --bar-decay F  spectrum fall per hop, 0..1 (default 0.035)\n"
        "  --rate HZ      maximum output lines per second (default 90; beats bypass this)\n"
        "  --beat-decay S beat envelope fall time in seconds (default 0.10)\n"
        "  --beat-gap S   minimum seconds between beats (default 0.11)\n"
        "  --beat-sensitivity F  bass must exceed its average by this factor (default 1.35)\n"
        "  --beat-floor F        bass below this never counts as a beat (default 0.15)\n"
        "  --gain-release F      auto gain release per hop, 0..1 (default 0.9995)\n"
        "  --source NAME  capture this PipeWire node by name (\"auto\" = default)\n"
        "  --mic          capture the default input (microphone) instead\n"
        "  -v             log target/format changes to stderr\n",
        argv0);
}

int main(int argc, char **argv)
{
    struct data *d = &g_data;
    memset(d, 0, sizeof(*d));
    d->armed = true;
    d->emit_interval = 1.0 / 90.0;
    d->beat_decay = 0.10;
    d->beat_min_gap = 0.11;
    d->bars = 50;
    d->bar_lo_hz = 50.0f;
    d->bar_hi_hz = 16000.0f;
    d->bar_decay = 0.035f;
    d->beat_sensitivity = 1.35f;
    d->beat_floor = 0.15f;
    d->gain_release = 0.9995f;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--app") && i + 1 < argc) {
            d->app_filter = argv[++i];
            if (d->app_filter[0] == '\0')
                d->app_filter = NULL;
        } else if (!strcmp(argv[i], "--rate") && i + 1 < argc) {
            double hz = atof(argv[++i]);
            if (hz > 0) d->emit_interval = 1.0 / hz;
        } else if (!strcmp(argv[i], "--beat-decay") && i + 1 < argc) {
            d->beat_decay = atof(argv[++i]);
        } else if (!strcmp(argv[i], "--beat-gap") && i + 1 < argc) {
            d->beat_min_gap = atof(argv[++i]);
        } else if (!strcmp(argv[i], "--bars") && i + 1 < argc) {
            d->bars = atoi(argv[++i]);
            if (d->bars < 1) d->bars = 1;
            if (d->bars > MAXBARS) d->bars = MAXBARS;
        } else if (!strcmp(argv[i], "--range") && i + 2 < argc) {
            d->bar_lo_hz = (float)atof(argv[++i]);
            d->bar_hi_hz = (float)atof(argv[++i]);
        } else if (!strcmp(argv[i], "--bar-decay") && i + 1 < argc) {
            d->bar_decay = (float)atof(argv[++i]);
        } else if (!strcmp(argv[i], "--source") && i + 1 < argc) {
            d->source_name = argv[++i];
            if (d->source_name[0] == '\0' || !strcmp(d->source_name, "auto"))
                d->source_name = NULL;
        } else if (!strcmp(argv[i], "--beat-sensitivity") && i + 1 < argc) {
            d->beat_sensitivity = (float)atof(argv[++i]);
        } else if (!strcmp(argv[i], "--beat-floor") && i + 1 < argc) {
            d->beat_floor = (float)atof(argv[++i]);
        } else if (!strcmp(argv[i], "--gain-release") && i + 1 < argc) {
            d->gain_release = (float)atof(argv[++i]);
        } else if (!strcmp(argv[i], "--mic")) {
            d->mic = true;
        } else if (!strcmp(argv[i], "-v")) {
            d->verbose = true;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    for (int i = 0; i < FFT_N; i++)
        d->window[i] = 0.5f - 0.5f * cosf(2.0f * (float)M_PI * (float)i / (float)(FFT_N - 1));

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    pw_init(&argc, &argv);

    d->loop = pw_main_loop_new(NULL);
    if (!d->loop) {
        fprintf(stderr, "[qs-audiotap] cannot create main loop\n");
        return 1;
    }
    d->context = pw_context_new(pw_main_loop_get_loop(d->loop), NULL, 0);
    d->core = pw_context_connect(d->context, NULL, 0);
    if (!d->core) {
        fprintf(stderr, "[qs-audiotap] cannot connect to PipeWire\n");
        return 1;
    }

    if (d->app_filter) {
        d->registry = pw_core_get_registry(d->core, PW_VERSION_REGISTRY, 0);
        pw_registry_add_listener(d->registry, &d->registry_listener, &registry_events, d);
    }

    connect_stream(d);

    struct spa_source *timer = pw_loop_add_timer(pw_main_loop_get_loop(d->loop), on_reconnect_timer, d);
    struct timespec value = { .tv_sec = 0, .tv_nsec = 250000000 };
    struct timespec interval = { .tv_sec = 0, .tv_nsec = 250000000 };
    pw_loop_update_timer(pw_main_loop_get_loop(d->loop), timer, &value, &interval, false);

    pw_main_loop_run(d->loop);

    if (d->stream)
        pw_stream_destroy(d->stream);
    if (d->registry)
        pw_proxy_destroy((struct pw_proxy *)d->registry);
    pw_core_disconnect(d->core);
    pw_context_destroy(d->context);
    pw_main_loop_destroy(d->loop);
    pw_deinit();
    return 0;
}
