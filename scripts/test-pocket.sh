#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
swift build --target ResetCore
BUILD_DIR=$(swift build --show-bin-path)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codexreset-pocket.XXXXXX")
swiftc -parse-as-library -I "$BUILD_DIR/Modules" tools/test-pocket.swift "$BUILD_DIR"/ResetCore.build/*.swift.o -o "$TEST_DIR/pocket"
"$TEST_DIR/pocket"
