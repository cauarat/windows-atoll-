# Notchy for Android

The Android app of Notchy. It puts Mochi on your phone and lets you chat through your computer's AI providers — over your own
Wi-Fi, straight to the computer, with nothing in between.

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
- **No coding agents.** Coucou's agent sessions, permission requests, Claude Code's questions, file changes, plan usage, the recap,
  the service cards, the island over other apps, the notifications, the widgets, the quick-settings tile and the offline demo are
  gone, with the foreground service and the alarm that kept the link up for them. The phone link carries chat only (capability `chat`).
- Mochi is drawn as in Coucou, with its outfits; Notchy's own characters (shapes, eyes, accessories) are not on Android yet.

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

Without a computer, run the pretend computer (pairing, and a fake chat provider with `--fake-chat`; a test tool):

```bash
node tools/dev-desktop.mjs --host <LAN IP>     # prints a pairing link; flags: --port --name --token --quiet --fake-chat
```

From the emulator the computer is `10.0.2.2`: `node tools/dev-desktop.mjs --host 10.0.2.2 --fake-chat`, then
`adb shell am start -a android.intent.action.VIEW -d '<the link>'`.

The protocol is upstream's "Android link" v1 (TLS with a pinned self-signed certificate, newline-delimited JSON), cut down to chat:
the desktop side of it is the computer's phone link, described in [`docs/PHONE_LINK.md`](../docs/PHONE_LINK.md).

## What it does

- **Home**: Mochi in the black hero panel, awake while the computer is connected and asleep while it is not, and which computer it
  is. When the link was lost Home says when and why, and the way to *Can't connect?*.
- **Chat** (a tab, when the computer offers it): talk to the AI providers set up on the computer, with the history kept on the phone
  (Clear forgets it here and on the computer), light Markdown, and the model to pick. The computer's API keys never leave it.
- **Pairing**: scan the QR code with the in-app camera (CameraX + zxing, offline) or paste the link; a scan or a `notchy://pair` link
  always asks to confirm. The certificate is pinned. If the computer's address changes the phone finds it again by itself (mDNS,
  checked against the pinned certificate before the token is sent), or you can type the address.
- **Reconnecting**: the link is looked at again when the screen turns on or the network changes, and comes back by itself.
  Settings > Computer > *Can't connect?* checks the network, address, discovery, certificate and pairing code. Nothing keeps the link
  up in the background: no service, no alarm, no notification.
- **Languages**, **theme** (System, Light, Dark, optional Material You), **reduce motion**, TalkBack labels everywhere.
- **Quick actions** (long-press the icon): *Chat*, *Pair again*. **Share to Notchy chat** puts shared text in the chat box as a draft;
  it is never sent by itself.
- Mochi and his outfits, sounds, wardrobe (Settings); a tap on Mochi slaps him, a long press pets him.

## Security rules the tests guard

Certificate pinning and the pairing token; `MainActivity` ignores intent extras (only the non-exported `LaunchActivity`, for the
shortcuts, can ask it for a screen); `FLAG_SECURE` on the pairing and chat screens; secrets only in the Android Keystore blob; no
logging of tokens; nothing that runs in the background; no ad, billing or analytics library.

## Layout

- `app/src/main/kotlin/.../mochi` the engine (pure Kotlin) and the Compose painter; `mochi/outfit` the outfits
- `.../link` protocol, pairing, TLS client, discovery, diagnostics
- `.../core` pure rules (navigation, chat, share, settings, tokens); `.../ui` Compose screens; `.../app` model, storage, network and
  screen watchers, discovery
- `tools/` the pretend computer and the outfit trace; `i18n/` the strings (English source and the translations)
- `reference/coucou/` upstream Coucou's desktop TypeScript the Kotlin port of Mochi was checked against, vendored unchanged at the
  commit above: the parity tests read it, so a drift in the port fails the build.
