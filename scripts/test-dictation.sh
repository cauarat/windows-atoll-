#!/usr/bin/env bash
# Dictation, the apps' side: the protocol reducer, the address parsing, the
# 100 ms framing and the hold-to-talk gesture, all held to
# tests/fixtures/dictation.json — on the Mac (Swift) and in the Windows/Linux
# front end (TypeScript). The service is held to the same file by
# scripts/test-dictation-service.sh, and the Rust gesture by
# dictation_keys.rs under cargo test in the Windows and Linux builds.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-dictation.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
BIN="$TEST_DIR/dictation-tests"
FIXTURE=tests/fixtures/dictation.json
swiftc -swift-version 6 \
    NotchBuddy/Sources/App/DictationProtocol.swift \
    NotchBuddy/Sources/App/DictationHoldGesture.swift \
    NotchBuddy/Sources/App/DictationPCM.swift \
    tests/DictationTests.swift -o "$BIN"
"$BIN" "$FIXTURE"

# Node 22.6+ for --experimental-strip-types. Loudly skipped rather than
# silently passed: a check that quietly stops running is worse than none.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the TypeScript half of this suite did NOT run."
    exit 1
fi
node --no-warnings --experimental-strip-types \
    --import ./tests/extensionless.mjs tests/dictation.ts
