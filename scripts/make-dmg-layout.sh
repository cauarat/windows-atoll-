#!/usr/bin/env bash
#
# Records the disk image window — its size, its background and where the two
# icons sit — into design/dmg/DS_Store, which scripts/package-mac-dmg.sh then
# copies into every .dmg it builds.
#
# Why it is recorded rather than done at package time: setting a Finder window
# means driving Finder over Apple Events, and a GitHub runner has no Finder
# session worth the name. Doing it once here and committing the result makes the
# packaging step a file copy, which works the same on a runner as on a desk.
#
#   bash scripts/make-dmg-layout.sh
#
# Run it after changing the background or the positions, and commit what it
# writes. It needs a Mac with Finder automation allowed for your terminal; the
# first run will ask.
#
# Positions are read from one place — the table below — and the background is
# drawn from the same numbers in scripts/make-dmg-background.swift. Change them
# in both or the arrow stops pointing at anything.
set -euo pipefail
cd "$(dirname "$0")/.."

VOLNAME=Notchy
APP_NAME=Notchy.app
README_NAME="Open me first.txt"
WIN_W=660; WIN_H=400
ICON_SIZE=96
APP_X=165;  APP_Y=205
APPS_X=495; APPS_Y=205
README_X=80; README_Y=316

say() { printf '\n  %s\n' "$*"; }
die() { printf '\n  error: %s\n\n' "$*" >&2; exit 1; }

[ -f design/dmg/background.png ] || die "no background — run: swift scripts/make-dmg-background.swift"

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/notchy-dmg-layout.XXXXXX")
MOUNT=""
cleanup() {
  if [ -n "$MOUNT" ]; then hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; fi
  rm -rf "$STAGE"
}
trap cleanup EXIT

# Retina and not, in one file: Finder reads both representations out of a TIFF.
say "Combining the background…"
tiffutil -cathidpicheck design/dmg/background.png design/dmg/background@2x.png \
  -out "$STAGE/background.tiff" >/dev/null || die "tiffutil failed"

# A stand-in bundle is enough: .DS_Store keys positions by file name, and the
# name is all that has to match what package-mac-dmg.sh puts in.
VOL="$STAGE/vol"
mkdir -p "$VOL/$APP_NAME" "$VOL/.background"
cp "$STAGE/background.tiff" "$VOL/.background/background.tiff"
ln -s /Applications "$VOL/Applications"
printf 'placeholder\n' > "$VOL/$README_NAME"

say "Building a writable image to arrange…"
RW="$STAGE/rw.dmg"
hdiutil create -quiet -srcfolder "$VOL" -volname "$VOLNAME" -format UDRW -fs HFS+ "$RW" \
  || die "hdiutil failed"

MOUNT="/Volumes/$VOLNAME"
hdiutil attach "$RW" -nobrowse -readwrite -noverify -quiet || die "could not attach the image"

say "Asking Finder to lay the window out…"
osascript <<APPLESCRIPT || die "Finder refused. Allow your terminal to control Finder in System Settings > Privacy & Security > Automation, then run this again."
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, ${WIN_W} + 200, ${WIN_H} + 120}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to $ICON_SIZE
    set background picture of opts to file ".background:background.tiff"
    set position of item "$APP_NAME" of container window to {$APP_X, $APP_Y}
    set position of item "Applications" of container window to {$APPS_X, $APPS_Y}
    set position of item "$README_NAME" of container window to {$README_X, $README_Y}
    update without registering applications
    close
  end tell
end tell
APPLESCRIPT

# Finder writes .DS_Store lazily. Give it the moment it needs, then make sure.
sync
osascript -e "tell application \"Finder\" to update disk \"$VOLNAME\"" >/dev/null 2>&1 || true
[ -f "$MOUNT/.DS_Store" ] || die "Finder did not write a .DS_Store"

cp "$MOUNT/.DS_Store" design/dmg/DS_Store
cp "$STAGE/background.tiff" design/dmg/background.tiff

hdiutil detach "$MOUNT" -quiet || true
MOUNT=""

cat <<EOF

  Written:
    design/dmg/DS_Store         $(du -h design/dmg/DS_Store | cut -f1)   window size, icon positions, background reference
    design/dmg/background.tiff  $(du -h design/dmg/background.tiff | cut -f1)   both resolutions in one file

  Commit both. scripts/package-mac-dmg.sh copies them into every image it
  builds, so the window looks the same wherever it was packaged.

EOF
