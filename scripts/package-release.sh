#!/bin/bash
set -euo pipefail
project_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$project_root"
app='dist/Codex Jet.app'
codesign --verify --deep --strict "$app"
xcrun lipo "$app/Contents/MacOS/CodexReset" -verify_arch arm64 x86_64
archive='CodexJet-macOS-universal.zip'
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/$archive"
(cd dist && shasum -a 256 "$archive" > SHA256SUMS)
printf '%s\n' "dist/$archive" 'dist/SHA256SUMS'
