#!/usr/bin/env bash
# One Coucou at a time: whose character the island is wearing.
#
# The island draws a single Mochi over every view, and he used to take his
# position from `state.view` and his face from whoever held focus. Clicking
# Mattermost and then Now Playing moved the focus without moving the view, so
# Now Playing's red heart and sprout ended up inside Mattermost's list.
#
# Against the old focus-always rule this suite reports five failures; against
# IslandOwner it is green. That gap is the point of it.
#
# It also carries `IslandView.messageHeight`, which lives in IslandTypes.swift
# and is already compiled in here — and the TypeScript twin of it, because the
# card's cap is the Mac's number copied by hand onto a platform that has
# nothing to derive it from.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-island-owner.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/IslandOwner.swift \
    NotchBuddy/Sources/App/IslandTypes.swift \
    NotchBuddy/Sources/App/EyeShape.swift \
    NotchBuddy/Sources/App/HomeContent.swift \
    NotchBuddy/Sources/App/IslandScreenGeometry.swift \
    NotchBuddy/Sources/App/MessageSource.swift \
    tests/IslandOwnerTests.swift -o "$TEST_DIR/island-owner-tests"
"$TEST_DIR/island-owner-tests"

# The TypeScript twin must agree, value for value. Two hand-kept ports of the
# same rules drift silently otherwise, and here that means a message card that
# stops growing at the wrong height on one platform.
"$TEST_DIR/island-owner-tests" --dump > "$TEST_DIR/swift-heights.tsv"

# Node 22.6+ for --experimental-strip-types. Loudly skipped rather than
# silently passed: a check that quietly stops running is worse than none.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the TypeScript half of this suite did NOT run."
    exit 1
fi
TABLE="$TEST_DIR/swift-heights.tsv" node --no-warnings --experimental-strip-types tests/message-height-parity.ts
