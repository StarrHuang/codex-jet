#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
swift build --target ResetCore
BUILD_DIR=$(swift build --show-bin-path)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codexreset-tokens.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
swiftc -parse-as-library -I "$BUILD_DIR/Modules" tools/test-tokens.swift "$BUILD_DIR"/ResetCore.build/*.swift.o -o "$TEST_DIR/test-tokens"
"$TEST_DIR/test-tokens"
