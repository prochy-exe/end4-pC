#!/usr/bin/env bash

set -o pipefail
shopt -s nullglob

devices=(/dev/input/by-id/*event-kbd /dev/input/by-id/*event-mouse)
if (( ${#devices[@]} == 0 )); then
    exit 0
fi

declare -A pressed=()

format_key() {
    local key="$1"
    case "$key" in
        KEY_SPACE) printf 'Space' ;;
        KEY_ENTER|KEY_KPENTER) printf 'Enter' ;;
        KEY_ESC) printf 'Esc' ;;
        KEY_BACKSPACE) printf 'Backspace' ;;
        KEY_TAB) printf 'Tab' ;;
        KEY_DELETE) printf 'Delete' ;;
        KEY_LEFT) printf 'Left' ;;
        KEY_RIGHT) printf 'Right' ;;
        KEY_UP) printf 'Up' ;;
        KEY_DOWN) printf 'Down' ;;
        BTN_LEFT) printf 'Mouse 1' ;;
        BTN_RIGHT) printf 'Mouse 2' ;;
        BTN_MIDDLE) printf 'Mouse 3' ;;
        BTN_SIDE) printf 'Mouse 4' ;;
        BTN_EXTRA) printf 'Mouse 5' ;;
        KEY_*) printf '%s' "${key#KEY_}" | tr '_' ' ' ;;
        *) return 1 ;;
    esac
}

active_modifiers() {
    local prefix=""
    (( ${pressed[KEY_LEFTCTRL]:-0} > 0 || ${pressed[KEY_RIGHTCTRL]:-0} > 0 )) && prefix+="Ctrl + "
    (( ${pressed[KEY_LEFTALT]:-0} > 0 || ${pressed[KEY_RIGHTALT]:-0} > 0 )) && prefix+="Alt + "
    (( ${pressed[KEY_LEFTSHIFT]:-0} > 0 || ${pressed[KEY_RIGHTSHIFT]:-0} > 0 )) && prefix+="Shift + "
    (( ${pressed[KEY_LEFTMETA]:-0} > 0 || ${pressed[KEY_RIGHTMETA]:-0} > 0 )) && prefix+="Super + "
    printf '%s' "${prefix% + }"
}

{
    for device in "${devices[@]}"; do
        [[ -r "$device" ]] && stdbuf -oL -eL evtest "$device" 2>/dev/null &
    done
    wait
} | while IFS= read -r line; do
    [[ $line =~ code[[:space:]]+[0-9]+[[:space:]]+\((KEY_[A-Z0-9_]+|BTN_[A-Z0-9_]+)\),[[:space:]]+value[[:space:]]+([0-9]+) ]] || continue
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"

    case "$key" in
        KEY_LEFTCTRL|KEY_RIGHTCTRL|KEY_LEFTALT|KEY_RIGHTALT|KEY_LEFTSHIFT|KEY_RIGHTSHIFT|KEY_LEFTMETA|KEY_RIGHTMETA)
            pressed[$key]="$value"
            if (( value > 0 )); then
                active_modifiers
                printf '\n'
            fi
            continue
            ;;
    esac

    (( value > 0 )) || continue
    label="$(format_key "$key")" || continue
    prefix="$(active_modifiers)"
    [[ -n "$prefix" ]] && prefix+=" + "
    printf '%s%s\n' "$prefix" "$label"
done
