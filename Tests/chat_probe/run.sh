#!/bin/zsh
# Headless live-chat probe against the real server, crew-test only. Usage: Tests/chat_probe/run.sh <tool|interrupt|queue|steer|clarify|reconnect|attach|peer|late|sync|read|a2ui|history>... (a2ui: installs the crew-ui skill, sends $A2UI_PROMPT)...
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
S="$ROOT/Sources"
swiftc -swift-version 6 -default-isolation MainActor -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
  "$S/Gateway.swift" "$S/GatewayTypes.swift" "$S/Hermes.swift" "$S/BotStore.swift" "$S/Profile/ProfileTypes.swift" "$S/Chat/Transcript.swift" "$S/Chat/Attachments.swift" "$S/Chat/AttachmentViews.swift" "$S/Chat/ChatSession.swift" "$S/Chat/Composer.swift" "$S/Chat/Dictation.swift" "$S/Chat/RequestCards.swift" \
  "$(dirname "$0")/main.swift" -o "$OUT/chatprobe"
set -a
source "$ROOT/.env.test"
set +a
echo "event logs: $OUT"
"$OUT/chatprobe" "$OUT" "$@"
