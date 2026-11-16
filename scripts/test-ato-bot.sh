#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-ato-bot.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
BIN="$TEST_DIR/ato-bot-tests"
swiftc NotchBuddy/Sources/App/AtoBot.swift NotchBuddy/Sources/App/EyeShape.swift tests/AtoBotTests.swift -o "$BIN"
"$BIN"

# Both ports against Actuar's own engine (design/ato/actuar-bot-v3.js), run
# under Node on every input the Swift side printed.
"$BIN" --dump > "$TEST_DIR/ato-dump.tsv"

# Node 22.6+ for --experimental-strip-types. Loudly skipped rather than silently
# passed: a check that quietly stops running is worse than no check at all.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the parity half of this suite did NOT run."
    exit 1
fi
echo ""
ATO_DUMP="$TEST_DIR/ato-dump.tsv" node --no-warnings --experimental-strip-types tests/ato-bot-parity.ts
