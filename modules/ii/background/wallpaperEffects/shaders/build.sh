#!/usr/bin/env bash
# Recompiles the wallpaper effect shaders. Run after editing any .frag here.
# Needs qt6-shadertools (provides qsb).
set -euo pipefail

cd "$(dirname "$0")"

QSB="$(command -v qsb || echo /usr/lib/qt6/bin/qsb)"
if [ ! -x "$QSB" ]; then
    echo "qsb not found - install qt6-shadertools" >&2
    exit 1
fi

for frag in *.frag; do
    echo "==> $frag"
    "$QSB" --glsl "100 es,120,150" --hlsl 50 --msl 12 -O -o "$frag.qsb" "$frag"
done
