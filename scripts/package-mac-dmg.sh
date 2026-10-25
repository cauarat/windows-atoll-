#!/usr/bin/env bash
#
# Builds Notchy for macOS and puts it in a .dmg you can hand to someone.
#
# Not a replacement for scripts/release.sh. That one signs with a Developer ID,
# notarizes, staples and writes the Sparkle appcast, and it refuses to run
# without those credentials. This produces the same app without them: useful for
# handing a build to a tester, and the only thing possible on a machine that has
# no Developer ID.
#
# The result is NOT signed by an identified developer and NOT notarized. Say so
# wherever it is offered — docs/download.html does.
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
( cd NotchBuddy && xcodegen >/dev/null \
  && xcodebuild -scheme "$SCHEME" -configuration Release "${NOSIGN[@]}" build >/dev/null ) \
  || die "the build failed — run it by hand in NotchBuddy/ to see why"

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
codesign --force --deep --sign - "$VOL/$APP_NAME.app" 2>/dev/null \
  || die "codesign failed"
codesign --verify --deep --strict "$VOL/$APP_NAME.app" \
  || die "the signature does not verify — the .dmg would arrive 'damaged'"

# ── 3. The drag-to-Applications window ────────────────────────────────────────
ln -s /Applications "$VOL/Applications"
ICON="$VOL/$APP_NAME.app/Contents/Resources/AppIcon.icns"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST" 2>/dev/null || echo "0")
mkdir -p "$OUT_DIR"
DMG="$OUT_DIR/$APP_NAME-macOS-$VERSION.dmg"
rm -f "$DMG"

say "Building $DMG…"
# UDZO keeps it compressed and read-only, which is what a download should be.
hdiutil create -quiet -srcfolder "$VOL" -volname "$APP_NAME" -format UDZO -fs HFS+ "$DMG" \
  || die "hdiutil failed"

[ -f "$ICON" ] && cp "$ICON" "$OUT_DIR/.VolumeIcon.icns" 2>/dev/null || true

# ── 4. Say what came out ──────────────────────────────────────────────────────
ARCHS=$(lipo -archs "$VOL/$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || echo "?")
MIN=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$PLIST" 2>/dev/null || echo "?")

cat <<EOF

  $APP_NAME $VERSION
    file          $DMG  ($(du -h "$DMG" | cut -f1))
    architectures $ARCHS
    minimum macOS $MIN
    built from    $BRANCH @ $COMMIT
    signing       ad-hoc only — not notarized, not a Developer ID

  Gatekeeper will warn on first open. Per app, never globally:
    xattr -dr com.apple.quarantine /Applications/$APP_NAME.app

EOF
