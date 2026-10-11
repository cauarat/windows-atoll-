#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-radial-chord.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/RadialChord.swift \
    tests/RadialChordTests.swift -o "$TEST_DIR/radial-chord-tests"
"$TEST_DIR/radial-chord-tests"
