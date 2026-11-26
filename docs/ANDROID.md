# Notchy on Android

Mochi on your phone, and a chat with the AI providers set up on your computer. Notchy for Android pairs with Notchy on your
computer and lets you talk to the providers you set up there; their API keys never leave the computer.

The phone talks to your computer **directly, over your own Wi-Fi**. There is no account, no server and no relay in between, and
nothing is sent anywhere else.

## What you need

| | |
|---|---|
| **Phone** | Android 11 or later |
| **Computer** | Notchy on a Mac, with the phone link (Settings → General → **Phone**). Windows and Linux do not have it yet |
| **Network** | The phone and the computer on the **same Wi-Fi** |

## Install

1. On the phone, open the [Releases](https://github.com/cauarat/windows-atoll-/releases) page and download the newest
   `Notchy-Android-<version>.apk` (an `android-v…` release).
2. Open the downloaded file. Android asks to allow installs from your browser or file manager the first time: allow it, then
   **Install**.
3. Open Notchy.

## Pair it with your computer

1. On the Mac, open Notchy's **Settings → General → Phone** and turn on **Link my phone to this Mac**. It is off by default, and
   listens on your local network only. If macOS asks whether Notchy may accept incoming connections or find devices on your local
   network, allow it.
2. Click **Show the pairing code**. A QR code appears.
3. On the phone, tap **Scan QR code** and point the camera at it (or scan it with the phone's own camera app, or paste the link).
   The phone names the computer and asks you to confirm.
4. Home shows Mochi awake and the name of your computer: you are connected.

Pairing again on the computer replaces the code: the phone that had the old one is disconnected.

## What you can do

| On the phone | How |
|---|---|
| **Chat** | When the computer allows it (**Let the phone chat with my AI providers** on the Mac): talk to the providers set up on the computer. Its API keys never leave the computer |
| **Share to Notchy** | Share text from another app: it lands in the chat box as a draft, never sent by itself |
| **Mochi** | Awake while the computer is connected, asleep while it is not. Tap him, hold him, dress him (Settings → Mochi's wardrobe) |

## Troubleshooting

**The phone says "Connecting…" or cannot find the computer**
- The phone and the computer must be on the same Wi-Fi. Guest networks and hotspots often keep devices apart ("client isolation").
- Notchy must be running on the computer with the phone link on, and the computer awake.
- A firewall must let Notchy accept connections on your private network.
- In the app: **Settings → Computer → Can't connect?** checks each step and says which one fails. You can also type the computer's
  address by hand.

**The Chat tab says chat is off**
- On the Mac, turn on **Let the phone chat with my AI providers** and set up at least one provider in Settings → Chat.

## Privacy

- The link is TLS, pinned to your computer's own certificate, and the pairing code never leaves the phone and the computer.
- The phone never receives your API keys. The chat history is kept on the phone only, and **Clear** forgets it there and on the
  computer.
- Nothing runs in the background: the phone is connected while Notchy is running.
- No account, no analytics, no ads.

Building it yourself: [`android/README.md`](../android/README.md).
