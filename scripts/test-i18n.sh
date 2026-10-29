#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Node only, and deliberately: every other suite here compiles a closed list of
# Swift files, so adding a source to one means remembering to add it to the
# other. This checks data, not code, and has nothing to go stale against.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the translation suite did NOT run."
    exit 1
fi

node --no-warnings --experimental-strip-types tests/i18n.ts

# The generated tables are the ones the three platforms actually read, so a
# catalogue edited without regenerating is a translation nobody sees.
echo ""
node scripts/generate-i18n.mjs
