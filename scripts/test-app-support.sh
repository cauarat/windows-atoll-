#!/usr/bin/env bash
# The retired hook relay: an nb-hook a user still has registered keeps finishing at once.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchy-app-support.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/AppSupport.swift \
    tests/AppSupportTests.swift -o "$TEST_DIR/app-support-tests"
"$TEST_DIR/app-support-tests"
