#!/usr/bin/env bash
#
# Writes the Sparkle appcast for one macOS build.
#
#   scripts/make-appcast.sh <file.dmg> <version> <download-url> [out.xml]
#
# Every installed copy of Notchy reads this file and nothing else to learn that
# an update exists. Until now nothing in this repository produced one: the live
# appcast on mac-v0.1.11 was uploaded by hand, mac-v0.1.10 never had one, and
# the only script that knew how to write one still called the app Coucou and
# published a .zip under a tag scheme this fork stopped using. A release that
# forgets this file does not fail — it just quietly strands everyone who already
# installed, which is the worst way for a thing to break.
#
# The signature is EdDSA over the file's bytes, made with the private half of
# the SUPublicEDKey baked into the app. The key comes from SPARKLE_PRIVATE_KEY
# when it is set (CI), and otherwise from the login Keychain under the account
# name Sparkle's generate_keys used. It is never written to disk by this script.
set -euo pipefail
cd "$(dirname "$0")/.."

DMG="${1:?usage: make-appcast.sh <file.dmg> <version> <download-url> [out.xml]}"
VERSION="${2:?no version}"
URL="${3:?no download url}"
OUT="${4:-$(dirname "$DMG")/appcast.xml}"
KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-coucou}"

die() { printf '\n  error: %s\n\n' "$*" >&2; exit 1; }

[ -f "$DMG" ] || die "no such file: $DMG"

# sign_update ships inside the resolved Sparkle package, so where it lands
# depends on the derived data path the build used. Look rather than guess.
SIGN="${SPARKLE_SIGN_UPDATE:-}"
if [ -z "$SIGN" ]; then
  SIGN=$(find "${HOME}/Library/Developer/Xcode/DerivedData" /tmp \
              -type f -name sign_update -path '*sparkle*' 2>/dev/null | head -1 || true)
fi
[ -n "$SIGN" ] && [ -x "$SIGN" ] \
  || die "sign_update not found. Build once so the Sparkle package resolves, or set SPARKLE_SIGN_UPDATE."

# `sign_update` prints the finished attributes:
#   sparkle:edSignature="…" length="…"
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  ATTRS=$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN" "$DMG" --ed-key-file -) \
    || die "signing failed with the key in SPARKLE_PRIVATE_KEY"
else
  ATTRS=$("$SIGN" "$DMG" --account "$KEY_ACCOUNT") \
    || die "signing failed. No SPARKLE_PRIVATE_KEY, and no key in the login Keychain under '$KEY_ACCOUNT'."
fi
case "$ATTRS" in
  *edSignature=*) ;;
  *) die "sign_update produced no signature: $ATTRS" ;;
esac

MIN=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" NotchBuddy/Resources/Info.plist 2>/dev/null || echo "15.0")
DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")

cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Notchy</title>
    <link>https://github.com/cauarat/windows-atoll-</link>
    <description>Updates for Notchy.</description>
    <language>en</language>
    <item>
      <title>$VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/cauarat/windows-atoll-/releases/tag/mac-v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$URL"
                 type="application/octet-stream"
                 $ATTRS />
    </item>
  </channel>
</rss>
XML

xmllint --noout "$OUT" || die "the appcast is not well-formed XML"
printf '\n  %s\n    version %s\n    %s\n\n' "$OUT" "$VERSION" "$URL"
