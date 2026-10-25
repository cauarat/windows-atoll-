#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-claude-account.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/ClaudeAccount.swift \
    tests/ClaudeAccountTests.swift -o "$TEST_DIR/claude-account-tests"
"$TEST_DIR/claude-account-tests"
