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
    pactl list sources short 2>/dev/null | awk '$2 ~ /monitor/ { print $2; exit }'
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
SYSTEM_AUDIO_FLAG=0
MIC_AUDIO_FLAG=0
COPY_AFTER_FLAG=0
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
    elif [[ "${ARGS[i]}" == "--sound" || "${ARGS[i]}" == "--system-audio" ]]; then
        SYSTEM_AUDIO_FLAG=1
    elif [[ "${ARGS[i]}" == "--mic" ]]; then
        MIC_AUDIO_FLAG=1
    elif [[ "${ARGS[i]}" == "--copy-after" ]]; then
        COPY_AFTER_FLAG=1
    fi
done

build_audio_args

if pgrep wf-recorder > /dev/null; then
    notify-send "Recording Stopped" "Stopped" -a 'Recorder' &
    pkill wf-recorder &
    set_recording_state false
else
    output_name="recording_$(getdate).mp4"
    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        show_recording_started_notification "$output_name"
        set_recording_state true
        wf-recorder -o "$(getactivemonitor)" --pixel-format yuv420p -f "./$output_name" -t "${AUDIO_ARGS[@]}"
    else
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                exit 1
            fi
        fi
        show_recording_started_notification "$output_name"
        set_recording_state true
        wf-recorder --pixel-format yuv420p -f "./$output_name" -t --geometry "$region" "${AUDIO_ARGS[@]}"
    fi
    if [[ $COPY_AFTER_FLAG -eq 1 ]]; then
        record_uri="file://$RECORDING_DIR/$output_name"
        printf '%s\n' "${record_uri// /%20}" | wl-copy --type text/uri-list
    fi
    set_recording_state false
fi