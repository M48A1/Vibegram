#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
xcrun swiftc -swift-version 5 -module-cache-path .build/checks/ModuleCache \
    Vibegram/Core/TDLibClient.swift Tests/TDLibSmoke.swift -o .build/checks/tdlib-smoke
VIBEGRAM_TDLIB_PATH="$PWD/Vendor/TDLib/macOS/TDLib.framework/TDLib" .build/checks/tdlib-smoke
