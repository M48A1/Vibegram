#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
framework="$PWD/Vendor/TDLib/macOS/TDLib.framework"
binary="$framework/Versions/A/TDLib"
mkdir -p "$framework/Versions/A/Resources"
cp .build/tdlib-macos/libtdjson.dylib "$binary"
install_name_tool -id '@rpath/TDLib.framework/Versions/A/TDLib' "$binary"
# Only macOS system dependencies are allowed. OpenSSL must have been linked statically.
if otool -L "$binary" | tail -n +3 | awk '{print $1}' | rg -v '^(/usr/lib/|/System/Library/)' ; then
    echo 'Unexpected non-system dependency; framework is not self-contained.' >&2
    exit 1
fi
cat > "$framework/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.vibegram.tdlib</string>
<key>CFBundleName</key><string>TDLib</string>
<key>CFBundleExecutable</key><string>TDLib</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>1.8.70</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
cp Vendor/td/LICENSE_1_0.txt "$framework/Versions/A/Resources/TDLib-LICENSE.txt"
cp scripts/tdlib-revision.txt "$framework/Versions/A/Resources/TDLib-REVISION.txt"
cp Vendor/openssl-3.5.9/LICENSE.txt "$framework/Versions/A/Resources/OpenSSL-LICENSE.txt"
ln -sfn A "$framework/Versions/Current"
ln -sfn Versions/Current/TDLib "$framework/TDLib"
ln -sfn Versions/Current/Resources "$framework/Resources"
codesign --force --sign - "$framework"
echo "Packaged: $framework"
shasum -a 256 "$binary"
