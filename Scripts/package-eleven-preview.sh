#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
preview_app="dist/SIU Eleven Preview.app"
mkdir -p "$preview_app/Contents/MacOS" "$preview_app/Contents/Resources"
cp .build/release/siu "$preview_app/Contents/MacOS/siu"
cp Packaging/SIU-Eleven-Info.plist "$preview_app/Contents/Info.plist"
ditto .build/release/siu_MacArrow.bundle "$preview_app/Contents/Resources/siu_MacArrow.bundle"
if [[ -f Packaging/AppIcon.icns ]]; then
    cp Packaging/AppIcon.icns "$preview_app/Contents/Resources/AppIcon.icns"
fi
codesign --force --deep --sign - "$preview_app"
"$preview_app/Contents/MacOS/siu" self-test
"$preview_app/Contents/MacOS/siu" asset-check
echo "Local development preview: $preview_app"
echo "This is not a notarized or universal public release."
