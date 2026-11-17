#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Node only: the Christmas parts are data, generated once for both platforms,
# so what can go wrong is the data — a part missing for one body, a name with no
# translation, a path the Swift parser was never taught — and not code drifting
# between Swift and TypeScript, which the generator rules out by construction.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the festive suite did NOT run."
    exit 1
fi

# A generator edited without --write is a hat only one platform has.
node scripts/generate-mochi-festive.mjs

node --no-warnings tests/mochi-festive.mjs
