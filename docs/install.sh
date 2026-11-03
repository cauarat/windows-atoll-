#!/usr/bin/env bash
#
# Installs Notchy for macOS, with no Gatekeeper dialog to get past.
#
#   curl -fsSL https://cauarat.github.io/windows-atoll-/install.sh | bash
#
# This is not a Gatekeeper bypass and it turns nothing off. `com.apple.quarantine`
# is set by whatever *downloads* a file — browsers and Mail opt into it through
# LSFileQuarantineEnabled. curl does not. So the copy this leaves in Applications
# was never flagged, Gatekeeper never assesses it, and the app simply opens. The
# exception is this one app, made once, by someone who asked for it; nothing here
# touches the setting that protects every other download.
#
# The .dmg from the download page is the same build. It arrives through a browser,
# so it *is* flagged, and the first open needs one trip through System Settings >
# Privacy & Security > Open Anyway. That route is fine too — this one is shorter.
#
# Notchy carries no Apple Developer ID either way: nobody at Apple has looked at
# it. What you are trusting is this repository and the GitHub Actions run that
# built the release, both of which are public.
set -euo pipefail

# The trap runs after main() returns, so what it touches cannot be local to main.
TMP=""
MOUNT=""
cleanup() {
  if [ -n "$MOUNT" ]; then hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; fi
  if [ -n "$TMP" ]; then rm -rf "$TMP"; fi
}
trap cleanup EXIT

# Everything lives in a function so that a connection dropped halfway down this
# file cannot leave bash executing half an installer.
main() {
  local REPO="cauarat/windows-atoll-"
  local APP="Notchy"
  local STABLE="https://github.com/$REPO/releases/download/mac-latest/Notchy-macOS.dmg"
  local SUMS="https://github.com/$REPO/releases/download/mac-latest/SHA256SUMS"

  say()  { printf '  %s\n' "$*"; }
  die()  { printf '\n  error: %s\n\n' "$*" >&2; exit 1; }

  printf '\n  Notchy — installing\n\n'

  # ── 1. Is this even a Mac that can run it ───────────────────────────────────
  [ "$(uname -s)" = "Darwin" ] || die "this installs the macOS build, and this is not a Mac."
  local V MAJOR
  V=$(sw_vers -productVersion)
  MAJOR=${V%%.*}
  [ "$MAJOR" -ge 15 ] 2>/dev/null \
    || die "Notchy needs macOS 15 or later; this is macOS $V."

  for t in curl hdiutil ditto shasum; do
    command -v "$t" >/dev/null || die "$t is missing, and this cannot run without it."
  done

  # ── 2. Somewhere to work, cleaned up whatever happens ───────────────────────
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/notchy-install.XXXXXX")

  # ── 3. Fetch the disk image ─────────────────────────────────────────────────
  #
  # The rolling mac-latest release is the stable name. Before the first one is
  # published it does not exist, so fall back to the newest mac-v* release the
  # API reports rather than failing on a 404 nobody can act on.
  local DMG="$TMP/Notchy.dmg" URL="$STABLE"
  say "Downloading $APP…"
  if ! curl -fsSL --retry 3 --retry-delay 1 -o "$DMG" "$URL" 2>/dev/null; then
    say "(no rolling release yet — taking the newest tagged build instead)"
    curl -fsSL -o "$TMP/releases.json" \
      "https://api.github.com/repos/$REPO/releases?per_page=30" 2>/dev/null \
      || die "could not reach GitHub. Check your network, or grab the .dmg by hand from https://github.com/$REPO/releases"
    URL=$(awk -F'"' '/"browser_download_url"/ && /\.dmg"/ {print $4; exit}' "$TMP/releases.json")
    [ -n "$URL" ] || die "could not find a macOS build to download. Check https://github.com/$REPO/releases"
    SUMS=""
    curl -fsSL --retry 3 --retry-delay 1 -o "$DMG" "$URL" 2>/dev/null \
      || die "the download failed. Check your network, or grab the .dmg by hand from https://github.com/$REPO/releases"
  fi
  [ -s "$DMG" ] || die "the downloaded file is empty."

  # ── 4. Check it arrived whole ───────────────────────────────────────────────
  #
  # TLS already covers the transport; this catches a truncated or swapped file
  # and gives the download page something it can honestly tell people to verify.
  local GOT WANT=""
  GOT=$(shasum -a 256 "$DMG" | awk '{print $1}')
  if [ -n "$SUMS" ]; then
    WANT=$(curl -fsSL "$SUMS" 2>/dev/null | awk '/Notchy-macOS\.dmg$/ {print $1; exit}') || true
  fi
  if [ -n "$WANT" ]; then
    [ "$GOT" = "$WANT" ] || die "checksum mismatch — the download does not match what the release published.
         expected $WANT
         got      $GOT
         Nothing was installed."
    say "Checksum verified."
  else
    say "No published checksum for this build; the download came over HTTPS from GitHub."
    say "SHA-256: $GOT"
  fi

  # ── 5. Mount, and put it where it belongs ───────────────────────────────────
  MOUNT="$TMP/mnt"
  mkdir -p "$MOUNT"
  hdiutil attach "$DMG" -nobrowse -readonly -noverify -mountpoint "$MOUNT" -quiet \
    || die "could not open the disk image."
  [ -d "$MOUNT/$APP.app" ] || die "the disk image does not contain $APP.app."

  # /Applications is group-writable by admin on a stock Mac, so this needs no
  # sudo. When it is not — a managed Mac, a standard account — ~/Applications is
  # a real install location that macOS treats the same way, and the app's own
  # location check accepts it.
  local DEST="/Applications"
  if [ ! -w "$DEST" ]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
    say "/Applications is not writable; installing to $DEST instead."
  fi

  # A running copy has to go first, or ditto replaces files under a live process
  # and the result is a bundle that is half old and half new.
  if pgrep -x "$APP" >/dev/null 2>&1; then
    say "Quitting the copy that is running…"
    osascript -e "tell application \"$APP\" to quit" >/dev/null 2>&1 || true
    local n=0
    while pgrep -x "$APP" >/dev/null 2>&1 && [ $n -lt 20 ]; do sleep 0.25; n=$((n+1)); done
    pkill -x "$APP" 2>/dev/null || true
  fi

  say "Installing to $DEST/$APP.app…"
  rm -rf "$DEST/$APP.app.old"
  if [ -d "$DEST/$APP.app" ]; then mv "$DEST/$APP.app" "$DEST/$APP.app.old"; fi
  if ! ditto "$MOUNT/$APP.app" "$DEST/$APP.app"; then
    if [ -d "$DEST/$APP.app.old" ]; then mv "$DEST/$APP.app.old" "$DEST/$APP.app"; fi
    die "the copy failed; the previous version was left in place."
  fi
  rm -rf "$DEST/$APP.app.old"

  hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  MOUNT=""

  # ── 6. Open it ──────────────────────────────────────────────────────────────
  # No xattr call anywhere above, and that is the point: there is no quarantine
  # flag on this copy to remove, because curl never set one.
  open -a "$DEST/$APP.app" || die "installed, but could not open it. Open $APP from Applications."

  cat <<EOF

  $APP is installed at $DEST/$APP.app and opening now.

  Mochi appears in the notch — or in a small bar at the top of the screen on a
  Mac without one. There is no Dock icon and no window.

  It will ask for Accessibility and, if you record a voice note, the microphone.
  Updates arrive by themselves from inside the app.

EOF
}

main "$@"
