#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
upstream="$repo_root/Vendor/GameplayFootball"
patch_dir="$repo_root/GameplayFootballPatches"
expected_revision="68159a2f0f96eec8ebba26ab7820130f36b922a7"

run_game=false
quick_match=false
lan_role=""
lan_host=""
lan_port=38245
for arg in "$@"; do
  case "$arg" in
    --run) run_game=true ;;
    --quick-match) quick_match=true ;;
    --lan-host) lan_role=host; quick_match=true ;;
    --lan-join=*) lan_role=client; lan_host="${arg#--lan-join=}"; quick_match=true ;;
    --lan-port=*) lan_port="${arg#--lan-port=}" ;;
    *) print -u2 "usage: $0 [--quick-match] [--lan-host|--lan-join=IPv4] [--lan-port=PORT] [--run]"; exit 2 ;;
  esac
done
if [[ "$lan_port" != <-> || "$lan_port" -lt 1 || "$lan_port" -gt 65535 ]]; then
  print -u2 "Invalid LAN port: $lan_port"
  exit 2
fi

for command_name in cmake ninja git tar ditto perl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    print -u2 "Missing dependency: $command_name"
    exit 2
  fi
done

if [[ ! -d "$upstream/src" ]]; then
  print -u2 "GameplayFootball submodule is missing. Run: git submodule update --init Vendor/GameplayFootball"
  exit 2
fi
actual_revision="$(git -C "$upstream" rev-parse HEAD)"
if [[ "$actual_revision" != "$expected_revision" ]]; then
  print -u2 "Expected GameplayFootball $expected_revision; got $actual_revision"
  exit 2
fi

# Keeping the staging tree outside this repository also avoids a CMake path
# normalization stall observed when configuring this upstream tree in Documents.
stage="$(mktemp -d /tmp/siu-gameplayfootball.XXXXXX)"
source_dir="$stage/source"
build_dir="$stage/build"
mkdir -p "$source_dir"
git -C "$upstream" archive HEAD | tar -xf - -C "$source_dir"
for patch_file in "$patch_dir"/*.patch; do
  (cd "$source_dir" && git apply --recount "$patch_file")
done
mkdir -p "$source_dir/src/siu"
ditto "$repo_root/GameplayFootballOverlay" "$source_dir/src/siu"
# GLSL 150 core removed texture2D(); the shaders otherwise use core syntax.
perl -pi -e 's/\btexture2D\(/texture(/g' "$source_dir"/data/media/shaders/*.frag

# CMake 4 can stall during its own startup if the invoking process is still
# inside the Documents-backed checkout, even with -S/-B pointing at /tmp.
(cd "$stage" && cmake -S "$source_dir" -B "$build_dir" -G Ninja -DCMAKE_POLICY_VERSION_MINIMUM=3.5)
if ! (cd "$stage" && cmake --build "$build_dir" --parallel "$(sysctl -n hw.ncpu)" > "$stage/build.log" 2>&1); then
  tail -n 60 "$stage/build.log" >&2
  print -u2 "Full build log: $stage/build.log"
  exit 1
fi
ditto "$source_dir/data" "$build_dir"
if $quick_match; then
  print '"debug" "true"' >> "$build_dir/football.config"
fi
if [[ -n "$lan_role" ]]; then
  print '"siu_lan_role" "'"$lan_role"'"' >> "$build_dir/football.config"
  print '"siu_lan_host" "'"$lan_host"'"' >> "$build_dir/football.config"
  print '"siu_lan_port" "'"$lan_port"'"' >> "$build_dir/football.config"
fi

print "GameplayFootball built at: $build_dir/gameplayfootball"
print "Build log: $stage/build.log"
if $run_game; then
  (cd "$build_dir" && ./gameplayfootball)
fi
