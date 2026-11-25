#!/usr/bin/env bash
# A photo on the message card: which of a post's files it is, and how large
# the card draws it.
#
# The size is a contract between three callers on the Mac — the window, the
# card and Mochi — and between the Mac and Windows, whose card grows by the
# same number. A photo drawn a few points taller than the card was grown for
# pushes the reply bar off the island.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-inbox-photo.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
BIN="$TEST_DIR/inbox-photo-tests"
swiftc NotchBuddy/Sources/App/InboxPhoto.swift \
    NotchBuddy/Sources/App/InboxFile.swift \
    tests/InboxPhotoTests.swift -o "$BIN"
"$BIN"

# The TypeScript twin must agree, value for value.
"$BIN" --dump > "$TEST_DIR/swift-photo-sizes.tsv"

# Node 22.6+ for --experimental-strip-types. Loudly skipped rather than
# silently passed: a check that quietly stops running is worse than none.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the TypeScript half of this suite did NOT run."
    exit 1
fi
TABLE="$TEST_DIR/swift-photo-sizes.tsv" node --no-warnings --experimental-strip-types tests/inbox-photo-parity.ts
