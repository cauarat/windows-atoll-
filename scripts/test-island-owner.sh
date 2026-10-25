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
