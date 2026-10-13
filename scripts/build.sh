#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/Clippy.app/Contents/MacOS build/Clippy.app/Contents/Resources build/module-cache
if [[ ! -f Resources/Clippy.icns || Resources/Clippy.png -nt Resources/Clippy.icns ]]; then
    bash scripts/make-icon.sh
fi
swiftc -swift-version 5 -O -target "$(uname -m)-apple-macosx14.0" -module-cache-path build/module-cache Sources/Geometry.swift Sources/TextAssembler.swift Sources/Settings.swift Sources/Feedback.swift Sources/main.swift -o build/Clippy.app/Contents/MacOS/Clippy
cp Resources/Clippy.icns build/Clippy.app/Contents/Resources/Clippy.icns
cp Resources/Info.plist build/Clippy.app/Contents/Info.plist
codesign --force --sign "${SCANNER_SIGNING_IDENTITY:--}" --identifier app.local.scanner build/Clippy.app
echo "Built build/Clippy.app"

install_path="/Applications/Clippy.app"
if [[ -d "$install_path" ]]; then
    rm -rf "$install_path"
fi
ditto build/Clippy.app "$install_path"
echo "Installed $install_path"
