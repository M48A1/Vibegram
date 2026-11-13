#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
xcrun swiftc -swift-version 5 -strict-concurrency=complete -module-cache-path .build/checks/ModuleCache \
    Vibegram/Core/Models.swift Vibegram/Core/Keychain.swift Vibegram/Core/TDLibClient.swift \
    Vibegram/Core/AppStore.swift Tests/CoreChecks.swift -o .build/checks/core
.build/checks/core
