#!/usr/bin/env bash
# Release builds (CI): `mac` signs dist/Crew.app with Developer ID; `ios` exports the Ad Hoc dist/Crew.ipa and dist/manifest.plist.
# The signing identity must already be in a keychain; VERSION and BUILD come from the release workflow.
set -euo pipefail
cd "$(dirname "$0")"

PLATFORM="${1:-}"
VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)-local}"
BUILD="${BUILD:-1}"
TEAM=82K3YC8HVF
PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
COMMON=( -project Crew.xcodeproj -scheme Crew -configuration Release -derivedDataPath .build -quiet
  "DEVELOPMENT_TEAM=${TEAM}" CODE_SIGN_STYLE=Manual "MARKETING_VERSION=${VERSION}" "CURRENT_PROJECT_VERSION=${BUILD}" )

install_profile() {
  local profile=$1 extension=$2 uuid
  [[ -f "$profile" ]] || { echo "✗ $profile not found"; exit 1; }
  uuid=$(security cms -D -i "$profile" | plutil -extract UUID raw -o - -)
  mkdir -p "$PROFILES_DIR"
  cp "$profile" "$PROFILES_DIR/$uuid.$extension"
}

check_entitlements() {
  local app=$1 entitlements
  entitlements=$(mktemp)
  codesign -d --entitlements - --xml "$app" >"$entitlements" 2>/dev/null
  local aps
  aps=$(/usr/libexec/PlistBuddy -c "Print :$2" "$entitlements" 2>/dev/null || true)
  [[ "$aps" == production ]] || { echo "✗ $2 is '$aps', expected production"; exit 1; }
  if [[ "$(/usr/libexec/PlistBuddy -c "Print :get-task-allow" "$entitlements" 2>/dev/null)" == true \
    || "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.get-task-allow" "$entitlements" 2>/dev/null)" == true ]]; then
    echo "✗ $app is debuggable (get-task-allow)"; exit 1
  fi
  if [[ "$PLATFORM" == mac ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.device.audio-input" "$entitlements" 2>/dev/null)" == true ]] \
      || { echo "✗ audio-input entitlement missing"; exit 1; }
  fi
  rm -f "$entitlements"
}

if [[ "$PLATFORM" != mac && "$PLATFORM" != ios ]]; then
  echo "usage: ./package.sh <mac|ios>"; exit 1
fi

echo "▸ Generating Xcode project…"
xcodegen generate --quiet
rm -rf dist
mkdir -p dist

if [[ "$PLATFORM" == mac ]]; then
  install_profile Signing/Crew_DeveloperID.provisionprofile provisionprofile
  echo "▸ Building Crew ${VERSION} (${BUILD}) for macOS…"
  xcodebuild "${COMMON[@]}" -destination 'generic/platform=macOS' \
    CODE_SIGN_IDENTITY="Developer ID Application" PROVISIONING_PROFILE_SPECIFIER="Crew Developer ID" \
    OTHER_CODE_SIGN_FLAGS=--timestamp build
  cp -R .build/Build/Products/Release/Crew.app dist/Crew.app
  check_entitlements dist/Crew.app com.apple.developer.aps-environment
  echo "✅ Built dist/Crew.app"
  exit 0
fi

install_profile "${IOS_ADHOC_PROFILE_PATH:-.secrets/Crew_Ad_Hoc.mobileprovision}" mobileprovision
echo "▸ Archiving Crew ${VERSION} (${BUILD}) for iOS…"
rm -rf .build/Crew.xcarchive .build/export
xcodebuild "${COMMON[@]}" -destination 'generic/platform=iOS' -archivePath .build/Crew.xcarchive \
  CODE_SIGN_IDENTITY="Apple Distribution" PROVISIONING_PROFILE_SPECIFIER="Crew Ad Hoc" archive
echo "▸ Exporting the Ad Hoc IPA…"
xcodebuild -exportArchive -quiet -archivePath .build/Crew.xcarchive -exportPath .build/export \
  -exportOptionsPlist Signing/ExportOptions-AdHoc.plist
cp .build/export/Crew.ipa .build/export/manifest.plist dist/

payload=$(mktemp -d)
unzip -q dist/Crew.ipa -d "$payload"
check_entitlements "$payload/Payload/Crew.app" aps-environment
rm -rf "$payload"
echo "✅ Built dist/Crew.ipa and dist/manifest.plist"
