#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-home-content.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/MessageSource.swift \
    NotchBuddy/Sources/App/HomeContent.swift \
    tests/HomeContentTests.swift -o "$TEST_DIR/home-content-tests"
"$TEST_DIR/home-content-tests"
