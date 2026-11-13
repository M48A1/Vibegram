#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/macOS"

if [[ "$(xcodebuild -version | head -1)" == 'Xcode 27.'* ]]; then
    bash scripts/xcode27.sh apply
fi

export CARGO
export RUSTC
export RUSTDOC
CARGO="$(rustup which --toolchain 1.96.1 cargo)"
RUSTC="$(rustup which --toolchain 1.96.1 rustc)"
RUSTDOC="$(rustup which --toolchain 1.96.1 rustdoc)"
export RUSTUP_TOOLCHAIN=1.96.1
export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C strip=none"
export CARGO_PROFILE_RELEASE_STRIP=none
export CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_STRIP=none
export CMAKE_POLICY_VERSION_MINIMUM=3.5
export PATH="$(dirname "$CARGO"):$PATH"

bash scripts/configure_frameworks.sh
xcodebuild -workspace Telegram-Mac.xcworkspace \
    -scheme Telegram -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$root/.build/official-macos" \
    -clonedSourcePackagesDirPath "$root/.build/official-packages" \
    CODE_SIGNING_ALLOWED=NO build
