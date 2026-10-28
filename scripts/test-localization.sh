#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
python3 - <<'PY'
import json, pathlib, re
base = json.loads(pathlib.Path('Sources/ResetApp/Resources/en.json').read_text())
locales = {name: json.loads(pathlib.Path(f'Sources/ResetApp/Resources/{name}.json').read_text()) for name in ('ja', 'ko')}
placeholder = lambda text: sorted(re.findall(r'\{\{\d+\}\}', text))
format_spec = lambda text: re.findall(r'%(?:\d+\$)?[-+0#]*(?:\d+)?(?:\.\d+)?[a-zA-Z%]', text)
for language, catalog in locales.items():
    assert set(catalog) == set(base), f'{language}: catalog keys differ from English'
    for key, english in base.items():
        value = catalog[key]
        assert placeholder(key) == placeholder(value), f'{language}: key placeholder mismatch: {key}'
        assert format_spec(key) == format_spec(value), f'{language}: key format mismatch: {key} -> {value}'
        assert placeholder(english) == placeholder(value), f'{language}: value placeholder mismatch: {key}'
        assert format_spec(english) == format_spec(value), f'{language}: value format mismatch: {key} -> {value}'
        assert value.strip(), f'{language}: empty value: {key}'
        assert value.count('\n') == key.count('\n'), f'{language}: newline count changed: {key}'
        assert value.startswith('\n') == key.startswith('\n'), f'{language}: leading newline changed: {key}'
        assert value.endswith('\n') == key.endswith('\n'), f'{language}: trailing newline changed: {key}'
        assert value != english or key in ('English', 'Codex Reset · 常驻提醒'), f'{language}: English fallback: {key}'
for source in pathlib.Path('Sources/ResetApp').glob('*.swift'):
    if source.name == 'Localization.swift':
        continue
    for match in re.finditer(r'\bL\(("(?:[^"\\]|\\.)*")', source.read_text()):
        key = json.loads(match[1])
        if re.search(r'[\u3400-\u9fff]', key):
            assert key in base, (source, key)
print(f'PASS: {len(base)} entries per ja/ko catalog, source coverage and interpolation/format signatures')
PY
swift build
BUILD_DIR=$(swift build --show-bin-path)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codexjet-language.XXXXXX")
set --
for object in "$BUILD_DIR"/ResetApp.build/*.swift.o; do
  case "$object" in */Launch.swift.o) ;; *) set -- "$@" "$object" ;; esac
done
swiftc -parse-as-library -I "$BUILD_DIR/Modules" tools/test-localization.swift "$@" "$BUILD_DIR"/ResetCore.build/*.swift.o -o "$TEST_DIR/localization"
for language in zh-Hans en ja-JP ko-KR; do
  case "$language" in
    ja-JP) expected=ja ;;
    ko-KR) expected=ko ;;
    *) expected="$language" ;;
  esac
  CODEXRESET_LANGUAGE="$language" "$TEST_DIR/localization" "$expected"
done
