#!/usr/bin/env bash
# Where the app is allowed to run from, and what it does when it is somewhere
# else.
#
# Pure on purpose: the alert, the ditto and the relaunch need a .dmg, a Finder
# and a pair of hands, so a rule left inside them is a rule only ever checked by
# dragging a disk image around. InstallLocation.swift holds the decision and
# imports nothing but Foundation, which is what lets swiftc compile it alone.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-install-location.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/InstallLocation.swift \
    tests/InstallLocationTests.swift -o "$TEST_DIR/install-location-tests"
"$TEST_DIR/install-location-tests"
