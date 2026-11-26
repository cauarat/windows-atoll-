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
| Windows/Linux (server) | `windows/src-tauri/src/phone_link/` (Coucou's Rust server, ported; `cargo test`), the box in `windows/src/settings/panes/phone.ts`, the island's side in `windows/src/island/phoneLink.ts` |

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
- Windows and Linux keep the certificate, its key and the token in the system keystore (Credential Manager, the Secret
  Service), in entries only Rust reads and writes (`secrets::INTERNAL_KEYS`): no window can reach them. If the keystore is
  missing the link does not start; nothing falls back to a file.

## Pairing

The computer shows a QR code (and a copyable link) in **Settings → General → Phone**, only after a click. **Copy the
link** keeps it out of clipboard histories: concealed and transient on the Mac, excluded from Windows' clipboard history
and cloud clipboard and from Linux clipboard managers, and never kept in Notchy's own.

```
notchy://pair?v=1&host=192.168.1.20&port=47830&fp=<sha256 hex of the certificate>&token=<secret>&name=<computer name>
```

- `token` is 16 to 128 characters of `[A-Za-z0-9_-]`, random. It is the shared secret: it travels only
  inside the pinned TLS connection and is kept in the Keychain on both the Mac and the iPhone (the system
  keystore on Windows and Linux, the Android Keystore on Android).
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
| `decision` | `fingerprint`, `decision` (`allow` or `deny`) | answer to an approval; no "always" from a phone |
| `answer` | `fingerprint`, `picks` (one list of labels per question) | answer to Claude's question (cap `answers`) |
| `getDiff` | `pillId`, `fileId` | the lines of one file a session changed (cap `diffs`) |
| `chatModels`, `chatSend`, `chatCancel`, `chatReset` | see Chat | cap `chat` |
| `ping` | | keep-alive, every 20 s |
| `bye` | | courtesy before closing |

Computer to phone:

| `type` | fields | meaning |
|---|---|---|
| `welcome` | `v`, `desktop`, `os`, `caps` | reply to a valid `hello`; `caps` is what this computer offers this phone now |
| `error` | `code`, `message` | `auth` closes the link and the phone stops retrying |
| `sessions` | `sessions[]` | the full list, replacing the previous one |
| `approval` | `pillId`, `fingerprint`, `tool`, `command`, `createdAt`, `truncated` | an agent waits for permission |
| `approvalResolved` | `fingerprint` | answered elsewhere or timed out |
| `question` | `pillId`, `fingerprint`, `createdAt`, `questions[]` | Claude Code asks (cap `answers`) |
| `diff` | `pillId`, `fileId`, `name`, `added`, `removed`, `tooLarge`, `gone`, `truncated`, `part`, `parts`, `lines` | cap `diffs` |
| `chatModels`, `chatDelta`, `chatDone`, `chatError` | see Chat | cap `chat` |
| `pong` | | reply to `ping` |

A session is `{pillId, agent, state, statusText, stepIndex, stepCount, updatedAt}`, plus what the phone was
offered: `steps`, `finalLine`, `project` (a folder name, never a path), `color` (details); `files` (diffs);
`character` (character). Unknown message types and unknown fields are ignored, by contract.

## Approvals and questions

- `fingerprint` is the lowercase hex SHA-256 of `pillId`, `sessionId`, `tool`, `command` and the request's
  id, joined by U+001F. The request id is new for every request (`ApprovalInfo.requestId`,
  `AskQuestion.requestId` on the Mac, the hook relay's `request_id` on Windows and Linux), so a late decision
  for one request can never answer the next.
- The computer applies a decision only for the request **still pending**, once, and not after 115 s. It
  goes through the path a click on the island takes (`HookServer.sendApprovalDecision` on the Mac,
  `pipe::answer` on Windows and Linux); the island's own card keeps working all along.
- A command is sent in full up to 500 characters; a longer one is cut and marked `truncated`, and then
  only Deny is possible from a phone (the computer refuses an `allow` for it too).
- **Allow, and an answer to a question, ask for Face ID or the phone's screen lock first.** Deny does not.
  With no screen lock set up, Allow is refused.
- A question is offered only if it fits whole (at most 4 questions of 8 options, short texts): the answer
  must carry the exact labels back. The phone has no "Other…" free text.

## Capabilities and the switches

A phone lists in `hello.caps` what it understands; the computer offers in `welcome.caps` the ones its
user switched on, re-read for every connection. Changing a switch disconnects the phones once so they
reconnect and learn. All off by default. The Mac and the PC have the same box and the same switches.

| cap | Switch (Settings → General → Phone) | what it adds |
|---|---|---|
| `details` | Show session details on the phone | steps, last line, folder name, pill colour |
| `diffs` | Show the files an agent changed on the phone | `files` per session, `getDiff` / `diff` (200 lines at most, in parts of 100, 20 requests per 10 s) |
| `answers` | Let the phone answer Claude Code's questions | `question` / `answer` |
| `chat` | Let the phone chat with my AI providers | chat with the providers set up in Settings → Chat |
| `character` | none: what Mochi wears says nothing about your work | `character: {accessory, eye, shape, festive}` per session, the Mac's stored raw values (Notchy addition) |

Neither computer offers `usage`, `services`, `recap`, `launch`, `prefs` or `relay` (Coucou capabilities the
Android app still understands). `welcome.os` is `macos`, `windows` or `linux`.

On Windows and Linux, `answers` and `diffs` are offered behind their switches as on the Mac, but carry nothing
yet: the island there has no AskUserQuestion card and keeps no per-file diffs (docs/parity, Phase 5). A question
stays in the terminal, and a `getDiff` is answered `gone`.

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
server's address); on Windows and Linux, whose Chat has Anthropic alone so far, that is its model while a key is
stored. **The provider is called from the computer with the computer's key, which never leaves it.** One
answer at a time per phone, 12 messages per 10 minutes, a conversation of its own in memory only (the
island's chat is not touched). `reason` is one of `off not_allowed busy rate too_long empty no_key
unreachable auth provider canceled internal`; a provider's own error text is never forwarded.

## Admission

The server answers the local network before it knows who is calling, so: only private, loopback and
link-local addresses; at most 8 connections; at most 2 unauthenticated ones per address and 4 for all
strangers together; 10 s to say hello (3 s when the pool is filling); a wrong token costs a pause; 20
minutes of silence closes a connection. (`PhoneLinkAdmission.swift`, `phone_link/admission.rs`, Coucou's numbers.)

## Behaviour rules

- Never block the agent: a phone that never answers changes nothing, the island's card stays usable.
- No telemetry. The only traffic is between the phone and its paired computer.
- Off by default. While off, nothing listens, nothing is announced, no timer runs.
- The phone keeps nothing it does not need: diff lines and the chat live in memory while they are shown.

## What a phone can do without the app in front

- **Android** keeps the link up in a foreground service, so approvals and questions reach it any time.
- **iPhone** has no push server here: it is connected while Notchy is open and for the short time iOS
  leaves an app after it goes to the background. Notifications (Deny, and Allow behind Face ID) and the
  Live Activity come from the app itself during that time. Reaching a locked iPhone would need Apple's
  push service (a paid developer account and a relay) or a Local Push Connectivity extension tied to a
  Wi-Fi network: possible later, not in this version.
