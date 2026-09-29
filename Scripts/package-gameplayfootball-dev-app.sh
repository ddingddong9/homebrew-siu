#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 || ! -x "$1/gameplayfootball" || ! -d "$1/media" ]]; then
  print -u2 "usage: $0 /absolute/path/to/gameplayfootball-build"
  exit 2
fi

build_dir="${1:A}"
script_dir="${0:A:h}"
repo_root="${script_dir:h}"
swift_binary="$repo_root/.build/release/siu"
if [[ ! -x "$swift_binary" ]]; then
  print -u2 "Missing SIU lobby executable: $swift_binary"
  exit 1
fi
icon_source="$repo_root/Assets/icon/siu-cutout.png"
app_dir="$build_dir/SIU Football.app"
contents="$app_dir/Contents"
if [[ ! -f "$icon_source" ]]; then
  print -u2 "Missing SIU icon: $icon_source"
  exit 1
fi
mkdir -p "$contents/MacOS" "$contents/Resources"
ditto "$build_dir/gameplayfootball" "$contents/MacOS/gameplayfootball"
ditto "$swift_binary" "$contents/MacOS/siu"
ditto "$script_dir/launch-gameplayfootball-dev.sh" "$contents/MacOS/launch-gameplayfootball"
ditto "$script_dir/GameplayFootballDev-Info.plist" "$contents/Info.plist"
for item in football.config media databases; do
  ditto "$build_dir/$item" "$contents/Resources/$item"
done

# Reuse the existing SIU application icon at every macOS-required resolution.
iconset="$(mktemp -d /tmp/siu-football-icon.XXXXXX)/siu.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$icon_source" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" "$icon_source" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$contents/Resources/siu.icns"
rm -r "${iconset:h}"

chmod +x "$contents/MacOS/launch-gameplayfootball"
plutil -lint "$contents/Info.plist" >/dev/null
print "$app_dir"
