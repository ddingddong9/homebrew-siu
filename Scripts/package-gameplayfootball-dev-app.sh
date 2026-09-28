#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 || ! -x "$1/gameplayfootball" || ! -d "$1/media" ]]; then
  print -u2 "usage: $0 /absolute/path/to/gameplayfootball-build"
  exit 2
fi

build_dir="${1:A}"
script_dir="${0:A:h}"
app_dir="$build_dir/GameplayFootballDev.app"
contents="$app_dir/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
ditto "$build_dir/gameplayfootball" "$contents/MacOS/gameplayfootball"
ditto "$script_dir/launch-gameplayfootball-dev.sh" "$contents/MacOS/launch-gameplayfootball"
ditto "$script_dir/GameplayFootballDev-Info.plist" "$contents/Info.plist"
for item in football.config media databases; do
  ditto "$build_dir/$item" "$contents/Resources/$item"
done
chmod +x "$contents/MacOS/launch-gameplayfootball"
print "$app_dir"
