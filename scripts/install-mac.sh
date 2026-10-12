#!/usr/bin/env bash
#
# Puts the app you just built in /Applications, where you can actually find it.
#
# Xcode leaves it in that worktree's DerivedData, which Spotlight and Launchpad
# do not offer — so the app you build is the app you cannot open. This copies it
# somewhere macOS will show you, and because every worktree copies to the same
# place, there is one Notchy.app rather than one per branch.
#
# One bundle means the last build wins, so it is stamped with where it came
# from: Settings shows the branch and commit, and an app that is missing work
# you remember doing says, in words, which branch it was built from. Two
# indistinguishable Notchy.apps is how four days of work went missing once.
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

# Stamped on the installed copy rather than at compile time: the build itself is
# shared between worktrees and must not be invalidated by a branch name, and a
# stamp is only ever asked about for the app somebody opened.
#
# Best-effort throughout. A missing git, a detached HEAD or a read-only plist
# must not fail a build that has already succeeded.
BRANCH=$(git -C "$PROJECT_DIR/.." rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
COMMIT=$(git -C "$PROJECT_DIR/.." rev-parse --short HEAD 2>/dev/null || echo "?")
DIRTY=$(git -C "$PROJECT_DIR/.." status --porcelain 2>/dev/null | head -1)
[ -n "$DIRTY" ] && COMMIT="$COMMIT+"

PLIST="$DEST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NotchyBuildBranch string $BRANCH" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :NotchyBuildBranch $BRANCH" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NotchyBuildCommit string $COMMIT" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :NotchyBuildCommit $COMMIT" "$PLIST" 2>/dev/null || true

echo "installed $DEST ($BRANCH $COMMIT)"
