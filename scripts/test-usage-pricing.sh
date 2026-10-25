#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-usage-pricing.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/ClaudeUsagePricing.swift \
    tests/ClaudeUsagePricingTests.swift -o "$TEST_DIR/usage-pricing-tests"
"$TEST_DIR/usage-pricing-tests"
