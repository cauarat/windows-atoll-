#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Node only, like the translation suite and for the same reason: this compares
# two declared tables, not code. SettingsView.swift has no unit to compile
# against — it is the whole window — so there is nothing here for swiftc to do.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the settings parity suite did NOT run."
    exit 1
fi

node --no-warnings --experimental-strip-types tests/settings-parity.ts
