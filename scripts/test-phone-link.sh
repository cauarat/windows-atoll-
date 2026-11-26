#!/usr/bin/env bash
# The Mac side of the phone link (docs/PHONE_LINK.md) against the vectors of Coucou's Windows/Linux
# server and Android client: pairing link, fingerprints, TXT record, framing, admission, the hub's
# subscribers and capabilities, the certificate. Pure files only: no socket, no Keychain, no AppState.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchy-phone-link.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
LINK=NotchBuddy/Sources/App/PhoneLink
swiftc -swift-version 6 -strict-concurrency=complete \
    $LINK/PhoneLinkProtocol.swift $LINK/PhoneLinkAdmission.swift $LINK/PhoneLinkHub.swift \
    $LINK/PhoneLinkIdentity.swift tests/PhoneLinkTests.swift -o "$TEST_DIR/phone-link-tests"
"$TEST_DIR/phone-link-tests"
