# Parity — Feature views

The Mac is the source of truth (see `CLAUDE.md`). Each gap names the Mac code, the Windows code and the fix; tick it in the PR that closes it. Audit of 2026-11-20 against `notchy` at f1dee26.

## Checklist

- [x] **NP-1** · high · behaviour · S — Now Playing reader is gated on the pill instead of the master switch — _Phase 8_
- [x] **NP-2** · high · missing on windows · M — Volume row (mute + level slider) missing from the Now Playing card — _Phase 8_
- [ ] **CB-1** · high · visual · S — Clipboard window is square and flat — no 16px rounded panel, hairline or shadow — _Phase 8_
- [ ] **UP-1** · high · extra on windows · S — Choose card has an extra 'Cancel' button — _Phase 8 — Cancel kept (owner), drawn the Mac way_
- [x] **NP-3** · medium · visual · S — Right-hand column is vertically centred with uniform 6px gaps instead of Mac's top/bottom spread — _Phase 8_
- [x] **NP-4** · medium · visual · M — Source badge shows a coloured initial instead of the app's real icon — _Phase 8_
- [x] **NP-5** · medium · behaviour · S — Title/artist cleaners (shortTitle/shortArtist) not ported — _Phase 8_
- [ ] **HY-1** · medium · extra on windows · S — Hydration intro shows an extra glass and a cyan wash — _Phase 8_
- [ ] **HY-2** · medium · visual · S — Goal-reached washes are ice-blue instead of green — _Phase 8_
- [ ] **HY-3** · medium · extra on windows · S — Paused reminders turn the water and the dot grey (Windows only) — _Phase 8_
- [ ] **HY-4** · medium · visual · S — Main card geometry: glass column, gaps and insets differ — _Phase 8_
- [ ] **HY-6** · medium · visual · S — Streak (goal reached) card dimensions differ — _Phase 8_
- [ ] **HY-7** · medium · behaviour · S — Next-mark progress uses a different formula and disappears after 365 days — _Phase 8_
- [ ] **HY-9** · medium · visual · S — Reminder (sip) card sizes, name styling and slide-in differ — _Phase 8_
- [ ] **HY-10** · medium · missing on windows · S — Default name is not taken from the OS account — _Phase 8_
- [ ] **TM-1** · medium · copy · S — Timer strings not localized — _Phase 8_
- [ ] **TM-2** · medium · visual · S — Running timer: clock size, paused dimming, padding — _Phase 8_
- [ ] **CB-2** · medium · behaviour · S — Clipboard window opens centred instead of under the island on the active display — _Phase 8_
- [ ] **CB-3** · medium · behaviour · S — Clicking outside does not dismiss the clipboard window; not draggable; resizable — _Phase 8_
- [ ] **CB-4** · medium · behaviour · M — Image entries cannot be copied back (row still says 'Copied') and image favourites are not persisted — _Phase 8_
- [ ] **CB-5** · medium · copy · S — Clipboard row/meta copy is hard-coded English and 'Just now' casing differs — _Phase 8_
- [ ] **UP-2** · medium · copy · S — Drop/upload/choose strings are not localized on Windows — _Phase 8_
- [ ] **UP-3** · medium · missing on windows · M — Upload canvas ignores the Mochi character (hats, eyes, body shape) — _Phase 8_
- [x] **NP-6** · low · behaviour · S — Mini Mochi on the artwork does not dance while music plays — _Phase 8_
- [x] **NP-7** · low · visual · S — Time labels use a monospace font instead of system font with tabular digits — _Phase 8_
- [x] **NP-8** · low · extra on windows · S — Transport buttons have hover circles, press scale and tooltips the Mac lacks; skip dial size differs — _Phase 8_
- [x] **NP-9** · low · behaviour · S — Elapsed extrapolation ignores playback rate; no 'unavailable' message — _Phase 8_
- [x] **NP-10** · low · behaviour · S — Mini Mochi badge is decided once at build time — _Phase 8_
- [ ] **HY-5** · low · visual · S — Main card control sizes and spacings drift from Mac — _Phase 8_
- [ ] **HY-8** · low · extra on windows · S — Week discs: today is bold and its frozen disc gets a ring + pop (Windows only); rest dots styled differently — _Phase 8_
- [ ] **HY-11** · low · copy · S — Hydration copy differences (tooltip order, durations, 'Logged' amount) — _Phase 8_
- [ ] **HY-12** · low · behaviour · S — Store behaviour drifts: prompt not cleared on tab switch, busy check, unsnooze — _Phase 8_
- [ ] **HY-13** · low · visual · S — Goal confetti geometry differs — _Phase 8_
- [ ] **HY-14** · low · visual · S — Glass animation and mini glass are CSS approximations — _Phase 8_
- [ ] **AG-1** · low · visual · S — Agenda header controls styled as island tabs; Updated label size/format — _Phase 8_
- [ ] **AG-2** · low · visual · S — Agenda padding, empty state layout and past-row colours — _Phase 8_
- [ ] **AG-3** · low · behaviour · S — Heads-up highlight lifetime and failure text — _Phase 8_
- [ ] **TM-3** · low · behaviour · S — Timer picker: drag-to-nudge missing, wheel added; Reset/Start glyphs — _Phase 8_
- [ ] **CB-6** · low · visual · S — Clipboard glyphs, empty-state position, tooltips and copy sound — _Phase 8_
- [ ] **UP-4** · low · platform forced · M — Swallowed file uses a generic sheet instead of the real file icon — _Phase 8_
- [ ] **UP-5** · low · behaviour · S — Fallback Uploading/Choose views drift (static progress, label, sizes) — _Phase 8_
- [ ] **UP-6** · low · extra on windows · S — Dropping a file resets the chat history on Windows only — _Phase 8 — Mac fix proposed, awaits the owner's yes_
- [x] **XM-1** · low · visual · S — Christmas cover uses the 320x180 thumbnail only — _Phase 8_
- [ ] **ATO-1** · low · visual · S — Ato badge text font differs — _Phase 8_
- [ ] **SN-1** · low · visual · S — Thrown snow flakes fade by alpha in flat white; layers pop instead of fading — _Phase 8_
- [x] **XM-2** · low · visual · S — Christmas album transitions and badge placement approximate — _Phase 8_

## How each side is built

MAC (SwiftUI, every IslandView body built at once, inactive ones opacity 0; singletons own clocks):
- IslandViewContent.swift dispatch: .overview -> OverviewView (homeShowsPlayer ? NowPlayingCardView : homeChoice{.timer -> FocusTimerView, message kinds -> HomeMessageView, .claudeCode -> focusedPill -> IntegrationCardView which for integration_music hosts NowPlayingCardView(drawsBackground:false)}); .upload/.uploading/.choose -> UploadView/UploadingView/ChooseView (fallbacks under UploadCanvasView, which owns the whole 640x176 body while UploadSequenceEngine.isActive); .timer -> FocusTimerView; .hydration -> HydrationView; .sip -> HydrationSipView; .agenda -> AgendaView. Clipboard is NOT an island view: ClipboardPanelController opens a borderless 380x460 NSPanel (ClipboardPanelView). Snow: IslandSnowLayer (bank, Shape+Canvas, own Timer) + IslandSnowfallLayer (TimelineView 30fps, .screen blend). Ato: BotCanvasView/MiniBotCanvasView draw AtoBotView over a BotEngine whose reactions Ato wears.
- NowPlayingCardView tree: ZStack{CardBackground(nil); HStack(14){[ChristmasAlbumView 52x108], artwork 108x108 r12 (+source badge 22 bottom-left, mini Mochi 28 bottom-right), VStack(0){titleRows(title 13 semibold / artist 11.5 · source 11), Spacer>=6, scrubber(bar 4 + 5 + times 10 mono-digit), Spacer>=8, transport HStack(18) [skipBack, prev 13, play 17, next 13, skipFwd], Spacer>=8, volumeRow(speaker + 4pt bar)]} padding 14/12}. Data: MusicController (follows master switch, cleans titles) <- NowPlayingController (MediaRemote via perl adapter) | ChristmasMusicPlayer (offscreen WKWebView).
- HydrationView: intro | main (glass 96 + portion pill | header row[Who, weekDots, StreakPill, pause 20] / count 26 / message / portions / log) | streak card (Who / flake+headline 24 / weekDiscs 26 / next-mark bar 84 + rest pill | glass 62 + total + Undo). HydrationSipView: Who + title/sub/buttons | glass 46 + total. CompactHydrationCue. Store: HydrationStore singleton (UserDefaults JSON).
- AgendaView: header(Mochi seat 26, calendar, 'Agenda · today', Updated, refresh 22, open 22) + ScrollView of AgendaRow; AgendaClient owns polling/heads-up.
- FocusTimerView: idle = picker (3 tiles 54x42 + Start/Reset) + presets column; running = header row + 4pt bar + Secondary buttons.

WINDOWS (Tauri, vanilla TS, views built once and kept, sync()/tick() from island frame loop):
- views/views.ts buildOverview hosts four 'home faces' (timer, message, player=buildNowPlaying, pill) swapped by homeKind(); buildTimer lives inside views.ts (there IS a Focus timer view on Windows, tab 'timer' + Home 'timer'). views/nowplaying.ts mirrors the NP card as DOM (.np flex row: .np-xmas, .np-art, .np-main column with justify-content:center gap 6 — no volume row). views/hydration.ts: buildHydration (intro/main/streak), buildSip, buildCompactSip; glass is inline SVG + CSS animations. views/agenda.ts reuses the message-list classes (.msg-head/.msg-list/.tab). views/upload.ts: buildUpload/buildUploading/buildChoose fallbacks; upload/canvas.ts + upload/sequence.ts are a line-for-line port of UploadCanvasView/UploadSequenceEngine (sequence is faithful; canvas omits MochiDress + file icon and adds a Cancel button). Clipboard is a separate Tauri window (clipboard.html + clipboard/main.ts + clipboard.css; Rust clipboard.rs poller + lib.rs window). Snow: island/snowLayer.ts (two canvases) over island/snow.ts arithmetic. Ato: ato/view.ts + ato/bot.ts (port, drawn by island + minibots). Data: media.rs (GSMTC poll 1 s, gated on the Now Playing PILL) -> island/media.ts -> State.media; island/christmasMusic.ts (hidden YouTube iframe); core/hydrationStore.ts (localStorage, shared with Settings window); island/agenda.ts + agenda.rs; core/timer.ts.
Mirroring quality: logic twins (hydration rules, snow, Ato pose, agenda rules, upload sequence, timer store, Christmas player) are close ports; the DOM/CSS views are hand-copied approximations with many small numeric drifts, several Windows-only embellishments, missing i18n on hard-coded strings, and a few missing features (volume row, title cleaning, app icons, character dress in the drop canvas, rounded/anchored clipboard window).

## Gaps

### NP-1 — Now Playing reader is gated on the pill instead of the master switch

- **Mac:** `NotchBuddy/Sources/App/MusicController.swift:110-127` — MediaRemote reader starts whenever Notchy is enabled (AppState.isEnabled); the pill only decides whether music gets its own pill. Home on automatic shows the player whenever anything plays.
- **Windows:** `windows/src-tauri/src/media.rs:77-88,106-115 (and README claim at media.rs:8-9)` — media.rs `enabled()` requires settings.enabled AND active_integrations contains integration_music; with the pill off nothing is read, State.media stays empty, homeShowsPlayer never turns on and Mochi never dances.
- **Fix:** In media.rs change `enabled()` to `settings.enabled` only (keep MUSIC_PILL for naming). media_command likewise. Update the file header comment. Keep the 1 s poll; clear the card when the master switch turns off (already done by the was_enabled branch).
- **Phase:** Phase 8
- **Done:** media.rs `enabled()` is `settings.enabled` alone, for the poll and `media_command`; the header says so.

### NP-2 — Volume row (mute + level slider) missing from the Now Playing card

- **Mac:** `NotchBuddy/Sources/App/NowPlayingCardView.swift:107-110,261-296` — Under the transport, when the output device has a volume: speaker.fill / speaker.slash.fill 10pt #8E939C (14 wide) button toggling mute, then a 4pt capsule track white .10 with #D6DAE1 fill, 14pt hit height, drag sets level live; Spacer(minLength 8) above it.
- **Windows:** `windows/src/views/nowplaying.ts:160 (main column has no volume row)` — No volume control at all.
- **Fix:** Add Rust commands volume_get/volume_set/volume_mute using IAudioEndpointVolume (windows crate Win32_Media_Audio_Endpoints: GetMasterVolumeLevelScalar/SetMasterVolumeLevelScalar/GetMute/SetMute on the default render endpoint); return null when the endpoint has no volume (mirrors SystemVolume.level == nil). In nowplaying.ts append .np-vol row (button 14px wide, svg speaker 10px, track height 4 radius 2 bg rgba(255,255,255,.10), fill #d6dae1, pointer-capture drag like the scrubber). Linux: hide the row (no dependency) until a PulseAudio backend exists.
- **Phase:** Phase 8
- **Done:** `windows/src-tauri/src/volume.rs` (volume_get / volume_set / volume_set_muted over the default render endpoint's IAudioEndpointVolume; `None` without an output; off zero un-mutes). The row in `views/nowplaying.ts` (speaker.fill / speaker.slash.fill drawn in their SF frames, 14 wide, #8E939C; 4 pt track white .10 / #D6DAE1 in a 14 pt hit area; pointer-capture drag that writes one level at a time; re-read when the card comes up and every 0.5 s while it plays). Linux: no row.

### NP-3 — Right-hand column is vertically centred with uniform 6px gaps instead of Mac's top/bottom spread

- **Mac:** `NotchBuddy/Sources/App/NowPlayingCardView.swift:101-111,231-254,298-341` — VStack(spacing 0) fills the artwork height: titleRows (title->artist spacing 2) at the top, Spacer(minLength 6), scrubber (bar, then 5pt, then times), Spacer(minLength 8), transport, [Spacer 8, volume] at the bottom.
- **Windows:** `windows/src/style.css:2478-2485,2513-2541; windows/src/views/nowplaying.ts:160` — .np-main is justify-content:center with gap 6px between title, sub, bar, times, transport; the bar carries 6px padding top/bottom so bar->times visual gap is ~12px (Mac 5) and title->artist is 6 (Mac 2).
- **Fix:** Make .np-main height:108px; justify-content:space-between; gap:0. Wrap title+sub in a block with gap 2px; wrap bar+times in a block (bar hit padding via ::before or negative margins so the visual gap to .np-times is 5px); keep transport (and the new volume row) at the bottom with min 8px separation.
- **Phase:** Phase 8
- **Done:** .np-main stretches to the card's height (not 108: SwiftUI's VStack takes the HStack's 115) with flex spacers of minimum 6/8/8 that share the rest; titles 15.5 + 2 + a 16.7 row (the dot is in the island's 14 pt); the bar's hit area is an overlay. Against a 2x capture of the Mac's card every row is within 0.5 pt: bar top 55.5, transport centre 94.7, volume centre 120 (Mac 119.5), art at 80/15.5, title at 202/12.

### NP-4 — Source badge shows a coloured initial instead of the app's real icon

- **Mac:** `NotchBuddy/Sources/App/NowPlayingCardView.swift:178-194; MusicController.swift:69-75,84-89` — 22pt #0B0C0E disc with the playing application's real icon at 16x16 (NSWorkspace icon); fallback music.note 9pt semibold #8E939C directly on the dark disc.
- **Windows:** `windows/src/views/nowplaying.ts:61-79,256-267; windows/src/style.css:2453-2469` — 18px coloured disc (brand tint table, #2A2E35 default) with the first letter of the source name in 600 10px white; fallback still paints the #2A2E35 inner disc.
- **Fix:** In media.rs resolve an icon once per source_id and add `sourceIcon: data:` to MediaState: packaged AUMIDs via Windows.ApplicationModel.AppInfo::GetFromAppUserModelId -> DisplayInfo().GetLogo(Size{16,16}); exe AUMIDs (Spotify.exe, chrome.exe) by finding the running process image path (QueryFullProcessImageNameW) and SHGetFileInfoW/ExtractIconExW -> PNG. Draw it as a 16px <img> on the 22px #0b0c0e disc; fallback = music note 9px #8e939c with no inner tint disc. Keep sourceTint only if the icon lookup fails.
- **Phase:** Phase 8
- **Done:** `windows/src-tauri/src/media_app.rs`: AppInfo's logo for packaged AUMIDs, the running executable's icon (SHGetFileInfoW → HICON → PNG) otherwise; resolved once per source in the poll and sent as `sourceIcon`. Drawn at 16 on the 22 disc; without one, music.note at 9 pt semibold #8E939C (`npGlyphs.ts`). The Christmas music carries Notchy's own icon. `sourceTint` is gone.

### NP-5 — Title/artist cleaners (shortTitle/shortArtist) not ported

- **Mac:** `NotchBuddy/Sources/App/MusicController.swift:155-156,187,390-423` — Title cut at the first " - " and trailing (...) / [...] groups stripped repeatedly; artist cut at " feat." / " ft." (case-insensitive). Applied to system tracks and the Christmas title. The pill name uses the cleaned title.
- **Windows:** `windows/src/island/media.ts:36-47; windows/src-tauri/src/media.rs:210-215` — Raw GSMTC title/artist shown, e.g. "Song - 2011 Remaster (Live)"; pill label uses the raw title.
- **Fix:** Port shortTitle/shortArtist into a pure TS module (e.g. core/mediaText.ts) and apply in island/media.ts apply() before State.setMedia (and in ChristmasMusic.media()). Add a parity test that dumps Swift outputs for a fixed list of titles.
- **Phase:** Phase 8
- **Done:** `MediaText.swift` (the Mac's cleaners, moved unchanged) and `windows/src/core/mediaText.ts`, compared over 27 inputs by `scripts/test-media-text.sh`. Applied in `island/media.ts` (where `hasTrack` now means a title, as `musicHasTrack` does) and to the Christmas title.

### NP-6 — Mini Mochi on the artwork does not dance while music plays

- **Mac:** `NotchBuddy/Sources/App/NowPlayingCardView.swift:201-210; BotCanvasView.swift:224` — MiniBotCanvasView(isDancing: state.musicPlaying) — the badge Mochi dances to the track.
- **Windows:** `windows/src/views/nowplaying.ts:97-104; windows/src/mochi/minibots.ts:30-60,94-117` — createMiniBot never calls engine.setDancing; the badge Mochi idles.
- **Fix:** Give minibots an optional dancing predicate (e.g. createMiniBot(task, 23, { dancing: () => State.media.isPlaying })) and call mb.engine.setDancing(...) in tickMiniBots before update.
- **Phase:** Phase 8
- **Done:** `createMiniBot(task, 23, { dancing })`; `tickMiniBots` sets it each frame. The card's Mochi also wears his character from the start.

### NP-7 — Time labels use a monospace font instead of system font with tabular digits

- **Mac:** `NotchBuddy/Sources/App/NowPlayingCardView.swift:338-339` — .system(size:10).monospacedDigit(), #6B7079.
- **Windows:** `windows/src/style.css:2535-2541` — font: 400 10px var(--mono) (Cascadia Mono/Consolas).
- **Fix:** font: 400 10px var(--font); font-variant-numeric: tabular-nums.
- **Phase:** Phase 8
- **Done:** 400 10px var(--font) with tabular-nums, #6B7079.

### NP-8 — Transport buttons have hover circles, press scale and tooltips the Mac lacks; skip dial size differs

- **Mac:** `NotchBuddy/Sources/App/NowPlayingCardView.swift:343-405` — Plain SF symbols (#F1F2F4) with no background/hover; only the skip buttons have .help("Back Ns"/"Forward Ns"); skip glyph 14pt; exact SF numbered dial for 5/10/15/30/45/60/75/90 else number 7pt semibold.
- **Windows:** `windows/src/style.css:2550-2563; windows/src/views/nowplaying.ts:135-137,329-336,350` — 24px round buttons with rgba(255,255,255,.08) hover and scale(.94) active; titles Previous/Play/Pause/Next; skip icon drawn at 15px with the number always at font-size 10 in a 24 viewBox.
- **Fix:** Remove .np-btn:hover background and :active transform; drop title on prev/play/next; call skipIcon(..., 14).
- **Phase:** Phase 8
- **Done:** No hover disc, no press scale, no title on previous/play/next. Every glyph on the card is drawn in its SF frame (`views/npGlyphs.ts`), fitted against the Mac's render at 16x: transport and speakers overlap the Mac's ink by 0.989–0.998, the notes 0.986, the snowflakes 0.95–0.97. The skip number sits where SF's own digits do. Frames land within 0.5 pt of the Mac's (skip back 325.25 vs 325.75, pause 397.25 vs 397.5, skip forward 467.25 vs 467.25).

### NP-9 — Elapsed extrapolation ignores playback rate; no 'unavailable' message

- **Mac:** `NotchBuddy/Sources/App/MediaPlaybackState.swift:60-65; NowPlayingCardView.swift:86-87` — estimatedTime multiplies elapsed wall time by playbackRate; if the media adapter is missing the card shows controller.unavailableReason instead of 'Nothing playing.'.
- **Windows:** `windows/src/views/nowplaying.ts:42-51,227-232` — Rate assumed 1 (1.5x podcasts drift until the next 1 s sample); Linux/no-GSMTC always shows 'Nothing playing.'.
- **Fix:** Read GetPlaybackInfo().PlaybackRate() in media.rs, add `rate` to MediaState and multiply in estimatedElapsed. Optionally emit an `unavailable` reason on Linux.
- **Phase:** Phase 8
- **Done:** media.rs reads `PlaybackRate` into `MediaState.rate`; `estimatedElapsed` and the poll's seek detector multiply by it.

### NP-10 — Mini Mochi badge is decided once at build time

- **Mac:** `NotchBuddy/Sources/App/NowPlayingCardView.swift:158-160` — Badge shown whenever !hideCharacters, reacting live to the setting.
- **Windows:** `windows/src/views/nowplaying.ts:97-104; windows/src/style.css:2900-2903` — If the app starts with characters hidden the badge is never created, so turning characters back on leaves the corner empty until restart.
- **Fix:** Always create the badge element; create/release the mini bot lazily in paintTrack based on State.settings.hideCharacters.
- **Phase:** Phase 8
- **Done:** The badge slot is always there; Mini Mochi is made while the card is on screen with the characters on, and released otherwise.

### XM-1 — Christmas cover uses the 320x180 thumbnail only

- **Mac:** `NotchBuddy/Sources/App/ChristmasMusicPlayer.swift:246-261` — Tries i.ytimg.com maxresdefault.jpg first, then mqdefault.jpg.
- **Windows:** `windows/src/island/christmasMusic.ts:31-32; windows/src/views/nowplaying.ts:239` — Always mqdefault.jpg — visibly softer at 108px on a 2x display.
- **Fix:** Use maxresdefault.jpg with an onerror fallback to mqdefault.jpg for both the album slot image and ChristmasMusic.media().artwork.
- **Phase:** Phase 8
- **Done:** `loadChristmasArtwork()`: maxresdefault first, kept only when it is not YouTube's 120 x 90 placeholder; mqdefault until then. One URL for the album and the main art.

### XM-2 — Christmas album transitions and badge placement approximate

- **Mac:** `NotchBuddy/Sources/App/NowPlayingCardView.swift:95-99,115-116; ChristmasAlbumView.swift:39-50,64-66,76,80-92` — Insert: move from leading + opacity; remove: scale 1.3 anchored trailing + opacity; spring(0.38, 0.85). Hover spring(0.3, 0.8). Snowflake 26 semibold white .9 on the sleeve. Badge (20 disc #0B0C0E, 15 disc #D23A4A, snowflake 8 bold) is inside the 3D-rotated album at offset (-5,+5) from its bottom-left.
- **Windows:** `windows/src/style.css:2339-2416; windows/src/views/nowplaying.ts:112-119` — Width/margin/opacity CSS transition 0.38s; no scale-out; snowflake svg 24 stroke 2; badge sits un-rotated at left 2px/bottom 16px of the slot.
- **Fix:** Add transform: scale(1.3) with transform-origin right to the folding state; move .np-xmas-badge inside .np-xmas-cover's rotated parent (positioned at left:-5px; bottom:-5px of the cover, overflow visible); snowflake 26px.
- **Phase:** Phase 8
- **Done:** The album is tilted with `perspective(132px) rotateY(-38deg)` about its trailing edge — the Mac's rotation3DEffect(perspective 0.5) on a 66 pt view; its far edge comes out 52 tall, as on the Mac. Hover -24° and 1.05. Insertion from the left with opacity; removal to scale 1.3 at the trailing edge with opacity. Snowflake 26 pt semibold. The badge rides on the cover at (-5, +5) from its bottom-left (projected 24–33.5 x 83–100 against the Mac's 25.5–32 x 85–98.5).

### HY-1 — Hydration intro shows an extra glass and a cyan wash

- **Mac:** `NotchBuddy/Sources/App/HydrationView.swift:352,379-394` — Card has no wash while !enabled; content is text only: Who (no detail), title 15 semibold, sub 13 #9398A1, buttons (spacing 7) with VStack spacing 8 and +4 top on the buttons.
- **Windows:** `windows/src/views/hydration.ts:300-325,537; windows/src/style.css:3092-3098` — A 58px glass at 55% sits in a 112px right column and the card gets WASH_WATER; text gap 5px, actions margin-top 6.
- **Fix:** Remove introGlass and its .hy-side; set --wash to WASH_NONE for the intro; .hy-intro gap 8px, .hy-intro .actions margin-top 4px, .actions gap 7px.
- **Phase:** Phase 8

### HY-2 — Goal-reached washes are ice-blue instead of green

- **Mac:** `NotchBuddy/Sources/App/HydrationView.swift:352,696; IslandViewContent.swift:1976-1983` — Streak card: celebrates -> .green (#34D399 @ .5). Sip card prompt .goal -> .green. Main card: celebrates (estimated goals only) -> green, paused/disabled -> none, else cyan (#22D3EE @ .38). CardBackground has no 'ice' wash.
- **Windows:** `windows/src/views/hydration.ts:26-28,485,526,648` — Streak card and sip-goal use WASH_ICE rgba(125,211,252,.36); main turns green for estimated AND target goals (goalReached()).
- **Fix:** Delete WASH_ICE; streak card and sip 'goal' use WASH_REACHED; main uses Hydration.celebrates (not goalReached) for the green wash.
- **Phase:** Phase 8

### HY-3 — Paused reminders turn the water and the dot grey (Windows only)

- **Mac:** `NotchBuddy/Sources/App/HydrationView.swift:401,434,270-283` — Glass is always #22D3EE and the Who dot always #22D3EE; pause only changes the message, the wash (none) and the pause glyph.
- **Windows:** `windows/src/views/hydration.ts:21-23,452,456` — Liquid and dot switch to #94A3B8 while paused.
- **Fix:** Remove LIQUID_PAUSED usage: glass.setColor(LIQUID) and whoDot background LIQUID always.
- **Phase:** Phase 8

### HY-4 — Main card geometry: glass column, gaps and insets differ

- **Mac:** `NotchBuddy/Sources/App/HydrationView.swift:362-364,398-411,429-430` — Leading pad lead(108, flush 18), trailing 18, vertical 12; glass 96 wide with portion pill under it (VStack spacing 7); HStack spacing 20 to the text (text starts at x=224).
- **Windows:** `windows/src/views/hydration.ts:328-331; windows/src/style.css:3072-3079,3088-3090,3139-3180` — Glass 100 inside a 108px button (padding 4/2/2) then text padding-left 18 (text at x=234), trailing 14; no vertical padding; glass button lifts 2px on hover; .no-mochi left pad 16.
- **Fix:** buildGlass(96); .hy-glass-btn width:auto; padding:0; gap 7px; remove :hover transform; .hy-main padding:0 18px 0 20px (or wrap gap 20); .hy-wrap padding:12px 0 12px 108px; .no-mochi .hy-wrap padding-left 18px.
- **Phase:** Phase 8

### HY-5 — Main card control sizes and spacings drift from Mac

- **Mac:** `NotchBuddy/Sources/App/HydrationView.swift:285-301,443-478,521-579` — Pause 20x20 circle bg .08 glyph 8 bold, no hover; count row top 4; message top 2 (lineLimit 2); portions top 9, chips h24 padding 10; log top 8; Undo h26 icon arrow.uturn.backward 9.5 bold; entry chip x button 16 (glyph 6.5 heavy), padding l9 r4; StreakPill flake 12; StreakPill unlit bg Ice.light(#9EDCFF) @ .16.
- **Windows:** `windows/src/style.css:3374-3548; windows/src/views/hydration.ts:336,471,246` — Pause 22x22 glyph 10 + hover .15; count margin 5 + letter-spacing -0.02em; msg margin 3 (no clamp); portions margin 11, chips h26 padding 11 + active scale; log margin 10, undo h28 icon 13; entry button 18 (glyph 8), padding r3; streak flake 13; unlit bg rgba(125,211,252,.16).
- **Fix:** Set .hy-round 20x20 glyph svg 8, remove hover; .hy-count-row margin-top 4, drop letter-spacing; .hy-msg margin-top 2 + -webkit-line-clamp:2; .hy-portions margin-top 9; .hy-chip height 24 padding 0 10; .hy-log margin-top 8; .hy-undo height 26, icon 9.5; .hy-entry button 16 glyph 6.5, padding 0 4 0 9; snowflake(12); .hy-streak background rgba(158,220,255,.16).
- **Phase:** Phase 8

### HY-6 — Streak (goal reached) card dimensions differ

- **Mac:** `NotchBuddy/Sources/App/HydrationView.swift:588-639` — HStack spacing 16; headline flake 28 #7AC4DF + text 24 semibold (minScale .7); discs top 10; next-mark bar 84x6 with fill min 6; right column 84 wide, spacing 5: glass 62 (no portion), total only (11 #9398A1), text-only Undo (11 medium, h20, padding 9).
- **Windows:** `windows/src/views/hydration.ts:379-403; windows/src/style.css:3121-3128,3552-3663` — Headline 26/30 letter-spacing -0.02em, flake 30; days margin 12; bar 96 with no min fill; side 112 wide gap 6; glass 66; amount shows 'X of Y'; Undo is the big icon+label button.
- **Fix:** Headline font 600 24px, no letter-spacing, flake 28; .hy-days margin-top 10; .hy-bar width 84, fill min-width 6px; .hy-side width 84 gap 5; buildGlass(62); amount.textContent = amountText(total); a small text-only .hy-undo-sm (11px 500, h20, padding 0 9px, bg rgba(255,255,255,.09)).
- **Phase:** Phase 8

### HY-7 — Next-mark progress uses a different formula and disappears after 365 days

- **Mac:** `NotchBuddy/Sources/App/HydrationView.swift:33-40,584-587,602-608` — mark = nextMark(after: days) (beyond 365: (days/100+1)*100), floor = previousMark(before: mark), progress = (days-floor)/(mark-floor). 5 days -> 50% toward 7.
- **Windows:** `windows/src/views/hydration.ts:31-32,516-521` — progress = run/nextMark (5 days -> 71%); row hidden when run >= 365.
- **Fix:** Port nextMark/previousMark exactly into hydrationText.ts and use (run-floor)/(mark-floor); never hide the row.
- **Phase:** Phase 8

### HY-8 — Week discs: today is bold and its frozen disc gets a ring + pop (Windows only); rest dots styled differently

- **Mac:** `NotchBuddy/Sources/App/HydrationView.swift:504-519,641-673` — Labels all 10pt #9398A1; discs have no ring or animation. Header dots: rest = fill #94A3B8 @ .5 and no stroke; today = clear + #9EDCFF stroke; others white .22 stroke.
- **Windows:** `windows/src/style.css:3352-3371,3583-3620` — .hy-day.today is 600/ink, today's frozen disc gets a 2px+3.5px ring and a 620ms pop; header rest dot bg .3 + border .7.
- **Fix:** Remove .hy-day.today rules and the hy-today keyframes; .hy-dot.rest {background: rgba(148,163,184,.5); border-color: transparent}.
- **Phase:** Phase 8

### HY-9 — Reminder (sip) card sizes, name styling and slide-in differ

- **Mac:** `NotchBuddy/Sources/App/HydrationView.swift:694-781` — HStack spacing 12; glass 46 with total under it (spacing 4, minWidth 84); title 15 semibold one line (minScale .8) top 4; sub 13 one line (minScale .85) top 1; buttons top 8 spacing 7; title is one plain sentence '<name>! How about some water?'; no transition between prompts.
- **Windows:** `windows/src/views/hydration.ts:554-569,571-664; windows/src/style.css:3667-3699` — Glass 54 in a 112 column (gap 6); title margin 3, sub 2, actions 10/gap 8, no single-line clamp; the name is rendered in a quieter 12px grey span; body slides in (hy-enter 260ms) when the prompt changes.
- **Fix:** buildGlass(46); .hy-side for sip: width 84 gap 4; .hy-sip-title margin-top 4 white-space nowrap with ellipsis; .sub margin-top 1 nowrap; .actions margin-top 8 gap 7; drop the .hy-name split (plain t('%@! How about some water?', name)); remove the hy-enter animation.
- **Phase:** Phase 8

### HY-10 — Default name is not taken from the OS account

- **Mac:** `NotchBuddy/Sources/App/HydrationStore.swift:117-119` — If no name is stored, uses the first word of NSFullUserName(), so the reminder greets the account's first name out of the box.
- **Windows:** `windows/src/core/hydrationStore.ts:230-258` — Name stays empty until typed in Settings, so the reminder is 'How about some water?'.
- **Fix:** Add a Rust command returning the display name (GetUserNameExW(NameDisplay), falling back to USERNAME / $USER on Linux) and, in load('island'), setName(first word) when name is empty.
- **Phase:** Phase 8

### HY-11 — Hydration copy differences (tooltip order, durations, 'Logged' amount)

- **Mac:** `NotchBuddy/Sources/App/HydrationView.swift:20-25,537,738,772-776` — Pause tooltip '<status> — <action>' (or action alone); duration 'h h m' unpadded ('1 h 5'); last-log minutes = max(1, floor); 'Logged: +<portion setting>'.
- **Windows:** `windows/src/views/hydration.ts:474,627,633; windows/src/core/hydrationText.ts:16-22` — Tooltip '<action> · <status>'; '1 h 05'; minutes rounded and can be 0 ('0 min ago'); 'Logged: +<last entry ml>'.
- **Fix:** pauseBtn.title = status ? `${status} — ${label}` : label; durationText: no padStart, minutes = Math.max(1, Math.floor(...)) at the call site; logged title uses Hydration.settings.portionML.
- **Phase:** Phase 8

### HY-12 — Store behaviour drifts: prompt not cleared on tab switch, busy check, unsnooze

- **Mac:** `NotchBuddy/Sources/App/HydrationView.swift:720-726; HydrationStore.swift:228-230,258-262,385` — Leaving the .sip view (to another tab) clears a non-reminder prompt; reminders defer 2 min for pendingApproval, pendingQuestion, isReplying or viewHoldsIslandOpen; unsnooze does not set awaiting; remove() only unfreezes when streak is enabled.
- **Windows:** `windows/src/island/island.ts:568; windows/src/core/hydrationStore.ts:396-398,418-424,569` — Prompt cleared only when the island leaves expanded; defers only for pendingApproval or isPinned; unsnooze sets awaiting=true; remove() always unfreezes.
- **Fix:** Call Hydration.clearPrompt() in Island.setView when leaving 'sip'; add pending question / reply-in-progress / page-open checks to due(); drop `this.awaiting = true` from unsnooze; guard streakUnfreeze with settings.streakEnabled.
- **Phase:** Phase 8

### HY-13 — Goal confetti geometry differs

- **Mac:** `NotchBuddy/Sources/App/HydrationView.swift:305-339,366-371` — Ring ellipse 68x56 scaled 0.55->1.55 over 0.9 s, Ice.light .75->0, 2pt; 9 flecks at angles -200+i*28 deg flying 22->66pt (y*0.9) over 1.2 s, delay (i%4)*40ms, radius 3.2/2.4 * (0.4+0.6e), colours cycle [#9EDCFF,#34D399,#F5F6F8,#F472B6,#22D3EE], even=circle odd=rounded rect 1; 150x150 frame offset x -23.
- **Windows:** `windows/src/views/hydration.ts:202-225; windows/src/style.css:3706-3752` — Ring 62x50; 9 pieces with hand-picked angles -108..108, travel 16->47px, delays 0-150ms, sizes 3-4px, plus 160deg rotation.
- **Fix:** Generate the 9 pieces from the Mac formula (angle -200+i*28, delay (i%4)*40, size 2*(i%3==0?3.2:2.4), colour cycle) and animate translate 22px->66px along the angle with y scaled .9; ring 68x56.
- **Phase:** Phase 8

### HY-14 — Glass animation and mini glass are CSS approximations

- **Mac:** `NotchBuddy/Sources/App/HydrationView.swift:96-104,111-114,158-208,788-809` — Pour 0.9 s easeOutBack; wave energy decays (1-t/3)^2 over 3 s; mini glass: outline white .6, no rim/shine; compact ring scale 0.9->1.5 opacity .8->0 over 1.8 s, glass 11pt; count uses .numericText contentTransition (snappy .5).
- **Windows:** `windows/src/views/hydration.ts:95-194; windows/src/style.css:3219-3334,3764-3797` — 900ms cubic-bezier level, 1.5 s stir then 3.3 s settle; mini glass keeps the .36 outline and the rim; ring 1->1.7, glass 12px; count changes instantly.
- **Fix:** Mini: stroke-opacity .6 and omit the rim path when mini; compact ring keyframes scale(.9)->scale(1.5); buildGlass(11, true); optional: animate the count with a short roll.
- **Phase:** Phase 8

### AG-1 — Agenda header controls styled as island tabs; Updated label size/format

- **Mac:** `NotchBuddy/Sources/App/AgendaView.swift:51-91` — Header 24pt high: calendar 11 semibold #38BDF8; 'Updated <locale short time>' 10pt #6B7079 (shown whenever lastUpdated exists); refresh arrow.clockwise 10 semibold #8E939C in a 22x22 plain hit area; open arrow.up.right.square 11 #8E939C 22x22; no hover backgrounds.
- **Windows:** `windows/src/views/agenda.ts:102-115,144-145; windows/src/style.css:297-317,1265-1270` — Calendar 12; Updated 11px and HH:mm, only when status is ready; refresh/open are .tab buttons (30x22 radius 11 with hover background); open glyph is a bare arrow (no square).
- **Fix:** Add .agenda-head-btn {width:22px;height:22px;background:none} without hover fill; icons 10 (refresh, stroke 2.4) and 11 (arrow-in-square svg); .agenda-updated 10px; format with toLocaleTimeString(language(), {timeStyle:'short'}); show whenever fetchedAtMs>0.
- **Phase:** Phase 8

### AG-2 — Agenda padding, empty state layout and past-row colours

- **Mac:** `NotchBuddy/Sources/App/AgendaView.swift:27-39,122-146,194-199` — Padding 12 h / 8 v, spacing 4. Empty state: text 13 (#8E939C or #FF8D97) and the 'Settings…' capsule on the SAME line (HStack spacing 8), top 2. Past rows: start time #6B7079, title #8E939C.
- **Windows:** `windows/src/views/agenda.ts:118,148-158; windows/src/views/views.ts:92-104; windows/src/style.css:1445-1462` — stack() pads 4 v with gap 5; empty text uses .sub (#9398A1) and the Settings button sits below it (margin-top 6); past start time #8E939C.
- **Fix:** Agenda body padding 8px 12px, gap 4; render empty text + button in a flex row gap 8, non-problem colour #8e939c; .agenda-row.past .agenda-times b {color:#6b7079}.
- **Phase:** Phase 8

### AG-3 — Heads-up highlight lifetime and failure text

- **Mac:** `NotchBuddy/Sources/App/IslandWindowController.swift:930,1221; AgendaView.swift:154; AgendaClient.swift:367` — agendaHighlight stays until the island shrinks; failure shows the localized error text produced by the client (e.g. 'Server returned 500' via key 'Server returned %lld').
- **Windows:** `windows/src/views/agenda.ts:130-135,96` — Highlight dropped on the next tab opening >5 s after the heads-up; Rust error strings are passed through t() verbatim so 'Server returned 500' never matches the catalog key and stays English.
- **Fix:** Clear Agenda.highlight in Island.setMode when leaving expanded instead of the 5 s rule; have agenda.rs return a key + args (e.g. {key:'Server returned %lld', args:[500]}) and translate with t(key, ...args).
- **Phase:** Phase 8

### TM-1 — Timer strings not localized

- **Mac:** `NotchBuddy/Sources/App/FocusTimerView.swift:59-63,114,147; FocusTimer.swift:20-26` — Tile labels Hours/Minutes/Seconds and kind labels Focus/Break/Deep Work go through Text(loc:) (catalog has all six).
- **Windows:** `windows/src/views/views.ts:417-419,438,486,492; windows/src/core/timer.ts:19-20` — Hard-coded English for tile labels, preset names, running label and Pause/Resume.
- **Fix:** Wrap with t(): tile(…, t('Hours')) etc.; t(TIMER_LABEL[kind]) in presets and running label; pauseBtn.textContent = t(isPaused ? 'Resume' : 'Pause') (add 'Resume' to the catalog if missing).
- **Phase:** Phase 8

### TM-2 — Running timer: clock size, paused dimming, padding

- **Mac:** `NotchBuddy/Sources/App/FocusTimerView.swift:27-29,150-158` — Clock 26 semibold monospaced digits #F5F6F8 always (paused or not); 'paused' 11 #8E939C; card padding 10 vertical, 16 trailing, lead(108, flush 16).
- **Windows:** `windows/src/style.css:537,699-710; windows/src/views/views.ts:489` — Clock 22px and greyed to --dim while paused; 'paused' #9398A1; padding 12 vertical.
- **Fix:** .timer-clock font-size 26px; remove the paused colour switch; .timer-paused color var(--dim-2); .timer-wrap padding 10px 16px 10px 108px.
- **Phase:** Phase 8

### TM-3 — Timer picker: drag-to-nudge missing, wheel added; Reset/Start glyphs

- **Mac:** `NotchBuddy/Sources/App/FocusTimerView.swift:66-89,107-113` — Vertical drag on a tile changes it by 1 per 12pt (up = more); no wheel handling. Start uses play.fill, Reset arrow.counterclockwise.
- **Windows:** `windows/src/views/views.ts:410-413,422-425; windows/src/style.css:627-633` — Mouse wheel nudges by 1; no drag. Reset uses the text glyph '↺'; Start a CSS triangle.
- **Fix:** Add pointerdown/move handling on .t-tile (setPicker(start - Math.trunc(dy/12))) keeping wheel optional; use proper svg play and counter-clockwise arrow icons at 12px.
- **Phase:** Phase 8

### CB-1 — Clipboard window is square and flat — no 16px rounded panel, hairline or shadow

- **Mac:** `NotchBuddy/Sources/App/ClipboardPanel.swift:39-55,131-139` — Borderless transparent NSPanel with shadow; content is a RoundedRectangle(16) filled #1C1C1E with a 1pt white .08 stroke, clipped to the radius.
- **Windows:** `windows/src/clipboard/clipboard.css:21-35; windows/src-tauri/src/lib.rs:1066-1080` — Window is created transparent but html/body paint #1c1c1e edge to edge, so the panel is a square with no border; no shadow configured.
- **Fix:** html, body {background: transparent}; #clip-root {background:#1c1c1e; border-radius:16px; border:1px solid rgba(255,255,255,.08); overflow:hidden}. In lib.rs add .shadow(true) (Win11 rounds/shadows undecorated windows) and keep transparent(true).
- **Phase:** Phase 8

### CB-2 — Clipboard window opens centred instead of under the island on the active display

- **Mac:** `NotchBuddy/Sources/App/ClipboardPanel.swift:69-83` — Each open places the panel horizontally centred on the active screen, 10pt below the island's reserved area.
- **Windows:** `windows/src-tauri/src/lib.rs:1076,1096-1108` — .center() once at creation; toggle just shows it wherever it was.
- **Fix:** In toggle_clipboard_window compute the island window's monitor and rect and set_position so the panel is centred on the island's x and 10px beyond the island on the side away from its edge (below for top edge, above for bottom edge).
- **Phase:** Phase 8

### CB-3 — Clicking outside does not dismiss the clipboard window; not draggable; resizable

- **Mac:** `NotchBuddy/Sources/App/ClipboardPanel.swift:49,87-99` — Global mouse-down anywhere else closes it (popover behaviour); Escape closes; movable by background; fixed 380x460.
- **Windows:** `windows/src-tauri/src/lib.rs:1070-1090; windows/src/clipboard/main.ts:180-183` — Only Escape/close button hide it; no drag region; resizable with min 320x320.
- **Fix:** Handle tauri::WindowEvent::Focused(false) -> hide(); add data-tauri-drag-region to .chrome; .resizable(false).
- **Phase:** Phase 8

### CB-4 — Image entries cannot be copied back (row still says 'Copied') and image favourites are not persisted

- **Mac:** `NotchBuddy/Sources/App/ClipboardStore.swift:196-211,252-315` — Copying an image row writes the NSImage back to the pasteboard; image favourites are saved as 0600 PNGs and restored at launch.
- **Windows:** `windows/src-tauri/src/clipboard.rs:199-221,332-343; windows/src/clipboard/main.ts:161-172` — write_back returns false for images, yet the UI flashes 'Copied'; image favourites vanish on restart.
- **Fix:** Keep the original arboard::ImageData (bounded by MAX_IMAGES=12, like the Mac keeps decoded images) and use board.set_image; encode favourites to PNG files beside the JSON (png/image crate or a tiny encoder). In main.ts only show 'Copied' when clipboardCopy resolves true.
- **Phase:** Phase 8

### CB-5 — Clipboard row/meta copy is hard-coded English and 'Just now' casing differs

- **Mac:** `NotchBuddy/Sources/App/ClipboardStore.swift:19-66` — L('Blank'), L('Image (%@)'), L('Link'), L('Text · %lld lines'), L('Text'), L('Image'), L('just now') (lowercase), L('%lldm ago'/'%lldh ago'/'%lldd ago').
- **Windows:** `windows/src/clipboard/main.ts:22-47` — Literal 'Blank', 'Image (…)', 'Link', 'Text · N lines', 'Text', 'Image', 'Nm ago'…; t('Just now') capitalised.
- **Fix:** Use t('Blank'), t('Image (%@)', size), t('Link'), t('Text · %lld lines', n), t('Text'), t('Image'), t('just now'), t('%lldm ago', n), t('%lldh ago', n), t('%lldd ago', n).
- **Phase:** Phase 8

### CB-6 — Clipboard glyphs, empty-state position, tooltips and copy sound

- **Mac:** `NotchBuddy/Sources/App/ClipboardPanel.swift:146-149,178-181,252-257,301-339; ClipboardStore.swift:210` — Close = xmark.circle.fill 14 #FF5F57 (x visible); title icon doc.on.clipboard.fill 13; History tab 'clock'; Favorites heart.fill; row icon link / text.alignleft; row actions heart vs heart.fill, doc.on.doc.fill, trash.fill, no tooltips; empty message centred vertically in the list; copying plays 'blip'.
- **Windows:** `windows/src/clipboard/main.ts:71-75,102-107,130-145; windows/src/clipboard/clipboard.css:48-56,220-225` — Close is a plain red dot; clipboard icon 15; History uses the stopwatch icon; heart always filled; text rows use doc / arrow icons; actions have Keep/Copy/Forget tooltips; empty message top-aligned (padding 20); no sound.
- **Fix:** Add an x to .chrome-close (svg xmark 8 #4d0000 or the circle-x path); icons 13; add clock and outline-heart icons; row icons link/text-align; remove action titles; .list empty: flex centre with height 100%; play the blip (emit to island or use Web Audio in the window).
- **Phase:** Phase 8

### UP-1 — Choose card has an extra 'Cancel' button

- **Mac:** `NotchBuddy/Sources/App/UploadCanvasView.swift:51-72,245-270; IslandViewContent.swift:913-929` — After the drop the choose card shows the title, sub and ONE white button 'Ask a question about it' (168x26 at 114,113). Fallback ChooseView has only 'Ask a question'.
- **Windows:** `windows/src/upload/canvas.ts:82-94,284-287; windows/src/views/upload.ts:98-102` — Canvas paints a second 120x26 'Cancel' pill at x 290 with a hit area; fallback view also has a Cancel button.
- **Fix:** Remove the second mk(290,…) hit area and the Cancel paint in drawChoose; remove Cancel from buildChoose; drop UploadCanvasActions.cancel.
- **Phase:** Phase 8 — Cancel kept (owner), drawn the Mac way

### UP-2 — Drop/upload/choose strings are not localized on Windows

- **Mac:** `NotchBuddy/Sources/App/UploadCanvasView.swift:149,157,178,252,257,265; IslandViewContent.swift:884-894,921-923` — Text('Drop your files here'), 'Uploading %@', '%@ is ready.', 'What do you want to do with it?', 'Ask a question about it' are LocalizedStringKeys (all in the catalog).
- **Windows:** `windows/src/upload/canvas.ts:177,186,204,276-287; windows/src/views/upload.ts:73-77,118-121` — Canvas text and fallback 'Uploading …'/' is ready.' are literal English.
- **Fix:** Use t('Drop your files here'), t('Uploading %@', name), t('%@ is ready.', name), t('What do you want to do with it?'), t('Ask a question about it') in canvas.ts and upload.ts.
- **Phase:** Phase 8

### UP-3 — Upload canvas ignores the Mochi character (hats, eyes, body shape)

- **Mac:** `NotchBuddy/Sources/App/UploadCanvasView.swift:286-298,365-388` — MochiDress(character for the focused pill, morph) draws accessory behind/front, may replace the body path and draws the character's own eyes (glint = sequence eye); accessories fade out as Mochi becomes a box.
- **Windows:** `windows/src/upload/canvas.ts:293-376` — Always the classic grey Mochi with sequence eyes.
- **Fix:** Expose the Windows Mochi engine's character drawing (body path / drawBehind / drawEyes / drawFront equivalents in mochi/engine.ts or mochi/character.ts) and call them from drawMochi with State.characterFor(State.focusId) and morph clamp.
- **Phase:** Phase 8

### UP-4 — Swallowed file uses a generic sheet instead of the real file icon

- **Mac:** `NotchBuddy/Sources/App/UploadCanvasView.swift:42-46,519-533` — During the suction strips the NSWorkspace icon of the dropped file (64x64) is drawn; the following-the-cursor sheet stays generic.
- **Windows:** `windows/src/upload/canvas.ts:491-533` — Generic sheet always (comment: not reachable from the webview).
- **Fix:** Closable: add a Rust command file_icon(path) using SHGetFileInfoW(SHGFI_ICON|SHGFI_LARGEICON) -> HICON -> PNG data URL (Linux: Gio content type icon or keep generic), decode to an ImageBitmap once after drop and drawImage in the strips like drawDocCG.
- **Phase:** Phase 8

### UP-5 — Fallback Uploading/Choose views drift (static progress, label, sizes)

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:816-929; AppState.swift:523-527` — UploadingView derives progress from wall time (ease-out quad over uploadDuration) and uses droppedLabel ('3 files'); checkmark.circle.fill icon; Choose title 14 semibold, sub 12.5 #9398A1.
- **Windows:** `windows/src/views/upload.ts:55-124` — Uses State.uploadProgress which is never advanced (stays 0%); uses droppedFile.name; text '✓'; title .title 15, sub 13.
- **Fix:** Compute progress from UploadSeq.sinceDrop()/uploadDuration with t*(2-t); add a droppedLabel getter (count>1 -> t('%lld files')); svg check icon; title 600 14px, sub 12.5px.
- **Phase:** Phase 8

### UP-6 — Dropping a file resets the chat history on Windows only

- **Mac:** `NotchBuddy/Sources/App/FileDropView.swift:85-89` — Drop sets droppedFile(s) and promptContext; chatHistory is kept.
- **Windows:** `windows/src/island/island.ts:766-768` — State.chatHistory = [] and Bridge.chatReset() on every drop.
- **Fix:** Remove the two reset lines (or move the reset to where the Mac resets, if product wants it on both).
- **Phase:** Phase 8 — Mac fix proposed, awaits the owner's yes

### ATO-1 — Ato badge text font differs

- **Mac:** `NotchBuddy/Sources/App/AtoBotView.swift:124-128` — Decor text drawn with .system(size, weight: .heavy) (SF Pro Heavy).
- **Windows:** `windows/src/ato/view.ts:317-322` — 800 weight "Open Sans", Arial (the original web engine's font).
- **Fix:** Use `900 ${size}px system-ui, "Segoe UI Variable Text", "Segoe UI", sans-serif` to match the Mac.
- **Phase:** Phase 8

### SN-1 — Thrown snow flakes fade by alpha in flat white; layers pop instead of fading

- **Mac:** `NotchBuddy/Sources/App/IslandSnowView.swift:139-145,196-201,240-246,274-279` — Flakes shrink (r = size*min(1, life/0.25)) and are part of the same path as the bank, so they share its #FFFFFF->#D3E2F2 gradient; bank layer fades in/out 0.2 s, snowfall 0.3 s.
- **Windows:** `windows/src/island/snowLayer.ts:258-270; windows/src/style.css:122-133` — Flakes keep their radius and fade alpha, pure white; .off is display:none (instant).
- **Fix:** Draw flakes into the bank path with radius scaled by min(1, life/0.25) and fill once with the gradient; replace display:none with opacity transitions (0.2 s bank, 0.3 s fall) plus visibility after the transition.
- **Phase:** Phase 8

## Already matches

- Upload sequence engine (upload/sequence.ts): every USC constant, easing, spring, phase timeline, mouth/eye/morph/progress math is a line-for-line port of UploadSequenceEngine.swift (only addition: 2 s stall cap in simulateTo).
- Upload canvas scene: card #0D0E10 r20, green radial wash, 1.5px [6,5] dashed border, drop text + chips (same rough width estimate), progress bar track/fill gradient/flash/glow, check badge, choose title/sub/primary button geometry, superellipse body, eye shapes, 28-strip suction and green crumbs.
- Drop flow timing and sounds: performDrop(2.4 s), gulp + 'approve' + happy emote at drop, 'tick' every 10%, 'approve' + happy at completion, switch to choose ~1 s later; inbox copy in background.
- Now Playing: clock() formatting, skip clamp to duration-1, scrub drag with 0.4 s hold, transport order (skip back, prev, play/pause, next, skip fwd) with 18px gaps, artwork 108 r12 + white .06 hairline, fallback #0E0F11 + music note #5F646D, title 13/600 #F5F6F8, artist 11.5 #8E939C, '·' #4E535B, source 11 #6E737C, bar 4px white .12 with #F5F6F8 fill, empty state 'Nothing playing.' 12px #8E939C at 116/16 gutter, reveal only on transition to playing, pill renamed to track title.
- Christmas music: same video id, autoplay/loop/playlist/start params, 3 s yield grace, 5 s report cadence, ended->restart, tear-down on yield, resume position, greeting start once per run, next disabled / previous = seek 0, album slot 52x108 with 66px cover r9, coverflow -38deg -> -24deg + 1.05 on hover, gold stroke .45 -> .9, sleeve gradient #D23A4A->#8C1626, season window 15 Nov - 6 Jan (dev/debug always).
- Hydration rules/store logic (estimate, streak settle/freeze, schedule/next reminder, amount formatting, day key) are parity-tested via tests/hydration-parity.ts; message() precedence and all copy keys match; portions [150,250,350,500]; snooze 30 min; 2.6 s celebration; proud/happy emotes and gulp/proud sounds; glass SVG geometry (cavity, outline, rim, shine, glint, drop path, level travel 93.6) identical.
- Hydration header row (Who dot 7 + 'Hydration' 12/600 + 'today' 12 #9398A1, week dots 8px gap 4), entry chips text, '+N today', streak copy keys, rest pill colours #B7C2D0 on #94A3B8 .16, frozen disc gradient white->#D9EFF9 with #2E8DB8 flake, sip copy for all four prompts and button rows.
- Agenda: polling every 10 min + after midnight, 60 s tab freshness, 2 min reminder freshness, notified-keys per day, heads-up opens agenda with 'approval' sound; row layout (times 38 wide 12/600 + 10 #6B7079, 2x26 accent bar r1, title 11.5/600 #E6E8EB, public id chip 9/700 mono, subtitle 10 #7D828B, phase 10.5 with #34D399/#FBBF24/#C5C8CD/#6B7079), accent tints .05/.12/.16, heads-up .8 outline, department colours #A78BFA/#22D3EE, all empty-state copy.
- Focus timer store: presets 25/5/45, colours #FF9F0A/#30D158/#D946EF, clamp rules, extend +60 s, reset to preset, blip on start, finish sound and island alert; picker tile 54x42 r10 bg .08 22/600, labels 9.5 #8E939C, colon dots 3px #5F646D padding 17, Start #30D158 h30 r9 pad 18, Reset white .12 pad 16, presets 128x30 r8 hover .06 with 20px dots.
- Clipboard: 380x460 size, header/tab/search paddings (14/14/10, tabs gap 10, tab h30 r9 pad 12, active #0A84FF, count capsule black .25), search h32 r9 white .08, divider .08, rows h46 pad 14 gap 10, 26px r6 icons, title 13/600, sub 11 #8E939C, hover .06, copied green .14 for 1.1 s, actions replace time on hover, limits 60 entries / 12 images / 20 000 chars, de-dup moves to top, text-only favourites stored 0600, Escape closes, watching starts when opened.
- Ato orb: AtoDriver/AtoReaction/state mapping and festive dressing mirror AtoBotView.swift; pose and SVG are parity-tested against actuar-bot-v3.js (tests/ato-bot-parity.ts).
- Snow: bank/plough/flake arithmetic parity-tested (tests/island-snow-parity.ts); 28px band, #FFFFFF->#D3E2F2 bank gradient, 60 fps while touched / 0.5 s while growing / stopped when settled, snowfall 30 fps with screen blend, steps aside for the auto-close hairline, reduce-motion behaviour.

## Known differences in windows/README.md

- **closable** — Linux 'Now Playing reads nothing' (no MPRIS backend). Add an MPRIS reader (zbus or dbus crate) in media.rs `backend` for cfg(linux): org.mpris.MediaPlayer2.Player Metadata/PlaybackStatus/Position + PlayPause/Next/Previous/SetPosition. Needs the dependency the README avoids; until then the closest faithful equivalent is the Mac's own unavailable path: show an explicit reason line instead of 'Nothing playing.'.
- **closable** — 'Not in this version: sending a file by email' (README line 247). Already at parity: the Mac removed the mail composer too (IslandViewContent.swift:21 '.mail: EmptyView() // the mail composer is gone'; canvas shows only 'Ask a question about it'). Update the README line and remove the Windows-only 'Cancel' that was added to fill the gap (UP-1).
- **closable** — README: 'The clipboard already made the same move here' (a window of its own). Not actually a difference — the Mac Clipboard Manager is also its own borderless panel (ClipboardPanel.swift). What differs is shape/placement/dismissal (CB-1..CB-3), all closable in Tauri; reword the README.
- **closable** — Source app icon on the Now Playing artwork (code comment nowplaying.ts:53-60: 'Windows reports an AUMID, not an icon'). Resolve icons in Rust via AppInfo::GetFromAppUserModelId(...).DisplayInfo().GetLogo() for packaged apps and SHGetFileInfoW on the process image for exe AUMIDs (NP-4). Not in README; should be removed from the list of 'forced' differences.
- **closable** — Real file icon in the drop animation (code comment canvas.ts:491-495: 'no equivalent reachable from the webview'). Rust SHGetFileInfoW -> PNG data URL command (UP-4). Linux can stay on the generic sheet (same fallback the Mac draws).
- **closable** — Clipboard image favourites and image copy-back are text-only (code comments clipboard.rs:199-203,332-336). Keep originals for the 12 retained images and use arboard set_image; persist favourites as PNG files (CB-4). Not mentioned in README; it should be listed or fixed.
- **closable** — Media reader 'Nothing runs until the Now Playing pill is on, the way the Mac only starts its reader from activeIntegrations' (media.rs:8-9). The premise is stale: the Mac now follows the master switch (MusicController.swift:110-127). Gate on settings.enabled only (NP-1).
- **forced** — Snow steps aside for the hairline except at the bottom edge ([data-edge=bottom] rule). Forced by the no-notch bottom-corner placement (hairline moves to the top); keep as the closest equivalent.

## Parity tests to add

- NowPlayingCardView.clock(_:) and MusicController.shortTitle/shortArtist outputs for a fixed list of titles (after porting the cleaners) vs nowplaying.ts clock() and the new TS cleaners.
- NowPlayingCardView.dialSeconds and skip clamp (skip(by:) target for elapsed/duration samples) vs nowplaying.ts skip().
- PlaybackState.estimatedTime(at:) with playbackRate vs estimatedElapsed().
- HydrationText.nextMark/previousMark and the streak-card progress for days 0..400 vs the TS port (would have caught HY-7).
- HydrationText.duration(minutes:) strings for 0..200 vs durationText (would have caught the '1 h 05' drift).
- Hydration view numeric constants (glass widths 96/62/46/11, gaps 20/16/12, bar width 84, headline 24) dumped from a Swift table and asserted against CSS custom properties or a TS constants module.
- HydrationSnowflake path points (computed from `half` + rotations) vs the hard-coded SNOWFLAKE path string in views/hydration.ts.
- CardBackground.washColor table (red/green/pink/amber/cyan/indigo/soft) vs washRGBA() in views/views.ts and the hydration WASH_* constants.
- ClipEntry.title/subtitle/size/ago for sample inputs vs clipboard/main.ts title/subtitle/sizeLabel/ago (including localized keys).
- FocusTimer.presets/Kind.label/Kind.hex and clock for sample remainders vs TIMER_PRESETS/TIMER_LABEL/TIMER_COLOR/FocusTimer.clock.
- AgendaRow phaseText/phaseHex/accent for sample phases vs views/agenda.ts phaseText and DEPARTMENT_COLOR.
- USC constants, usProgressCurve(u) samples and computeFrame(t) outputs at fixed t (engine is pure) vs upload/sequence.ts — currently a hand-kept pair with no test.
- ChristmasMusicPlayer constants (videoID, 3 s yield grace, 5 s report cadence, artwork URL order) vs christmasMusic.ts.
- ChristmasAlbumView constants (width 52, cover 66, radius 9, tilt -38/-24, gold opacity .45/.9, sleeve colours) vs the .np-xmas CSS values.

## Risks

- Switching media.rs to the master switch (NP-1) keeps a GSMTC COM poll running every second for every user, not just pill users — acceptable on the Mac's own reasoning but worth measuring CPU on low-end machines.
- Volume control (NP-2) and app-icon extraction (NP-4, UP-4) need new `windows` crate features (Win32_Media_Audio, Win32_UI_Shell, ApplicationModel) and have no Linux equivalent without new dependencies; Linux must degrade to hiding the row / generic icons.
- Making the clipboard window transparent with rounded corners (CB-1) on Windows 10 can show a black or white backing during WebView2 startup; Windows 11 adds its own corner rounding/shadow to undecorated windows — verify both.
- Hide-on-blur for the clipboard (CB-3) must not fire while its own search box or the island's toggle button takes focus, or the toggle will close-then-reopen.
- Removing Windows-only embellishments (paused grey water, today emphasis, hover states, Cancel button, prompt slide-in) is a deliberate behaviour change Windows users have seen; confirm with the product owner that Mac-exact wins.
- The marching-dash direction may already be mirrored: Mac uses dashPhase = +wallTime*20 (UploadCanvasView.swift:115) while Windows uses lineDashOffset = -wallTime*20 (canvas.ts:158); both paths run clockwise on screen, so the ants likely march in opposite directions — verify side by side before changing.
- Porting MochiDress to the upload canvas (UP-3) depends on the Windows Mochi engine exposing character body/eye/accessory drawing in a reusable way; if it is entangled with BotEngine state it is a larger refactor.
- Localizing canvas text (UP-2) changes string widths; the Mac uses the same rough chip-width estimate, so keep that estimate rather than measureText to stay pixel-identical with the Mac.
- Several Mac strings used via SecondaryButton(String)/Text(String) are not actually localized on the Mac (e.g. 'Pause', 'Resume', 'Copied'); blindly t()-ing them on Windows would make Windows MORE translated than the Mac — check each key's Mac call site before translating.
