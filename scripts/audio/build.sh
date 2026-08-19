#!/usr/bin/env bash
# Builds qs-audiotap, the PipeWire capture/analysis helper used by the
# wallpaper effect. Needs pipewire headers (pipewire package on Arch).
#
# The binary lands next to this script; WallpaperAudio.qml runs it from there
# and will invoke this script once on its own if the binary is missing.
set -euo pipefail

cd "$(dirname "$0")"

if ! pkg-config --exists libpipewire-0.3; then
    echo "qs-audiotap: libpipewire-0.3 development files not found." >&2
    echo "  Arch: sudo pacman -S pipewire" >&2
    exit 1
fi

# Serialise concurrent builds (the output and input taps can both trigger one)
# and link to a temp name, then rename into place. Writing the binary directly
# makes an immediately following exec fail with ETXTBSY.
exec 9>.build.lock
flock 9

tmp="qs-audiotap.$$"
trap 'rm -f "$tmp"' EXIT
cc -O2 -Wall -Wextra -o "$tmp" qs_audiotap.c \
    $(pkg-config --cflags --libs libpipewire-0.3) -lm
mv -f "$tmp" qs-audiotap

echo "qs-audiotap: built $(pwd)/qs-audiotap"
