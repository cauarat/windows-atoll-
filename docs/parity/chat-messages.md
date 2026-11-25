# Parity — Built-in chat and message services

The Mac is the source of truth (see `CLAUDE.md`). Each gap names the Mac code, the Windows code and the fix; tick it in the PR that closes it. Audit of 2026-11-20 against `notchy` at f1dee26.

## Checklist

- [ ] **CHAT-01** · high · missing on windows · L — Assistant replies are plain text, not Markdown — _Phase 6_
- [x] **MSG-01** · high · visual · S — Card background is grey instead of black — _Phase 4_
- [ ] **CHAT-02** · high · missing on windows · M — Code blocks with copy button missing — _Phase 6_
- [ ] **MSG-02** · high · visual · S — Message pop-up and list are tinted by source instead of indigo — _Phase 4_
- [ ] **CHAT-03** · high · copy · S — System prompt forbids Markdown and names a different place — _Phase 6_
- [ ] **MSG-03** · high · copy · S — Relative time copy ('just now', '5m') — _Phase 6_
- [ ] **CHAT-04** · high · missing on windows · L — Model / provider picker capsule and popover missing — _Phase 6_
- [ ] **MSG-04** · high · visual · S — Message body is 13px / 36px two-line box instead of 12pt / 30pt — _Phase 4_
- [ ] **CHAT-05** · high · missing on windows · L — Only Anthropic is supported; no Google/OpenAI/Ollama/LM Studio and no streaming — _Phase 6_
- [ ] **MSG-05** · high · visual · S — Microphone sits left of the field instead of next to Send — _Phase 6_
- [ ] **MSG-06** · high · behaviour · S — Recording cannot be discarded (scrap button hidden by CSS) — _Phase 6_
- [ ] **CHAT-09** · high · behaviour · M — Chat does not hold the island or protect a draft — _Phase 6_
- [ ] **MSG-20** · high · behaviour · M — Pill ticker text, lifetime and read-sync — _Phase 6_
- [ ] **MSG-27** · high · missing on windows · L — No OS notification banners for messages — _Phase 6_
- [ ] **CHAT-06** · medium · behaviour · S — Different default Claude model — _Phase 6_
- [ ] **CHAT-07** · medium · copy · S — API error wording differs — _Phase 6_
- [ ] **MSG-07** · medium · visual · S — Reply bar metrics and focus state — _Phase 6_
- [ ] **CHAT-08** · medium · behaviour · S — Chat sounds/emotes differ (Windows beeps, Mac emotes) — _Phase 6_
- [ ] **MSG-08** · medium · visual · S — Paperclip / mic colours and glyphs — _Phase 6_
- [ ] **MSG-09** · medium · visual · M — Recording strip level dot, colours and clock rate — _Phase 6_
- [ ] **CHAT-10** · medium · missing on windows · M — No window context captured when opening the chat tab — _Phase 6_
- [ ] **MSG-10** · medium · visual · M — Attachment chips show a dot instead of a thumbnail/icon — _Phase 6_
- [ ] **MSG-11** · medium · visual · S — Attachment chip details (truncation, remove button, audio length) — _Phase 6_
- [ ] **CHAT-12** · medium · visual · S — Chat card has no 10pt bottom inset — _Phase 6_
- [ ] **MSG-12** · medium · behaviour · S — Only freshly recorded clips can be played back before sending — _Phase 6_
- [ ] **MSG-13** · medium · behaviour · M — Attaching copies files first, breaking duplicate detection and renaming files — _Phase 6_
- [ ] **MSG-14** · medium · behaviour · S — Rejection notice shown with nothing staged (squeezes the 160 card) — _Phase 6_
- [ ] **MSG-15** · medium · visual · S — Received voice-note player sizes, font and label — _Phase 6_
- [ ] **MSG-16** · medium · visual · S — Home message row: Ato logo missing, extra 'more waiting' — _Phase 6_
- [ ] **MSG-18** · medium · behaviour · S — Empty pop-up states and read-message fallback — _Phase 6_
- [ ] **MSG-19** · medium · behaviour · S — A new arrival steals the card picked from a list — _Phase 6_
- [ ] **MSG-21** · medium · behaviour · S — Escape marks the message read — _Phase 6_
- [ ] **MSG-22** · medium · behaviour · S — Arrival sound/view switch while replying on Home — _Phase 6_
- [ ] **MSG-26** · medium · behaviour · S — Answering from the all-sources list returns to the list — _Phase 6_
- [ ] **MSG-28** · medium · copy · S — Connection-problem wording in empty lists — _Phase 2_
- [ ] **MSG-29** · medium · visual · S — Messages list chrome (back button, dot, spacing, scrollbar) — _Phase 6_
- [ ] **CHAT-11** · low · visual · S — Context chip animation and spacing — _Phase 6_
- [ ] **CHAT-13** · low · visual · S — Chat scroll indicator and scroll animation — _Phase 6_
- [ ] **CHAT-14** · low · behaviour · S — Input locked while waiting for the answer — _Phase 6_
- [ ] **CHAT-15** · low · extra on windows · S — Chat history cleared on every file drop — _Phase 6 — Mac fix proposed, awaits the owner's yes_
- [ ] **MSG-17** · low · visual · S — Who-row text can wrap — _Phase 6_
- [ ] **MSG-23** · low · behaviour · S — Send sound on pop-up replies — _Phase 6_
- [ ] **MSG-24** · low · behaviour · S — Reply field enabled when there is no reply channel — _Phase 6_
- [ ] **MSG-25** · low · behaviour · S — Home 'Open' marks read and clears staging — _Phase 6_
- [ ] **MSG-30** · low · visual · S — Message card row spacing — _Phase 4_
- [ ] **MSG-31** · low · copy · S — Placeholder bodies and Rust errors are English-only — _Phase 6_
- [ ] **MSG-32** · low · behaviour · S — Ato preview not trimmed / empty preview — _Phase 6_
- [ ] **MSG-33** · low · extra on windows · S — Pointer cursors and hover fills that macOS does not have — _Phase 4_
- [ ] **MSG-34** · low · behaviour · S — Messages ignored entirely while Coucou is switched off — _Phase 6_
- [ ] **MSG-35** · low · platform forced · M — Voice note file format — _not done — AAC encoding is invisible to users_

## How each side is built

MAC (SwiftUI). IslandViewContent dispatches IslandView → view. Chat = PromptView (IslandViewContent.swift:935-1090): CardBackground(wash:.indigo) [card #000000, radial wash at (0.5,1.3) r280, 1px white .035 stroke, radius 20] → VStack(spacing 6, padding L84 T12 R16 B14, outer .padding(.bottom,10)): [ContextChip (file OR captured window "App · host", springs 1.06 + white stroke then settles)] → [ScrollView (no indicators) of ChatBubble (user: right, white .13 bubble r12, 12.5 #F1F2F4 / assistant: ChatMarkdownView) + TypingDotsView] or Spacer → [right-aligned model capsule: provider dot 6, model 10.5 medium #7B8089, chevron.up.chevron.down 8 #5C6370, white .06 capsule → popover ModelPickerView 300 wide #16171B: provider chips Anthropic/Google/OpenAI/Ollama/LM Studio + model list 260 high] → [input bar: TextField 13 + SendButtonStyle 28 white circle arrow.up 11 semibold; H10 V6 white .07 r12]. ClaudeService.chat: Anthropic non-streaming with web_search, other providers via OpenAI-compatible API, local ones stream via LocalChat (SSE at 15 Hz, <think> filtered). System prompt asks for light Markdown. ChatMarkdown.parse → blocks (heading, paragraph, code w/ copy button, lists, quote, rule) + inline AttributedString markdown. Errors → note view + Mochi error state; success → happy emote; no chat sounds. Chat tab icon = ChatSparkleIcon (16 wide) in IslandHeader, whose preAction captures the frontmost window as context.
Messages: MessageInbox (model, unread/active/list rules, syncPill → pill name/steps/badge), MessageNotifier (macOS banners with Reply/Open), MessagingCoordinator (connect per pill). MessageView (pop-up, IslandViewContent.swift:2358-2616): CardBackground(.indigo) → VStack(spacing 6, lead 116/16): whoRow (dot 8, sender 12 semibold #F5F6F8, origin 12 #8E939C, "N more waiting · time" 11 #6B7079) → MessageBody (12pt #9398A1, 2 lines or full w/ scroll; voice: VoiceNoteRow + scrolling transcript) → ReplyAttachmentsRow (only when staged; chips + red notice) → replyRow [bar: AttachButton paperclip | TextField 12 or RecordingStrip | VoiceRecordButton mic | Send 28; H10 V5, white .07→.12 focused, r12, green 1.5 drop stroke] + SecondaryButton "Open". HomeMessageView: same rows, no wash, AtoLogo for Ato, no "more waiting". MessagesListView: CardBackground(.indigo), padding 12/12/8, header [chevron.left 10 semibold #6B7079 24x24][Mochi seat 26][dot 7][name 12 semibold][N waiting 11] → ScrollView of MessageRow (dot 5, sender 11 semibold #C5C8CD, origin/time 10 #6B7079, body 10.5 #9398A1 indent 10; accent .08/.16 hover, r5) or connection-problem/empty text.
WINDOWS (Tauri, vanilla TS). views/chat.ts buildPrompt: .card.wash.chat-card (--wash indigo .5) → .chat-body (padding 12/16/14/84, gap 6): .chip-row (droppedFile chip only) → .chat-log (bubbles: .bubble user, .reply plain pre-wrap text; .typing dots) → .chat-bar (input 13px + .send-btn 28). Bridge.chatSend → Rust claude.rs (Anthropic only, non-streaming, system prompt forbids markdown, default model claude-opus-5). Sounds send/finish/error; no emote; no model picker; no window context. Tab icon = ICONS.chatSparkle (flattened Mac path) in views.ts header. Messages: Rust mattermost.rs/ato.rs/whatsapp.rs emit "message"/"message-updated"/"message-status" (messages.rs); island/messages.ts ingests into State (core/state.ts inbox port), sets pill (60 s auto-clear), plays question, reveals card. views/message.ts buildMessage(home?) = card(indigo or null; wash re-tinted per source) → .stack(116,16; gap 5, pad 4): .who-row → body (.sub 13px clamp 36px or FULL scroll) / .vn voice player + transcript → .chip-row attachments → .chip-notice → .actions[.chat-bar (clip, mic, input, mic-row, send 24) + btn Open]. views/messages.ts buildMessages = card(indigo, re-tinted) → .stack(12,12): .msg-head [.tab back][.msg-mochi][dot][b name][.msg-count] → .msg-list of .msg-row. Attachments: core/attachments.ts (pure, parity-tested twin of ReplyAttachment.swift) + island/replyAttachments.ts (ingest-copies every file into inbox) + island/voiceNote.ts (MediaRecorder → m4a or 16 kHz WAV) + island/voicePlayer.ts (received Ato clips). No OS notification banners. The Windows code mirrors the Mac file-for-file for messages (message.ts ≈ MessageView+HomeMessageView, messages.ts ≈ MessagesListView, state.ts ≈ MessageInbox, attachments.ts ≈ ReplyAttachment.swift) but chat.ts is a thin port of only PromptView/ChatBubble/TypingDots without ChatMarkdown(View), ModelPickerView, LocalChat or the multi-provider half of ClaudeService.

## Gaps

### CHAT-01 — Assistant replies are plain text, not Markdown

- **Mac:** `NotchBuddy/Sources/App/ChatMarkdown.swift:5-117; ChatMarkdownView.swift:5-91; IslandViewContent.swift:1252-1275` — Assistant message is parsed by ChatMarkdown.parse into blocks (fenced code, ATX heading needing a space, ---/***/___ rule, '> ' quote, '- '/'* '/'+ ' bullets with indent = leadingSpaces/2, '1. ' ordered, paragraphs joined with \n) rendered in a VStack(spacing 6): heading level<=2 14pt bold, else 13 semibold #F1F2F4; paragraph 12.5 #B0B5BE; list prefix '•' or 'n.' 12.5 #6B7079 in minWidth 10 (20 if prefix>2 chars), HStack spacing 6, indent 12pt per level; quote = 2pt #4B5563 capsule bar + 8 gap + 12.5 #8A8F98 text; rule = Divider opacity 0.3. Inline: AttributedString markdown (inlineOnlyPreservingWhitespace) → bold/italic/`code`/links; link taps only open if safeWebURL passes. All text selectable.
- **Windows:** `windows/src/views/chat.ts:14-23; windows/src/style.css:1637-1643` — h('div',{class:'reply', text}) — raw text, white-space:pre-wrap, 12.5 #b0b5be. Any ** / ``` / # shows literally.
- **Fix:** Add windows/src/core/chatMarkdown.ts as a line-for-line port of ChatMarkdown.parse (same block enum and break rules), and render in chat.ts bubble() with classes .md-h1/.md-h3/.md-p/.md-li/.md-quote/.md-rule/.md-code using exactly the sizes/colours above (gap 6px between blocks). Inline: small tokenizer for **bold**, *italic*/_italic_, `code` (var(--mono)), [text](url) → <a> whose click calls a TS port of SafeWebURL.swift then actions.openUrl. Never use innerHTML with model text (build nodes). Keep user-select:text.
- **Phase:** Phase 6

### CHAT-02 — Code blocks with copy button missing

- **Mac:** `NotchBuddy/Sources/App/ChatMarkdownView.swift:38-51, 93-117` — Fenced code → HStack(alignment .top): code Text 11pt monospaced #C8CDD4, selectable, full width; CopyButton 22x22, white .06 bg, radius 4, icon doc.on.doc 10pt #6B7079 → checkmark #22C55E for 1.5 s after copying. Block padding 10, bg #0D0E12, radius 8, 1px white .08 stroke. Language tag is parsed but not shown.
- **Windows:** `none (chat.ts:14-23)` — Code arrives as plain text inside the reply paragraph (and the Windows prompt currently tells the model not to use fences).
- **Fix:** In the CHAT-01 renderer, .md-code { display:flex; align-items:flex-start; gap:8px; padding:10px; background:#0d0e12; border:1px solid rgba(255,255,255,.08); border-radius:8px } pre { font: 400 11px var(--mono); color:#c8cdd4; white-space:pre-wrap; flex:1 } and a 22x22 button (rgba(255,255,255,.06), radius 4) with a doc.on.doc-style 10px icon #6b7079 that calls navigator.clipboard.writeText (or a Rust clipboard command) and swaps to a #22c55e checkmark for 1500 ms.
- **Phase:** Phase 6

### CHAT-03 — System prompt forbids Markdown and names a different place

- **Mac:** `NotchBuddy/Sources/App/ClaudeService.swift:189-208` — "You are Mochi, <name>'s personal AI assistant embedded in the notch of their Mac." (or 'a personal AI assistant embedded in the notch of the user's Mac.') + same research sentence + "Use light Markdown when it helps: short paragraphs, bullet lists, **bold**, `inline code` and fenced code blocks. Avoid tables and big headings: the chat window is small."
- **Windows:** `windows/src-tauri/src/claude.rs:25-46, 273-287` — "…living on the edge of the user's screen." and "No markdown formatting (no **, no ##, no bullet dashes). Use plain text with line breaks."
- **Fix:** Replace the last sentence of SYSTEM_PROMPT with the Mac's Markdown sentence verbatim (ship together with CHAT-01, otherwise raw ** appears). Keep the first sentence's platform wording (no notch) but phrase it the same shape: 'embedded in the island at the edge of their screen'. Update the Rust unit test that asserts the old ending.
- **Phase:** Phase 6

### CHAT-04 — Model / provider picker capsule and popover missing

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:989-1017, 1123-1250; IslandTypes.swift:106-157; AppState.swift:414-499` — Right-aligned row (padding H10) above the input: capsule (H8 V4, white .06) with a 6x6 dot in provider accent (#E07950 Anthropic, #4285F4 Google, #10A37F OpenAI, #FACC15 Ollama, #A3E635 LM Studio), active model id 10.5 medium #7B8089, chevron.up.chevron.down 8 #5C6370. Click → popover 300 wide, padding 14, bg #16171B: wrapping provider chips (dot 7, name 12 regular/semibold when active, H10 V6, active bg accent .18 + stroke accent .5, else white .06 + white .1 stroke; local providers hidden unless configured), spring 0.25/0.7, 'pop' sound + surprised emote; Divider .2; model list (fixed 260 high, rows 12pt #C8CDD4 or accent when active + checkmark 10 semibold, active bg accent .1, r6, H8 V6) with 'Loading models…' + spinner, or errors ('No API key — add it in Settings.', 'Failed to load models. Check your API key.', 'Connect Ollama in Settings → Chat first.', 'No models yet. Download one in Ollama first.', 'Cannot reach <url>. Is the server running?'). Picking a model plays 'blip' and closes.
- **Windows:** `none (chat.ts:40-57; model only in settings.rs:353 via lib.rs:921)` — No picker. The model is whatever Settings stores; no provider choice.
- **Fix:** Add the capsule row in chat.ts between .chat-log and .chat-bar, and an in-island popover element (absolute, 300px, #16171b, radius like NSPopover ~10px, shadow) built from a TS twin of the ChatProvider table. Add Rust commands models_list(provider) (Anthropic /v1/models display_name; Google openai/models with the same exclusion list; OpenAI /v1/models sorted by created with the same exclusions; Ollama/LM Studio /v1/models via normaliseURL) and persist chatProvider + per-provider model in settings.rs. Same strings, sounds and emote.
- **Phase:** Phase 6

### CHAT-05 — Only Anthropic is supported; no Google/OpenAI/Ollama/LM Studio and no streaming

- **Mac:** `NotchBuddy/Sources/App/ClaudeService.swift:216-441; LocalChat.swift:24-207` — Google/OpenAI via OpenAI-compatible /chat/completions (non-streaming, 30 s); Ollama/LM Studio stream SSE: an empty assistant placeholder is appended, typing dots vanish at the first visible token, text updates at most 15×/s, <think>…</think> hidden (open block hidden while streaming). Local errors: 'Ollama isn't running. Open it, then ask again.', 'Start the local server in LM Studio, then ask again.', '<m> isn't installed. Pick another model above the chat box.'; missing key: '<Provider> API key missing. Configure it in Settings.'; local file context inlines up to 24 000 chars + '[truncated]'.
- **Windows:** `windows/src-tauri/src/claude.rs:92-178; windows/src/views/chat.ts:62-97` — One request/response to Anthropic; the whole answer appears at once.
- **Fix:** Add windows/src-tauri/src/local_chat.rs (normalise_url, parse_sse_delta, progressive_filter, filter_thinking_blocks ported 1:1) and an openai_compat path in claude.rs; stream with tauri events ('chat-token' {id, visible}) throttled to 1/15 s; chat.ts pushes a placeholder ChatMessage with empty content (not rendered while empty, like ChatBubble) and updates it in place. Same error strings.
- **Phase:** Phase 6

### CHAT-06 — Different default Claude model

- **Mac:** `NotchBuddy/Sources/App/AppState.swift:329; IslandTypes.swift:133; AppState.swift:472-474` — Default 'claude-sonnet-4-6'; when the fetched list does not contain the saved id it picks the first id containing 'sonnet', else the first.
- **Windows:** `windows/src-tauri/src/claude.rs:23; windows/src-tauri/src/settings.rs:353-355` — Default 'claude-opus-5'; no list, no auto-correction.
- **Fix:** DEFAULT_MODEL = "claude-sonnet-4-6" and port the auto-pick rule into the models_list command from CHAT-04.
- **Phase:** Phase 6

### CHAT-07 — API error wording differs

- **Mac:** `NotchBuddy/Sources/App/ClaudeService.swift:496-527, 531-553, 606-610` — Non-200: the API's own error.message as-is; not_found_error → 'Model not found: <id>. Pick another one in Settings.'; non-JSON → raw body. Transport errors → URLSession localizedDescription. 'Unexpected API response.', 'No response text.'
- **Windows:** `windows/src-tauri/src/claude.rs:180-213, 145-176` — 'Claude API 404 Not Found: <message>', 'Network error: <reqwest error>', 'Bad API response: …'; refusal → stop_details explanation or 'Claude declined this one.'
- **Fix:** In call(): if error.type == 'not_found_error' return format!("Model not found: {model}. Pick another one in Settings."); otherwise return the bare message (no 'Claude API {status}:' prefix); map reqwest errors to a plain sentence without 'Network error:'. Keep the refusal branch (harmless extra).
- **Phase:** Phase 6

### CHAT-08 — Chat sounds/emotes differ (Windows beeps, Mac emotes)

- **Mac:** `NotchBuddy/Sources/App/ClaudeService.swift:548-553, 606-610; IslandViewContent.swift:1069-1089` — No sound on send, answer or error. Answer → triggerEmote(.happy). Error → stateOverride = .error (Mochi wears the error state on the note card) + view .note.
- **Windows:** `windows/src/views/chat.ts:67, 83-91` — Sound.play('send') on submit, 'finish' on answer, 'error' on failure; no emote; stateOverride cleared to null on error.
- **Fix:** Remove the three Sound.play calls; on success call the engine's triggerEmote('happy') (expose through ViewActions); on error set State.stateOverride = 'error' before switching to 'note'.
- **Phase:** Phase 6

### CHAT-09 — Chat does not hold the island or protect a draft

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:1047-1067; AppState.swift:215, 836-841; IslandWindowController.swift:1255-1268` — chatInProgress = draft non-empty OR answer pending; chatHoldsIsland keeps the prompt card from folding when the pointer leaves, and an arriving message neither plays 'question' nor replaces the chat (it is still counted/badged).
- **Windows:** `windows/src/views/chat.ts:62-106; windows/src/island/messages.ts:75-107; windows/src/island/island.ts:330-345` — No hold: a message arriving mid-chat switches the island to the message card and plays 'question'; the pointer leaving can fold a half-typed question away.
- **Fix:** Add State.chatInProgress updated on chat input 'input' events and around submit; include (view==='prompt' && chatInProgress) in fsm.heldOpen; in island/messages.ts handle() skip Sound.play and setView when it is true.
- **Phase:** Phase 6

### CHAT-10 — No window context captured when opening the chat tab

- **Mac:** `NotchBuddy/Sources/App/IslandRootView.swift:721-730; IslandViewContent.swift:2076-2087; ClaudeService.swift:229-242` — Clicking the chat tab with no context captures the frontmost app/window title/URL; the chip reads 'App · host' (or app name) and the first turn carries 'Context — App: X, Window: Y, URL: Z'.
- **Windows:** `windows/src/views/views.ts:121-131; windows/src/views/chat.ts:74-76, 111-117` — Only a dropped file becomes context; the chip shows only State.droppedFile; ChatContext::Window exists in Rust but is never sent.
- **Fix:** Rust command capture_window_context: GetForegroundWindow (taken before the island activates — call it on mousedown of the tab) → GetWindowTextW + process exe description; browser URL via UI Automation for Edge/Chrome address bar (optional, title-only fallback). Set State.promptContext = {kind:'window',…}; chat.ts chip renders from State.promptContext with the Mac label rule and passes it on the first turn.
- **Phase:** Phase 6

### CHAT-11 — Context chip animation and spacing

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:948-950, 2089-2109` — Chip (dot 7 rainbow gradient, 11.5 #F1F2F4, H10 V4, white .1 capsule) appears at scale 1.0 and springs (response .25, damping .55) to 1.06 with a 1.5pt white .75 stroke OVERLAY (no layout change), then after 0.45 s eases out 0.3 s back. 4pt top padding.
- **Windows:** `windows/src/views/chat.ts:33-38; windows/src/style.css:1576-1604, 1677-1685` — Starts already at 1.06 with a real 1.5px border (adds 3px to the chip), transitions to settled after a 0.45 s delay; sits in the 26px-high .chip-row; no top padding.
- **Fix:** Use box-shadow: 0 0 0 1.5px rgba(255,255,255,.75) instead of border; keyframe scale 1→1.06 (spring-like cubic-bezier .3,1.5,.5,1 over 250 ms) then 0.3 s ease-out back after 450 ms; margin-top 4px; do not give the chat chip row the reply chips' fixed 26px height.
- **Phase:** Phase 6

### CHAT-12 — Chat card has no 10pt bottom inset

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:1045` — The whole PromptView ZStack has .padding(.bottom, 10): the card stops 10pt above the island's bottom edge.
- **Windows:** `windows/src/views/chat.ts:52-57; windows/src/style.css:1562-1574` — The chat card fills the full view height.
- **Fix:** .chat-card { height: calc(100% - 10px); }
- **Phase:** Phase 6

### CHAT-13 — Chat scroll indicator and scroll animation

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:953-982` — ScrollView(showsIndicators: false); scrolls to the last non-empty message / typing dots with animation.
- **Windows:** `windows/src/style.css:1606-1616; windows/src/views/chat.ts:121-127` — Thin visible scrollbar; jumps to bottom.
- **Fix:** .chat-log { scrollbar-width: none } and log.scrollTo({top: log.scrollHeight, behavior: 'smooth'}).
- **Phase:** Phase 6

### CHAT-14 — Input locked while waiting for the answer

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:1020-1034, 1069-1089` — Field stays enabled (focus is dropped on send and given back when the answer lands); send button disabled only when the field is empty.
- **Windows:** `windows/src/views/chat.ts:63-66, 130` — input.disabled = true while sending; send button never disabled.
- **Fix:** Do not disable the input; blur on send and refocus after; set send.disabled = input.value === '' (no visual dimming, like the Mac's custom style).
- **Phase:** Phase 6

### CHAT-15 — Chat history cleared on every file drop

- **Mac:** `NotchBuddy/Sources/App/FileDropView.swift:73-162; ClaudeService.swift:182-184 (clearConversation never called)` — Dropping a file keeps the existing chat history and API conversation (context then only rides on the first turn of an empty conversation).
- **Windows:** `windows/src/island/island.ts:766-768` — State.chatHistory = [] and chat_reset on every drop, so the dropped file always becomes first-turn context.
- **Fix:** For strict parity remove the two lines; recommended instead: keep Windows and fix the Mac to reset on drop (see risks).
- **Phase:** Phase 6 — Mac fix proposed, awaits the owner's yes

### MSG-01 — Card background is grey instead of black

- **Mac:** `NotchBuddy/Sources/App/IslandTypes.swift:202-208; IslandViewContent.swift:1987-2042` — Every card (chat, message, list, Home) is #000000 with the radial wash and 1px white .035 stroke.
- **Windows:** `windows/src/style.css:17, 389-396` — --card: #141518.
- **Fix:** --card: #000000 (shared with every other surface; coordinate).
- **Phase:** Phase 4
- **Done:** --card is #000000, the Mac's IslandConst.cardHex. Done with the Now Playing card, where it shows most: the Mac's card is black with only its hairline.

### MSG-02 — Message pop-up and list are tinted by source instead of indigo

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:2382, 2651` — CardBackground(wash: .indigo) → #6366F1 @ 0.5 for every source and for the all-sources list.
- **Windows:** `windows/src/views/message.ts:438; windows/src/views/messages.ts:118` — --wash = SOURCE_COLOR + '8c' (≈0.55) per message/list source; in the all-sources list the wash is never reset, so it keeps the last source's colour.
- **Fix:** Delete both setProperty('--wash', …) lines; card('indigo') already sets the right wash.
- **Phase:** Phase 4

### MSG-03 — Relative time copy ('just now', '5m')

- **Mac:** `NotchBuddy/Sources/App/MessageInbox.swift:58-69` — 'now' under 60 s (also for future stamps), else RelativeDateTimeFormatter .abbreviated in the app language: '5 min. ago', '2 hr. ago', '3 days ago'.
- **Windows:** `windows/src/views/integrations.ts:16-24 used at message.ts:32 and messages.ts:40` — 'just now', '5m', '2h', '3d'.
- **Fix:** Add messageTimeAgo(ms) in core: elapsed < 60 s → t('now'); else new Intl.RelativeTimeFormat(currentLocale, {style:'short', numeric:'always'}).format(-n, unit) with minute/hour/day/week/month/year buckets. Use it only in message.ts and messages.ts.
- **Phase:** Phase 6

### MSG-04 — Message body is 13px / 36px two-line box instead of 12pt / 30pt

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:2253-2259, 2296-2319; MessageBodyMetrics.swift:16-33` — Body and transcript 12pt #9398A1 (failure #FF8D97), TextKit line height 15 → two lines = 30pt; pending/failed transcript 12 italic #6B7079.
- **Windows:** `windows/src/views/message.ts:58-72, 94; windows/src/core/layout.ts:166-167; windows/src/views/dom.ts:76-101; windows/src/style.css:1177-1180, 3051-3065` — class 'sub' = 13px, line-height 1.35, clamp height 36px; transcript also 13px.
- **Fix:** Body/transcript/ruler: font 400 12px var(--font); line-height 15px; MESSAGE_BODY_TWO_LINES = 30; re-dump the message-height parity table.
- **Phase:** Phase 4

### MSG-05 — Microphone sits left of the field instead of next to Send

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:2446-2482; HomeMessageView.swift:98-133` — Bar order: paperclip · text field (or RecordingStrip) · mic · send arrow.
- **Windows:** `windows/src/views/message.ts:252-253` — clip · mic · input · mic-row · send.
- **Fix:** h('div',{class:'chat-bar'}, clip, input, micRow, mic, send).
- **Phase:** Phase 6

### MSG-06 — Recording cannot be discarded (scrap button hidden by CSS)

- **Mac:** `NotchBuddy/Sources/App/VoiceRecordButton.swift:72-104; IslandViewContent.swift:2450-2466` — While recording the field is replaced by [red dot][0:07][spacer][xmark discard]; the paperclip stays visible.
- **Windows:** `windows/src/style.css:2908-2909; windows/src/views/message.ts:248-251` — `.chat-bar.recording .clip-btn:not(.mic-btn){display:none}` also matches the scrap button (class clip-btn inside .mic-row), so there is no discard control, and it hides the paperclip.
- **Fix:** Give scrap its own class (e.g. 'mic-scrap') and change the rule to `.chat-bar.recording .chat-input { display:none }` only.
- **Phase:** Phase 6

### MSG-07 — Reply bar metrics and focus state

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:2460-2492, 2801-2809; HomeMessageView.swift:110-141` — Padding H10 V5; background white .07, .12 while the field is focused; r12; field font 12; send 28x28 white circle, arrow.up 11 semibold, opacity .4 while sending.
- **Windows:** `windows/src/views/message.ts:224-234; windows/src/style.css:1772-1812` — Padding 6/10; no focused state; field 13px; send forced to 24x24.
- **Fix:** Scope to the message card: .chat-bar padding 5px 10px; .chat-bar:focus-within { background: rgba(255,255,255,.12) }; .chat-input font-size 12px; remove the 24px inline size on send (28px).
- **Phase:** Phase 6

### MSG-08 — Paperclip / mic colours and glyphs

- **Mac:** `NotchBuddy/Sources/App/ReplyAttachmentsRow.swift:157-170; VoiceRecordButton.swift:18-38` — paperclip 12 medium and mic.fill (filled) 12 medium, #8E939C idle, #F5F6F8 on hover; recording shows stop.fill #FF8D97.
- **Windows:** `windows/src/style.css:1750-1764, 2919; windows/src/views/icons.ts:59-61; message.ts:237-244, 483` — #6B7079 idle, #F5F6F8 hover; outline mic 13px; recording #ef4444.
- **Fix:** .clip-btn { color: var(--dim-2) }; add a filled mic path (mic.fill) at 12px; .mic-btn.on { color: #ff8d97 }.
- **Phase:** Phase 6

### MSG-09 — Recording strip level dot, colours and clock rate

- **Mac:** `NotchBuddy/Sources/App/VoiceRecordButton.swift:76-103; VoiceRecorder.swift:131-158` — 8pt #FF8D97 dot, scale 0.7+0.3·level and opacity 0.55+0.45·level from live metering ((dB+50)/50, eased ×0.4, 0.25 s ease-out); time 12pt monospaced digits #E7E9EC; discard xmark 9 bold #8E939C; sampled every 0.25 s.
- **Windows:** `windows/src/style.css:2911-2943; windows/src/island/voiceNote.ts:91-93` — #ef4444 dot on a fixed 1.1 s pulse; time #f5f6f8; discard xmark 11px dim-3; ticks every 500 ms.
- **Fix:** Add an AnalyserNode on the stream, sample RMS→dBFS on the existing interval set to 250 ms, apply the same mapping/easing to transform/opacity with transition 0.25s ease-out; colours #ff8d97 and #e7e9ec; xmark 9px #8e939c.
- **Phase:** Phase 6

### MSG-10 — Attachment chips show a dot instead of a thumbnail/icon

- **Mac:** `NotchBuddy/Sources/App/ReplyAttachmentsRow.swift:55-66, 92-150` — 16x16 slot, radius 3: image files show their thumbnail; others a symbol 10pt #8E939C (photo, doc.richtext, doc.text, waveform, paperclip) or the Finder icon.
- **Windows:** `windows/src/views/message.ts:504-519; windows/src/style.css:1599-1604` — A 7px rainbow-gradient chip-dot for every kind (data-kind has no CSS).
- **Fix:** 16px slot; images via convertFileSrc(path) with the asset protocol scoped to the inbox (or a Rust thumbnail command returning a data URL); per-kind SVG icons at 10px #8e939c.
- **Phase:** Phase 6

### MSG-11 — Attachment chip details (truncation, remove button, audio length)

- **Mac:** `NotchBuddy/Sources/App/ReplyAttachmentsRow.swift:15-41, 61-90, 97-107` — Name 11 #E7E9EC max 104pt with MIDDLE truncation; size 10 #6B7079 — or for audio the duration '0:07'; xmark 8 bold #8E939C turning #F5F6F8 while the CHIP is hovered; audio play button fills the 16pt slot (white .14 circle, play.fill/pause.fill 9pt #E7E9EC); notice under chips 10pt #FF8D97 with 4pt spacing.
- **Windows:** `windows/src/style.css:1691-1746, 2947-2961; windows/src/views/message.ts:496-522` — Chip max-width 170 with tail ellipsis; x dim-3 → ink only on its own hover; audio shows byte size; play button 14px white .16.
- **Fix:** att-name max-width 104px with JS middle-ellipsis; .att-chip:hover .chip-x { color: var(--ink) }; for audio chips read duration (Audio element metadata or WAV header) and show clock(); chip-play 16px rgba(255,255,255,.14), 9px glyph.
- **Phase:** Phase 6

### MSG-12 — Only freshly recorded clips can be played back before sending

- **Mac:** `NotchBuddy/Sources/App/VoiceRecordButton.swift:151-159; ReplyAttachmentsRow.swift:97-107` — Any staged audio attachment (picked, dropped or recorded) gets the play button.
- **Windows:** `windows/src/island/voiceNote.ts:206-238` — canPlay() true only for clips recorded this session; a dropped .m4a shows the plain dot.
- **Fix:** Play by convertFileSrc(attachment.path) (or a Rust read_file_bytes) for every kind==='audio'.
- **Phase:** Phase 6

### MSG-13 — Attaching copies files first, breaking duplicate detection and renaming files

- **Mac:** `NotchBuddy/Sources/App/ReplyAttachmentStore.swift:17-36; IslandWindowController.swift:412-416` — Original URLs are staged: same file twice → '<name> is already attached.'; folder → '<name> is a folder.'; nothing is copied before the rules run.
- **Windows:** `windows/src/island/replyAttachments.ts:45-58; windows/src-tauri/src/files.rs:26-70` — ingest_file copies every file into the inbox under a unique name first, so the same file twice becomes 'x.pdf' and 'x (2).pdf' (duplicate never fires), the recipient receives 'x (2).pdf', a folder says 'Folders can't be dropped yet.', and 20 MB+ files are copied before being refused.
- **Fix:** New Rust command stat_paths(paths) → [{path,size,isDir}]; run acceptAttachments on the ORIGINAL paths (isRegularFile:false for dirs); send originals (Rust reads at send time). Keep ingest_bytes only for pastes and recordings.
- **Phase:** Phase 6

### MSG-14 — Rejection notice shown with nothing staged (squeezes the 160 card)

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:2388-2392; ReplyAttachmentsRow.swift:33-38; VoiceRecordButton.swift:45-55; IslandTypes.swift:408-441` — The notice lives inside the attachments row, which exists only while something is staged; a refused microphone instead opens System Settings › Privacy › Microphone.
- **Windows:** `windows/src/views/message.ts:274-275, 521-522; windows/src/core/layout.ts:210-218; windows/src/island/voiceNote.ts:62-72, 188-202` — The notice row shows whenever replyNotice is set, but the card only grows for it when attachments>0, so 14px is squeezed into 160 and rows clip.
- **Fix:** Show .chip-notice only when staged.length > 0 (inside the chip block); on NotAllowedError open 'ms-settings:privacy-microphone' via the opener (closest equivalent).
- **Phase:** Phase 6

### MSG-15 — Received voice-note player sizes, font and label

- **Mac:** `NotchBuddy/Sources/App/VoiceNoteRow.swift:31-166` — HStack spacing 10: skip buttons 18x18, glyph 14pt #F1F2F4, no hover background; play 28 white circle with 12pt bold glyph (+1pt x offset for play), small light ProgressView while loading; track = 4pt capsule (white .12, fill #F5F6F8) in a 12pt hit area, 9pt thumb clamped inside the bar; 5pt gap; times row 10pt system font with monospaced digits #6B7079 and centre label [waveform icon + 'Voice message'] #8E939C (or 'Couldn't load the audio' #FF8D97).
- **Windows:** `windows/src/views/message.ts:80-93, 192-212; windows/src/style.css:2967-3049, 2513-2563` — .vn-skip 22x22 using .np-btn (hover circle, :active scale), 16px glyph; play glyph 14px, no offset; bar hit area 16 (6px padding), track gap 2px; times in var(--mono) (Cascadia Mono); no waveform icon; thumb overflows ±4.5px at the ends.
- **Fix:** .vn-skip 18x18, no hover bg, skipIcon(…,14); play glyph 12px with translateX(1px) for play; np-bar padding 4px for the vn variant and .vn-track gap 5px; .vn-times font 400 10px var(--font) + tabular-nums; prepend a 10px waveform SVG to the label; clamp thumb left to [4.5px, 100%-4.5px].
- **Phase:** Phase 6

### MSG-16 — Home message row: Ato logo missing, extra 'more waiting'

- **Mac:** `NotchBuddy/Sources/App/HomeMessageView.swift:71-95` — Home who-row: HStack spacing 6; Ato shows AtoLogo(side:10), others an 8pt dot; only the time on the right (no 'N more waiting').
- **Windows:** `windows/src/views/message.ts:27-42, 440-442` — Same row as the pop-up: dot for every source, gap 7, and 'N more waiting · age'.
- **Fix:** When home: atoMark(10) from views/logos.ts for ato, gap 6px, and pass others = 0.
- **Phase:** Phase 6

### MSG-17 — Who-row text can wrap

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:2411-2432` — Sender and origin are lineLimit(1) (truncate); time fixedSize.
- **Windows:** `windows/src/style.css:1187-1198; windows/src/views/message.ts:33-41` — Spans have no nowrap/ellipsis; a long channel name wraps and pushes the card.
- **Fix:** .who-row > span { white-space:nowrap; overflow:hidden; text-overflow:ellipsis; min-width:0 }.
- **Phase:** Phase 6

### MSG-18 — Empty pop-up states and read-message fallback

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:2399-2405; HomeMessageView.swift:49-67; MessageInbox.swift:218-223` — No active message → 'Nothing from <Source> yet.' when a list is open, else 'Nothing waiting.', 13pt #8E939C at the 116 gutter; Home empty line 12pt #8E939C, localized. active falls back to the newest UNREAD only.
- **Windows:** `windows/src/views/message.ts:367-375, 417-425; windows/src/core/state.ts:613-620` — Pop-up always 'Nothing waiting.' inside the 12px who-row; Home lines not passed through t(); activeMessage falls back to messages[0] even if read, so the pop-up can show an answered message with a live reply bar.
- **Fix:** activeMessage fallback → this.unreadMessages[0] ?? null; pop-up empty text 13px #8e939c with the list-source variant; wrap Home lines in t().
- **Phase:** Phase 6

### MSG-19 — A new arrival steals the card picked from a list

- **Mac:** `NotchBuddy/Sources/App/MessageInbox.swift:138-141` — activeID = new id only when no list is open.
- **Windows:** `windows/src/core/state.ts:714, 718-720` — Line 714 sets activeMessageId = event.id unconditionally before the guard at 720.
- **Fix:** Delete line 714.
- **Phase:** Phase 6

### MSG-20 — Pill ticker text, lifetime and read-sync

- **Mac:** `NotchBuddy/Sources/App/MessageInbox.swift:155-190, 337-362` — syncPill on ingest/update/markRead: name = sender (or catalog name), state question, steps = [origin ('in <channel>' or source name), body], stepIndex 1, badge .approval unless focused; stays until read; when read it moves to the next unread from that source or back to idle immediately.
- **Windows:** `windows/src/island/messages.ts:21-46, 90-100, 110-127; windows/src/core/state.ts:725-759` — steps = [channel ?? label] (no 'in '), cleared after 60 s even if unread, and never re-synced when a message is answered or dismissed.
- **Fix:** Port syncPill(source) into state.ts and call it from ingestMessage, updateMessage, markMessageRead and dismissMessage; remove scheduleClear/CLEAR_AFTER_MS.
- **Phase:** Phase 6

### MSG-21 — Escape marks the message read

- **Mac:** `NotchBuddy/Sources/App/IslandRootView.swift:775-778; IslandViewContent.swift:2445-2519` — Escape/close collapses the island and the message stays unread (pill still says so).
- **Windows:** `windows/src/views/message.ts:395-399` — Escape in the field calls dismiss(): marks read, moves to the next card/list or default view.
- **Fix:** On Escape: input.blur(); actions.collapse(); do not call dismiss().
- **Phase:** Phase 6

### MSG-22 — Arrival sound/view switch while replying on Home

- **Mac:** `NotchBuddy/Sources/App/IslandWindowController.swift:1255-1268; HomeMessageView.swift:153-156` — While isReplying (pop-up OR Home field focused) or chat hold, no 'question' sound and no switch to the card.
- **Windows:** `windows/src/island/messages.ts:83-106` — Only view==='message' && pinned is protected; 'question' always plays; typing on Home gets replaced by the pop-up.
- **Fix:** typing = State.isPinned && (State.view === 'message' || State.view === 'overview') || chatHold; wrap Sound.play('question') in !typing.
- **Phase:** Phase 6

### MSG-23 — Send sound on pop-up replies

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:2557-2579; HomeMessageView.swift:221; MessageNotifier.swift:209` — Pop-up reply is silent; Home and banner replies play 'send'.
- **Windows:** `windows/src/island/messages.ts:71-72` — Every reply plays 'send'.
- **Fix:** Move Sound.play('send') out of replyToMessage into the home branch of message.ts submit().
- **Phase:** Phase 6

### MSG-24 — Reply field enabled when there is no reply channel

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:2464; HomeMessageView.swift:115` — TextField disabled when sending or conversationID == nil.
- **Windows:** `windows/src/views/message.ts:344-348, 462` — Only disabled while sending; submit then shows 'There is nowhere to reply to this one.'.
- **Fix:** input.disabled = sending || !message.conversationId.
- **Phase:** Phase 6

### MSG-25 — Home 'Open' marks read and clears staging

- **Mac:** `NotchBuddy/Sources/App/HomeMessageView.swift:187-190` — Home Open only opens the link.
- **Windows:** `windows/src/views/message.ts:292-304, 332-336` — openCurrent() → dismiss(): marks read, stops audio, cancels recording, clears files.
- **Fix:** if (home) { actions.openUrl(link); return; }
- **Phase:** Phase 6

### MSG-26 — Answering from the all-sources list returns to the list

- **Mac:** `NotchBuddy/Sources/App/MessageInbox.swift:240-249; IslandViewContent.swift:2591-2615` — The all-sources list sets listSource = nil, so after a reply the card walks straight to the next unread message (any source) and only collapses when none are left.
- **Windows:** `windows/src/views/message.ts:306-322; windows/src/core/state.ts:680-684` — listSource 'all' sends the user back to the list after each reply.
- **Fix:** In dismiss(): treat source === 'all' like no list (fall through to the unreadMessages branch).
- **Phase:** Phase 6

### MSG-27 — No OS notification banners for messages

- **Mac:** `NotchBuddy/Sources/App/MessageNotifier.swift:35-235; MessagingCoordinator.swift:84-90; AppState.swift:290-291; SettingsView.swift:704` — Each message also posts a silent banner (title sender, subtitle origin, body, thread per conversation) with a Reply text box and Open button; default click opens the card; withdrawn when the message is read; 'Also show a macOS notification' toggle (default on); permission asked when a message pill is switched on.
- **Windows:** `none` — Nothing outside the island.
- **Fix:** Windows toast (WinRT ToastNotification via the windows crate, or tauri-plugin-notification for the simple case) with an input box + 'Send' and 'Open' actions, tag = 'notchy.message.<id>', group = conversation; remove via ToastNotificationHistory on read; route activations to the same reply/markRead path. Add 'Also show a Windows notification' setting. Needs an AppUserModelID (shortcut or MSIX).
- **Phase:** Phase 6

### MSG-28 — Connection-problem wording in empty lists

- **Mac:** `NotchBuddy/Sources/App/MessageInbox.swift:436-462; IslandViewContent.swift:2656-2669` — 'Connecting…', 'Not connected.', the failure reason alone; WhatsApp: 'Scan the QR code in Settings to connect WhatsApp.' / unlinked 'Connect WhatsApp in Settings.'; all sources → first problem only; red #FF8D97, 13pt, 2 lines max.
- **Windows:** `windows/src/views/messages.ts:57-64, 121-136; windows/src/core/state.ts:181-186; windows/src-tauri/src/whatsapp.rs:260-264` — 'Not connected' (no period), 'Connection failed · <reason>', QR shown as 'Connection failed · Scan…', unlinked WhatsApp 'Not connected', all problems joined with ' · '.
- **Fix:** Port connectionProblem per source (needsQR state on the Rust side instead of failed+detail; isLinked check) and pick the first non-null for 'all'; -webkit-line-clamp 2.
- **Phase:** Phase 2

### MSG-29 — Messages list chrome (back button, dot, spacing, scrollbar)

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:2650-2726; IslandTypes.swift:262` — Back = chevron.left 10 semibold #6B7079 in a 24x24 plain hit area (no hover fill); all-sources header dot #6B7079; padding L12 R12 V8, header→list 4pt; list without scroll indicator; empty text #8E939C; Mochi botX 65.
- **Windows:** `windows/src/views/messages.ts:67-95, 115; windows/src/style.css:297-317, 1243-1283; windows/src/core/layout.ts:133-136` — Back is a .tab (30x22, #8E939C, hover pill rgba .07/#b0b5be, 12px chevron); all-sources dot #FFFFFF; .stack padding 4 and gap 5; thin scrollbar; empty text #9398a1; botX 72 to compensate for the wider button.
- **Fix:** Dedicated .msg-back {width:24px;height:24px;color:#6b7079;background:none} with a 10px semibold chevron; dot #6B7079 for all; padding 8px 12px, gap 4px; .msg-list scrollbar-width:none; empty colour var(--dim-2); restore botX 65.
- **Phase:** Phase 6

### MSG-30 — Message card row spacing

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:2385-2396` — VStack spacing 6, no vertical padding, centred in 160.
- **Windows:** `windows/src/views/views.ts:92-104; windows/src/style.css:1214-1226` — .stack gap 5px plus 4px top/bottom padding.
- **Fix:** For the message card stack: gap 6px; padding-top/bottom 0.
- **Phase:** Phase 4

### MSG-31 — Placeholder bodies and Rust errors are English-only

- **Mac:** `NotchBuddy/Sources/App/MattermostClient.swift:556-562; AtoClient.swift:652; WhatsAppWebController.swift:155-213, 386; IslandViewContent.swift:2528-2533; VoiceNoteRow.swift:109` — '📎 Sent a file', client errors, 'Reply to %@…', 'Back/Forward Ns' go through L()/LocalizedStringKey (es, pt-BR).
- **Windows:** `windows/src-tauri/src/mattermost.rs:75; ato.rs:701-707; whatsapp.rs:263, 281, 315-364; windows/src/views/message.ts:205-208, 467` — Hard-coded English in Rust (crate::i18n::t exists and is used for 'Voice message') and template literals without t() in TS.
- **Fix:** Wrap these in crate::i18n::t(&current(), …) in Rust and t() in TS (catalog already has '📎 Sent a file' and 'Reply to %@…'; add the rest to i18n/catalog.json).
- **Phase:** Phase 6

### MSG-32 — Ato preview not trimmed / empty preview

- **Mac:** `NotchBuddy/Sources/App/AtoRules.swift:323-326; AtoClient.swift:652` — Preview trimmed; empty → '📎 Sent a file'.
- **Windows:** `windows/src-tauri/src/ato.rs:701-707` — Raw last_message_preview; Some("") becomes an empty body.
- **Fix:** trim and filter empty before unwrap_or_else.
- **Phase:** Phase 6

### MSG-33 — Pointer cursors and hover fills that macOS does not have

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:2743-2789, 2207-2234; ReplyAttachmentsRow.swift:75-81` — Arrow cursor everywhere; SecondaryButton ('Open') has no hover state.
- **Windows:** `windows/src/style.css:450-452, 1293, 1732, 1759, 2996, 2550-2563` — cursor:pointer on rows/clip/x/play; .btn.secondary:hover background .15; .np-btn hover circle.
- **Fix:** cursor: default on those selectors; drop the hover background on .btn.secondary (shared) or at least in the message card.
- **Phase:** Phase 4

### MSG-34 — Messages ignored entirely while Coucou is switched off

- **Mac:** `NotchBuddy/Sources/App/MessageInbox.swift:127-149; MessageNotifier.swift:99-100` — The inbox still ingests (list, pill, Home) — only the banner and the reveal are gated.
- **Windows:** `windows/src/island/messages.ts:75-76` — handle() returns when State.paused, so the message is never stored.
- **Fix:** Always ingestMessage + pill sync; gate only Sound.play and island.reveal/setView on !State.paused.
- **Phase:** Phase 6

### MSG-35 — Voice note file format

- **Mac:** `NotchBuddy/Sources/App/VoiceRecorder.swift:196-221` — AAC .m4a, 44.1 kHz mono 64 kbps (~2.4 MB / 5 min).
- **Windows:** `windows/src/island/voiceNote.ts:25-29, 124-145; windows/src/island/wav.ts` — WebView2 usually only records WebM/Opus, re-encoded to 16 kHz mono WAV (~9.6 MB / 5 min).
- **Fix:** Closest equivalent possible on Windows: send the decoded PCM to Rust and encode AAC .m4a with Media Foundation's built-in AAC encoder (IMFSinkWriter), keeping WAV as the Linux fallback.
- **Phase:** not done — AAC encoding is invisible to users

## Already matches

- Chat user bubble: right-aligned, 32px min left gap, white .13, radius 12, padding 6/10, 12.5px #F1F2F4, selectable
- Assistant plain-paragraph colour/size (12.5 #B0B5BE) and 8px right gap
- Typing dots: 3 × 5px #6B7079, scale 0.6↔1.2, 0.45 s each way, 0.14 s stagger
- Chat input bar: H10 V6, white .07, radius 12, 13px field, 28px white send circle with arrow-up, placeholders 'Ask me anything…' / 'Continue…'
- Chat card paddings L84 T12 R16 B14, row gap 6, indigo wash rgba(99,102,241,0.5)
- Chat height 240 + 40·n capped at 300 (layout.ts:157 = IslandRootView.swift:60-64)
- First-turn context blocks: PDF document, jpg/png/gif/webp image, text ≤200 KB inline as 'File contents:'; 'File: <name>' text; window context sentence format
- Multi-turn history keeps tool_use/tool_result blocks; failed turn popped; 'API key missing. Open settings.'; web_search max_uses 5; max_tokens 4096
- Chat-tab sparkle icon: Windows path is the Mac ChatSparkleShape flattened onto the 24 grid, drawn at 16px
- File-drop flow name handling: droppedFile = first, droppedFiles = all, copy to inbox in background
- Messages list rows: dot 5, sender 11 semibold #C5C8CD, origin/time 10 #6B7079, body 10.5 #9398A1 indented 10, padding 4/8, accent 8%/16% hover, radius 5, 3px gap, newest first
- List header name 12 semibold, 'N waiting' 11 #6B7079, 26px Mochi seat hidden with characters off
- Pop-up who-row: dot 8, sender 12 semibold #F5F6F8, origin 12 #8E939C, 'N more waiting · time' 11 #6B7079
- Origin strings 'in <channel>' / '<Source> · direct'; placeholders 'No reply channel', 'Sending…', 'Reply to <who>…'
- Failure replaces the body in #FF8D97 and keeps the typed text; voice note hides on failure
- Open button (secondary capsule) only when a link exists; reply pins the island on focus; picker holds the card (pickingFile)
- Green 1.5px drop outline on the reply bar while a file hovers
- Attachment rules: kinds, extensions, MIME table, limits 10 / 20 MB / 50 MB, rejection sentences, size labels (parity-tested by scripts/test-reply-attachments.sh)
- Message card height growth with chips/notice/overflow and 650 cap (parity-tested by tests/message-height-parity.ts)
- Voice-note transcript states copy: 'Transcribing…', 'No transcript for this one', 'Voice message', 'Couldn't load the audio'
- Received clip semantics: toggle/seek/skip load on demand, end leaves it loaded at 0 paused, listening holds the card
- Recording rules: 0.5 s minimum, 5-minute cap, 'blip' on start, 'Voice message <yyyy-MM-dd at HH.mm.ss>' and 'Pasted image <stamp>.png' names, 'attach' sound when staged
- Source colours #1B6FF3 / #1B2FEB / #25D366, labels, pill ids, supportsAttachments
- Home resolution automatic/ato/mattermost/whatsapp → lastBySource; Home stays after sending
- Mattermost classify (own message + self-test marker, system_ posts, D/G direct, mentions, monitored channel by name or display name), file-only body, sender override/sender_name trimming, channel nil for DMs, permalink {server}/{team}/pl/{post}, upload-then-post with one 401 re-login
- WhatsApp display name (strip ~), summary 'WhatsApp' gets no reply channel, id prefix 'whatsapp:', link web.whatsapp.com
- Ato queue name only when not assigned to me, '[anexo]' attachment-preview detection, '🎤 Voice message' body until transcript

## Known differences in windows/README.md

- **closable** — 'Not in this version: … dragging Mochi onto a window to attach it as context' (and, unlisted, the chat tab's automatic capture of the frontmost window) Capture on chat-tab mousedown with GetForegroundWindow/GetWindowTextW/QueryFullProcessImageNameW (title-only fallback, UI Automation for browser URL); drag-onto-window via WindowFromPoint at drag end. Feeds the existing ChatContext::Window in claude.rs (CHAT-10).
- **forced** — ChatGPT/site drawn in a separate window rather than inside the island (MESSAGE_EXPANDED_CAP 650 is copied from the Mac's ChatGPT view height) Out of this surface; the built-in chat is unaffected. Keep the copied 650 and add it to a parity dump.
- **closable** — Microphone permission: the OS switch 'Let desktop apps access your microphone' is not Coucou's to answer; card says so Platform-forced in principle, but match the Mac's behaviour: on NotAllowedError open ms-settings:privacy-microphone (the Mac opens the Privacy pane) and only show the notice when something is staged (MSG-14).
- **closable** — Voice note is .m4a only where the webview will record one, otherwise 16 kHz mono WAV Encode AAC/.m4a in Rust with Media Foundation (Windows only); WAV stays the Linux fallback (MSG-35).
- **closable** — File picker is tauri-plugin-dialog Already titled 'Attach to your reply'; the Mac's OK button reads 'Attach' — set it via IFileOpenDialog::SetOkButtonLabel if the picker moves to a Rust command. Minor.
- **forced** — WhatsApp Web runs in its own hidden window with no IPC Not user-visible in the message UI; card behaviour matches. Only the QR/unlinked wording in the list differs (MSG-28).

## Parity tests to add

- ChatMarkdown.parse block list for a fixture set (headings with/without space, nested bullets, ordered lists, quotes, rules, fences) dumped from Swift and compared with the new windows/src/core/chatMarkdown.ts
- ClaudeService.makeSystemPrompt(name:) text (minus the platform sentence) vs claude.rs system_prompt
- ChatProvider table (rawValue, displayName, accentHex, defaultModel, keychainKey, isLocal) and AppState.defaultClaudeModel vs a TS/Rust twin and claude.rs DEFAULT_MODEL
- LocalChat.normaliseURL / parseSSEDelta / filterThinkingBlocks / progressiveFilter vectors (already in tests/ChatParsingTests.swift) run against the Rust port
- Model-list exclusion lists for Google/OpenAI/local (ClaudeService.swift:137, 157-159; LocalChat.swift:93)
- MessageSource displayName/accentHex/pillID vs SOURCE_LABEL/SOURCE_COLOR/PILL_FOR_SOURCE (only supportsAttachments is tested today)
- InboxMessage.timeAgo outputs for fixed deltas (0, 59 s, 61 s, 5 min, 2 h, 3 d, future) vs the TS messageTimeAgo
- MessageBodyMetrics.lineHeight, twoLines, voicePlayerHeight, voiceGap, contentWidth vs MESSAGE_BODY_TWO_LINES, VOICE_PLAYER_HEIGHT, VOICE_GAP, messageBodyWidth
- VoiceNote.durationLabel vs message.ts clock() and the mic timer
- MessageSource.connectionProblem strings per client state vs messages.ts connectionProblem
- MessageInbox.syncPill result (name, state, steps, stepIndex, badge) for sample messages vs the TS port
- IslandConst.cardHex and CardBackground wash colours vs --card and washRGBA
- chatPromptHeight formula (240/40/300) and ViewLayout rows for prompt/message/messages (botX 65 vs 72)
- ChatSparkleShape path flattened to the 24 grid vs icons.ts chatSparkle (generate, don't hand-copy)
- Shared JSON fixtures for Mattermost 'posted' frames → (kind, sender, channel, body) through both MattermostClient.classify/body and mattermost.rs handle_frame/proto::classify_post
- WhatsAppRules.displayName/isSummary/messageID/key vectors vs message_proto.rs twins; AtoRules.body/isAttachmentPreview vs ato_is_attachment_preview
- Body placeholders ('📎 Sent a file', '🎤 ' + 'Voice message') and their catalog keys

## Risks

- The Mac keeps only the FIRST text block of an Anthropic reply (ClaudeService.swift:541-548); with web search the answer is split into many text blocks around citations, so Mac answers can be truncated. Windows joins all blocks (claude.rs:165-172). Do not copy the Mac here — fix the Mac to join.
- The Mac never clears the chat conversation (clearConversation is unused) and only sends context on the first turn, so a file dropped after chatting is silently ignored on the Mac. Windows resets on drop. Recommend fixing the Mac rather than regressing Windows (CHAT-15).
- CHAT-03 (Markdown prompt) must ship with CHAT-01/02 (renderer); alone it makes Windows show raw ** and ``` .
- Changing --card to #000000 (MSG-01) touches every view on Windows; it is shared with other surfaces' audits.
- Changing the message body to 12px/15px (MSG-04) changes island sizing and the message-height parity table; update both sides' dumps together.
- Markdown links come from model output: Windows has no TS port of SafeWebURL.swift — port it (with scripts/test-safe-links.sh vectors) before making links clickable.
- Toast replies (MSG-27) need a registered AppUserModelID; unpackaged dev builds may not receive activations; reply-from-toast must reuse the same send path and withdraw on read.
- Window-context capture (CHAT-10) must read the foreground window before the island activates, otherwise it captures Coucou itself.
- Multi-provider chat (CHAT-04/05) means storing Google/OpenAI keys in Credential Manager and calling localhost servers; do it in Rust, not webview fetch (CSP).
- MSG-13 changes when files are read: sending originals means a file moved/deleted between staging and sending fails at send time (the Mac has the same behaviour).
- Whether WebView2 exposes Explorer-copied files in clipboardData.files on paste was not verified; the Mac attaches copied files and PNG/TIFF images.
- Several Mac strings (e.g. 'Ask me anything…', 'N more waiting · …', 'Nothing from X yet.' in the pop-up) are not in i18n/catalog.json, so both platforms show English for them; that is parity, not a Windows gap.
- The user's separate question about T3 Code / Tailscale and the API-key error is outside this surface and was not investigated here.
