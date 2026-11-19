#!/usr/bin/env bash
# Which of the commercial panel's meetings reach the notch, and when — held to
# pages the panel's own Agenda read, names and ids replaced.
#
# Pure on purpose: get the rule wrong and the notch is quiet before a meeting,
# or rings for one that was remarcada, and neither shows from a script run
# against the live panel.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-agenda-rules.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/AgendaRules.swift \
    tests/AgendaRulesTests.swift -o "$TEST_DIR/agenda-rules-tests"
"$TEST_DIR/agenda-rules-tests"

# The island's half: which day it is and when the heads-up comes, on Windows
# and Linux. Node 22.6+ for --experimental-strip-types; loudly skipped rather
# than silently passed.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the island agenda suite did NOT run."
    exit 1
fi
node --no-warnings --experimental-strip-types tests/agenda-rules.ts
