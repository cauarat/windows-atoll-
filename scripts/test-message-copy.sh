#!/usr/bin/env bash
# Copy on a message card: what it copies — the words, the photo or the voice
# message the sender sent, never what the card says about them — and what an
# app pasting it finds on the clipboard.
#
# The clipboard half writes to a pasteboard of its own, so running this never
# touches what the user has copied.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-message-copy.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
BIN="$TEST_DIR/message-copy-tests"
swiftc NotchBuddy/Sources/App/InboxPhoto.swift \
    NotchBuddy/Sources/App/InboxAudio.swift \
    NotchBuddy/Sources/App/MessageCopy.swift \
    NotchBuddy/Sources/App/MessagePasteboard.swift \
    tests/MessageCopyTests.swift -o "$BIN"
# AppKit says it could not consume a sandbox extension when a file URL is read
# back off a pasteboard; nothing here is sandboxed, so that line is noise.
"$BIN" 2> >(grep -v "sandbox_extension_consume" >&2)

# The TypeScript twin must agree on what each card copies.
"$BIN" --dump > "$TEST_DIR/swift-copy.tsv"

# Node 22.6+ for --experimental-strip-types. Loudly skipped rather than
# silently passed: a check that quietly stops running is worse than none.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the TypeScript half of this suite did NOT run."
    exit 1
fi
TABLE="$TEST_DIR/swift-copy.tsv" node --no-warnings --experimental-strip-types tests/message-copy-parity.ts
