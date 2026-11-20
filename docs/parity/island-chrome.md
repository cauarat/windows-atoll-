# Parity — The island, its ring and pills

The Mac is the source of truth (see `CLAUDE.md`). Each gap names the Mac code, the Windows code and the fix; tick it in the PR that closes it. Audit of 2026-11-20 against `notchy` at f1dee26.

## Checklist

- [ ] **IC-G01** · high · platform forced · S — Default placement is bottom-right instead of top-centre — _kept — Windows keeps bottom-right (owner)_
- [ ] **IC-G02** · high · visual · M — Resting sizes: 184x0 hidden / 288x32 compact vs Mac's no-notch 80x24 tab / 240x24 bar — _Phase 4_
- [ ] **IC-G04** · high · extra on windows · S — Header has two extra tabs (Integrations, Site) and the right-hand group is in a different order — _Phase 4 — Integrations and Site tabs kept (owner); right group reordered_
- [ ] **IC-G34** · high · platform forced · L — ChatGPT and the site are separate windows instead of screens inside the island — _Phase 3_
- [ ] **IC-G03** · medium · behaviour · S — 'Always visible' is on by default; the Mac's is off and the bar folds after 180 s — _kept — Windows keeps its always-visible default with bottom-right (owner)_
- [ ] **IC-G05** · medium · extra on windows · S — Extra 'blip' sound on every header tab, gear, clipboard and ring press — _Phase 4_
- [ ] **IC-G06** · medium · visual · S — Motion: no travel-scaled spring/curve, and view changes that shrink use the close curve — _Phase 4_
- [ ] **IC-G07** · medium · missing on windows · L — Radial menu and two-button chord are missing — _Phase 7_
- [ ] **IC-G08** · medium · missing on windows · M — No AI Agents panel and no 'agents' ring disc — _Phase 5_
- [ ] **IC-G09** · medium · behaviour · S — Default ring arrangement differs on a fresh install — _Phase 4_
- [ ] **IC-G10** · medium · behaviour · S — The ring's timer disc opens the Timer view instead of starting or stopping the timer — _Phase 7_
- [ ] **IC-G12** · medium · visual · S — The site disc draws a globe and says 'Site' instead of the site mark and host name — _Phase 4_
- [ ] **IC-G13** · medium · visual · S — The WhatsApp disc draws an ellipsis — _Phase 4_
- [ ] **IC-G15** · medium · behaviour · M — Escape only closes the island when its window has keyboard focus — _Phase 7_
- [ ] **IC-G17** · medium · behaviour · S — The close shortcut and header X collapse instead of dismissing — _Phase 3_
- [ ] **IC-G18** · medium · behaviour · M — Multi-display: Windows stays on the primary display by default and has no per-display choice — _Phase 4_
- [ ] **IC-G19** · medium · behaviour · S — Hovering open after an approval folded away shows Home, not the waiting approval — _Phase 5_
- [ ] **IC-G20** · medium · behaviour · S — FSM click is ignored from 'hidden', and there is no reopen branch for home-but-not-expanded — _Phase 4_
- [ ] **IC-G22** · medium · behaviour · S — Pick-up and drop feedback differs: no happy emote, no 'approve' on drop, plus a Windows-only glow ring — _Phase 7_
- [ ] **IC-G25** · medium · missing on windows · M — A second click on the Now Playing pill opens nothing — _Phase 7_
- [ ] **IC-G26** · medium · platform forced · M — Claude Code pill target opens VS Code instead of bringing up the running terminal — _Phase 5_
- [ ] **IC-G27** · medium · copy · S — Pill catalog lacks subtitles and icons, and the idle card copy differs — _Phase 5_
- [ ] **IC-G11** · low · behaviour · S — The ring's settings disc does not open Settings on the Island section — _Phase 1_
- [ ] **IC-G14** · low · visual · S — Ring discs vanish instantly on close and use a different enter curve — _Phase 4_
- [ ] **IC-G16** · low · missing on windows · S — No 'Show island with shortcut' — _Phase 2_
- [ ] **IC-G21** · low · behaviour · S — FSM hooks missing: hiddenExternally, holdsHomeOpen re-arm, held-open guard on the fold — _Phase 7_
- [ ] **IC-G23** · low · extra on windows · S — Dizzy plays an extra 'dizzy' sound and opens with an auto-close hold — _Phase 7_
- [ ] **IC-G24** · low · behaviour · S — Music starting reveals the island with a peek sound; the Mac is silent — _Phase 7_
- [ ] **IC-G28** · low · missing on windows · S — The Notifications pill does not wear its own character (antenna + pixel eyes) — _Phase 8_
- [ ] **IC-G29** · low · behaviour · S — Hover and click-through margins are wider than the Mac's — _Phase 7_
- [ ] **IC-G30** · low · visual · S — Compact-bar details: mini-grid metrics, timer badge position and colour, and missing fades — _Phase 4_
- [ ] **IC-G31** · low · visual · S — View-switch and header-hide transitions differ slightly — _Phase 4_
- [ ] **IC-G32** · low · visual · S — Hydration and sip card geometry differs from the Mac table — _Phase 4_
- [ ] **IC-G33** · low · missing on windows · L — Dragging Mochi onto a window to attach it as context is missing — _Phase 6_
- [ ] **IC-G35** · low · behaviour · S — Saved ring buttons with dead ids are not pruned — _Phase 4_
- [ ] **IC-G36** · low · platform forced · S — Window level and Spaces behaviour — _not done — the window level is already the closest Windows allows_
- [ ] **IC-G37** · low · behaviour · S — Sound engine: unlimited overlap and suspend-on-idle vs a pool of 3 — _Phase 7_
- [ ] **IC-G38** · low · extra on windows · S — Bottom-edge wake dwell (220 ms) and the invisible wake strip are Windows-only — _Phase 4_

## How each side is built

MAC (source of truth)
AppDelegate.setupIsland creates one IslandWindowController on the display under the cursor, chosen from the displays the user selected (an empty selection means all of them). refreshIslands moves it whenever the screen setup changes or the cursor moves to another allowed display.

IslandWindowController owns a borderless, non-activating NSPanel (IslandPanel). It is 1200x820, sits at level mainMenu+3, joins all Spaces including full-screen ones, and starts click-through. Its contentView holds an NSHostingView(IslandRootView) with a FileDropNSView on top of it. The controller also runs:
- A 60 Hz pollFrame for hover and stay rects (6/20 pt), click-through, following the cursor across displays and hovering over Mochi.
- NSEvent monitors: a global and a local Escape, ⌘V paste, mouse down/drag/up for click-to-open, hold-to-move (2 s), slap and drag-to-window attach, and a global "show island" hotkey.
- NotificationCenter wiring: hookExpand→notify, hookReveal, a silent musicReveal, inbox (sound "question"), agenda, hydration, timer, islandDismiss/closeHotKeyPressed→dismiss, and islandPositionChanged.
- IslandStateMachine (hidden/petit/home/coucou), which drives setMode/expand.
- IslandAnchor (six presets plus free drop, default top-centre), with IslandScreenGeometry measured per display: the notch when there is one, otherwise 80x24 and 240x24 compact.

View tree: IslandRootView is a ZStack(top) of Color.clear, IslandEdgeRingView(islandBounds) and IslandContainer(islandBounds). Both share one animated size.

IslandContainer is a ZStack(topLeading), back to front:
- IslandShape: black, square top, bottom radius 14 (resting) or 22 (open).
- Snow.
- Exactly one of three bodies:
  - GreetingCanvas.
  - UploadCanvas with the header.
  - IslandContentView: header 34 pt, padding 8/10/10, then a ZStack of every IslandViewContent with a 0.16 s cross-fade.
- Snowfall.
- BotPlacement: glow plus BotCanvasView.
- NotchSiteView, only for .web.
- CountdownBar.
- Compact group: CompactTimerBadge, or CompactHydrationCue, or CompactMiniGrid.

Motion lives in IslandMotion: an open spring of 0.34/0.78, a close curve of (.45,0,.2,1) over 0.22 s, and grow/shrink variants scaled by distance travelled.

Separate windows: AgentsPanelController (420x480 floating panel), RadialMenuController (268x268, opened by RadialChordTap, a CGEventTap feeding RadialChordMachine), ClipboardPanel, CloseHotKey (Carbon RegisterEventHotKey) and SoundEngine (a pool of 3 AVAudioPlayers per sound).

Header: left Home / Chat / Clipboard; right Agenda? / Hydration / Timer; then gear, speaker and X (dismiss).

WINDOWS (Tauri 2)
Rust island.rs owns one transparent, always-on-top, non-focusable webview window called "island". It has three sizes, picked by Fold:
- Panel 760x700.
- Strip 240x6 (invisible).
- Bar 288x32.
apply_geometry places the window on target_monitor ("primary" by default, or "cursor") using parse_placement, preset_origin (with a 2 px BOTTOM_GAP) or free_geometry. Default position is bottom-right.

A poll thread runs in three modes: Parked, Resting (500 ms) and Live (16 ms). It emits "cursor", toggles WS_EX_TRANSPARENT against the rect the page pushes (HIT_MARGIN 14), carries drags (begin_drag/drag_to/finish_drag), watches for screen changes, re-asserts HWND_TOPMOST and follows the virtual desktop (platform/windows.rs). shortcut.rs registers the close shortcut and emits "close-shortcut".

TS main.ts boots the Island and wires the cursor, tray, close-shortcut, screen-changed and settings-changed events.

island/island.ts merges IslandWindowController and IslandRootView into one class. DOM tree:
- #root
  - #wake-strip
  - #edge-ring (sibling of the island)
  - #island
    - #grab-glow (Windows-only)
    - #island-clip: snow, greeting canvas, upload layer, #content (#header, #views), snowfall
    - #bot-glow
    - #bot-canvas
    - #mini-grid
    - #compact-timer
    - compact sip
    - #countdown

Logic files mostly have one-to-one counterparts:
- island/fsm.ts ↔ IslandStateMachine. Port, with forceHome/forcePetit/forceHidden instead of openedExternally/collapse/hiddenExternally, and pinned/heldOpen flags instead of closures.
- core/anchor.ts ↔ IslandAnchor (parity-tested).
- core/layout.ts ↔ IslandTypes.viewLayouts + islandSize + botPosition.
- core/anim.ts ↔ IslandMotion. Spring and Tracked, without the travel variants.
- core/fold.ts: Windows-only window sizing.
- core/edgeRing.ts ↔ IslandEdgeLayout + IslandEdgeAction. It adds side mirroring for corners and a different default deal, and has no "agents" action.
- core/pillOpen.ts ↔ PillOpen.
- core/state.ts INTEGRATION_AGENTS ↔ PillCatalog. Ids, names and colours only: no subtitle, icon, category or character.
- core/sound.ts ↔ SoundEngine (WebAudio).
- views/views.ts buildHeader ↔ IslandHeader. It has 2 extra tabs (Integrations, Site) and a different right-hand order.

No Windows counterpart at all for:
- RadialAction, RadialChord, RadialChordTap, RadialGeometry, RadialMenu
- AgentsPanel and AgentsPanelView
- IslandDisplays (per-display selection)
- the IslandScreenGeometry no-notch sizes and height overrides
- the show-island hotkey
- drag-Mochi-onto-a-window
- the NotchSiteGlyph ring mark

## Gaps

### IC-G01 — Default placement is bottom-right instead of top-centre

- **Mac:** `NotchBuddy/Sources/App/IslandAnchor.swift:35-40 (defaultPosition = "top-centre"); IslandWindowController.swift:229-246 (top uses screen.frame, island hangs from the very top edge)` — The island hangs from the top-centre of the display, against the bezel. Top corners are square and the bottom corners are rounded. It grows downward, and ring discs hang left, right and below.
- **Windows:** `windows/src/core/anchor.ts:21-22 (DEFAULT_POSITION = "bottom-right"); windows/src-tauri/src/settings.rs:295-297 (default_position), 369; windows/src-tauri/src/island.rs:111-124 (parse_position fallback bottom/right)` — The island sits bottom-right above the taskbar, next to the clock. It grows upward, the ring's 'bottom' row flips above the island, and columns are mirrored inward (edgeRing.ts effectiveSide).
- **Fix:** Make top-centre the default on Windows: DEFAULT_POSITION = "top-centre" in anchor.ts and default_position() -> "top-centre" in settings.rs. Keep parse_position's fallback as-is: the Mac's own edge(of:) also falls back to bottom/right on garbage. Edge::Top already uses the whole display (placement_area), so the island presses against the top bezel over a top taskbar, the way the Mac's covers the menu bar. Square-top/rounded-bottom (radiusCss), ring-below and immediate hover at the top edge are already implemented, so at top-centre the island, ring and motion line up with the Mac's. Decide whether existing installs (settings.json already stores "bottom-right") are migrated once, or keep their stored value. Update README and the Rust resting_bar tests, which assume bottom-right.
- **Phase:** kept — Windows keeps bottom-right (owner)

### IC-G02 — Resting sizes: 184x0 hidden / 288x32 compact vs Mac's no-notch 80x24 tab / 240x24 bar

- **Mac:** `NotchBuddy/Sources/App/IslandScreenGeometry.swift:8-10,41-46 (no notch: 80x24, width scales with height), 51-61 (IslandRestingLayout: botDiameter=min(max(20,h-18),max(0,h-6)), miniGridScale=min(1,(h-4)/28), miniGrid x=w-40); IslandWindowController.swift:1902-1903 (hidden=(nw,nh), compact=(nw+160,nh)); IslandRootView.swift:500-503 (hidden on no-notch: Mochi at (w/2,h/2), opacity 1); design/captures/no_notch_hidden.png, no_notch_compact.png` — A PC has no notch, so the Mac geometry it has to match is the Mac's own on a notchless display. Hidden is a visible 80x24 black tab hanging from the top, with an 18 pt Mochi centred in it (opacity 1). Compact is 240x24: Mochi at x 40, y 12, diameter 18, and the mini grid at x w-40 scaled 0.714. With the 'Non-notch display height' override (22-60, custom default 32) the width scales by h/24.
- **Windows:** `windows/src/core/layout.ts:79-90 (NOTCH_W 184, NOTCH_H 32, COMPACT_W 288, WAKE_STRIP 240x6), 251-257 (hidden h=0), 294-297 (hidden opacity 0, compact d=20 fixed); windows/src/core/anchor.ts:94 (METRICS 288x32); windows/src-tauri/src/island.rs:26-27,131-132 (STRIP 240x6, REST 288x32)` — Hidden retracts to zero height and leaves an invisible 240x6 wake strip. Compact is a fixed 288x32 with Mochi d20 at (40,16) and an unscaled grid. No height preference.
- **Fix:** In layout.ts: - Port IslandScreenGeometry's no-notch branch: NOTCH_W=80, NOTCH_H=24, COMPACT_W=NOTCH_W+160. - Make islandSize('hidden') return {w: NOTCH_W, h: NOTCH_H} instead of h 0. - Make botPosition hidden return {cx: w/2, cy: h/2, d: restDiameter(h), opacity: 1} and compact {cx: 40, cy: h/2, d: restDiameter(h)}.  Elsewhere: - Scale #mini-grid by min(1,(h-4)/28). - Update METRICS (anchor.ts), REST_W/REST_H (island.rs) and the anchor parity table. - The hidden window becomes a small visible tab (a Fold::Bar of 80x24) instead of the invisible strip. - greeting.ts picks up the new numbers through COMPACT_W/NOTCH_H. - Optionally add plainDisplayHeight (22-60), with width = 80*h/24.
- **Phase:** Phase 4

### IC-G03 — 'Always visible' is on by default; the Mac's is off and the bar folds after 180 s

- **Mac:** `NotchBuddy/Sources/App/AppState.swift:553-572 (absenceInterval 180, alwaysVisible false); SettingsView.swift:332-353 ('Always visible' toggle; 'Hide after … s without movement' disabled while it is on); IslandStateMachine.swift:76-87,284-297` — After 3 min of quiet the compact bar folds to hidden. On a notchless Mac that is still a visible 80x24 tab with Mochi, so the island never vanishes; it just gets smaller.
- **Windows:** `windows/src/core/state.ts:376-378 (absenceInterval 180, standby false, alwaysVisible true); windows/src-tauri/src/settings.rs:243-245` — The bar never folds by default. Turned off, it folds into an invisible wake strip and Mochi is gone from the screen. A Standby mode also exists.
- **Fix:** Once G02 makes hidden a visible tab, default alwaysVisible to false in both state.ts and settings.rs, as on the Mac. The fold then reads exactly like a notchless Mac. Standby can stay as a Windows-only extra or be removed (the Mac has none).
- **Phase:** kept — Windows keeps its always-visible default with bottom-right (owner)

### IC-G04 — Header has two extra tabs (Integrations, Site) and the right-hand group is in a different order

- **Mac:** `NotchBuddy/Sources/App/IslandRootView.swift:713-750 (left: Home, Chat, Clipboard; right: Agenda (if on), Hydration, Timer); IslandTypes.swift:11-45 (no .integrations view exists)` — 3 tabs on the left, then Agenda/Hydration/Timer on the right. The site is reached only from its ring disc.
- **Windows:** `windows/src/views/views.ts:136-141,186-187 (left: Home, Chat, Clipboard, Integrations, Site; right: Agenda, Timer, Water); views.ts:707 (integrations view); windows/src/core/layout.ts:115` — 5 tabs on the left, including a pills-grid 'Integrations' view and a globe 'Site' button. On the right, Timer comes before Water.
- **Fix:** Drop tabPills and tabSite from the left group (views.ts:186), and reorder the right group to tabAgenda, tabWater, tabTimer. Remove the 'integrations' view from VIEW_LAYOUTS and buildViews. Keep the site reachable from the ring's 'site' disc, as on the Mac.
- **Phase:** Phase 4 — Integrations and Site tabs kept (owner); right group reordered

### IC-G05 — Extra 'blip' sound on every header tab, gear, clipboard and ring press

- **Mac:** `NotchBuddy/Sources/App/IslandRootView.swift:793-865 (TabButton/ClipboardTabButton: no sound), 759-766 (gear: no sound); IslandEdgeAction.swift:61-75 (built-ins play nothing); PillActions.swift:68 (only openPill plays blip)` — Tabs, gear and clipboard are silent. Ring built-ins (clipboard, timer, settings, site) are silent. Only a pill disc plays 'blip', through openPill.
- **Windows:** `windows/src/views/views.ts:114-115,160,165,174-177 (actions.blip() in go(), openPage, clipboard, gear); windows/src/island/island.ts:1103-1104 (pressRingButton blips for every action)` — Every tab click, the gear, the clipboard tab, the Site/ChatGPT page toggles and every ring disc play 'blip'.
- **Fix:** Remove actions.blip() from go(), openPage, tabClip and gearBtn. In pressRingButton, play 'blip' only on the default (pill) branch.
- **Phase:** Phase 4

### IC-G06 — Motion: no travel-scaled spring/curve, and view changes that shrink use the close curve

- **Mac:** `NotchBuddy/Sources/App/IslandMotion.swift:35-61 (fullTravel 400; grow: response 0.34+0.16t, damping min(0.96,0.78+0.18t); shrink: 0.22+0.16t s); IslandRootView.swift:234-236 (mode shrink uses shrink(travel:)), 278 (every view change uses grow(travel:) whichever direction)` — Closing from a big card or screen takes longer in proportion to the distance; a 640x240→240x24 fold is about 0.34 s. Switching views always uses a spring whose overshoot shrinks as the distance grows, including when the island gets shorter.
- **Windows:** `windows/src/core/anim.ts:24 (stale '340 ms' comment), 91-95 (fixed constants); windows/src/island/island.ts:886-899 (animateGeometry fixed), 630-633 (setView shrinking → close curve)` — Every open uses the 0.34/0.78 spring and every close the 0.22 s curve, whatever the distance. A view change that makes the island shorter uses the 0.22 s close curve instead of the spring.
- **Fix:** Port grow(travel) and shrink(travel) into anim.ts with FULL_TRAVEL=400. In animateGeometry, take a flag for 'mode change' vs 'view change': - Mode shrink: curveTowards(target, (0.22+0.16*t)*1000). - Mode grow: the plain open spring. - View change: springTo with grow(travel) in both directions. Travel is max(|Δw|,|Δh|). Fix the stale comment.
- **Phase:** Phase 4

### IC-G07 — Radial menu and two-button chord are missing

- **Mac:** `NotchBuddy/Sources/App/RadialAction.swift:9-99; RadialChord.swift:45-155 (window 60 ms, slop 6 pt; only the right-down is delayed); RadialChordTap.swift:58-222; RadialGeometry.swift:12-62 (outer 110, inner 34, shadowPad 24, 2-8 wedges, wedge 0 straight up, clockwise, centre clamped inset 122); RadialMenu.swift:25-156 (52 pt discs #15171B/#2A2D33 hovered, stroke white 8%/#3B9EFF 80%, icon 17 pt medium #B0B5BE/#F5F6F8/#5A5F68 unavailable, scale 1.12 spring 0.2/0.7, shadow black 50% r6 y2, dead zone 51 pt #0E0F11 92% with 9 pt #8E939C title; 'peek' on open, 'blip' on commit, Escape closes); AppState.swift:85-89 (off by default)` — An opt-in setting. Pressing left and right together (within 60 ms and 6 pt) opens a wheel of 6 default wedges at the pointer: Open Notchy, Clipboard, Play/Pause, Next, Focus timer, Settings. Flicking and releasing runs the wedge; releasing in the dead zone keeps the wheel up for clicking.
- **Windows:** `none` — No equivalent.
- **Fix:** Port RadialChordMachine to Rust, and reuse tests/RadialChordTests.swift's cases as Rust tests. Run a WH_MOUSE_LL hook on its own thread with a message loop: - Swallow the right-down for 60 ms; re-post it with SendInput if no left press follows, and tag re-posted events through dwExtraInfo. - Synthesize a left-up when the chord was left-first. - Reset whenever GetAsyncKeyState disagrees with the machine. Show a 268x268 transparent topmost tool window centred on the clamped pointer and draw the wheel in TS with the exact values above. Poll the cursor and buttons at 60 Hz while it is open, and handle Escape through the same LL keyboard hook as G15. Off by default, like the Mac; not possible on Wayland.
- **Phase:** Phase 7

### IC-G08 — No AI Agents panel and no 'agents' ring disc

- **Mac:** `NotchBuddy/Sources/App/IslandEdgeAction.swift:11,17,27,37,48-55,63-66 (agents: 'AI Agents', sparkles, #E07950, toggles the panel); AgentsPanel.swift:86-131 (420x480 floating panel, centred, top = screen.maxY-320-10-h, refresh every 2 s while open, Escape closes); AgentsPanelView.swift:11-150 (bg #0B0C0E, radius 16, stroke white 8%; header sparkles #E07950 + 'AI Agents' 13 semibold + xmark; cards 'Account' and 'Running here', radius 14, title 9 pt semibold uppercase #6E737C); AppState.swift:80 (showAgentsPanel, default off)` — The ring can hold a sparkles disc that opens a floating panel: the Claude Code account from ~/.claude.json, and the live sessions from ~/.claude/sessions/*.json, each with name, cwd and status (#F5A524 working, #34D399 otherwise).
- **Windows:** `windows/src/core/edgeRing.ts:190-195 (no 'agents' entry); dead code: windows/src/style.css:2565+ (.ag-* dashboard), windows/src/core/bridge.ts:296-302, windows/src-tauri/src/lib.rs:975, island.rs:18-22 (comment about a dashboard that no longer exists)` — Nothing. An old dashboard was removed and left orphan CSS and comments behind.
- **Fix:** Add {id:'agents', title:'AI Agents', color:'#E07950'} to EDGE_ACTIONS and RING_MARKS (ICONS.sparkles exists), and a showAgentsPanel setting. Add a Rust command that reads %USERPROFILE%\.claude.json and %USERPROFILE%\.claude\sessions\*.json (never the .key files), and a 420x480 borderless window with the exact styling above. Delete the dead .ag-* CSS and the stale comments.
- **Phase:** Phase 5

### IC-G09 — Default ring arrangement differs on a fresh install

- **Mac:** `NotchBuddy/Sources/App/IslandEdgeLayout.swift:119-125 (alternating left/right in catalog order, nothing underneath); AppState.swift:675-678,713-719` — With the default active pills, the left column is Now Playing then Ato, the right column is Mattermost then Notifications, and nothing sits below.
- **Windows:** `windows/src/core/edgeRing.ts:151-175 (every pill on the left, Now Playing in the bottom row)` — The left column is Mattermost, Ato, Notifications, and Now Playing sits alone in the bottom row.
- **Fix:** Make defaults() return pills.map((action, i) => ({action, side: i % 2 === 0 ? 'left' : 'right'})). effectiveSide stays for corner placements; at top-centre it changes nothing, so the layout is the Mac's exactly. Update the README bullet.
- **Phase:** Phase 4

### IC-G10 — The ring's timer disc opens the Timer view instead of starting or stopping the timer

- **Mac:** `NotchBuddy/Sources/App/IslandEdgeAction.swift:68-69 (FocusTimer.isActive ? stop() : startFromPicker())` — One click starts a focus session from the picker's preset, or stops a running one. The view does not change.
- **Windows:** `windows/src/island/island.ts:1109-1111 (setView('timer'))` — Switches the island to the Timer tab.
- **Fix:** In pressRingButton, use case 'timer': FocusTimer.isActive ? FocusTimer.stop() : FocusTimer.startFromPicker(). Both exist in core/timer.ts:109,161.
- **Phase:** Phase 7

### IC-G11 — The ring's settings disc does not open Settings on the Island section

- **Mac:** `NotchBuddy/Sources/App/IslandEdgeAction.swift:70-71 (openFullSettings with object "island"); RadialAction.swift:79-80` — Opens Settings with the Island section selected.
- **Windows:** `windows/src/island/island.ts:1112-1114; windows/src/core/bridge.ts:186 (openSettingsWindow takes no section)` — Opens Settings on whatever page it last showed, or the default.
- **Fix:** Add an optional section to open_settings_window and emit it to the settings window, which selects the matching nav item ('island'). Call it with 'island' from the ring, and with 'integrations' from the idle pill card's Settings… link (as IslandViewContent.swift:1643 does).
- **Phase:** Phase 1

### IC-G12 — The site disc draws a globe and says 'Site' instead of the site mark and host name

- **Mac:** `NotchBuddy/Sources/App/IslandEdgeRingView.swift:100-111 (NotchSiteGlyph at side 34 on a 22 pt #0E0F11 circle); NotchSite.swift:88-111 (dot r=0.059s, rings r=0.126s/0.221s, strokes 0.047s/0.050s with round caps, arcs 174→466° and 227→452°); IslandEdgeAction.swift:21 (title = NotchSite.hostLabel)` — A dot with two rings cut open towards the upper left, in #38BDF8. The tooltip is the URL's host.
- **Windows:** `windows/src/island/island.ts:70 (site: ICONS.globe), 1083 (label t('Site')); windows/src/core/edgeRing.ts:194` — A generic globe; the tooltip says 'Site'.
- **Fix:** Add siteMark(side, ink) to views/logos.ts, an SVG port of NotchSiteGlyph with the same ratios and angles (y is subtracted). Draw it at 34 with a 22 px #0E0F11 circle behind it. Set the title to new URL(State.settings.siteUrl).host.
- **Phase:** Phase 4

### IC-G13 — The WhatsApp disc draws an ellipsis

- **Mac:** `NotchBuddy/Sources/App/PillCatalog.swift:96-97 (icon 'phone.bubble.fill', colour #25D366); IslandEdgeRingView.swift:112-124 (13 pt medium symbol over a 22 pt #0E0F11 circle, initial underneath)` — A green phone-in-bubble symbol.
- **Windows:** `windows/src/island/island.ts:63-71 (RING_MARKS has no integration_whatsapp), 1087-1090 (falls back to ICONS.ellipsis)` — A green '…'.
- **Fix:** Add a phone.bubble.fill-like path to icons.ts and map integration_whatsapp to it in RING_MARKS. Better: move icon ids into the pill catalog (G27) so a new pill cannot fall through again.
- **Phase:** Phase 4

### IC-G14 — Ring discs vanish instantly on close and use a different enter curve

- **Mac:** `NotchBuddy/Sources/App/IslandEdgeRingView.swift:28 (.transition(.scale(0.3)+opacity)), 36 (animation IslandMotion.forGrowing: open spring 0.34/0.78 in, close curve 0.22 s out), 69-71 (hover spring 0.2/0.7)` — Discs scale up from 0.3 and fade in on the open spring with no delay. On close they shrink to 0.3 and fade on the 0.22 s close curve, in step with the island edge.
- **Windows:** `windows/src/island/island.ts:1045-1063 (clear(ringEl) the moment the ring becomes empty); windows/src/style.css:2858-2872 (enter: opacity 0.18 s ease-out + transform 0.26 s overshoot bezier, both delayed 0.06 s; no exit)` — They appear 60 ms late on a CSS curve and are removed from the DOM in one frame when the island closes.
- **Fix:** On close, remove .on and delete the elements after 220 ms; use transition: transform 0.22s cubic-bezier(.45,0,.2,1), opacity 0.22s for the exit. For the enter, drop the 0.06 s delay and approximate the 0.34/0.78 spring (or drive scale and opacity from a Tracked spring in the frame loop).
- **Phase:** Phase 4

### IC-G15 — Escape only closes the island when its window has keyboard focus

- **Mac:** `NotchBuddy/Sources/App/IslandWindowController.swift:1116-1127 (global keyDown: Escape → closeScreen if a screen is up, else collapse() if expanded and not pinned), 1131-1140 (local twin)` — Pressing Escape in any app closes an open island, unless it is pinned or held open mid-reply. The key still reaches the other app.
- **Windows:** `windows/src/island/island.ts:1556-1559 (window keydown); windows/src-tauri/tauri.conf.json:32 (focusable false)` — The island window is non-focusable, so Escape does nothing unless the user is typing in a reply or chat field inside it.
- **Fix:** Install a WH_KEYBOARD_LL hook in Rust only while the poll is in Watch::Live (island expanded). It must never consume: always CallNextHookEx. On VK_ESCAPE key-down, emit 'escape' to the island, which runs the Mac's rule: close the page if one is up, otherwise collapse() if !State.isPinned. Unhook when collapsed. Do not use a global-shortcut registration: that would swallow Escape from other apps.
- **Phase:** Phase 7

### IC-G16 — No 'Show island with shortcut'

- **Mac:** `NotchBuddy/Sources/App/AppState.swift:580-588 (off, ⌘⇧N); IslandWindowController.swift:1412-1421 (expand(to: .overview) when hidden or compact); SettingsView.swift:402-414` — An optional shortcut opens the island on Home, with no notification hold.
- **Windows:** `windows/src-tauri/src/shortcut.rs:39-56 (registers only the close shortcut)` — Only the close shortcut exists.
- **Fix:** Add openShortcutEnabled (false) and openShortcut ('Ctrl+Shift+N') to Settings. Register it beside the close shortcut in shortcut.rs and emit 'open-shortcut'. In main.ts: if mode !== 'expanded', island.expand('overview') (not alert(), which arms a hold).
- **Phase:** Phase 2

### IC-G17 — The close shortcut and header X collapse instead of dismissing

- **Mac:** `NotchBuddy/Sources/App/IslandWindowController.swift:1079-1093 (dismiss: refuse while the file picker is open; close a screen; cancel the voice recording; clear staged reply attachments; isReplying=false; isPinned=false; drop first responder; collapse), 1234-1238 (X and close hotkey → dismiss)` — The X or the shortcut closes the island now and throws away a half-staged reply: files and recording go, and an open ChatGPT or site screen closes first.
- **Windows:** `windows/src/main.ts:53-55 (close-shortcut → collapse()); windows/src/views/views.ts:171 (X → actions.collapse()); windows/src/island/island.ts:637-647` — Folds the island and leaves staged attachments and any recording in place. It does not refuse while the file picker is open.
- **Fix:** Add Island.dismiss(), ported from Mac dismiss(): return if not expanded or State.pickingFile; hide pages; stop the recording; ReplyAttachments.clear(); setPinned(false); focusWindow(false); collapse(). Route the X and 'close-shortcut' to it.
- **Phase:** Phase 3

### IC-G18 — Multi-display: Windows stays on the primary display by default and has no per-display choice

- **Mac:** `NotchBuddy/Sources/App/IslandDisplays.swift:78-112 (empty selection = all; a selection matching nothing = all; active = the display under the cursor, else the first); IslandWindowController.swift:799,865-875 (follows the cursor across chosen displays only while not expanded; re-measures notch geometry per display); AppDelegate.swift:251-263; SettingsView.swift:357-365 (Displays checklist)` — By default the island follows the cursor to whichever display it is on, whenever the island is not open. Users can tick which displays are allowed.
- **Windows:** `windows/src/core/state.ts:382 (screen 'primary'); windows/src-tauri/src/settings.rs:368; windows/src-tauri/src/island.rs:499-512 (target_monitor primary|cursor), 1101-1119 (screen key re-checked every 500 ms, including while open)` — The default pins it to the main display. 'Display under the cursor' follows within 0.5 s, even while a card is open, and there is no subset selection.
- **Fix:** Default screen to 'cursor'. In the watch tick, skip a cursor-driven monitor change while !gate.collapsed (open), unless the monitor disappeared. Optionally replace primary|cursor with a list of monitor ids that follows IslandDisplays.chosen (empty = all, nothing matching = all).
- **Phase:** Phase 4

### IC-G19 — Hovering open after an approval folded away shows Home, not the waiting approval

- **Mac:** `NotchBuddy/Sources/App/IslandWindowController.swift:1634-1640 (defaultView: pendingApproval → .approval, then sip, then empty/overview), 564-577 (the home transition lands on defaultView)` — While a Claude Code permission request is still pending, any reopen (hover, click) lands on the approval card.
- **Windows:** `windows/src/island/island.ts:546-548 (restingView: sip or State.defaultView()); windows/src/core/state.ts:879-881 (defaultView: empty/overview only)` — Reopening lands on Home, and the pending request is only reachable from its badge.
- **Fix:** State.defaultView(): if pendingApproval → 'approval'; else if Hydration.enabled && awaiting → 'sip'; else tasks empty ? 'empty' : 'overview'. restingView can then just call it.
- **Phase:** Phase 5

### IC-G20 — FSM click is ignored from 'hidden', and there is no reopen branch for home-but-not-expanded

- **Mac:** `NotchBuddy/Sources/App/IslandStateMachine.swift:207-212 (click accepts .petit or .hidden); IslandWindowController.swift:1390-1397 (mouse-up: fsm home but mode not expanded → expand(defaultView), else fsm.click())` — Clicking the resting shape always opens it, including when the machine thinks it is hidden: after an alert, or the visible no-notch hidden tab.
- **Windows:** `windows/src/island/fsm.ts:183-188 (petit only); windows/src/island/island.ts:1452-1454` — A click on a free-placed bar while the FSM is hidden (drawModeFor draws it as compact) does nothing. With G02's visible hidden tab, clicking it would do nothing.
- **Fix:** In fsm.ts click(): if (this.state !== 'petit' && this.state !== 'hidden') return. In releaseGrab, if fsm.state === 'home' && State.mode !== 'expanded', call expand(defaultView()); otherwise fsm.click().
- **Phase:** Phase 4

### IC-G21 — FSM hooks missing: hiddenExternally, holdsHomeOpen re-arm, held-open guard on the fold

- **Mac:** `NotchBuddy/Sources/App/IslandStateMachine.swift:217-222 (hiddenExternally), 292 (petit hide skipped while isHeldOpen), 315 (holdsHomeOpen re-arms the leave collapse every 1.0 s); IslandWindowController.swift:620-637, 932-935 (isPinned kept through a fold while held open), 786` — A chat with something typed holds the island against pointer-leave only, re-checking every second, while Escape and the tabs still close it. The compact bar never folds while a reply is held. AppState hiding the island keeps the FSM in step.
- **Windows:** `windows/src/island/fsm.ts:243-273 (no held-open check in schedulePetitHide; pinned/heldOpen block the leave collapse outright); windows/src/island/island.ts:558-561 (always clears isPinned)` — Uses two flags (pinned blocks leave-collapse; heldOpen blocks the hold). The fold timer ignores held-open, and there is no external-hide sync.
- **Fix:** Add holdsHomeOpen?: () => boolean with a 1 s re-arm in scheduleHomeCollapse, an isHeldOpen check in the petitHide callback, and hiddenExternally(). Make the FSM's timer scheduler injectable (like Swift's `schedule`) so both machines can be trace-tested.
- **Phase:** Phase 7

### IC-G22 — Pick-up and drop feedback differs: no happy emote, no 'approve' on drop, plus a Windows-only glow ring

- **Mac:** `NotchBuddy/Sources/App/IslandWindowController.swift:282-295 (lift: 'peek' + triggerEmote happy, no visual ring), 304-320 (drop: store position, move, play 'approve')` — Holding for 2 s shows nothing until the island lifts. On lift: peek sound and Mochi's happy face. On drop: the approve chime.
- **Windows:** `windows/src/island/island.ts:1349-1361 (grabGlow 'filling'), 1386-1412 (lift: 'peek' only), 1443-1450 (drop: no sound); windows/src/style.css:88-108 (#grab-glow: 18px/5px white glow growing over 2 s, then a lifted shadow plus a 1.5px white ring); windows/src-tauri/src/island.rs:952-1010 (finish_drag silent)` — A white glow grows around the bar during the hold, and a white outline and shadow appear while carried. Peek on lift with no emote. A silent drop.
- **Fix:** Add this.engine.triggerEmote('happy') in liftOff and Sound.play('approve') in releaseGrab's dragging branch. Remove the .filling/.lifted styles (or keep them as an explicitly accepted extra).
- **Phase:** Phase 7

### IC-G23 — Dizzy plays an extra 'dizzy' sound and opens with an auto-close hold

- **Mac:** `NotchBuddy/Sources/App/IslandWindowController.swift:1670-1686 (handleDizzy: expand(to: .confused), no sound, no hold); BotEngine.swift:409-432 (slap: 'slap' plus 'annoyed' after 60 ms; state sounds are never played)` — The third slap is silent apart from the slap itself, and the confused card has no countdown.
- **Windows:** `windows/src/island/island.ts:1690-1707 (Sound.play('dizzy'); alert('confused'), which arms the notification hold and the countdown hairline)` — Plays 'dizzy' as well, and draws the auto-close hairline over the confused card.
- **Fix:** Remove Sound.play('dizzy') and use this.expand('confused') instead of alert().
- **Phase:** Phase 7

### IC-G24 — Music starting reveals the island with a peek sound; the Mac is silent

- **Mac:** `NotchBuddy/Sources/App/IslandWindowController.swift:1182-1187 (musicReveal sets silentNextReveal), 534-540` — Playback starting brings the compact bar up without sound.
- **Windows:** `windows/src/island/media.ts:53 (island.reveal()); windows/src/island/island.ts:440 (petit from hidden always plays 'peek')` — The bar comes up with 'peek'.
- **Fix:** Add reveal({silent:true}) that sets a silentNextReveal flag checked in the petit arm. Use it from media.ts.
- **Phase:** Phase 7

### IC-G25 — A second click on the Now Playing pill opens nothing

- **Mac:** `NotchBuddy/Sources/App/PillActions.swift:98-102, 183-189 (openPillTarget music → MusicController.openNowPlayingTab: the tab or app that is playing)` — The first click shows the player on Home; the second brings up the app or browser tab that is playing.
- **Windows:** `windows/src/island/island.ts:1024-1031 (only Claude and the message sources are handled)` — The second click does nothing.
- **Fix:** Add a Rust command that activates the GSMTC session's source app. State.media.sourceId is its AppUserModelID: use IApplicationActivationManager::ActivateApplication for packaged apps, or find a top-level window of the source process and SetForegroundWindow. Call it from openPillTarget for integration_music.
- **Phase:** Phase 7

### IC-G26 — Claude Code pill target opens VS Code instead of bringing up the running terminal

- **Mac:** `NotchBuddy/Sources/App/PillActions.swift:171-182 (activate the first running Terminal, iTerm2, kitty or Ghostty)` — The second click on the Claude Code pill (or ↗) raises the terminal where Claude Code is running.
- **Windows:** `windows/src/island/island.ts:1025-1027 (Bridge.openInVSCode(cwd)); windows/src/views/integrations.ts:89-97` — Launches VS Code on the session's folder.
- **Fix:** Closest equivalent: EnumWindows for CASCADIA_HOSTING_WINDOW_CLASS (Windows Terminal), ConsoleWindowClass, mintty, Alacritty and WezTerm. Prefer the window whose process tree owns the session (the hook payload carries the cwd). Then AllowSetForegroundWindow and SetForegroundWindow. Fall back to VS Code only when no terminal is running.
- **Phase:** Phase 5

### IC-G27 — Pill catalog lacks subtitles and icons, and the idle card copy differs

- **Mac:** `NotchBuddy/Sources/App/PillCatalog.swift:19-66, 82-106 (subtitle 'Integration' or 'Messages'; icon; category; sessionSubtitle 'Claude Code'); IslandViewContent.swift:1500-1515 (message sources: 'Not signed in' / 'N waiting' / 'Connected'; others: 'Connected' / 'Not connected'), 1562-1571 (header = catalog name + subtitle)` — Claude Code's idle card reads 'Claude Code · Integration'. Mattermost, Ato, WhatsApp and Notifications read 'Messages', with status 'Not signed in', 'N waiting' or 'Connected'.
- **Windows:** `windows/src/core/state.ts:198-227 (task(): no subtitle/icon/category); windows/src/views/integrations.ts:55-112 ('VS Code' at 108; kind always 'Integration'; 'Hooks not installed', 'Server not configured', 'Key not configured', 'Connected · loading…', connection-state labels)` — The header reads 'VS Code · Integration' and every pill is labelled 'Integration'. Status reads 'Connecting…', 'Connection failed · …', 'Server not configured', 'Hooks not installed' or 'Connected · loading…'.
- **Fix:** Extend INTEGRATION_AGENTS entries with subtitle, icon, category and character, copied from PillCatalog. Render name and subtitle in idleCard. Port statusLabel and statusDot exactly: unread count from State for message sources; 'Connected'/'Not connected' for hooks.
- **Phase:** Phase 5

### IC-G28 — The Notifications pill does not wear its own character (antenna + pixel eyes)

- **Mac:** `NotchBuddy/Sources/App/PillCatalog.swift:102-106; AppState.swift:663-670 (pill's own character before the default)` — With no character chosen, the Notifications Mochi has an antenna and pixel eyes.
- **Windows:** `windows/src/core/state.ts:874-877 (characterFor: stored, else default)` — It wears the default character.
- **Fix:** Add a PILL_CHARACTER map {integration_notifications: 'antenna:pixel'} and consult it in characterFor between the stored choice and defaultCharacter (also in settings/welcome previews).
- **Phase:** Phase 8

### IC-G29 — Hover and click-through margins are wider than the Mac's

- **Mac:** `NotchBuddy/Sources/App/IslandWindowController.swift:52-54 (enter 6, stay 20), 700-741 (hover rect = island when closed, chrome when open; click rect = hover ∪ chrome; exact island ∪ chrome when there is no notch and it is not expanded), 725-735 (0.5 s 'just reshaped, pointer still' grace)` — The pointer has to come within 6 pt to open the island and leave by 20 pt to close it.
- **Windows:** `windows/src/island/island.ts:93,102 (ENTER 14, STAY 28), 1607-1611; windows/src-tauri/src/island.rs:65-67 (HIT_MARGIN 14)` — 14 px to open and 28 px to close, so it opens from further away and stays open longer.
- **Fix:** Set ENTER_MARGIN=6 and STAY_MARGIN=20. In Rust, use 20 as the hit margin while open (the island's own rect when collapsed already matches). Keep targetRect as the Windows equivalent of the reshape grace.
- **Phase:** Phase 7

### IC-G30 — Compact-bar details: mini-grid metrics, timer badge position and colour, and missing fades

- **Mac:** `NotchBuddy/Sources/App/IslandRootView.swift:875-893 (12 pt cells, spacing 4, 28x28 frame), 194-197 (timer centred at x w-44), 684-693 (11 pt semibold monospaced, paused #8E939C), 188-216 (compact group fades 0.25 s easeInOut), 172-174 (Mochi fades 0.25 s for greeting/upload/characters-off)` — Faces are 12 pt with 4 pt gaps, the timer sits centred 44 pt from the right edge, and everything cross-fades over 0.25 s.
- **Windows:** `windows/src/style.css:235-245 (13px cells, gap 3, 29x29), 733-739 (#compact-timer: no transition), 157-161 (#bot-canvas: no opacity transition); windows/src/island/island.ts:918-921 (timer left = w-62), 2019 (paused #9398a1), 2029 (createMiniBot(t, 13)), 1821` — Faces are 13 px with 3 px gaps, the timer is placed by its left edge, the paused colour is a slightly different grey, and Mochi and the timer pop in and out without fading.
- **Fix:** Grid: columns 12px, gap 4px, 28x28; createMiniBot(t, 12). Timer: translateX(-50%) at left w-44; paused colour #8E939C. Add transition: opacity .25s ease-in-out to #bot-canvas and #compact-timer.
- **Phase:** Phase 4

### IC-G31 — View-switch and header-hide transitions differ slightly

- **Mac:** `NotchBuddy/Sources/App/IslandRootView.swift:656-666 (incoming: spring 0.4/0.8 delayed 0.16 s on opacity and scale 0.97→1; outgoing: easeIn 0.16 on both), 616-621 (header hidden for .confused and .web, with hit testing disabled)` — Cards cross-scale smoothly, and the invisible header cannot be clicked.
- **Windows:** `windows/src/style.css:364-378 (incoming: opacity 0.3 s ease-out + overshoot transform 0.3 s, delayed 0.16 s; outgoing: opacity only, so scale snaps); windows/src/views/views.ts:205 (opacity 0 only, header still clickable)` — The outgoing card's scale jumps, and the hidden header's invisible buttons remain clickable on the confused card.
- **Fix:** On .view (outgoing): transition: opacity .16s ease-in, transform .16s ease-in. On .view.on: approximate spring(0.4,0.8) with transform .4s cubic-bezier(.25,1.1,.4,1) .16s and opacity .4s .16s. In header sync, also set pointerEvents='none' while hidden.
- **Phase:** Phase 4

### IC-G32 — Hydration and sip card geometry differs from the Mac table

- **Mac:** `NotchBuddy/Sources/App/IslandTypes.swift:280-282 (hydration 240 / botX 62 / d 58; sip 160 / 62 / 56), 262 (messages botX 65), 311 (agenda botX 35), 242 (uploading botY 118)` — The water reminder card is 160 pt tall like every other notification. Mochi sits at x 62 at 56-58 pt.
- **Windows:** `windows/src/core/layout.ts:136-148 (messages 72, agenda 36, hydration 64/54, sip 170/64/54), 103 (uploading botY 103)` — The reminder is 170 px tall and Mochi is at x 64, 54 px. (messages/agenda/uploading are documented, measured deviations.)
- **Fix:** Set sip to {height:160, botX:62, botDiameter:56} and hydration to {botX:62, botDiameter:58}, and re-check the views' gutters. Keep the documented messages/agenda/uploading deviations only if the Windows header metrics really differ; otherwise align them too.
- **Phase:** Phase 4

### IC-G33 — Dragging Mochi onto a window to attach it as context is missing

- **Mac:** `NotchBuddy/Sources/App/IslandWindowController.swift:1330-1349 (drag starts on Mochi after 3 pt; love emote), 1354-1371 (drop on a window → promptContext, 'approve', happy emote, expand(.prompt)), 1439-1497 (ghost panel 40/0.6 pt, fades in over 0.18 s, scales up on a 0.28/0.55 spring), 1501-1559 (highlight: rounded 12, white 75% 3 pt stroke, 16 pt white glow, fade in 0.14 s, fade out 0.12 s)` — Dragging Mochi out of the open island carries a ghost Mochi and outlines the window under the cursor. Dropping attaches that window's context to the chat.
- **Windows:** `none (README 'Not in this version')` — Not available.
- **Fix:** Closable with Win32: WindowFromPoint and GetAncestor(GA_ROOT), skipping own-process and non-app windows. Read GetWindowTextW, the process exe name and the DWM extended frame bounds for the highlight. Draw the ghost and highlight as transparent topmost click-through tool windows with the exact values above.
- **Phase:** Phase 6

### IC-G34 — ChatGPT and the site are separate windows instead of screens inside the island

- **Mac:** `NotchBuddy/Sources/App/IslandTypes.swift:286-305 (web/webchat: size class .large, default 600x650, user range 360-600 x 240-800); IslandRootView.swift:176-184 (site drawn over the island, clipped to its shape), 616-621 (island header hidden for .web); IslandWindowController.swift:903-958 (screens fade out over 0.12 s when folding; closeScreen hands over to a pending approval or question)` — Opening ChatGPT or the site grows the island itself into a 600x650 screen. The page is clipped to the island's rounded shape and the island's header is replaced by the page's own bar. It reads as one surface.
- **Windows:** `windows/src/views/views.ts:113-140 (openPage toggles a separate window); windows/src-tauri/src/island.rs:585-648 (page window: island width, 8 px gap, 650 tall, on the far side of the card)` — A second window appears below or above the 640-wide card, 8 px away. Two surfaces.
- **Fix:** Best: enable Tauri's 'unstable' feature and use Window::add_child to put a child webview inside the island window. Add a 'web'/'webchat' view of size class large (600x650) and position the child at the island's rect, inside the header-replacing bar. Without unstable, the closest equivalent: - Grow the island to 600x650 on 'web'. - Hide its header. - Place the page window inside the island's rect (x+0, y+34, w, h-34) with zero gap. - Use DWMWA_WINDOW_CORNER_PREFERENCE and a borderless, topmost, non-taskbar window, so it reads as drawn inside.
- **Phase:** Phase 3

### IC-G35 — Saved ring buttons with dead ids are not pruned

- **Mac:** `NotchBuddy/Sources/App/AppState.swift:1089-1096` — Buttons whose pill or action no longer exists are dropped from the saved ring.
- **Windows:** `windows/src/core/state.ts:668-677; windows/src/island/island.ts:1083,1090 (label = raw id, '…' mark)` — They draw as grey '…' discs labelled with the raw id and do nothing useful.
- **Fix:** In the edgeButtons getter, filter to ids in INTEGRATION_AGENTS or EDGE_ACTIONS, and persist the filtered list once.
- **Phase:** Phase 4

### IC-G36 — Window level and Spaces behaviour

- **Mac:** `NotchBuddy/Sources/App/IslandWindowController.swift:345-350 (level mainMenu+3, canJoinAllSpaces, stationary, fullScreenAuxiliary, ignoresCycle; no shadow)` — Always above everything, including full-screen apps, on every Space.
- **Windows:** `windows/src-tauri/src/platform/windows.rs:279-349 (TOOLWINDOW + HWND_TOPMOST, re-asserted on foreground change), 386-424 (follows the virtual desktop)` — Topmost within the topmost band, re-asserted twice a second, following the current virtual desktop. Can be covered by exclusive-fullscreen apps and by other topmost windows between ticks.
- **Fix:** Already the closest available. Optionally also re-assert on EVENT_SYSTEM_FOREGROUND through SetWinEventHook (no 500 ms lag) instead of polling the foreground window.
- **Phase:** not done — the window level is already the closest Windows allows

### IC-G37 — Sound engine: unlimited overlap and suspend-on-idle vs a pool of 3

- **Mac:** `NotchBuddy/Sources/App/SoundEngine.swift:15-49 (3 preloaded players per sound; a 4th overlapping play restarts the first; played synchronously)` — At most 3 copies of one sound at a time, and no start-up latency.
- **Windows:** `windows/src/core/sound.ts:70-76 (AudioContext suspended after 1.5 s idle), 87-102 (unlimited BufferSources; resume() is async)` — Any number can stack, e.g. many 'tick's. The first sound after 1.5 s of idle waits on an async resume and can be clipped or late, e.g. the 'open' on hover.
- **Fix:** Cap concurrent sources per name at 3 (stop the oldest). Raise the idle suspend delay, or skip suspending while the island is expanded or resting under the pointer.
- **Phase:** Phase 7

### IC-G38 — Bottom-edge wake dwell (220 ms) and the invisible wake strip are Windows-only

- **Mac:** `NotchBuddy/Sources/App/IslandStateMachine.swift:157-166 (hover opens at once); IslandWindowController.swift:700-711` — Hovering the resting shape opens it immediately.
- **Windows:** `windows/src/island/island.ts:90,1480-1498 (WAKE_DWELL_MS 220 at the bottom), 1208-1221 (240x6 wake strip)` — At a bottom position the pointer must rest 220 ms. When folded, only an invisible 240x6 strip answers.
- **Fix:** These go away with top-centre (G01) and the visible hidden tab (G02). Keep the dwell only for users who pick a bottom preset.
- **Phase:** Phase 4

## Already matches

- FSM states and timings match: hidden/petit/home/coucou; leave grace 0.12 s; greeting folds 0.6 s after it ends and is never cut short by the pointer; notification hold = 0.34 + autoCloseInterval (default 5 s), re-armed per card and left running on re-enter, as a floor rather than a ceiling; petit→hidden = absenceInterval (180 s); the alwaysVisible setter settles the island on screen; a card arriving during the greeting is delivered 0.34 s after the fold.
- Open spring 0.34/0.78 and close curve cubic-bezier(.45,0,.2,1) over 0.22 s for mode changes (only the travel variants are missing, G06).
- Expanded width 640; corner radii 14 resting / 22 open; square corners against the edge and rounded on the other side; black fill, no shadow.
- View heights and Mochi placement for overview, empty, approval, question, error, finished, confused, upload, choose, mail, prompt, searching, result, note, message, timer, media and greeting; chat height min(300, 240+40n); message card growth and the 650 cap (parity-tested); botPosition formula (header 42, card 84, half the growth); compact Mochi (40,16,20) at 32 px height.
- Bot glow colours, opacities, 2.2x size, 6 px blur and 0.4 s transition; Mochi position spring 0.5/0.72.
- Mochi hover: blink, scale 1.08, 'hover', hearts and 'love' after 1.9 s, 6 s cooldown, re-armed after 40 px of movement. Slap: 'slap' plus 'annoyed' after 60 ms; dizzy after 3 slaps within 1.7 s; recovers after 3.3 s to the previous view with the happy emote.
- Placement logic: six presets with identical labels, 'free:fx,fy' drops, magnet 48, freeGeometry, islandX/islandY (Swift↔TS parity-tested by scripts/test-island-anchor.sh; Rust has its own copy of the table); hold-to-move 2 s with 6 px slop; resting-only pick-up.
- Edge ring geometry: diameter 34, gap 10, spacing 8, centre formula (columns centred on the island's mid-height, the row on its mid-width), shown only when open, part of the click-through and stay rect when open. Disc #0E0F11 with a 1 px border at 22% of the tint (75% on hover), 1.08 hover scale, 0 2 5 black 45% shadow. Mattermost and Ato marks drawn from the same ratios at 16 px. Clipboard #8AB4F8, Focus timer #F5A524, Settings #8E939C, Site #38BDF8; clipboard disc toggles the clipboard window.
- Pill catalog ids, names, colours and order (Claude Code #F5F6F8, Now Playing #FA2D48, Mattermost #1B6FF3, Ato #1B2FEB, WhatsApp #25D366, Notifications #FFFFFF); Claude Code always loaded; default active set {notifications, mattermost, ato, music}; ring defaults exclude Claude Code.
- Pill-open rules: a second click on the same pill while the island is up also opens the service; 6 px pointer slop for a second click that misses a moved disc; forgotten when the island closes; app → website → nothing resolution. Message pill → its list; Notifications → all sources; others → Home with that pill in focus; 'blip' on a pill click.
- Countdown hairline: white 35%, 2 px, radius 2, centred, max 160 px, visible during the last min(10 s, 0.6 × hold); hidden while the reply is held; snow steps aside under it.
- Compact bar right slot: mini grid of up to 4 other tasks centred at w-40; the running timer takes the slot; the hydration glass takes it while a reminder waits; the grid goes with characters off.
- Header metrics: 34 tall, padding 8/10/10, tabs 30x22 capsules, active #1D1F23 with #F5F6F8 ink, hover white 7% with #B0B5BE, idle #8E939C, left padding 14, gap 5, right group trailing 6, actions gap 14 trailing 16, X 18x18 with a 5 px larger hit area.
- Sounds: the same 28 WAV files, default volume 0.12, slider 0-0.2; 'open' on expand, 'close' on leaving expanded, 'peek' from hidden to compact and on lift, 'question' for an inbox message, 'approval' for an agenda heads-up, 'blip' for a hydration reminder, 'greet' in the greeting.
- Close shortcut: off by default, ⌃⌥X ↔ Ctrl+Alt+X, registered system-wide so it works whichever app has focus and swallows the key; registration failure surfaced in Settings.
- Click-through: 60 Hz toggling against the island/chrome rect while open; the resting window takes the mouse whole (equivalent to the Mac's exact rect on notchless displays); watchdogs on both sides stop a stuck state from eating clicks.
- Greeting collapse 0.34 s, and the greeting is skipped (reported complete) when characters are hidden.

## Known differences in windows/README.md

- **closable** — No notch, so the island lives against a screen edge, bottom-right by default; 'Mochi has no such preference on the Mac'. Stale. The Mac has the same 'Island sits at' picker with the same six presets plus free drag (IslandSettingsView.swift:203-210, IslandAnchor.swift:44-51); only its default is top-centre. Make top-centre the default on Windows (G01) and use the Mac's own notchless geometry (G02): an 80x24 tab with Mochi centred when hidden, a 240x24 bar when compact. That is exactly what the Mac shows on an external non-notch display. The only part forced by the platform is that there is no physical cutout to hide in.
- **closable** — 'It stays out': Never (always visible) is on by default, and off it retracts into an invisible wake strip; the Mac keeps 'Always visible' as its own row. On a notchless Mac, 'hidden' is still a visible 80x24 tab with Mochi. Render hidden that way (G02), then default alwaysVisible to false and Hide after to 180 s as on the Mac (G03). Mirror the Mac's 'Always visible' toggle on its own row, with 'Hide after … s without movement' disabled while it is on. Standby is Windows-only and can be dropped or kept as an accepted extra.
- **closable** — 'It costs nothing while it sits there': the window shrinks to the bar and the cursor poll parks. Not visible to the user, so there is nothing to close. Keep it: Fold::Bar simply takes the new 80x24 and 240x24 sizes.
- **closable** — Not in this version: dragging Mochi onto a window to attach context, and jumping to a specific terminal window ('Open terminal' opens VS Code). Both can be done with Win32 (G33, G26): WindowFromPoint/GetAncestor plus GetWindowTextW and the process name for drag-attach; EnumWindows for Windows Terminal, console, mintty, Alacritty and WezTerm plus SetForegroundWindow for the terminal jump, falling back to VS Code. (Sending a file by email is outside this surface.)
- **closable** — The site and ChatGPT are separate windows anchored to the island rather than drawn inside it. Tauri 2's 'unstable' feature provides Window::add_child, which can host a child webview inside the island window at the island's large 600x650 rect (G34), at the cost of an unstable API. Without it, the closest equivalent: grow the island to 600x650, hide its header, and overlay the page window exactly inside the island rect with zero gap and rounded DWM corners, so it reads as one surface.
- **closable** — The AI Agents dashboard has no Session/Week gauges, and its ring disc lacks the five-hour arc. Stale on both sides. The current Mac has no gauges and no arc: the agents disc is a plain sparkles symbol opening AgentsPanel, a 420x480 floating panel with an 'Account' card and a 'Running here' card. Windows has no panel and no disc at all, only dead .ag-* CSS. Port the panel and add the 'agents' action (G08); Claude Code keeps the same files under %USERPROFILE%.
- **closable** — The ring is dealt differently on a fresh install (message services down the near side, the player in the row). Port IslandEdgeLayout.defaults: alternate left/right in catalog order, nothing below (G09). Keep effectiveSide mirroring only for corner presets; at top-centre the result is identical to the Mac.
- **closable** — Permission approval works from any terminal (the Mac only listens to VS Code sessions). Outside this surface, and a Windows-only capability rather than a visual difference. Leave it, or restrict it to match the Mac only if the owner wants identical behaviour.

## Parity tests to add

- IslandMotion: openResponse 0.34, openDamping 0.78, closeDuration 0.22, close curve control points (0.45,0,0.2,1), fullTravel 400, and grow(travel)/shrink(travel) outputs at travel 0/100/400/600, compared with core/anim.ts. Today they are copied by hand and the 340 ms comment is already stale.
- IslandStateMachine: run the same scripted input traces (mouseEntered/mouseLeft/click/reveal/openedExternally↔forceHome/collapse↔forcePetit/greetComplete/alwaysVisible flips) on a fake clock in Swift and TS and compare transition logs and timer deadlines. Needs an injectable scheduler in fsm.ts, like Swift's `schedule`. Would have caught G20 and G21.
- IslandEdgeLayout: dump center(side,index,count,w,h) for a grid of island sizes and defaults(pills:) for several pill sets, and compare with edgeRing.ts layout() (anchor top-centre) and defaults(). Would have caught G09. Today the Swift tests are Swift-only.
- IslandEdgeAction: dump id, title, colorHex and icon for every case and compare with EDGE_ACTIONS plus RING_MARKS. Would catch the missing 'agents' (G08) and the site glyph and title (G12).
- PillCatalog: dump id, name, color, subtitle, icon, logo, category and character, in order, and compare with INTEGRATION_AGENTS once those fields are added. Would catch G13, G27 and G28.
- IslandConst.viewLayouts: dump height, botX, botY, botDiameter and agentMode per view and compare with VIEW_LAYOUTS, with an explicit allowlist for deliberate deviations (messages, agenda, uploading). Would catch G32.
- IslandScreenGeometry and IslandRestingLayout: dump the no-notch width and height at menu-bar 24 and with overrides 22/32/60, botDiameter, botCenterY and miniGridScale, and compare with layout.ts NOTCH_W/NOTCH_H/COMPACT_W and the resting botPosition once G02 lands; also check METRICS and island.rs REST_W/REST_H agree with them.
- botPosition: dump (cx,cy,d,opacity) for every mode × view × several island heights, including hidden on notch and no-notch, and compare with layout.ts botPosition.
- PillOpen: run tests/PillOpenTests.swift's cases against core/pillOpen.ts (opensTarget, opensTargetAt with POINTER_SLOP 6, pillTarget). The TS file is a port with no test of its own.
- IslandDisplays.chosen/active rules (empty = all, nothing matching = all, cursor display else first), against a TS/Rust port if G18 adds a per-display selection.
- RadialChordMachine and RadialGeometry: reuse tests/RadialChordTests.swift's input/output table for a Rust port (wedge(dx,dy,count), angle(of:), centre clamping, minWedges/maxWedges).
- CountdownBar constants (white 0.35, 2 px, radius 2, max 160, window min(10, 0.6×(autoClose+0.34))) against countdownWidth in island.ts.
- SoundEngine name list (28) against SOUND_NAMES in sound.ts, plus a table of island event → sound name on each side (open/close/peek/lift/drop/hover/love/slap/annoyed/question/approval/blip). Would catch G05, G22, G23 and G24.
- CloseHotKey.isAllowed and the default (⌃⌥X) against acceleratorFrom and default_close_shortcut, documenting the intended platform mapping (⌘→Win? ⌃→Ctrl, ⌥→Alt).
- Edge ring disc styling (fill #0E0F11, stroke tint 22%/75%, hover 1.08, shadow, logo 16, glyph 13) and header tab metrics (30x22, #1D1F23, #B0B5BE, white 7%, paddings 14/6/16, gaps 5/14). These are visual constants copied into CSS by hand; dumping the Swift values to JSON and asserting against parsed CSS custom properties would stop drift.

## Risks

- The README section 'What's different from the Mac version' and windows/screenshots/*.png are stale: the screenshots still show the removed Resend/n8n/Vercel/GitHub pills and 'VS Code', the AI Agents bullet describes gauges neither side has, and the placement bullet says the Mac has no position preference, which it does. Anyone working from them will port the wrong thing.
- Changing the default position to top-centre only reaches fresh installs: settings.rs writes position explicitly, so existing settings.json files keep 'bottom-right' unless migrated. The Rust resting_bar tests and the welcome-placement tests assume bottom-right and the 288x32 bar; the anchor parity table and METRICS have to change together with REST_W/REST_H.
- At top-centre there is no reserved menu bar on Windows, so the resting tab or bar (80-240 x 24) sits over the title bar or tab strip of maximised windows and takes clicks in that rectangle. On the Mac the same spot is the system menu bar. Keep the collapsed hit area exactly the bar (no margin).
- Low-level keyboard and mouse hooks (G15 Escape, G07 radial chord) in an unsigned Rust binary are the kind of behaviour Defender and Smart App Control heuristics flag; the README already records a Wacatac false positive. Code-signing should come first. The hooks must be strictly pass-through (Escape) and opt-in (radial), and the chord's 60 ms right-button delay can break right-click in games or remote desktops.
- Tauri's 'unstable' multiwebview (the cleanest way to put ChatGPT or the site inside the island) is not covered by semver and may break on Tauri updates. The overlay-window fallback needs careful z-order and focus handling, because the island is non-focusable while the page must take keystrokes.
- Shrinking the resting footprint to 240x24 changes what a stored free:fx,fy point means visually (the island's resting centre shifts slightly), and it changes the greeting's collapse destination (greeting.ts uses COMPACT_W/NOTCH_H) and every hit-test that assumed 32 px.
- Wayland/Linux cannot have global cursor reads or input hooks, so G07 (radial), G15 (global Escape) and parts of G18 (following the cursor) are not possible there; parity there stays partial.
- island.ts merges the Mac controller and root view, and several Windows paths use alert() (which arms a notification hold) where the Mac uses expand() (no hold): confused, tray open, setView from closed. Fixes must keep that distinction or cards will fold away on their own unexpectedly.
- The Windows hidden state at the bottom edge folds to zero height; G02's visible hidden tab must also work for bottom presets (a tab standing on the taskbar) and for free placement (fold.ts drawModeFor), or bottom users lose the island entirely.
