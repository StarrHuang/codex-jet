#!/bin/bash
# Install/update the public Codex Jet GitHub release. Never changes quota history or Codex login.
set -euo pipefail
repo='StarrHuang/codex-jet'
install_root="${CODEXRESET_INSTALL_DIR:-$HOME/Applications}"
archive=''
launch=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --archive) archive="$2"; shift 2 ;;
    --destination) install_root="$2"; shift 2 ;;
    --no-launch) launch=0; shift ;;
    *) printf 'Usage: %s [--archive release.zip] [--destination directory] [--no-launch]\n' "$0" >&2; exit 1 ;;
  esac
done
[ "$(uname -s)" = Darwin ] || { echo '仅支持 macOS。' >&2; exit 1; }
mac_version=$(sw_vers -productVersion)
[ "${mac_version%%.*}" -ge 14 ] || { echo '需要 macOS 14 或更新版本。' >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-/tmp}/codexjet-install.XXXXXX")
staging=''
target="$install_root/Codex Jet.app"
cleanup() {
  if [ -n "$staging" ] && [ -d "$staging/previous.app" ] && [ ! -e "$target" ]; then
    mv "$staging/previous.app" "$target"
  fi
  [ -z "$staging" ] || rm -rf "$staging"
  rm -rf "$work"
}
trap cleanup EXIT
if [ -z "$archive" ]; then
  release_url="https://github.com/$repo/releases/latest/download"
  archive="$work/CodexJet-macOS-universal.zip"
  curl --fail --location --silent --show-error \
    --output "$archive" "$release_url/CodexJet-macOS-universal.zip"
  curl --fail --location --silent --show-error \
    --output "$work/SHA256SUMS" "$release_url/SHA256SUMS"
else
  [ -f "$archive" ] || { echo '未找到安装包。' >&2; exit 1; }
  source_dir=$(cd "$(dirname "$archive")" && pwd)
  cp "$archive" "$work/CodexJet-macOS-universal.zip"
  cp "$source_dir/SHA256SUMS" "$work/SHA256SUMS"
  archive="$work/CodexJet-macOS-universal.zip"
fi
(cd "$work" && shasum -a 256 -c SHA256SUMS)
ditto -x -k "$archive" "$work/unpacked"
source_app="$work/unpacked/Codex Jet.app"
codesign --verify --deep --strict "$source_app"
binary_description=$(/usr/bin/file -b "$source_app/Contents/MacOS/CodexReset")
case "$binary_description" in
  *"$(uname -m)"*) ;;
  *) echo '安装包不支持本机 CPU 架构。' >&2; exit 1 ;;
esac
if [ -d "$target" ] && pgrep -x CodexReset >/dev/null; then
  echo '请先从菜单退出 Codex Jet，再运行安装/更新。' >&2
  exit 1
fi
mkdir -p "$install_root"
staging=$(mktemp -d "$install_root/.codexjet-stage.XXXXXX")
ditto "$source_app" "$staging/new.app"
codesign --verify --deep --strict "$staging/new.app"
if [ -e "$target" ]; then mv "$target" "$staging/previous.app"; fi
mv "$staging/new.app" "$target"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target/Contents/Info.plist")
printf '已安装 Codex Jet %s：%s\n' "$version" "$target"
if [ "$launch" -eq 1 ]; then open "$target"; fi
