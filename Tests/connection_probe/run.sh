#!/bin/zsh
# Connection page edit probe against the real server, crew-test only: adds deepwiki and a dummy API Key server, switches a tool, changes an address, rotates the dummy key, records Tests/fixtures/mcp/config-raw.v0.23.1.json, then removes both and the dummy key.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
S="$ROOT/Sources"
swiftc -swift-version 6 -default-isolation MainActor -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
  "$S/Gateway.swift" "$S/GatewayTypes.swift" "$S/Hermes.swift" "$S/Inspector/MCP.swift" \
  "$(dirname "$0")/main.swift" -o "$OUT/connectionprobe"
set -a
source "${CREW_ENV_TEST:-$ROOT/.env.test}"
set +a
"$OUT/connectionprobe" "$@"
