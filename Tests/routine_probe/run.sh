#!/bin/zsh
# Headless routine Stop probe against the real server, crew-test only: adds a long routine, runs it, stops it and records Tests/fixtures/scenarios/routine-stop, then removes the routine.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
S="$ROOT/Sources"
swiftc -swift-version 6 -default-isolation MainActor -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
  "$S/Gateway.swift" "$S/GatewayTypes.swift" "$S/Hermes.swift" "$S/Tasks/Routines.swift" \
  "$(dirname "$0")/main.swift" -o "$OUT/routineprobe"
set -a
source "${CREW_ENV_TEST:-$ROOT/.env.test}"
set +a
"$OUT/routineprobe" "$@"
