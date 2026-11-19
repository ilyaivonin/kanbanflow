#!/bin/bash
# Regenerates assets/AppIcon.icns from a square PNG.
# Usage: ./macos/make-icon.sh [path/to/icon.png]
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="${1:-assets/icon.png}"
OUT="assets/AppIcon.icns"
TMP="$(mktemp -d)"
ICONSET="$TMP/AppIcon.iconset"
trap 'rm -rf "$TMP"' EXIT

if [ ! -f "$SRC" ]; then
    echo "Icon source not found: $SRC" >&2
    exit 1
fi

WIDTH="$(sips -g pixelWidth "$SRC" | awk '/pixelWidth/ {print $2}')"
HEIGHT="$(sips -g pixelHeight "$SRC" | awk '/pixelHeight/ {print $2}')"
if [ "$WIDTH" != "$HEIGHT" ]; then
    echo "Icon source must be square (got ${WIDTH}x${HEIGHT})." >&2
    exit 1
fi

mkdir -p "$ICONSET"
MASTER="$TMP/icon_1024.png"
sips -s format png -z 1024 1024 "$SRC" --out "$MASTER" >/dev/null

make_size() {
    local size="$1"
    local name="$2"
    sips -s format png -z "$size" "$size" "$MASTER" --out "$ICONSET/$name" >/dev/null
}

make_size 16  "icon_16x16.png"
make_size 32  "icon_16x16@2x.png"
make_size 32  "icon_32x32.png"
make_size 64  "icon_32x32@2x.png"
make_size 128 "icon_128x128.png"
make_size 256 "icon_128x128@2x.png"
make_size 256 "icon_256x256.png"
make_size 512 "icon_256x256@2x.png"
make_size 512 "icon_512x512.png"
make_size 1024 "icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$OUT"
echo "Wrote $OUT"
