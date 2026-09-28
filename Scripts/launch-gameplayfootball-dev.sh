#!/bin/zsh
set -euo pipefail
bundle_contents="${0:A:h:h}"
cd "$bundle_contents/Resources"
exec "$bundle_contents/MacOS/gameplayfootball" "$@"
