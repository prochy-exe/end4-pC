#!/usr/bin/env bash
# Screenshots every monitor separately and packs them into one row, left to
# right by real x position, with no vertical offset - a bare `grim` capture
# places each monitor at its real x/y, which leaves blank space wherever
# monitors don't share the same y-range. This flushes them into one row
# instead, matching how record.sh --all-monitors handles the video case.

set -euo pipefail

COPY_TO_CLIPBOARD=1
SAVE_DIR=""
for arg in "$@"; do
    case "$arg" in
        --no-clipboard) COPY_TO_CLIPBOARD=0 ;;
        --save-dir=*) SAVE_DIR="${arg#--save-dir=}" ;;
    esac
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mapfile -t NAMES < <(hyprctl monitors -j | jq -r 'sort_by(.x) | .[].name')

FILES=()
for name in "${NAMES[@]}"; do
    file="$TMP_DIR/$name.png"
    grim -o "$name" "$file"
    FILES+=("$file")
done

MERGED="$TMP_DIR/merged.png"
magick "${FILES[@]}" +append "$MERGED"

if [[ -n "$SAVE_DIR" ]]; then
    mkdir -p "$SAVE_DIR"
    SAVE_PATH="$SAVE_DIR/screenshot-$(date '+%Y-%m-%d_%H.%M.%S').png"
    cp "$MERGED" "$SAVE_PATH"
    if [[ $COPY_TO_CLIPBOARD -eq 1 ]]; then
        wl-copy < "$SAVE_PATH"
    fi
    notify-send "Screenshot Saved" "Saved to $SAVE_PATH" -a "Screen Snip" -i "image-x-generic"
else
    wl-copy < "$MERGED"
    notify-send "Screenshot Copied" "Copied to clipboard" -a "Screen Snip" -i "image-x-generic"
fi
