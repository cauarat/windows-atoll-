#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-mochi-character.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
BIN="$TEST_DIR/mochi-character-tests"
swiftc NotchBuddy/Sources/App/EyeShape.swift \
    NotchBuddy/Sources/App/MochiCharacter.swift \
    tests/MochiCharacterTests.swift -o "$BIN"
"$BIN"

# The TypeScript twin must agree, value for value. Two hand-kept ports of the
# same rules drift silently otherwise: the grid is exactly the kind of table
# where one side gains a preset and nobody notices for a release.
"$BIN" --dump > "$TEST_DIR/swift-presets.tsv"

# Node 22.6+ for --experimental-strip-types. Loudly skipped rather than silently
# passed: a check that quietly stops running is worse than no check at all.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the TypeScript half of this suite did NOT run."
    exit 1
fi
CATALOG="$TEST_DIR/swift-presets.tsv" node --no-warnings --experimental-strip-types tests/mochi-character-parity.ts
