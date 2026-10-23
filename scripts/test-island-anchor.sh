#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-island-anchor.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
BIN="$TEST_DIR/island-anchor-tests"
swiftc NotchBuddy/Sources/App/IslandAnchor.swift \
    tests/IslandAnchorTests.swift -o "$BIN"
"$BIN"

# The TypeScript twin must agree, value for value. Two hand-kept ports of the
# same rules drift silently otherwise, and here that means Rust putting the
# window somewhere the page is not drawing the island.
"$BIN" --dump > "$TEST_DIR/swift-anchor.tsv"

# Node 22.6+ for --experimental-strip-types. Loudly skipped rather than
# silently passed: a check that quietly stops running is worse than none.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the TypeScript half of this suite did NOT run."
    exit 1
fi
TABLE="$TEST_DIR/swift-anchor.tsv" node --no-warnings --experimental-strip-types tests/island-anchor-parity.ts
