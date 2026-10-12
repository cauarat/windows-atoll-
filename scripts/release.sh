#!/usr/bin/env bash
# Builds, notarizes and publishes Coucou for macOS (GitHub build).
#
#   ./scripts/release.sh 0.1.2            build, sign, notarize, staple, tag, publish
#   ./scripts/release.sh 0.1.2 --finish   finish after an interrupted notarization wait
#
# Run it from a clean checkout of main. CFBundleShortVersionString in
# NotchBuddy/project.yml must match the version, and CHANGELOG.md needs a
# "## <version>" section: it becomes the release notes.
set -euo pipefail

VERSION="${1:?Usage: $0 <version> [--finish]}"
MODE="${2:-}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Where the release is published, and — this is the part that bites — the repo
# whose Latest release the installed copies fetch appcast.xml from. The app has
# that URL compiled in (SUFeedURL in NotchBuddy/project.yml); publishing the
# release anywhere else means nobody ever sees it. Change both or neither.
REPO="${COUCOU_REPO:-cauarat/windows-atoll-}"
BUILD_DIR="/tmp/coucou-release-$VERSION"
APP="$BUILD_DIR/Coucou.app"
ZIP="$BUILD_DIR/Coucou.zip"
COMMIT_FILE="$BUILD_DIR/commit"
TAG="v$VERSION"

die() { echo "error: $*" >&2; exit 1; }

case "$MODE" in
  ""|--finish) ;;
  *) die "unknown option '$MODE' (the only option is --finish)" ;;
esac

cd "$REPO_ROOT"

# ── Checks shared by both modes ───────────────────────────────────────────────
command -v gh >/dev/null || die "gh is not installed (brew install gh)"

# The "## <version>" section of CHANGELOG.md, without leading or trailing blank lines.
CHANGES=$(awk -v head="## $VERSION" '
  index($0, head " ") == 1 || $0 == head { found = 1; next }
  found && /^## / { exit }
  found {
    if ($0 ~ /^[ \t\r]*$/) { if (started) blanks++; next }
    while (blanks > 0) { print ""; blanks-- }
    print; started = 1
  }
' CHANGELOG.md)
[ -n "$CHANGES" ] || die "CHANGELOG.md has no '## $VERSION' section"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  die "tag $TAG already exists here"
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  die "tag $TAG already exists on GitHub"
fi

if [ "$MODE" != "--finish" ]; then
  # The release must match a commit: no uncommitted changes to tracked files.
  if ! git diff --quiet || ! git diff --cached --quiet; then
    die "commit or stash your changes first, the release has to match a commit"
  fi
  COMMIT=$(git rev-parse HEAD)

  # ── 1. Developer ID identity ────────────────────────────────────────────────
  # "|| true": with pipefail, grep finding nothing would end the script silently.
  IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(Developer ID Application[^"]*\)".*/\1/' || true)
  [ -n "$IDENTITY" ] || die "no 'Developer ID Application' certificate found. Install it via Xcode → Settings → Accounts."
  echo "Signing with: $IDENTITY"

  # ── 2. xcodegen + Release build ─────────────────────────────────────────────
  cd "$REPO_ROOT/NotchBuddy"
  xcodegen generate
  PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
  [ "$PLIST_VERSION" = "$VERSION" ] || die "the app is version $PLIST_VERSION, not $VERSION: update CFBundleShortVersionString in NotchBuddy/project.yml"
  # Sparkle compares this one, not the pretty one. If it does not move, an
  # installed copy decides the new release is the same build and stays put.
  BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)
  [ "$BUILD_VERSION" = "$VERSION" ] || die "CFBundleVersion is $BUILD_VERSION, not $VERSION: update it in NotchBuddy/project.yml, or no installed copy will see this release as newer"

  rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
  echo "$COMMIT" > "$COMMIT_FILE"

  # -derivedDataPath pins where SwiftPM checks Sparkle out, so sign_update is
  # at a path this script can name instead of one it has to go hunting for.
  xcodebuild \
    -project NotchBuddy.xcodeproj \
    -scheme NotchBuddy \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/dd" \
    build \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR"

  # ── 3. Zip + notarize ───────────────────────────────────────────────────────
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo
  echo "Sending to Apple for notarization. If you stop the wait (Ctrl+C), Apple keeps going:"
  echo "  check it with  xcrun notarytool history --keychain-profile coucou-notary"
  echo "  once Accepted  ./scripts/release.sh $VERSION --finish"
  echo
  xcrun notarytool submit "$ZIP" --keychain-profile coucou-notary --wait \
    || die "notarization failed: see xcrun notarytool log <id> --keychain-profile coucou-notary (the id is printed above)"
  cd "$REPO_ROOT"
else
  [ -d "$APP" ] && [ -f "$COMMIT_FILE" ] || die "nothing to finish in $BUILD_DIR, run ./scripts/release.sh $VERSION first"
  COMMIT=$(cat "$COMMIT_FILE")
fi

# ── 4. Staple + verify ────────────────────────────────────────────────────────
xcrun stapler staple "$APP" \
  || die "stapling failed: Apple has not accepted the build yet. Check xcrun notarytool history --keychain-profile coucou-notary, then run ./scripts/release.sh $VERSION --finish"
spctl -a -vv "$APP"

# ── 5. Re-zip (with the stapled app) ──────────────────────────────────────────
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Release zip ready: $ZIP"

# ── 5b. Sign it and write the appcast ─────────────────────────────────────────
# This is what every installed copy checks before it will unpack anything. The
# private key lives in the login Keychain under the "coucou" account and never
# touches the disk or the repo; sign_update reads it from there, and macOS may
# ask once for permission to let it.
SIGN_UPDATE="$BUILD_DIR/dd/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
[ -x "$SIGN_UPDATE" ] || die "sign_update is not at $SIGN_UPDATE — the Sparkle package did not resolve during the build"

# Prints: sparkle:edSignature="…" length="…" — dropped into the enclosure as-is.
SIGNATURE=$("$SIGN_UPDATE" "$ZIP" --account coucou) \
  || die "signing failed. If no key exists yet, create one once with:  $SIGN_UPDATE --help  and generate_keys --account coucou"

# The changelog as HTML, because Sparkle renders the description as a web page.
# Escaped first: a "<" in a release note would otherwise be read as markup.
NOTES_HTML=$(printf '%s\n' "$CHANGES" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' | awk '
  /^[-*] / { if (!inlist) { print "<ul>"; inlist = 1 } sub(/^[-*] /, ""); print "<li>" $0 "</li>"; next }
  /^[ \t]*$/ { next }
  { if (inlist) { print "</ul>"; inlist = 0 } print "<p>" $0 "</p>" }
  END { if (inlist) print "</ul>" }
')

APPCAST="$BUILD_DIR/appcast.xml"
cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Coucou</title>
    <link>https://github.com/$REPO</link>
    <description>Updates for Coucou.</description>
    <language>en</language>
    <item>
      <title>$VERSION</title>
      <pubDate>$(date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
$NOTES_HTML
      ]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/Coucou.zip"
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
xmllint --noout "$APPCAST" || die "the appcast is not well-formed XML: $APPCAST"
echo "Appcast ready: $APPCAST"

# ── 6. Tag the built commit + GitHub release ──────────────────────────────────
NOTES="Coucou $VERSION for macOS 15 or later (Apple silicon and Intel).

Signed with a Developer ID and notarized by Apple.

## What's new

$CHANGES

## Install

1. Download Coucou.zip below and unzip it.
2. Move Coucou.app to your Applications folder, replacing the old one if you have it.
3. Launch it, and click Open when macOS asks you to confirm.

Linux and Windows: see the [README](https://github.com/Louis-CFM/coucou#readme)."

echo
echo "──────── Release notes ────────"
echo "$NOTES"
echo "───────────────────────────────"
echo
read -r -p "Tag $(git rev-parse --short "$COMMIT") as $TAG and publish this release? [y/N] " ANSWER
case "$ANSWER" in
  y|Y|yes|oui|o|O) ;;
  *) die "stopped before tagging. Run ./scripts/release.sh $VERSION --finish to publish later." ;;
esac

git tag "$TAG" "$COMMIT"
git push origin "$TAG"

# appcast.xml rides along: SUFeedURL points at /releases/latest/download/, so
# whichever release holds the Latest badge is the one every copy reads.
gh release create "$TAG" "$ZIP" "$APPCAST" \
  --repo "$REPO" \
  --title "Coucou $VERSION" \
  --latest \
  --notes "$NOTES"

echo "✓ $TAG released: https://github.com/$REPO/releases/tag/$TAG"
