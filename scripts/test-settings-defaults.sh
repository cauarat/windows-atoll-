#!/usr/bin/env bash
# Where a fresh install starts and what the Settings fields accept, held to one
# file on both platforms: tests/fixtures/settings-defaults.json. This runs the
# Mac's half and the TypeScript front end's; settings.rs is held to the same
# file by settings_defaults_test.rs, under cargo test in the Windows and Linux
# builds.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-settings-defaults.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
BIN="$TEST_DIR/settings-defaults-tests"
FIXTURE=tests/fixtures/settings-defaults.json
swiftc NotchBuddy/Sources/App/SettingsDefaults.swift \
    NotchBuddy/Sources/App/MessageSource.swift \
    NotchBuddy/Sources/App/HomeContent.swift \
    NotchBuddy/Sources/App/IslandAnchor.swift \
    tests/SettingsDefaultsTests.swift -o "$BIN"
"$BIN" "$FIXTURE"

# Node 22.6+ for --experimental-strip-types. Loudly skipped rather than
# silently passed: a check that quietly stops running is worse than none.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the TypeScript half of this suite did NOT run."
    exit 1
fi
# state.ts imports its neighbours without an extension, as Vite allows and
# Node does not; tests/extensionless.mjs teaches Node to.
node --no-warnings --experimental-strip-types \
    --import ./tests/extensionless.mjs tests/settings-defaults.ts
