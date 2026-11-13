#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/checks
xcrun swiftc -module-cache-path .build/checks/ModuleCache Vibegram/Core/Models.swift Tests/ModelChecks.swift -o .build/checks/models
.build/checks/models
