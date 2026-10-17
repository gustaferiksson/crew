#!/usr/bin/env bash
# Runs the CrewUITests XCUITests on a private iOS 27 simulator (never on the Mac). Usage: Tests/ui.sh [-only-testing:CrewUITests/...]
set -euo pipefail
cd "$(dirname "$0")/.."

device=$(xcrun simctl create "crew-ui-$$" "${IOS_SIMULATOR:-iPhone 18 Pro}" com.apple.CoreSimulator.SimRuntime.iOS-27-0)
trap 'xcrun simctl shutdown "$device" >/dev/null 2>&1 || true; xcrun simctl delete "$device"' EXIT

echo "▸ Building for testing…"
xcodegen generate --quiet
xcodebuild build-for-testing -quiet -project Crew.xcodeproj -scheme CrewUITests -derivedDataPath .build -skipPackagePluginValidation -skipMacroValidation \
  -destination "platform=iOS Simulator,id=$device" CODE_SIGNING_ALLOWED=NO

echo "▸ Booting the simulator…"
xcrun simctl bootstatus "$device" -b >/dev/null

echo "▸ Warming up…"
ready="$HOME/Library/Developer/CoreSimulator/Devices/$device/data/tmp/crew-ready.log"
xcrun simctl install "$device" .build/Build/Products/Debug-iphonesimulator/Crew.app
SECONDS=0
xcrun simctl launch --stdout="$ready" "$device" dev.gustaf.crew -snapshot sidebar -server hermes.example.com -username gustaf
until grep -q ready "$ready" 2>/dev/null; do
  if (( SECONDS > 420 )); then
    echo "✗ Crew did not render its snapshot within ${SECONDS}s of launch"
    exit 1
  fi
  sleep 1
done
echo "▸ First launch rendered in ${SECONDS}s"
xcrun simctl terminate "$device" dev.gustaf.crew

xcodebuild test-without-building -xctestrun .build/Build/Products/CrewUITests_*.xctestrun \
  -destination "id=$device" -collect-test-diagnostics never -test-timeouts-enabled YES -default-test-execution-time-allowance 300 "$@"
