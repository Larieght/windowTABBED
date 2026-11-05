#!/bin/bash
# Builds Resources/AppIcon.icns from Resources/Icon/AppIcon-1024.png, the 1024 px export of
# the app icon (Figma › App Icon page › "AppIcon 1024 (export)", design 08g).
# Usage: scripts/make-icon.sh
set -euo pipefail

cd "$(dirname "$0")/.."

SOURCE="Resources/Icon/AppIcon-1024.png"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
rm -rf "$(dirname "$ICONSET")"
echo "Built Resources/AppIcon.icns"
