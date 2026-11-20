# Windows ↔ Mac parity

The Windows and Linux app (`windows/`) is meant to look and behave like the Mac app (`NotchBuddy/`): every view, control, colour, size, motion, string and interaction. The Mac is the source of truth. This folder is the checklist for getting there and staying there.

On 2026-11-20 seven read-only audits compared every Swift view with its Tauri twin. They found **295 gaps**, 68 of which you notice at once side by side. Each gap names the Mac code, the Windows code, and the fix.

| Surface | Gaps | High | File |
|---|---|---|---|
| Settings window | 54 | 21 | [settings.md](settings.md) |
| ChatGPT, the site and WhatsApp Web | 41 | 11 | [web-pages.md](web-pages.md) |
| Claude Code cards and Home | 34 | 11 | [session-cards.md](session-cards.md) |
| Built-in chat and message services | 50 | 14 | [chat-messages.md](chat-messages.md) |
| The island, its ring and pills | 38 | 4 | [island-chrome.md](island-chrome.md) |
| Feature views | 46 | 4 | [feature-views.md](feature-views.md) |
| Welcome, Mochi, tray and updater | 32 | 3 | [onboarding-mochi-shell.md](onboarding-mochi-shell.md) |

Gap ids repeat between some reports, so three surfaces are prefixed: `SC-` (Claude Code cards), `IC-` (island chrome) and `OB-` (welcome, Mochi, tray).

## Owner decisions (2026-11-20)

- **Always.** The whole Windows app follows the Mac's design and UX, low-severity gaps included. `CLAUDE.md` carries the rule.
- **Placement.** Windows keeps **bottom-right** as its default, and keeps always-visible as the default that goes with it (IC-G01, IC-G03).
- **Windows-only extras.**
  - **Standby** is removed (W-15).
  - These stay, and are redrawn the Mac way: the **Never** hide button, the **Integrations** and **Site** header tabs, the **Pages** card (site URL), the key **Remove** button, and the file-drop **Cancel**.
- **The Mac gets "Never".** The Mac's Behavior group swaps its "Always visible" checkbox for the same Never button beside "Hide after … s without movement", on the same setting. W-14 lands that way on both sides.
- **Radial menu.** It is reworked with the owner on the Mac until it is useful, then ported (W-32, IC-G07).
- **Mac-side fixes need a yes first.** Until then, Windows copies the Mac:
  - SC-G05: the approval target shows only the tool name.
  - SC-G21: the error card is a static mock.
  - CHAT-15 / UP-6: a file dropped after chatting is ignored.
  - Only the first text block of a web-search answer is kept.
  - Allow, Deny, Always, Retry and OK are untranslated.
- **Not done:**
  - MSG-35: AAC encoding.
  - OB-G29: the crash-recovery note.
  - OB-G31: tray shortcuts.
  - IC-G36: window level.
  - The notch row of W-17 and the Accessibility row of W-32 are platform-forced.

## Phases

Each phase is one branch, one PR into `notchy`, merged when CI is green.

| Phase | What changes |
|---|---|
| 0 | This checklist, the `CLAUDE.md` rule, page windows no longer fetch at launch, comparison tooling |
| 1 | Settings looks like the Mac: sidebar, panes, light/dark, macOS controls, every existing row in its Mac pane |
| 2 | Settings flows: models, ChatGPT switch + clear data, service sign-in blocks, open shortcut, update window, tray |
| 3 | ChatGPT and the site drawn inside the island (child webview on Windows, glued window on Linux) |
| 4 | Island look: black cards, Mac sizes, resting tab/bar, displays, motion, ring visuals |
| 5 | Claude Code: approval card, Always, AskUserQuestion, finished files and diffs, terminal, AI Agents |
| 6 | Built-in chat (Markdown, providers, streaming) and message services (cards, inbox, Windows notifications) |
| 7 | Radial menu (Mac first, then Windows), Escape from any app, island behaviour and sounds |
| 8 | Feature views, Mochi wearing the user's character, welcome |
| 9 | Final side-by-side sweep; `windows/README.md` "What's different" reduced to the forced and owner-chosen items |

## Comparing the two

- **Mac references.** `bash scripts/capture-mac-reference.sh` captures the real Settings window, one pane at a time, in light and dark, into `design/captures/parity/`. That folder is gitignored: a Settings capture shows the account's names, server addresses and sign-in emails, so each Mac takes its own. Island views are rendered offscreen with ImageRenderer instead, from Phase 4 on.
- **Windows renders.** `cd windows && ./node_modules/.bin/vite`, then open `/dev/compare.html`. It shows a Mac capture beside any Windows page, side by side, as a difference overlay, or faded over it.
- **The real thing.** A side-by-side check on a Windows PC closes each phase. SSH cannot take Windows GUI screenshots, so that check runs in a session on the PC's own desktop.
