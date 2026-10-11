#!/usr/bin/env bash
#
# Puts the app you just built in /Applications, where you can actually find it.
#
# The build itself lands in ~/Library/Developer/Coucou/Products (see SYMROOT in
# project.yml), which keeps every worktree writing to one bundle — but nothing
# under ~/Library is offered by Spotlight or Launchpad, so the app you build is
# the app you cannot open. This copies it somewhere macOS will show you.
#
# Runs after every Debug build. Silent and harmless when it has no business
# running: no /Applications to write to, on CI, or a Release build, which
# belongs to scripts/release.sh and must not touch the installed copy.
set -euo pipefail

SRC="${BUILT_PRODUCTS_DIR:-}/${WRAPPER_NAME:-Notchy.app}"
DEST="/Applications/${WRAPPER_NAME:-Notchy.app}"

[ "${CONFIGURATION:-Debug}" = "Debug" ] || exit 0
[ -z "${CI:-}" ]                       || exit 0
[ -d "$SRC" ]                          || exit 0
[ -w "$(dirname "$DEST")" ]            || { echo "note: $(dirname "$DEST") is not writable, leaving the installed copy alone"; exit 0; }

# Built beside the target and swapped in, rather than copied over the top: a
# half-written bundle is an app that launches to nothing, and the one being
# replaced may well be running right now.
rm -rf "$DEST.new" "$DEST.old"
ditto "$SRC" "$DEST.new"
[ -d "$DEST" ] && mv "$DEST" "$DEST.old"
mv "$DEST.new" "$DEST"
rm -rf "$DEST.old"

# Without this the first build after a fresh clone leaves an app Spotlight has
# never heard of, which is the whole problem this script exists to solve.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$DEST" 2>/dev/null || true

echo "installed $DEST"
