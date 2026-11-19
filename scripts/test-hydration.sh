#!/usr/bin/env bash
# The hydration rules: who gets an estimate and how much, which day a glass
# belongs to, how the streak forgives a missed day, and when the next reminder
# is due.
#
# Pure on purpose: a wrong number here is a goal nobody asked for or a reminder
# in the middle of the night, and neither shows from watching the island.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-hydration.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
BIN="$TEST_DIR/hydration-tests"
swiftc NotchBuddy/Sources/App/Hydration.swift \
    tests/HydrationTests.swift -o "$BIN"
"$BIN"

# The TypeScript twin has to give the same answers. Both sides run one script
# and this compares what they saw.
"$BIN" --dump > "$TEST_DIR/swift-hydration.tsv"

# Node 22.6+ for --experimental-strip-types. Loudly skipped rather than silently
# passed: a check that quietly stops running is worse than no check at all.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the TypeScript half of this suite did NOT run."
    exit 1
fi
TZ=UTC HYDRATION_DUMP="$TEST_DIR/swift-hydration.tsv" node --no-warnings --experimental-strip-types tests/hydration-parity.ts
