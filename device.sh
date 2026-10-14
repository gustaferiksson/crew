#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f .env ]]; then
  set -a
  source ./.env
  set +a
fi

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM in .env}"
DEVICE="${DEVICE:-$(xcrun devicectl list devices | awk '/(connected|available)/ && /physical/ { for (i = 1; i < NF; i++) if ($(i + 1) == "(UDID)") { print $i; exit } }')}"
: "${DEVICE:?No paired iPhone found (xcrun devicectl list devices)}"

MARKETING_VERSION="${MARKETING_VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)-local}"

echo "▸ Generating Xcode project…"
xcodegen generate --quiet

echo "▸ Building iOS for ${DEVICE}…"
log=$(mktemp)
if ! xcodebuild -project Crew.xcodeproj -scheme Crew -configuration Debug -derivedDataPath .build -skipPackagePluginValidation -skipMacroValidation \
  -destination 'generic/platform=iOS' "DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM}" "MARKETING_VERSION=${MARKETING_VERSION}" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build >"$log" 2>&1; then
  grep -E 'error:' "$log" | sort -u || tail -40 "$log"
  exit 1
fi

echo "▸ Installing…"
xcrun devicectl device install app --device "$DEVICE" .build/Build/Products/Debug-iphoneos/Crew.app \
  || xcrun devicectl device install app --device "$DEVICE" .build/Build/Products/Debug-iphoneos/Crew.app

echo "▸ Launching…"
xcrun devicectl device process launch --device "$DEVICE" dev.gustaf.crew
