#!/usr/bin/env bash
# Runs the CrewUITests XCUITests on an iOS 27 simulator (never on the Mac). Usage: Tests/ui.sh [-only-testing:CrewUITests/...]
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild test -project Crew.xcodeproj -scheme CrewUITests -derivedDataPath .build -skipPackagePluginValidation -skipMacroValidation \
  -destination "platform=iOS Simulator,OS=27.0,name=${IOS_SIMULATOR:-iPhone 18 Pro}" CODE_SIGNING_ALLOWED=NO "$@"
