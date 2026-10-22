#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
swift build --target ResetCore
BUILD_DIR=$(swift build --show-bin-path)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codexreset-deadline.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
swiftc -parse-as-library -I "$BUILD_DIR/Modules" tools/test-deadline.swift "$BUILD_DIR"/ResetCore.build/*.swift.o -o "$TMP_DIR/test-deadline"
"$TMP_DIR/test-deadline"
