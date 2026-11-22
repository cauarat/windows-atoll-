#!/usr/bin/env bash
# The Settings sidebar: the same rows, in the same order, with the same titles,
# symbols and colours on a Mac and on Windows — and on Windows, only the panes
# that are not ported yet hidden.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-settings-sections.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
BIN="$TEST_DIR/settings-section-tests"
swiftc NotchBuddy/Sources/App/SettingsSection.swift \
    tests/SettingsSectionTests.swift -o "$BIN"
"$BIN"

# The TypeScript twin must agree, row for row. Two hand-kept copies of one
# table drift silently otherwise, and here that is a window that looks almost
# like the Mac's.
"$BIN" --dump > "$TEST_DIR/swift-sections.tsv"

# Node 22.6+ for --experimental-strip-types. Loudly skipped rather than
# silently passed: a check that quietly stops running is worse than none.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the TypeScript half of this suite did NOT run."
    exit 1
fi
SECTIONS_DUMP="$TEST_DIR/swift-sections.tsv" node --no-warnings --experimental-strip-types tests/settings-sections-parity.ts
