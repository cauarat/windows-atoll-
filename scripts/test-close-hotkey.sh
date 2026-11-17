#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-close-hotkey.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/CloseHotKey.swift \
    tests/CloseHotKeyTests.swift -o "$TEST_DIR/close-hotkey-tests"
"$TEST_DIR/close-hotkey-tests"
