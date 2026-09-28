#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h}"
test_dir="$(mktemp -d /tmp/siu-lan-test.XXXXXX)"
clang++ -std=c++14 -Wall -Wextra -Werror \
  -I "$repo_root/GameplayFootballOverlay" \
  "$repo_root/GameplayFootballOverlay/lan_protocol.cpp" \
  "$repo_root/Tests/lan_protocol_test.cpp" \
  -o "$test_dir/lan_protocol_test"
"$test_dir/lan_protocol_test"
clang++ -std=c++14 -Wall -Wextra -Werror -pthread \
  -I "$repo_root/GameplayFootballOverlay" \
  "$repo_root/GameplayFootballOverlay/lan_protocol.cpp" \
  "$repo_root/GameplayFootballOverlay/lan_session.cpp" \
  "$repo_root/Tests/lan_session_test.cpp" \
  -o "$test_dir/lan_session_test"
"$test_dir/lan_session_test"
print "LAN protocol and loopback tests passed"
