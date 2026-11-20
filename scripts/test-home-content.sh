#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-home-content.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
BIN="$TEST_DIR/home-content-tests"
swiftc NotchBuddy/Sources/App/MessageSource.swift \
    NotchBuddy/Sources/App/HomeContent.swift \
    tests/HomeContentTests.swift -o "$BIN"
"$BIN"

# The TypeScript twin must agree: the same choices in the same order, the same
# words under each, the same default. It had drifted once already, with nothing
# to say so — Windows never had "Notifications" at all.
"$BIN" --dump > "$TEST_DIR/swift-home.tsv"

# Node 22.6+ for --experimental-strip-types. Loudly skipped rather than
# silently passed: a check that quietly stops running is worse than none.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the TypeScript half of this suite did NOT run."
    exit 1
fi
# state.ts imports its neighbours without an extension, as Vite allows and
# Node does not; tests/extensionless.mjs teaches Node to.
HOME_DUMP="$TEST_DIR/swift-home.tsv" node --no-warnings --experimental-strip-types \
    --import ./tests/extensionless.mjs tests/home-content-parity.ts
