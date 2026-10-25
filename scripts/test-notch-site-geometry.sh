#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-notch-site.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/NotchSiteGeometry.swift \
    tests/NotchSiteGeometryTests.swift -o "$TEST_DIR/notch-site-tests"
"$TEST_DIR/notch-site-tests"
