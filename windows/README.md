<div align="center">

<img src="src-tauri/icons/128x128.png" width="96" alt="Coucou icon">

# Coucou for Windows

**Mochi doesn't get a notch on a PC — so it lives in the corner by the clock instead.**

Approve Claude Code permissions, watch your session work, drop a file, chat with Claude, keep an eye on your services — without leaving what you're doing.

![Windows 10/11](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows)
![Tauri 2](https://img.shields.io/badge/Tauri-2-FFC131?logo=tauri&logoColor=black)
![Rust](https://img.shields.io/badge/Rust-backend-000?logo=rust)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

</div>

<img src="screenshots/greeting.png" width="640" alt="Mochi waving hello at launch">

---

## Install

Both packages are on the
[latest Windows release](https://github.com/cauarat/windows-atoll-/releases/tag/windows-latest).

### The installer

Download **`Coucou-Windows-setup.exe`** and run it. It installs for the current
user only, so there is no admin prompt, and it adds a Start Menu entry.

### The portable .zip

Download **`Coucou-Windows-portable.zip`**, unzip it somewhere you will keep it,
and run `coucou.exe`. Nothing is written outside your user profile.

`coucou-hook.exe` must stay next to `coucou.exe` — that is the layout
`ensure_hook_exe()` falls back to, and it is what makes Claude Code hooks work
without an installer. Running it from inside the .zip does not work, because
Windows only extracts the file you double-click. `Add to Start Menu.cmd` gives
it a Start Menu entry and, if you want, starts it when you sign in.

### First run

Neither package is code-signed yet, and Windows has two separate guards that
react to that. They are not the same thing and they do not have the same fix.

**SmartScreen** — *"Windows protected your PC"*. Click **More info → Run
anyway**. This one has an override.

**Smart App Control** — *"Smart App Control blocked an app that might be
unsafe"*. **This one has no override**: the dialog offers only *OK* and *Get
apps from the Store*, and there is no per-app allowance. It blocks unsigned
code outright, the portable `.zip` included, because it inspects the
executable rather than the installer.

To run Coucou on a machine with Smart App Control on, turn it off:
**Settings → Privacy & security → Windows Security → App & browser control →
Smart App Control settings → Off**. Since the April 2026 update it can be
switched back on again afterwards; before that, turning it off was permanent
short of reinstalling Windows.

The real fix is an EV code-signing certificate, which Smart App Control
trusts on sight. An OV certificate also works but only once the build has
built up reputation, which takes weeks of installs.

There is no window and no taskbar entry. Mochi sits just above the taskbar in
the bottom-right corner, next to the clock — rest the mouse there for a moment
and it peeks out — and in the notification area. **Settings… → General → Island
sits at** moves it to any of the six spots: the three along the top edge and the
three along the bottom.

Defender has previously flagged the unsigned NSIS installer as
`Trojan:Win32/Wacatac.H!ml`, a machine-learning false positive on unsigned Rust
binaries. The portable .zip has no NSIS stub and is the way around it; a real
fix needs a code-signing certificate.

## Using it

<img src="screenshots/compact.png" width="292" alt="The compact island, with the integration pills as mini Mochis">
<img src="screenshots/overview.png" width="640" alt="The overview: the focused integration on the left, the other pills on the right">
<img src="screenshots/approval.png" width="640" alt="A Claude Code permission request, with Deny and Allow">
<img src="screenshots/chat.png" width="640" alt="Chatting with Claude from the island">
<img src="screenshots/drop.png" width="640" alt="Mochi turned into a box, waiting for a file">

| What you do | What happens |
|---|---|
| Rest the mouse in the island's corner for a moment | Mochi peeks out |
| Click the small island | It opens |
| Click Mochi | It gets annoyed. Three times in a row and it goes dizzy |
| Rest the pointer on Mochi for two seconds | Hearts |
| Drag a file onto the island | Mochi turns into a box, swallows it, then offers to answer questions about it |
| `Esc` | Closes the island |
| Tray icon | Open, Settings…, Pause, Quit |

Everything else happens on its own: a Claude Code permission request opens the
island with **Deny / Allow**, a finished session shows what it did, and
your integrations sit in the coloured pills next to Mochi.

## Claude Code

<img src="screenshots/settings.png" width="562" alt="The settings window">

Open **Settings… → Claude Code → Install hooks…**. You get the exact diff of what
will change in `%USERPROFILE%\.claude\settings.json`, the path of the dated backup
that will be taken, and nothing is written until you click. Your own hooks are
never touched, and uninstalling removes only Coucou's entries.

The relay is a tiny executable, `coucou-hook.exe`, copied to
`%LOCALAPPDATA%\Coucou\bin\` at launch. It is given 300 ms to reach Coucou and
exits cleanly if the app is closed, slow or crashed — **a Claude Code session is
never blocked or slowed down by Coucou.** If nobody answers a permission request
in time, Coucou stays quiet and Claude Code asks in the terminal as usual.

It works from any terminal — Windows Terminal, PowerShell, VS Code, Git Bash.

## Chat and keys

**Settings… → Claude** takes your Anthropic API key. Keys live in the **Windows
Credential Manager**, never on disk and never in the interface — the island can
only ask whether a key exists. Same for every integration key.

No telemetry. The only network requests Coucou makes are to the services you
configure yourself.

## Build it yourself

You need [Rust](https://rustup.rs), [Node 20+](https://nodejs.org), and the
**MSVC build tools** (Visual Studio Build Tools with "Desktop development with
C++"). WebView2 ships with Windows 10/11.

```powershell
cd windows
npm install
npm run tauri dev      # live-reloading development build
npm run pack           # builds the installer and drops it in windows/release/
```

`npm run dev` alone serves the front end in an ordinary browser, which is enough
to work on the island's looks. It also serves `dev/upload-preview.html`, which
replays the whole file-drop choreography on a loop — the one part of the UI that
otherwise needs a real drag from Explorer to see. Neither page ships in the app.

`npm run pack` leaves two files in `windows/release/`, the same names the release
workflow publishes:

```
Coucou-Windows-X.Y.Z-setup.exe    the versioned installer
Coucou-Windows-setup.exe          the same file under the rolling name
```

Installing is optional — `target/release/coucou.exe` runs on its own. There is no
window in the taskbar and no console: the island in the corner of the screen and
the Mochi in the notification area are the whole app, and Quit lives in its menu.

The 28 sounds are the macOS app's own files; they are never duplicated in this
folder. The path is declared once, in `SOUNDS_DIR` at the top of
`vite.config.ts` — when they move to `shared/sounds/`, change that one line.

The app icon and the tray icon are drawn in code, like Mochi itself:

```powershell
npm run icons          # regenerates src-tauri/icons from scripts/gen-icons.mjs
```

### Layout

```
windows/
  src/                 island front end (TypeScript, no framework)
    mochi/             Mochi and the launch greeting, in Canvas 2D
    island/            state machine, hooks, integrations
    views/             every island view
    settings/          the settings window
  src-tauri/           Rust backend: window, named pipe, Claude API, pollers
  hook/                coucou-hook.exe, the Claude Code relay
  portable/            what ships inside the portable .zip beside the binaries
  scripts/             icon generator
```

### Log

`%LOCALAPPDATA%\Coucou\coucou.log` — hook events, permission decisions, poller
problems. It stays on your machine.

## What's different from the Mac version

- No notch, so the island lives against a screen edge — bottom right by default,
  above the taskbar and next to the clock — and retracts into that edge instead
  of hiding in a notch. **Settings… → General → Island sits at** offers all six
  spots. At a bottom corner the pointer has to rest in the wake strip for a
  moment, because that corner is also the route to the clock and the tray.
  Mochi has no such preference on the Mac, where it belongs to the notch.
- Permission approval works from **any** terminal; the Mac build only listens to
  VS Code sessions.
- Not in this version: sending a file by email, dragging Mochi onto a window to
  attach it as context, and jumping to a specific terminal window — "Open
  terminal" opens the working folder in VS Code when `code` is on your `PATH`.
- Cal.com shows the next bookings as a list rather than the Mac's calendar.

## Linux

The same app builds for Linux: everything that differs lives in
`src-tauri/src/platform/`, and the relay's transport in `hook/src/unix.rs`.

```bash
sudo apt install build-essential pkg-config \
  libwebkit2gtk-4.1-dev libgtk-layer-shell-dev libayatana-appindicator3-dev \
  librsvg2-dev libssl-dev libdbus-1-dev patchelf \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good
npm install
npm run tauri dev      # live-reloading development build
npm run pack           # AppImage, .deb and .rpm in windows/release/
```

What changes on Linux:

- **The island** is a gtk-layer-shell overlay anchored to the edge and corner
  you picked, on compositors that support it: COSMIC, KDE Plasma, Hyprland, Sway
  and other wlroots compositors. At the top it sits over any panel, the way the
  Mac island sits in the notch; at the bottom it keeps clear of one, so it rests
  on your panel rather than covering its clock. GNOME has no layer-shell, so there the island
  is a regular window. `COUCOU_LAYER_SHELL=0` forces that mode anywhere.
- **Click-through** is the window's input region, kept equal to the island
  shape, so the compositor sends every other click to what is underneath.
- **Mochi's eyes** follow the pointer only while it is over the island: Wayland
  gives no app the cursor position anywhere else.
- **Claude Code hooks** go through `~/.local/share/coucou/bin/coucou-hook` and a
  Unix socket at `$XDG_RUNTIME_DIR/coucou.sock`. Both ends check that the other
  runs as the same user.
- **Keys** live in the Secret Service (GNOME Keyring, KWallet).
- **Files**: preferences in `~/.config/coucou/`, the log at
  `~/.local/share/coucou/coucou.log`.
- What the Windows build leaves out, this one does too: sending a file by
  email, dragging Mochi onto a window, and jumping to a specific terminal
  window — "Open terminal" opens the folder in VS Code.
