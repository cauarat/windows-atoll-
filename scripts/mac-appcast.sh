#!/usr/bin/env bash
# Gives a published `mac-v*` release the appcast.xml that Mac auto-update reads.
#
#   scripts/mac-appcast.sh 0.1.15             sign the published .dmg, upload the appcast
#   scripts/mac-appcast.sh 0.1.15 --dry-run   write it, print it, upload nothing
#
# Run it on the Mac that holds the update key, right after the "macOS release"
# workflow has published `mac-v<version>`. That workflow cannot do this part:
# every installed copy checks an update against the EdDSA key compiled into it
# (SUPublicEDKey), and the private half lives in a login Keychain under the
# account "coucou", not in this repository's secrets. The key never touches the
# disk here either — sign_update reads it from the Keychain itself.
#
# Why it cannot wait: SUFeedURL is /releases/latest/download/appcast.xml, and
# the workflow pins Latest on the release it has just published. Until this
# script has run, that URL is a 404 and every installed copy's update check
# finds nothing — silently, which is what happened to every Mac release before
# 0.1.11. So: run it as soon as the workflow is green.
#
# It refuses, rather than publishes, when the Keychain key is not the one the
# packaged app trusts. A feed signed by the wrong key is one every copy
# rejects, and that only shows up on somebody else's Mac.
#
# The notes come from the "## <version>" section of CHANGELOG.md, as the
# Windows manifest's do. --dry-run on a version already published is the test:
# the signature is deterministic, so it must reproduce that release's appcast
# exactly, bar the date.
set -euo pipefail

VERSION="${1:?Usage: $0 <version> [--dry-run]}"
MODE="${2:-}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# The repository whose Latest release the installed copies read the feed from.
# It is compiled into the app (SUFeedURL in NotchBuddy/project.yml): change
# both or neither.
REPO="${COUCOU_REPO:-cauarat/windows-atoll-}"
TAG="mac-v$VERSION"
DMG_NAME="Notchy-macOS-$VERSION.dmg"
FEED="https://github.com/$REPO/releases/latest/download/appcast.xml"

die() { echo "error: $*" >&2; exit 1; }

case "$MODE" in
  ""|--dry-run) ;;
  *) die "unknown option '$MODE' (the only option is --dry-run)" ;;
esac

command -v gh >/dev/null      || die "gh is not installed (brew install gh)"
command -v xmllint >/dev/null || die "xmllint is not installed"

# Sparkle ships its tools inside the Swift package, so they are wherever Xcode
# last resolved it. Any build of the app on this Mac leaves them behind.
SPARKLE_BIN="${SPARKLE_BIN:-$(ls -td "$HOME"/Library/Developer/Xcode/DerivedData/NotchBuddy-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1)}"
[ -x "$SPARKLE_BIN/sign_update" ] && [ -x "$SPARKLE_BIN/generate_keys" ] \
  || die "Sparkle's sign_update was not found. Build the app once in Xcode (or with xcodebuild), or set SPARKLE_BIN to the directory holding it."

# ── The notes ─────────────────────────────────────────────────────────────────
CHANGES=$(awk -v head="## $VERSION" '
  index($0, head " ") == 1 || $0 == head { found = 1; next }
  found && /^## / { exit }
  found { print }
' "$REPO_ROOT/CHANGELOG.md")
[ -n "$(printf '%s' "$CHANGES" | tr -d '[:space:]')" ] \
  || die "CHANGELOG.md has no \"## $VERSION\" section. It becomes what the update window shows."

# As HTML, because Sparkle renders the description as a web page. Escaped
# first: a "<" in a release note would otherwise be read as markup.
NOTES_HTML=$(printf '%s\n' "$CHANGES" \
  | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e "s/'/\&#x27;/g" \
        -e 's/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g' \
  | awk '
  /^[-*] / { if (!inlist) { print "        <ul>"; inlist = 1 } sub(/^[-*] /, ""); print "          <li>" $0 "</li>"; next }
  /^[ \t]*$/ { next }
  { if (inlist) { print "        </ul>"; inlist = 0 } print "        <p>" $0 "</p>" }
  END { if (inlist) print "        </ul>" }')

# ── The package, as published ─────────────────────────────────────────────────
# Downloaded rather than taken from a local build: the signature has to be over
# the very bytes a Mac will fetch, and those were built on a runner.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/notchy-appcast.XXXXXX")"
MOUNT=""
cleanup() {
  [ -z "$MOUNT" ] || hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

gh release download "$TAG" --repo "$REPO" --pattern "$DMG_NAME" --dir "$WORK" \
  || die "could not download $DMG_NAME from $TAG. Has the \"macOS release\" workflow finished?"
DMG="$WORK/$DMG_NAME"

# ── Is this the key the app trusts? ───────────────────────────────────────────
MOUNT="$(hdiutil attach -nobrowse -readonly "$DMG" | tail -1 | awk '{print $NF}')"
PLIST="$MOUNT/Notchy.app/Contents/Info.plist"
SHIPPED_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST")"
SHIPPED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
hdiutil detach "$MOUNT" -quiet
MOUNT=""

[ "$SHIPPED_VERSION" = "$VERSION" ] \
  || die "$DMG_NAME holds version $SHIPPED_VERSION, not $VERSION. Sparkle compares CFBundleVersion: a feed announcing $VERSION for it would be offered for ever."

KEYCHAIN_KEY="$("$SPARKLE_BIN/generate_keys" --account coucou -p 2>/dev/null | tail -1)" \
  || die "no update key under the Keychain account \"coucou\" on this Mac. This has to run on the Mac that holds it."
[ "$KEYCHAIN_KEY" = "$SHIPPED_KEY" ] \
  || die "the Keychain key ($KEYCHAIN_KEY) is not the one this build trusts ($SHIPPED_KEY). Nothing signed here would be accepted by any installed copy."

# Prints: sparkle:edSignature="…" length="…" — dropped into the enclosure as-is.
SIGNATURE="$("$SPARKLE_BIN/sign_update" "$DMG" --account coucou)" || die "signing failed"

# ── The feed ──────────────────────────────────────────────────────────────────
APPCAST="$WORK/appcast.xml"
cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Notchy</title>
    <link>https://github.com/$REPO</link>
    <description>Updates for Notchy.</description>
    <language>en</language>
    <item>
      <title>$VERSION</title>
      <pubDate>$(date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
$NOTES_HTML
      ]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/$DMG_NAME"
                 sparkle:version="$VERSION"
                 sparkle:shortVersionString="$VERSION"
                 $SIGNATURE
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

# A malformed appcast is one every installed copy silently ignores, so it is
# worth the one line it costs to find out here instead.
xmllint --noout "$APPCAST" || die "the appcast is not well-formed XML"

if [ "$MODE" = "--dry-run" ]; then
  cat "$APPCAST"
  echo "" >&2
  echo "Dry run: nothing uploaded." >&2
  exit 0
fi

# ── Publish, then read it back the way an installed copy does ─────────────────
gh release upload "$TAG" "$APPCAST" --repo "$REPO" --clobber

LATEST="$(gh api "repos/$REPO/releases/latest" --jq .tag_name)"
if [ "$LATEST" != "$TAG" ]; then
  echo "" >&2
  echo "warning: the appcast is on $TAG, but Latest is $LATEST — and Latest is where the feed is read from." >&2
  echo "         scripts/pin-latest-release.sh $REPO puts the badge back on the newest macOS release." >&2
  exit 1
fi

# The redirect behind /releases/latest/ can lag a moment behind the upload.
for attempt in 1 2 3 4 5 6; do
  if curl -fsSL "$FEED" -o "$WORK/live.xml" 2>/dev/null && cmp -s "$WORK/live.xml" "$APPCAST"; then
    echo "The feed now announces $VERSION: $FEED"
    exit 0
  fi
  sleep 5
done
die "uploaded, but $FEED does not serve it back yet. Fetch it by hand before trusting this release."
