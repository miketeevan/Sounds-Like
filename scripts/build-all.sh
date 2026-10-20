#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
xcodebuild -project RadioBridge.xcodeproj -scheme RadioBridge -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build-public-ios CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RadioBridge.xcodeproj -scheme SoundsLikeTV -configuration Release -sdk appletvsimulator -destination 'generic/platform=tvOS Simulator' -derivedDataPath build-public-tv CODE_SIGNING_ALLOWED=NO build
