#!/usr/bin/env bash
# The first-run welcome and the name Mochi greets you by: the Swift rules, then
# the TypeScript twins held to the same answers.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-welcome.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
BIN="$TEST_DIR/welcome-tests"
swiftc NotchBuddy/Sources/App/UserIdentity.swift \
    NotchBuddy/Sources/App/Onboarding.swift \
    tests/WelcomeTests.swift -o "$BIN"
"$BIN"

# The Windows and Linux app greets with the same rules. The Swift side dumps
# every input it checks; the TypeScript side replays them.
"$BIN" --dump > "$TEST_DIR/welcome.json"

# Node 22.6+ for --experimental-strip-types. Loudly skipped rather than silently
# passed: a check that quietly stops running is worse than no check at all.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the TypeScript half of this suite did NOT run."
    exit 1
fi
WELCOME_DUMP="$TEST_DIR/welcome.json" node --no-warnings --experimental-strip-types tests/welcome-parity.ts
