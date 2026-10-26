#!/bin/sh
# Compile the project-owned square master into all standard macOS icon sizes.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
destination=${1:?Usage: scripts/build-icon.sh resources-directory}
icon_work=$(mktemp -d "${TMPDIR:-/tmp}/codexjet-icon.XXXXXX")
trap 'rm -rf "$icon_work"' EXIT HUP INT TERM
icon_set="$icon_work/AppIcon.iconset"
mkdir -p "$icon_set" "$destination"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$project_root/assets/brand/app-icon.png" --out "$icon_set/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$project_root/assets/brand/app-icon.png" --out "$icon_set/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_set" -o "$destination/AppIcon.icns"
