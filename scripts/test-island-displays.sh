#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-island-displays.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/IslandDisplays.swift \
    tests/IslandDisplaysTests.swift -o "$TEST_DIR/island-display-tests"
"$TEST_DIR/island-display-tests"
