#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-media-text.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
BIN="$TEST_DIR/media-text-tests"
swiftc NotchBuddy/Sources/App/MediaText.swift tests/MediaTextTests.swift -o "$BIN"
"$BIN"

# The TypeScript twin must clean every title and artist exactly as the Mac does:
# the card and the pill show what comes out, on both platforms.
"$BIN" --dump > "$TEST_DIR/swift-media-text.tsv"

# Node 22.6+ for --experimental-strip-types. Loudly skipped rather than
# silently passed: a check that quietly stops running is worse than none.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the TypeScript half of this suite did NOT run."
    exit 1
fi
MEDIA_TEXT_DUMP="$TEST_DIR/swift-media-text.tsv" node --no-warnings --experimental-strip-types \
    --import ./tests/extensionless.mjs tests/media-text-parity.ts
