#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "Usage: Scripts/package-app.sh VERSION"
  exit 2
fi

version="$1"
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$' ]]; then
  print -u2 "Version must look like 1.4.0-beta.1"
  exit 2
fi

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
staging_dir="$root_dir/dist/siu-$version-app-stage"
archive="$root_dir/dist/siu-v$version-macos-app.zip"
if [[ -e "$staging_dir" || -e "$archive" ]]; then
  print -u2 "Package output already exists; choose a new version or move the old output first."
  exit 1
fi

cd "$root_dir"
swift build -c release --triple arm64-apple-macosx13.0
swift build -c release --triple x86_64-apple-macosx13.0

app="$staging_dir/SIU.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Packaging/SIU-Info.plist "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"
lipo -create \
  "$root_dir/.build/arm64-apple-macosx/release/siu" \
  "$root_dir/.build/x86_64-apple-macosx/release/siu" \
  -output "$app/Contents/MacOS/siu"
ditto "$root_dir/.build/arm64-apple-macosx/release/siu_MacArrow.bundle" \
  "$app/Contents/Resources/siu_MacArrow.bundle"

iconset="$staging_dir/siu.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Assets/icon/siu-cutout.png \
    --out "$iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" Assets/icon/siu-cutout.png \
    --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/siu.icns"
rm -r "$iconset"

codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/siu" self-test
"$app/Contents/MacOS/siu" asset-check
cd "$staging_dir"
zip -qry "$archive" SIU.app
shasum -a 256 "$archive"
