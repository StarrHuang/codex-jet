#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
python3 - <<'PY'
import json, pathlib, re
catalog = json.loads(pathlib.Path('Sources/ResetApp/Resources/en.json').read_text())
for key, value in catalog.items():
    assert sorted(re.findall(r'\{\{\d+\}\}', key)) == sorted(re.findall(r'\{\{\d+\}\}', value)), key
    assert re.findall(r'%(?:\d+\$)?[-+0#]*(?:\d+)?(?:\.\d+)?[a-zA-Z%]', key) == re.findall(r'%(?:\d+\$)?[-+0#]*(?:\d+)?(?:\.\d+)?[a-zA-Z%]', value), key
    assert not re.search(r'[\u3400-\u9fff]', value), key
for source in pathlib.Path('Sources/ResetApp').glob('*.swift'):
    if source.name == 'Localization.swift': continue
    for match in re.finditer(r'\bL\(("(?:[^"\\]|\\.)*")', source.read_text()):
        key = json.loads(match[1])
        if re.search(r'[\u3400-\u9fff]', key): assert key in catalog, (source, key)
print(f'PASS: {len(catalog)} English entries, source coverage and interpolation/format signatures')
PY
swift build
BUILD_DIR=$(swift build --show-bin-path)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codexreset-language.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
set --
for object in "$BUILD_DIR"/ResetApp.build/*.swift.o; do
  case "$object" in */Launch.swift.o) ;; *) set -- "$@" "$object" ;; esac
done
swiftc -parse-as-library -I "$BUILD_DIR/Modules" tools/test-localization.swift "$@" "$BUILD_DIR"/ResetCore.build/*.swift.o -o "$TEST_DIR/localization"
CODEXRESET_LANGUAGE=zh-Hans "$TEST_DIR/localization" zh-Hans
CODEXRESET_LANGUAGE=en "$TEST_DIR/localization" en
