#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
swift build
BUILD_DIR=$(swift build --show-bin-path)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codexreset-quota-motion.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
proof_reduced=''
if [ "${1:-}" = --reduce-motion ]; then proof_reduced=--reduce-motion; fi
set --
for object in "$BUILD_DIR"/ResetApp.build/*.swift.o; do
  case "$object" in
    */Launch.swift.o) ;;
    *) set -- "$@" "$object" ;;
  esac
done
swiftc -parse-as-library -I "$BUILD_DIR/Modules" tools/proof-quota-motion.swift "$@" "$BUILD_DIR"/ResetCore.build/*.swift.o -o "$TEST_DIR/proof-quota-motion"
"$TEST_DIR/proof-quota-motion" /tmp/quota-flow-proof ${proof_reduced:+"$proof_reduced"}
