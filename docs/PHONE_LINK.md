# Phone link (protocol v1)

How Notchy for iPhone and Notchy for Android talk to Notchy on the computer. It is Coucou's
"Android link" (Louis-CFM/coucou, `docs/ANDROID_LINK.md`, MIT), with Notchy's own names, so a phone
paired with Coucou is never offered a Notchy and the other way round. Both phones speak exactly this;
the computer cannot tell them apart.

There is no server anywhere: the phone connects to the computer directly over the local network.
Coucou's iPhone app uses iCloud instead, which needs the Mac app signed by a paid Apple developer
team; Notchy's Mac build is ad-hoc signed, so both phones use this link.

| Side | Code |
|---|---|
| Mac (server) | `NotchBuddy/Sources/App/PhoneLink/`, tests in `tests/PhoneLinkTests.swift` (`scripts/test-phone-link.sh`) |
| iPhone (client) | `ios/Notchy/Link/` |
| Android (client) | `android/app/src/main/kotlin/com/cauarati/notchy/link/` |
| Windows/Linux (server) | not yet: Coucou's `windows/src-tauri/src/phone_link/` is the one to port |

## Transport

- TCP, then TLS 1.2 or 1.3. The computer uses a self-signed ECDSA P-256 certificate (named curve
  `prime256v1`: Android's TLS refuses explicit curve parameters) that it makes once.
- Newline-delimited JSON, one object per line, UTF-8. A line over 64 KiB is a protocol error.
- No host name check and no certificate authority: the phone accepts exactly one certificate, the one
  whose SHA-256 it got when pairing (certificate pinning).
- Default port **47830** (any port works; it is in the pairing link).
- The Mac keeps the private key **inside the login keychain** (`SecKeyCreateRandomKey`, permanent): it
  signs the certificate there and never reads the key out. Coucou imports a raw key instead, which needs
  the keychain-access entitlement a team-signed app has; an ad-hoc signed Notchy gets
  `errSecMissingEntitlement` (-34018). A new build of Notchy asks once, like its other Keychain items,
  before it may use the key again.

## Pairing

The computer shows a QR code (and a copyable link) in **Settings → General → Phone**, only after a click:

```
notchy://pair?v=1&host=192.168.1.20&port=47830&fp=<sha256 hex of the certificate>&token=<secret>&name=<computer name>
```

- `token` is 16 to 128 characters of `[A-Za-z0-9_-]`, random. It is the shared secret: it travels only
  inside the pinned TLS connection and is kept in the Keychain on both the Mac and the iPhone (the Android
  Keystore on Android).
- The phone names the computer and asks before it pairs, whether the link came from its own scanner, the
  camera app or the clipboard. A `host` that is not on a local network is refused.
- **Pair again** on the computer makes a new token: the phone that held the old one is told `auth` and
  disconnected.

## Finding the computer again

While the link is on, the computer announces itself with DNS-SD, service type **`_notchy._tcp`**, TXT
`v=1` and `fp=<first 16 hex characters of the certificate's SHA-256>` — never the token. When the saved
address stops answering, a phone looks for that service, connects to a candidate, and keeps the new
address only once the full pinned fingerprint has matched and the computer has welcomed it.

## Messages

Phone to computer:

| `type` | fields | meaning |
|---|---|---|
| `hello` | `v`, `token`, `device`, `caps` | first message; must match the pairing |
| `chatModels`, `chatSend`, `chatCancel`, `chatReset` | see Chat | cap `chat` |
| `ping` | | keep-alive, every 20 s |
| `bye` | | courtesy before closing |

Computer to phone:

| `type` | fields | meaning |
|---|---|---|
| `welcome` | `v`, `desktop`, `os`, `caps` | reply to a valid `hello`; `caps` is what this computer offers this phone now |
| `error` | `code`, `message` | `auth` closes the link and the phone stops retrying |
| `chatModels`, `chatDelta`, `chatDone`, `chatError` | see Chat | cap `chat` |
| `pong` | | reply to `ping` |

Unknown message types and unknown fields are ignored, by contract.

### Retired with the coding agents

Notchy no longer shows coding agents (November 2026), and the half of the link that carried them is gone
from the Mac, the iPhone and Android: `sessions`, `approval`, `approvalResolved`, `question` and `diff`
(computer to phone), `decision`, `answer` and `getDiff` (phone to computer), and the `details`, `diffs`,
`answers` and `character` capabilities. The protocol stays v1: a phone or computer of an older version
sends them now and then, and the other side ignores them as unknown types. Coucou's own link still
carries them; see its `docs/ANDROID_LINK.md`.

## Capabilities and the Mac's switches

A phone lists in `hello.caps` what it understands; the computer offers in `welcome.caps` the ones its
user switched on, re-read for every connection. Changing a switch disconnects the phones once so they
reconnect and learn. Off by default.

| cap | Mac switch (Settings → General → Phone) | what it adds |
|---|---|---|
| `chat` | Let the phone chat with my AI providers | chat with the providers set up in Settings → Chat |

The Mac offers nothing else, whatever a phone asks for.

## Chat (cap `chat`)

| Direction | `type` | fields |
|---|---|---|
| phone → computer | `chatModels` | ask for the list |
| computer → phone | `chatModels` | `models[]`: `{id: "provider/model", provider, label}` |
| phone → computer | `chatSend` | `id` (1–64 of `[A-Za-z0-9_-]`, made by the phone), `model`, `text` (≤ 4000) |
| computer → phone | `chatDelta` | `id`, `text` to append (pieces of at most 8 KiB) |
| computer → phone | `chatDone` | `id`; `text` only if it replaces what was streamed |
| computer → phone | `chatError` | `id`, `reason`, `message` |
| phone → computer | `chatCancel` | `id` |
| phone → computer | `chatReset` | forget the conversation |

The models are the one chosen in Settings → Chat for each provider that is set up (a key, or a local
server's address). **The provider is called from the Mac with the Mac's key, which never leaves it.** One
answer at a time per phone, 12 messages per 10 minutes, a conversation of its own in memory only (the
island's chat is not touched). `reason` is one of `off not_allowed busy rate too_long empty no_key
unreachable auth provider canceled internal`; a provider's own error text is never forwarded.

## Admission

The server answers the local network before it knows who is calling, so: only private, loopback and
link-local addresses; at most 8 connections; at most 2 unauthenticated ones per address and 4 for all
strangers together; 10 s to say hello (3 s when the pool is filling); a wrong token costs a pause; 20
minutes of silence closes a connection. (`PhoneLinkAdmission.swift`, Coucou's numbers.)

## Behaviour rules

- No telemetry. The only traffic is between the phone and its paired computer.
- Off by default. While off, nothing listens, nothing is announced, no timer runs.
- The phone keeps nothing it does not need: the chat lives in memory while it is shown.

## While the app is not in front

Nothing reaches a phone while Notchy is closed, and nothing needs to: the chat is the only thing on the
link, and it is used with the app open.

- **Android** is connected while Notchy runs. There is no foreground service, alarm, widget or
  notification any more; they existed to bring approvals and questions in.
- **iPhone** is connected while Notchy is open and for the short time iOS leaves an app after it goes to
  the background, so an answer still streaming when the phone is put away is there when it comes back.
