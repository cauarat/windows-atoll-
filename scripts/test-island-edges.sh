#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-island-edges.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/IslandEdgeLayout.swift \
    tests/IslandEdgeLayoutTests.swift -o "$TEST_DIR/island-edge-tests"
"$TEST_DIR/island-edge-tests"
