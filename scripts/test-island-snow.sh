#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-island-snow.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
BIN="$TEST_DIR/island-snow-tests"
swiftc NotchBuddy/Sources/App/IslandSnow.swift \
    tests/IslandSnowTests.swift -o "$BIN"
"$BIN"

# The TypeScript twin has to plough the same snow. Both sides run one script —
# open, sweep, rest, sweep back, leave, close — and this compares what they saw.
"$BIN" --dump > "$TEST_DIR/swift-snow.tsv"

# Node 22.6+ for --experimental-strip-types. Loudly skipped rather than silently
# passed: a check that quietly stops running is worse than no check at all.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the TypeScript half of this suite did NOT run."
    exit 1
fi
SNOW_DUMP="$TEST_DIR/swift-snow.tsv" node --no-warnings --experimental-strip-types tests/island-snow-parity.ts
