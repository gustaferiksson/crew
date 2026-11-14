#!/bin/zsh
# Headless routine Stop probe against the real server, crew-test only: adds a long routine, runs it, stops it and records Tests/fixtures/scenarios/routine-stop, then removes the routine. `run.sh room`: a throwaway bot in a throwaway room with crew-test, a routine posting into the room (create, edits to local and back, rename and schedule edit, Run Now, disband, Run Now), records Tests/fixtures/scenarios/routine-room, then deletes the bot.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
S="$ROOT/Sources"
swiftc -swift-version 6 -default-isolation MainActor -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
  "$S/Gateway.swift" "$S/GatewayTypes.swift" "$S/Hermes.swift" "$S/Tasks/Routines.swift" "$S/Tasks/RoutineDestination.swift" \
  "$(dirname "$0")/main.swift" -o "$OUT/routineprobe"
set -a
source "${CREW_ENV_TEST:-$ROOT/.env.test}"
set +a
"$OUT/routineprobe" "$@"
