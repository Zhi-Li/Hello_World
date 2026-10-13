#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
    echo "Package the compiled app on a Mac." >&2
    exit 1
fi
app=dist/ScreenGate.app
helper=dist/ScreenGateService
if [[ ! -x "$app/Contents/MacOS/ScreenGate" || ! -x "$helper" ]]; then
    echo "Run scripts/build.sh successfully before packaging." >&2
    exit 1
fi
codesign --verify --strict "$app"
codesign --verify --strict "$helper"
xcrun lipo -verify_arch arm64 x86_64 "$app/Contents/MacOS/ScreenGate"
xcrun lipo -verify_arch arm64 x86_64 "$helper"
stage=$(mktemp -d "${TMPDIR:-/tmp}/screengate-release.XXXXXX")
trap 'rm -rf "$stage"' EXIT
release="$stage/ScreenGate"
mkdir -p "$release/dist" "$release/resources"
ditto "$app" "$release/dist/ScreenGate.app"
cp "$helper" "$release/dist/ScreenGateService"
cp Install.command Recover.command Uninstall.command "$release/"
cp resources/com.screengate.service.plist resources/com.screengate.ui.plist "$release/resources/"
cp resources/BINARY_README.md "$release/README.md"
cp MAC_TEST_CHECKLIST.md "$release/"
chmod 755 "$release/"*.command "$release/dist/ScreenGateService"
output="$PWD/dist/ScreenGate-macOS-universal.zip"
rm -f "$output"
ditto -c -k --sequesterRsrc --keepParent "$release" "$output"
echo "Compiled app and installer packaged: $output"
