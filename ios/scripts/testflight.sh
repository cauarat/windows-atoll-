#!/usr/bin/env bash
#
# Archives Notchy for iPhone and uploads it to App Store Connect, for TestFlight.
#
# Needs an Apple Developer Program membership (TestFlight does not exist for a free Apple ID), and, once:
#   1. In App Store Connect → Apps, a new iOS app with the bundle ID com.cauarati.NotchyPhone (or yours:
#      change PRODUCT_BUNDLE_IDENTIFIER in ios/project.yml, and the widget's after it).
#   2. In App Store Connect → Users and Access → Integrations, an API key with the App Manager role.
#      Download the .p8 once and keep it out of this repository.
#   3. Export, in your shell (never in a file in the repo):
#        NOTCHY_TEAM_ID=ABCDE12345            # your team, Membership details in developer.apple.com
#        ASC_KEY_ID=XXXXXXXXXX                # the key's id
#        ASC_ISSUER_ID=xxxxxxxx-xxxx-…        # shown above the keys list
#        ASC_KEY_PATH=~/.private/AuthKey_XXXXXXXXXX.p8
#
#   ios/scripts/testflight.sh 0.1.0 3         # marketing version, build number (must grow every upload)
#
# Xcode signs with your team automatically (it creates the certificates and profiles it needs through the
# API key). The build then appears in App Store Connect → TestFlight after Apple's processing; add testers,
# or a public link (up to 10,000 people), from there. The first build for external testers goes through a
# short Beta App Review.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: testflight.sh <version> <build>}"
BUILD="${2:?usage: testflight.sh <version> <build>}"
: "${NOTCHY_TEAM_ID:?set NOTCHY_TEAM_ID}" "${ASC_KEY_ID:?set ASC_KEY_ID}" "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}" "${ASC_KEY_PATH:?set ASC_KEY_PATH}"
KEY_PATH="${ASC_KEY_PATH/#\~/$HOME}"
[ -f "$KEY_PATH" ] || { echo "No API key at $KEY_PATH" >&2; exit 1; }

command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen" >&2; exit 1; }
xcodegen >/dev/null

OUT="build/testflight"
rm -rf "$OUT"
mkdir -p "$OUT"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

xcodebuild -project NotchyPhone.xcodeproj -scheme Notchy -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Notchy.xcarchive" \
  DEVELOPMENT_TEAM="$NOTCHY_TEAM_ID" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  "${AUTH[@]}" archive

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${NOTCHY_TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

# destination=upload sends the build straight to App Store Connect.
xcodebuild -exportArchive -archivePath "$OUT/Notchy.xcarchive" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" "${AUTH[@]}"

echo "Uploaded Notchy $VERSION ($BUILD). It shows up in App Store Connect → TestFlight once Apple has processed it."
