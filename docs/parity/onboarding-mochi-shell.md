# Parity — Welcome, Mochi, tray and updater

The Mac is the source of truth (see `CLAUDE.md`). Each gap names the Mac code, the Windows code and the fix; tick it in the PR that closes it. Audit of 2026-11-20 against `notchy` at f1dee26.

## Checklist

- [ ] **OB-G1** · high · missing on windows · L — Launch greeting Mochi never wears the user's character — _Phase 8_
- [ ] **OB-G2** · high · missing on windows · S — Pill's shipped face (Notifications = antenna + pixel eyes) not honoured — _Phase 8_
- [ ] **OB-G3** · high · visual · S — Greeting card is grey (#141518) instead of black — _Phase 4_
- [ ] **OB-G4** · medium · visual · S — Happy / wink eye arc follows the prototype, not Swift — _Phase 8_
- [ ] **OB-G5** · medium · behaviour · S — Character eyes do not replace a pill's permanent (resting) eye — _Phase 8_
- [ ] **OB-G6** · medium · visual · M — Tray icon is the coloured app icon, not the monochrome Mochi glyph — _Phase 2_
- [ ] **OB-G7** · medium · missing on windows · S — No permanent 'Check for Updates…' item; tray order differs — _Phase 2_
- [ ] **OB-G8** · medium · behaviour · L — No Sparkle-style update prompt window — _Phase 2_
- [ ] **OB-G10** · medium · behaviour · S — Launch at startup defaults to ON (Mac: OFF) — _Phase 1_
- [ ] **OB-G9** · low · copy · S — Tray update labels are hard-coded English — _Phase 2_
- [ ] **OB-G11** · low · extra on windows · S — Dizzy plays a 'dizzy' sound on Windows — _Phase 7_
- [ ] **OB-G12** · low · behaviour · S — After a slap, the hover is not restarted — _Phase 8_
- [ ] **OB-G13** · low · behaviour · S — Alt+F4 on the name screen discards the typed name — _Phase 8_
- [ ] **OB-G14** · low · platform forced · M — Welcome window chrome: no shadow, custom close dot, fixed radius — _Phase 8_
- [ ] **OB-G15** · low · visual · S — Back button colour (link style) — _Phase 8_
- [ ] **OB-G16** · low · visual · S — Face/Body/Christmas segmented control does not look native — _Phase 8_
- [ ] **OB-G17** · low · visual · S — Tile and chip borders and name colours — _Phase 8_
- [ ] **OB-G18** · low · visual · M — Screen change is not a crossfade — _Phase 8_
- [ ] **OB-G19** · low · extra on windows · S — Whole row toggles a switch on Windows — _Phase 8_
- [ ] **OB-G20** · low · visual · S — '4/4 slots used' warning colour — _Phase 8_
- [ ] **OB-G21** · low · visual · S — Selected language row tint — _Phase 8_
- [ ] **OB-G22** · low · extra on windows · S — 'Use the default for this one' underlines on hover — _Phase 8_
- [ ] **OB-G23** · low · platform forced · S — Look grid scrollbar takes room on both sides — _Phase 8_
- [ ] **OB-G24** · low · platform forced · S — Platform words in welcome copy and tip icons — _Phase 8_
- [ ] **OB-G25** · low · behaviour · S — System language resolution only checks the first preferred language — _Phase 1_
- [ ] **OB-G26** · low · visual · S — Waving hands are sized from the shape's box instead of classic's — _Phase 8_
- [ ] **OB-G27** · low · visual · S — Greeting line squeezes text instead of truncating — _Phase 8_
- [ ] **OB-G28** · low · behaviour · S — Tray 'Open Notchy' waits for the greeting and can open 'empty' — _Phase 2_
- [ ] **OB-G29** · low · extra on windows · S — Crash-recovery notice at launch — _not done — the crash-recovery note is Windows reliability_
- [ ] **OB-G30** · low · copy · M — Settings > Updates copy and status line differ — _Phase 2_
- [ ] **OB-G31** · low · platform forced · S — Menu shortcuts (Cmd-, / Cmd-Q) not shown — _not done — tray menus cannot carry working shortcuts_
- [ ] **OB-G32** · low · visual · S — Primary button and progress bar native shapes need checking — _Phase 8_
- [ ] **OB-G33** · medium · visual · S — The Windows app icon is a different drawing from the Mac's — _Phase 8, owner's call_

## How each side is built

MAC (source of truth)
- App shell: NotchBuddyApp (@main, Settings scene only) -> AppDelegate.applicationDidFinishLaunching: SIGPIPE ignore, Keychain warm-up, setActivationPolicy(.accessory) (no Dock), setupMenuBarItem(), setupIsland(). setupIsland: island controller on cursor's chosen display; if enabled && (NOTCHY_ONBOARDING || OnboardingGate.shouldShow) -> island parked (setRunning(false)) and OnboardingWindowController.show(placeBelowIsland) -> on finish startAfterWelcome (MessagingCoordinator + island greeting); else island.showWindow + fsm.launch() (greeting); off -> parked. HookServer, Hydration, Music, Messaging (not under welcome), Agenda start. Reopen (Finder/Spotlight) -> open island or Settings when off. Quit = NSApplication.terminate.
- Menu bar extra (NSStatusItem): template image MenuBarIcon 24x18 (monochrome Mochi glyph, auto-tinted), alpha 0.4 + tooltip "Notchy — off" when off. Menu: Open Notchy (greyed when off) | separator | Settings… (Cmd-,) | Check for Updates… (always) | Turn Notchy off/on | separator | Quit (Cmd-Q). Titles re-localised on .languageChanged.
- Updater: Sparkle SPUStandardUpdaterController, 6 h schedule (SUScheduledCheckInterval 21600, SUEnableAutomaticChecks), Sparkle's own windows for 'update available' (notes, Install/Skip/Remind), progress and 'up to date'. Settings > Updates GroupBox: 'Notchy x.y', 'Check for updates' button, 'Check automatically' toggle, privacy hint.
- Language: AppLanguage (system/en/es/pt-BR, self-named labels), resolved over Locale.preferredLanguages; L()/Text(loc:) + Localizing { .environment(locale).id(language) } rebuilds every SwiftUI window; AppKit titles refreshed by notification.
- Welcome: OnboardingWindowController: NSWindow 520x660 titled+closable+fullSizeContentView, transparent titlebar, title hidden, movable by background, darkAqua, black, mini/zoom hidden, level .floating, placed centred under the island; local mouse-down monitor routes presses on Mochi to slap. OnboardingModel (flow, name, launchAtLogin via SMAppService, engine, editing, lookTab, pointer/gaze/hover/love logic). OnboardingView tree: VStack(spacing 0) [topBar(Skip, h22 + top10) | OnboardingMochiView(diameter 56 questions / 84 hello+ready, overhang 34) | progressRow(Back link + ProgressView + 'N of 5') | screen(.id(step).transition(.opacity), top 16, top/centre aligned) | footer(borderedProminent large, minWidth 190, 13.5 semibold: Begin/Continue/Open Notchy, default action)] padding h32 b26, black, .animation(easeInOut 0.2). Screens: welcome (26 bold title, 13.5 body, 13.5 secondary), name (19 semibold, 300x42 field r10, preview capsule #101113 h36), language (OnboardingOption rows), look (OnboardingLookScreen: heading, chips (Everyone + pills, 66 wide, preview 20), reset line h18, segmented Face/Body/Christmas, ScrollView of 7-column LazyVGrid of CharacterTile size 30; Christmas: badge, Ready-made, Head, Eyes, Texture, Extra), tools (service pill rows h34 with small switches, 'n/4 slots used'), startup (Launch at Mac startup, Enable sounds rows h40), ready (26 bold 'All set, X!', 3 SF-symbol tips).
- Mochi: BotEngine (state table, emotes, tweens, particles, idle look/breath/blink, dance, draw/drawHandsBehind/drawHandsAndExtras/drawParticlesOnly), MochiCharacter (accessory/eye/shape/festive, resolve(shape, resting:)), MochiShape (generated), MochiFur, MochiFestive(+Data, generated JSON), MochiDress (lends the character to the greeting and upload renderers), CharacterPreviewView/CharacterTile. Greeting: GreetingCanvasView (CG drawing in 640x150 space, dressed via MochiDress, card IslandConst.cardHex #000000, SwiftUI Text line).

WINDOWS/LINUX (Tauri)
- Shell: lib.rs run(): panic hook, OS restart registration (--recovered), settings load, welcome decision (same gate + NOTCHY_ONBOARDING), plugins (single-instance -> open_island/show settings, autostart, dialog, updater, global-shortcut), windows created hidden at launch (settings, clipboard, onboarding, web, whatsapp), island shown or parked, tray::build, pipe/media/mattermost/ato/whatsapp start, update::start (90 s then 6 h), autostart sync with OS. main.ts (island page): boot, setLanguage + Bridge.setLanguage, island.start() under welcome else launch() (greeting + optional 'recovered' note); listens to tray 'open', settings-changed, onboarding-finished/start.
- Tray (tray.rs): TrayIconBuilder with app's colour icon (default_window_icon), alpha x0.4 when off, tooltip 'Notchy'/'Notchy — off'. Menu: Open Notchy (greyed when off) | [Update to X… / Version X is out — open the page… / Restart to finish updating to X — only when relevant] | separator | Settings… | Turn Notchy off/on | separator | Quit. Rebuilt on language/master/update changes.
- Updater (update.rs + settings/main.ts Updates section): tauri-plugin-updater, phases idle/checking/upToDate/available/downloading/ready/error, key-mismatch detection, portable -> releases page; all UI inline in Settings + tray row; no standalone prompt window.
- Language: core/i18n.ts t(), LANGUAGES same four, resolve via navigator.language; Rust i18n.rs for tray (reported language).
- Welcome: lib.rs create_onboarding_window (520x660 logical, frameless, transparent, no shadow, always on top, skip taskbar, hidden), show_onboarding_window placed by island::welcome_origin, CloseRequested -> finish; onboarding/main.ts host; welcome.ts (module state + SCREENS map) builds DOM: .ob panel [.ob-close red dot | .ob-top Skip | .ob-stage canvas | .ob-progress | .ob-screen > .ob-inner(.fade) | .ob-foot .ob-go]; onboarding.css carries the Mac numbers. Mochi: one BotEngine on a canvas with the same gaze/hover/slap/dizzy rules; Ato via drawAtoInBotFrame.
- Mochi: engine.ts (port of BotEngine, draw includes hands/badge/particles), character.ts, shape.ts (generated, parity-tested), festive.ts + festive.generated.ts (byte-identical JSON, tested), preview.ts (static swatches), minibots.ts. Greeting: mochi/greeting.ts (Canvas 2D port in the same 640x150 space) driven by island.ts; no MochiDress equivalent.

Organisation: the Windows welcome mirrors the Mac screen for screen and constant for constant (comments cite the Swift); core rules (steps/progress/gate/names/periods, presets, shapes, festive data, season) are parity-tested. Gaps cluster in: things Windows never ported (MochiDress, pill shipped faces, resting-eye rule, Sparkle prompts, permanent Check for Updates), defaults/behaviours chosen differently (autostart, dizzy sound, tray order), and native-chrome look-alikes (window, tray glyph, segmented control).

## Gaps

### OB-G1 — Launch greeting Mochi never wears the user's character

- **Mac:** `NotchBuddy/Sources/App/GreetingCanvasView.swift:644-679; MochiDress.swift:22-121; BotEngine.swift:1807-1856` — The greeting builds MochiDress(character: AppState.character(for: focusTask?.id)): a shaped body path scaled to the greeting's hw/hh (bodyPath(rx:ry:)), accessories behind (ears/horns/antenna/sprout) and in front (crown/bow/beret/sparkles), and the character's own eyes in the greeting's sockets (halfGap hb*0.19, size hb*0.12) with the greeting's expression as the glint (dot->pill, happy/content->happy). Classic characters draw exactly the old Mochi.
- **Windows:** `windows/src/mochi/greeting.ts:350-452 (drawMochi), 573-601 (draw); windows/src/island/island.ts:463-478` — Always draws classic Mochi (superellipse n=3.2, aspect 1.34, #16171A dot/arc eyes) whatever the user picked in the welcome's look screen or Settings > Characters.
- **Fix:** Add windows/src/mochi/dress.ts, a port of MochiDress: construct a throwaway BotEngine with character, bodyColor null, yaw/pitch/roll/tilt 0; expose from engine.ts public wrappers characterBodyPath(R) (shapedPath with bodyLOD/furAmount), drawAccessoryBehind/Front(x, R, rx, ry, body) and drawCharacterEyes(x, slots, w, h, open, R, rx, glint). In greeting.ts drawMochi take a `dress` argument: body = dress.bodyPath(hw, hh) scaled by (hw/hh, 1) or mochiPath; draw dress behind before the body, skip own eyes when dress.hasOwnEyes, then dress.drawEyes at (±halfGap+offset) and dress.drawFront — all inside the same translate/rotate/scale as the body. Island passes State.characterFor(focusTask id) into Greeting.start. Do the same for upload/canvas.ts (UploadCanvasView uses MochiDress too).
- **Phase:** Phase 8

### OB-G2 — Pill's shipped face (Notifications = antenna + pixel eyes) not honoured

- **Mac:** `NotchBuddy/Sources/App/PillCatalog.swift:~99-103 (character: MochiCharacter(accessory: .antenna, eye: .pixel)); AppState.swift:663-670` — character(for:) = pillCharacters[id] ?? PillCatalog.definition(id).character ?? defaultCharacter. The Notifications pill's Mochi has an antenna and pixel eyes out of the box — on the island minis, in the welcome's look chip/header/tiles, and its 'Classic' face tile writes a real override.
- **Windows:** `windows/src/core/state.ts:215-227, 874-877 (characterFor); windows/src/onboarding/welcome.ts:860-864 (characterOf)` — characterFor/characterOf = pillCharacters[id] ?? defaultCharacter; the Notifications Mochi is the default (classic) everywhere; in the look screen the Antenna/Pixel face is not shown as chosen and picking Classic for Notifications is a no-op (writeLook sees no change).
- **Fix:** Add an optional `character` storage string to the INTEGRATION_AGENTS task for NOTIFICATIONS_PILL ("antenna:pixel:-"), and make State.characterFor and welcome.ts characterOf return stored ?? agent.character ?? defaultCharacter. Add the shipped characters to a PillCatalog parity dump.
- **Phase:** Phase 8

### OB-G3 — Greeting card is grey (#141518) instead of black

- **Mac:** `NotchBuddy/Sources/App/GreetingCanvasView.swift:573-578; IslandTypes.swift:208 (cardHex = "#000000")` — The 620x104 r20 greeting card is pure black, so on the black island only the particle rings, halo and Mochi read.
- **Windows:** `windows/src/mochi/greeting.ts:580-586 (fillStyle "#141518"); windows/src/style.css:17 (--card: #141518)` — Card filled #141518 — a visible dark-grey slab (see windows/screenshots/greeting.png). The same --card value colours the island's cards.
- **Fix:** Use "#000000" in greeting.ts (and change --card in style.css to #000000 to match IslandConst.cardHex island-wide; coordinate with the island auditor).
- **Phase:** Phase 4

### OB-G4 — Happy / wink eye arc follows the prototype, not Swift

- **Mac:** `NotchBuddy/Sources/App/BotEngine.swift:2389-2393 (.happy), 2434-2446 (.wink)` — Path.addArc(center (0, h*0.18), radius w*0.82, start 192°, end 168°, clockwise: true), stroked w*0.5 round. In SwiftUI's flipped space clockwise:true sweeps by decreasing angle, which does not produce the prototype's ∩ arc. Shown for 2 s on every greet() (the welcome's hello screen), the finished state, dancing, chewing, wink emote.
- **Windows:** `windows/src/mochi/engine.ts:1-5 (declared deviation), 1987-1993, 2035-2046` — arc(0, h*0.18, w*0.82, 1.12π → 1.88π) — the prototype's ∩ (design/captures/char_state_finished.png).
- **Fix:** First capture the Mac's happy eye on a real Mac. If the Mac draws something other than the ∩ and the owner wants the Mac to be the source of truth, port the Swift path literally (canvas arc(0, h*0.18, w*0.82, 192°, 168°, anticlockwise=true)). The better fix is to change the Swift arc to the prototype's so that both match the design. Then record the chosen geometry in a parity dump.
- **Phase:** Phase 8

### OB-G5 — Character eyes do not replace a pill's permanent (resting) eye

- **Mac:** `NotchBuddy/Sources/App/MochiCharacter.swift:65-75 (resolve(_:resting:)); BotEngine.swift:1506-1533, 1669-1670` — resting = eyeOverride != nil && eyeOverrideUntil == ∞ (miniEye / setPermanentEmote); resting is cleared for dance/chewing/cup; character.resolve(shape, resting:) lets the chosen eyes (and festive eyes) replace a resting override.
- **Windows:** `windows/src/mochi/character.ts:198-205 (resolveEye, no resting); windows/src/mochi/engine.ts:1661-1687` — resolveEye only replaces 'pill'/'wide'; a mini Mochi with a permanent emote/miniEye keeps those eyes forever and never shows its chosen character or Christmas eyes.
- **Fix:** Add `resting` to resolveEye(character, shape, resting=false) with Swift's rule (resting || isNeutral). In engine.drawEyes, compute resting as in BotEngine.swift:1516-1526 and use it for both resolveEye and the festive check (`festive = worn && (resting || isNeutral(shape))`). Extend mochi-character-parity.ts to cover it.
- **Phase:** Phase 8

### OB-G6 — Tray icon is the coloured app icon, not the monochrome Mochi glyph

- **Mac:** `NotchBuddy/Sources/App/AppDelegate.swift:32-38; NotchBuddy/Assets.xcassets/MenuBarIcon.imageset/menubar@2x.png` — Template image (isTemplate) 24x18 pt: solid Mochi silhouette with two eye cut-outs and an antenna nub at top right. AppKit tints it white or black to follow the menu bar, and sets alpha 0.4 when the app is off.
- **Windows:** `windows/src-tauri/src/tray.rs:74-85, 107-109; windows/src-tauri/icons/32x32.png` — The 32x32 full-colour white Mochi app icon (dark rim) is used, with per-pixel alpha x0.4 when off.
- **Fix:** Ship the MenuBarIcon glyph as tray assets: white and black variants at 16, 20, 24 and 32 px, generated by scripts/gen-icons.mjs from the same shape. Choose the variant from the Windows theme (HKCU\...\Personalize\SystemUsesLightTheme) and rebuild the tray when WM_SETTINGCHANGE arrives. On Linux use the appindicator symbolic icon. Keep the 0.4 alpha when off.
- **Phase:** Phase 2

### OB-G7 — No permanent 'Check for Updates…' item; tray order differs

- **Mac:** `NotchBuddy/Sources/App/AppDelegate.swift:40-58, 95-108, 112-116` — Menu: Open Notchy | — | Settings… | Check for Updates… (always present, opens Sparkle, which answers either way) | Turn Notchy off | — | Quit.
- **Windows:** `windows/src-tauri/src/tray.rs:35-66; windows/src-tauri/src/update.rs:197-205` — Menu: Open Notchy | [update row only while one is available/ready, directly under Open] | — | Settings… | Turn Notchy off | — | Quit. Nothing to click to check for updates from the tray.
- **Fix:** Build the menu in the Mac's order. Add an 'update' item after Settings… labelled t("Check for Updates…") that runs update::check_now(app, true) and shows the result (see G8). While a version is available or ready, either relabel that same item to the localised 'Update to %@…' or keep the Mac label and let the prompt carry the version. Do not insert the item under Open.
- **Phase:** Phase 2

### OB-G8 — No Sparkle-style update prompt window

- **Mac:** `NotchBuddy/Sources/App/Updater.swift:41-66; project.yml:147-149 (SUEnableAutomaticChecks, 21600 s)` — When a scheduled check finds a release, Sparkle opens its own window with the app icon, 'A new version of Notchy is available!', a release-notes view, and Skip This Version / Remind Me Later / Install Update. Install shows a download progress window, then 'Install and Relaunch'. A manual check with nothing new shows a 'You're up to date!' alert.
- **Windows:** `windows/src-tauri/src/update.rs:282-332 (check_now), 409-420 (from_tray); windows/src/settings/main.ts:660-775` — A background find only changes the tray row and the Settings > Updates line. There is no window, and no skip-this-version or remind-later. Clicking the tray row starts downloading straight away and opens Settings to show progress. A manual check's answer appears only as a status line in Settings.
- **Fix:** Add a small 'updater' webview window, created hidden at launch because WebView2 windows created later come up blank. Lay it out like Sparkle: icon, title, a 'Notchy %@ is now available — you have %@.' line, a notes box (text only), and Skip This Version / Remind Me Later / Install Update buttons, then a progress state and 'Install and Relaunch'. Open it on the first background find of each version, unless that version was skipped (store it in settings.skipped_update). Have the tray's Check for Updates… open it in 'checking' and then 'up to date', 'available' or 'error' state. Keep Settings > Updates as the Mac has it.
- **Phase:** Phase 2

### OB-G9 — Tray update labels are hard-coded English

- **Mac:** `NotchBuddy/Sources/App/AppDelegate.swift:99 (L("Check for Updates…"))` — Every menu title goes through L() and follows the chosen language.
- **Windows:** `windows/src-tauri/src/update.rs:197-205` — format!("Update to {version}…"), "Version {version} is out — open the page…" and "Restart to finish updating to {version}" never pass through i18n::t, and the last two are not in i18n/catalog.json. A Portuguese menu therefore shows English rows.
- **Fix:** Route the strings through crate::i18n::t(&lang, …) with %@ substitution, and add the keys to the catalogue. This becomes moot if G7 replaces the row with 'Check for Updates…'.
- **Phase:** Phase 2

### OB-G10 — Launch at startup defaults to ON (Mac: OFF)

- **Mac:** `NotchBuddy/Sources/App/OnboardingView.swift:27-28, 212-222; SettingsView.swift:29, 439-443` — launchAtLogin reads SMAppService.mainApp.status. A fresh install is not registered, so the welcome's 'Launch at Mac startup' switch starts OFF and nothing registers until the user turns it on.
- **Windows:** `windows/src-tauri/src/settings.rs:383 (autostart: true); windows/src-tauri/src/lib.rs:1380-1394; windows/src/onboarding/welcome.ts:978-982` — A fresh install defaults to autostart=true and registers with the OS at first launch, so the welcome's 'Launch at startup' switch starts ON. The TS DEFAULT_SETTINGS says false, but Rust's value wins.
- **Fix:** Set autostart: false in settings.rs Default, so a fresh install matches the Mac. The lib.rs sync then keeps the OS consistent. Settings files that already exist keep their stored value. If the owner prefers ON, change the Mac instead; one of the two must move.
- **Phase:** Phase 1

### OB-G11 — Dizzy plays a 'dizzy' sound on Windows

- **Mac:** `NotchBuddy/Sources/App/OnboardingView.swift:71-80; IslandWindowController.swift:1670-1686 (no sound)` — The third slap calls setState(.dizzy, force: true): a two-turn roll and spiral eyes, then after 3.3 s idle and a happy emote. The 'dizzy' sound is never played anywhere on the Mac; only slap and annoyed sounds come from the earlier slaps.
- **Windows:** `windows/src/onboarding/welcome.ts:218-227; windows/src/island/island.ts:1690-1694` — The welcome and the island both call Sound.play("dizzy") on the third slap, and setState is not forced.
- **Fix:** Remove Sound.play("dizzy") from both places and call engine.setState("dizzy", true).
- **Phase:** Phase 7

### OB-G12 — After a slap, the hover is not restarted

- **Mac:** `NotchBuddy/Sources/App/OnboardingView.swift:136-142, 144-151` — slap() cancels the love wait, sets hovering=false, slaps, then re-runs pointerMoved. The pointer is still on him, so hoverIn fires again: a blink, eyes back to 1.08, the hover sound, and a new 1.9 s love timer, unless hearts were sent less than 6 s ago.
- **Windows:** `windows/src/onboarding/welcome.ts:1036-1044, 1170-1194` — onPress only calls cancelHover(): eyes go back to 1 and the timer is cleared, but hover.on stays true. There is no re-hover and no blink or sound, and no hearts until the pointer moves 40 px or leaves and comes back.
- **Fix:** In onPress, after cancelHover(), set hover.on = false and call trackHover(mochiCircle(), pointer) after engine.slap().
- **Phase:** Phase 8

### OB-G13 — Alt+F4 on the name screen discards the typed name

- **Mac:** `NotchBuddy/Sources/App/OnboardingWindow.swift:124-130` — windowWillClose (the close button or Cmd-W) calls model.leaveStep(), so a name typed on the name screen is saved, exactly as Skip saves it.
- **Windows:** `windows/src-tauri/src/lib.rs:243-254, 315-350; windows/src/onboarding/main.ts:68; windows/src/onboarding/welcome.ts:241-257` — Rust handles CloseRequested itself: it finishes, then the page receives 'onboarding-finished' and runs stopWelcome() without commitName(). The in-page red button calls skip() and keeps the name; Alt+F4 loses it.
- **Fix:** On CloseRequested, emit 'onboarding-close' to the page and let it call skip(), which commits and then finishes. Keep the Rust finish as a fallback if the page does not answer within about 500 ms. Alternatively, call leaveStep() at the top of stopWelcome() while host is still set.
- **Phase:** Phase 8

### OB-G14 — Welcome window chrome: no shadow, custom close dot, fixed radius

- **Mac:** `NotchBuddy/Sources/App/OnboardingWindow.swift:47-73; OnboardingView.swift:275-281, 297-311` — A native titled window: system rounded corners, system drop shadow, the darkAqua 1 px rim, and the native red close button, which turns grey when the window is inactive and shows × on hover of the button group. Skip is aligned with that button.
- **Windows:** `windows/src-tauri/src/lib.rs:220-241 (.decorations(false).transparent(true).shadow(false)); windows/src/onboarding/onboarding.css:58-97` — A frameless transparent window with a CSS radius of 12 px, an inset 1 px rgba(255,255,255,.1) rim, and no shadow. A hand-drawn 12x12 #FF5F57 dot at (10,10) stays red when the window is unfocused.
- **Fix:** For the closest equivalent, on Windows 11 drop transparency and use .shadow(true) with DWMWA_WINDOW_CORNER_PREFERENCE=ROUND for a native shadow and rounded corners; elsewhere pad the window 24 px and draw box-shadow 0 18px 50px rgba(0,0,0,.55) in CSS. Grey the dot (rgba(255,255,255,.22)) on window blur. Measure the Mac's close-button centre and corner radius from a capture (macOS 15 about 10 pt, macOS 26 larger), and align .ob-close and Skip to them.
- **Phase:** Phase 8

### OB-G15 — Back button colour (link style)

- **Mac:** `NotchBuddy/Sources/App/OnboardingView.swift:314-331` — Back is a 10 pt semibold chevron.left plus 'Back' with .buttonStyle(.link), which on macOS normally draws in the link/accent colour.
- **Windows:** `windows/src/onboarding/onboarding.css:139-149` — Back is drawn in --primary #F5F6F8 at 13 px.
- **Fix:** Check a Mac capture. If it is blue, set .ob-back { color: #419CFF } (dark linkColor) or var(--accent).
- **Phase:** Phase 8

### OB-G16 — Face/Body/Christmas segmented control does not look native

- **Mac:** `NotchBuddy/Sources/App/OnboardingView.swift:825-838 (Picker .segmented .fixedSize)` — A native NSSegmentedControl in dark mode: a filled rounded track (about rgba(255,255,255,.1)) with no outline, the selected segment as a raised lighter pill with a soft shadow, 13 pt labels, about 22 pt high, and every segment as wide as the widest label plus padding.
- **Windows:** `windows/src/onboarding/onboarding.css:552-576` — A transparent track with a 1 px rgba(255,255,255,.1) border and radius 7, fixed 84 px segments, 12 px labels, and the selected segment as a flat rgba(255,255,255,.14) fill.
- **Fix:** .ob-tabs { background: rgba(255,255,255,.1); border: 0; padding: 1px; border-radius: 7px } .ob-tab { font-size: 13px; height: 20px; min-width: (widest label + 24px), measured once } .ob-tab[aria-selected=true] { background: rgba(255,255,255,.24); box-shadow: 0 1px 1.5px rgba(0,0,0,.35) }. Compare against a Mac capture.
- **Phase:** Phase 8

### OB-G17 — Tile and chip borders and name colours

- **Mac:** `NotchBuddy/Sources/App/CharacterSettingsView.swift:50-68; OnboardingView.swift:983-1005` — An unchosen tile or chip has a 1 pt white 0.08 stroke and its name in system .secondary (dark, about rgba(235,235,245,0.6)). Chosen: #16222E fill, #3B9EFF stroke, #CFE3F7 name.
- **Windows:** `windows/src/onboarding/onboarding.css:415-451, 486-523` — The tile stroke is rgba(255,255,255,0.05) (the chip's is 0.08), and both names use #8E939C.
- **Fix:** Set .ob-tile box-shadow to inset 0 0 0 1px rgba(255,255,255,.08), and set the .ob-tile > span and .ob-chip > span colour to rgba(235,235,245,.6).
- **Phase:** Phase 8

### OB-G18 — Screen change is not a crossfade

- **Mac:** `NotchBuddy/Sources/App/OnboardingView.swift:261-270, 292` — screen.id(step).transition(.opacity) under .animation(.easeInOut(0.2)): the old screen fades out while the new one fades in. The progress row fades in and out, and the Mochi frame (56↔84) and the ProgressView value animate on the same curve, cubic-bezier(.42,0,.58,1).
- **Windows:** `windows/src/onboarding/welcome.ts:366-403, 1060-1073; windows/src/onboarding/onboarding.css:159-172, 206-214` — The whole panel is rebuilt. The old screen vanishes at once and the new .ob-inner fades in over 0.2 s. The progress row pops in and out, and Mochi's size eases with a quadratic in-out.
- **Fix:** Keep the previous .ob-inner absolutely positioned in .ob-screen and fade it to 0 over 200 ms while the new one fades in. Fade .ob-progress in and out. Use cubic-bezier(.42,0,.58,1) for the CSS animations, and the matching cubic for the canvas resize ease.
- **Phase:** Phase 8

### OB-G19 — Whole row toggles a switch on Windows

- **Mac:** `NotchBuddy/Sources/App/OnboardingView.swift:444-465, 481-493` — Only the small switch is clickable. The row is a plain HStack with a background.
- **Windows:** `windows/src/onboarding/welcome.ts:931-935, 972` — Rows are <label> elements, so a click anywhere on the row flips the switch.
- **Fix:** Use <div class="ob-row"> instead of <label>, and give the switch an aria-label with the row's name.
- **Phase:** Phase 8

### OB-G20 — '4/4 slots used' warning colour

- **Mac:** `NotchBuddy/Sources/App/OnboardingView.swift:436-438 (.orange)` — SwiftUI .orange, which is systemOrange in dark mode (#FF9F0A).
- **Windows:** `windows/src/onboarding/onboarding.css:720-722 (#ff8a3d)` — #FF8A3D.
- **Fix:** .ob-count.full { color: #FF9F0A }
- **Phase:** Phase 8

### OB-G21 — Selected language row tint

- **Mac:** `NotchBuddy/Sources/App/OnboardingView.swift:597 (Color.accentColor.opacity(0.25))` — The system accent at 25 %. In dark mode with the default blue that is rgba(10,132,255,.25), and it follows the user's macOS accent colour.
- **Windows:** `windows/src/onboarding/onboarding.css:400-403` — rgba(10,120,255,.25).
- **Fix:** Use rgba(10,132,255,.25). The user's Windows accent colour could be read as well, but the Mac default is the safer match.
- **Phase:** Phase 8

### OB-G22 — 'Use the default for this one' underlines on hover

- **Mac:** `NotchBuddy/Sources/App/OnboardingView.swift:764-778` — A plain button in accent colour, 11 pt, with no hover underline.
- **Windows:** `windows/src/onboarding/onboarding.css:540-550` — The link is underlined on hover.
- **Fix:** Delete the .ob-link:hover rule.
- **Phase:** Phase 8

### OB-G23 — Look grid scrollbar takes room on both sides

- **Mac:** `NotchBuddy/Sources/App/OnboardingView.swift:782-794` — The ScrollView uses macOS overlay scrollers, which take no width, so the 7-column grid fills the full 456 pt.
- **Windows:** `windows/src/onboarding/onboarding.css:581-592` — scrollbar-gutter: stable both-edges reserves a thin bar's width on each side, so the tiles are narrower than on the Mac.
- **Fix:** Remove both-edges and use an overlay-style custom scrollbar (absolutely positioned thumb), since WebView2 has no overlay scrollbars. Alternatively use scrollbar-gutter: auto with a 6 px thin bar.
- **Phase:** Phase 8

### OB-G24 — Platform words in welcome copy and tip icons

- **Mac:** `NotchBuddy/Sources/App/OnboardingView.swift:387, 472, 502-504, 511-522` — 'I live in your Mac's notch. …', 'Launch at Mac startup', 'Move the pointer to the notch whenever you want to see me.', 'Settings are in the menu bar icon.' Tip icons are the SF Symbols cursorarrow.rays, menubar.rectangle and slider.horizontal.3 at 13 pt in accent, 20 pt wide.
- **Windows:** `windows/src/onboarding/welcome.ts:84-89, 451, 978, 1007-1009` — 'I live at the edge of your screen. …', 'Launch at startup', 'Move the pointer to my spot on the screen…', 'Settings are in the tray icon.' The icons are hand-drawn 15 px SVGs at stroke 1.7, and a taskbar glyph replaces the menu bar one.
- **Fix:** Keep the platform wording, which is right for a PC, but use 'Launch at Windows startup' on Windows and 'Launch at login' on Linux as new catalogue keys. Redraw the three icons to the SF symbols' proportions at 13 px optical size so they read the same weight.
- **Phase:** Phase 8

### OB-G25 — System language resolution only checks the first preferred language

- **Mac:** `NotchBuddy/Sources/App/AppLanguage.swift:36-45` — Walks Locale.preferredLanguages in order and returns the first pt / es / en match, else en. A user whose list is [fr, pt-BR] gets Portuguese.
- **Windows:** `windows/src/core/i18n.ts:30-41; windows/src-tauri/src/i18n.rs:22-44` — Uses navigator.language only, so the same user gets English. Rust falls back to environment variables.
- **Fix:** Iterate navigator.languages and return the first tag that starts with pt, es or en, else en. Report that result to Rust as now.
- **Phase:** Phase 1

### OB-G26 — Waving hands are sized from the shape's box instead of classic's

- **Mac:** `NotchBuddy/Sources/App/BotEngine.swift:1019-1043` — drawHandsBehind always uses rx=1.14R and ry=0.88R for the hand ellipse (0.30ry x 0.26ry) and for bodyH. Only the anchor (handX/handY) comes from the shape.
- **Windows:** `windows/src/mochi/engine.ts:832-840, 2107-2123` — Receives the shaped rx/ry (rxK/ryK), so a Frog's waving hands are about 15 % smaller and a Pointy's about 16 % larger than on the Mac.
- **Fix:** Inside drawHandsBehind, use const ry0 = R*0.88 for hew/heh/bodyH, as Swift does.
- **Phase:** Phase 8

### OB-G27 — Greeting line squeezes text instead of truncating

- **Mac:** `NotchBuddy/Sources/App/GreetingCanvasView.swift:709-724` — SF 13 semibold #F5F6F8, lineLimit 1, tail truncation ('…') within a maximum width of 560.
- **Windows:** `windows/src/mochi/greeting.ts:607-624` — fillText(label, x, y, 560) compresses the glyphs horizontally when the text is too long.
- **Fix:** Measure the text with measureText and cut it with '…' to fit 560 px before calling fillText.
- **Phase:** Phase 8

### OB-G28 — Tray 'Open Notchy' waits for the greeting and can open 'empty'

- **Mac:** `NotchBuddy/Sources/App/AppDelegate.swift:118-123` — Brings the welcome forward if it is up; otherwise expands the island to .overview immediately.
- **Windows:** `windows/src/main.ts:47-49; windows/src-tauri/src/lib.rs:299-305` — island.alert(State.defaultView()), which is held back until the greeting has played and opens the 'empty' view when there are no tasks.
- **Fix:** Call island.expand("overview") directly, or match what IslandWindowController.expand(to: .overview) shows when there are no tasks.
- **Phase:** Phase 2

### OB-G29 — Crash-recovery notice at launch

- **Mac:** `NotchBuddy/Sources/App/AppDelegate.swift:19-28 (no equivalent)` — No restart-after-crash registration and no 'recovered' note.
- **Windows:** `windows/src-tauri/src/lib.rs:1136-1139; windows/src/main.ts:110-123; windows/src/island/island.ts:1231-1235` — The app registers with the OS for restart. After a crash it relaunches with --recovered, and the island shows a recovered note after the greeting.
- **Fix:** Keep it for reliability; it only shows after a crash. For strict parity, either add the same note on the Mac or hide it on Windows.
- **Phase:** not done — the crash-recovery note is Windows reliability

### OB-G30 — Settings > Updates copy and status line differ

- **Mac:** `NotchBuddy/Sources/App/SettingsView.swift:445-463` — A 'Notchy x.y' row with a 'Check for updates' button, a 'Check automatically' toggle, and the hint '…It never installs or restarts on its own — that is the Install button. Every build is signed…'. There is no status line; Sparkle's windows give the answers.
- **Windows:** `windows/src/settings/main.ts:690-775` — A coloured dot heading, a status line (Looking… / You are on the latest version. / Notchy %@ is out… / Downloading… %lld%), a button whose label changes, a progress bar, inline notes, and the hint '…It never downloads or restarts on its own — that is this button. Every package is signed…'.
- **Fix:** Once G8 exists, reduce the section to the Mac's three rows and the Mac hint string, and move the status, notes and progress into the updater window.
- **Phase:** Phase 2

### OB-G31 — Menu shortcuts (Cmd-, / Cmd-Q) not shown

- **Mac:** `NotchBuddy/Sources/App/AppDelegate.swift:46, 56` — Settings… shows ⌘, and Quit shows ⌘Q.
- **Windows:** `windows/src-tauri/src/tray.rs:40-49` — No accelerators.
- **Fix:** Leave as is: Windows tray menus do not carry app shortcuts and an accelerator there would not work globally. Optionally show 'Ctrl+,' text for Settings to mirror the Mac.
- **Phase:** not done — tray menus cannot carry working shortcuts

### OB-G32 — Primary button and progress bar native shapes need checking

- **Mac:** `NotchBuddy/Sources/App/OnboardingView.swift:323-325, 333-343; project.yml:4-5 (macOS 15.0+)` — A .borderedProminent .controlSize(.large) button: on macOS 15 a rounded rectangle (radius about 6 pt, about 28 pt tall, accent gradient); on macOS 26 a capsule. A linear ProgressView in accent: a thin rounded bar about 4–6 pt.
- **Windows:** `windows/src/onboarding/onboarding.css:151-165, 224-237` — A 28 px capsule (radius 14, minimum width 218) in flat #3B9EFF; an 8 px track at rgba(255,255,255,.08) with radius 4.
- **Fix:** Find out which macOS the owner's Mac runs, and match the button radius (6 px on 15, 14 px on 26) and the progress track height (about 5 px) to a capture.
- **Phase:** Phase 8

## Already matches

- Seven screens in the same order, 'N of 5' progress, first-run gate and onboardingVersion=1, NOTCHY_ONBOARDING preview variable with the same step names (parity-tested by tests/welcome-parity.ts)
- Name rules: typed name cleaning (40 graphemes), account first-name heuristic (32 max, handle detection), greeting fallback, day periods 5-12/12-18/else, greeting keys (parity-tested)
- Welcome window 520x660, above other windows, no taskbar/Dock, centred horizontally next to the island, brought forward instead of duplicated, 'Open Notchy' and second launch bring it back while up, island parked under it, greeting replayed when it ends, 'Show the welcome again…' folds the island
- Palette (Ink #F5F6F8/#B8BCC4/#8E939C/#3B9EFF, field .07, row .06, edge .10), all font sizes/weights, paddings (32/26), top bar 22+10, Mochi 84/56 with 34 overhang, screen top 16, row heights 34/40 r10, name field 300x42 r10 with accent focus stroke, greeting preview capsule #101113 h36, 7-column grid gap 6, tile 30, chip 20 / 66 wide, reset line h18, Christmas badge colours, section label 10.5 @0.8
- Behaviour: choices saved immediately, name saved on leaving its screen, Skip keeps choices, language switch re-renders in place without losing step or draft, 4-slot rule with disabled fifth, Claude Code excluded from welcome, Ato listed only with Christmas, face pick removes Christmas, body pick keeps it, 'Use the default for this one', love emote on every pick, greet/proud/happy per screen with 0.45 s hello delay, Enter = primary button
- Header Mochi interaction: gaze tanh(dx/260), -tanh(dy/200) eased over 0.28 s, eyes x0.3/x0.24, lean 3 px / 2.5 px / 0.07 rad; hover blink + 1.08 eyes + hover sound, hearts after 1.9 s, 6 s cooldown, 40 px restart; slap squash/annoyed; 3 slaps in 1.7 s dizzy for 3.3 s then idle + happy; Ato orb in header while dressing Ato
- 18 character presets, accessories, eye kinds, storage string format, preset matching by face (parity-tested by tests/mochi-character-parity.ts); Christmas season 15 Nov–6 Jan (parity-tested)
- Six body shapes, outlines/anchors/metrics, fur hash and tile (parity-tested by tests/mochi-shape-parity.ts); Christmas artwork JSON byte-identical on both sides, catalogue sizes and names in i18n (tests/mochi-festive.mjs)
- Festive palette (ginger #B5743A, flake #3FA9F5, edge #5FAEE6, Ato glint #1B2FEB) and light curves (2.2 s bulbs, 1.8 s breath)
- Bot state table (colours, tints, eyes, badges, bounce/scan/breathe/zz/sweat, look, tilt), emote→eye map, triggerEmote/greet/blink/squash/slap/gulp/doRoll tween keys and timings, mini behaviour loop, idle look/breath/blink cadence (2.2+3.2 s, 22 % double blink), ambient particles 1.3 s, particle emission parameters, dance transform 112 BPM, badge drawing, eye shapes other than happy/wink, hand wave geometry
- Character swatches (CharacterPreviewView ↔ preview.ts): idle, update(0.6), pinned pose, festiveStill
- Launch greeting: timings T, 640x150 geometry, easing, seeded LCG particles (seed 7, 5 rings x 170 dots, 16 streaks), halo gold→blue, hands, badge, tint, line at y 132 with fades, greet sound at 1.36 s and blip at 2.72 s, 0.34 s collapse, Christmas music starts with it, skipped when characters are hidden
- Tray/menu basics: Open Notchy greyed when off, Settings…, Turn Notchy off/on, Quit, tooltip 'Notchy' / 'Notchy — off', icon dimmed to 0.4 when off, master switch persisted and applied from the menu without the webview, titles relocalised on language change
- Updater fundamentals: 6-hour schedule, request carries nothing, never installs or restarts without a click, signature verification, 'Check automatically' toggle
- Language: four options (system/en/es/pt-BR) with self-named labels and translated 'Same as system', pt-PT→pt-BR, live switch everywhere including tray and welcome window title
- Quit simply exits; no Dock/taskbar presence; second launch opens the island (or Settings when off)

## Known differences in windows/README.md

- **forced** — No notch: the island lives against a screen edge (bottom right by default), so the welcome says 'I live at the edge of your screen', the tips say 'my spot on the screen' / 'tray icon', and the greeting folds into the Windows compact bar (smallPose uses hard-coded EAR_Y/COMPACT_W instead of IslandRestingLayout) Forced by the hardware. Closest faithful equivalent: keep the platform wording but mirror the Mac sentence structure exactly, and use 'Launch at Windows startup' (and 'Launch at login' on Linux) instead of the generic 'Launch at startup'. Keep the greeting's collapse target derived from the Windows resting bar.
- **closable** — Tray menu (README 'Using it' table: 'Open, Settings…, Turn Coucou off, Quit — plus Update to … when there is one') instead of the Mac menu with a permanent 'Check for Updates…' Rebuild tray.rs in the Mac order with a permanent localised 'Check for Updates…' after Settings… (G7), use a monochrome theme-aware Mochi glyph as the icon (G6), and update the README row (it also still says 'Coucou' where the UI says 'Notchy').
- **closable** — Updates (README 'Updates'): announced only as a tray row and in Settings → Updates, with no Sparkle window; the portable .zip cannot replace itself and opens the releases page The prompt part is closable: add a Sparkle-like updater window (G8). The portable .zip limitation is genuinely forced; its closest equivalent is the same window with 'Open the download page' in place of Install Update.
- **forced** — Linux: Mochi's eyes follow the pointer only while it is over the island (Wayland gives no global cursor) Forced by Wayland. In the welcome window eyes already track within the window on both platforms, which is exactly what the Mac does there (onContinuousHover is window-local).
- **closable** — Now Playing pill hidden on Linux (no MPRIS yet), so the welcome's tools and look screens list one service fewer Closable by implementing MPRIS in media.rs (the BootInfo.media flag then becomes true and the pill reappears); until then forced.

## Parity tests to add

- Welcome layout constants: window 520x660, Mochi diameters 84/56, overhang 34, tile 30, chip 20, chip width 66, slots 4, grid columns 7 — dump from OnboardingView and compare with welcome.ts/onboarding.css values
- Welcome interaction constants: hello delay 0.45 s, dizzy recovery 3.3 s, love wait 1.9 s, love cooldown 6 s, hover restart 40 pt, gaze divisors 260/200, gaze time constant 0.28 s, eye pull 0.3/0.24, lean 3/2.5/0.07
- Per-screen copy keys (title, hint, button word, row labels, tips) as a step→[catalog keys] table on both sides, so a sentence present on one platform only fails the build
- Look-screen rules: lookChoices (who is listed incl. Ato season rule), lookTabs/shownTab, what each tile writes — as input/output tables like welcome-parity
- PillCatalog: ids, names, colours, order, category, and the shipped `character` per pill (Notifications = antenna:pixel) plus the character(for:) fallback rule
- MochiCharacter.resolve with the `resting` flag (all 13 shapes x 6 eyes x resting true/false)
- BOT_STATES table (colour, tint, eye, badge kind/colour, bounces, scans, breathes, zz, sweat, look, tilt, sound) and EMOTE_EYE map
- Tween key lists for greet/blink/squash/gulp/slap/triggerEmote/doMiniBehaviorLoop/setState side effects (target, duration, easing name)
- Eye-shape geometry parameters, especially happy/wink arc centre, radius, start/end angle and direction, and hand ellipse factors (classic rx/ry)
- Greeting: GT timing constants, geometry (GC0, GHB, GASP, GCARD, GCARD_R, GLINE_Y), card colour, mini colours, first N LCG particle values, sound times
- Tray/menu model: item ids, order, separators, labels (catalog keys), enabled rule, off-alpha 0.4, tooltip keys
- AppLanguage.resolved over a list of preferred-language arrays vs TS resolve(navigator.languages)
- Defaults that shape first run: launch-at-startup default, soundEnabled, autoUpdate, activeIntegrations, defaultCharacter

### OB-G33 — The Windows app icon is a different drawing from the Mac's

Found in Phase 1's side-by-side check: the Settings sidebar shows each app's own icon, and the two are not the same picture.

- **Mac:** `NotchBuddy/Assets.xcassets/AppIcon.appiconset/` — a macOS rounded-square tile, peach-to-white, with Mochi's face and pink cheeks at the bottom. It is what the Dock, Finder and the Settings sidebar show.
- **Windows:** `windows/src-tauri/icons/` (icon.ico, 32x32, 128x128, icon.png) — a white Mochi blob with a dark rim on transparency. It is what the taskbar, Start, the installer and the Settings sidebar show.
- **Fix:** the owner decides. One option is to generate the Windows set from the Mac's AppIcon (scripts/gen-icons.mjs), which keeps the tile shape, unusual for a Windows icon. The other is to keep the blob and record it in README.md as an owner-chosen divergence. The tray glyph is separate (OB-G6).
- **Phase:** Phase 8

## Risks

- The Mac's happy/wink arc (addArc 192°→168°, clockwise:true in SwiftUI's flipped space) may not render as the designed ∩; capture it on a real Mac before 'fixing' Windows to match — the right fix may be on the Mac side.
- Porting MochiDress means exposing private engine.ts drawing helpers (shapedPath, drawAccessory, character eyes) and scaling shaped outlines to the greeting's 1.34 aspect; a mistake shows on every launch. Do it behind a check that classic characters draw byte-identically (as the Mac guarantees).
- Changing State.characterFor to honour shipped faces changes the Notifications mini-Mochi for every existing Windows user immediately (they never saw the antenna before).
- Changing the autostart default only affects fresh installs (serde default); existing settings.json files keep autostart=true — decide whether to migrate.
- A new updater window must be created hidden at launch with the same BROWSER_ARGS, or WebView2 brings it up blank (lib.rs notes this failure mode).
- Theme-aware tray glyphs need a registry read plus WM_SETTINGCHANGE handling on Windows and a symbolic icon on Linux appindicator, some builds of which ignore runtime icon changes.
- Several 'native look' targets (segmented control, small switch 44x20 pill knob, large prominent button, progress bar, window corner radius, traffic-light position) differ between macOS 15 and macOS 26; confirm which macOS the reference Mac runs before tuning CSS.
- macOS .accentColor and .secondary follow the user's system accent/appearance; Windows uses fixed values, so a Mac with a non-blue accent will never match exactly.
- The greeting card colour (#141518) is the island-wide --card token on Windows; changing it to #000000 affects every island card and must be coordinated with the island/cards auditor.
