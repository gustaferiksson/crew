#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

presenters='^Sources/(BotsView|Chat/ChatFixtures|Chat/ChatScreen|Chat/ChatView|Chat/Composer|Chat/PaymentSnapshots|Chat/UserBubble|Inspector/BotInspector|Inspector/InspectorSnapshots|Profile/ProfileSnapshots)\.swift:'
failed=0

search() {
  grep -rnE --include='*.swift' "$1" Sources Widgets || true
}

report() {
  [[ -z "$1" ]] && return
  printf '%s\n✗ %s\n\n' "$1" "$2"
  failed=1
}

report "$(search '\.(sheet|popover|fullScreenCover)\(' | grep -vE "$presenters" || true)" \
  "Present sheets, popovers and full-screen covers only from a screen container (PLAN.md Decisions, #222); allowlist a file in scripts/lint-ui.sh only if it is one."
report "$(search '\bAsyncImage[[:space:]]*[({]')" \
  "AsyncImage loses its image when a lazy stack recycles the row (#134); use CachedImage."
report "$(search '\bScrollViewReader\b')" \
  "ScrollViewReader lands short in a long lazy stack (#152); scroll through TranscriptScroll's ScrollPosition."
report "$(grep -rnE --include='*.swift' '\b(NSWindow|NSPanel)\(|class [A-Za-z]+: (NSWindow|NSPanel)\b' Tests/CrewTests | grep -v '^Tests/CrewTests/OffscreenWindow.swift:' || true)" \
  "A plain NSWindow in a test lands on the user's screen when ordered in; host test views in OffscreenWindow."

[[ $failed == 0 ]] && echo "✓ UI lint passed"
exit $failed
