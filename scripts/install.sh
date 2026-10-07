#!/usr/bin/env bash
# Builds Coucou and puts it in /Applications, where there is an icon to click.
#
#   ./scripts/install.sh              build, install, launch
#   ./scripts/install.sh --uninstall  quit it and take it back out
#
# Coucou has no Dock icon and no window of its own (LSUIElement), so a build
# left in DerivedData is a build nobody can find. From /Applications it behaves
# like any other app: Finder, Launchpad and Spotlight all show it, and the menu
# bar icon is the control once it is running.
#
# The build is unsigned, which is what you want on your own Mac: nothing was
# downloaded, so nothing is quarantined and Gatekeeper does not ask. Signed and
# notarized builds for other people are scripts/release.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/NotchBuddy/build/install"   # gitignored

die() { echo "error: $*" >&2; exit 1; }

MODE="${1:-}"
case "$MODE" in
  ""|--uninstall) ;;
  *) die "unknown option '$MODE' (the only option is --uninstall)" ;;
esac

# PRODUCT_NAME decides the bundle's name, so it decides what to install and what
# to remove. Read it rather than hardcoding it: this repo has been renamed once.
APP_NAME=$(sed -n 's/^ *PRODUCT_NAME: *//p' "$REPO_ROOT/NotchBuddy/project.yml" | head -1)
[ -n "$APP_NAME" ] || die "no PRODUCT_NAME in NotchBuddy/project.yml"
BUNDLE_ID=$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER: *//p' "$REPO_ROOT/NotchBuddy/project.yml" | head -1)

# /Applications is group-writable for admins, so this needs no sudo. On a Mac
# where it is not, ~/Applications is the per-user equivalent and Spotlight and
# Launchpad index it just the same.
if [ -w /Applications ]; then
  DEST_DIR="/Applications"
else
  DEST_DIR="$HOME/Applications"
fi
DEST="$DEST_DIR/$APP_NAME.app"

# Quits the running copy, wherever it was launched from. The AppleEvent is the
# polite ask; the kill is for a copy that is wedged or was never scriptable.
quit_running() {
  pgrep -x "$APP_NAME" >/dev/null 2>&1 || return 0
  echo "Quitting the running copy…"
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || return 0
    sleep 0.5
  done
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  sleep 0.5
}

# ── Uninstall ─────────────────────────────────────────────────────────────────
if [ "$MODE" = "--uninstall" ]; then
  quit_running
  REMOVED=0
  for dir in /Applications "$HOME/Applications"; do
    if [ -d "$dir/$APP_NAME.app" ]; then
      rm -rf "$dir/$APP_NAME.app" || die "could not remove $dir/$APP_NAME.app"
      echo "Removed $dir/$APP_NAME.app"
      REMOVED=1
    fi
  done
  [ "$REMOVED" = 1 ] || echo "$APP_NAME.app was not in /Applications or ~/Applications."
  echo
  echo "Your settings and keys are untouched. To clear those too:"
  if [ -n "$BUNDLE_ID" ]; then echo "  defaults delete $BUNDLE_ID"; fi
  echo "  and remove the Coucou entries in Keychain Access."
  echo "Claude Code hooks, if you installed them, are still in ~/.claude/settings.json."
  exit 0
fi

# ── Build ─────────────────────────────────────────────────────────────────────
command -v xcodegen >/dev/null || die "xcodegen is not installed (brew install xcodegen)"
command -v xcodebuild >/dev/null || die "xcodebuild is not installed (install Xcode)"

cd "$REPO_ROOT/NotchBuddy"
echo "Generating the Xcode project…"
xcodegen generate

rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
LOG="$BUILD_DIR/build.log"
echo "Building $APP_NAME… (the first build takes a few minutes)"
# Thousands of lines of compiler chatter hide the one line that matters, so the
# whole log goes to a file and only errors reach the terminal.
set +e
xcodebuild \
  -project NotchBuddy.xcodeproj \
  -scheme NotchBuddy \
  -configuration Debug \
  build \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  > "$LOG" 2>&1
STATUS=$?
set -e
if [ $STATUS -ne 0 ]; then
  grep -E "error:|fatal error:" "$LOG" | head -20 || true
  die "the build failed. Full log: $LOG"
fi

BUILT="$BUILD_DIR/$APP_NAME.app"
[ -d "$BUILT" ] || die "the build reported success but produced no $APP_NAME.app. Full log: $LOG"

# ── Install ───────────────────────────────────────────────────────────────────
quit_running
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
ditto "$BUILT" "$DEST" || die "could not copy the app into $DEST_DIR"

# Launch Services caches the bundle by path; telling it about the new copy is
# what makes Spotlight and Launchpad find it without a logout.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST" >/dev/null 2>&1 || true

open "$DEST"

cat <<EOF

  ✓ $APP_NAME.app is in $DEST_DIR, and it is running.

  To open it      Click $APP_NAME in Finder, Launchpad or Spotlight (⌘ Space).
                  It is already running, so clicking it again brings Mochi
                  down from the notch — or opens Settings, if Coucou is
                  switched off.
  While it runs   The Mochi icon in the menu bar, next to the clock, has
                  Open, Settings…, the on/off switch and Quit.
  To close it     Menu bar icon → Quit.

  There is no Dock icon and no window: Coucou lives in the notch, and the
  menu bar icon is the handle on it.

  Hooks: menu bar icon → Settings… → Claude Code → Install hooks…

EOF
