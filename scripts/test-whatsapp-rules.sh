#!/usr/bin/env bash
# What the WhatsApp Web bridge reports, and what the inbox makes of it.
#
# The page itself cannot be driven from a script, so the half that can be
# checked is: does every event the bridge sends read back the way it was meant,
# and does the hidden page stay on WhatsApp's own hosts.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-whatsapp-rules.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/WhatsAppRules.swift \
    tests/WhatsAppRulesTests.swift -o "$TEST_DIR/whatsapp-rules-tests"
"$TEST_DIR/whatsapp-rules-tests"
# The bridge must at least parse; a syntax error in it is a page that silently
# never reports anything.
if command -v node >/dev/null 2>&1; then
    node --check shared/whatsapp-bridge.js
    echo "  ✓ shared/whatsapp-bridge.js parses"
fi
