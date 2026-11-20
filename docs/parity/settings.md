# Parity — Settings window

The Mac is the source of truth (see `CLAUDE.md`). Each gap names the Mac code, the Windows code and the fix; tick it in the PR that closes it. Audit of 2026-11-20 against `notchy` at f1dee26.

## Checklist

- [x] **W-01** · high · visual · L — No sidebar: Windows is one long scrolling page; Mac is a 200pt sidebar with 9 panes — _Phase 1_
- [x] **W-02** · high · visual · M — Window size and placement differ (560x680, min 460x480 vs 720x560, min 640x420) — _Phase 1_
- [x] **W-03** · high · visual · M — Forced dark theme; Mac follows the system light/dark appearance with native colours — _Phase 1_
- [x] **W-04** · high · visual · M — Every toggle is a green iOS switch; Mac uses checkboxes (and small accent switches only in Hydration) — _Phase 1_
- [x] **W-05** · high · visual · M — Buttons are pills; Mac uses native push buttons (prominent blue, bordered grey, link, small) — _Phase 1_
- [x] **W-06** · high · visual · M — Cards with an inside h2 instead of macOS GroupBoxes (title above the box) — _Phase 1_
- [x] **W-14** · high · copy · S — Behavior rows renamed and restructured (Auto-close, Hide after + Never pill) vs 'Close after … s inactive' / 'Always visible' / 'Hide after … s without movement' — _Phase 1_
- [ ] **W-16** · high · behaviour · L — Displays: 'Island lives on' (Main display / Display under the cursor) instead of the Mac All displays / Only selected + per-display checkboxes — _Phase 4_ (partial: the Displays GroupBox draws a Mac radio group over today's two choices; per-display checkboxes are Phase 4)
- [ ] **W-18** · high · missing on windows · M — Hotkey: 'Show island with shortcut' missing; close row renamed 'Close shortcut' — _Phase 2_ (partial: the Hotkey GroupBox and the close-shortcut rows are the Mac's; 'Show island with shortcut' is Phase 2)
- [x] **W-21** · high · missing on windows · M — Active pills pane missing; pill switches scattered across Integrations and Messages — _Phase 1_
- [x] **W-23** · high · behaviour · M — Home shows: 'Notifications' option and the Mac default missing; automatic hint truncated — _Phase 1_
- [x] **W-24** · high · missing on windows · M — Dynamic Island pane with its segmented Layout/Content/Activity/Behavior tabs missing — _Phase 1_
- [x] **W-25** · high · behaviour · M — Ring editor: different title, hint, empty text, side names/order, add control, add side, reorder and remove controls — _Phase 1_
- [ ] **W-32** · high · missing on windows · L — Radial menu pane missing — _Phase 7_
- [ ] **W-33** · high · missing on windows · L — AI Agents pane missing (and no AI Agents panel at all on Windows) — _Phase 5_
- [ ] **W-34** · high · behaviour · M — Chat › Anthropic API: wrong title, button text, model list, default model; no live model list or Custom… — _Phase 2_ (partial: GroupBox 'Anthropic API', Save, divider, Model popup and hint; live list, Custom… and the default model are Phase 2)
- [ ] **W-35** · high · missing on windows · L — 'Chat — other providers' (Google AI, OpenAI) missing — _Phase 6_
- [ ] **W-36** · high · missing on windows · L — 'Local models' (Ollama, LM Studio) missing — _Phase 6_
- [ ] **W-37** · high · missing on windows · M — ChatGPT (website): Windows has one switch in a 'Pages' card; Mac has a ChatGPT group with two toggles and Clear data — _Phase 2_ (partial: 'ChatGPT (website)' with 'Open it from the chat tab'; the master switch and Clear ChatGPT data are Phase 2)
- [ ] **W-40** · high · behaviour · M — Mattermost block: per-field Save rows and 'Forget sign-in' instead of the Mac form + single Sign In/Sign Out + status chip — _Phase 2_ (partial: header, chip, Mac placeholders, Sign In with spinner, Open with and footer; the single-form flow is Phase 2)
- [ ] **W-41** · high · behaviour · M — Ato block: same form mismatch; no auto-enable pill or orange no-slot note; password kept — _Phase 2_ (partial: header with logo, chip, Mac copy and fields; the single form, pill auto-enable and digest-only storage are Phase 2)
- [x] **W-07** · medium · visual · S — Type scale, colours and label layout differ (12px dim hints, 12.5px dim 132px label column) — _Phase 1_
- [x] **W-08** · medium · visual · M — Popups, sliders, text fields and segmented controls do not look like macOS controls — _Phase 1_
- [x] **W-09** · medium · behaviour · S — No bottom status bar; feedback is inline notice pills per section — _Phase 1_
- [x] **W-10** · medium · visual · S — Master switch: separate card with status dot and warn notice; Mac has a GroupBox 'Notchy' checkbox in General — _Phase 1_
- [x] **W-11** · medium · copy · S — Your name: label row and short hint instead of the Mac GroupBox with the welcome button — _Phase 1_
- [x] **W-12** · medium · copy · S — Language: inline row with a one-line hint instead of a GroupBox with the full explanation — _Phase 1_
- [x] **W-13** · medium · behaviour · S — Sound: no 'Enable sounds' label, no % readout, slider not disabled when off — _Phase 1_
- [x] **W-15** · medium · extra on windows · S — 'Standby' row exists only on Windows — _Phase 1 — Standby removed (owner)_
- [ ] **W-17** · medium · platform forced · M — Notch height group missing — _Phase 4_
- [ ] **W-20** · medium · platform forced · M — Updates: inline downloader card instead of the Mac's minimal group (Sparkle window does the rest) — _Phase 2_ (partial: the Updates group has the Mac's three rows; today's states sit on one line under them until the Phase 2 window)
- [x] **W-22** · medium · behaviour · S — Pill at 4/4: Mac disables and greys the row; Windows silently ignores the click — _Phase 1_
- [ ] **W-26** · medium · missing on windows · S — Built-in 'AI Agents' ring action missing from EDGE_ACTIONS — _Phase 4 (site) / Phase 5 (AI Agents)_
- [ ] **W-27** · medium · missing on windows · M — 'Big screen' group (large island width/height) missing — _Phase 3_
- [x] **W-28** · medium · copy · S — Christmas toggles live in General with shortened hints; Mac has a 'Christmas' GroupBox under Dynamic Island › Layout — _Phase 1_
- [x] **W-29** · medium · visual · S — Skip back/forward: number fields in General instead of Steppers in Dynamic Island › Content › 'Now Playing' — _Phase 1_
- [x] **W-31** · medium · copy · S — 'Island sits at' is a General row with a short hint; Mac has GroupBox 'Where it sits' under Behavior — _Phase 1_
- [x] **W-38** · medium · extra on windows · S — 'Site' URL field and the 'Pages' card exist only on Windows — _kept — the Pages/Site field stays, Mac-styled, in Phase 1 (owner)_
- [ ] **W-39** · medium · missing on windows · M — Integrations › Messages: 'Also show a macOS notification' missing; the 'Show the whole message' layout differs — _Phase 2_ (partial: 'Messages' caption and 'Show the whole message'; the Windows notification checkbox is Phase 2)
- [ ] **W-42** · medium · missing on windows · M — Agenda: separate card; missing status chip, own sign-in, Refresh now and Open the commercial panel; different copy — _Phase 2_ (partial: inside Integrations with header, chip and checkboxes; its own sign-in and buttons are Phase 2)
- [ ] **W-43** · medium · behaviour · S — WhatsApp block: different buttons and states; 'Open with' missing; the no-slot note is a red error — _Phase 2_ (partial: Mac labels, chip, orange no-slot note and Open with; Unlink-only-when-linked is Phase 2)
- [ ] **W-44** · medium · behaviour · M — 'Open with': free-text path fields in General instead of a per-service popup + Choose… — _Phase 2_ (partial: an 'Open with' row in each service block, still a typed path; the popup and Choose… are Phase 2)
- [x] **W-45** · medium · copy · S — Characters: hide switch row with a short hint instead of its own GroupBox with the full text — _Phase 1_
- [x] **W-46** · medium · visual · S — Characters: section headings lack 'for <name>'; no 'Wearing and eyes' heading; Wearing/Eyes on one row — _Phase 1_
- [x] **W-47** · medium · visual · S — Character tiles: sizes, font, fill, hover and the Christmas badge colour differ — _Phase 1_
- [x] **W-48** · medium · missing on windows · S — Characters: 'Use the default for this one' and 'Keeping a face of their own… / Give them the default too' missing; Ato listing rule differs — _Phase 1_
- [x] **W-49** · medium · behaviour · M — Hydration main: off-state buttons missing; headings instead of GroupBoxes; several row behaviours differ — _Phase 1_
- [x] **W-50** · medium · visual · M — Hydration sub-screens: back control, titles, order and visuals differ from the Mac — _Phase 1_
- [x] **W-52** · medium · behaviour · S — Settings cannot be opened on a specific pane — _Phase 1_
- [x] **W-19** · low · visual · S — Startup: switch row 'Launch at startup', not a GroupBox checkbox; the defaults disagree — _Phase 1_
- [x] **W-30** · low · copy · S — Info groups 'What the island carries', 'What it shows by itself', 'Opening' missing — _Phase 1_
- [ ] **W-51** · low · behaviour · S — Tray menu: no permanent 'Check for Updates…'; the update item is untranslated — _Phase 2_
- [x] **W-53** · low · extra on windows · S — Windows-only extras with no Mac twin (header h1, footer, key Remove, status lines, Credential Manager notes) — _Phase 1_
- [x] **W-54** · low · behaviour · S — Opening Settings does not fold the island — _Phase 1_

## How each side is built

MAC (source of truth). Window: AppDelegate.openSettings (AppDelegate.swift:189-213) builds an NSWindow 720x560 content, min 640x420, styleMask titled|closable|miniaturizable|resizable, standard title bar with traffic lights, title "Settings — Notchy" (re-translated on language change, :102). Before showing it folds the island (closeScreen/collapse, :193-194) and places the window horizontally centred on the active allowed display with its top 12pt under the island (placeBelowIsland :217-236). Closing keeps it (isReleasedWhenClosed=false). Deep links: posting .openFullSettings with a section id writes UserDefaults "settingsSection" first ("island" from the ring gear and the radial, "integrations" from the island, "hydration" from the hydration card).
Body (SettingsView.swift:121-198) is an HStack:
- SIDEBAR, 200pt wide, NSVisualEffectView .sidebar material with behind-window vibrancy (:1226-1235). Header: app icon 32x32, "Notchy" 13pt semibold, version 11pt secondary, optional build stamp 10pt monospaced at secondary 70%; padding h16/top16/bottom10; then a Divider. Then List(.sidebar) whose rows are Label(title, icon) with an SF Symbol 11pt semibold white on a 20x20 rounded rect (radius 5) filled with the row colour (:1239-1255). Rows in order: General (gearshape.fill #8E939C), Active pills (square.grid.2x2.fill #F5A524), Dynamic Island (capsule.fill #EC4899), Radial menu (circle.grid.cross.fill #F472B6), AI Agents (sparkles #E07950), Chat (bubble.left.and.bubble.right.fill #E07950), Integrations (puzzlepiece.extension.fill #7C5CFF), Characters (face.smiling.inverse #2DD4BF), Hydration (drop.fill #22D3EE). The selection is persisted in "settingsSection" (default "general") and is drawn as the native accent-coloured rounded selection.
- A vertical Divider.
- DETAIL: the pane title in .title2 (17pt) semibold, padding h20/top20/bottom12. Below it a ScrollView with VStack spacing 18 and padding h20/bottom16. At the bottom, an optional status bar (Divider plus 12pt text; red when the text starts with ❌) that shows every save/connect message.
Every pane is a stack of native GroupBoxes. A GroupBox has its title above a rounded, faintly filled box; content is padded 6. Toggles without .toggleStyle are macOS CHECKBOXES (label on the right). Pickers are popup buttons. Buttons are native push buttons (.borderedProminent means accent blue). Fields are .roundedBorder. Everything follows the system light/dark appearance.
Mac pane tree:
1 General: GroupBox "Notchy" [checkbox "Notchy is on/off" + hint ending "…from the menu bar."] · "Your name" [TextField with placeholder = macOS first name or "Your first name"; hint "Mochi greets you by this name…"; button "Show the welcome again…"] · "Language" [popup: Same as system/English/Español/Português (Brasil); long hint] · "Sound" [checkbox "Enable sounds"; "Volume" (56pt) slider 0–0.2, disabled when off, "NN %" (36pt)] · "Behavior" ["Close after [5] s inactive" (64pt field, clamp 2–120); checkbox "Always visible" (default OFF); "Hide after [180] s without movement" (clamp 5–3600, disabled while Always visible)] · "Displays" [radio group All displays / Only selected; one checkbox per connected display (the last one cannot be unticked); note for remembered-but-unplugged displays; hint] · "Notch height" [toggle "Notch display height" → slider 32–60 (default 40) "NN pt", or "Matches the cutout"; Divider; toggle "Non-notch display height" → slider 22–60 (default 32), or "Matches the menu bar"; hint] · "Hotkey" [checkbox "Show island with shortcut" → "Shortcut" (70pt) recorder (⌘⇧N) + "presses this → island opens"; checkbox "Close island with shortcut" → recorder (⌃⌥X) + "presses this → island closes" + refusal line] · "Startup" [checkbox "Launch at Mac startup"; errors go to the status bar] · "Updates" ["Notchy x.y.z" ……… "Check for updates" (disabled while checking); checkbox "Check automatically"; hint]. Sparkle shows its own window for available/install.
2 Active pills: one GroupBox [hint "Choose the tools you use…"; "N/4 slots used" (orange at 4); popup "Home shows" (Notifications [default], Last message, Ato, Mattermost, WhatsApp, Timer, Claude Code) + hint; Divider + caption "Where you code" → Claude Code dot + "Always on"; Divider + caption "Services" → Now Playing, Mattermost, Ato, WhatsApp, Notifications, each a 10pt dot + 12pt name + trailing checkbox, disabled and greyed at 4/4].
3 Dynamic Island: segmented Layout|Content|Activity|Behavior (persisted "islandTab"). Layout: "Buttons around the island" (hint + ring editor), "Big screen" (Width/Height toggles + slider step 10, 360–600 / 240–800, defaults 600/650), "Christmas" in season (checkboxes "Snow on the island" and "Christmas music when Notchy starts", each with a full hint). Content: "What the island carries" (note + "Set these under Active pills."), "Now Playing" (hint, Steppers "Skip back"/"Skip forward" showing "10 s", hint). Activity: "What it shows by itself" note. Behavior: "Where it sits" (popup "Island sits at" with 6 presets + "Where you dropped it"; hold-to-drag hint), "Opening" note.
4 Radial menu: GroupBox [checkbox "Use the radial menu"; hint; permission row; trackpad hint] · "What is on the wheel" [hint 2–8; slot rows with icon + popup + ⌃ ⌄ ⊖; menu "+ Add"].
5 AI Agents: GroupBox [checkbox "Show AI Agents"; hint; "Open AI Agents"] · "What it reads" [3 monospaced lines + footer] · "Right now" [account dot + label; note; "N sessions running."].
6 Chat: "Anthropic API" [SecureField "API key (sk-ant-…)", Save (prominent); Divider; popup "Model" (live from /v1/models, fallback Sonnet 4.6/Sonnet 5.5/Opus 5.5/Haiku 4.5, + "Custom…" → TextField "Model ID (e.g. claude-sonnet-4-6)"); hint] · "Chat — other providers" [Google AI key + Save; OpenAI key + Save] · "Local models" [Ollama and LM Studio: URL + Connect/Connecting…, or URL + Disconnect, with "Connected"] · "ChatGPT (website)" [checkbox "Show ChatGPT in the notch"; checkbox "Open it from the chat tab" (disabled unless the first is on); hint; "Clear ChatGPT data" + note].
7 Integrations: one GroupBox [caption "Messages"; checkbox "Also show a macOS notification" + hint; checkbox "Show the whole message" + hint; Mattermost block; Ato block; Agenda block; WhatsApp block]. Each block: header (logo/dot + name + status chip on the right), fields, Sign In/Sign Out row, "Open with" [popup Website|App] + "Choose…", footer.
8 Characters: GroupBox [checkbox "Hide the characters" + long hint] · GroupBox (opacity 0.4 and disabled when hidden) [hint; popup "Character for"; "Body  for X" 7-col tiles; "Face  for X" 6-col; "Wearing and eyes  for X" + popups "Wearing" and "Eyes"; Christmas block; "Use the default for this one"; "Keeping a face of their own…" + "Give them the default too"].
9 Hydration: main [GroupBox checkbox "Hydration reminders" + hint; if on: GroupBoxes "Your goal", "Reminders" (with timeline), "When not to notify"; if off: "Answer the questions" + link "Where the numbers come from"]. The questions, estimate, manual and sources screens replace the pane, each with a "‹ Back" link.

WINDOWS (now). Window: lib.rs:1024-1051 creates WebviewWindow "settings" hidden at launch: 560x680, min 460x480, resizable, native Windows decorations, centred once; document.title sets the title (main.ts:2469). Opening only shows and focuses it (lib.rs:1117-1125): no island fold, no placement, no section argument. settings.html forces a dark body (#0b0c0e/#f5f6f8) and settings.css sets color-scheme: dark, so there is no light theme.
Layout: ONE vertical scrolling column (#settings-root: padding 22/24/32, max-width 720, gap 18) with no sidebar. Header h1 "Notchy" 17px/600 + version 12px. Then stacked cards (section: bg #141518, 1px rgba(255,255,255,.07) border, radius 14, padding 16/18, gap 12, h2 13px/600 inside the card). Rows are flex with a 132px dim (#9398a1, 12.5px) label column on the left and controls to the right. All toggles are green (#22c55e) 36x20 iOS-style switches. Buttons are pills (radius 999) with white-alpha fill; "primary" is a white fill with dark text; "danger" is a red tint. Inputs: radius 8, white 7% fill. Selects use the native popup.
Section order (main.ts:2471-2488): 1 [● Notchy] master row + hint ("…from the icon by the clock.") + warn notice when off · 2 [● Claude] status line, "API key" + "Save key" + "Remove", "Model" select (Opus 5/Sonnet 5/Haiku 4.5) · 3 [Integrations] slot note + switch rows for Notifications and Now Playing only · 4 [Messages] "Show the whole message", 2 hints, Mattermost and Ato blocks (pill switch, per-field credential rows each with its own Save + dot, "Session" Sign in + Forget sign-in), WhatsApp block (pill switch, Show QR code + Unlink) · 5 [Agenda] toggle + lead select + 2 switches · 6 [Hydration] switch + panel with h3 groups and the 4 sub-screens · 7 [On the island's border] ring rows (dot, name, side select Row/Left/Right, ↑, Remove) + "Add" select · 8 [Pages] Site URL + "Chat tab opens ChatGPT" · 9 [Characters] hide switch row + picker · 10 [General] Your name, Language, Sound, Auto-close, Close shortcut, Skip back, Skip forward, Mattermost opens, Ato opens, Hide after + [Never], Standby, (season) Snow, Christmas music, Home shows, Island lives on, Island sits at, Launch at startup, Show the welcome again… · 11 [● Updates] inline check/download/install/progress/notes + "Check automatically" · footer "No telemetry…". Missing entirely: Active pills pane, Dynamic Island pane (tabs, Big screen), Radial menu, AI Agents, other chat providers, local models, ChatGPT master switch and clear-data, message banners, Displays, Notch height, open-island hotkey.

How Windows should be organised to mirror the Mac: split main.ts (2512 lines, one file) into settings/shell.ts (sidebar + detail + status bar, section routing persisted in localStorage "settingsSection", plus deep-link argument), settings/controls.ts (macCheckbox, macSwitchSmall, popup, segmented, stepper, slider, groupBox, pushButton(prominent|bordered|link|small), statusChip), and settings/panes/{general,activePills,island,radial,agents,chat,integrations,characters,hydration}.ts, one file per Mac *SettingsView. Put the sidebar table (id, title, icon, colour, order) in a shared data file that a parity test compares against Swift.

## Gaps

### W-01 — No sidebar: Windows is one long scrolling page; Mac is a 200pt sidebar with 9 panes

- **Mac:** `NotchBuddy/Sources/App/SettingsView.swift:121-198, 222-251, 1226-1255` — HStack with a 200pt sidebar on NSVisualEffectView .sidebar vibrancy. Header: 32x32 app icon, 'Notchy' 13pt semibold, version 11pt secondary. Divider, then List(.sidebar) with 9 rows (General, Active pills, Dynamic Island, Radial menu, AI Agents, Chat, Integrations, Characters, Hydration). Each row has a 20x20 rounded (r5) colour tile with a white 11pt semibold symbol. Selection is persisted in 'settingsSection' (default general). Detail pane: title 17pt semibold (padding 20/20/12), then scroll content with 18pt spacing and padding 0 20 16.
- **Windows:** `windows/src/settings/main.ts:2463-2489; windows/src/settings/settings.css:35-70` — One centred column (max-width 720) holding 11 stacked cards plus an h1 'Notchy' + version and a footer. You have to scroll through everything, and the order matches no Mac pane.
- **Fix:** Rebuild repaint() (main.ts:2463) as a shell: <aside class=sidebar width:200px> containing the header (img 32x32 from the app icon, 'Notchy' 13px/600, version 11px secondary) + a 1px divider + 9 rows (height ≈28px, padding 0 8px, gap 8px, icon tile 20x20 r5 with the Mac hex colours and a white glyph drawn as inline SVG, label 13px). The selected row gets an accent fill (#0A84FF dark / #007AFF light) with white text and r5 (grey rgba(128,128,128,.2) when the window is unfocused). Then a 1px vertical divider and a <main> with h1 17px/600 (padding 20px 20px 12px) and a scroll container (padding 0 20px 16px, gap 18px). Persist the selection in localStorage 'settingsSection' (default 'general'). Move each existing section into the pane the Mac puts it in (see the gaps below). Delete the h1 version header and the 'No telemetry' footer.
- **Phase:** Phase 1

### W-02 — Window size and placement differ (560x680, min 460x480 vs 720x560, min 640x420)

- **Mac:** `NotchBuddy/Sources/App/AppDelegate.swift:189-236` — 720x560 content, min 640x420, resizable/miniaturizable. On every open, the island is folded first (closeScreen/collapse) and the window is centred horizontally on the active allowed display, with its top 12pt under the island; the height shrinks to fit.
- **Windows:** `windows/src-tauri/src/lib.rs:1024-1051, 1117-1125` — 560x680, min 460x480, centred once at creation on the primary monitor. Open only unminimizes/shows/focuses it; the island is not folded.
- **Fix:** lib.rs:1032-1033 → .inner_size(720.0, 560.0).min_inner_size(640.0, 420.0). In show_settings_window, collapse the island (same path as Esc) and position the window: x = monitor work-area centre − w/2; y = island rect bottom + 12 for a top-edge island (or work-area centre for a bottom island). Clamp the height to the work area. Use the monitor under the island (island::window → current_monitor).
- **Phase:** Phase 1

### W-03 — Forced dark theme; Mac follows the system light/dark appearance with native colours

- **Mac:** `NotchBuddy/Sources/App/SettingsView.swift:121-198 (SwiftUI semantic colours, .secondary, Divider, GroupBox, .sidebar material)` — Light mode: light sidebar vibrancy, window background ≈#ECECEC, primary text black 85%, secondary black 50%, GroupBox fill black ≈4%. Dark mode: dark sidebar vibrancy, window background ≈#1E1E1E–#262626, text white 85%, secondary white 55%, GroupBox fill white ≈5%. The accent is the system blue.
- **Windows:** `windows/settings.html:8; windows/src/settings/settings.css:3-33` — Always near-black #0b0c0e with #141518 cards, #f5f6f8 text and #9398a1 dim text. color-scheme: dark is hard-coded and the inline body style forces dark even before the CSS loads.
- **Fix:** Drop the inline style in settings.html and 'color-scheme: dark' in settings.css. Define tokens under :root with @media (prefers-color-scheme: light) and (dark): --window-bg, --sidebar-bg (translucent: dark rgba(40,40,44,.85), light rgba(232,232,236,.85); optionally enable Mica via window-vibrancy on Windows 11), --label (rgba(0,0,0,.85) / rgba(255,255,255,.85)), --secondary (rgba(0,0,0,.5) / rgba(255,255,255,.55)), --separator (rgba(0,0,0,.1) / rgba(255,255,255,.1)), --box-fill (rgba(0,0,0,.04) / rgba(255,255,255,.05)), --accent (#007AFF / #0A84FF). Set color-scheme: light dark so native popups follow. Leave the Tauri window theme unset so the title bar follows the OS.
- **Phase:** Phase 1

### W-04 — Every toggle is a green iOS switch; Mac uses checkboxes (and small accent switches only in Hydration)

- **Mac:** `SettingsView.swift:258,318,341,402,416,440,454,667-668,704,712,1095,1138-1140,1213-1218; IslandSettingsView.swift:80,90,111; RadialSettingsView.swift:12; AgentsSettingsView.swift:14; CharacterSettingsView.swift:319; HydrationSettingsView.swift:32,92-93,160-161,170-171,188` — A Toggle with no style inside a GroupBox renders as a native checkbox: 14x14 rounded square, label 13pt to the RIGHT, ticked state filled with the accent blue and a white check. Only Day streak, Quiet hours and 'Today is hot or I moved more' use .toggleStyle(.switch).controlSize(.small): a small switch with an accent-blue track. Pill rows use a label-hidden checkbox on the trailing edge.
- **Windows:** `windows/src/settings/main.ts:108-116 (toggle), 169-186 (pillToggle); settings.css:161-189` — A 36x20 switch with a green #22c55e track for every boolean, placed to the right of a 132px label column.
- **Fix:** Add controls.ts macCheckbox(label, on, onChange): <label class=cb><input type=checkbox><span>label</span></label>. Style it 14x14, r3.5, 1px border var(--separator), fill var(--box-fill), checked fill var(--accent), white ✓ glyph, 6px gap, 13px label in var(--label), disabled at 0.4. Use it wherever the Mac has a plain Toggle. Restyle .switch as the macOS small switch (≈26x15, track var(--accent) when on, rgba(128,128,128,.3) when off, white knob with a subtle shadow, no green) and use it only for the 3 Hydration rows.
- **Phase:** Phase 1

### W-05 — Buttons are pills; Mac uses native push buttons (prominent blue, bordered grey, link, small)

- **Mac:** `SettingsView.swift:516-520, 605-609, 614-622, 676-682, 857-884, 1143-1148, 1181-1185; HydrationSettingsView.swift:45-46, 87-88, 410-417` — .borderedProminent: accent-blue filled rounded rect (r≈5-6, height ≈22pt regular, 13pt white text). Default/.bordered: grey filled push button (dark rgba(255,255,255,.12), light white with a hairline border and shadow). .link: accent-coloured text with no chrome. .controlSize(.small): ≈18pt tall, 11pt text. .borderless icon buttons (chevrons, minus.circle) are bare glyphs.
- **Windows:** `windows/src/settings/settings.css:102-151` — Padding 7x14, radius 999, rgba(255,255,255,.09) fill. 'primary' is a white fill with black text; 'danger' is a red tint. Buttons scale to 0.96 on press.
- **Fix:** settings.css: button { height:22px; padding:0 10px; border-radius:6px; font:400 13px var(--font); background: var(--button-bg); box-shadow: 0 0.5px 1px rgba(0,0,0,.15) } .prominent { background: var(--accent); color:#fff } .link { background:none; color: var(--accent); padding:0 } .small { height:18px; font-size:11px; padding:0 7px; border-radius:5px } .borderless { background:none; padding:2px; color: var(--secondary) }. Remove the scale-on-press transform. Replace class 'primary' with 'prominent' everywhere the Mac uses .borderedProminent; drop 'danger' (the Mac has no red buttons).
- **Phase:** Phase 1

### W-06 — Cards with an inside h2 instead of macOS GroupBoxes (title above the box)

- **Mac:** `SettingsView.swift:256-465 (every GroupBox), 472, 512, 551, 586, 665, 695` — GroupBox('Title'): a regular-weight title in the label colour (≈11–13pt), left-aligned ABOVE a rounded box (r≈6) with a faint fill and hairline edge; content inset by the box plus .padding(6). Some boxes have no title (Active pills, Integrations, AI Agents first box, Characters, Hydration main toggle). Boxes are separated by 18pt.
- **Windows:** `windows/src/settings/settings.css:55-70; main.ts every h('section', …, h('h2' …))` — Cards r14, padding 16/18, bg #141518, with a bold 13px h2 INSIDE the card, often prefixed by a status dot.
- **Fix:** controls.ts groupBox(title?: string, ...children): <div class=gb>{title && <div class=gb-title>}<div class=gb-box>children</div></div>. CSS: .gb-title { font:400 12px var(--font); color: var(--label); margin:0 0 6px 2px } .gb-box { background: var(--box-fill); border:0.5px solid var(--separator); border-radius:6px; padding:10px 12px; display:flex; flex-direction:column; gap: var(--vstack-gap) }. Pass gap per box to match the Mac VStack spacing (6/8/10/12/14). Remove the status dots from headings (the Mac has none). Calibrate the exact title size and radius against a real Mac capture.
- **Phase:** Phase 1

### W-07 — Type scale, colours and label layout differ (12px dim hints, 12.5px dim 132px label column)

- **Mac:** `SettingsView.swift (hints .system(size:11) .secondary; integration hints size 10; section captions 11 semibold secondary; row labels primary 13pt inline)` — Body 13pt SF in the label colour. Hints are 11pt secondary (10pt in Integrations, 12pt in Chat). Labels sit inline in the label colour ('Close after [ ] s inactive', 'Volume' 56pt, 'Shortcut' 70pt, Hydration labels 150pt). Pickers show their label to the left of the popup.
- **Windows:** `windows/src/settings/settings.css:72-88` — Hints 12px #9398a1. Every row has a 132px dim label column (12.5px #9398a1), so labels look secondary.
- **Fix:** settings.css: .hint{font-size:11px;color:var(--secondary)} .hint.s10{font-size:10px} .row>label{color:var(--label);font-size:13px;min-width:auto}. Rebuild each row as the Mac inline flow (see the per-row gaps) and drop the uniform 132px column, except Hydration, which uses 150px. The font stays Segoe UI Variable, which is platform-forced (SF Pro is not licensed for Windows).
- **Phase:** Phase 1

### W-08 — Popups, sliders, text fields and segmented controls do not look like macOS controls

- **Mac:** `SettingsView.swift:299-304, 322, 336-338, 514-515; IslandSettingsView.swift:27-31, 122-123; HydrationSettingsView.swift:151-156, 136-137` — Popup button: r5, 22pt tall, value text plus a double-chevron accent square on the right. Slider: 4pt track, the left part filled with the accent colour, ≈20pt white round knob with a shadow. .roundedBorder field: r≈5, control background (white / #1E1E1E), 3px accent focus ring. Segmented: r6 track, selected segment raised (white in light, lighter grey in dark). DatePicker .field: a 78pt time field.
- **Windows:** `windows/src/settings/settings.css:191-244, 457-465, 486-513` — Native dark <select>. Range: 140px white-20% track, 13px white thumb, no fill. Inputs: r8, white 7% fill, focus border white 28%. .hy-seg: selected segment is a white fill with black text.
- **Fix:** select{appearance:none;height:22px;border-radius:5px;padding:0 24px 0 8px;background:var(--control-bg) url(chevrons.svg) right 3px center/16px no-repeat}. input[type=range]: fill the leading part with var(--accent) via a --pct gradient, 20px white thumb with 0 1px 2px rgba(0,0,0,.3). Text inputs: r5, height 22px, background var(--control-bg), focus box-shadow 0 0 0 3px color-mix(var(--accent) 50%, transparent). Segmented: track r6 bg rgba(128,128,128,.2), selected bg var(--segment-selected) (#fff light / #636366 dark) with color var(--label).
- **Phase:** Phase 1

### W-09 — No bottom status bar; feedback is inline notice pills per section

- **Mac:** `SettingsView.swift:189-196, 518, 565, 579, 620, 655, 679, 985, 997-1022` — One statusMessage line at the bottom of the detail pane (12pt, secondary or red if it starts with ❌). It is cleared when the sidebar selection changes. Messages: '✓ Key saved.', '✓ Google key saved.', '✓ OpenAI key saved.', 'Ollama disconnected.', '✓ ChatGPT data cleared — you are signed out.', '❌ Startup: …', '✓ Connected · N models', etc.
- **Windows:** `windows/src/settings/main.ts:255-290, 525-547, 582-591, 923-937 (notice ok/err)` — Green/red tinted .notice blocks appended inside each card ('Saved. It never touches disk.', 'Key removed.', 'Signing in — the dot above says how it went.', …).
- **Fix:** Add a status bar to the shell (border-top 1px var(--separator), padding 8px 20px, 12px, colour secondary or #FF453A/#FF3B30 for ❌). Expose setStatus(text) and clear it on pane change. Route every save/connect message through it with the Mac strings, which already exist in the catalog. Delete the .notice usage.
- **Phase:** Phase 1

### W-10 — Master switch: separate card with status dot and warn notice; Mac has a GroupBox 'Notchy' checkbox in General

- **Mac:** `SettingsView.swift:256-275` — General › GroupBox 'Notchy' with checkbox 'Notchy is on'/'Notchy is off' and an 11pt hint ending '…Turn it back on here or from the menu bar.' No dot, no extra notice.
- **Windows:** `windows/src/settings/main.ts:66-104` — Its own top card: an h2 with a green/red dot + 'Notchy', a label row + switch, a hint ending '…from the icon by the clock.', and an amber notice 'Notchy is off — Mochi is hidden and nothing is being watched.' when off.
- **Fix:** Make it the first groupBox('Notchy') of the General pane with macCheckbox. Keep paintMaster for tray sync. Remove the dot and the warn notice. The hint's last clause is platform copy: keep 'icon by the clock' (its own catalog key), which is the faithful equivalent of 'menu bar'.
- **Phase:** Phase 1

### W-11 — Your name: label row and short hint instead of the Mac GroupBox with the welcome button

- **Mac:** `SettingsView.swift:277-295` — GroupBox 'Your name': a full-width rounded field (label hidden; placeholder = the macOS first name or 'Your first name'), hint 'Mochi greets you by this name when Notchy starts, and uses it in the chat.', and the button 'Show the welcome again…' right under it.
- **Windows:** `windows/src/settings/main.ts:2112-2130, 2408-2414` — Row: label 'Your name' + field + hint 'what Mochi calls you'. 'Show the welcome again…' is the last row of General, after Launch at startup.
- **Fix:** groupBox('Your name', field(full width, placeholder unchanged), hint(t('Mochi greets you by this name when Notchy starts, and uses it in the chat.')), pushButton(t('Show the welcome again…'))). Remove the trailing welcome row.
- **Phase:** Phase 1

### W-12 — Language: inline row with a one-line hint instead of a GroupBox with the full explanation

- **Mac:** `SettingsView.swift:297-314; AppLanguage.swift:21-28` — GroupBox 'Language': a label-hidden popup + hint 'Mochi speaks this language everywhere: the island, Settings, the menu bar and the notifications. Following the system means Spanish or Portuguese if your Mac is set to one of them, and English otherwise.'
- **Windows:** `windows/src/settings/main.ts:2308-2335` — Row 'Language' + select + 'Mochi speaks this language everywhere.'
- **Fix:** groupBox('Language', popup, hint). Use the Mac sentence, or add a Windows twin key to the catalog that replaces 'menu bar' with 'the icon by the clock' and 'your Mac' with 'Windows', with es/pt-BR. The repaint-on-change behaviour stays.
- **Phase:** Phase 1

### W-13 — Sound: no 'Enable sounds' label, no % readout, slider not disabled when off

- **Mac:** `SettingsView.swift:316-330` — GroupBox 'Sound': checkbox 'Enable sounds'; then 'Volume' (56pt) + full-width slider 0…0.2 (disabled when sounds are off) + 'NN %' (36pt, monospaced digits, value/0.2*100).
- **Windows:** `windows/src/settings/main.ts:2133-2140, 2336-2340` — Row 'Sound' + switch + 140px slider (step 0.005), always enabled, no percentage.
- **Fix:** groupBox('Sound', macCheckbox(t('Enable sounds')), row(label 'Volume' width 56, slider flex:1 disabled=!soundEnabled, span width 36 text-align:right tabular-nums `${Math.round(v/0.2*100)} %`)). Update the % on input.
- **Phase:** Phase 1

### W-14 — Behavior rows renamed and restructured (Auto-close, Hide after + Never pill) vs 'Close after … s inactive' / 'Always visible' / 'Hide after … s without movement'

- **Mac:** `SettingsView.swift:332-355; AppState.swift:535-571` — GroupBox 'Behavior': 'Close after' [64pt field, 5] 's inactive'; checkbox 'Always visible'; 'Hide after' [64pt field, 180] 's without movement' (the whole row disabled while Always visible is on).
- **Windows:** `windows/src/settings/main.ts:2142-2151, 2244-2283, 2341-2345, 2363-2368` — 'Auto-close' [72px number] 'seconds a notification stays open'; later 'Hide after' [number] + a pill toggle button 'Never' + 'seconds of quiet before Mochi folds away' / 'Mochi stays in its corner…'.
- **Fix:** groupBox('Behavior', inlineRow(t('Close after'), numberField(64px), t('s inactive')), macCheckbox(t('Always visible') ↔ settings.alwaysVisible), inlineRow(t('Hide after'), numberField(64px), t('s without movement')).disabled(alwaysVisible)). Delete toggleButton 'Never' (main.ts:2249) and its hints. Keep the Windows default alwaysVisible=true (platform-forced, see README).
- **Phase:** Phase 1

### W-15 — 'Standby' row exists only on Windows

- **Mac:** `none (no standby in NotchBuddy/Sources/App)` — Not present.
- **Windows:** `windows/src/settings/main.ts:2234-2242, 2369-2373; windows/src-tauri/src/settings.rs:50-51` — A switch 'Standby' with 'once folded away, only a message brings Mochi back'; it is mutually exclusive with Never/Always visible.
- **Fix:** To match exactly, remove the row from the UI (keep the field so stored values are ignored, or force standby=false). If the owner wants to keep the behaviour, port it to the Mac Behavior group first so both sides have it.
- **Phase:** Phase 1 — Standby removed (owner)

### W-16 — Displays: 'Island lives on' (Main display / Display under the cursor) instead of the Mac All displays / Only selected + per-display checkboxes

- **Mac:** `SettingsView.swift:357-365, 1311-1385; AppState.swift:54-58` — GroupBox 'Displays': radio group (vertical) 'All displays' / 'Only selected'. When 'Only selected', there is an 11pt checkbox per connected display (localized name); the last one cannot be unticked. An 11pt note covers selected displays that are unplugged ('1 selected display is not connected right now — …'), plus the hint 'Mochi rests at the top of every display you allow. She opens, and shows notifications, on the one your pointer is on.' The island follows the cursor among the allowed displays.
- **Windows:** `windows/src/settings/main.ts:2205-2214, 2392-2395; windows/src-tauri/src/settings.rs:64-65` — A select with 2 values; 'primary' pins to the main monitor, 'cursor' follows the mouse across all monitors.
- **Fix:** Add displaySelection: string[] to settings.rs/state.ts (empty = all) and a Rust command listing monitors from app.available_monitors() with a stable id (name + position + size) and a display name. Render a radio group plus checkboxes exactly as DisplayPickerRow, with the same 'never untick the last one' rule and the remembered-count note. Migrate screen: 'cursor' → [] and 'primary' → [primary id]. island.rs chooses the active monitor = the allowed monitor under the cursor.
- **Phase:** Phase 4

### W-17 — Notch height group missing

- **Mac:** `SettingsView.swift:367-398, 1263-1304; AppState.swift:64-72, 127-130` — GroupBox 'Notch height' with two IslandHeightRows: toggle 'Notch display height' (slider 32–60, default 40, 'NN pt' / 'Matches the cutout'), Divider, toggle 'Non-notch display height' (slider 22–60, default 32 / 'Matches the menu bar'), and a hint about raising it to make Mochi easier to reach.
- **Windows:** `none` — No equivalent; the resting bar height is fixed.
- **Fix:** PCs have no notch, so the first row is platform-forced. Add the second row only: groupBox('Notch height' → better a Windows key such as 'Bar height', or keep the Mac title) with a toggle 'Non-notch display height' + slider 22–60 default 32 'NN px' / 'Matches the menu bar' (needs a Windows key: 'Matches the taskbar'). Wire it to the compact-bar height in core/layout.ts/island.rs. Keep the Mac hint text.
- **Phase:** Phase 4

### W-18 — Hotkey: 'Show island with shortcut' missing; close row renamed 'Close shortcut'

- **Mac:** `SettingsView.swift:400-437, 1389-1443; AppState.swift:580-605` — GroupBox 'Hotkey': checkbox 'Show island with shortcut' → row 'Shortcut' (70pt) + recorder (default ⌘⇧N) + 'presses this → island opens'; checkbox 'Close island with shortcut' → row 'Shortcut' + recorder (⌃⌥X) + 'presses this → island closes' + 'This shortcut is taken or not allowed here.' Recorder: 11pt monospaced text, padding 8x3, r5, controlBackground fill, gray 30% border, accent 12% fill while recording.
- **Windows:** `windows/src/settings/main.ts:2038-2102; windows/src-tauri/src/settings.rs:186-194` — One row 'Close shortcut' + switch + a pill button showing 'Ctrl+Alt+X' + hint. No open-island shortcut.
- **Fix:** Add openShortcutEnabled (default false) and openShortcut (default 'Ctrl+Shift+N') to settings.rs/state.ts and register them in shortcut.rs next to the close one (the same error-reporting path). Build groupBox('Hotkey', macCheckbox('Show island with shortcut'), [if on] inlineRow(label 'Shortcut' 70px, recorder, hint 'presses this → island opens'), macCheckbox('Close island with shortcut'), [if on] inlineRow(...'presses this → island closes'), refusal line). Style the recorder as the Mac (font 11px var(--mono), padding 3px 8px, r5, border 1px rgba(128,128,128,.3), recording bg accent 12%).
- **Phase:** Phase 2

### W-19 — Startup: switch row 'Launch at startup', not a GroupBox checkbox; the defaults disagree

- **Mac:** `SettingsView.swift:439-443, 980-988` — GroupBox 'Startup' with checkbox 'Launch at Mac startup'. It reflects SMAppService state (off on a fresh install); a failure reverts it and shows '❌ Startup: …' in the status bar.
- **Windows:** `windows/src/settings/main.ts:2401-2404; windows/src-tauri/src/settings.rs:383; windows/src/core/state.ts:394` — Row 'Launch at startup' + switch. Rust defaults autostart=true and the TS default is false (they disagree). Failures only go to the log.
- **Fix:** groupBox('Startup', macCheckbox(t('Launch at startup'))). The copy is platform-forced: keep 'Launch at startup' or add 'Launch at Windows startup'. Make the TS DEFAULT_SETTINGS.autostart equal Rust. Report autostart errors to the status bar as '❌ Startup: …'.
- **Phase:** Phase 1

### W-20 — Updates: inline downloader card instead of the Mac's minimal group (Sparkle window does the rest)

- **Mac:** `SettingsView.swift:446-465; Updater.swift:37-66; AppDelegate.swift:52,99` — General › last GroupBox 'Updates': row 'Notchy x.y.z' … Spacer … 'Check for updates' (disabled while checking); checkbox 'Check automatically'; hint '…It never installs or restarts on its own — that is the Install button. Every build is signed…'. Sparkle shows its own window with the notes and Install.
- **Windows:** `windows/src/settings/main.ts:649-776; windows/src-tauri/src/update.rs:197-204` — A separate card with a status dot in the heading; the row holds the label, a multi-state action button (Check/Update to x/Open the download page/Restart now/Try again), a status line and a progress bar; an error notice; a release-notes notice; a switch; and a hint with different words ('downloads…this button…Every package is signed').
- **Fix:** Move it into General as the last groupBox('Updates'): row(label `Notchy ${version}`, spacer, pushButton('Check for updates')), macCheckbox('Check automatically'), hint. Show the available/downloading/ready/error states in a small modal dialog in the settings webview, styled like Sparkle's sheet (title, notes, 'Install update'/'Remind me later'), so the group itself stays identical to the Mac. Tauri has no Sparkle, so this is the closest equivalent. Hint: use the Mac sentence or a Windows twin.
- **Phase:** Phase 2

### W-21 — Active pills pane missing; pill switches scattered across Integrations and Messages

- **Mac:** `SettingsView.swift:471-507, 1193-1221; PillCatalog.swift (categories, order)` — One GroupBox: hint 'Choose the tools you use. Notchy only shows what you declare here.' (11pt); 'N/4 slots used' (11pt, orange at 4); popup 'Home shows' + hint; then Divider + caption 'Where you code' (11pt semibold secondary) → Claude Code row with 'Always on'; Divider + 'Services' → Now Playing, Mattermost, Ato, WhatsApp, Notifications. Each row: 10pt colour dot, 12pt name, trailing checkbox.
- **Windows:** `windows/src/settings/main.ts:326-372, 169-186, 601, 438` — The 'Integrations' card shows only Notifications and Now Playing (switch first, then dot and name) under the note 'Pick up to 4 pills… Keys are stored in the Windows Credential Manager, never on disk.' Mattermost/Ato/WhatsApp switches sit in the Messages blocks, Claude Code is not listed, and 'Home shows' is in General.
- **Fix:** New panes/activePills.ts that renders exactly the Mac tree, from INTEGRATION_AGENTS grouped by category (add category: 'workspace'|'service' to the TS table). Use the same order as PillCatalog.all (Claude Code; Now Playing, Mattermost, Ato, WhatsApp, Notifications), hiding Now Playing when !boot.media. Remove pillToggle from the message blocks and delete INTEGRATIONS/integrationsSection.
- **Phase:** Phase 1

### W-22 — Pill at 4/4: Mac disables and greys the row; Windows silently ignores the click

- **Mac:** `SettingsView.swift:478-480, 1199-1219` — atMax = count >= 4 && !isOn: the name turns secondary and the checkbox is disabled; the counter turns orange.
- **Windows:** `windows/src/settings/main.ts:169-186, 343-350` — Clicking an off switch at 4 does nothing, with no visual cue; the note text only states the numbers.
- **Fix:** In activePills rows: disabled = atMax; name colour var(--secondary) when atMax; counter colour #FF9F0A (dark)/#FF9500 (light) when count>=4. Re-evaluate every row in activeChanged.
- **Phase:** Phase 1

### W-23 — Home shows: 'Notifications' option and the Mac default missing; automatic hint truncated

- **Mac:** `HomeContent.swift:11-38, 106-119; AppState.swift:374` — Options in order: Notifications (default), Last message, Ato, Mattermost, WhatsApp, Timer, Claude Code. Notifications hint: 'Every message service as one queue — Home keeps the last thing any of them said, and keeps it while something is playing.' Automatic hint: '…keeps whichever spoke last, and hands over to whatever is playing while something is.'
- **Windows:** `windows/src/core/state.ts:105-126, 384; windows/src-tauri/src/settings.rs:334-336; main.ts:2219-2227` — No 'notifications' case; the default is 'automatic'; the automatic hint stops at '…whichever spoke last.' The row sits in General.
- **Fix:** state.ts: HomeContent adds 'notifications' first; HOME_LABEL.notifications='Notifications'; HOME_HINT copied verbatim from Swift for notifications and automatic. homeSource treats notifications like automatic, but it never hands Home to the player (mirror showsMusic/playerTakesHome). Defaults: DEFAULT_SETTINGS.homeContent and settings.rs default_home_content → 'notifications'. Render the popup in the Active pills pane with its label shown ('Home shows' left of the popup).
- **Phase:** Phase 1

### W-24 — Dynamic Island pane with its segmented Layout/Content/Activity/Behavior tabs missing

- **Mac:** `IslandSettingsView.swift:8-40` — A segmented control across the top (persisted in 'islandTab', default layout) swaps four groups of GroupBoxes (see the following gaps).
- **Windows:** `none (pieces spread over main.ts:792-903, 2347-2356, 2376-2386, 2396-2400)` — No such pane. The ring is its own card; snow, music, skip seconds and position are rows in General.
- **Fix:** panes/island.ts: segmented(['Layout','Content','Activity','Behavior']) persisted in localStorage 'islandTab', with spacing 12 between the segmented control and the content. Move the ring, Big screen, Christmas, Now Playing skip and Where it sits into it as described below.
- **Phase:** Phase 1

### W-25 — Ring editor: different title, hint, empty text, side names/order, add control, add side, reorder and remove controls

- **Mac:** `IslandSettingsView.swift:45-56, 241-364; IslandEdgeLayout.swift:5-7` — GroupBox 'Buttons around the island' with hint 'Anything here sits on the island's border, so one click opens it without opening the island first.' Row: 10pt dot, a 16pt-wide icon (the pill logo at 13pt simplified, or the SF symbol in secondary), 12pt name, Spacer, side popup (92pt) with Left/Right/Bottom in that order, then borderless ⌃, ⌄, ⊖ (minus.circle). Up/down swap with the neighbour on the SAME side. Empty state: 'No buttons yet.' Add: borderless menu '+ Add a button' listing unused built-ins, a Divider, then unused pills. A new button goes to whichever of left/right has fewer.
- **Windows:** `windows/src/settings/main.ts:792-903` — Card 'On the island's border'. Row: dot + name + select (Row/Left/Right) + '↑' + red 'Remove'. ↑ swaps with the previous item in the whole list; there is no ↓. Empty: 'Nothing on the border.' Add: a row 'Add' with a select whose first option is 'Add a button…'; new buttons go to 'bottom'. Its hint is about 'Row'.
- **Fix:** Port IslandRingEditor 1:1: the side popup with options left/right/bottom labelled t('Left'), t('Right'), t('Bottom'); icon/logo per row (reuse views/logos.ts); borderless chevron-up/down/minus-circle SVG buttons; move(button, ±1) within the same side; empty t('No buttons yet.'); a menu button '+ Add a button' (a custom dropdown with the built-ins, a separator, then the pills); add() picks left if left.count <= right.count else right. Use the Mac hint. Remove 'Row' wording. The 'bottom' semantics (away from the screen edge) stay as a Windows note in the code only.
- **Phase:** Phase 1

### W-26 — Built-in 'AI Agents' ring action missing from EDGE_ACTIONS

- **Mac:** `IslandEdgeAction.swift (cases agents, clipboard, timer, settings, site; #E07950 sparkles)` — Five built-ins: agents (AI Agents, #E07950), clipboard (#8AB4F8), timer (Focus timer, #F5A524), settings (#8E939C), site (host label, #38BDF8). The menu lists them in that order.
- **Windows:** `windows/src/core/edgeRing.ts:190-195` — Four built-ins; no agents. The site title is 'Site' rather than the host label.
- **Fix:** Add { id: 'agents', title: 'AI Agents', color: '#E07950' } first once the AI Agents panel exists (W-37). Use the site's host as its title (NotchSite.hostLabel = url.host) to match. Add an edge-action parity test.
- **Phase:** Phase 4 (site) / Phase 5 (AI Agents)

### W-27 — 'Big screen' group (large island width/height) missing

- **Mac:** `IslandSettingsView.swift:58-73, 107-126; AppState.swift:110-124; IslandTypes.swift:199` — GroupBox 'Big screen' with a hint and rows 'Width'/'Height': a checkbox (off = designed size), a trailing 'NNN pt' (11pt secondary, monospaced digits) showing the fallback when off, and when on a slider with step 10 (360–600 default 600; 240–800 default 650).
- **Windows:** `none` — No setting; large views use fixed sizes.
- **Fix:** Add largeIslandWidth/Height: number|null to settings.rs/state.ts. Use them where layout.ts sizes 'screen' views (agenda, MESSAGE_EXPANDED_CAP). Render via a sizeRow(checkbox, 'NNN px', slider step 10).
- **Phase:** Phase 3

### W-28 — Christmas toggles live in General with shortened hints; Mac has a 'Christmas' GroupBox under Dynamic Island › Layout

- **Mac:** `IslandSettingsView.swift:77-101` — GroupBox 'Christmas' (in season only): checkbox 'Snow on the island' + hint 'A little snow falls faintly behind what the island shows and settles along its bottom edge until January 6…'; checkbox 'Christmas music when Notchy starts' + hint 'Notchy plays its Christmas music as it says hello, until January 6…'.
- **Windows:** `windows/src/settings/main.ts:2376-2386` — Two General rows with switches and shortened inline hints ('until January 6 — it falls faintly…', 'until January 6 — it plays as Notchy says hello…').
- **Fix:** Move to the island pane's Layout tab as groupBox('Christmas', macCheckbox, hint(Mac text), macCheckbox, hint(Mac text)). Keep the season gate (import.meta.env.DEV || isFestiveSeason()).
- **Phase:** Phase 1

### W-29 — Skip back/forward: number fields in General instead of Steppers in Dynamic Island › Content › 'Now Playing'

- **Mac:** `IslandSettingsView.swift:147-181` — GroupBox 'Now Playing': hint ('How far the player's two round buttons jump…'); 'Skip back' label … '10 s' + Stepper (1–120); 'Skip forward' likewise; hint ('The number is drawn on the button. 5, 10, 15, 30, 45, 60, 75 and 90 get the system's own numbered dial…').
- **Windows:** `windows/src/settings/main.ts:2157-2174, 2347-2356` — Two General rows: 72px number input + hints 'seconds the player's left round button jumps' / 'seconds the right one jumps'.
- **Fix:** Content tab: groupBox('Now Playing', hint, stepperRow('Skip back'), stepperRow('Skip forward'), hint). stepperRow = label, spacer, `${v} s` 11px secondary tabular, then a macOS stepper (two stacked 11x10 arrow buttons, r4). Clamp 1–120. The second hint mentions the 'system's own numbered dial': add a Windows twin or keep it as-is.
- **Phase:** Phase 1

### W-30 — Info groups 'What the island carries', 'What it shows by itself', 'Opening' missing

- **Mac:** `IslandSettingsView.swift:131-144, 186-195, 223-232` — Three GroupBoxes of explanatory text that point to Active pills and General.
- **Windows:** `none` — Absent.
- **Fix:** Add them verbatim in the Content, Activity and Behavior tabs (the strings exist in the catalog).
- **Phase:** Phase 1

### W-31 — 'Island sits at' is a General row with a short hint; Mac has GroupBox 'Where it sits' under Behavior

- **Mac:** `IslandSettingsView.swift:200-221; IslandAnchor.swift:40-51` — GroupBox 'Where it sits': popup with visible label 'Island sits at' (6 presets + 'Where you dropped it') + hint 'Hold the resting island for two seconds and it comes unstuck: it follows the pointer, across displays, until you let go. Drop it near an edge and it settles into that corner.'
- **Windows:** `windows/src/settings/main.ts:2285-2303, 2396-2400` — General row + 'where Mochi peeks out'.
- **Fix:** Behavior tab: groupBox('Where it sits', labelledPopup('Island sits at', …), hint(Mac text)). Keep the default bottom-right (platform-forced).
- **Phase:** Phase 1

### W-32 — Radial menu pane missing

- **Mac:** `RadialSettingsView.swift:4-121; RadialAction.swift; RadialGeometry.swift:25-26` — GroupBox: checkbox 'Use the radial menu' (default off), hint, permission row (dot #34D399 ok / #F5A524, text, 'Open Settings'), trackpad hint. GroupBox 'What is on the wheel': hint 'Between 2 and 8…', a row per slot (16pt icon, popup of 9 actions, ⌃ ⌄ ⊖ with remove disabled at 2), menu '+ Add' while below 8.
- **Windows:** `none` — No radial menu exists on Windows.
- **Fix:** Feature port: a low-level mouse hook (SetWindowsHookEx WH_MOUSE_LL in a Rust thread) detects the left+right chord and suppresses the context menu; a transparent always-on-top wheel window draws the wedges. Windows needs no Accessibility permission, so the permission row becomes a constant 'granted' state or is omitted. Settings pane = a 1:1 port of RadialSettingsView with radialEnabled/radialSlots in settings.rs/state.ts and a RadialAction TS twin, parity-tested.
- **Phase:** Phase 7

### W-33 — AI Agents pane missing (and no AI Agents panel at all on Windows)

- **Mac:** `AgentsSettingsView.swift:6-97; ClaudeAccount.swift` — GroupBox: checkbox 'Show AI Agents' (default off) + hint + 'Open AI Agents'. GroupBox 'What it reads' (3 lines in 11pt medium monospaced with 10pt #6E737C notes + footer). GroupBox 'Right now' (when on): account dot (#34D399/#8E939C) + label 12pt, a 10pt #6E737C note, 'N sessions running.'
- **Windows:** `windows/src/core/bridge.ts:296-302 (empty AI Agents section)` — Nothing. The README still describes a Windows AI Agents dashboard, but the bridge has no commands for it.
- **Fix:** Port the reader in Rust (%USERPROFILE%\.claude.json account summary; %USERPROFILE%\.claude\sessions\*.json, never opening .key) plus a panel. Settings pane = a 1:1 port. Replace '~/.claude.json' and 'Keychain' wording with Windows twins, or keep the Mac paths verbatim since Claude Code uses the same relative paths.
- **Phase:** Phase 5

### W-34 — Chat › Anthropic API: wrong title, button text, model list, default model; no live model list or Custom…

- **Mac:** `SettingsView.swift:9-28, 199-217, 512-549, 975-978; AppState.swift:329; ClaudeService.swift:111-125` — GroupBox 'Anthropic API': SecureField placeholder 'API key (sk-ant-…)', 'Save' (.borderedProminent) → '✓ Key saved.' in the status bar; Divider; popup 'Model' filled from GET /v1/models (display_name), falling back to Claude Sonnet 4.6 (claude-sonnet-4-6), Sonnet 5.5, Opus 5.5, Haiku 4.5 (claude-haiku-4-5-20251001), then 'Custom…', which reveals TextField 'Model ID (e.g. claude-sonnet-4-6)'. Hint 'Used by the chat. The list comes from your Anthropic account.' Default model claude-sonnet-4-6.
- **Windows:** `windows/src/settings/main.ts:235-314; windows/src-tauri/src/claude.rs:23; windows/src/core/state.ts:396` — Card '● Claude' with a status line ('Key saved in the Windows Credential Manager.' / 'No key yet — the chat needs one.'); 'API key' field placeholder 'sk-ant-...' + 'Save key' (white primary) + red 'Remove'; 'Model' select with claude-opus-5 / claude-sonnet-5 / claude-haiku-4-5. No fetch, no Custom…, no hint. Default claude-opus-5.
- **Fix:** Chat pane groupBox('Anthropic API'): secure field (placeholder t('API key (sk-ant-…)'), with a '•••• (stored)' placeholder kept as the Credential Manager adaptation), prominent 'Save', divider, labelled popup 'Model'. Add a Rust command fetch_models that calls /v1/models with the stored key and runs on pane open. Use the fallback list + 'Custom…' + custom field, with the Mac hint. Defaults: claude.rs DEFAULT_MODEL and state.ts → 'claude-sonnet-4-6'. Drop 'Remove' and the status line (the Mac clears by saving an empty field), or keep 'Remove' only if the owner wants it.
- **Phase:** Phase 2

### W-35 — 'Chat — other providers' (Google AI, OpenAI) missing

- **Mac:** `SettingsView.swift:551-584; AppState.swift:350-363` — GroupBox: 12pt hint; ● #4285F4 'Google AI' (12pt semibold) + SecureField 'API key (AI Studio)' + Save; Divider; ● #10A37F 'OpenAI' + SecureField 'API key (sk-…)' + Save. The chat can then switch provider.
- **Windows:** `windows/src-tauri/src/secrets.rs:14-34 (no google-api-key/openai-api-key); claude.rs (Anthropic only)` — Not available; the chat is Anthropic-only.
- **Fix:** Add 'google-api-key' and 'openai-api-key' to KNOWN_KEYS. Add provider clients (OpenAI-compatible /v1/chat/completions for both; Gemini via its OpenAI-compatible endpoint, as on the Mac) and chatProvider plus per-provider model in settings. Render the group 1:1. The hint says 'Keychain': add a Windows twin with 'Windows Credential Manager'.
- **Phase:** Phase 6

### W-36 — 'Local models' (Ollama, LM Studio) missing

- **Mac:** `SettingsView.swift:586-661, 990-1024` — GroupBox with hint 'Connect to a local model server. No API key needed.' Ollama (● #FACC15) and LM Studio (● #A3E635): when disconnected, a URL field (placeholder http://127.0.0.1:11434 / :1234) + prominent 'Connect'/'Connecting…'; when connected, a 10pt 'Connected' in #22C55E beside the name, the URL in 11pt monospaced secondary and a bordered 'Disconnect'. Status bar: '✓ Connected · N models', 'No models yet — download one in X first.', 'Couldn't reach X at URL. Is it running?', 'Only http:// and https:// URLs are supported.'
- **Windows:** `none` — Not available.
- **Fix:** Rust: fetch /v1/models (OpenAI-compatible) from the given base URL, plus a chat client for those providers. Settings: ollamaServerURL/lmstudioServerURL. Port the UI and the status messages 1:1.
- **Phase:** Phase 6

### W-37 — ChatGPT (website): Windows has one switch in a 'Pages' card; Mac has a ChatGPT group with two toggles and Clear data

- **Mac:** `SettingsView.swift:663-689; AppState.swift:803-809; WebChatController.swift:88-93` — The last GroupBox of Chat, 'ChatGPT (website)': checkbox 'Show ChatGPT in the notch' (webChatEnabled, default off; nothing loads chatgpt.com without it); checkbox 'Open it from the chat tab' (useWebChat, disabled unless the first is on); hint 'Opens chatgpt.com itself inside the island, with no API key. Signing in is optional…'; bordered 'Clear ChatGPT data' + 11pt note 'Signs out and deletes the cookies WebKit stored for the site.' → status '✓ ChatGPT data cleared — you are signed out.'
- **Windows:** `windows/src/settings/main.ts:915-959; windows/src-tauri/src/settings.rs:141-144` — Card 'Pages': 'Site' URL field + 'Chat tab opens ChatGPT' switch (webChat) + a hint about separate windows. There is no master switch and no clear-data.
- **Fix:** Chat pane groupBox('ChatGPT (website)'): macCheckbox('Show ChatGPT in the notch') → new setting webChatEnabled (default false) gating toggle_webchat_window/web::create; macCheckbox('Open it from the chat tab') → existing webChat, disabled=!webChatEnabled; Mac hint; bordered 'Clear ChatGPT data' → new command web_clear_data that calls clear_all_browsing_data() on the webchat WebviewWindow (Tauri 2 API) and hides it; note with a Windows twin ('…deletes the cookies WebView2 stored…'); status line. The separate window, rather than drawing in the island, stays platform-forced.
- **Phase:** Phase 2

### W-38 — 'Site' URL field and the 'Pages' card exist only on Windows

- **Mac:** `NotchSite.swift:15 (URL hard-coded, no setting)` — No setting; the globe opens the fixed NotchSite.url.
- **Windows:** `windows/src/settings/main.ts:915-959` — An editable URL field with validation and the 'Saved. The new page is loaded next time Notchy starts.' feedback.
- **Fix:** To match, remove the Pages card (keep siteUrl at its default). If the owner wants it configurable, add it to the Mac too rather than keeping a Windows-only row.
- **Phase:** kept — the Pages/Site field stays, Mac-styled, in Phase 1 (owner)

### W-39 — Integrations › Messages: 'Also show a macOS notification' missing; the 'Show the whole message' layout differs

- **Mac:** `SettingsView.swift:699-717; AppState.swift:290-302` — Caption 'Messages' (11pt semibold secondary); checkbox 'Also show a macOS notification' (default ON) + 10pt hint; checkbox 'Show the whole message' + 10pt hint.
- **Windows:** `windows/src/settings/main.ts:615-634` — Card 'Messages' with a switch row 'Show the whole message', its hint, and an extra hint 'Both of these hold a connection open…'. No banner option.
- **Fix:** Add messageBanners (default true) and post a Windows toast (tauri-plugin-notification, or the winrt toast API with an input box for reply; reply-from-toast needs COM activation, so without it the toast only opens the island). Label: Windows twin 'Also show a Windows notification'. Render the caption and both checkboxes as on the Mac; drop the extra hint.
- **Phase:** Phase 2

### W-40 — Mattermost block: per-field Save rows and 'Forget sign-in' instead of the Mac form + single Sign In/Sign Out + status chip

- **Mac:** `SettingsView.swift:721-766, 1033-1040, 1065-1073, 1172-1190` — Header: ● #1B6FF3 + 'Mattermost' (12pt semibold), Spacer, status chip (6pt dot + 10pt text: green 'Connected as <user>' / yellow 'Connecting…' / red <reason> / grey 'Not connected'). Fields with placeholders only: 'Server URL  (https://chat.example.com)', 'Username or email', 'Password' (secure); login and password are disabled while connected. Row: prominent 'Sign In' ('Signing in…' + small spinner; disabled until all 3 are filled), or bordered 'Sign Out' when connected. Then 'Open with' row and footer 'Turn the Mattermost pill on for Notchy to connect. Credentials are kept in your macOS Keychain.'
- **Windows:** `windows/src/settings/main.ts:193-231, 398-412, 519-611` — Header: pill switch + dot + name + status dot + text ('Connected · detail', 'Fill in the address…', 'Pill switched off…'). Hint 'Direct messages and mentions open a card…'. Three rows 'Server URL'/'Login'/'Password', each with its own Save button and dot. Row 'Session' with 'Sign in' + 'Forget sign-in'. Inline notices. No Sign Out, no field locking, no Open with.
- **Fix:** Rebuild as the Mac block: three inputs (placeholders = Mac keys), signInRow(prominent 'Sign In' → secretSet ×3 + clear token + Bridge.mattermostSignIn(); 'Signing in…' + spinner while CONNECTION 'connecting'; 'Sign Out' → clear token + password + disconnect). Disable login/password while connected. statusChip with the Mac texts (pass the username in status.detail as 'Connected as %@'). Remove the pill switch, per-field Save, dots and 'Forget sign-in'. Footer with a Windows twin key ('…kept in the Windows Credential Manager.').
- **Phase:** Phase 2

### W-41 — Ato block: same form mismatch; no auto-enable pill or orange no-slot note; password kept

- **Mac:** `SettingsView.swift:769-834; AtoTokenStore.swift:67-93` — Header: Ato logo (16pt) + 'Ato' + status chip. Hint 'Sign in with your Actuar account — the one you use on novo.actuar.com.' Email + Password (disabled while connected). Sign In stores email + password DIGEST only, clears the password field, switches the Ato pill on if a slot is free, otherwise shows an orange 10pt 'Your Ato sign-in is saved, but all 4 pill slots are in use…'. Then Open with, then footer 'Turn the Ato pill on for Notchy to connect. Only conversations assigned to you…'.
- **Windows:** `windows/src/settings/main.ts:413-425, 519-611; windows/src-tauri/src/ato.rs:1211` — Pill switch + dot header, a combined hint, per-field Save rows (the raw password is stored in Credential Manager), Sign in + Forget sign-in, and no pill auto-enable.
- **Fix:** Same rebuild as W-40 plus: on Sign In, if the pill is off and a slot is free, add 'integration_ato' and save; else show the orange note (#FF9F0A). Clear the password input after saving. Optionally store only ato_password_digest (already in Rust) to match the Mac's security model. Use the logo from views/logos.ts at 16px.
- **Phase:** Phase 2

### W-42 — Agenda: separate card; missing status chip, own sign-in, Refresh now and Open the commercial panel; different copy

- **Mac:** `SettingsView.swift:836, 1080-1169` — Inside Integrations between Ato and WhatsApp. Header: calendar icon (AgendaView.accent) + 'Agenda' + chip (Off / Not signed in / Reading the commercial panel… / 'N meetings today' / No access to the commercial panel / reason). Hint. Checkbox 'Show the Agenda tab'. When on: 'Signed in as <email> — the Actuar account Ato uses.', or 'Sign in with your Actuar account — the one you use on the commercial panel.' + Email + Password + Sign In. 'Heads-up' popup ('N min before', max 160pt); checkboxes 'Notify Onboarding meetings' / 'Notify Backoffice meetings'; small buttons 'Refresh now' and 'Open the commercial panel'; footer hint.
- **Windows:** `windows/src/settings/main.ts:971-1025; lib.rs:1275-1276 (agenda_refresh, agenda_open exist)` — Own card 'Agenda'. Switch rows. Account line 'Signed in with the Actuar account saved under Ato above.' / 'Save your Actuar e-mail and password under Ato above…'. No chip, no fields, no buttons.
- **Fix:** Move into the Integrations pane after Ato. Add the header chip fed by the island's agenda status (emit an 'agenda-status' event to the settings window). Use the Mac signed-in sentence with the stored email (needs a 'secret_get_email' or a boot field, because the email is not secret). Add the Email/Password/Sign In fallback (writes ato-email/ato-password, does not switch the pill on). Add small buttons → Bridge.agendaRefresh()/agendaOpen('onboarding'). Use checkboxes.
- **Phase:** Phase 2

### W-43 — WhatsApp block: different buttons and states; 'Open with' missing; the no-slot note is a red error

- **Mac:** `SettingsView.swift:839-903, 1053-1061` — Header: phone.bubble.fill in #25D366 + 'WhatsApp' + chip (Connected / Connecting… / orange 'Waiting for the QR code to be scanned' / reason / Not connected). Hint. Buttons: when connected, bordered 'Show WhatsApp' + 'Unlink'; otherwise prominent 'Connect WhatsApp' (switches the pill on, or shows the orange note) + 'Unlink' only if linked; small spinner while connecting. Then Open with row and footer.
- **Windows:** `windows/src/settings/main.ts:433-513` — Pill switch + dot header with status text. Row 'Session': 'Show QR code' + 'Unlink' (always both). The no-slot message is a red .notice.err. No Open with row (whatsappOpenTarget exists but is unused in the UI).
- **Fix:** Port the button logic and labels; map a QR-pending state to the orange chip text; orange 10px text instead of the err notice; add the openWithRow for WhatsApp; remove the pill switch.
- **Phase:** Phase 2

### W-44 — 'Open with': free-text path fields in General instead of a per-service popup + Choose…

- **Mac:** `SettingsView.swift:918-971` — Inside each service block: 'Open with' (11pt secondary) + popup [Website | <app display name> (current, or the suggested bundle if installed)] (max 190pt) + small 'Choose…' that opens a file panel on /Applications.
- **Windows:** `windows/src/settings/main.ts:2183-2203, 2357-2362` — General rows 'Mattermost opens' / 'Ato opens' with a text field ('website, or a path to an application') + 'empty opens the web page'. None for WhatsApp.
- **Fix:** openWithRow(service): popup with options 'Website' and, when set, the exe's display name (file stem, or FileDescription from the version resource); small 'Choose…' → tauri-plugin-dialog open({filters:[{name:'Applications',extensions:['exe','lnk']}], defaultPath: '%ProgramFiles%'}). Suggest the Mattermost desktop app if %LOCALAPPDATA%\Programs\mattermost\Mattermost.exe exists. Place it in each block.
- **Phase:** Phase 2

### W-45 — Characters: hide switch row with a short hint instead of its own GroupBox with the full text

- **Mac:** `CharacterSettingsView.swift:316-332` — First GroupBox: checkbox 'Hide the characters' + 11pt hint 'Mochi and the little ones stop appearing, and every card closes the gap it was leaving for a face. Nothing else changes…'.
- **Windows:** `windows/src/settings/main.ts:2016-2025` — Row label + switch + 'every job the island has, it keeps — only the faces go'.
- **Fix:** groupBox(null, macCheckbox('Hide the characters'), hint(Mac text)). Then a second groupBox for the picker (opacity .4 + pointer-events none when hidden, as now).
- **Phase:** Phase 1

### W-46 — Characters: section headings lack 'for <name>'; no 'Wearing and eyes' heading; Wearing/Eyes on one row

- **Mac:** `CharacterSettingsView.swift:139-159, 219-264` — 'Body', 'Face', 'Wearing and eyes', 'Christmas' headings are 11pt medium secondary followed by '  for <Everyone else|pill name>' at secondary 65%. 'Character for' is a labelled popup. 'Wearing' and 'Eyes' are two separate labelled popups on their own lines. Dividers sit between Body, Face, Wearing and Christmas.
- **Windows:** `windows/src/settings/main.ts:1975-2005` — Plain .hint 'Body'/'Face' with no name; a single row 'Wearing' [select] 'Eyes' [select]; no dividers; Christmas set off by a border-top.
- **Fix:** sectionLabel(title) = span 11px/500 secondary + span `  ${t('  for %@', editingName)}` at opacity .65 (key '  for %@' exists). Add dividers (1px var(--separator)) between the blocks. Render labelledPopup('Wearing') and labelledPopup('Eyes') stacked under the heading 'Wearing and eyes'.
- **Phase:** Phase 1

### W-47 — Character tiles: sizes, font, fill, hover and the Christmas badge colour differ

- **Mac:** `CharacterSettingsView.swift:40-72, 339-374, 388-398, 450-483` — Preview size 42 for bodies and 46 for faces and festive (canvas = size/0.6). VStack spacing 1, padding v3. Name 9.5pt, secondary or #CFE3F7 when chosen. Fill white 3% (#16222E chosen), stroke white 8% (#3B9EFF chosen), r10, no hover. Badge 'Until January 6': capsule fill #16222E, stroke #3B9EFF at 55%, text #CFE3F7 9.5pt medium, padding 7x2. Festive row titles 10.5pt secondary 80%.
- **Windows:** `windows/src/settings/main.ts:1868, 1884, 1921; windows/src/settings/settings.css:294-376` — Previews 48/54/54; tile padding 4/2/5, gap 2; name 10px; fill var(--card) #141518, border var(--hairline); hover #1b1e24/#32363e; badge red rgba(244,80,94,.14) with #ff8d97 text 10px; festive row titles use .hint 12px.
- **Fix:** characterPreview sizes → 42 (bodies), 46 (faces + festive), atoPreview 46. CSS .char-tile{gap:1px;padding:3px 0;background:rgba(255,255,255,.03);border-color:rgba(255,255,255,.08)} remove :hover; span font-size 9.5px. .char-badge{background:#16222E;border:1px solid rgba(59,158,255,.55);color:#CFE3F7;font:500 9.5px var(--font);padding:2px 7px}. Festive row label 10.5px, secondary at 80% opacity.
- **Phase:** Phase 1

### W-48 — Characters: 'Use the default for this one' and 'Keeping a face of their own… / Give them the default too' missing; Ato listing rule differs

- **Mac:** `CharacterSettingsView.swift:150-152, 190-199, 226-228, 272-301` — When editing a pill that has its own character: an 11pt button 'Use the default for this one' (removes the override). When editing the default and some pills override it: a Divider, the 11pt text 'Keeping a face of their own, so the default above does not reach them: A, B.' and a button 'Give them the default too'. Ato is listed only in season, or when it wears something, or while it is being edited; body/face/wearing are always hidden for Ato.
- **Windows:** `windows/src/settings/main.ts:1817-1819, 1896-1903` — Neither control exists. Ato is always listed. The Mochi rows hide for Ato only when Christmas is available.
- **Fix:** Add both controls after the festive block, using the same conditions (settings.pillCharacters[editing] exists; overriding = INTEGRATION_AGENTS with a pillCharacters entry). Filter the 'who' options with the Mac pickable rule; hide mochiOnly whenever editing === ATO_PILL.
- **Phase:** Phase 1

### W-49 — Hydration main: off-state buttons missing; headings instead of GroupBoxes; several row behaviours differ

- **Mac:** `HydrationSettingsView.swift:29-212` — Top GroupBox: checkbox 'Hydration reminders' + hint. When OFF, it shows 'Answer the questions' + link 'Where the numbers come from'. When on: GroupBox 'Your goal' (labels 150pt; with no goal the text 'no goal, just logging' replaces the stepper; − and + are never disabled; name field 160pt), GroupBox 'Reminders' (quiet time fields are NOT disabled when quiet is off; 'Today is hot…' is a small switch with its label and the hint on the next line), GroupBox 'When not to notify' (checkbox 'During a focus timer'; 'Pause reminders' shows three buttons, or when paused 'Resume reminders' + 'Paused. Logging still works.'; 'When the goal is reached' segmented always shown, max 340pt).
- **Windows:** `windows/src/settings/main.ts:1256-1448, 1726-1794` — Hint above a switch row; when off and on the main screen the panel is hidden entirely, with no way into the questions. h3 headings separated by hairlines instead of GroupBoxes. '—' with disabled ± for no goal; ± disabled at the bounds; name 180px; quiet times disabled when off; hot row is label + switch + hint inline; three toggle-style pause buttons where pressing the active one resumes; the after-goal row is hidden unless the goal is estimated/target.
- **Fix:** Main: groupBox(macCheckbox('Hydration reminders'), hint). When off, render a row with pushButton('Answer the questions') + link('Where the numbers come from'). When on, render groupBox('Your goal'|'Reminders'|'When not to notify') with 150px labels and the Mac rules: show the 'no goal, just logging' text instead of the stepper; don't disable ± (clamp only); name width 160; don't disable the quiet times; hot = switch with its label + hint below; pause shows 3 bordered buttons, or 'Resume reminders' + note; always show the after-goal segmented control.
- **Phase:** Phase 1

### W-50 — Hydration sub-screens: back control, titles, order and visuals differ from the Mac

- **Mac:** `HydrationSettingsView.swift:407-418, 439-489, 554-603, 613-681, 725-800` — BackRow = link-style '‹ Back' (10pt semibold chevron + 'Back') on its own line. Screen titles 20pt semibold below it; question titles 17pt. Intro has two Labels with icons (cross.case, lock) and no footnote; 'Begin' is the default (accent) button. Options: r10, primary 6% fill, selected accent 25%. Estimate: Back → questions; a HydrationGlass graphic (60pt, black 85% tile r12) beside 'Your starting estimate' / 'about X' (26pt) / caption; the slider row comes BEFORE GroupBox 'How I got to this number'; a zero line reads '0 ml'. Manual: 'No celebration…' as plain 12pt text; Save clamps 100–6000. Sources: Back → main; the table is in a GroupBox; bullets in GroupBoxes titled 'Where they agree' etc. with 4pt grey dots.
- **Windows:** `windows/src/settings/main.ts:1219-1225, 1452-1715; settings.css:631-811` — A round 28px '‹' button next to a 15px h3 title. Intro uses cyan bullets + footnote. Options r12 with a cyan selection. Estimate: back → main, no glass, the box before the slider, a zero line reads ''. Manual: bullet; accepts 3–4 digits (100–9999). Sources: back → the originating screen; the table is not boxed; h3 + cyan bullets.
- **Fix:** hydrationHeader → link-style '‹ Back' button row + separate title (20px/600; questions 17px/600). Intro: two icon labels (inline SVG) 12px secondary, drop the footnote, Begin = prominent. Options: r10, rgba(128,128,128,.12) fill, selected accent 25%. Estimate: Back → questions, add a glass SVG (reuse views/hydration.ts glass) in a 76px black tile r12, reorder the slider before the box, render 0 as '0 ml'. Manual: plain paragraph; clamp to 100–6000 with Save disabled when <100. Sources: back → main; wrap the table and each bullet list in groupBox(title) with 4px grey dots.
- **Phase:** Phase 1

### W-51 — Tray menu: no permanent 'Check for Updates…'; the update item is untranslated

- **Mac:** `AppDelegate.swift:40-56, 95-101` — Open Notchy / — / Settings… (⌘,) / Check for Updates… / Turn Notchy off|on / — / Quit (⌘Q). Every title goes through L().
- **Windows:** `windows/src-tauri/src/tray.rs:35-66; windows/src-tauri/src/update.rs:197-204` — Open Notchy / [Update to x…] only when available / — / Settings… / Turn Notchy off|on / — / Quit. The update labels are English format! strings.
- **Fix:** Add a permanent 'Check for Updates…' item (→ update::check, then show settings on General). Keep the dynamic label as the item text when an update is available. Translate menu_item strings via i18n::t with catalog keys.
- **Phase:** Phase 2

### W-52 — Settings cannot be opened on a specific pane

- **Mac:** `AppDelegate.swift:182-187; IslandEdgeAction.swift:71; IslandViewContent.swift:1643; HydrationView.swift:828` — The ring gear and radial 'Settings' open on Dynamic Island; the island's integrations link opens Integrations; the hydration card opens Hydration.
- **Windows:** `windows/src-tauri/src/lib.rs:1117-1130; windows/src/island/island.ts:1112-1113; windows/src/core/hydrationStore.ts:89,263` — Always opens the single page at its current scroll. Hydration uses a localStorage side channel to scroll to its section.
- **Fix:** open_settings_window(section: Option<String>) emits 'settings-section' to the settings webview, which selects the sidebar row. Pass 'island' from pressRingButton('settings'), 'integrations' from the island's integration links and 'hydration' from views/hydration.ts.
- **Phase:** Phase 1

### W-53 — Windows-only extras with no Mac twin (header h1, footer, key Remove, status lines, Credential Manager notes)

- **Mac:** `none` — None of these exist.
- **Windows:** `windows/src/settings/main.ts:2472, 2484-2487, 243-264, 340-350, 629-632` — h1 'Notchy' + version; footer 'No telemetry. Network requests only go to the services you configure yourself.'; 'Remove' key button; 'Key saved in the Windows Credential Manager.' line; slot note mentioning Credential Manager; 'Both of these hold a connection open…' hint.
- **Fix:** Delete them as part of the pane rebuild. The version moves into the sidebar header.
- **Phase:** Phase 1

### W-54 — Opening Settings does not fold the island

- **Mac:** `AppDelegate.swift:190-194` — closeScreen/collapse before showing, so the always-on-top island never covers Settings.
- **Windows:** `windows/src-tauri/src/lib.rs:1117-1125` — The island stays as it is.
- **Fix:** In show_settings_window, emit the existing collapse/close path to the island window (the Esc behaviour) before show().
- **Phase:** Phase 1

## Found in review

An adversarial review of the Phase 1 port, before it merged, compared each pane with its Swift source and the Mac captures. These were defects in the new Windows code rather than gaps from the audit, so they do not count toward the 295. All were fixed in the same PR.

- [x] **RC1** · high · bug — Settings placement mixes two displays' pixels, so on mixed-DPI setups the window comes back the wrong size, off-centre and partly off-screen
- [x] **RA1** · medium · parity — Sidebar tile glyphs are drawn at about 65–75 % of the Mac's size
- [x] **RA2** · medium · parity — Behavior, Hotkey and Startup GroupBoxes stretch across the pane; on the Mac they hug their content
- [x] **RA3** · medium · bug — Clicking the already-selected sidebar row re-renders the pane and resets Characters' "Character for"
- [x] **RB1** · medium · bug — On Linux, Now Playing still takes one of the four slots, but the pane hides its row
- [x] **RC2** · medium · bug — On Linux the first Settings open of every run shrinks the window to the 640x420 floor (or an odd size), because outer_size() of a never-mapped GTK window is a position
- [x] **RD1** · medium · bug — Settings stays in the old language when the welcome or another window changes it
- [x] **RD2** · medium · parity — disable() greys plain labels and fades fields twice; SwiftUI's .disabled() does neither (Hide after row)
- [x] **RD3** · medium · parity — Disabled Volume slider greys the "NN %" readout and fades the knob to 27%
- [x] **RD4** · medium · parity — Any click or drag on a slider leaves a 3px blue rectangle around the whole slider
- [x] **RD5** · medium · parity — Stepper does not repeat when held and ignores arrow keys
- [x] **RA4** · low · parity — With sounds off, the "NN %" readout is dimmed and the slider nearly disappears
- [x] **RA5** · low · bug — Clicking a sidebar row drops keyboard focus, so ↑/↓ stop moving the selection
- [x] **RA6** · low · parity — The selected sidebar row's title is regular weight; on the Mac it is semibold
- [x] **RA7** · low · parity — Sidebar/detail divider is near-black in dark (#0D0D0D) where the Mac draws #343434
- [x] **RA8** · low · parity — Popup buttons are about 12px narrower than the Mac's for the same text, with a smaller chevron
- [x] **RB2** · low · bug — The ring editor's "+ Add a button" menu stays open after focus leaves it, takes over the arrow keys and can outlive its pane
- [x] **RB3** · low · parity — Ring editor shows Now Playing as two beamed notes; the Mac's row shows SF music.note, a single eighth note
- [x] **RB4** · low · parity — Sign-in and WhatsApp spinner is 12 px; the Mac's ProgressView().controlSize(.small) is 16x16 pt
- [x] **RC3** · low · parity — A Settings window the user resized comes back at that size; the Mac reopens a closed Settings at 720x560 every time
- [x] **RC4** · low · parity — A dropped (free) island is not kept clear: Settings is centred over it, and a bottom island on a short work area covers the status line
- [x] **RC5** · low · bug — With Rust now reverting a refused autostart change, the welcome's 'Launch at startup' switch stays on while the stored value is off
- [x] **RD10** · low · parity — Dark push buttons and popups are lighter than the Mac's
- [x] **RD11** · low · parity — Sidebar selection is 38px with 2px gaps; the Mac's is 40pt with none
- [x] **RD12** · low · bug — Clicking a sidebar row loses keyboard focus, so arrows stop working; each row is its own Tab stop
- [x] **RD13** · low · bug — Segmented control is role=radiogroup but has no arrow keys; every segment is a Tab stop
- [x] **RD14** · low · bug — On Windows, an arrow key on the Language popup switches language and drops keyboard focus
- [x] **RD15** · low · test — Two parity checks can be skipped silently
- [x] **RD6** · low · parity — Slider track 4px and knob 20x14; the Mac's are 6pt and 20x16
- [x] **RD7** · low · parity — Rounded-border fields draw 24px tall with a 0.5px inner border; the Mac's bezel is 26pt with a 1pt border
- [x] **RD8** · low · parity — Link buttons use the accent colour; the Mac's .link style uses linkColor
- [x] **RD9** · low · parity — Sidebar/detail divider is near-black in dark and invisible in light
- [x] **RA2b** · low · parity — Characters' "Hide the characters" box stretched across the pane; on the Mac it is as wide as its note (found while checking RA2)

## Already matches

- Window title 'Settings — Notchy', translated and following language changes (Mac AppDelegate.swift:102,203; Windows main.ts:2469, lib.rs:1031).
- Closing hides and reuses the window; re-launching while off shows Settings (Mac applicationShouldHandleReopen; Windows single-instance plugin).
- Tray/menu: Open Notchy greyed while off, Settings…, Turn Notchy off/on, Quit; icon dimmed to 40% when off; tooltip 'Notchy' / 'Notchy — off'.
- Master switch semantics and hint text, apart from the last clause ('menu bar' vs 'icon by the clock').
- Language values system/en/es/pt-BR, self-named labels, only 'Same as system' translated, the whole window re-renders on change (AppLanguage.swift ↔ core/i18n.ts LANGUAGES/LANGUAGE_LABEL).
- Sound: default on, volume range 0–0.2, default 0.12.
- Auto-close default 5 s clamped 2–120; absence default 180 s clamped 5–3600, disabled while Always visible/Never.
- Close shortcut: off by default, ⌃⌥X ↔ Ctrl+Alt+X, 'Press keys…', 'presses this → island closes', 'This shortcut is taken or not allowed here.', recorder hidden while off.
- Pill cap of 4 and the default active set (notifications, mattermost, ato, music); pill ids, names and colours (INTEGRATION_AGENTS ↔ PillCatalog).
- HomeContent labels and hints for ato/mattermost/whatsapp/timer/claudeCode.
- Island position presets: ids, labels, order and 'Where you dropped it' (parity-tested by tests/island-anchor-parity.ts).
- Skip seconds default 10, range 1–120.
- Snow and Christmas music default true, shown only in season, always in dev builds.
- Agenda: lead choices 5/10/15/30/60 with default 15, both notify toggles default on, agenda off by default, footer hint text identical.
- WhatsApp hint and footer text identical; 'All 4 pill slots are in use…' text identical; Connect switches the pill on when a slot is free.
- 'Show the whole message' text, hint and default off.
- Characters: 'Character for' options and order, 'Everyone else (default)', 'Nothing' / 'As they come', 7-column bodies and 6-column faces, chosen ring #3B9EFF with fill #16222E and name #CFE3F7, Christmas rows Ready-made/Head/Eyes/Texture/Extra with None, 'Until January 6' text, season rule, picker dimmed to 0.4 when hidden. Presets, shapes and festive catalogue are parity-tested.
- Hydration: every string on the five screens, question order and options, block reasons, sources data and URLs, intervals 45/60/90/120, goal step ±100 within 500–4000, timeline legend texts, dot colour #22D3EE, track geometry (4px line, 16px bands, 10px dots), quiet-band unwrapping. Rules are parity-tested by tests/hydration-parity.ts.
- Updates: auto-check on by default every 6 hours, nothing installs without a click, signed packages only.
- Every Mac settings string already exists in i18n/catalog.json, so the port is wiring, not translation; the exceptions are noted in risks.

## Known differences in windows/README.md

- **closable** — 'Settings… → General → Island sits at offers all six spots. Mochi has no such preference on the Mac.' Stale: the Mac now has the same six presets under Dynamic Island › Behavior › 'Where it sits'. Move the Windows row there (W-31) and fix the README. The bottom-right DEFAULT stays platform-forced (no notch).
- **closable** — 'It stays out' — Never (beside Hide after) on by default, plus Standby; the Mac keeps 'Always visible' as its own row. The UI can match exactly: render the Mac 'Always visible' checkbox and the 'Hide after … s without movement' row (W-14) and drop Standby (W-15). Only the default value (alwaysVisible=true on Windows) is platform-forced, because there is no notch to hide into.
- **forced** — The site and ChatGPT open as separate anchored windows; set up under Settings → Pages. The separate window is forced (Tauri has no stable multiwebview), and the anchored window is already the closest equivalent. The SETTINGS side is closable: drop 'Pages' and put the Mac 'ChatGPT (website)' group at the end of Chat with both checkboxes and Clear ChatGPT data (W-37, W-38).
- **closable** — The AI Agents dashboard lacks the Session/Week gauges. Stale and understated: there is no AI Agents panel or settings pane on Windows at all (bridge.ts:296-302 is empty, and EDGE_ACTIONS has no 'agents'). Port the panel and the pane (W-33, W-26). Only the statusline-relay gauges would remain platform/feature-limited.
- **closable** — The ring is dealt differently on a fresh install (message services down the near side; player in the row). The first-run default can stay (edge geometry is platform-specific), but the EDITOR must behave like the Mac: Left/Right/Bottom labels and order, add to the side with fewer, move within the side, + Add menu (W-25).
- **closable** — 'Chat and keys: Settings… → Claude takes your Anthropic API key.' Rename to the Mac 'Chat' pane › 'Anthropic API' group. Storage in Windows Credential Manager instead of the Keychain is platform-forced; only the hint wording changes.
- **closable** — README screenshot windows/screenshots/settings.png shows a 'Claude Code / Install hooks' card and Stripe/GitHub integrations that no longer exist. Retake it after the sidebar rebuild.

## Parity tests to add

- Settings sidebar table: section ids, titles, colour hexes and order (SettingsView.swift:154-164) vs a TS SETTINGS_SECTIONS, plus the default 'general' and the 'island'/'integrations'/'hydration' deep-link ids.
- HomeContent: cases in order, labels, hints, default (.notifications) and migratedRawValue vs state.ts HOME_CONTENTS/HOME_LABEL/HOME_HINT and settings.rs default_home_content. Untested today and already drifted (notifications is missing).
- IslandEdgeAction ids, titles and colours vs edgeRing.ts EDGE_ACTIONS (agents is missing); IslandEdgeSide order (left, right, bottom) vs the TS side list and labels.
- PillCatalog.all (id, name, colour, category, order, alwaysLoadedID) and PillCategory titles vs INTEGRATION_AGENTS plus a TS category field.
- Claude model fallback list and AppState.defaultClaudeModel vs main.ts MODELS and claude.rs DEFAULT_MODEL (they differ today: claude-sonnet-4-6 vs claude-opus-5).
- AppState defaults and ranges dumped from Swift vs DEFAULT_SETTINGS + settings.rs Default: soundVolume 0.12, autoClose 5 with 2…120, absence 180 with 5…3600, skip 10 with 1…120, large 600×650 with 360…600 / 240…800 step 10, notch 32…60 (40) and plain 22…60 (32), close hotkey ⌃⌥X, open hotkey ⌘⇧N, alwaysVisible, islandSnow, christmasMusic, messageBanners true, webChatEnabled/useWebChat false, autostart (TS and Rust disagree today).
- AppLanguage raw values and labels vs LANGUAGES/LANGUAGE_LABEL.
- AgendaRules.leadChoices/defaultLeadMinutes vs the [5,10,15,30,60] literal in main.ts:975.
- Hydration UI bounds not covered by hydration-parity: goal step 500…4000 ±100, manual target 100…6000 (Windows accepts up to 9999).
- RadialAction ids, titles, icons, defaults and RadialGeometry min/max wedges (2/8), once a TS twin exists.
- Connection chip strings: Mac 'Connected as %@', 'Connecting…', 'Not connected', 'Waiting for the QR code to be scanned' and the agenda status texts vs CONNECTION_LABEL and the Windows status mapping.
- Character tile metrics (preview sizes 42/46, name 9.5, colours #16222E/#3B9EFF/#CFE3F7, badge colours) as a small shared constants table.
- Settings window geometry (720×560, min 640×420) vs lib.rs create_settings_window.
- A settings-tree dump: for each pane, the ordered list of group titles and row label/hint catalog keys, from Swift (a test target that walks a declarative description) vs TS, so a row added on one side fails the build.

## Risks

- Native macOS metrics in this report come from SwiftUI defaults, not measurements: GroupBox corner radius, title font and fill, sidebar row height, popup/checkbox/slider sizes, and window background (#1E1E1E vs #262626 in dark, ≈#ECECEC in light). Capture the real Mac Settings window in light and dark at 1x/2x before writing the CSS, and compare screenshots side by side.
- Matching the Settings UI exactly exposes features Windows does not have: radial menu, AI Agents panel, Google/OpenAI/Ollama/LM Studio chat providers, message banners, per-display selection, bar height, open-island hotkey, Big screen sizes. Each needs a real feature port. Showing rows that do nothing would be worse than the current gaps, so sequence the feature ports with the panes.
- The sidebar needs ≥640px width; the current min_inner_size of 460 and any code that assumes the single column (hydration's scrollIntoView, the 'onSetupAsked' path) must be reworked to select the pane instead.
- SF Pro cannot ship on Windows (licence), so Segoe UI Variable will wrap differently; long Portuguese hints at 10–11px may wrap where the Mac's do not.
- Mac quirks that exact parity would copy: 'Accessibility granted.' and 'Signing in…' are built from ternary Strings, so they are not localized on the Mac (they are missing from the catalog). HydrationSettingsView.swift:167 '.disabled(false)' leaves quiet times editable while off. The character tile colours are dark-only even in light mode. Decide whether to copy each one or fix the Mac.
- Security semantics differ: the Mac stores only an Ato password digest and clears the field. Windows stores the raw ato-password in Credential Manager, and the per-field Save writes credentials before sign-in. Moving to the Mac single-Sign-In flow changes when secrets are written.
- Removing Windows-only rows (Standby, Site URL, Forget sign-in, Remove key, inline update progress) removes functionality some users may rely on. Confirm with the owner, or port the same rows to the Mac, before deleting them.
- Defaults already disagree across the three Windows sources (TS DEFAULT_SETTINGS.autostart=false vs Rust true; TS model 'claude-opus-5'). Changing defaults to match the Mac (homeContent 'notifications', model 'claude-sonnet-4-6') only affects fresh installs unless a migration is added.
- README claims (an AI Agents dashboard on Windows; 'Island sits at' being Windows-only) are stale and will mislead whoever implements from it.
