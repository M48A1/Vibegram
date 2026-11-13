#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/official-checks

git -C macOS diff --check
git -C iOS diff --check
git -C macOS apply --reverse --check "$PWD/patches/official/macos-uid-dc.patch"
git -C macOS apply --reverse --check "$PWD/patches/official/macos-xcode27-support.patch"
git -C iOS apply --reverse --check "$PWD/patches/official/ios-uid-dc.patch"

xcrun swiftc -frontend -parse \
    macOS/packages/PeerInfoUI/Sources/PeerInfoUI/UserInfoEntries.swift \
    macOS/packages/Localization/Sources/Localization/Localizable.swift
ios_profile=iOS/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources
xcrun swiftc -frontend -parse \
    "$ios_profile/PeerInfoProfileItems.swift" \
    "$ios_profile/PeerInfoScreen.swift" \
    "$ios_profile/PeerInfoScreenOpenPeerInfoContextMenu.swift"

plutil -lint macOS/Telegram-Mac/en.lproj/Localizable.strings \
    iOS/Telegram/Telegram-iOS/en.lproj/Localizable.strings
python3 iOS/build-system/GenerateStrings/GenerateStrings.py \
    --source iOS/Telegram/Telegram-iOS/en.lproj/Localizable.strings \
    --outImplementation .build/official-checks/PresentationStrings.m \
    --outHeader .build/official-checks/PresentationStrings.h \
    --outData .build/official-checks/PresentationStrings.data
rg -q 'Vibegram_AvatarDC' .build/official-checks/PresentationStrings.h
rg -q 'Vibegram_UnknownDC' .build/official-checks/PresentationStrings.h
echo 'Official client source checks passed (full builds and UI checks are separate).'
