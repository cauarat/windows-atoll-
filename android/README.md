# Notchy for Android

The Android app of Notchy. It shows your coding agents as Mochi on your phone, and lets you approve or deny their permission
requests, answer Claude Code's questions and chat through your computer's AI providers — all over your own Wi-Fi, straight to the
computer, with nothing in between.

Ported from [Coucou for Android](https://github.com/Louis-CFM/coucou/tree/main/android) by Rhytam Biswas, part of
[Coucou](https://github.com/Louis-CFM/coucou) by Louis Raillé: **ported from Louis-CFM/coucou@202082ee0204bbc4fb78d8178cea3f0c6fcc34e4**.
The Android code is © Rhytam Biswas under the MIT License ([LICENSE](LICENSE)); Mochi, the icon and the sounds come from Coucou
(© Louis Raillé, see Coucou's `LICENSE-ASSETS.md`). Notchy as a whole is GPL v3 (see `NOTICE` at the root of this repository).

How to install and pair it: [`docs/ANDROID.md`](../docs/ANDROID.md). Needs Android 11 or later.

## What changed from Coucou for Android

- The name, the package (`com.cauarati.notchy`), the pairing link (`notchy://pair?…`), the network announcement (`_notchy._tcp`) and
  the default port (47830), so Notchy and Coucou never answer each other's phones.
- **No internet relay.** Coucou's optional relay through Cloudflare is gone, with its WebSocket client, its crypto and its settings:
  Notchy talks to the computer on the local network and to nothing else.
- English, Spanish and Brazilian Portuguese, the three languages of the Mac and Windows apps.
- The pill catalog (`core/Pills.kt`) is Notchy's own (`NotchBuddy/Sources/App/PillCatalog.swift`), plus the agent pills the Mac's hook
  server routes sessions to.
- It looks and behaves like the Mac's island and Notchy for iPhone: a black island hanging from the top of the screen with Mochi on the
  left, the session in focus with its ticker, the approval and question cards, the pills with their colour and character, and Chat
  inside the island. The values (sizes, colours, radii, washes) are the Mac's, from `IslandViewContent.swift` by way of
  `ios/Notchy/UI/IslandStyle.swift`; `ui/IslandKit.kt` is their Compose twin.
- Mochi wears Notchy's characters: the six bodies, the eyes, the eight accessories and the Christmas parts, as the computer says each pill
  wears them (cap `character`). The body tables come from `scripts/generate-mochi-shapes.mjs` and the Christmas artwork from
  `scripts/generate-mochi-festive.mjs` (`assets/festive.json`), the same generators as the Mac's and Windows'; `scripts/test-mochi-character.sh`
  compares the Kotlin tables with the Swift ones. Coucou's outfits (Settings > Mochi's wardrobe) stay, for a Mochi that wears no character.

## Build and test

Needs JDK 17 and the Android SDK (platform 35). From this folder:

```bash
./gradlew testDebugUnitTest assembleDebug lint
node scripts/gen-strings.mjs --check      # res/values*/strings.xml are generated from i18n/
```

A release build (R8 shrinking and obfuscation, resources shrunk, `android.util.Log` calls removed, not debuggable) is
`./gradlew assembleRelease`; `lint` depends on it, with a check that no debug log text is left in the APK. Signing keys are never in
the repository: set `NOTCHY_KEYSTORE_FILE`, `NOTCHY_KEYSTORE_PASSWORD`, `NOTCHY_KEY_ALIAS` (and `NOTCHY_KEY_PASSWORD` if it differs)
in the environment or in `~/.gradle/gradle.properties`. Without them the release APK is unsigned (it cannot be installed), never signed
with a debug key. CI (`.github/workflows/android.yml`) builds the debug APK on every pull request and a signed release on an
`android-v*` tag.

Without a computer: open the app and tap *Try the demo*. Or run the pretend computer (fake sessions, a fake approval; a test tool):

```bash
node tools/dev-desktop.mjs --host <LAN IP>     # prints a pairing link; flags: --details --answers --diffs --character --usage --services --fake-chat --launch
                                               # --scene sessions|approval|question holds one still picture, for screenshots
```

From the emulator the computer is `10.0.2.2`: `node tools/dev-desktop.mjs --host 10.0.2.2 --details --answers`, then
`adb shell am start -a android.intent.action.VIEW -d '<the link>'`.

The protocol is upstream's "Android link" v1 (TLS with a pinned self-signed certificate, newline-delimited JSON): the desktop side of
it is the computer's phone link.

## What it does

- **Home**: the island, as on the Mac and the iPhone: Mochi on the left (in the pill's character), and on the right the request waiting,
  Claude Code's question, or the session in focus with its last steps as the island's ticker. The header has the Home and Chat tabs,
  the link's dot, sound and Settings. Under it, one card per pill (its Mochi, project, state and lines changed), then what only the
  phone has: the link's health, plan usage, *Recent* (your own Allow/Deny decisions, kept only on the phone). A step is shown as the
  computer sent it ("Runs · npm test"); notifications, widgets and the island over other apps keep plain words (`core/ToolLabels.kt`).
- **Requests**: on Home the island holds the approval card (the command in full, Deny, Allow) and the question card (the options as
  chips); on any other screen the same card rises in a sheet. Allow and an answer need the fingerprint or screen lock, Deny does not,
  taps in the first 600 ms are ignored, and each request expires after 120 s. These screens never show in screenshots.
- **Island over other apps** (optional, off by default): a black island from the camera cut-out drops while an agent works, shows the
  result for 10 s and goes back up. Needs Android's "Display over other apps".
- **Chat** (the island's second tab, when the computer offers it), **session details**, **file changes** and **plan usage** are opt-in switches on the
  computer, all off by default; the phone is told only what it asks for and the computer allows.
- **Pairing**: scan the QR code with the in-app camera (CameraX + zxing, offline) or paste the link; a scan or a `notchy://pair` link
  always asks to confirm. The certificate is pinned. If the computer's address changes the phone finds it again by itself (mDNS,
  checked against the pinned certificate before the token is sent), or you can type the address.
- **Keeping the link alive with the screen off**: an alarm every few minutes checks that the computer still answers and reconnects if
  not; Home says when and why the link was lost; Settings > Computer > *Can't connect?* checks the network, address, discovery,
  certificate and pairing code.
- **Spoken alerts** (off by default), **request alerts** (wake the screen or not, vibration), **languages**, **theme** (System, Light,
  Dark, optional Material You), **reduce motion**, TalkBack labels everywhere.
- **Widgets**, all on one card, coloured by the most urgent agent's state:
  - *Agents summary* (3x2): a small Mochi, a headline and up to three lines.
  - *Mochi at a glance* (2x2): Mochi in the state of your most urgent agent, its name and a state word.
  - *All your agents* (4x3): one row per agent, up to five.
  - *Mochi, big* (4x4): Mochi, the agent and your plan usage, with buttons that open the app's screens.
  - *One-line status* (4x1): a slim line with four round buttons.
  - *Approvals waiting* (2x2): calm when nothing waits, bright orange "N waiting" when something does.
  - *Plan usage* (2x2): a ring for your Claude or Codex plan usage.
  - *Finished today* (2x2): agent tasks finished today, counted on this phone only.
  - *Mochi's mood* (1x1): just his face.
  - *Your team* (4x2): up to four agents you pick.

  Widgets only open a screen of the app; none approves, denies or sends anything. A request is always decided in the app, behind the
  fingerprint.
- **Quick actions** (long-press the icon): *Chat*, *Recent decisions*, *Pair again*. **Share to Notchy chat** puts shared text in the
  chat box as a draft; it is never sent by itself.
- Mochi and his outfits, sounds, wardrobe (Settings); a tap on Mochi slaps him, a long press pets him.

## Security rules the tests guard

Certificate pinning and the pairing token; approval fingerprints, 120 s expiry and decide-once; the biometric gate for Allow;
`MainActivity` ignores intent extras (only the non-exported `LaunchActivity` can ask for the Allow prompt); `FLAG_SECURE` on pairing,
chat, approval and question screens; secrets only in the Android Keystore blob; no logging of tokens or answers; no ad, billing or
analytics library.

## Layout

- `app/src/main/kotlin/.../mochi` the engine (pure Kotlin) and the Compose painter; `mochi/outfit` the outfits
- `.../link` protocol, pairing, TLS client, discovery, demo link
- `.../core` pure rules (island, navigation, safe text, home text, glance); `.../ui` Compose screens; `.../app` model, notifications,
  service, storage
- `tools/` the pretend computer and the outfit trace; `i18n/` the strings (English source and the translations)
- `reference/coucou/` upstream Coucou's desktop TypeScript the Kotlin port was checked against, vendored unchanged at the commit above:
  the parity tests read it, so a drift in the port fails the build. Pill ids are checked against Notchy's own Swift catalog.
