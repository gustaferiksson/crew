#!/usr/bin/env bash
# Renders every -snapshot screen to snapshots/ (macOS and iOS light + dark, iOS when an iOS 27 simulator exists). Run ./build.sh first.
set -euo pipefail
cd "$(dirname "$0")"

ALL=( login login-unreachable sidebar sidebar-flat sidebar-draft sidebar-search search-result unreachable avatars avatar-picker chat chat-history chat-selection chat-timestamps chat-worklog chat-question chat-questions chat-questions-snacks chat-offline chat-attachments chat-dictation chat-mentions composer-line composer-lines composer-running composer-running-text chat-steer chat-steer-taken chat-waiting chat-mention-peek chat-mention-chat chat-window chat-window-inspector chat-window-missing chat-a2ui chat-a2ui-cards chat-a2ui-form chat-a2ui-table chat-a2ui-chart chat-a2ui-map layout layout-inspector inspector-info inspector-tasks inspector-routines inspector-look profile-skills bot-page notifications new-bot group-chat group-welcome group-inspector chat-payment chat-payment-holding chat-payment-approved chat-payment-loading chat-payment-failed chat-payment-unverified chat-payment-punycode chat-payment-countdown chat-payment-notice chat-payment-offer chat-payment-receipts inspector-shops inspector-shops-empty inspector-shops-no-card inspector-shops-several add-shop add-shop-error inspector-shops-update-error add-card add-card-invalid replace-card add-card-http add-card-cover inspector-passwords inspector-passwords-empty inspector-passwords-error inspector-passwords-offline inspector-passwords-narrow add-login add-login-invalid edit-login connect-1password )
SCREENS=( "${@:-${ALL[@]}}" )
FIXTURE_ARGS=( -server hermes.example.com -username gustaf )
MAC_APP=.build/Build/Products/Debug/Crew.app/Contents/MacOS/Crew
IOS_APP=.build/Build/Products/Debug-iphonesimulator/Crew.app
mkdir -p snapshots

for screen in "${SCREENS[@]}"; do
  for appearance in Light Dark; do
    suffix=$([[ $appearance == Dark ]] && echo "-dark" || echo "")
    "$MAC_APP" -snapshot "$screen" -AppleInterfaceStyle "$appearance" -ApplePersistenceIgnoreState YES "${FIXTURE_ARGS[@]}" >snapshots/.out 2>/dev/null &
    pid=$!
    ( sleep 20 && kill "$pid" 2>/dev/null ) &
    wait "$pid"
    cp "$(tail -1 snapshots/.out)" "snapshots/macos-${screen}${suffix}.png"
    echo "▸ snapshots/macos-${screen}${suffix}.png"
  done
done
rm -f snapshots/.out

DEVICE=$(xcrun simctl list devices available | awk -v name="${IOS_SIMULATOR:-iPhone 18 Pro}" '/^-- iOS 27/{ios=1; next} /^--/{ios=0} ios && index($0, name " (") {match($0, /[0-9A-F-]{36}/); print substr($0, RSTART, RLENGTH); exit}')
if [[ -z "$DEVICE" ]]; then
  echo "No iOS 27 simulator, skipping iOS snapshots"
  exit 0
fi
WAS_BOOTED=$(xcrun simctl list devices | grep -q "$DEVICE) (Booted" && echo yes || echo no)
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl status_bar "$DEVICE" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl install "$DEVICE" "$IOS_APP"
for appearance in light dark; do
  xcrun simctl ui "$DEVICE" appearance "$appearance"
  suffix=$([[ $appearance == dark ]] && echo "-dark" || echo "")
  for screen in "${SCREENS[@]}"; do
    xcrun simctl terminate "$DEVICE" dev.gustaf.crew 2>/dev/null || true
    rm -f snapshots/.out
    xcrun simctl launch --stdout="$PWD/snapshots/.out" "$DEVICE" dev.gustaf.crew -snapshot "$screen" "${FIXTURE_ARGS[@]}" >/dev/null
    for _ in {1..40}; do grep -q ready snapshots/.out 2>/dev/null && break; sleep 0.5; done
    xcrun simctl io "$DEVICE" screenshot "snapshots/ios-${screen}${suffix}.png" >/dev/null 2>&1
    echo "▸ snapshots/ios-${screen}${suffix}.png"
  done
done
rm -f snapshots/.out
xcrun simctl ui "$DEVICE" appearance light
xcrun simctl terminate "$DEVICE" dev.gustaf.crew 2>/dev/null || true
if [[ $WAS_BOOTED == no ]]; then xcrun simctl shutdown "$DEVICE"; fi
