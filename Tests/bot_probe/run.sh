#!/bin/zsh
# Headless bot management probe against the real server: creates, duplicates, files and deletes crew-test-tmp(-2) only. With an m4a argument it only sends that to /api/audio/transcribe on crew-test.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
S="$ROOT/Sources"
swiftc -swift-version 6 -default-isolation MainActor -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
  "$S/Gateway.swift" "$S/GatewayTypes.swift" "$S/Hermes.swift" "$S/BotStore.swift" "$S/Profile/ProfileTypes.swift" \
  "$(dirname "$0")/main.swift" -o "$OUT/botprobe"
set -a
source "$ROOT/.env.test"
set +a
"$OUT/botprobe" "$@"
