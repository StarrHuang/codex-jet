#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
swift build
BUILD_DIR=$(swift build --show-bin-path)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codexreset-flight3d.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
swiftc -parse-as-library -I "$BUILD_DIR/Modules" tools/test-flight-3d.swift \
  Sources/ResetApp/Roadster3DRenderer.swift Sources/ResetApp/RoadsterCarGeometry.swift \
  "$BUILD_DIR"/ResetCore.build/*.swift.o -o "$TEST_DIR/flight3d"
"$TEST_DIR/flight3d"
