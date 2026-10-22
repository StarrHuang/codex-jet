#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
swift build
BUILD_DIR=$(swift build --show-bin-path)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codexreset-menu.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
# Reuse the debug app module but exclude its executable entry point.
set --
for object in "$BUILD_DIR"/ResetApp.build/*.swift.o; do
  case "$object" in
    */Launch.swift.o) ;;
    *) set -- "$@" "$object" ;;
  esac
done
swiftc -parse-as-library -I "$BUILD_DIR/Modules" tools/test-menu.swift "$@" "$BUILD_DIR"/ResetCore.build/*.swift.o -o "$TEST_DIR/test-menu"
"$TEST_DIR/test-menu"
