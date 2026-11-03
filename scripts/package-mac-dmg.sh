#!/usr/bin/env bash
#
# Builds Notchy for macOS and puts it in a .dmg you can hand to someone.
#
# This is the only way a release is cut; .github/workflows/macos-release.yml
# runs it, then scripts/make-appcast.sh writes the feed installed copies update
# from.
#
# The result is NOT signed by an identified developer and NOT notarized, because
# there is no Apple Developer ID behind this project. Say so wherever it is
# offered — docs/download.html does, and it also offers the shorter route:
# curl sets no quarantine flag, so a copy installed by scripts/install.sh at
# docs/install.sh is never assessed by Gatekeeper at all.
#
# Why it signs at all: Xcode leaves the bundle `linker-signed`, which has no
# _CodeSignature directory. Copied to another Mac that bundle is reported as
# *damaged* and there is no way past it. A real ad-hoc signature turns that dead
# end into the ordinary "unidentified developer" prompt, which the user can get
# through. That is the whole reason for the codesign step below.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="${1:-dist}"
SCHEME=NotchBuddy
APP_NAME=Notchy

say() { printf '\n  %s\n' "$*"; }
die() { printf '\n  error: %s\n\n' "$*" >&2; exit 1; }

# ── 1. Build ──────────────────────────────────────────────────────────────────
#
# No SYMROOT: a custom one is a legacy build location and Swift packages —
# Sparkle, for the updater — are refused in that mode. Release, so the debug
# dylib and the preview stub stay out of what ships.
# Signing is turned off for the build itself and done by hand in step 2.
# Release otherwise refuses to start without a development team, and the point
# here is precisely to produce a build for a machine that has no Developer ID.
NOSIGN=(CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO)

say "Building $SCHEME (Release)…"
# The output goes to a file because a clean build prints thousands of lines
# nobody reads. It used to go to /dev/null, which threw away the only thing
# anyone ever wants from it: when this failed on CI and nowhere else, the log
# held the script's own "run it by hand" and not one compiler diagnostic, and
# "run it by hand" is no use on a runner that is already gone.
BUILD_LOG=$(mktemp "${TMPDIR:-/tmp}/notchy-build.XXXXXX")
if ! ( cd NotchBuddy && xcodegen >/dev/null \
       && xcodebuild -scheme "$SCHEME" -configuration Release "${NOSIGN[@]}" build ) \
     >"$BUILD_LOG" 2>&1
then
  printf '\n  --- what the compiler said ---\n' >&2
  grep -E "error:|\*\* BUILD FAILED \*\*" "$BUILD_LOG" | head -40 >&2 || true
  die "the build failed — see above; full log kept at $BUILD_LOG"
fi
rm -f "$BUILD_LOG"

BUILT=$(
  xcodebuild -scheme "$SCHEME" -configuration Release "${NOSIGN[@]}" -showBuildSettings \
    -project NotchBuddy/NotchBuddy.xcodeproj 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}'
)
APP="$BUILT/$APP_NAME.app"
[ -d "$APP" ] || die "no $APP_NAME.app in $BUILT"

# ── 2. Stage and sign ─────────────────────────────────────────────────────────
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/notchy-dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
VOL="$STAGE/vol"
mkdir -p "$VOL"
ditto "$APP" "$VOL/$APP_NAME.app"

# The Info.plist has to be final before signing: changing it afterwards breaks
# the seal. Release builds get no stamp from install-mac.sh, so it goes on here.
PLIST="$VOL/$APP_NAME.app/Contents/Info.plist"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
COMMIT=$(git describe --always --dirty 2>/dev/null || echo "?")
for k in "NotchyBuildBranch:$BRANCH" "NotchyBuildCommit:$COMMIT"; do
  /usr/libexec/PlistBuddy -c "Add :${k%%:*} string ${k#*:}" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :${k%%:*} ${k#*:}" "$PLIST"
done

say "Signing the bundle ad-hoc…"
# --entitlements is not optional, though it reads that way. Re-signing drops
# whatever the build put there, and this bundle has exactly one entitlement —
# com.apple.security.automation.apple-events, which is what jumping to the
# terminal, sending mail and controlling playback all run on. Without this
# line every downloaded copy arrives with those quietly dead, and it looks
# like a broken feature rather than a packaging mistake.
#
# No --options runtime, and it must stay that way until there is a Developer
# ID. The hardened runtime turns on library validation, which requires every
# loaded library to carry the same Team ID as the app. An ad-hoc signature has
# no Team ID at all, so Sparkle.framework is refused and the app is killed by
# dyld before main() — "Library not loaded: @rpath/Sparkle.framework". It was
# added here on the reasoning that notarization would need it later, and it
# shipped in mac-v0.1.7, which crashed on launch for everyone who downloaded
# it. Notarization needs a Developer ID first; with one, the app and the
# framework share a Team ID and validation passes. Without one, this flag buys
# nothing and costs the whole app.
ENTITLEMENTS=NotchBuddy/Resources/Notchy.entitlements
[ -f "$ENTITLEMENTS" ] || die "no entitlements at $ENTITLEMENTS"
codesign --force --deep --sign - \
  --entitlements "$ENTITLEMENTS" \
  "$VOL/$APP_NAME.app" \
  || die "codesign failed"
codesign --verify --deep --strict "$VOL/$APP_NAME.app" \
  || die "the signature does not verify — the .dmg would arrive 'damaged'"
# Proves the entitlement survived rather than trusting that it did: a silent
# strip is invisible until someone else's Mac cannot play music.
codesign -d --entitlements - --xml "$VOL/$APP_NAME.app" 2>/dev/null \
  | grep -q "apple-events" \
  || die "the signed bundle has no apple-events entitlement"
# The pairing that killed mac-v0.1.7, asserted rather than remembered: the
# hardened runtime validates every loaded library against the app's Team ID,
# an ad-hoc signature has none, and Sparkle.framework is then refused by dyld
# before main() runs. A signature that verifies tells you nothing about this —
# the app is well-formed and still cannot start.
codesign -dvv "$VOL/$APP_NAME.app" 2>&1 | grep -q "flags=.*runtime" \
  && die "hardened runtime on an ad-hoc signature: Sparkle will not load"

# ── 3. The drag-to-Applications window ────────────────────────────────────────
ln -s /Applications "$VOL/Applications"

# The window itself: a background with an arrow, and the two icons placed where
# it points. Recorded once by scripts/make-dmg-layout.sh rather than arranged
# here, because arranging it means driving Finder over Apple Events and a CI
# runner has no Finder session worth the name. Copying two files works the same
# everywhere. Missing files are not fatal — an image with a plain file list is
# worse-looking, not broken — but say so, because silently shipping the plain
# one is how it would stay plain for a year.
if [ -f design/dmg/DS_Store ] && [ -f design/dmg/background.tiff ]; then
  mkdir -p "$VOL/.background"
  cp design/dmg/background.tiff "$VOL/.background/background.tiff"
  cp design/dmg/DS_Store "$VOL/.DS_Store"
else
  say "note: no design/dmg layout — the window will be a plain file list."
  say "      regenerate it with: bash scripts/make-dmg-layout.sh"
fi

# The first open is refused on any Mac but the one that built this, because
# there is no Developer ID behind it. Saying so in the window is the whole
# difference between "one click in System Settings" and "it does not work":
# the dialog macOS shows names no way forward, and nobody goes looking for a
# download page they have already left.
cat > "$VOL/Open me first.txt" <<'README'
Notchy — installing

1. Drag Notchy into Applications.

2. Open it FROM APPLICATIONS, not from this window.

   A copy opened here runs from the disk image, and macOS gives it
   a temporary location of its own. From there it loses the
   permissions you grant it, cannot answer Claude Code, and cannot
   update itself. Notchy notices and offers to move itself, but the
   shorter path is to drag it across first.

3. The first open is refused, once. This build carries no Apple
   Developer ID, so Apple has not checked it and macOS says so.
   Open System Settings > Privacy & Security, scroll down to the
   message naming Notchy, and click "Open Anyway". That is once
   per Mac; every later launch is ordinary.

Or install it in one line, and meet no dialog at all:

   curl -fsSL https://cauarat.github.io/windows-atoll-/install.sh | bash

The quarantine flag that makes macOS ask is set by whatever
downloads a file. Browsers set it; curl does not. So the copy that
command installs is never assessed by Gatekeeper and simply opens.
Nothing is turned off, and the exception is this one app.

The same steps in English, Spanish and Portuguese:
https://cauarat.github.io/windows-atoll-/download.html?go=mac
README
ICON="$VOL/$APP_NAME.app/Contents/Resources/AppIcon.icns"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST" 2>/dev/null || echo "0")
mkdir -p "$OUT_DIR"
DMG="$OUT_DIR/$APP_NAME-macOS-$VERSION.dmg"
rm -f "$DMG"

say "Building ${DMG}…"
# UDZO keeps it compressed and read-only, which is what a download should be.
hdiutil create -quiet -srcfolder "$VOL" -volname "$APP_NAME" -format UDZO -fs HFS+ "$DMG" \
  || die "hdiutil failed"

[ -f "$ICON" ] && cp "$ICON" "$OUT_DIR/.VolumeIcon.icns" 2>/dev/null || true

# ── 4. Say what came out ──────────────────────────────────────────────────────
ARCHS=$(lipo -archs "$VOL/$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || echo "?")
MIN=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$PLIST" 2>/dev/null || echo "?")
# Printed rather than assumed. The signing step already refuses without it;
# this is so the person reading the output can see it, which is how the last
# silent strip would have been caught.
ENTS=$(codesign -d --entitlements - --xml "$VOL/$APP_NAME.app" 2>/dev/null \
  | grep -o "com\.apple\.security\.[a-z.-]*" | paste -sd, - )
[ -n "$ENTS" ] || ENTS="none"

cat <<EOF

  $APP_NAME $VERSION
    file          $DMG  ($(du -h "$DMG" | cut -f1))
    architectures $ARCHS
    minimum macOS $MIN
    built from    $BRANCH @ $COMMIT
    signing       ad-hoc — not notarized, not a Developer ID
    entitlements  $ENTS

  Handed to someone through a browser, the first open is refused once, and the
  way through is a click rather than a command: System Settings > Privacy &
  Security > Open Anyway. The image says so itself, in "Open me first.txt".

  Published, it is reachable without that dialog at all — curl sets no
  quarantine flag, so docs/install.sh installs a copy Gatekeeper never assesses:
    curl -fsSL https://cauarat.github.io/windows-atoll-/install.sh | bash

  Handing this file to someone directly, the same trick works locally:
    hdiutil attach $DMG -nobrowse -quiet \
      && ditto "/Volumes/$APP_NAME/$APP_NAME.app" "/Applications/$APP_NAME.app" \
      && hdiutil detach "/Volumes/$APP_NAME" -quiet

EOF
