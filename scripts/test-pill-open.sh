#!/usr/bin/env bash
# One click opens the island, two also open the service behind the pill.
#
# Both halves are pure on purpose — whether a click counts as the second one,
# and what "the service" resolves to. The island cannot be clicked from a
# script on this Mac, so a rule left inside the click handler is a rule only
# ever checked by hand.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-pill-open.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/PillOpen.swift \
    tests/PillOpenTests.swift -o "$TEST_DIR/pill-open-tests"
"$TEST_DIR/pill-open-tests"
