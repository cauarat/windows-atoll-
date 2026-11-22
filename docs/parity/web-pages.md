# Parity — ChatGPT, the site and WhatsApp Web

The Mac is the source of truth (see `CLAUDE.md`). Each gap names the Mac code, the Windows code and the fix; tick it in the PR that closes it. Audit of 2026-11-20 against `notchy` at f1dee26.

## Checklist

- [ ] **WC-01** · high · visual · L — ChatGPT opens as a separate floating window beside the island, not inside it — _Phase 3_ — _island side done (view, card, page_show); child webview is Rust's_
- [ ] **S-01** · high · visual · L — Site opens as a separate window instead of overlaying the island with its own header — _Phase 3_ — _island side done (view, own row, card); child webview is Rust's_
- [x] **WC-02** · high · missing on windows · M — No ChatGPT header row (Mochi, title, reload, close) — _Phase 3_ — _done: island row (Mochi seat, title, reload, X)_
- [ ] **S-02** · high · missing on windows · M — Site header controls missing (back, mark, spinner, reload, open in browser, close) — _Phase 3_ — _island side done (row drawn, page_back/reload/open_in_browser called)_
- [x] **S-03** · high · behaviour · S — Opening the site from the ring disc doesn't hold the island, so the page is hidden as soon as it is reached — _Phase 3_ — _done: the site is a screen and holds the island_
- [ ] **WC-04** · high · visual · M — Card chrome: rounded #141518 card with hairline vs a DWM window with shadow — _Phase 3_ — _island side done (card); rounded clip is Rust's_
- [ ] **WC-05** · high · missing on windows · M — No loading state; page visible before it has loaded — _Phase 3_ — _island side done (dots under the page); hidden-until-ready is Rust's_
- [ ] **WC-06** · high · missing on windows · M — No blocked/failed states, copy, or Try again — _Phase 3_ — _island side done (copy, Try again); blocked/failed states are Rust's_
- [ ] **WC-07** · high · behaviour · M — ChatGPT is loaded at every launch and never released (no cold/warm/live lifecycle) — _Phase 0 (no fetch at launch) / Phase 2 (switch) / Phase 3 (lifecycle)_
- [x] **WC-09** · high · behaviour · M — Chat tab is a toggle and the page outlives tab switches; the page doesn't follow card height — _Phase 3_ — _done: the tab only selects; leaving hides the page and resizes_
- [ ] **WC-11** · high · behaviour · M — Escape does not close ChatGPT or the site — _Phase 3_ — _island side done (Escape, page-escape → closeScreen); the accelerator hook is Rust's_
- [ ] **WA-01** · medium · behaviour · S — WhatsApp "needs QR" is reported as a red failure — _Phase 2_
- [ ] **PF-01** · medium · platform forced · M — Linux cannot host a positioned child webview — _Phase 3_
- [ ] **WA-02** · medium · missing on windows · M — No WhatsApp load deadline, retry backoff or crash recovery — _Phase 2_
- [x] **WC-03** · medium · visual · S — Island tab header absent above ChatGPT, and the chat tab is not lit — _Phase 3_ — _done: tabs stay up, chat tab lit for `webchat`_
- [ ] **S-04** · medium · extra on windows · S — Extra globe tab in the island header — _Phase 4 — Site tab kept (owner), drawn the Mac way_
- [x] **S-05** · medium · visual · M — Ring disc mark and tooltip differ (globe and "Site" vs NotchSiteGlyph and host name) — _Phase 3_ — _done: NotchSiteGlyph at 34 in the tint, host as tooltip_
- [ ] **S-06** · medium · behaviour · S — Site lifecycle: Mac loads fresh on each open and tears down on close; Windows loads at launch and lives forever — _Phase 3_
- [ ] **S-07** · medium · behaviour · S — Site navigation policy is stricter on Windows — _Phase 3_
- [ ] **WC-08** · medium · behaviour · S — Audio/voice keeps playing from a hidden ChatGPT — _Phase 3_
- [ ] **S-08** · medium · missing on windows · S — No site failure state — _Phase 3_ — _island side done (host, error, Try again); the failed state is Rust's_
- [x] **WC-10** · medium · behaviour · S — Cards and alerts replace the island under an open page — _Phase 3_ — _done: alert(), hooks and messages stand down over a screen_
- [x] **WC-12** · medium · behaviour · S — Closing a screen does not hand over to a waiting approval or question — _Phase 3_ — _done: `closeScreen()` (no question card on Windows yet)_
- [ ] **WC-13** · medium · behaviour · S — Links that open a new window (target=_blank, window.open) do nothing — _Phase 3_
- [ ] **WC-16** · medium · behaviour · S — Files dropped on ChatGPT never reach the page — _Phase 3_ — _island side done (its own drop stands down on a screen); the child's drop handler is Rust's_
- [ ] **WC-17** · medium · visual · S — ChatGPT follows the Windows theme (can be light) instead of forced dark — _Phase 3_
- [ ] **WC-18** · medium · missing on windows · M — No isolated ChatGPT data store and no "Clear ChatGPT data" — _Phase 2_
- [ ] **WC-19** · medium · copy · S — Settings: one switch in a Windows-only "Pages" section instead of the Mac's "ChatGPT (website)" group — _Phase 2_
- [ ] **WC-20** · medium · missing on windows · M — "Big screen" size preference missing; page height fixed at 650 and shrinks to fit — _Phase 3_ — _islandSize takes a `large` size; the preference itself is not ported_
- [x] **WC-21** · medium · visual · S — Page anchors to island+ring bounds, so it can be wider than and offset from the island — _Phase 3_ — _done: the page rect is the card's, never the chrome rect_
- [ ] **WC-26** · medium · platform forced · S — Keyboard: the island window is unfocusable, so typing into an in-island page needs explicit activation — _Phase 3_
- [ ] **PF-02** · low · platform forced · S — User agent and rounded clip can only be approximated — _Phase 3_
- [ ] **WA-03** · low · copy · S — WhatsApp settings buttons and window title differ — _Phase 2_
- [ ] **WA-04** · low · behaviour · S — WhatsApp links, downloads and media prompts handled differently — _Phase 3_
- [ ] **S-09** · low · extra on windows · S — Editable Site URL field (Mac hard-codes NotchSite.url) — _kept — the Pages/Site field stays, Mac-styled, in Phase 1 (owner)_
- [ ] **WC-14** · low · behaviour · S — Downloads stay in WebView2 instead of going to the browser — _Phase 3_
- [ ] **WC-15** · low · behaviour · S — Microphone/camera prompt instead of a silent deny — _Phase 3_
- [x] **WC-22** · low · extra on windows · S — Both pages can be up at once; the site and ChatGPT stack on the same spot — _Phase 3_ — _done: one screen at a time_
- [x] **WC-23** · low · behaviour · S — Chat tab plays a blip; Mac tabs are silent — _Phase 3_ — _done for the chat and site tabs; the rest of the header is IC-G05_
- [ ] **WC-24** · low · extra on windows · S — Borderless page window can be resized from its edges — _Phase 3_
- [ ] **WC-25** · low · behaviour · S — Navigation gestures and zoom not locked down — _Phase 3_

## Phase 3 — the island's half (2026-11-22)

ChatGPT (`webchat`) and the site (`web`) are island views now (`windows/src/core/layout.ts`): 600 × 650 and 600 × 600 on the Mac's table, `sizeClass: "large"`, and both 600 × 650 on screen because a screen takes `max(its layout, DEFAULT_LARGE_SIZE)` as the Mac's `islandSize` does. The island draws everything around and under the page (`windows/src/views/screens.ts`, styles at the end of `style.css`) and `windows/src/island/pageHost.ts` drives the page host contract with src-tauri:

- `page_show(label, x, y, width, height)` with the card's own rect inset by its 1 px stroke, once the island has stopped moving and the card has finished fading in; again on a window resize, a scale change, `screen-changed` or the island jumping somewhere else. `page_hide` before the first frame of any change that moves the island or leaves the screen; `page_hide_all` on fold, Escape and the close shortcut (`closeScreen`). Its answer and every `page-state` event drive the dots, the blocked/failed copy, and the site's spinner, back button and tooltip (`core/pageState.ts`); `page-escape` is the island's own Escape; `smoke-open-view` opens the view as its tab or disc would.
- A screen holds the island (`viewHoldsIslandOpen` → `fsm.heldOpen`, timers cancelled, no countdown); `alert()`, the hook cards and the message card stand down over one, sounds still playing; the island's drop stands down too. Escape, the screen's X, the island's X and the close shortcut go through `closeScreen()`: a pending approval takes over, otherwise the island folds with "close" and the view resets.
- The chat tab selects `webchat` when Settings has ChatGPT opening from it (`settings.webChat`), else the built-in chat, and is lit for either; the site's tab selects `web` like any tab; the ring disc opens the site as a notification would (`alert("web")`), so nothing happens over a screen. Both tabs and the disc are silent.
- Mochi rides ChatGPT's row as the island's own Mochi (`VIEW_LAYOUTS.webchat` botX 41, botY 67, diameter 20.4 = the 34 px canvas), with no glow and no slap/love hit; the site has none. With the characters off the seat closes and "ChatGPT" moves to x 24.
- The row icons are drawn stand-ins for the SF Symbols, sized against `Image(systemName:)` rendered in its 18 × 18 frame at 8×: every ink box within 0.13 pt, centroid within 0.4 pt. The ring's site disc and the site's 16 pt tile are `NotchSiteGlyph`/`NotchSiteIcon` ported in `views/logos.ts`, on the same pixels as the SwiftUI shapes.
- A failure says what the Mac says. The blocked and failed copy is the Mac's, in the catalogue in all three languages; the detail line is WebView2's error name turned into CFNetwork's own sentence for the matching NSURLError (`failureSentence`), copied from the system's tables in English, Spanish and Brazilian Portuguese. A name with no counterpart there — a failed redirect, an unexpected error — is shown as it came. On the Mac the blocked title stays English whatever the language: `WebChatHostView.swift:62` builds the title with the status already in it and `:125` hands that to `Text(loc:)`, so its key is never found (a Mac fix, waiting for the owner).
- Measured in `windows/dev/webchat-preview.html` (headless Chrome, 2×) against the owner's capture and a SwiftUI render of both views' bodies: island 600 × 650; ChatGPT row y 50…84 with Mochi's seat 24…58, "ChatGPT" from x 66, reload 526…544 and X 558…576; card x 20 y 84, 560 × 546, page at 21, 85, 558 × 544; site row y 8…42, back 14…32, mark 40…56, spinner 64…76, reload 502, open 534, X 566…584; site card x 10 y 42, 580 × 598, page at 11, 43, 578 × 596. Failure block and Try again on the SwiftUI render's pixels within about 1 pt. `?check=1` runs the behaviour above as 22 checks against the real island.
- Still the island's: the Big-screen preference (WC-20, `islandSize` already takes the size) and the travel-scaled motion (IC-G06). The 700 px panel holds 650 plus a 44 px row of discs at every edge anchor; a dropped island near the middle of a short display can still cut that row off, as the 650 message card already could.

## How each side is built

MAC (source of truth)
ChatGPT is an island VIEW, `.webchat` (IslandTypes.swift:40, layout :303-305 = width 600, height 650, botDiameter 0, sizeClass .large → `isScreen`). Reached ONLY from the island header's chat tab (2nd tab, sparkle mark) when Settings → Chat → GroupBox "ChatGPT (website)" has BOTH "Show ChatGPT in the notch" and "Open it from the chat tab" on (AppState.swift:803-817 `chatTabView`). No pill, no radial wedge. The tab sets `state.view = .webchat` (spring 0.3/0.8) and stays lit (#1D1F23 capsule) while the page is up (IslandRootView.swift:836-838).
Island while it shows: 600 × max(650, largeIslandHeight) (islandSize IslandWindowController.swift:1917-1921; Big-screen slider height 240…800, width capped at 600), black, expanded corner 22, grows with IslandMotion.grow. Tree (IslandRootView.swift:603-675 + WebChatHostView.swift:41-140):
  8pt top → IslandHeader 34pt (all tabs, gear, speaker, X — NOT hidden for webchat; hidden only for .confused/.web, :616)
  → content ZStack, padding h10 / bottom 10 → WebChatIslandView:
     8pt → header row 34pt, h-padding 14: [Mochi BotCanvasView 34×34, hidden when characters off] 8 ["ChatGPT" 12pt semibold #F5F6F8] spacer [arrow.clockwise reload] 14 [xmark → closeNotchSite]; buttons 11pt medium #8E939C, 18×18, hit area inset −5 (28×28)
     → card: RoundedRectangle(16, .continuous) fill #141518, overlay stroke white 3.5% 1pt, padding h10 / bottom 10 ⇒ card ≈ 560 × 546 at x20,y84 of the island
        • WKWebView clipped to the same 16pt continuous shape, opacity 0 until loadState == .ready, then 0.2s easeOut fade-in
        • idle/loading: TypingDotsView centred (3 × 5pt #6B7079 dots, scale 0.6↔1.2, 0.45s easeInOut, 0.14s stagger)
        • blocked(403/503 main frame): "ChatGPT is refusing the built-in browser (HTTP n)." 13 semibold / "Open it in your browser instead, or try again." 11 #8E939C centred max 360 / "Try again" capsule #1D1F23 11 semibold pad 12×6; 20pt padding
        • failed: "Could not reach ChatGPT." / error.localizedDescription / Try again
Controller (WebChatController.swift): web view lives outside SwiftUI; phases cold (no WebContent process, nothing contacts OpenAI) → live (attached, panel makeKey + firstResponder) → warm (detached on leaving the view/collapse, media suspended, page hidden/throttled) → cold after 600s idle, memory-pressure warning/critical, or master off (saves interactionState: URL, back/forward, scroll). Named WKWebsiteDataStore (UUID under `webChatStoreID`), "Clear ChatGPT data" deletes it. Safari 27 UA. Main-frame-only allowlist of 8 OpenAI hosts (dot-anchored suffix); anything else → cancel + open in default browser; new-window requests: allowed host loads in place, else browser; non-renderable MIME → browser; <input type=file> → NSOpenPanel then re-key; mic/camera → deny; back/forward swipe + magnification off; darkAqua appearance; black under-page.
Hold/close: `viewHoldsIslandOpen` (AppState.swift:833) feeds fsm.isHeldOpen (IslandWindowController.swift:620-631) → never folds on pointer-leave or timers; `notify()` refuses every card while a screen is up (:1021-1022; sounds still play); countdown hairline hidden. Escape (local monitor :1106-1113 and :1131-1140), the ChatGPT X, the island X and the close hotkey all → `closeScreen()` (:952-958): pending approval/question takes over, otherwise fold to compact with "close" sound; screen view reset to default with 0.12s fade (:925-927). Leaving to another tab → deactivate (warm) and island resizes to that card. Drop view stands down so dropped files reach ChatGPT (:462). Scroll momentum holds the mouse 0.35s (:1301-1306).
Site (`.web`, IslandTypes.swift:286-287 = 600×600 large): reached from the edge-ring disc `.site` (IslandEdgeAction.swift:72-73 → hookExpand → notify(.web)); disc draws NotchSiteGlyph on a #0E0F11 22pt circle tinted #38BDF8 (IslandEdgeRingView.swift:99-111). NotchSiteView OVERLAYS the whole island (IslandRootView.swift:178-184) and the IslandHeader is hidden/non-hit (:616-621): header 8+34 = [chevron.left back if canGoBack] [NotchSiteIcon 16 tile, tooltip = page title or host] [small spinner while loading] … [arrow.clockwise] [arrow.up.right open in browser] [xmark]; IslandHeaderIconButton 13pt #8E939C→#F5F6F8 hover, 18×18, spacing 14, leading 14 / trailing 16; card 16pt continuous #141518 + 3.5% stroke, padding h10/b10 (≈580×598); failure = host label + error + Try again. Page built on open, stopped + blanked on close (fresh load each time), default data store, any http/https/about/blob stays in place, other schemes only on link click to the system, back gestures on. (NotchSiteLauncher beside the notch is dead code — not used anywhere.)
WhatsApp: never shown in the island. Hidden WKWebView (inactiveSchedulingPolicy .none, bridge script, Safari 18 UA) runs while the pill is on and the Mac is linked; sign-in is a titled 1000×720 window "Connect WhatsApp", centred, app activated, auto-closes 1.2s after connected; states disconnected/connecting/needsQR/connected/failed; 60s load deadline → "WhatsApp Web did not load" → retry 5s doubling to 300s; WebContent crash → reload; links/downloads → browser; mic/camera denied.

WINDOWS (Tauri 2.12.0)
No `web`/`webchat` island views exist (layout.ts:11-35; islandSize always 640 wide, :240-273). Each page is a separate WebviewWindow built AT LAUNCH (lib.rs:1295 → web.rs:147-163): borderless, transparent, always-on-top, skip-taskbar, resizable 760×620 (min 420×320), hidden, default shadow (→ Win11 DWM 8px rounding, 1px border, drop shadow), Edge 140 UA for ChatGPT, on_navigation allowlist (same 8 hosts; site = configured host only). Shown by `toggle` (web.rs:212-237): placed by `page_placement` (island.rs:585-648) — width = the rect the island pushes via set_island_rect, which is island + ring discs (island.ts:1187-1200), x aligned to it, on the far side of the card with 8px gap, height min(650, room) else not shown — then show + set_focus. Entry points: header chat tab when Settings → Pages → "Chat tab opens ChatGPT" (views.ts:121-131), a header globe tab (views.ts:136-140) and the ring "site" disc (island.ts:1115-1117). Header paths call setPinned(up) (pinned + heldOpen), the ring path does not. Every exit from expanded calls hide_pages (island.ts:552-566); master off hides (lib.rs:121). No header, no Mochi, no reload/close, no loading/blocked/failed UI, no cold/warm lifecycle, no Escape, no new-window/download/permission/drop handling, shared default WebView2 profile, no clear-data. WhatsApp (whatsapp.rs) mirrors the Mac's hidden page with a title-change doorbell instead of IPC, a decorated 1000×720 window titled "WhatsApp" for the QR, a 5s supervisor, no load deadline/retry.

KEY ARCHITECTURAL QUESTION — can Windows draw ChatGPT inside the island?
Yes on Windows. Cargo.lock resolves tauri 2.12.0 / tauri-runtime-wry 2.12.0 / wry 0.57.0; tauri's `unstable = ["tauri-runtime-wry?/unstable"]` feature exposes `Window::add_child(WebviewBuilder, position, size)` (tauri window/mod.rs:1229-1248, gated `all(desktop, feature = "unstable")`) and `tauri::webview::WebviewBuilder` (unstable_struct, webview/mod.rs:263-286). `Webview::set_bounds/set_size/set_position/hide/show/set_focus/reparent/set_auto_resize/with_webview` are public (webview/mod.rs:1655-1768, 1862). The child WebviewBuilder has everything the Mac controller needs: on_navigation, on_new_window, on_download, on_page_load, on_permission_request, user_agent, additional_browser_args, data_directory, background_color, disable_drag_drop_handler, focused, zoom_hotkeys_enabled. On WebView2, wry makes each child a `WRY_WEBVIEW` WS_CHILD|WS_CLIPCHILDREN HWND placed HWND_TOP above the island's own webview (wry webview2/mod.rs:211-282), so it inherits the island's always-on-top band, virtual-desktop handling, WS_EX_TRANSPARENT click-through toggling and focusable flag. It is rectangular: clip it with SetWindowRgn(CreateRoundRectRgn(…, 2·16·scale)) on the container HWND obtained through `with_webview(|w| w.controller().ParentWindow())`; the edge aliasing falls on the island's own #141518 card drawn beneath, so it reads as the Mac's 16pt card. No HTML can be drawn over it (airspace), so loading dots/failure states are island HTML shown while the child is hidden — exactly the Mac's "opacity 0 until ready". Linux: NOT viable — tauri-runtime-wry packs Linux children into the window's GtkBox (lib.rs:5187-5191) and WebKitGTK `set_bounds` only positions inside a GtkFixed (webkitgtk/mod.rs:963-985), so a child cannot be placed over the card; keep a separate window there.
Alternative B: a borderless OWNED window (`.parent(&island)`, shadow(false), opaque #141518, SetWindowRgn 16) glued exactly over the card rect, moved on every island move/animation. No unstable flag and it also works on Linux X11/GNOME, but it is two HWNDs to keep in lockstep through springs, drags, DPI changes, topmost reasserts and desktop switches, and activating it moves the foreground away from the island.
RECOMMENDATION: A on Windows (closest to the Mac: the page lives in the island, moves and clips with it, one hit-test, one z-order), B as the Linux path and as the Windows fallback if add_child shows the blank-WebView2 problem. File-level steps: (1) Cargo.toml:17 `features = ["tray-icon", "unstable"]` (pin tauri to 2.12.x; add windows-crate feature Win32_Graphics_Gdi). (2) island.rs:485-487 `window()` uses `get_webview_window`, which returns None as soon as the window has a second webview (tauri lib.rs:603-611, is_webview_window) — switch every island window/webview lookup (island.rs, lib.rs, shortcut.rs, platform/*) to `get_window(WINDOW_LABEL)` + `get_webview(WINDOW_LABEL)` first. (3) web.rs: replace WebviewWindowBuilder for CHAT_LABEL/SITE_LABEL with `WebviewBuilder` added through `island_window.add_child(...)` lazily on first open (cold) from an async command or spawned thread (sync callers deadlock on WebView2, window/mod.rs:1186-1189), same BROWSER_ARGS, own data_directory for ChatGPT, background_color #141518, disable_drag_drop_handler, on_page_load (Started→loading, Finished→ready→show), on_new_window, on_download, permission deny; keep it hidden() when warm; close() after 600s for cold. (4) New commands `page_bounds(label, x, y, w, h)` (Webview::set_bounds + re-apply the rounded region) and `page_state` events → island. (5) platform/windows.rs: `round_child_region(webview, radius)`; WebView2 AcceleratorKeyPressed on the controller to turn Escape into a "close-screen" event to the island; set_activating(true) + webview.set_focus while live. (6) layout.ts/island.ts/views.ts: add `web` and `webchat` views (600×650/600×600, sizeClass large), `isScreen`/`viewHoldsIslandOpen`, alert() guard, closeScreen(), header hiding for `web`, ChatGPT header + site header + card + dots/failure views; push the card rect only after the open spring settles and hide the child at the start of any shrink. (7) Linux cfg: keep web.rs's window path but restyle it as option B over the card rect.

## Gaps

### WC-01 — ChatGPT opens as a separate floating window beside the island, not inside it

- **Mac:** `IslandViewContent.swift:35; IslandTypes.swift:303-305; IslandWindowController.swift:1917-1921; IslandRootView.swift:263-282` — The chat tab switches the island itself to `.webchat`: the black island springs to 600×650 (IslandMotion.grow), keeps its tab header, and ChatGPT fills a rounded card inside it.
- **Windows:** `web.rs:89-144, 175-237; island.rs:585-648; views.ts:121-131` — The island stays at its current card (e.g. Home 640×160). A separate 640-wide borderless always-on-top WebView2 window up to 650 tall appears 8px above it (bottom-right default) or below it (top). If there isn't enough room, nothing shows at all.
- **Fix:** Add `webchat` (600×650) and `web` (600×600) entries with a large size class to layout.ts VIEW_LAYOUTS/islandSize and make the island grow to them. Host ChatGPT as a child webview of the island window via tauri `unstable` add_child, positioned over the card rect (island x+20, y+84, 560×546 at the default size) and clipped with SetWindowRgn radius 16. See the architecture section. Linux: an owned window glued over the same rect.
- **Phase:** Phase 3

### WC-02 — No ChatGPT header row (Mochi, title, reload, close)

- **Mac:** `WebChatHostView.swift:46-49, 82-121` — Below the island tabs: 8pt gap, then a 34pt row padded 14 horizontally. It holds Mochi (BotCanvasView 34×34, omitted when characters are off), 8pt, "ChatGPT" in 12pt semibold #F5F6F8, a spacer, then reload (arrow.clockwise) and X (xmark), 14pt apart. The icons are 11pt medium #8E939C in 18×18 frames with a 28×28 hit area. X posts closeNotchSite.
- **Windows:** `none (web.rs builds a chrome-less window)` — The page window has no header, title, Mochi, reload or close control.
- **Fix:** In views.ts add buildWebChat() using the existing `.header-actions`/`.close` CSS: an 18×18 button with an inset −5 hit area, at 11px and weight 500, with colour var(--dim-2) and no hover change. Put Mochi in the header by giving VIEW_LAYOUTS.webchat botX 41, botY 67 and diameter ≈20 (34px canvas = diameter/0.6), hidden with hideCharacters. Reload calls a new `webchat_reload` command; X calls closeScreen().
- **Phase:** Phase 3

### WC-03 — Island tab header absent above ChatGPT, and the chat tab is not lit

- **Mac:** `IslandRootView.swift:616-621, 721-730, 833-841` — The full IslandHeader row stays on top of the ChatGPT screen. The chat tab is lit (#1D1F23 capsule, #F5F6F8 ink) while the view is .webchat or .prompt.
- **Windows:** `views.ts:196` — The tab header belongs to the separate island card. `tabChat.on` only toggles for `prompt`, so opening ChatGPT never lights the tab.
- **Fix:** Once `webchat` is a view, change views.ts:196 to `tabChat.classList.toggle("on", v === "prompt" || v === "webchat")` and keep #header visible for webchat. Hide it (opacity 0, pointer-events none) only for `confused` and `web`.
- **Phase:** Phase 3

### WC-04 — Card chrome: rounded #141518 card with hairline vs a DWM window with shadow

- **Mac:** `WebChatHostView.swift:51-58, 72-77` — A RoundedRectangle(16, .continuous) filled #141518 with a 1pt white 3.5% stroke, inset 20pt from the island's sides and bottom. The page is clipped to the same shape. No shadow.
- **Windows:** `web.rs:99-106 (decorations false, transparent true, default shadow)` — The default shadow=true on an undecorated window gives Windows 11 DWM 8px rounding, a 1px light border and a drop shadow. The window is transparent, has no inset and no hairline, and sits detached from the island.
- **Fix:** Draw the card in island HTML (`.card` but border-radius 16px, background var(--card) #141518, border 1px rgba(255,255,255,.035)) and put the child webview over its inner rect with SetWindowRgn(CreateRoundRectRgn(0,0,w+1,h+1,32·scale,32·scale)). Set background_color #141518. If a window is kept (Linux), set .shadow(false).
- **Phase:** Phase 3

### WC-05 — No loading state; page visible before it has loaded

- **Mac:** `WebChatHostView.swift:55-58, 66-67; IslandViewContent.swift:1277-1296` — While idle or loading, typing dots are centred on the bare card: three 5pt #6B7079 dots scaling 0.6↔1.2 over 0.45s with a 0.14s stagger. The web view stays at opacity 0 and fades in over 0.2s easeOut on didFinish.
- **Windows:** `web.rs:89-144 (no on_page_load)` — The window appears immediately and shows whatever WebView2 has painted, which can be transparent, white or half-loaded.
- **Fix:** Add `.on_page_load` to the ChatGPT builder: Started → emit page-state loading and hide() the child; Finished → emit ready and show(). The island renders the existing `.typing` element (style.css:1645-1670 already matches TypingDotsView) centred in the card. Fake the 0.2s fade by delaying show() until the island opacity transition has run.
- **Phase:** Phase 3

### WC-06 — No blocked/failed states, copy, or Try again

- **Mac:** `WebChatController.swift:265-300; WebChatHostView.swift:60-66, 123-139` — A main-frame 403/503 shows "ChatGPT is refusing the built-in browser (HTTP n)." and "Open it in your browser instead, or try again.". Any other failure shows "Could not reach ChatGPT." with the system error. Both have a "Try again" capsule (#1D1F23, 11pt semibold, 12×6 padding). Title 13pt semibold, detail 11pt #8E939C centred, max width 360, 20pt padding.
- **Windows:** `none` — WebView2's own error page or Cloudflare's block page shows inside the window, with no app copy.
- **Fix:** In on_page_load, or a navigation-completed hook through with_webview (ICoreWebView2 NavigationCompleted → HttpStatusCode / WebErrorStatus), emit blocked(code) or failed(msg). Render the failure block in island HTML while the child is hidden. Add the two missing strings to i18n/catalog.json; they are absent today and Mac renders them through Text(loc:) with interpolation, so use the key form "ChatGPT is refusing the built-in browser (HTTP %@).".
- **Phase:** Phase 3

### WC-07 — ChatGPT is loaded at every launch and never released (no cold/warm/live lifecycle)

- **Mac:** `WebChatController.swift:15-19, 46-49, 87-146, 173-180, 229-240; IslandWindowController.swift:1001-1005` — Nothing touches OpenAI until the user opens ChatGPT with both settings on. The page goes warm (detached) when left and cold (process released, state saved) after 600s idle, on memory pressure, or when the master switch turns off. The URL, back/forward history and scroll position come back on rebuild.
- **Windows:** `web.rs:146-163; lib.rs:1295; lib.rs:118-121` — The `webchat` window is built at startup with WebviewUrl chatgpt.com, so it fetches chatgpt.com on every launch even when the feature is off. That breaks the README/Settings promise that network requests only go to configured services. It stays alive hidden for the whole session; master off only hides it.
- **Fix:** Create the child webview lazily on first open (async command), hide() on leave (warm), close() after 600s via a tokio timer, and close on master off and on Windows low-memory notification (CreateMemoryResourceNotification). Persist the last URL (from on_navigation) in settings and reload it instead of the root. If the blank-on-late-create issue is real, create at launch pointed at about:blank and navigate on first open.
- **Phase:** Phase 0 (no fetch at launch) / Phase 2 (switch) / Phase 3 (lifecycle)

### WC-08 — Audio/voice keeps playing from a hidden ChatGPT

- **Mac:** `WebChatController.swift:107, 121-128` — Deactivating calls setAllMediaPlaybackSuspended(true); activating resumes media.
- **Windows:** `web.rs:239-245 (hide only)` — hide() leaves the page running. BROWSER_ARGS even sets autoplay without a gesture, so voice playback continues from a closed island.
- **Fix:** On warm: run `document.querySelectorAll('audio,video').forEach(m=>m.pause())` through webview.eval, or mute through ICoreWebView2_8::put_IsMuted(true) via with_webview, and unmute on show. Prefer IsMuted, which needs no page script.
- **Phase:** Phase 3

### WC-09 — Chat tab is a toggle and the page outlives tab switches; the page doesn't follow card height

- **Mac:** `IslandRootView.swift:843-849; IslandWindowController.swift:453-468` — The chat tab only selects the view, and a second click keeps it. Clicking Home, Timer or another tab deactivates ChatGPT (warm) and resizes the island to that card.
- **Windows:** `views.ts:113-131; web.rs:196-237; lib.rs:607-613` — A second click hides the window. Switching to another tab leaves ChatGPT up and the island pinned. set_island_rect never calls reanchor, so when the card changes height (timer 190, lists 240) the page window overlaps the card or leaves a gap.
- **Fix:** Once ChatGPT is a view, setView() leaving `webchat` calls `page_hide("webchat")` and drops the hold. No toggle. The Windows/Linux window fallback must also re-run web::anchor from set_island_rect while a page is up.
- **Phase:** Phase 3

### WC-10 — Cards and alerts replace the island under an open page

- **Mac:** `IslandWindowController.swift:1016-1022, 1261-1268, 1215-1225` — notify() returns early while a screen holds the island, so approvals, messages, timer end, hydration and agenda never cover ChatGPT or the site. Sounds still play and the pill carries the badge.
- **Windows:** `island.ts:657-676` — alert() always forceHome()+expand(view): the island card under or beside the page switches to the alert. Because the page is not re-anchored, a taller card can overlap it.
- **Fix:** Add `get viewHoldsIslandOpen() { return State.mode === "expanded" && isScreen(State.view) }` and return early from alert() when it is true. Play the sound before the guard as the Mac does.
- **Phase:** Phase 3

### WC-11 — Escape does not close ChatGPT or the site

- **Mac:** `IslandWindowController.swift:1106-1113, 1119-1124, 1131-1140` — With ChatGPT focused, a local key monitor swallows Escape and calls closeScreen(). A global monitor does the same for the site.
- **Windows:** `island.ts:1556-1557; web.rs:234-235` — The page window has the keyboard, so Escape goes to chatgpt.com. The island's own handler requires `!State.isPinned`, and pinned is true while a page is up.
- **Fix:** Hook the WebView2 controller's AcceleratorKeyPressed through with_webview. On VK_ESCAPE keydown, set Handled and emit "close-screen" to the island, which calls closeScreen(). In island.ts, Escape calls closeScreen() when viewHoldsIslandOpen, before the isPinned check.
- **Phase:** Phase 3

### WC-12 — Closing a screen does not hand over to a waiting approval or question

- **Mac:** `IslandWindowController.swift:938-958, 1079-1086, 1240-1243` — closeScreen(): a pending approval opens .approval, a pending question opens .question, otherwise the island folds to compact and the view resets with a 0.12s fade. The island X and close hotkey go through dismiss() → closeScreen().
- **Windows:** `island.ts:637-647; main.ts:53-55` — The island X and close shortcut call collapse() → forcePetit, which hides the page and folds regardless of a pending approval.
- **Fix:** Add closeScreen() to island.ts: if State.pendingApproval, expand("approval"); else if a question is pending, expand("question"); else collapse(). Route the header X, close-shortcut, Escape and the page X through it whenever viewHoldsIslandOpen.
- **Phase:** Phase 3

### WC-13 — Links that open a new window (target=_blank, window.open) do nothing

- **Mac:** `WebChatController.swift:305-320` — An allowed host loads in place; anything else opens in the default browser through safeWebURL.
- **Windows:** `web.rs:89-129 (no on_new_window); wry webview2/mod.rs:848-850` — With no handler, wry calls SetHandled(true), so citations and "open in new tab" links in ChatGPT answers are silently swallowed.
- **Fix:** Add `.on_new_window(|url, _| { if keeps_in_window(&url, CHAT_HOSTS) { navigate same webview } else { platform::open_url(url) }; NewWindowResponse::Deny })`. Same on the site, which loads any safe web URL in place.
- **Phase:** Phase 3

### WC-14 — Downloads stay in WebView2 instead of going to the browser

- **Mac:** `WebChatController.swift:276-283` — A response WebKit cannot show is cancelled and its URL opened in the browser.
- **Windows:** `web.rs:89-129 (no on_download)` — WebView2's default download flow runs inside a borderless always-on-top window.
- **Fix:** `.on_download(|_, ev| { if let DownloadEvent::Requested { url, .. } = ev { platform::open_url(url.as_str()) }; false })` for chat and site.
- **Phase:** Phase 3

### WC-15 — Microphone/camera prompt instead of a silent deny

- **Mac:** `WebChatController.swift:345-354` — Every media capture request from ChatGPT is denied, so voice mode never hangs on a prompt.
- **Windows:** `lib.rs:1214-1222` — Labels other than `island` get PermissionResponse::Default, so WebView2 shows its own permission prompt in a chrome-less window.
- **Fix:** In the global on_permission_request return PermissionResponse::Deny for Microphone/Camera when webview.label() is "webchat", "site" or "whatsapp".
- **Phase:** Phase 3

### WC-16 — Files dropped on ChatGPT never reach the page

- **Mac:** `IslandWindowController.swift:459-462` — Coucou's drop view stands down while .webchat is on screen, so a dropped file is attached to ChatGPT.
- **Windows:** `web.rs:92-106 (drag-drop handler left on)` — Tauri's drag-drop handler is on by default, so the OS drop becomes a tauri event nobody listens to and ChatGPT's HTML5 drop zone never fires.
- **Fix:** Call `.disable_drag_drop_handler()` on the ChatGPT webview builder. For the child-webview design, also have island.ts onDragDrop ignore drops whose position is inside the card rect while view === "webchat".
- **Phase:** Phase 3

### WC-17 — ChatGPT follows the Windows theme (can be light) instead of forced dark

- **Mac:** `WebChatController.swift:210-211` — The web view has appearance darkAqua and a black under-page, so the page renders its dark theme inside the black island.
- **Windows:** `web.rs:92-106` — With no theme set, prefers-color-scheme follows Windows. In light mode a white ChatGPT sits on a black island.
- **Fix:** Set the ChatGPT profile's PreferredColorScheme to DARK through with_webview (ICoreWebView2_13::Profile().SetPreferredColorScheme), and background_color #141518 (#000 for overscroll). Give ChatGPT its own data_directory first: PreferredColorScheme is per profile and would otherwise flip the settings and clipboard windows too.
- **Phase:** Phase 3

### WC-18 — No isolated ChatGPT data store and no "Clear ChatGPT data"

- **Mac:** `WebChatController.swift:153-163, 182-196; SettingsView.swift:675-685` — A named WKWebsiteDataStore holds the cookies. "Clear ChatGPT data" goes cold, deletes the store and shows "✓ ChatGPT data cleared — you are signed out."
- **Windows:** `web.rs:92-110 (default profile shared with island/settings/clipboard)` — ChatGPT shares the island's default WebView2 profile. Calling clear_all_browsing_data on it would also wipe the island's own storage. There is no clear button.
- **Fix:** Give ChatGPT `.data_directory(app_local_data_dir/webchat-webview)`, as whatsapp.rs:71-75,104-108 already does, and add a `webchat_clear_data` command (close the webview, delete the dir or clear_all_browsing_data, reset the saved URL). Add a settings button with the Mac copy, and add the confirmation string to the catalog (missing today).
- **Phase:** Phase 2

### WC-19 — Settings: one switch in a Windows-only "Pages" section instead of the Mac's "ChatGPT (website)" group

- **Mac:** `SettingsView.swift:663-689` — Under Settings → Chat, after Local models, a GroupBox titled "ChatGPT (website)" holds checkbox Toggles "Show ChatGPT in the notch" and "Open it from the chat tab" (disabled until the first is on). Below them: the 11pt secondary explainer "Opens chatgpt.com itself inside the island, with no API key. Signing in is optional and only buys you history and memory. Attaching a window or asking about a dropped file still uses the built-in chat." and a bordered "Clear ChatGPT data" button with "Signs out and deletes the cookies WebKit stored for the site.".
- **Windows:** `settings/main.ts:905-959, 2480` — A "Pages" h2 with a Site URL field, a single "Chat tab opens ChatGPT" switch, and a different hint ("…Each is a window of its own…"). It is not in the chat section.
- **Fix:** Split `web_chat` into `web_chat_enabled` and `use_web_chat` (settings.rs:141-144, state.ts:319-320). Move the block into the chat/API section as a group titled t("ChatGPT (website)") with the two Mac strings (already in the catalog), disabling the second until the first is on, plus the explainer and clear button. Drop the "window of its own" hint once WC-01 lands.
- **Phase:** Phase 2

### WC-20 — "Big screen" size preference missing; page height fixed at 650 and shrinks to fit

- **Mac:** `AppState.swift:110-124; IslandSettingsView.swift:57-71; IslandWindowController.swift:1917-1921` — Settings → Island → Layout → "Big screen" has Width and Height sliders (360–600 and 240–800, off = designed size). Screens are max(layout, chosen): ChatGPT 600×650…800, site 600×600…800.
- **Windows:** `island.rs:83-91, 627-648; layout.ts:68-77` — PAGE_H is a constant 650, shrunk to whatever room remains, with a 320 minimum. There is no preference, and the 700px panel cannot hold an island taller than about 656 with a ring row.
- **Fix:** Add largeIslandWidth/Height to Settings (Rust + TS) with the same ranges and copy ("Big screen", "How large the island gets…", already in the catalog), and use max(layout, large) in islandSize. Raise PANEL_H (island.rs:24, layout.ts:77, tests/IslandAnchorTests.swift) to 800 + 44 to hold an 800-tall screen plus the ring.
- **Phase:** Phase 3

### WC-21 — Page anchors to island+ring bounds, so it can be wider than and offset from the island

- **Mac:** `WebChatHostView.swift:76-77` — The page card sits exactly 20pt inside the island's left, right and bottom edges.
- **Windows:** `island.ts:1187-1200, 943; web.rs:182-191; island.rs:612-617` — `card` is the rect pushed by set_island_rect, which is chromeBounds(island + edge discs). With discs on the sides the page is wider than the island and shifted; with a disc row on the far side it is pushed past the discs.
- **Fix:** With the child-webview design, compute the card rect from the island rect alone in TS (x+20, y+84, w−40, h−104 for webchat; x+10, y+42, w−20, h−52 for web) and send it with a dedicated page_bounds command, never the chrome rect.
- **Phase:** Phase 3

### WC-22 — Both pages can be up at once; the site and ChatGPT stack on the same spot

- **Mac:** `IslandTypes.swift:11-46 (one `view` at a time); IslandWindowController.swift:1021-1022` — Only one screen can be on the island. Pressing the site disc while ChatGPT is up does nothing, because notify() is refused.
- **Windows:** `web.rs:212-237; views.ts:113-116` — Each window toggles on its own, so both can be visible and overlapping. Closing one calls setPinned(false) while the other is still up, so the island folds and hides both.
- **Fix:** Make them views (only one at a time). Until then, toggling one hides the other, and the pin follows `any page visible`.
- **Phase:** Phase 3

### WC-23 — Chat tab plays a blip; Mac tabs are silent

- **Mac:** `IslandRootView.swift:843-849` — TabButton changes the view with no sound.
- **Windows:** `views.ts:113-116, 174-177` — openPage() and go() both call actions.blip().
- **Fix:** Drop actions.blip() from tab clicks. This applies to the whole header; coordinate with the header surface owner.
- **Phase:** Phase 3

### WC-24 — Borderless page window can be resized from its edges

- **Mac:** `n/a (the page is inside the fixed-size island)` — The page size is the island's size; nothing to drag.
- **Windows:** `web.rs:99-101` — `.resizable(true)` on an undecorated window gives tao drag-resize borders, so the user can drag ChatGPT out of alignment.
- **Fix:** Goes away with the child webview. For the Linux/fallback window set `.resizable(false)`.
- **Phase:** Phase 3

### WC-25 — Navigation gestures and zoom not locked down

- **Mac:** `WebChatController.swift:206-209` — Back/forward swipe and magnification are off, so a sideways scroll in a code block cannot navigate away from the conversation.
- **Windows:** `web.rs:92-110` — WebView2 swipe navigation (IsSwipeNavigationEnabled) is on by default for touch and precision touchpads, and pinch zoom is on.
- **Fix:** Through with_webview set ICoreWebView2Settings6::put_IsSwipeNavigationEnabled(false) and ICoreWebView2Settings5::put_IsPinchZoomEnabled(false). Keep zoom_hotkeys_enabled(false), which is the default.
- **Phase:** Phase 3

### WC-26 — Keyboard: the island window is unfocusable, so typing into an in-island page needs explicit activation

- **Mac:** `WebChatController.swift:111-116, 336-340; IslandWindowController.swift:430-468` — The non-activating panel is made key and the WKWebView first responder whenever ChatGPT becomes live, and again after the file panel closes.
- **Windows:** `tauri.conf.json island "focusable": false; platform/windows.rs:283-292; lib.rs:615-622` — Today the separate window takes focus with set_focus(). Once the page is a child of the island window, the window must become focusable first.
- **Fix:** Closest equivalent: when webchat goes live call platform::set_activating(&island, true), win.set_focus() and child_webview.set_focus(). On leave, set_activating(false). WebView2's file picker returns focus on its own.
- **Phase:** Phase 3

### S-01 — Site opens as a separate window instead of overlaying the island with its own header

- **Mac:** `IslandRootView.swift:176-184, 608-621; NotchSite.swift:300-350; IslandTypes.swift:283-287` — NotchSiteView covers the whole 600×650 island (clipped to the island shape) and the IslandHeader is hidden and non-interactive. The card is 16pt continuous #141518 with a 3.5% stroke, padded 10 at the sides and bottom (≈580×598), under the island's under-page colour #141518.
- **Windows:** `web.rs:147-153, 212-237; views.ts:132-140` — A chrome-less 640-wide transparent window hangs beside the island card. The island keeps its normal header and card.
- **Fix:** Add a `web` view (600×600, large) whose island HTML is header + card. Hide #header for it. Put the child webview at island x+10, y+42, w−20, h−52 with a radius-16 region.
- **Phase:** Phase 3

### S-02 — Site header controls missing (back, mark, spinner, reload, open in browser, close)

- **Mac:** `NotchSite.swift:352-411` — The 34pt row 8pt from the top holds a chevron.left back button (only when canGoBack), a NotchSiteIcon 16pt tile with the page title (or host) as tooltip, and a small ProgressView at 0.6 scale in a 12×12 frame while loading, all with leading 14 and spacing 8. On the right, spacing 14 and trailing 16: arrow.clockwise reload, arrow.up.right (opens the current URL, or NotchSite.url, in the browser) and xmark (closeNotchSite). Buttons are 13pt #8E939C, #F5F6F8 on hover, 18×18 with an inset −5 hit area.
- **Windows:** `none` — None of these exist. The only way out is the globe again or folding the island.
- **Fix:** buildSite() in views.ts reuses the `.header-actions` CSS (13px, hover var(--ink)). Feed back/loading/title from Rust page events (on_page_load, on_document_title_changed, plus a history.length check by eval) and add commands site_back, site_reload and site_open_external (open the current webview.url() via platform::open_url).
- **Phase:** Phase 3

### S-03 — Opening the site from the ring disc doesn't hold the island, so the page is hidden as soon as it is reached

- **Mac:** `IslandEdgeAction.swift:72-73; IslandWindowController.swift:620-631, 1021-1035` — The disc posts hookExpand(.web), and the open site holds the island through viewHoldsIslandOpen.
- **Windows:** `island.ts:1115-1117 vs views.ts:113-116` — pressRingButton("site") calls Bridge.toggleSiteWindow() without setPinned. Moving the pointer onto the page leaves the island rect, mouseLeft schedules the 0.12s collapse, and setMode → hidePages removes the page.
- **Fix:** Immediate fix: `void Bridge.toggleSiteWindow().then(up => this.viewActions.setPinned(up === true))`. Proper fix: the disc calls this.setView("web") once the site is a view.
- **Phase:** Phase 3

### S-04 — Extra globe tab in the island header

- **Mac:** `IslandRootView.swift:719-734 (Home, Chat, Clipboard only)` — The site is reached only from its disc on the island's border. The left tab group is Home, Chat, Clipboard.
- **Windows:** `views.ts:132-140, 186` — A fifth left tab (globe, title "Site") sits after Clipboard and the Integrations grid tab.
- **Fix:** Remove tabSite from the header and leave the site on the edge ring, as on the Mac. The Integrations tab belongs to the header surface audit.
- **Phase:** Phase 4 — Site tab kept (owner), drawn the Mac way

### S-05 — Ring disc mark and tooltip differ (globe and "Site" vs NotchSiteGlyph and host name)

- **Mac:** `IslandEdgeRingView.swift:99-111; NotchSite.swift:62-112; IslandEdgeAction.swift:21` — The disc draws NotchSiteGlyph at side 34 on a #0E0F11 22pt circle in the tint. The glyph is a dot of radius 0.059·side plus two broken rings: radius 0.126·side, stroke 0.047·side, from 174° to 466°, and radius 0.221·side, stroke 0.050·side, from 227° to 452°, with round caps, degrees counter-clockwise from the right. The tooltip is NotchSite.hostLabel (the default site host).
- **Windows:** `island.ts:63-71; edgeRing.ts:194` — A generic globe (ICONS.globe) at 15px, with the tooltip "Site".
- **Fix:** Port NotchSiteGlyph/NotchSiteIcon as an SVG builder in views/logos.ts (PILL_LOGOS-style, so it keeps its own drawing). Tile #15191D, corner 0.212·side, border #303234 (#454A50 when highlighted), stroke max(0.5, 0.03·side), ink #888FA0 (#C3C9D6 when highlighted). Use new URL(siteUrl).host as the disc title.
- **Phase:** Phase 3

### S-06 — Site lifecycle: Mac loads fresh on each open and tears down on close; Windows loads at launch and lives forever

- **Mac:** `NotchSite.swift:172-221, 300-303, 349` — @StateObject NotchSiteWeb is built when the site opens (default data store, so sign-in persists). On disappear it calls stopLoading and loads a blank page so no script outlives the island. Every open reloads the site.
- **Windows:** `web.rs:146-153; lib.rs:1295` — The site URL is fetched at app launch and the page keeps running hidden all session. Reopening shows the old state. Changing the URL needs a restart.
- **Fix:** Create or navigate the site webview on open and navigate to about:blank (or close it) on close. Read site_url at open time, which also removes the restart note.
- **Phase:** Phase 3

### S-07 — Site navigation policy is stricter on Windows

- **Mac:** `NotchSite.swift:249-286` — Any http, https, about or blob navigation stays in the island. Other schemes are cancelled and handed to the system only if a link was clicked. A new-window request loads in the same view when it is a safe web URL.
- **Windows:** `web.rs:72-87, 111-126` — Only the configured host stays. Every other host opens in the browser, and new-window requests are swallowed.
- **Fix:** For SITE_LABEL, on_navigation allows scheme http/https/about/blob and calls platform::open_url only for other schemes. on_new_window navigates the same webview when the scheme is http/https and returns Deny.
- **Phase:** Phase 3

### S-08 — No site failure state

- **Mac:** `NotchSite.swift:321-339` — On a failed navigation the card shows the host label (13pt semibold), the error (11pt #8E939C, centred, max 360) and a "Try again" capsule.
- **Windows:** `none` — WebView2's error page appears, which matters when Tailscale is down because the default URL is a tailnet host.
- **Fix:** Same mechanism as WC-06, reusing the shared failure block.
- **Phase:** Phase 3

### S-09 — Editable Site URL field (Mac hard-codes NotchSite.url)

- **Mac:** `NotchSite.swift:14-18` — No setting: the site is the literal the default site URL.
- **Windows:** `settings/main.ts:915-946; settings.rs:135-140, 348-350` — Settings → Pages → Site text field with validation copy, applied on the next start.
- **Fix:** Either remove the field for strict parity, or keep it as a deliberate Windows extra and list it in the README. Recommend keeping it but moving it out of a "Pages" section that no longer exists on the Mac.
- **Phase:** kept — the Pages/Site field stays, Mac-styled, in Phase 1 (owner)

### WA-01 — WhatsApp "needs QR" is reported as a red failure

- **Mac:** `WhatsAppWebController.swift:52-62, 361-363; SettingsView.swift:1053-1061` — A separate needsQR state shows an orange chip reading "Waiting for the QR code to be scanned". A failure is red with its reason.
- **Windows:** `whatsapp.rs:260-264; settings/main.ts:474-488` — The `qr` event sets state "failed" with the detail "Scan the QR code in Settings to connect WhatsApp.", so the red failure colour and label show for something that isn't an error.
- **Fix:** Emit a dedicated status, e.g. "needs_qr", from whatsapp.rs and add it to CONNECTION_COLOR/CONNECTION_LABEL in settings (orange, t("Waiting for the QR code to be scanned"), already in the catalog). Keep the inbox hint string for the island.
- **Phase:** Phase 2

### WA-02 — No WhatsApp load deadline, retry backoff or crash recovery

- **Mac:** `WhatsAppWebController.swift:78, 312-342, 445-462` — If the page is still connecting after 60s it fails with "WhatsApp Web did not load" and reloads after 5s, doubling to 300s. Navigation failures do the same, and a terminated WebContent process reloads right away. retryDelay resets to 5 on connect.
- **Windows:** `whatsapp.rs:150-183 (supervisor only)` — The page is navigated once. A load that never connects or a failed navigation stays stuck in "connecting" with no retry. A WebView2 process failure is not handled.
- **Fix:** In whatsapp.rs add a 60s tokio deadline after navigate ("WhatsApp Web did not load" → set_state failed), exponential retry 5→300s while RUNNING, on_page_load error detection, and ICoreWebView2 ProcessFailed through with_webview → reload.
- **Phase:** Phase 2

### WA-03 — WhatsApp settings buttons and window title differ

- **Mac:** `SettingsView.swift:855-888; WhatsAppWebController.swift:285-295` — Not connected: a prominent "Connect WhatsApp" button, disabled while the sign-in window is up, plus "Unlink" only if the Mac was ever linked. Connected: "Show WhatsApp" and "Unlink". A small spinner shows while connecting. The window title is L("Connect WhatsApp").
- **Windows:** `settings/main.ts:440-472, 506; whatsapp.rs:82` — "Show QR code" and "Unlink" always show under a "Session" label, with no spinner. The window title is the literal "WhatsApp" and is not localized.
- **Fix:** Mirror the Mac's state-dependent buttons with the existing catalog keys "Connect WhatsApp", "Show WhatsApp" and "Unlink". Set the window title to t("Connect WhatsApp") via i18n.rs when showing the login.
- **Phase:** Phase 2

### WA-04 — WhatsApp links, downloads and media prompts handled differently

- **Mac:** `WhatsAppWebController.swift:431-443, 467-487` — New-window links and non-renderable responses open in the browser. Mic and camera are denied.
- **Windows:** `whatsapp.rs:79-103; lib.rs:1214-1222` — New-window requests are swallowed, downloads use WebView2's own flow, and mic/camera get WebView2's default prompt.
- **Fix:** Add on_new_window (open_url + Deny) and on_download (open_url + false) to the WhatsApp builder, and deny mic/camera for label "whatsapp" in on_permission_request.
- **Phase:** Phase 3

### PF-01 — Linux cannot host a positioned child webview

- **Mac:** `WebChatHostView.swift:11-35` — The WKWebView is a subview of the island.
- **Windows:** `tauri-runtime-wry-2.12.0/src/lib.rs:5187-5191; wry-0.57.0/src/webkitgtk/mod.rs:683-720, 963-985` — On Linux, Tauri packs child webviews into the window's GtkBox and set_bounds only positions inside a GtkFixed, so add_child cannot place ChatGPT over the card.
- **Fix:** Closest equivalent: keep a separate page window on Linux (cfg) but make it a layer-shell surface (or a transient window on GNOME) positioned exactly over the island's card rect. Use shadow off, background #141518, no decorations, and the same TS-drawn header and card underneath.
- **Phase:** Phase 3

### PF-02 — User agent and rounded clip can only be approximated

- **Mac:** `WebChatController.swift:53-57; WebChatHostView.swift:56` — Safari 27 UA. The page is clipped to an anti-aliased continuous (squircle) 16pt corner.
- **Windows:** `web.rs:43-46` — Edge 140 UA. A Win32 region cannot anti-alias or draw a squircle.
- **Fix:** Keep a current Edge UA; it is the right equivalent and should be bumped with WebView2. Use CreateRoundRectRgn at 16·scale over the island's own #141518 card so any aliasing falls on matching colour.
- **Phase:** Phase 3

## Already matches

- ChatGPT host allowlist: the same 8 hosts with dot-anchored suffix matching, and non-web schemes never stay (web.rs:30-70 vs WebChatPolicy.swift:9-40), mirrored by Rust unit tests web.rs:255-272.
- Main-frame-only filtering: WebView2 NavigationStarting is main-frame, matching the Mac's `targetFrame.isMainFrame` guard, so Turnstile and sign-in iframes are not gated.
- A disallowed main-frame navigation opens in the default browser (platform::open_url vs NSWorkspace.open).
- A browser-like UA is used so ChatGPT and WhatsApp do not reject the embedded view.
- The ChatGPT website is off by default (settings.rs:388 web_chat false; AppState useWebChat/webChatEnabled false).
- Same default site URL (state.ts:398, settings.rs:349 vs NotchSite.swift:15) and the same ring tint #38BDF8 (edgeRing.ts:194 vs IslandEdgeAction.swift:41).
- Page height 650 = IslandConst.defaultLargeSize.height (island.rs:90, asserted in island.rs:1621-1623). MESSAGE_EXPANDED_CAP 650 = fullBodyCap, parity-tested by tests/message-height-parity.ts.
- From the header path, the island holds itself open while a page is up (setPinned → fsm.pinned + heldOpen), close to viewHoldsIslandOpen → isHeldOpen.
- Pages go away on every exit from expanded (island.ts:562-566) and with the master switch (lib.rs:118-121), like the Mac's setMode screen reset and deactivate.
- Island content shell padding 8/10/10 (style.css:265-272) and header metrics (.tab 30×22 radius 11, .header-actions gap 14, padding-right 16, .close 18×18 with −5 hit inset) already match IslandContentView, IslandHeader and IslandHeaderIconButton, ready to reuse for the ChatGPT and site headers.
- `.typing` dots (style.css:1645-1670: 5px #6B7079, scale 0.6↔1.2, 0.14s stagger) already reproduce TypingDotsView, ready to reuse as the ChatGPT loading state.
- WhatsApp: same shared/whatsapp-bridge.js, hidden page running only while the pill is on and the machine is linked, its own data store cleared on Unlink, a 1000×720 sign-in window that hides 1.2s after connecting, the same message mapping (display name, summary chats, "📎 Sent a file"), the same send-error strings, and the same keep-in-webview rule.
- The Mac's NotchSiteLauncher (icon beside the notch) is dead code on the Mac, so correctly not ported.
- Settings strings already in i18n/catalog.json for the Mac block: "ChatGPT (website)", "Show ChatGPT in the notch", "Open it from the chat tab", the explainer, "Clear ChatGPT data", "Signs out and deletes the cookies…", "Big screen" and its explainer, "Connect WhatsApp", "Show WhatsApp", "Waiting for the QR code to be scanned", "WhatsApp Web did not load".

## Known differences in windows/README.md

- **closable** — README.md:250-257: "The site and ChatGPT are drawn inside the island on the Mac. Here each is a window of its own, anchored to the island… a second WebView2 inside the island's own is not something Tauri does without its unstable multiwebview feature." Closable on Windows now. The locked Tauri is 2.12.0, whose `unstable` feature exposes Window::add_child + WebviewBuilder (window/mod.rs:1229-1248), and Webview::set_bounds/hide/show/with_webview are public. Host ChatGPT and the site as child webviews of the island window over the card rect, clip with SetWindowRgn radius 16, and draw header, card, dots and failure states in island HTML (see the architecture section). Prerequisites: island.rs window() must stop using get_webview_window, and add_child must run off the sync command thread. Not closable on Linux (GtkBox packing): there the faithful equivalent is a borderless layer-shell or transient window placed exactly over the island's card, with the same TS chrome around it. The README line must then be rewritten as a Linux-only difference.
- **forced** — README.md:276-282: WhatsApp Web in a window of its own, hidden except for the QR, ringing by title change and drained with eval_with_callback rather than IPC. This is an implementation difference with no user-visible effect, and it is the safer design (no remote origin with IPC), so keep it. The user-visible parts can be closed: the needs-QR state (WA-01), retry and timeout (WA-02), button copy and window title (WA-03), and link/download/permission handling (WA-04).
- **closable** — README.md:102 usage table: "Esc — Closes the island" (implicitly not while a page is up). Make Escape close a screen like the Mac's closeScreen(): catch VK_ESCAPE through the WebView2 controller's AcceleratorKeyPressed and route it to island.closeScreen() (WC-11).
- **forced** — README.md:226-229 / 230-240: no notch, so the island lives against a screen edge (bottom-right by default). Platform-forced, but it does not stop the page living in the island. At a bottom anchor the island grows upward to 600×650 holding ChatGPT, the mirror image of the Mac growing down from the notch. PANEL_H 700 already fits 650 plus a 44px ring row; raise it if the Big-screen height (up to 800) is ported.

## Parity tests to add

- webChatAllowedHosts (WebChatPolicy.swift:9-18) vs CHAT_HOSTS (web.rs:30-39): dump the Swift set sorted and compare with the Rust array in a script. Today only each side's own unit tests cover it (scripts/test-webchat-policy.sh is Swift-only).
- isChatGPTHost/webChatKeepsInIsland truth table (accepted/rejected URLs from tests/WebChatPolicyTests.swift) run against web.rs keeps_in_window.
- IslandConst.defaultLargeSize (600×650), viewLayouts[.web] (600, 600, large, botDiameter 0) and viewLayouts[.webchat] (600, 650, large) vs the new TS VIEW_LAYOUTS web/webchat. Also islandSize(.expanded, .web/.webchat, large:) for a grid of largeIslandWidth/Height vs TS islandSize.
- AppState.largeWidthRange 360…600 and largeHeightRange 240…800 vs the TS/Rust setting ranges.
- WebChatIslandView metrics (header 34, top 8, row padding 14, card radius 16, card inset 10+10, fill #141518, stroke white 0.035, title 12 semibold, button 11 medium 18×18, Mochi 34) and NotchSiteView metrics (card 16, inset 10, header buttons 13pt, trailing 16, leading 14): lift them into a Swift `ScreenLayout` enum and dump. These are hand-copied today with no test.
- Card rect formulas: webchat (x+20, y+84, w−40, h−104) and site (x+10, y+42, w−20, h−52), computed in Swift from those constants and checked against the TS function that feeds page_bounds.
- WebChatController.coldTTL (600s) and holdMouseBriefly (0.35s) vs Rust/TS constants.
- WhatsAppWebController loadTimeout 60s, retryDelay 5→300 doubling, login close delay 1.2s vs whatsapp.rs constants.
- NotchSiteGlyph/NotchSiteIcon ratios and colours (dot 0.059, rings 0.126/0.221, strokes 0.047/0.050, arcs 174–466 and 227–452, tile #15191D, corner 0.212, border 0.030, ink #888FA0/#C3C9D6, border #303234/#454A50, disc #0E0F11 22pt) vs the TS SVG port.
- IslandEdgeAction.site colorHex/title (hostLabel) vs edgeRing.ts EDGE_ACTIONS site entry.
- WhatsAppRules.keepsInWebView (Swift) vs message_proto::whatsapp_keeps_in_webview (Rust): shared URL truth table. scripts/test-whatsapp-rules.sh is Swift-only.
- The i18n check should flag the Mac page strings missing from i18n/catalog.json: "ChatGPT is refusing the built-in browser (HTTP %@).", "Open it in your browser instead, or try again.", "Could not reach ChatGPT." and "✓ ChatGPT data cleared — you are signed out.". They are passed through variables or interpolation, so extract-swift-strings.mjs misses them.

## Risks

- Adding a child webview to the island window makes `app.get_webview_window("island")` return None (tauri lib.rs:603-611: is_webview_window() is false once a webview's label differs from the window's). island.rs:485-487 window(), and every caller in island.rs, lib.rs, shortcut.rs and platform/*, must move to get_window plus get_webview first, or the island stops being placed, polled and click-through-toggled.
- Window drag-drop events switch from labeled-webview emits to emit_to_window when the window has several webviews (tauri manager/window.rs:205-270). The island's getCurrentWebview().onDragDropEvent (bridge.ts:470-472) must be re-verified, and the file-drop-onto-island flow tested again.
- On Windows, add_child and WebviewBuilder::build deadlock when called from a synchronous command or event handler (window/mod.rs:1186-1189). Create the child from an async command or a spawned thread, and only on the main thread via add_child's run_on_main_thread.
- web.rs and lib.rs record that a WebView2 created after the island's comes up blank when browser args differ. A lazily created child must pass exactly crate::BROWSER_ARGS. Test cold creation after launch; fall back to creating at launch on about:blank if needed.
- A separate data_directory for ChatGPT (needed for clear-data and for a per-profile dark colour scheme) creates a second WebView2 environment and browser process in the same top-level window. This is expected to work (WhatsApp already does it as a window) but must be verified for child controllers. Memory cost is about 300-600 MB while warm, which is why the 600s cold timer matters.
- Capabilities are matched by window label: capabilities/default.json grants "island" core:default, which would cover webviews inside that window. Remote origins (chatgpt.com) get no IPC unless `remote.urls` is configured. Keep it that way, and prefer scoping the capability with `webviews: ["island"]` so the child is excluded explicitly.
- Airspace: no island HTML can render over the child HWND. Every overlay (dots, failure, the countdown hairline, snow, Mochi glow, a ring disc overlapping the card) must sit outside the card rect or appear only while the child is hidden. Sending set_bounds every frame during the open/close spring would jank; show the child only after the spring settles and hide it at the start of a shrink, which matches the Mac's fade-in-after-load and 0.12s fade-out.
- Click-through: WS_EX_TRANSPARENT toggling by the cursor poll (island.rs:1195-1236) covers the child as part of the same top-level, which is good. A momentum scroll or drag-select that leaves the island loses the mouse once the poll flips. The poll already keeps the panel live while the left button is down; add a short post-wheel hold like the Mac's holdMouseBriefly if users notice.
- tao rewrites GWL_EXSTYLE on every apply_diff (platform/windows.rs:263-278), and set_focusable toggling for typing goes through tao. The child's SetWindowRgn is on the WRY_WEBVIEW child HWND, not the top-level, so tao will not reset it, but it must be re-applied after every set_bounds.
- The `unstable` API surface can change between Tauri minors. Pin tauri to 2.12.x in Cargo.toml when enabling it.
- Mac detail not to port blindly: WebChatController.holdsMouse's setter is only ever set to false (IslandWindowController.swift:1376), so only the scroll-momentum hold is real. NotchSiteLauncher and NotchSiteGeometry.islandSize/panelSize (full-screen site sizing) are unused on the Mac.
- Behaviour change for current Windows users: making the chat tab a view instead of a toggle, and removing the header globe tab, changes muscle memory. Switching ChatGPT to its own profile signs current users out of ChatGPT once.
