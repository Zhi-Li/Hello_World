#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Build this project on a Mac with macOS 12 or later." >&2
    exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
    echo "Install Apple's Command Line Tools, then run Install.command again."
    xcode-select --install || true
    exit 1
fi
macos_major=$(sw_vers -productVersion | cut -d. -f1)
if (( macos_major < 12 )); then
    echo "ScreenGate requires macOS 12 or later." >&2
    exit 1
fi
swift_version=$(xcrun swift --version | sed -nE 's/.*Swift version ([0-9]+)\.([0-9]+).*/\1 \2/p' | head -1)
read -r swift_major swift_minor <<< "$swift_version"
if [[ -z "${swift_major:-}" || -z "${swift_minor:-}" ]] || \
   (( swift_major < 5 || (swift_major == 5 && swift_minor < 7) )); then
    echo "Building needs Swift 5.7 or later."
    echo "On macOS 12.7.6, install Xcode 14.2 or compatible Command Line Tools from developer.apple.com/download/all/."
    exit 1
fi
export MACOSX_DEPLOYMENT_TARGET=12.0
# SwiftPM 5.7 calls this --build-path; the newer name arrived in Swift 5.8.
build_path_option=--scratch-path
if (( swift_major == 5 && swift_minor < 8 )); then
    build_path_option=--build-path
fi
echo "Running schedule, usage, and protocol tests…"
xcrun swift test
echo "Building Apple silicon and Intel versions…"
for architecture in arm64 x86_64; do
    xcrun swift build -c release --arch "$architecture" "$build_path_option" ".build/$architecture"
done
arm_bin=$(xcrun swift build -c release --arch arm64 "$build_path_option" .build/arm64 --show-bin-path)
intel_bin=$(xcrun swift build -c release --arch x86_64 "$build_path_option" .build/x86_64 --show-bin-path)
app="dist/ScreenGate.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun lipo -create "$arm_bin/ScreenGate" "$intel_bin/ScreenGate" -output "$app/Contents/MacOS/ScreenGate"
xcrun lipo -create "$arm_bin/ScreenGateService" "$intel_bin/ScreenGateService" -output dist/ScreenGateService
cp resources/Info.plist "$app/Contents/Info.plist"
xcrun swift scripts/make-icon.swift "$app/Contents/Resources"
codesign --force --sign - --timestamp=none "$app"
codesign --force --sign - --timestamp=none dist/ScreenGateService
codesign --verify --strict "$app"
codesign --verify --strict dist/ScreenGateService
xcrun lipo "$app/Contents/MacOS/ScreenGate" -verify_arch arm64 x86_64
xcrun lipo dist/ScreenGateService -verify_arch arm64 x86_64
echo "Universal app built: dist/ScreenGate.app (arm64 + x86_64)"
