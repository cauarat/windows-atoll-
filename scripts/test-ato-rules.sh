#!/usr/bin/env bash
# Which Ato messages reach the notch, held to frames captured off the real hub.
#
# The rule is pure on purpose: the hub carries a whole workspace, so a filter
# that is wrong either keeps the notch silent or fills it with every colleague's
# WhatsApp, and neither can be checked from a script against the live service.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-ato-rules.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/AtoRules.swift \
    NotchBuddy/Sources/App/InboxFile.swift \
    NotchBuddy/Sources/App/InboxAudio.swift \
    NotchBuddy/Sources/App/SignalRConnection.swift \
    tests/AtoRulesTests.swift -o "$TEST_DIR/ato-rules-tests"
"$TEST_DIR/ato-rules-tests"
