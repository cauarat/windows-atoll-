#!/bin/bash
# Captures the Mac Settings window, pane by pane, in light and dark: the
# reference the Windows port is held to (docs/parity/, windows/dev/compare.html).
#
#   bash scripts/capture-mac-reference.sh                  # every pane, both schemes
#   SECTIONS="general chat" SCHEMES=dark bash scripts/capture-mac-reference.sh
#
# Needs a Debug build installed at /Applications/Notchy.app — any
# `xcodebuild -configuration Debug build` installs itself there — because the
# environment hooks it relies on (AppDelegate.applyReferenceCaptureOverrides)
# are compiled into Debug only. The screen must be unlocked: a locked Mac
# captures black.
#
# It quits the running Notchy, relaunches it once per capture, and leaves it
# running normally at the end with the sidebar and island tab it had before.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP=${APP:-/Applications/Notchy.app}
OUT=${OUT:-$ROOT/design/captures/parity/settings}
SECTIONS=${SECTIONS:-"general activepills island radial aiagents chat integrations characters hydration"}
SCHEMES=${SCHEMES:-"light dark"}
ISLAND_TABS=${ISLAND_TABS:-"layout content activity behavior"}
BUNDLE=$(defaults read "$APP/Contents/Info" CFBundleIdentifier)

# Read whole, not piped into `grep -q`: under pipefail, grep leaving early
# kills nm with SIGPIPE and the check fails on a build that has the hooks.
symbols=$(nm -U "$APP"/Contents/MacOS/* 2>/dev/null || true)
if ! grep -q applyReferenceCaptureOverrides <<<"$symbols"; then
    echo "✗ $APP is not a Debug build with the capture hooks." >&2
    echo "  cd NotchBuddy && xcodebuild -scheme NotchBuddy -configuration Debug build" >&2
    exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/window-id.swift" <<'SWIFT'
import CoreGraphics
import Foundation
// The Settings window: an ordinary (layer 0) Notchy window at least 640 wide
// (its minimum). The island is a panel at a higher level, and Notchy also keeps
// a small helper window parked far off-screen; neither matches.
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in windows where (w[kCGWindowOwnerName as String] as? String) == "Notchy"
    && (w[kCGWindowLayer as String] as? Int) == 0 {
    if let bounds = w[kCGWindowBounds as String] as? [String: Double],
       (bounds["Width"] ?? 0) >= 640, (bounds["X"] ?? 0) > -10000 {
        print(w[kCGWindowNumber as String] as? Int ?? 0)
        break
    }
}
SWIFT
swiftc -O -o "$TMP/window-id" "$TMP/window-id.swift" 2>/dev/null

saved_section=$(defaults read "$BUNDLE" settingsSection 2>/dev/null || echo general)
saved_tab=$(defaults read "$BUNDLE" islandTab 2>/dev/null || echo layout)

quit_app() {
    osascript -e "tell application id \"$BUNDLE\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do pgrep -x Notchy >/dev/null || return 0; sleep 0.2; done
    pkill -x Notchy || true
    sleep 0.5
}

# LaunchServices answers -600 for a moment after the previous copy quits, so a
# launch straight after a quit is retried rather than taken as final.
launch() {
    for _ in 1 2 3 4 5 6; do
        open -a "$APP" "$@" 2>/dev/null && return 0
        sleep 1
    done
    echo "  ✗ could not launch $APP" >&2
    return 1
}

capture() { # scheme section tab file
    local scheme=$1 section=$2 tab=$3 file=$4
    quit_app
    local envs=(--env "NOTCHY_APPEARANCE=$scheme" --env "NOTCHY_SETTINGS_SECTION=$section")
    [ -n "$tab" ] && envs+=(--env "NOTCHY_ISLAND_TAB=$tab")
    launch "${envs[@]}"
    # Settings opens once the launch greeting has run: about 18 s on this Mac.
    local id=""
    for _ in $(seq 1 180); do
        id=$("$TMP/window-id")
        [ -n "$id" ] && break
        sleep 0.25
    done
    if [ -z "$id" ]; then echo "  ✗ $file: Settings never appeared" >&2; return 1; fi
    sleep 1.2   # let the pane lay out and any live list load
    screencapture -x -o -l "$id" "$file"
    echo "  ✓ ${file#$ROOT/}"
}

mkdir -p "$OUT"
for scheme in $SCHEMES; do
    for section in $SECTIONS; do
        if [ "$section" = island ]; then
            for tab in $ISLAND_TABS; do
                capture "$scheme" island "$tab" "$OUT/island-$tab-$scheme.png"
            done
        else
            capture "$scheme" "$section" "" "$OUT/$section-$scheme.png"
        fi
    done
done

quit_app
defaults write "$BUNDLE" settingsSection -string "$saved_section"
defaults write "$BUNDLE" islandTab -string "$saved_tab"
launch
echo "Done: $OUT"
