#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-webchat-policy.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/WebChatPolicy.swift \
    tests/WebChatPolicyTests.swift -o "$TEST_DIR/webchat-policy-tests"
"$TEST_DIR/webchat-policy-tests"
