#!/bin/sh
set -eu
export CODEXRESET_LANGUAGE=zh-Hans
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
swift build --target ResetCore
BUILD_DIR=$(swift build --show-bin-path)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codexreset-radar.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
swiftc -parse-as-library -I "$BUILD_DIR/Modules" Sources/ResetApp/Localization.swift Sources/ResetApp/Radar.swift Sources/ResetApp/RadarObservation.swift Sources/ResetApp/ExtraResetAdvice.swift tools/test-radar.swift "$BUILD_DIR"/ResetCore.build/*.swift.o -o "$TEST_DIR/test-radar"
"$TEST_DIR/test-radar"
