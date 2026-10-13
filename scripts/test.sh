#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Geometry.swift Sources/TextAssembler.swift Sources/Settings.swift Sources/Feedback.swift Tests/CoreTests.swift -o build/CoreTests
build/CoreTests
