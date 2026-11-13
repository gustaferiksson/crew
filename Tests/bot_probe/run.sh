#!/bin/zsh
# Headless bot management probe against the real server: creates, duplicates, files, hides and deletes crew-test-tmp(-2) only. With `rich` it creates crew-test-rich(-bare) through New Bot's steps, checks crew-ui is installed and enabled, then deletes them. With an m4a argument it only sends that to /api/audio/transcribe on crew-test.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
S="$ROOT/Sources"
swiftc -swift-version 6 -default-isolation MainActor -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
  "$S/Gateway.swift" "$S/GatewayTypes.swift" "$S/Hermes.swift" "$S/BotStore.swift" "$S/Profile/ProfileTypes.swift" "$S/Chat/Transcript.swift" "$S/Chat/LimitFailure.swift" "$S/Chat/FailureMetadata.swift" "$S/Chat/Draft.swift" "$S/Groups/GroupStore.swift" "$S/Groups/GroupSession.swift" "$S/Groups/RoomContext.swift" "$S/Groups/ReplyTarget.swift" "$S/Chat/Attachments.swift" "$S/Chat/AttachmentViews.swift" "$S/Chat/ChatSession.swift" "$S/Chat/ContextUsage.swift" "$S/Chat/HistoryPages.swift" "$S/Chat/Payments.swift" "$S/Chat/Composer.swift" "$S/Chat/Dictation.swift" "$S/Chat/RequestCards.swift" "$S/Chat/Mentions.swift" "$S/Chat/SlashCommands.swift" "$S/BotAvatar.swift" "$S/AvatarView.swift" "$S/PokeTracker.swift" "$S/AvatarTaskKey.swift" "$S/AvatarShape.swift" "$S/Chat/ChatSessions.swift" "$S/Push/PushRoute.swift" "$S/Chat/MarkdownBlocks.swift" "$S/Voice/BotAnswer.swift" "$S/Voice/Speaker.swift" "$S/Voice/BotVoices.swift" "$S/AvatarFace.swift" "$S/EyePose.swift" "$S/EyeScript.swift" "$S/SeededGenerator.swift" "$S/NewBotAdvanced.swift" "$S/Profile/CrewUISkill.swift" "$S/Inspector/MCP.swift" \
  "$(dirname "$0")/main.swift" -o "$OUT/botprobe"
cp "$S/Profile/crew-ui.SKILL.md" "$OUT/"
set -a
source "${CREW_ENV_TEST:-$ROOT/.env.test}"
set +a
"$OUT/botprobe" "$@"
