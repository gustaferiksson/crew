#!/usr/bin/env bash
# Builds Crew for macOS (team-signed when .env sets DEVELOPMENT_TEAM) and the iOS Simulator.
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f .env ]]; then
  set -a
  source ./.env
  set +a
fi

MAC_SIGNING=( "CODE_SIGN_IDENTITY=-" "CODE_SIGN_STYLE=Manual" "CODE_SIGN_ENTITLEMENTS=" )
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  MAC_SIGNING=( "DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM}" "CODE_SIGN_ENTITLEMENTS=" )
fi
# CREW_PUSH=1 signs with the push entitlements, which need Push enabled on the App ID (server/crew-push/README.md).
if [[ -n "${DEVELOPMENT_TEAM:-}" && "${CREW_PUSH:-}" == 1 ]]; then
  MAC_SIGNING=( "DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM}" -allowProvisioningUpdates -allowProvisioningDeviceRegistration )
fi

if xcrun simctl list runtimes | grep -q 'iOS 27'; then
  IOS_DESTINATION="platform=iOS Simulator,OS=27.0,name=${IOS_SIMULATOR:-iPhone 18 Pro}"
else
  IOS_DESTINATION="generic/platform=iOS Simulator"
fi

MARKETING_VERSION="${MARKETING_VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)-local}"

echo "▸ Generating Xcode project…"
xcodegen generate --quiet

build() {
  local log
  log=$(mktemp)
  if ! xcodebuild -project Crew.xcodeproj -scheme Crew -configuration Debug -derivedDataPath .build -skipPackagePluginValidation -skipMacroValidation "MARKETING_VERSION=${MARKETING_VERSION}" "$@" build >"$log" 2>&1; then
    grep -E 'error:|warning:' "$log" | sort -u || tail -40 "$log"
    exit 1
  fi
  if grep -E '(^|: )warning:' "$log" | grep -v 'appintentsmetadataprocessor' | sort -u | grep .; then
    echo "✗ Build produced warnings"
    exit 1
  fi
}

echo "▸ Building macOS…"
build -destination 'platform=macOS,arch=arm64' "${MAC_SIGNING[@]}"
# Xcode never bumps the bundle's mtime, so Finder and the Dock keep the generic icon cached before AppIcon existed.
touch .build/Build/Products/Debug/Crew.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f .build/Build/Products/Debug/Crew.app

echo "▸ Building iOS Simulator (${IOS_DESTINATION})…"
build -destination "$IOS_DESTINATION" CODE_SIGNING_ALLOWED=NO

echo "✅ Built .build/Build/Products/Debug/Crew.app and Debug-iphonesimulator/Crew.app"
