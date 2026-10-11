#!/usr/bin/env bash
# The TypeScript half of the island FSM, run against node with a timer shim.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -x windows/node_modules/.bin/tsc ] \
  || { echo "error: run 'npm install' in windows/ first" >&2; exit 1; }
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchy-island-fsm-win.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
windows/node_modules/.bin/tsc \
    windows/src/island/fsm.ts windows/tests/island-fsm.test.ts \
    --outDir "$TEST_DIR" \
    --target es2022 --module es2022 --moduleResolution bundler \
    --strict --skipLibCheck
# tsc emits plain .js; node needs telling they are modules.
echo '{"type":"module"}' > "$TEST_DIR/package.json"
node "$TEST_DIR/tests/island-fsm.test.js"
