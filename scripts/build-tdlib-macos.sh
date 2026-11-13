#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
revision="$(tr -d '\n' < scripts/tdlib-revision.txt)"
brew_bin="$(command -v brew || true)"
if [[ -z "$brew_bin" && -x /opt/homebrew/bin/brew ]]; then brew_bin=/opt/homebrew/bin/brew; fi
if [[ -z "$brew_bin" ]]; then echo 'Homebrew is required to locate CMake, gperf and OpenSSL.' >&2; exit 1; fi
cmake_bin="$($brew_bin --prefix cmake)/bin/cmake"
openssl_root="$root/Vendor/OpenSSL/macOS"
if [[ ! -f "$openssl_root/lib/libcrypto.a" ]]; then bash scripts/build-openssl-macos.sh; fi
export PATH="$($brew_bin --prefix gperf)/bin:$PATH"
if [[ ! -d Vendor/td/.git ]]; then
    mkdir -p Vendor
    git clone --no-checkout https://github.com/tdlib/td.git Vendor/td
    git -C Vendor/td checkout --detach "$revision"
fi
actual="$(git -C Vendor/td rev-parse HEAD)"
if [[ "$actual" != "$revision" ]]; then
    echo "Expected TDLib $revision, found $actual. No source changes were made." >&2
    exit 1
fi
"$cmake_bin" -S Vendor/td -B .build/tdlib-macos \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_OSX_ARCHITECTURES="$(uname -m)" \
    -DOPENSSL_ROOT_DIR="$openssl_root" \
    -DOPENSSL_INCLUDE_DIR="$openssl_root/include" \
    -DOPENSSL_CRYPTO_LIBRARY="$openssl_root/lib/libcrypto.a" \
    -DOPENSSL_SSL_LIBRARY="$openssl_root/lib/libssl.a" \
    -DOPENSSL_USE_STATIC_LIBS=TRUE \
    -DTD_INSTALL_STATIC_LIBRARIES=OFF \
    -DCMAKE_INSTALL_PREFIX="$root/Vendor/TDLib/macOS"
"$cmake_bin" --build .build/tdlib-macos --target tdjson --parallel "${TDLIB_JOBS:-4}"
bash scripts/package-tdlib-macos.sh
