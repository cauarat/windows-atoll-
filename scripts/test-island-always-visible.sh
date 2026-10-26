#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Node 22.6+ for --experimental-strip-types. Loudly skipped rather than
# silently passed: a check that quietly stops running is worse than none.
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
if [ -z "${NODE_MAJOR:-}" ] || [ "$NODE_MAJOR" -lt 22 ]; then
    echo ""
    echo "  ! node 22+ not found — the island visibility suite did NOT run."
    exit 1
fi

node --no-warnings --experimental-strip-types tests/island-always-visible.ts
