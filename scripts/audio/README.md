# qs-audiotap

Audio analysis for every visualiser in the shell. **Replaces cava.**

Connects straight to PipeWire, captures either the default sink monitor, a named
node, one application's output stream, or the microphone, and prints one line per
analysis hop:

```
bass mid treble volume beat bar0 bar1 ... barN-1     (all 0..1)
```

The first five are the scalars the wallpaper shader wants; the rest is a
log-spaced spectrum over `--range` (50Hz..16kHz by default, 50 bars) for the bar
visualisers. `services/AudioLevels.qml` publishes the bars to
`GlobalStates.visualizerPoints` on the old 0..1000 scale, so the existing widgets
did not have to change.

## Why not cava

Latency. cava applies its own smoothing (`noise_reduction`), emits ascii bars
that have to be reparsed in QML, and can only be pointed at a source, not at one
application. Doing the FFT here removes the smoothing stage, the reparse, and the
QML-side attack/decay that used to sit on top of all of it.

Window is 1024 samples (21.3ms at 48kHz - the floor on band latency), hop is 256
(5.3ms), and the requested quantum is 256/48000. Beat detection runs on the raw
band energy and **bypasses output rate limiting entirely**, so a kick reaches the
shader on the next frame rather than at the next scheduled emission.

## Build

```
scripts/audio/build.sh
```

Needs `pipewire` development headers; the FFT is hand-rolled radix-2 so there is
no fftw dependency. `AudioLevels.qml` runs this automatically if the binary is
missing, so a fresh clone works without a manual step. The script links to a temp
name and renames into place - writing the binary directly makes an immediately
following `exec` fail with `ETXTBSY`.

The compiled binary is gitignored: it is per-machine.

## Choosing what to listen to

Settings → Bar → **Visualizer Audio** drives `bar.visualizer.outputSource`:

| value | behaviour |
|---|---|
| `auto` | follow whichever MPRIS player is currently playing (default) |
| `app:<name>` | pin to one application |
| `<node name>` | pin to a PipeWire device |

An explicit choice wins over the automatic follow. Whatever is chosen, if the
target cannot be resolved qs-audiotap falls back to the sink monitor rather than
going silent - or worse, to the default input.

## Lifecycle

`AudioLevels.qml` keeps the output tap running even when nothing is drawing a
visualiser (`background.effects.audio.autoStart`, on by default), so the first
beat after one appears is not lost to a process start plus a PipeWire connect.
It costs ~0.6% of one core and ~7MB. While nothing is on screen the QML side
skips publishing, so no bindings fire for a viewer that does not exist; the next
line lands within ~11ms of a consumer appearing.

The **microphone tap is never auto-started** - it only runs while an input
visualiser is actually on screen.

## Options

| flag | meaning |
|---|---|
| `--app NAME` | capture only this application's stream (substring, case-insensitive); follows it across restarts via the PipeWire registry |

| `--source NAME` | capture a PipeWire node by name (what the Settings source pickers store) |
| `--mic` | capture the default input instead of the speakers |
| `--bars N` | spectrum bars per line (default 50) |
| `--range LO HI` | spectrum range in Hz (default 50 16000) |
| `--bar-decay F` | spectrum fall per hop (default 0.035) |
| `--rate HZ` | max output lines per second (default 90; beats bypass this) |
| `--beat-decay S` | beat envelope fall time (default 0.10) |
| `--beat-gap S` | minimum seconds between beats (default 0.11) |
| `--beat-sensitivity F` | bass must exceed its running average by this factor (default 1.35) |
| `--beat-floor F` | bass below this never counts as a beat (default 0.15) |
| `--gain-release F` | auto gain release per hop (default 0.9995) |
| `-v` | log target/format changes to stderr |

## Notes

- Auto gain is **per band**, not shared. Music carries far more energy at low
  frequencies, so one shared reference gets pinned by the bass and leaves treble
  stuck near zero. The spectrum bars do use a shared gain plus a frequency tilt,
  because per-bar gain there looks like noise.
- A sink's monitor is **not a separate node** in PipeWire; `alsa_output.….monitor`
  is a PulseAudio-compatibility source name. `target.object` has to name the sink
  itself, with `stream.capture.sink=true` alongside. Passing the `.monitor` name
  straight through matched nothing, and a Capture stream with no target
  autoconnects to the default *input* - which is how this ended up analysing the
  microphone instead of the speakers.
- `global_remove` must match the exact registry id of the node we attached to.
  Reacting to any removal meant our own reconnect churn knocked the app target
  back to the sink monitor immediately.
- Beat detection has re-arm hysteresis: bass must fall back near its running
  average before another beat can fire. Without it a single kick's decay tail
  crosses the threshold again and every beat lands twice.
