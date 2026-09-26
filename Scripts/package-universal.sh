#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "Usage: Scripts/package-universal.sh VERSION"
  exit 2
fi

version="$1"
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$' ]]; then
  print -u2 "Version must look like 1.3.0-beta.1"
  exit 2
fi

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
staging_dir="$root_dir/dist/siu-$version-stage"
archive="$root_dir/dist/siu-v$version-macos-universal.zip"
if [[ -e "$staging_dir" || -e "$archive" ]]; then
  print -u2 "Package output already exists; choose a new version or move the old output first."
  exit 1
fi

cd "$root_dir"
swift build -c release --triple arm64-apple-macosx13.0
swift build -c release --triple x86_64-apple-macosx13.0
mkdir -p "$staging_dir"
lipo -create \
  "$root_dir/.build/arm64-apple-macosx/release/siu" \
  "$root_dir/.build/x86_64-apple-macosx/release/siu" \
  -output "$staging_dir/siu"
codesign --force --sign - "$staging_dir/siu"
ditto "$root_dir/.build/arm64-apple-macosx/release/siu_MacArrow.bundle" \
  "$staging_dir/siu_MacArrow.bundle"
"$staging_dir/siu" self-test
"$staging_dir/siu" asset-check
ditto -c -k --sequesterRsrc "$staging_dir" "$archive"
shasum -a 256 "$archive"
