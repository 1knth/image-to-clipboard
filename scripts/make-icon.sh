#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/Clippy.iconset
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/Clippy.png --out "build/Clippy.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Resources/Clippy.png --out "build/Clippy.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/Clippy.iconset -o Resources/Clippy.icns
