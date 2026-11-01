#!/bin/zsh
# Headless live-chat probe against the real server, crew-test only. Usage: Tests/chat_probe/run.sh <tool|voice|think|interrupt|queue|steer|clarify|reconnect|attach|peer|late|sync|read|cleared|a2ui|history|mention|slash|fresh|cold-open|first|routine|compressed|room-history>... (room-history: a throwaway room with crew-test, eight rounds and a Compress, writes Tests/fixtures/rooms) (compressed: two Compact Chats then a turn on crew-test, events in <logs>/compressed-turn.jsonl) (slash: records Tests/fixtures/commands.catalog for crew-test) (first: a throwaway bot's first turn, events in <logs>/first-turn.jsonl) (routine: records routine-delivery, one bot-chat routine run on a throwaway; it pushes to the user's devices) (a2ui: installs the crew-ui skill, sends $A2UI_PROMPT), or record <scenario> (writes Tests/fixtures/scenarios/<scenario>, see Tests/README.md)
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
S="$ROOT/Sources"
swiftc -swift-version 6 -default-isolation MainActor -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
  "$S/Gateway.swift" "$S/GatewayTypes.swift" "$S/Hermes.swift" "$S/BotStore.swift" "$S/Profile/ProfileTypes.swift" "$S/Chat/Transcript.swift" "$S/Chat/Attachments.swift" "$S/Chat/AttachmentViews.swift" "$S/Chat/ChatSession.swift" "$S/Chat/ChatSessions.swift" "$S/Chat/Composer.swift" "$S/Chat/Dictation.swift" "$S/Chat/RequestCards.swift" "$S/Chat/Payments.swift" "$S/Push/PushRoute.swift" "$S/Chat/Mentions.swift" "$S/Chat/SlashCommands.swift" "$S/BotAvatar.swift" "$S/AvatarView.swift" "$S/AvatarShape.swift" \
  "$(dirname "$0")/main.swift" -o "$OUT/chatprobe"
set -a
source "${CREW_ENV_TEST:-$ROOT/.env.test}"
set +a
echo "event logs: $OUT"
"$OUT/chatprobe" "$OUT" "$@"
