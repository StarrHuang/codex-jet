#!/bin/zsh
set -euo pipefail
project_root=${0:A:h:h}
cd "$project_root"
app_version=$(tr -d '\n' < VERSION)
[[ "$app_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'VERSION must be a numeric x.y.z version'; exit 1; }
case "${1:-}" in
  --universal)
    swift build -c release --scratch-path .build/universal-arm64 --triple arm64-apple-macosx14.0
    arm_bin=$(swift build -c release --scratch-path .build/universal-arm64 --triple arm64-apple-macosx14.0 --show-bin-path)
    swift build -c release --scratch-path .build/universal-x86_64 --triple x86_64-apple-macosx14.0
    intel_bin=$(swift build -c release --scratch-path .build/universal-x86_64 --triple x86_64-apple-macosx14.0 --show-bin-path)
    ;;
  '')
    swift build -c release
    native_bin=$(swift build -c release --show-bin-path)
    ;;
  *) print -u2 'Usage: scripts/build-app.sh [--universal]'; exit 1 ;;
esac
app_path="$project_root/dist/Codex Jet.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
if [[ "${1:-}" == --universal ]]; then
  xcrun lipo -create "$arm_bin/ResetApp" "$intel_bin/ResetApp" -output "$app_path/Contents/MacOS/CodexReset"
else
  cp "$native_bin/ResetApp" "$app_path/Contents/MacOS/CodexReset"
fi
rm -f "$app_path/Contents/Resources/roadster.png"
cp Sources/ResetApp/Resources/en.json "$app_path/Contents/Resources/en.json"
cat > "$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codexreset.desktop</string>
<key>CFBundleName</key><string>Codex Jet</string>
<key>CFBundleDisplayName</key><string>Codex Jet</string>
<key>CFBundleExecutable</key><string>CodexReset</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string></array>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$app_version</string>
<key>CFBundleVersion</key><string>$app_version</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
strip -S "$app_path/Contents/MacOS/CodexReset"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
print "$app_path"
