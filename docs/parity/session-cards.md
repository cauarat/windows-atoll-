# Parity — Claude Code cards and Home

The Mac is the source of truth (see `CLAUDE.md`). Each gap names the Mac code, the Windows code and the fix; tick it in the PR that closes it. Audit of 2026-11-20 against `notchy` at f1dee26.

## Checklist

- [ ] **SC-G01** · high · visual · S — Card background is grey #141518 instead of black #000000 — _Phase 4_
- [ ] **SC-G02** · high · visual · M — Standard cards are 108px tall instead of 98pt with a 5pt inset — _Phase 4_
- [ ] **SC-G04** · high · missing on windows · M — Approval buttons: Windows shows N/Y hints that do nothing and has no 'Always' — _Phase 5_
- [ ] **SC-G06** · high · behaviour · S — An approval does not take focus or open the island unless its pill is already focused — _Phase 5_
- [ ] **SC-G07** · high · missing on windows · M — Approval card is not dismissed when the request is answered in the terminal; no 'Handled in…' or 'Still waiting…' note — _Phase 5_
- [ ] **SC-G09** · high · missing on windows · L — AskUserQuestion card is missing; Windows has a placeholder telling the user to answer in the terminal — _Phase 5_
- [ ] **SC-G10** · high · missing on windows · L — Finished card has no list of touched files and no diff drill-down — _Phase 5_
- [ ] **SC-G11** · high · missing on windows · L — No live diff steps in the ticker and no DiffEngine — _Phase 5_
- [ ] **SC-G12** · high · behaviour · S — Finished title reads the wrong field and is cut to 60 characters — _Phase 5_
- [ ] **SC-G25** · high · behaviour · S — Home has no 'Notifications' choice and defaults to 'automatic' — _Phase 1_
- [ ] **SC-G27** · high · missing on windows · L — AI Agents panel is missing (and the README describes a dashboard that no longer exists) — _Phase 5_
- [ ] **SC-G03** · medium · visual · S — Approval CodeBlock stretches full width and truncates instead of hugging its text and wrapping — _Phase 5_
- [ ] **SC-G05** · medium · copy · S — Approval target text differs: Mac shows the Bash command or else the tool name; Windows shows 'Tool · path/url/pattern' — _Phase 5 — copy the Mac; porting Windows' richer target to the Mac awaits the owner's yes_
- [ ] **SC-G08** · medium · behaviour · S — A second approval is refused instead of replacing the first — _Phase 5_
- [ ] **SC-G13** · medium · behaviour · M — 'Open terminal' opens VS Code and leaves the island open — _Phase 5_
- [ ] **SC-G14** · medium · visual · S — Ticker ignores whether the task is still active — _Phase 5_
- [ ] **SC-G16** · medium · behaviour · S — ↗ jump button on the Claude Code card opens VS Code instead of the terminal — _Phase 5_
- [ ] **SC-G17** · medium · copy · S — Step labels: truncation, Bash verbs and tool table differ — _Phase 5_
- [ ] **SC-G18** · medium · behaviour · S — External agents (agent_*) on Home show the integration idle card instead of the ticker — _Phase 5_
- [ ] **SC-G19** · medium · copy · S — Claude Code pill is called 'VS Code' on Windows — _Phase 5_
- [ ] **SC-G21** · medium · copy · S — Error card content: Mac is a static placeholder, Windows is dynamic — _Phase 5 — copy the Mac; a real Mac error card awaits the owner's yes_
- [ ] **SC-G22** · medium · behaviour · S — Alerts can replace a pending approval card — _Phase 5_
- [ ] **SC-G23** · medium · behaviour · M — Agent routing: terminal filter, Cursor/Codex pills, external agent colour — _Phase 5_
- [ ] **SC-G26** · medium · visual · M — Home message face: type sizes, who row and reply bar differ — _Phase 4_
- [ ] **SC-G28** · medium · visual · S — Compact bar geometry: width, mini grid and timer colour — _Phase 4_
- [ ] **SC-G29** · medium · extra on windows · S — Header has two extra tabs and the right group is in a different order — _Phase 4 — Integrations and Site tabs kept (owner); right group reordered_
- [ ] **SC-G34** · medium · platform forced · M — System font, SF Mono and SF Symbols — _Phase 4_
- [ ] **SC-G15** · low · visual · S — Ticker transition timing is slightly different — _Phase 5_
- [ ] **SC-G20** · low · copy · S — Claude Code idle card: status copy, Settings link and spacing — _Phase 5_
- [ ] **SC-G24** · low · behaviour · S — Minor hook-event differences — _Phase 5_
- [ ] **SC-G30** · low · behaviour · S — Confused view: invisible header still takes clicks; gutter and hold differ — _Phase 4_
- [ ] **SC-G31** · low · extra on windows · S — Buttons get hover/press effects the Mac does not have; decisions play sounds — _Phase 4_
- [ ] **SC-G32** · low · visual · S — Island resize motion is not scaled by distance — _Phase 4_
- [ ] **SC-G33** · low · copy · S — Step strings and Home empty lines are not translated on Windows — _Phase 5_

## How each side is built

MAC (source of truth). IslandRootView -> ZStack[IslandEdgeRingView, IslandContainer]. IslandContainer draws IslandShape (black, bottom corners 22 expanded / 14 compact, flat top hanging from the notch), snow, then IslandContentView = VStack(padding top 8, bottom 10){ IslandHeader 34pt [left HStack(5): Home, Chat, Clipboard | Spacer | right HStack(5): Agenda?, Hydration, Timer | HStack(14): gearshape, speaker, xmark]; ZStack of EVERY IslandViewContent at once, padding h10, where every non-tall view is framed at height 98 and centred in the 108pt slot (5pt black above and below the card) }, then BotPlacement (Mochi + glow), CountdownBar, and in compact mode CompactTimerBadge / CompactHydrationCue / CompactMiniGrid on the right (x = w-40). IslandViewContent switch: overview -> OverviewView (by HomeContent: timer -> FocusTimerView; notifications/automatic/ato/mattermost/whatsapp -> HomeMessageView; claudeCode -> focusedPill = CardBackground + [IntegrationCardView | who-row + TickerView] + DiffCardView overlay + 16pt jump button); empty -> EmptyStateView; approval -> ApprovalView (amber: AgentWho, CodeBlock, Deny/Allow/Always); question -> QuestionView (cyan: asking header + counter + Reply in terminal, header label, question, option chips with 1-4 shortcuts, Other... inline field, Send/Next); error -> ErrorView (red, static copy); finished -> FinishedView (green: AgentWho, final line, Open terminal/OK, touched files -> DiffCardView); confused -> ConfusedView (pink). Shared atoms: CardBackground (radius 20, #000000, radial wash at (0.5,1.3) r280 stop 0.7, 1pt white .035 stroke), AgentWho, CodeBlock, PrimaryButton, SecondaryButton, TickerView/TickerRowView/TickerShimmerText, DiffCardView/DiffLineRowView. The AI Agents panel is a separate 420x480 borderless NSPanel (AgentsPanelController + AgentsPanelView: header 'AI Agents' + 'Account' card + 'Running here' card), opened from the 'agents' edge button, the radial menu or Settings. Data path: nb-hook (python, Unix socket) -> HookServer.processEvent / processPermissionRequest / processQuestionRequest -> AppState (tasks, pendingApproval, pendingQuestion, sessionDiffs, finalLine) -> views. WINDOWS. island.ts builds #island > #island-clip > [snow, greeting canvas, upload canvas, #content(padding 8/10/10) > [#header (views.ts buildHeader: left Home, Chat, Clipboard, Integrations, Site | right Agenda, Timer, Water | gear, speaker, close), #views > one .view per IslandViewName (absolute inset 0, so each card fills the whole 108px)]] plus bot canvas/glow, #mini-grid, #compact-timer, #countdown, and the edge ring as a sibling. views.ts has one buildX() per Swift struct (buildOverview with four home faces, buildEmpty, buildApproval, buildQuestion (placeholder), buildError (dynamic), buildFinished, buildConfused, buildNote, plus an extra buildIntegrations tab); ticker.ts ports TickerView; integrations.ts ports IntegrationCardView; message.ts serves both the pop-up and Home's message face. CSS classes stand in for the Swift atoms (.card = CardBackground, .btn.primary/.secondary = Primary/SecondaryButton, .who-row = AgentWho, .code = CodeBlock, .stack = the VStack with the lead() gutter via --gutter/--flush). Data path: coucou-hook (Rust) -> pipe.rs (named pipe / Unix socket; only PermissionRequest is held open, everything else is emitted and closed) -> 'hook' event -> island/hooks.ts -> core/state.ts. There is no DiffEngine, no AskQuestion model, no sessionDiffs/finalLine, no question relay mode and no AI Agents panel on Windows. The mirroring is close at the atom level, but the data layer is a reduced port, so several Mac cards are missing or never reached.

## Gaps

### SC-G01 — Card background is grey #141518 instead of black #000000

- **Mac:** `NotchBuddy/Sources/App/IslandTypes.swift:202-208; IslandViewContent.swift:1987-2012 (commit f03cf70 'Make the cards black')` — Every card (CardBackground and UploadingView) fills with IslandConst.cardHex = #000000, so cards read as part of the black notch and the coloured washes glow out of black.
- **Windows:** `windows/src/style.css:17 (--card: #141518), 389-396 (.card background: var(--card)); style.css:1891,1896 (upload card)` — Every .card is #141518, a grey slab inside the black island. This is the exact look the Mac commit removed.
- **Fix:** In style.css set --card: #000000 (island stylesheet only; settings.css has its own --card). Check the .up-card rules at 1889-1897, which also use var(--card). Leave --card-flat (#0e0f11, used by pills and the drop zone) alone unless that surface is audited separately. Add the value to a parity dump (see parity_test_opportunities).
- **Phase:** Phase 4

### SC-G02 — Standard cards are 108px tall instead of 98pt with a 5pt inset

- **Mac:** `NotchBuddy/Sources/App/IslandRootView.swift:623-671 (frame(height: isTall ? nil : 98) inside a 108pt ZStack, centred)` — In a 160pt island the slot under the header is 108pt (160-8-34-10). Non-tall views (overview pill/message faces, empty, approval, question, error, finished, confused, note, message, sip) are framed at 98pt and centred, leaving 5pt of black between the header and the card and 15pt below the card. Tall views (prompt, timer, messages, hydration, agenda, Home holding timer/player, a reply with files, a grown message body, large screens) fill the slot.
- **Windows:** `windows/src/style.css:358-378 (#views flex:1, .view position:absolute inset:0), 389-396 (.card height:100%)` — Every .view is inset:0, so each card is 108px, sits flush under the header and stops 10px from the island's bottom. Cards look 10px taller and have no gap under the tabs.
- **Fix:** Add a 'tall' rule that mirrors IslandRootView.swift:648-655. Default .view { top:5px; bottom:5px } (98px card). Add a .view.tall { top:0; bottom:0 } class that island.ts syncDom toggles using the same predicate: prompt, timer, messages, hydration, agenda, overview when homeKind() is timer or player, message/overview with replyAttachments or bodyOverflow>0. Put the predicate in core/layout.ts (isTallView) so it can be parity-tested against Swift.
- **Phase:** Phase 4

### SC-G03 — Approval CodeBlock stretches full width and truncates instead of hugging its text and wrapping

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:2062-2074 (CodeBlock), 256-258` — CodeBlock is a Text inside a leading-aligned VStack. The box is only as wide as the command, and a long command wraps onto more lines (no lineLimit).
- **Windows:** `windows/src/style.css:1200-1212 (.code white-space:nowrap; text-overflow:ellipsis), 1214-1226 (.stack column, align-items defaults to stretch)` — The .code div stretches to the full card width (visible in windows/screenshots/approval.png) and cuts the command to one line with an ellipsis.
- **Fix:** .code { align-self:flex-start; max-width:100%; white-space:pre-wrap; word-break:break-word; } and drop nowrap/ellipsis. If wrapping can overflow the 98px card, clamp it with -webkit-line-clamp to the lines that fit, but keep the hugging width.
- **Phase:** Phase 5

### SC-G04 — Approval buttons: Windows shows N/Y hints that do nothing and has no 'Always'

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:259-272; HookServer.swift:751-765; nb-hook 1347-1364 (always -> updatedPermissions from permission_suggestions; plain allow for codex)` — Three capsule buttons in this order: SecondaryButton 'Deny', PrimaryButton 'Allow', SecondaryButton 'Always' (hidden when pillId == agent_codex). No kbd hints and no keyboard shortcuts. 'Always' sends permissionDecision 'always', and the relay answers allow + updatedPermissions = payload.permission_suggestions, so Claude Code remembers the rule.
- **Windows:** `windows/src/views/views.ts:577-586; windows/src/island/island.ts:1556-1559 (only Escape is handled); windows/src-tauri/src/pipe.rs:306-313 (always collapsed to allow); windows/hook/src/main.rs:76-87` — Two buttons, 'Deny [N]' and 'Allow [Y]', each with a kbd badge. Pressing N or Y does nothing because there is no handler. There is no 'Always', and the Rust side would turn one into a plain allow anyway.
- **Fix:** In buildApproval call btn(...) without the kbd argument and add btn('Always','secondary',()=>actions.decide('always')) after Allow (hide it for codex once codex routing exists). Widen ViewActions.decide to 'allow'|'deny'|'always'. In pipe.rs answer(), pass 'always' through unchanged. In hook/src/main.rs decision_json(), make 'always' emit {behavior:'allow', updatedPermissions: <payload.permission_suggestions>}. The relay still holds the payload in main(), so pass it into decision_json.
- **Phase:** Phase 5

### SC-G05 — Approval target text differs: Mac shows the Bash command or else the tool name; Windows shows 'Tool · path/url/pattern'

- **Mac:** `NotchBuddy/Sources/App/HookServer.swift:686 (command = tool_input.command ?? tool), IslandViewContent.swift:258` — The CodeBlock shows the raw command for Bash. For Edit, Write, WebFetch and so on it shows only the tool name, e.g. 'Write'.
- **Windows:** `windows/src/island/hooks.ts:101-127 (APPROVAL_FIELDS/approvalTarget), 300-305` — Always shows 'Tool · <first of command|file_path|path|url|query|pattern|prompt>', e.g. 'Write · C:\...\.env'.
- **Fix:** For strict parity, set command = tool_input.command ?? tool. The better fix is to port approvalTarget into HookServer.processPermissionRequest so both platforms show the richer target; flag this choice to the owner (see risks).
- **Phase:** Phase 5 — copy the Mac; porting Windows' richer target to the Mac awaits the owner's yes

### SC-G06 — An approval does not take focus or open the island unless its pill is already focused

- **Mac:** `NotchBuddy/Sources/App/HookServer.swift:703-714 (focusBeforeApproval saved, focusId = pillId with spring(0.5,0.72), expandIfNeeded(.approval)); 783-790 (focus restored)` — Every approval saves the current focus, switches focus to the owning pill, and force-expands onto the approval card. After a decision or dismissal the previous focus is restored.
- **Windows:** `windows/src/island/hooks.ts:309-320` — If integration_claude is not focused, Windows only sets a badge and reveals the compact bar. The relay was already told the card is up (ack), so Claude Code waits up to 108s on a card nobody can see.
- **Fix:** In hooks.ts PermissionRequest: store focusBeforeApproval = State.focusId, call State.setFocus(CLAUDE_ID), and always call island.alert('approval'). In decide() and in the timeout/dismiss paths, restore the saved focus if focus is still CLAUDE_ID and the saved task still exists.
- **Phase:** Phase 5

### SC-G07 — Approval card is not dismissed when the request is answered in the terminal; no 'Handled in…' or 'Still waiting…' note

- **Mac:** `NotchBuddy/Sources/App/HookServer.swift:399-429 (dismiss on matching PostToolUse/PostToolUseFailure, or Stop/StopFailure/UserPromptSubmit/SessionEnd/Interrupt for the same session), 60-86 (dismissApprovalCard -> NoteView 3s -> collapse), 716-732 (fd EOF), 734-746 (115s -> 'Still waiting in VS Code.')` — If the user answers in VS Code, the matching PostToolUse (same session, tool and sorted-key tool_input), the end of the turn, or the relay closing the socket dismisses the card. The island shows a Note ('Handled in VS Code.', 15pt semibold, gutter 98) for 3s and then collapses. After 115s it shows 'Still waiting in VS Code.'.
- **Windows:** `windows/src/island/hooks.ts:217-224, 321-333 (only a silent 110s timeout); windows/src-tauri/src/pipe.rs:231-241 (no read on the pipe while waiting)` — The card stays pinned until the 110s timeout and then silently switches to Home. A request answered in the terminal leaves a stale, pinned Allow/Deny card on screen.
- **Fix:** Store inputKey (JSON.stringify of tool_input with sorted keys) on State.pendingApproval. In hooks.ts, on PostToolUse/PostToolUseFailure with the same session_id+tool+inputKey, or on Stop/StopFailure/UserPromptSubmit/SessionEnd for the same session_id, call a dismissApproval(note) that clears the pin and badge, sets State.noteMessage = t('Handled in VS Code.'), calls setView('note') and collapses 3s later. On timeout use t('Still waiting in VS Code.'). In pipe.rs, race the decision wait against a read on the relay connection; on EOF emit an 'approval-gone' event that the island treats as handled.
- **Phase:** Phase 5

### SC-G08 — A second approval is refused instead of replacing the first

- **Mac:** `NotchBuddy/Sources/App/HookServer.swift:688-700` — A new PermissionRequest sends 'ask' to the old one (Claude Code re-asks it in the terminal) and the card shows the newest request.
- **Windows:** `windows/src/island/hooks.ts:289-295` — The new request is declined and the old card stays.
- **Fix:** When a new request arrives, call Bridge.approvalDecline(old.requestId) and replace State.pendingApproval with the new request (re-ack it and restart the timeout).
- **Phase:** Phase 5

### SC-G09 — AskUserQuestion card is missing; Windows has a placeholder telling the user to answer in the terminal

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:284-466 (QuestionView), 1096-1121 (ChipFlowLayout); AskQuestion.swift:1-60; HookServer.swift:123-174, 310-321, 795-880; nb-hook --ask mode 1231-1279` — Cyan-wash card, VStack spacing 4, leading 116 (flush 16), trailing 16, vertical 4. Header row: grey 'Claude Code is asking' (12pt #8E939C, no dot or name), Spacer, 'i/n' (10pt #6B7079) when there are several questions, underlined 'Reply in terminal' (10pt #6B7079, sends 'ask'). Optional header label (10pt #6B7079, max 12 chars). Question text 13pt semibold #F5F6F8, at most 2 lines. Options wrap with spacing 6. Single-select: each option is a SecondaryButton with keyboard shortcut 1-4 that answers and advances or sends. Multi-select chips: 12pt medium, padding 8/4, radius 7; selected bg #22D3EE@0.22, text #67E8F9, 1pt stroke #22D3EE@0.55; unselected bg white@0.07, text #C5C8CD, stroke white@0.10; then a PrimaryButton 'Send'/'Next' at opacity 0.4 while nothing is chosen. 'Other…' SecondaryButton opens an inline field ('Your answer…', 12pt, padding 8/5, bg white .07, radius 8, focused, Enter commits, Esc closes), a capsule 'Send'/'Next' (11 medium, bg white .15 or .05 when empty) and a '✕' (9pt). Answers: a string for single-select, an array for multi-select (AskQuestion.buildAnswers). The card pins the island, plays the 'approval' sound, moves focus like an approval, times out after 120s ('ask'), and sends 'ask' if it leaves the screen.
- **Windows:** `windows/src/views/views.ts:591-609 (static placeholder, and nothing routes to 'question'); windows/src-tauri/src/pipe.rs:214-219 (only PermissionRequest is held open); windows/hook/src/main.rs:50 (only PermissionRequest waits)` — Unreachable. buildQuestion draws the focused pill's dot and name, 'Claude Code is asking a question', the last step or 'Claude needs an answer.', and 'Answer in your terminal — Notchy can't reply for you yet.'. The relay never holds an AskUserQuestion connection.
- **Fix:** (1) Port AskQuestion.parse/buildAnswers to core/askQuestion.ts. (2) In coucou-hook add an '--ask' mode: exit if tool_name != AskUserQuestion, tag coucou_kind='ask_user_question', wait up to about 125s, and on {permissionDecision:'answer',answers} print {hookSpecificOutput:{hookEventName:'PreToolUse',permissionDecision:'allow',updatedInput:{questions,answers}}}. (3) In pipe.rs, hold ask_user_question connections open like PermissionRequest and add an 'answer' Reply carrying the answers JSON. (4) In hooks.ts, set State.pendingQuestion, pin, play the 'approval' sound, take focus and alert('question'); skip the AskUserQuestion step on PreToolUse. (5) Rewrite buildQuestion to the Mac layout: a flex-wrap gap 6 row, .btn.secondary options, .q-chip multi-select chips with the colours above, a digit 1-4 keydown handler while view==='question', and the Other… field. (6) Document the PreToolUse matcher 'AskUserQuestion' -> 'coucou-hook --ask' in docs/INTEGRATIONS.md, because hooks are installed by hand on Windows.
- **Phase:** Phase 5

### SC-G10 — Finished card has no list of touched files and no diff drill-down

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:498-585 (FinishedView), 589-722 (DiffCardView/DiffLineRowView); AppState.swift:733-786 (sessionDiffs, touchedFiles, 50-diff cap, 1h expiry)` — Under the buttons, up to 4 touched files in a VStack(spacing 2): file name 10.5pt #9398A1 (middle truncation), then '+N' (9pt medium mono #22C55E) and '−N' (9pt medium mono #F4505E). '+ N more' (10pt #6B7079) when there are more. Clicking a file cross-fades (easeIn 0.16) to DiffCardView: a header with chevron.left 8pt + file name 12 semibold #F5F6F8, '+N/−N' 10pt medium mono, and a 14px ↗ circle that opens the file in VS Code ('code -g path:1' for new files). Below it a scrolling list of rows: a 12px symbol column + text, both 10.5pt mono; added rows bg #22C55E@.12 / text #86EFAC; removed rows bg #F4505E@.12 / text #FCA5A5; context rows text #6B7079 with symbol #454850. Empty states: 'Diff too large' / 'No changes' (10.5pt #6B7079). Padding leading 108 (flush 10), trailing 10, vertical 4. Esc goes back.
- **Windows:** `windows/src/views/views.ts:634-652` — Only the who row, title and two buttons. No file list and no diff view.
- **Fix:** Depends on G11. Add touchedFiles(pillId) to state.ts. In buildFinished append a .touched list (rows as above) and a diff overlay built by a shared buildDiffCard(diff, onDismiss) in views/diff.ts. Add CSS .diff-line.add/.del/.ctx using the exact hex values. The ↗ calls Bridge.openInVSCode(path, line?).
- **Phase:** Phase 5

### SC-G11 — No live diff steps in the ticker and no DiffEngine

- **Mac:** `NotchBuddy/Sources/App/HookServer.swift:465-474, 1027-1062; DiffEngine.swift:1-270 (LCS, 3-line context hunks, 200KB/4000-line/1e6 guards, toOneLine, U+E001 diff-step encoding); IslandViewContent.swift:147-154, 1826-1867` — PostToolUse of Edit, MultiEdit or Write appends a diff step. The ticker shows it as the file name (13pt medium) followed by ' +N' (10pt medium mono #22C55E) and ' −N' (#F4505E). Tapping the row opens DiffCardView over the Home card, and the ↗ jump button hides while it is open.
- **Windows:** `windows/src/island/hooks.ts:217-219 (PostToolUse only sets state); windows/src-tauri/src/hooks.rs:203 (empty '// Minimal unified diff (LCS)' heading left behind); windows/src/views/ticker.ts` — Edits appear only as 'Edits · file.ts' from PreToolUse. There are no counts, nothing is tappable, and there is no diff.
- **Fix:** Port DiffEngine.swift to core/diffEngine.ts (or Rust behind a command), including makeDiffStep/parseDiffStep with the same U+E001 marker. On PostToolUse build the FileDiff, appendSessionDiff (ids increase, cap 50, expire after 1h), and append the diff step. Teach ticker.ts makeRow to render diff steps (file name plus coloured counts, click -> onDiffTap) and buildOverview to overlay the diff card and hide .jump while it is open. Raise or skip coucou-hook's MAX_FIELD_LEN (2000) for old_string, new_string and content, or diffs will be computed on truncated text (see risks).
- **Phase:** Phase 5

### SC-G12 — Finished title reads the wrong field and is cut to 60 characters

- **Mac:** `NotchBuddy/Sources/App/HookServer.swift:491-502 (last_assistant_message ?? message, DiffEngine.toOneLine up to 200 chars, stored as finalLine and as a step), IslandViewContent.swift:511-515 (finalLine ?? last non-diff step ?? 'Session finished'); SessionStart/UserPromptSubmit/PreToolUse/SessionEnd reset finalLine (436, 444, 454, 534)` — The green card's 15pt title is Claude's last answer as one line of plain text (markdown **, __, `, # stripped, whitespace collapsed, at most 200 chars).
- **Windows:** `windows/src/island/hooks.ts:17-29 (no last_assistant_message field), 239-241 (payload.message.slice(0,60)); views/views.ts:649` — Claude Code's Stop payload carries last_assistant_message, which Windows never reads. The title is usually the last tool step (e.g. 'Runs · npm test'), or a raw markdown fragment cut at 60 characters.
- **Fix:** Add last_assistant_message to HookPayload. Port toOneLine. On Stop set task.finalLine = toOneLine(last_assistant_message ?? message) and append it as a step. Clear finalLine where Mac does. In buildFinished use finalLine ?? the last non-diff step ?? t('Session finished'). Add finalLine to the AgentTask interface.
- **Phase:** Phase 5

### SC-G13 — 'Open terminal' opens VS Code and leaves the island open

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:518-529` — Activates the first running terminal (Terminal, iTerm2, kitty, Ghostty), otherwise launches Terminal.app, then posts .islandCollapse.
- **Windows:** `windows/src/island/island.ts:279-282; windows/src/views/views.ts:640` — Bridge.openInVSCode(cwd), and the island stays expanded.
- **Fix:** Add a Rust command focus_terminal(cwd). It enumerates top-level windows (EnumWindows + process image name) for WindowsTerminal.exe, pwsh.exe, powershell.exe, cmd.exe, wezterm-gui.exe or alacritty.exe and calls SetForegroundWindow on the first one found. If none is running, it launches 'wt.exe -d <cwd>' (or 'cmd /c start powershell' when wt is missing). On Linux it does the same with the $TERMINAL / x-terminal-emulator fallback. Then call actions.collapse(). Use the same command for G16.
- **Phase:** Phase 5

### SC-G14 — Ticker ignores whether the task is still active

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:1718, 1820-1824` — isActive = task.state is thinking or working. When it is not (finished, idle, approval and so on), the chevron is hidden, the checkmark shows on every row, the shimmer is off, and the current row is static #C9CDD4 while the completed row stays #6B7079.
- **Windows:** `windows/src/views/ticker.ts:63-71, 98-127` — The current row always shimmers with a chevron, even after the session has stopped.
- **Fix:** Pass isActive into Ticker.sync and place(). When it is false: chevron opacity 0, check opacity 1, shimmer 0, dim 1, and dim colour #C9CDD4 for phase < 0.5 (otherwise #6b7079).
- **Phase:** Phase 5

### SC-G15 — Ticker transition timing is slightly different

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:1774-1810, 1900-1920` — Row A uses easeOut 0.28s to y -22 and opacity 0. Rows B and C use timingCurve(0.4,0,0.2,1) 0.38s. The commit happens 0.50s later. The shimmer is a moving 3-stop gradient (phase-0.3, phase, phase+0.3) sweeping -0.1 to 1.1 every 2.2s. A step that arrives mid-transition is dropped.
- **Windows:** `windows/src/views/ticker.ts:15-21, 129-155; windows/src/style.css:1072-1093` — A single 380ms clock. A's fade is linear (p*1.35) and its position uses the B/C curve. The commit is at 380ms. Bursts are queued (an improvement). The shimmer is a CSS background with 260% size and 0/40/70% stops.
- **Fix:** Give A its own easeOut(0.28) curve for y and opacity and add a 120ms hold before commit (DURATION 380, COMMIT 500). Keep the queue. Optionally drive the shimmer from tick() with the Mac's stop formula.
- **Phase:** Phase 5

### SC-G16 — ↗ jump button on the Claude Code card opens VS Code instead of the terminal

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:192-216; PillActions.swift:170-182` — For integration_claude, activates the running terminal app (Claude Code runs in a terminal; the pill 'has not meant Visual Studio Code for a long time').
- **Windows:** `windows/src/island/island.ts:287-290, 1024-1028` — Calls openInVSCode(sessionCwd).
- **Fix:** Make openPillTarget(ALWAYS_LOADED_PILL) call the focus_terminal command from G13. Keep 'Open Visual Studio Code' on the idle card for VS Code.
- **Phase:** Phase 5

### SC-G17 — Step labels: truncation, Bash verbs and tool table differ

- **Mac:** `NotchBuddy/Sources/App/HookServer.swift:950-1023 (labels incl. codex apply_patch/update_plan/spawn_agent, mcp__server__tool -> 'server · tool', bashVerb), 1064-1069 (oneLine: newlines/tabs collapsed, cut at 60 + '…')` — 'Runs · npm install foo…' with multi-line commands joined onto one line, cut at 60 characters with '…'. Bash verbs are inferred: cat/head/tail -> 'Reads', rg/grep/find/ls -> 'Finds', test runners -> 'Tests'. MCP tools read 'server · tool'. Queries go through oneLine as well.
- **Windows:** `windows/src/island/hooks.ts:70-99` — cmd.slice(0,40) with no collapsing (a newline breaks the row), no '…', every Bash call is 'Runs', MCP tool names are shown raw, codex tools are missing. PowerShell -> 'Runs' is extra.
- **Fix:** Port stepLabel, bashVerb and oneLine exactly (limit 60 plus '…'). Keep PowerShell -> 'Runs' and run its first word through bashVerb as well (Get-Content -> Reads, Select-String/Get-ChildItem -> Finds). Add a fixture-driven parity test.
- **Phase:** Phase 5

### SC-G18 — External agents (agent_*) on Home show the integration idle card instead of the ticker

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:94-144 (non-integration task -> who row + TickerView, subtitle 'Agent' for .agent), 111-117` — A focused coucou_agent pill (isIntegration false) shows the same ticker layout as Claude Code, with the subtitle 'Agent'.
- **Windows:** `windows/src/views/views.ts:300-337 (ticker only when task.id === 'integration_claude'; subtitle hard-coded as 'Claude Code' : 'n8n')` — Falls through to renderIntegrationCard -> idleCard, so it shows 'Integration' and 'Key not configured' in red. The subtitle would read 'n8n' for any non-Claude source.
- **Fix:** Use the ticker when task.isIntegration === false, or when task.id is a workspace pill with state != idle or steps.length > 0. Subtitle: claudeCode -> 'Claude Code', agent -> 'Agent', n8n -> 'n8n'.
- **Phase:** Phase 5

### SC-G19 — Claude Code pill is called 'VS Code' on Windows

- **Mac:** `NotchBuddy/Sources/App/PillCatalog.swift:82 (name 'Claude Code'); AppState.swift:1027-1037 (SessionEnd resets the name to the catalog name); IslandViewContent.swift:1566` — Between sessions the pill and its card header read 'Claude Code'. During a session they show the project name.
- **Windows:** `windows/src/island/hooks.ts:136-143 (clearSession sets name = 'VS Code'); windows/src/views/integrations.ts:108; windows/src/views/views.ts:498` — After SessionEnd the name becomes 'VS Code'. The idle card header and pill label always say 'VS Code'.
- **Fix:** Use the catalog name (INTEGRATION_AGENTS entry, 'Claude Code') in clearSession, the idleCard header and buildPill.
- **Phase:** Phase 5

### SC-G20 — Claude Code idle card: status copy, Settings link and spacing

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:1408-1424 (configured = SessionStart hook command contains 'notchy'), 1489-1515, 1561-1655 (status row top 2 + spacing 6; no Settings… for workspace pills)` — Status dot 5pt with 'Connected' (#22C55E) or 'Not connected' (#F4505E), 11pt #6B7079. The action row has only 'Open Visual Studio Code' (11 medium, colour @0.7). Rows are 8pt apart.
- **Windows:** `windows/src/views/integrations.ts:55-112; windows/src/style.css:2015-2029` — 'Hooks not installed' or 'Connected · loading…', plus a 'Settings…' link when unconfigured. Status 4px below the header, actions 6px below.
- **Fix:** For integration_claude: labels t('Connected')/t('Not connected'), no Settings… link, .int-status padding-top 8px, .int-actions padding-top 8px. Message pills follow their own Mac labels ('Not signed in' / 'N waiting' / 'Connected'); the integrations audit owns those.
- **Phase:** Phase 5

### SC-G21 — Error card content: Mac is a static placeholder, Windows is dynamic

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:470-494` — AgentWho(focus, 'n8n'). 'Workflow stopped.' (15 semibold). 'Gmail node timed out after 30s. Retry or open n8n.' (12pt #FF8D97). PrimaryButton 'Retry' and SecondaryButton 'Open in n8n', both of which do nothing.
- **Windows:** `windows/src/views/views.ts:611-632` — Label 'Claude Code' or 'n8n'. Title 'Session stopped on an error.' for Claude. The detail is the last step or 'No detail available.'. Retry goes to Home.
- **Fix:** Strict parity means porting the Mac strings. Recommended instead: fix the Mac ErrorView to use Windows' dynamic content and keep Windows as is (see risks). Either way, give both platforms the same strings and Retry behaviour.
- **Phase:** Phase 5 — copy the Mac; a real Mac error card awaits the owner's yes

### SC-G22 — Alerts can replace a pending approval card

- **Mac:** `NotchBuddy/Sources/App/HookServer.swift:586-615 (expandIfNeeded: approval/question always win; other alerts only when pendingApproval == nil; never over a screen)` — While an approval is pending, Stop/StopFailure (finished/error) do not take the view.
- **Windows:** `windows/src/island/hooks.ts:172-180` — surface() calls setView for any alert while expanded, so a Stop arriving under an open approval swaps it for the green card, which is still pinned.
- **Fix:** In surface(): if expanded and the view is not approval/question and State.pendingApproval (or pendingQuestion) is set, do not change the view. Approval and question always win.
- **Phase:** Phase 5

### SC-G23 — Agent routing: terminal filter, Cursor/Codex pills, external agent colour

- **Mac:** `NotchBuddy/Sources/App/HookServer.swift:353-395, 569-582 (colorForProject), 637-668` — Only VS Code (TERM_PROGRAM/bundle id) routes to integration_claude. The Cursor bundle routes to agent_cursor and coucou_agent 'codex' to agent_codex, both workspace pills with approval cards. Other terminals are ignored. External agent colour comes from IslandConst.colorForProject (project table, then fallback).
- **Windows:** `windows/src/island/hooks.ts:38-46, 163-169, 279-286; windows/src/core/layout.ts:380-390 (colorForProject exists but is unused here)` — Every terminal routes to integration_claude. 'codex' becomes an external pill with no approvals. There is no Cursor pill. Colour comes only from the fallback hash.
- **Fix:** Keep any-terminal (documented; see readme_known_differences). Add codex -> agent_codex with approvals and 'Always' hidden. Detect Cursor through TERM_PROGRAM / CURSOR_TRACE_ID forwarded by coucou-hook. Use layout.colorForProject(name) for external agents.
- **Phase:** Phase 5

### SC-G24 — Minor hook-event differences

- **Mac:** `NotchBuddy/Sources/App/HookServer.swift:451-463 (PreToolUse does not reveal; skips AskUserQuestion), 526-536 (Interrupt; SessionEnd clears diffs), 1027 (AskUserQuestion permission -> 'ask')` — Only SessionStart and UserPromptSubmit reveal a hidden island. PreToolUse for AskUserQuestion adds no step. Interrupt resets the pill to idle.
- **Windows:** `windows/src/island/hooks.ts:208-215, 262-269` — Every PreToolUse reveals the island and appends an 'AskUserQuestion' step. There is no Interrupt case.
- **Fix:** Remove surface() from PreToolUse. Skip the step when tool_name === 'AskUserQuestion'. Add case 'Interrupt': updateTask idle + clear badge. Answer an AskUserQuestion PermissionRequest with decline.
- **Phase:** Phase 5

### SC-G25 — Home has no 'Notifications' choice and defaults to 'automatic'

- **Mac:** `NotchBuddy/Sources/App/HomeContent.swift:11-27, 46-72, 105-113; AppState.swift:374 (default .notifications)` — Default Home is 'Notifications': the newest message from any source, and it does not hand Home to the player when music loads. 'Last message' (automatic) is a separate option that does.
- **Windows:** `windows/src/core/state.ts:105-142 (no 'notifications'), 384 (homeContent 'automatic')` — The option does not exist and the default is automatic, so on a fresh install Home turns into the Now Playing card whenever something is loaded.
- **Fix:** Add 'notifications' to HomeContent, HOME_CONTENTS (first), HOME_LABEL ('Notifications') and HOME_HINT (the Mac sentence). homeSource('notifications') = lastSource. homeShowsPlayer is true only for 'automatic' or a music-pill focus. Default 'notifications', with a settings migration. Update the automatic hint to the full Mac copy ('…and hands over to whatever is playing while something is.').
- **Phase:** Phase 1

### SC-G26 — Home message face: type sizes, who row and reply bar differ

- **Mac:** `NotchBuddy/Sources/App/HomeMessageView.swift:29-157 (who row HStack 6, AtoLogo 10pt for Ato, time only; empty line 12pt #8E939C translated); IslandViewContent.swift:2244-2259 (body 12pt #9398A1), 2801-2809 (send 28pt); MessageBodyMetrics.swift:20-33 (line ≈15pt, twoLines ≈30)` — Body 12pt, two lines = 30pt. Who row spacing 6 with Ato's logo instead of a dot, showing only the age. Reply bar padding 5/10, white .07 (.12 when focused), field 12pt, send 28x28. On Home, Open only opens the link. Sending plays the 'send' sound and stays.
- **Windows:** `windows/src/views/message.ts:26-42, 58-72 (body class .sub = 13px, line-height 1.35, 36px), 232-234 (send 24px), 367-375 (empty lines without t()), 332-336 (Open marks read and dismisses); windows/src/style.css:1772-1792 (.chat-bar padding 6/10, input 13px); windows/src/core/layout.ts:166-167` — Body 13px, two lines = 36px. Who row gap 7, always a dot, and 'N more waiting · age' on Home too. Reply bar padding 6, field 13px, no focus brightening, send 24px. On Home, Open marks the message read. Empty-state strings are not translated.
- **Fix:** Body: font-size 12px, line-height 15px; MESSAGE_BODY_TWO_LINES = 30 (this changes message-height parity inputs, so update the measuring ruler to the same font). Home who row: gap 6, Ato logo (logos.ts) at 10px, no 'more waiting'. .chat-bar in cards: padding 5px 10px, input 12px, :focus-within background .12, send 28px. Home Open: open only. Wrap the empty lines in t(). Coordinate with the message-card audit.
- **Phase:** Phase 4

### SC-G27 — AI Agents panel is missing (and the README describes a dashboard that no longer exists)

- **Mac:** `NotchBuddy/Sources/App/AgentsPanel.swift:13-144 (reads ~/.claude.json and ~/.claude/sessions/*.json, alive by pid, 2s poll while open, Esc closes, 420x480 borderless floating panel placed under the island); AgentsPanelView.swift:7-150; IslandEdgeAction.swift:10-72 ('agents' ring button, sparkles #E07950); AppState.swift:74-82 (showAgentsPanel, off by default)` — Background #0B0C0E, radius 16, 1pt white .08 stroke. Header: sparkles #E07950 + 'AI Agents' (13 semibold), and a borderless xmark (10 semibold, secondary) that closes. Then a divider at opacity .12 and a scroll area with padding 14 and spacing 12 holding two cards. Each card: padding 12, #000000, radius 14, 1pt white .05 stroke, title uppercased 9pt semibold #6E737C. 'Account' card: when signed in, a green #34D399 8pt dot, label 12 medium, organisation 11 secondary, 'Claude Code last refreshed this <relative>.' (10pt #6E737C) and an honesty note; otherwise a grey dot, 'No Claude Code account found on this Mac.' and the 'Run `claude login`…' note. 'Running here' card: one row per live session with a 7pt dot (#F5A524 working, otherwise #34D399), name/project 12 medium, cwd 10pt #6E737C truncated at the head, and status 10pt secondary. Empty: 'No Claude Code sessions running.'.
- **Windows:** `none (windows/src/core/edgeRing.ts:190-195 has no 'agents'; windows/src/core/bridge.ts:296-302 is an empty AI Agents section; windows/src-tauri/src/lib.rs:975 has an orphaned doc comment; windows/src/style.css:2565-2580 has orphaned .ag-* rules; windows/README.md:258-264 is stale)` — Nothing. No panel, no 'agents' ring action, no 'Show AI Agents' setting.
- **Fix:** Add a Rust module agents.rs that reads %USERPROFILE%\.claude.json (oauthAccount: displayName/emailAddress/organizationName/profileFetchedAt; parse only when mtime changes) and ~/.claude/sessions/*.json (skip .key files; alive check via OpenProcess/kill(0)). Add a borderless, transparent, always-on-top 420x480 Tauri window 'agents' (agents.html + agents.ts) styled with the values above, placed centred 10px under the island's top reservation, with a 2s poll while visible and Esc to close. Add {id:'agents', title:'AI Agents', color:'#E07950'} to EDGE_ACTIONS with the sparkles icon, available when settings.showAgentsPanel. Add the setting (off by default). Port ClaudeAccount parsing tests. Delete the orphaned .ag-* CSS and the lib.rs comment, and rewrite the README paragraph.
- **Phase:** Phase 5

### SC-G28 — Compact bar geometry: width, mini grid and timer colour

- **Mac:** `NotchBuddy/Sources/App/IslandWindowController.swift:1903 (compact = nw + 160); IslandScreenGeometry.swift:41-61 (no-notch bar 80x24 scaled by height; botDiameter, miniGridScale, miniGridCenterX = w-40); IslandRootView.swift:188-216, 684-703 (timer badge 11 semibold mono, paused #8E939C, centre x w-44), 873-893 (grid 2x12pt, spacing 4, 28x28, mini canvas 20)` — On a notched Mac the bar is notch width + 160 (184 fallback -> 344) by the notch height. On a Mac display without a notch it is 80*(h/24)+160 wide (240x24 measured, about 267x32 at a chosen 32). The grid is 12pt cells with 4pt spacing in 28pt, scaled to (h-4)/28.
- **Windows:** `windows/src/core/layout.ts:79-83 (COMPACT_W = NOTCH_W + 104 = 288, from the old SPEC); windows/src/style.css:235-245 (#mini-grid 29px, 13px cells, gap 3); windows/src/island/island.ts:918-921, 2019 (paused #9398a1), 2029 (createMiniBot 13)` — 288x32. Grid of 13px cells with 3px gap in 29px. Paused timer colour #9398a1.
- **Fix:** Use Mac's no-notch formula: COMPACT_W = (80*NOTCH_H/24) + 160 (≈267 at 32), or 344 if the owner wants the notched-Mac look. Grid: 12px cells, gap 4, 28px box, createMiniBot(t, 12), with scale min(1,(h-4)/28). Paused timer colour #8E939C. Put COMPACT_W under the island-resting-bar test.
- **Phase:** Phase 4

### SC-G29 — Header has two extra tabs and the right group is in a different order

- **Mac:** `NotchBuddy/Sources/App/IslandRootView.swift:713-788 (left: Home, Chat, Clipboard; right: Agenda?, Hydration, Timer; then gear, speaker, xmark 13pt)` — Three tabs on the left and Hydration before Timer on the right. Site and the pills are reached from the edge ring, not the header.
- **Windows:** `windows/src/views/views.ts:136-145, 186-188 (left adds Integrations grid + Site globe; right: Agenda, Timer, Water); 366-392 (an extra 'integrations' view with no Mac equivalent); windows/src/core/layout.ts:115` — Five tabs on the left and Timer before Water. A whole Integrations view exists that the Mac removed.
- **Fix:** Remove tabPills and tabSite from the header (keep both in the ring) and order the right group Agenda, Water, Timer. Remove the 'integrations' view and its layout row, or keep it reachable only from a ring pill if the owner wants it. Close icon 13px (Mac xmark at 13pt) with a 5px hit inset (already there).
- **Phase:** Phase 4 — Integrations and Site tabs kept (owner); right group reordered

### SC-G30 — Confused view: invisible header still takes clicks; gutter and hold differ

- **Mac:** `NotchBuddy/Sources/App/IslandRootView.swift:616-621 (header opacity 0 and allowsHitTesting false); IslandViewContent.swift:726-740 (fixed leading 128); IslandWindowController.swift:1670-1686 (expand(to:.confused), no notification hold)` — The header is hidden and click-through. Text stays at 128 even with characters hidden. The view returns after 3.3s and the island does not fold away during it.
- **Windows:** `windows/src/views/views.ts:205, 656-664; windows/src/island/island.ts:1689-1708 (alert('confused') starts the auto-close hold)` — The header has opacity 0 but its buttons still take clicks. The gutter collapses to 18 with no-mochi. alert() arms the auto-close hold, which can fold the island mid-dizzy.
- **Fix:** header.sync: pointerEvents = 'none' when confused. Confused stack: --flush:128px. handleDizzy: use this.expand('confused') (plus forceHome when not expanded) instead of alert().
- **Phase:** Phase 4

### SC-G31 — Buttons get hover/press effects the Mac does not have; decisions play sounds

- **Mac:** `NotchBuddy/Sources/App/IslandViewContent.swift:2178-2234 (.buttonStyle(.plain), no hover); HookServer.swift:751-791 (no sound on decision)` — Capsule buttons do not change on hover and dim slightly while pressed (plain style). Allow and Deny are silent.
- **Windows:** `windows/src/style.css:433-452 (.btn transition, :active scale(.94), .secondary:hover .15); windows/src/island/island.ts:298` — Secondary buttons brighten to .15 on hover, all buttons shrink to .94 when pressed, and approve/blip sounds play.
- **Fix:** Remove .btn.secondary:hover and the scale; use .btn:active { opacity:.75 } to imitate plain-style press dimming. Remove Sound.play in decide().
- **Phase:** Phase 4

### SC-G32 — Island resize motion is not scaled by distance

- **Mac:** `NotchBuddy/Sources/App/IslandMotion.swift:43-61; IslandRootView.swift:234-236, 278` — Growing uses spring(response 0.34+0.16t, damping min(.96, .78+.18t)) and shrinking a 0.22+0.16t curve, with t = min(1, travel/400).
- **Windows:** `windows/src/core/anim.ts:91-95; windows/src/island/island.ts:886-899` — A fixed 0.34/0.78 spring and a fixed 220ms close.
- **Fix:** animateGeometry: compute the travel from the current to the target w/h and use the same formulas.
- **Phase:** Phase 4

### SC-G33 — Step strings and Home empty lines are not translated on Windows

- **Mac:** `NotchBuddy/Sources/App/HookServer.swift:478, 539-542 (L('⚠ failed'), L('+ subagent'), L('• subagent done')); HomeMessageView.swift:50,60-67 (Text(loc:))` — These strings are in i18n/catalog.json and show in Spanish or Portuguese.
- **Windows:** `windows/src/island/hooks.ts:223, 272, 276; windows/src/views/message.ts:371-374` — They are always English.
- **Fix:** Wrap them in t(...).
- **Phase:** Phase 5

### SC-G34 — System font, SF Mono and SF Symbols

- **Mac:** `All views (.font(.system…), .monospaced(), Image(systemName:))` — SF Pro text and SF Mono code; SF Symbols glyphs (arrow.up.right, chevron.right, checkmark, xmark, sparkles, …).
- **Windows:** `windows/src/style.css:7-8 (--font: system-ui/Segoe UI Variable; --mono: Cascadia Mono/Consolas); windows/src/views/icons.ts` — Segoe UI Variable / Cascadia Mono; hand-drawn SVG paths on a 24px grid.
- **Fix:** SF Pro and SF Symbols may not be shipped on Windows (Apple licence). The closest faithful option is to bundle Inter (metrics close to SF Pro) with font-feature-settings 'cv11','ss01' and letter-spacing -0.01em at 12-15px, plus JetBrains Mono or SF-like Menlo metrics for code. Keep the redrawn icons, but tune their stroke weights to the SF weights used (medium 9pt chevron, regular 8pt checkmark).
- **Phase:** Phase 4

## Already matches

- Card corner radius 20, 1px white .035 hairline, and the wash colours and radial geometry (washRGBA equals CardBackground.washColor; 280px at 50% 130%, clear at 70%)
- PrimaryButton/SecondaryButton metrics: 12.5px/500, padding 7/13, capsule, #F5F6F8 on #0B0C0E, white .09 on #F1F2F4, kbd styling
- AgentWho: 8px dot, gap 7, 12px semibold #F5F6F8 name, 12px #8E939C label
- CodeBlock typography: 12px mono, #E8E9EC, padding 5/10, bg .07, border .06, radius 10 (only width and wrapping differ, G03)
- Approval/finished/error/question stack: leading 116 (flush 16), trailing 16, vertical 4, spacing 5; Empty: 118/18 with gap 16 and an 'Ask Claude' primary button to prompt; Note gutter 98; Confused 128/18 (except G30)
- Overview Claude Code card: who row at top 10, 108/36 insets, 7px dot, 12 semibold name, 11px #8E939C subtitle, 11px #6B7079 'i/n' counter; ticker 44px tall at 6/12/108 with the 0/.12/.85/1 mask; jump button 16px circle, white .07, #5F646D, top 8 right 10, hidden while a detail is open
- Ticker: 22px rows, completed scale 11.5/13, -10px shift, chevron/check/shimmer/dim crossfade formulas, check #454850, chevron #8E939C, curve (0.4,0,0.2,1) over 380ms
- Header chrome: 34px tall, content padding 8/10/10, tabs 30x22 capsules with on #F5F6F8/#1D1F23, hover #B0B5BE/white .07, off #8E939C, gap 5, left padding 14, right group padding 6, actions gap 14, trailing 16
- Countdown hairline: white .35, 2px, radius 2, up to 160px, shown in the last min(10s, 60%) of the hold
- Bot glow colours and opacities per state, including ratelimit #F59E0B (rate-limit has no card on either side, only Mochi's state and the 'rate' sound)
- VIEW_LAYOUTS rows for these views: overview 160/68/58, empty 160/70/62, approval and question 160/62/56, error and finished 160/62/58, confused 160/76/66, note 160/60/50
- Hook events: SessionStart reveal + 'work' sound; UserPromptSubmit reads prompt[0..60]; Notification rate-limit/'?' rules; Stop badge when unfocused and back to idle after 5.2s; StopFailure; subagent steps; 20-step cap; validateAgent; project alias map
- Approval pins the island; Escape collapses only when not pinned; auto-close default 5s; dizzy recovery after 3.3s with the 'happy' emote
- islandOwner rule (parity-tested by tests/island-owner-parity.ts) and messageCardHeight (parity-tested by tests/message-height-parity.ts)
- PillBadge visuals (14px #0B0C0E ring, 12px coloured disc, 6px glyph, .6 glow). The Mac defines PillBadgeView but never renders it, so badges only show in Windows' extra Integrations tab

## Known differences in windows/README.md

- **closable** — Permission approval works from any terminal; the Mac build only listens to VS Code sessions (README.md:245-246) coucou-hook already forwards env context. Windows could match the Mac by honouring TERM_PROGRAM=vscode (VS Code sets it on Windows too), but that would drop Windows Terminal users. Recommend the opposite direction: port any-terminal to the Mac's HookServer (drop the isVSCodeEditor guard), so the platforms agree without losing a feature. Either way, change the 'Handled in …' note to 'Handled in the terminal.' when not VS Code.
- **closable** — No jump to a specific terminal window; 'Open terminal' opens the working folder in VS Code (README.md:247-249) The Mac does not target a specific window either: it activates the first running terminal app and collapses. A Rust focus_terminal command (EnumWindows by process name WindowsTerminal/pwsh/powershell/cmd, SetForegroundWindow, else 'wt -d <cwd>') reproduces that exactly (G13/G16).
- **closable** — AI Agents dashboard without Session/Week gauges (README.md:258-264) The paragraph is stale on both sides. The Mac replaced the dashboard with AgentsPanel (Account + Running here, no gauges), and the Windows dashboard code has been removed (empty bridge section, orphaned CSS/doc comment). Port AgentsPanel as a 420x480 Tauri window plus the 'agents' ring action and setting (G27), then rewrite the paragraph.
- **forced** — No notch: the island lives against a screen edge, bottom right by default (README.md:226-229) Forced: there is no notch or menu bar cutout. The closest faithful equivalent for the compact bar/peek is Mac's no-notch geometry (80*(h/24)+160 wide, Mochi at x 40, grid at w-40; G28) with corners mirrored to the docked edge. Offering 'top centre' as the default would read most like the Mac.
- **forced** — It stays out: alwaysVisible defaults to true on Windows (false on Mac) (README.md:230-240) Mostly forced. A hidden Mac island disappears into the notch's black, but a hidden PC island would just vanish. Keep the default, but make the resting bar match the Mac compact bar's metrics (G28) so 'peek' looks identical once revealed.
- **closable** — The ring is dealt differently on a fresh install; the Mac 'leaves the dashboard underneath' (README.md:265-269) Add the 'agents' edge action (G27) and use the Mac's IslandEdgeLayout.defaults dealing, with agents underneath when showAgentsPanel is on. Parity-test the defaults against Swift.

## Parity tests to add

- IslandConst.cardHex vs the island stylesheet's --card. The black-card change drifted with no test: dump the hex from Swift and assert the CSS custom property in windows/src/style.css.
- IslandConst.viewLayouts (height, botX, botY, botDiameter, sizeClass) vs VIEW_LAYOUTS, with an explicit allow-list for the measured exceptions (uploading botY, messages/agenda botX, hydration, sip). Today it is entirely hand-copied.
- The tall-view predicate (IslandRootView.swift:648-655) vs a new core/layout.ts isTallView(), plus the 98pt standard card height.
- CardBackground.washColor vs washRGBA, for every Wash case.
- islandSize(.compact) and IslandRestingLayout (botDiameter, botCenterY, miniGridScale, miniGridCenterX) for a no-notch screen vs COMPACT_W / botPosition('compact') / mini-grid metrics.
- botPosition for every (mode, view, islandH) triple, including the grown-message case.
- HookServer.stepLabel + bashVerb + oneLine over a fixture file of tool_name/tool_input pairs vs the TS stepLabel.
- DiffEngine.fromEdit/fromNew/toOneLine and makeDiffStep/parseDiffStep vs a TS (or Rust) port, reusing tests/DiffEngineTests.swift cases (scripts/test-diff-engine.sh is Swift-only today).
- AskQuestion.parse/buildAnswers vs a TS port (scripts/test-ask-question.sh is Swift-only today).
- HomeContent: cases, order, label, hint, source(lastSource:), showsMusic, playerTakesHome vs HOME_CONTENTS/HOME_LABEL/HOME_HINT/homeSource/homeShowsPlayer (scripts/test-home-content.sh is Swift-only, and the TS twin is already missing 'notifications').
- PillCatalog rows (id, name, colour, subtitle, sessionSubtitle, category) vs INTEGRATION_AGENTS. 'Claude Code' vs 'VS Code' drifted.
- IslandEdgeAction (ids, titles, icons, colours, availability) vs EDGE_ACTIONS ('agents' is missing).
- IslandMotion (openResponse 0.34, openDamping 0.78, closeDuration 0.22, fullTravel 400, grow/shrink travel formulas) vs core/anim.ts.
- Atom style tokens (PrimaryButton/SecondaryButton paddings, font sizes and colours; AgentWho; CodeBlock; ticker row 22 and scale 11.5/13; DiffLineRowView colours; question chip colours). Generate one design-tokens JSON into both Swift and CSS custom properties.
- MessageBodyMetrics.lineHeight/twoLines (≈15/30) vs MESSAGE_BODY_TWO_LINES (36).

## Risks

- The Mac is not uniformly the better reference here. ErrorView (IslandViewContent.swift:470-494) is a static mock with fake Gmail text and no-op Retry/Open buttons, and the Mac approval CodeBlock hides which file or URL is being authorised. Copying these to Windows literally would make Windows worse. Recommend fixing the Mac side (dynamic error text, Windows' approvalTarget) and then matching. The owner should decide G05/G21.
- coucou-hook truncates every forwarded string field to MAX_FIELD_LEN = 2000 (windows/hook/src/main.rs:35). A Windows DiffEngine built from tool_input.old_string/new_string/content would report wrong +/− counts for large edits unless those fields are exempt (or the diff is computed inside the relay).
- AskUserQuestion and 'Always' need relay protocol changes (pipe.rs Reply enum, coucou-hook --ask mode, updatedPermissions passthrough) and a new hook entry in each user's ~/.claude/settings.json. Windows no longer installs hooks automatically (hooks.rs header), so existing users will not get the question card until they edit settings by hand; docs/INTEGRATIONS.md must be updated.
- Changing the standard card to 98px (G02) together with Mac type sizes (G26) changes what fits in a 160 island. Do both at once and re-run tests/message-height-parity.ts. MESSAGE_BODY_TWO_LINES feeds island.bodyOverflow and the window height.
- Several Mac-side strings are untranslated on both platforms (missing from i18n/catalog.json): 'Allow', 'Deny', 'Always', 'Retry', 'OK', 'needs permission', 'Claude Code is asking', 'Other…', 'Running here', 'Account'. The Mac passes Strings to PrimaryButton/SecondaryButton, which renders them verbatim. Parity holds in English, but a pt-BR user sees English on both. Fix in the catalog and in the button initialisers on both sides.
- Windows screenshots (windows/screenshots/*.png) and design/captures are stale: they show the old two-column overview, French copy and kbd hints. Do not use them as the visual reference; use the Swift code values listed here.
- Out of this surface but noticed: DEFAULT_SETTINGS.siteUrl in windows/src/core/state.ts:398 defaults to a personal tailnet hostname, which would ship to every fresh install.
- Approval routing parity (G06/G08/G22) changes when the island steals focus and the view. Verify against the FSM pin/hold logic in island.ts (alert/forceHome) so an approval arriving while the message reply box has the cursor does not discard a half-written reply. The Mac guards this with isReplying in notify paths.
