#!/usr/bin/env bash
CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
JSON_PATH=".screenRecord.savePath"
CUSTOM_PATH=$(jq -r "$JSON_PATH" "$CONFIG_FILE" 2>/dev/null)
RECORDING_DIR=""
if [[ -n "$CUSTOM_PATH" ]]; then
    RECORDING_DIR="$CUSTOM_PATH"
else
    RECORDING_DIR="$HOME/Videos"
fi

RECORD_FPS=$(jq -r '.screenRecord.frameRate // 30' "$CONFIG_FILE" 2>/dev/null)
[[ "$RECORD_FPS" =~ ^[0-9]+$ && "$RECORD_FPS" -gt 0 ]] || RECORD_FPS=30

USE_RECORDING_INDICATOR=$(jq -r '(
    (.bar.utilButtons.showScreenRecordingIndicator // false)
    or ((.bar.utilButtons.order // []) | any(. == "recordingIndicator"))
    or ((.bar.monitorSettings // []) | any(
        (.values.utilButtons.showScreenRecordingIndicator == true)
        or ((.values.utilButtons.order // []) | any(. == "recordingIndicator"))
    ))
)' "$CONFIG_FILE" 2>/dev/null)

set_recording_state() {
    local state=$1
    local STATE_FILE="$HOME/.local/state/quickshell/states.json"
    local tmp=$(mktemp)
    jq ".record.enable = $state" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}

get_system_audio_source() {
    local sink
    sink=$(pactl get-default-sink 2>/dev/null)

    pactl list sources short 2>/dev/null |
        awk -v sink="$sink" '$2 == sink ".monitor" { print $2; exit }'
}

get_mic_audio_source() {
    local default_source
    default_source="$(pactl get-default-source 2>/dev/null)"
    if [[ -n "$default_source" && "$default_source" != *monitor* ]]; then
        echo "$default_source"
        return
    fi
    pactl list sources short 2>/dev/null | awk '$2 !~ /monitor/ { print $2; exit }'
}

build_audio_args() {
    local system_source=""
    local mic_source=""

    if [[ $SYSTEM_AUDIO_FLAG -eq 1 ]]; then
        system_source="$(get_system_audio_source)"
    fi
    if [[ $MIC_AUDIO_FLAG -eq 1 ]]; then
        mic_source="$(get_mic_audio_source)"
    fi

    AUDIO_ARGS=()
    if [[ $SYSTEM_AUDIO_FLAG -eq 1 && $MIC_AUDIO_FLAG -eq 1 ]]; then
        if [[ -n "$system_source" ]]; then
            AUDIO_ARGS=(--audio="$system_source")
            if [[ -n "$mic_source" && "$mic_source" != "$system_source" ]]; then
                notify-send "Recorder" "wf-recorder can only use one audio source; using system audio" -a 'Recorder' & disown
            fi
        elif [[ -n "$mic_source" ]]; then
            AUDIO_ARGS=(--audio="$mic_source")
        fi
    elif [[ $SYSTEM_AUDIO_FLAG -eq 1 && -n "$system_source" ]]; then
        AUDIO_ARGS=(--audio="$system_source")
    elif [[ $MIC_AUDIO_FLAG -eq 1 && -n "$mic_source" ]]; then
        AUDIO_ARGS=(--audio="$mic_source")
    fi

    if [[ ($SYSTEM_AUDIO_FLAG -eq 1 || $MIC_AUDIO_FLAG -eq 1) && ${#AUDIO_ARGS[@]} -eq 0 ]]; then
        notify-send "Recorder" "Audio source not found, recording video only" -a 'Recorder' & disown
    fi
}

getactivemonitor() {
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
}

# Probes for a working GPU encoder so re-encodes don't have to burn CPU on
# libx264. Having an encoder compiled into ffmpeg doesn't mean it actually
# works at runtime (e.g. Nvidia's VAAPI shim only supports decode), so this
# does a real 0.2s throwaway encode rather than trusting `ffmpeg -encoders`.
# Sets GPU_ENCODER to nvenc/vaapi/software and, for vaapi, GPU_VAAPI_DEVICE
# to the render node that worked. Probes at CRF-28-equivalent quality since
# that's the harder (more lossy) target to get a hardware encoder to accept;
# the same encoder is reused at other quality levels once picked.
pick_gpu_encoder() {
    local probe_src=(-f lavfi -i testsrc=size=320x240:rate=30:duration=0.2)

    if command -v nvidia-smi >/dev/null 2>&1 \
        && ffmpeg -hide_banner -y "${probe_src[@]}" -c:v h264_nvenc -preset p6 -rc vbr -cq 28 -b:v 0 \
            -f null - >/dev/null 2>&1; then
        GPU_ENCODER="nvenc"
        return
    fi

    local dev
    for dev in /dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/renderD130; do
        [[ -e "$dev" ]] || continue
        if ffmpeg -hide_banner -y -vaapi_device "$dev" "${probe_src[@]}" \
            -vf 'format=nv12,hwupload' -c:v h264_vaapi -qp 28 -f null - >/dev/null 2>&1; then
            GPU_ENCODER="vaapi"
            GPU_VAAPI_DEVICE="$dev"
            return
        fi
    done

    GPU_ENCODER="software"
}

# Whether $1's average bitrate is at or under $2 (kbps). Used to catch cases
# where a GPU encoder's bitrate cap wasn't actually honored - observed in
# testing to happen intermittently with h264_nvenc/h264_vaapi on some
# content (variable-frame-rate screen captures seem to confuse their VBV/
# maxrate accounting, though not reliably reproducible enough to pin down
# further) - rather than trusting -maxrate/-bufsize blindly for something
# that's supposed to guarantee a small file.
encode_within_budget() {
    local file="$1" budget_kbps="$2"
    [[ -s "$file" ]] || return 1
    local size_bytes duration_s
    size_bytes=$(stat -c %s "$file" 2>/dev/null) || return 1
    duration_s=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    awk -v b="$size_bytes" -v d="$duration_s" -v budget="$budget_kbps" \
        'BEGIN { if (d+0 <= 0) exit 1; exit !((b*8/1000)/d <= budget) }'
}

# Lets the user know a recording ended up eating CPU instead of GPU time, so
# it's visible when it happens rather than a silent surprise.
notify_gpu_fallback() {
    local reason="$1"
    notify-send "Recorder" "GPU encode $reason - redid it in software (uses more CPU)" -a 'Recorder' & disown
}

# Re-encodes a raw capture, preferring a GPU encoder (much lighter on CPU)
# with a software libx264 fallback. h264 (not h265/vp9) for broad
# compatibility. quality is a CRF (software) / CQ (nvenc) / QP (vaapi) value
# - lower means higher quality and bigger file; the software path also gets
# a slow preset for better compression at the same CRF, which is fine since
# this runs after recording stops rather than in real time (GPU presets
# don't have an equivalent slow/fast tradeoff, so they just get a fixed
# quality setting). small_audio compresses audio down for sharing; leave it
# unset to keep audio at its default quality.
social_reencode() {
    local src="$1" dst="$2" quality="$3" small_audio="$4"
    pick_gpu_encoder

    local -a audio_args=() nvenc_cap_args=() vaapi_rc_args=()
    if [[ "$small_audio" == "1" ]]; then
        audio_args=(-c:a aac -b:a 128k -movflags +faststart)
        # NVENC's CQ mode has no bitrate ceiling by itself (unlike x264's
        # CRF) - for busy/high-motion content it happily spends 20+ Mbps to
        # hit the quality target, which defeats the entire point of social
        # mode. Cap it explicitly. Same story for VAAPI's default constant-QP
        # mode, so switch it to VBR with an explicit cap too.
        nvenc_cap_args=(-maxrate 6M -bufsize 12M)
        vaapi_rc_args=(-rc_mode VBR -maxrate 6M -bufsize 12M)
    fi

    case "$GPU_ENCODER" in
        nvenc)
            ffmpeg -y -i "$src" -c:v h264_nvenc -preset p6 -rc vbr -cq "$quality" -b:v 0 \
                "${nvenc_cap_args[@]}" -pix_fmt yuv420p "${audio_args[@]}" "$dst" >/dev/null 2>&1
            ;;
        vaapi)
            ffmpeg -y -vaapi_device "$GPU_VAAPI_DEVICE" -i "$src" \
                -vf 'format=nv12,hwupload' -c:v h264_vaapi -qp "$quality" \
                "${vaapi_rc_args[@]}" "${audio_args[@]}" "$dst" >/dev/null 2>&1
            ;;
        *)
            ffmpeg -y -i "$src" -c:v libx264 -preset slow -crf "$quality" -pix_fmt yuv420p \
                "${audio_args[@]}" "$dst" >/dev/null 2>&1
            ;;
    esac

    # GPU encode can fail mid-run on some driver setups even after the probe
    # passed, or (see encode_within_budget above) land way over budget
    # despite the cap - either way, redo in software rather than losing the
    # recording or shipping an oversized "social" file.
    local fallback_reason=""
    if [[ "$GPU_ENCODER" != "software" ]]; then
        if [[ ! -s "$dst" ]]; then
            fallback_reason="failed"
        elif [[ "$small_audio" == "1" ]] && ! encode_within_budget "$dst" 9000; then
            fallback_reason="went over the size budget"
        fi
    fi

    if [[ -n "$fallback_reason" ]]; then
        notify_gpu_fallback "$fallback_reason"
        ffmpeg -y -i "$src" -c:v libx264 -preset slow -crf "$quality" -pix_fmt yuv420p \
            "${audio_args[@]}" "$dst" >/dev/null 2>&1
    elif [[ ! -s "$dst" ]]; then
        ffmpeg -y -i "$src" -c:v libx264 -preset slow -crf "$quality" -pix_fmt yuv420p \
            "${audio_args[@]}" "$dst" >/dev/null 2>&1
    fi

    rm -f "$src"
}

# Records every monitor separately (wf-recorder can't span multiple outputs
# in one --geometry capture - confirmed it errors with "Failed to detect
# output based on geometry" when given a region crossing output boundaries),
# then packs them into one row afterward, left to right by real x position,
# with no vertical offset between them - deliberately NOT placing each at
# its real y position, since that leaves black bars wherever monitors don't
# share the same y-range, which is the "looks terrible" result being
# avoided here.
record_all_monitors() {
    local output_name="$1"
    local monitors_json
    monitors_json="$(hyprctl monitors -j)"

    local max_h
    max_h=$(jq '[.[].height] | max' <<< "$monitors_json")

    local tmp_dir
    tmp_dir="$(mktemp -d)"

    # Constant frame rate - see the fullscreen/region raw capture comments
    # below for why. Always applied here regardless of social mode, since
    # this always feeds a re-encode (the hstack merge) either way.
    local -a cfr_args=(-r "$RECORD_FPS")

    local -a tmp_files pids
    local first=1
    while IFS=$'\t' read -r name; do
        local tmp_file="$tmp_dir/$name.mp4"
        tmp_files+=("$tmp_file")
        if [[ $first -eq 1 ]]; then
            wf-recorder -o "$name" --pixel-format yuv420p -f "$tmp_file" -t "${cfr_args[@]}" "${AUDIO_ARGS[@]}" &
            first=0
        else
            wf-recorder -o "$name" --pixel-format yuv420p -f "$tmp_file" -t "${cfr_args[@]}" &
        fi
        pids+=("$!")
    done < <(jq -r 'sort_by(.x) | .[].name' <<< "$monitors_json")

    set_recording_state true
    wait "${pids[@]}"

    # Duration of the actual recording, used as an explicit -t cutoff below.
    # Not relying on -shortest here: with -filter_complex the encode can
    # keep running past when the real streams end, since ffmpeg's EOF-driven
    # -shortest doesn't always trigger cleanly against a filter graph.
    local duration
    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${tmp_files[0]}")

    # Scale each to the same height first - hstack requires matching
    # heights, and this is a no-op when they already match (the common
    # case) but keeps things working if a monitor's resolution differs.
    local -a ffmpeg_inputs=()
    local filter="" scaled=""
    local i
    for i in "${!tmp_files[@]}"; do
        ffmpeg_inputs+=(-i "${tmp_files[$i]}")
        filter+="[$i:v]scale=-2:${max_h}[s$i];"
        scaled+="[s$i]"
    done
    # No output label yet - run_hstack_encode below appends the label (and,
    # for vaapi, a hwupload stage) itself, since that part depends on which
    # encoder ends up being used.
    local hstack_filter="${filter}${scaled}hstack=inputs=${#tmp_files[@]}"

    # Social mode trades quality for the smallest file (CRF/CQ/QP 28, and a
    # slow x264 preset when falling back to software since that's not
    # time-constrained here); the default path keeps the original near-
    # lossless, fast target instead - GPU encoding only changes how that
    # target is hit, not what the target is.
    local quality x264_preset small_audio
    if [[ $SOCIAL_FLAG -eq 1 ]]; then
        quality=28; x264_preset="slow"; small_audio=1
    else
        quality=18; x264_preset="veryfast"; small_audio=0
    fi

    pick_gpu_encoder
    run_hstack_encode "$GPU_ENCODER" "$output_name" "$duration" "$hstack_filter" ffmpeg_inputs "$quality" "$x264_preset" "$small_audio"
    # Same story as social_reencode's fallback: redo in software if the GPU
    # encode failed outright, or (social tier only) came in way over budget
    # despite the cap.
    local fallback_reason=""
    if [[ "$GPU_ENCODER" != "software" ]]; then
        if [[ ! -s "./$output_name" ]]; then
            fallback_reason="failed"
        elif [[ "$small_audio" == "1" ]] && ! encode_within_budget "./$output_name" 9000; then
            fallback_reason="went over the size budget"
        fi
    fi
    if [[ -n "$fallback_reason" ]]; then
        notify_gpu_fallback "$fallback_reason"
        run_hstack_encode "software" "$output_name" "$duration" "$hstack_filter" ffmpeg_inputs "$quality" "$x264_preset" "$small_audio"
    fi

    rm -rf "$tmp_dir"
}

# Runs the scale+hstack ffmpeg encode for record_all_monitors with the given
# encoder (nvenc/vaapi/software, see pick_gpu_encoder). quality is a CRF
# (software) / CQ (nvenc) / QP (vaapi) value; x264_preset only affects the
# software path. small_audio compresses audio down for sharing; 0 keeps
# audio at its default quality. Takes the ffmpeg_inputs array by name since
# bash can't pass arrays by value.
run_hstack_encode() {
    local mode="$1" output_name="$2" duration="$3" hstack_filter="$4"
    local -n inputs_ref="$5"
    local quality="$6" x264_preset="$7" small_audio="$8"
    local -a global_args=() encode_args=() pixfmt_args=() audio_args=()
    local vfilter="${hstack_filter}[v]"

    case "$mode" in
        nvenc)
            encode_args=(-c:v h264_nvenc -preset p6 -rc vbr -cq "$quality" -b:v 0)
            # NVENC's CQ mode has no bitrate ceiling by itself (unlike x264's
            # CRF) - for busy/high-motion content it happily spends 20+ Mbps
            # to hit the quality target, which defeats the point of social
            # mode. Cap it explicitly for that tier only.
            [[ "$small_audio" == "1" ]] && encode_args+=(-maxrate 6M -bufsize 12M)
            pixfmt_args=(-pix_fmt yuv420p)
            ;;
        vaapi)
            global_args=(-vaapi_device "$GPU_VAAPI_DEVICE")
            vfilter="${hstack_filter},format=nv12,hwupload[v]"
            encode_args=(-c:v h264_vaapi -qp "$quality")
            # Same story as nvenc above - VAAPI's default constant-QP mode
            # isn't bounded either, so switch to VBR with a cap for social.
            [[ "$small_audio" == "1" ]] && encode_args+=(-rc_mode VBR -maxrate 6M -bufsize 12M)
            ;;
        *)
            encode_args=(-c:v libx264 -preset "$x264_preset" -crf "$quality")
            pixfmt_args=(-pix_fmt yuv420p)
            ;;
    esac

    [[ "$small_audio" == "1" ]] && audio_args=(-c:a aac -b:a 128k -movflags +faststart)

    ffmpeg -y "${global_args[@]}" "${inputs_ref[@]}" -filter_complex "$vfilter" \
        -map "[v]" -map "0:a?" \
        "${encode_args[@]}" "${audio_args[@]}" "${pixfmt_args[@]}" -t "$duration" \
        "./$output_name" >/dev/null 2>&1
}

show_recording_started_notification() {
    local filename="$1"
    if notify-send --help 2>&1 | grep -q -- "--action"; then
        (
            local action
            action=$(notify-send --wait --action="stop=Stop recording" "Starting recording" "$filename" -a 'Recorder')
            if [[ "$action" == "stop" ]]; then
                pkill wf-recorder >/dev/null 2>&1
                notify-send "Recording Stopped" "Stopped" -a 'Recorder' & disown
            fi
        ) & disown
    else
        notify-send "Starting recording" "$filename" -a 'Recorder' & disown
    fi
}

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

ARGS=("$@")
MANUAL_REGION=""
FULLSCREEN_FLAG=0
ALL_MONITORS_FLAG=0
SYSTEM_AUDIO_FLAG=0
MIC_AUDIO_FLAG=0
COPY_AFTER_FLAG=0
SOCIAL_FLAG=0
for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[i]}" == "--region" ]]; then
        if (( i+1 < ${#ARGS[@]} )); then
            MANUAL_REGION="${ARGS[i+1]}"
        else
            notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' & disown
            exit 1
        fi
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    elif [[ "${ARGS[i]}" == "--all-monitors" ]]; then
        ALL_MONITORS_FLAG=1
    elif [[ "${ARGS[i]}" == "--sound" || "${ARGS[i]}" == "--system-audio" ]]; then
        SYSTEM_AUDIO_FLAG=1
    elif [[ "${ARGS[i]}" == "--mic" ]]; then
        MIC_AUDIO_FLAG=1
    elif [[ "${ARGS[i]}" == "--copy-after" ]]; then
        COPY_AFTER_FLAG=1
    elif [[ "${ARGS[i]}" == "--social" ]]; then
        SOCIAL_FLAG=1
    fi
done

build_audio_args

to_file_uri() {
    python3 - "$1" <<'PY'
import pathlib
import sys
print(pathlib.Path(sys.argv[1]).resolve().as_uri())
PY
}

if pgrep wf-recorder > /dev/null; then
    notify-send "Recording Stopped" "Stopped" -a 'Recorder' &
    pkill wf-recorder &
    set_recording_state false
else
    output_name="recording_$(getdate).mp4"
    if [[ $ALL_MONITORS_FLAG -eq 1 ]]; then
        if [[ "$USE_RECORDING_INDICATOR" != "true" ]]; then
            show_recording_started_notification "$output_name"
        fi
        record_all_monitors "$output_name"
    elif [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        if [[ "$USE_RECORDING_INDICATOR" != "true" ]]; then
            show_recording_started_notification "$output_name"
        fi
        set_recording_state true
        # Constant frame rate always, not wf-recorder's default damage-driven
        # VFR - for social mode specifically, the re-encode's GPU bitrate cap
        # relies on the VBV/leaky-bucket rate-control model, which assumes
        # roughly regular frame timing to compute its per-frame bit budget;
        # VFR's bursty timing seems to throw that off (confirmed unreliable
        # in testing). Applied to non-social recording too since variable
        # frame rate doesn't have a real upside for screen recording either
        # way.
        if [[ $SOCIAL_FLAG -eq 1 ]]; then
            raw_file="$(mktemp --suffix=.mp4)"
            wf-recorder -o "$(getactivemonitor)" --pixel-format yuv420p -f "$raw_file" -t -r "$RECORD_FPS" "${AUDIO_ARGS[@]}"
            social_reencode "$raw_file" "./$output_name" 28 1
        else
            wf-recorder -o "$(getactivemonitor)" --pixel-format yuv420p -f "./$output_name" -t -r "$RECORD_FPS" "${AUDIO_ARGS[@]}"
        fi
    else
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                exit 1
            fi
        fi
        if [[ "$USE_RECORDING_INDICATOR" != "true" ]]; then
            show_recording_started_notification "$output_name"
        fi
        set_recording_state true
        # See the fullscreen branch above for why CFR (-r) here, always.
        if [[ $SOCIAL_FLAG -eq 1 ]]; then
            raw_file="$(mktemp --suffix=.mp4)"
            wf-recorder --pixel-format yuv420p -f "$raw_file" -t -r "$RECORD_FPS" --geometry "$region" "${AUDIO_ARGS[@]}"
            social_reencode "$raw_file" "./$output_name" 28 1
        else
            wf-recorder --pixel-format yuv420p -f "./$output_name" -t -r "$RECORD_FPS" --geometry "$region" "${AUDIO_ARGS[@]}"
        fi
    fi
    if [[ $COPY_AFTER_FLAG -eq 1 ]]; then
        record_path="$RECORDING_DIR/$output_name"
        record_uri="$(to_file_uri "$record_path")"
        printf '%s\r\n' "$record_uri" | wl-copy --type text/uri-list
    fi
    set_recording_state false
fi