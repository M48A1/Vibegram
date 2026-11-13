#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
version=3.5.9
checksum=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
archive="Vendor/downloads/openssl-$version.tar.gz"
prefix="$root/Vendor/OpenSSL/macOS"
mkdir -p Vendor/downloads .build/openssl-macos
if [[ ! -f "$archive" ]]; then
    curl --fail --location --retry 2 \
        "https://github.com/openssl/openssl/releases/download/openssl-$version/openssl-$version.tar.gz" -o "$archive"
fi
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 --check
if [[ ! -d "Vendor/openssl-$version" ]]; then tar -xzf "$archive" -C Vendor; fi
case "$(uname -m)" in
    arm64) target=darwin64-arm64-cc ;;
    x86_64) target=darwin64-x86_64-cc ;;
    *) echo 'Unsupported macOS architecture' >&2; exit 1 ;;
esac
cd .build/openssl-macos
perl "$root/Vendor/openssl-$version/Configure" "$target" no-shared no-tests no-module \
    --prefix="$prefix" --libdir=lib -mmacosx-version-min=14.0
make -j"${TDLIB_JOBS:-4}" build_sw
make install_sw
