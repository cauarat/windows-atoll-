# Changelog

## 0.1.9 — October 29, 2026

When an update check fails, it now says why.

- **The reason is on screen.** "The check did not go through." used to be the whole answer. The sentence saying *why* — the host that could not be reached, the error GitHub returned — was printed at the foot of the section, under a four-line paragraph and below the bottom edge of the window, so nobody ever read it. It sits directly under the message now.
- Settings → Updates still said **Coucou**, in English, after the rename and after everything else was translated: the version line, the window title, and every sentence the updater says while it works. All of it is Notchy now, in your language.
- Publishing a release uploads the packages before the manifest that announces them, instead of both at once. A copy that checked during those seconds got a failure that looked exactly like a broken connection.

## 0.1.8 — October 29, 2026

Notchy speaks your language.

- **Settings → General → Language**: English, Español or Português (Brasil), and "Same as system", which is what a fresh install picks — Spanish or Portuguese if Windows is set to one of them, English otherwise. It takes effect at once; nothing restarts.
- It is the whole app, not the settings window: the island, every card, the chat, the notification-area menu, the messages you get when a service will not connect, and the names of Mochi's faces.
- The line that says what Claude Code is doing was French — `Bash` read as "Exécute". It is in your language now, like everything else.
- The site and the installer speak all three too.

## 0.1.5 — October 13, 2026

Windows catches up with the Mac.

- The AI Agents dashboard: what Claude Code has been doing and what it cost — today's spend, the hourly trend, the split by model and by project, and thirteen weeks of activity. It is all read from Claude Code's own transcripts on this machine; nothing is sent anywhere.
- A globe on the island opens your site, and the chat tab can open ChatGPT instead of the built-in chat (Settings → Pages). Each opens a window of its own, and a link to anywhere else opens in your browser.
- One Notifications pill over both message services, so what is waiting is one queue instead of two places to remember.
- Seven integrations nobody was using — Resend, n8n, Vercel, GitHub, Stripe, Cal.com and Notion — are gone, along with the seven pollers that woke all day to find no key. Your stored choices are migrated; the pills that are left are seeded if every one you had was removed.
- Updating itself works from this release on. The packages before it were signed with a key that no longer exists, so this one is installed by hand once and the ones after it arrive on their own.

## 0.1.4 — October 9, 2026

- Coucou updates itself. It asks GitHub every few hours whether a newer release exists and offers it from the icon by the clock and in Settings → Updates; one click downloads, verifies and installs it. Nothing is downloaded or restarted until you click, because a restart nobody asked for would drop a Claude Code permission request that was waiting to be answered. The check carries no identifier and no usage of any kind, and can be switched off.
- Every package is signed, and one whose signature does not match is refused before it is run — so a tampered download can do nothing but fail.
- macOS (GitHub build) and the Linux AppImage update the same way. The portable Windows .zip and the .deb and .rpm packages cannot replace themselves, so they say a new version is out and point at the download page instead.

## 0.1.3 — October 3, 2026

- Answer Claude's questions from the notch: when Claude Code asks a multiple-choice question, pick an option or type your own answer right in the island, and Reply in terminal hands it back. Update your hooks in Settings to turn it on (#165) — thanks @Vega8991 for the idea (#94)
- Claude plan usage (GitHub build): turn on Settings → Agents → Plan usage to see your 5-hour and weekly limits in a small pill in the notch header, and click it for the details and reset times. Pro and Max plans; your current status line keeps working (#159)
- Chat with local models through Ollama or LM Studio, no API key needed: connect them in Settings → Chat → Local models. Answers stream in, and thinking blocks stay hidden (#156)
- Markdown in chat answers: bold, lists, headings, quotes, and code blocks with a copy button. Links open only when they are web links (#156)
- Apple Music (GitHub build): see what is playing in the notch, play, pause and skip on hover, and Mochi dances along (#144, #153)
- Settings are now organized in a sidebar (#153)
- The chat greets you by your own first name (#154)

## 0.1.2 — October 2, 2026

- Codex support (GitHub build): sessions show up live on the Codex pill, and permission requests get Allow and Deny in the notch. Install from Settings → Codex Hooks, then trust the hooks once with /hooks in Codex (#130) — thanks @lacatu5
- Cursor: Claude Code started in Cursor's terminal shows up on the Cursor pill, and you can answer its permission requests from the notch (#120).
- Pick your main coding tool in Settings → Active pills: VS Code, Cursor, Codex or Antigravity (Codex and Antigravity: GitHub build). It stays on and no longer takes one of the 4 slots (#120).
- The permission card stays in the notch until you answer it: the mouse no longer folds it, and reopening the island shows the request again (#117).
- The permission card also shows when the island is already open, and the pill you were on comes back once you answer (#120).

## 0.1.1 — October 2, 2026

- Declare the tools you use in Settings: Gemini CLI, Antigravity, Anthropic, Google AI and OpenAI pills join the existing ones (Cursor and Codex pills are coming soon), and you pick the main pill.
- Chat now supports Google AI (Gemini) and OpenAI in addition to Anthropic; switch provider and model by clicking the model name in the chat view, on macOS.
- Linux version: the Tauri app now builds for Linux too (AppImage, .deb, .rpm), with the island as a layer-shell overlay on Wayland and Claude Code hooks over a private Unix socket (#21) — thanks @Davy133
- Compact island on screens without a notch (#22) — thanks @Kamasoutra
- Only web links (http/https) open from the notch; other kinds of links from Claude or integrations are ignored (#16) — thanks @Cris1670
- Hook socket limited to your own user account, with size and time limits; logs no longer keep commands, n8n data or full URLs, and stay under 1 MB (#16) — thanks @Cris1670 and @Vignesh-Thangamariappan
- The island always reopens after folding, and Settings opens below it, resizable — thanks @rouderz
- Choose the Claude model for the chat in Settings; the list comes from your Anthropic account, and Claude Sonnet 4.6 stays the default — thanks @rouderz
- Windows build artifacts are now downloadable from a manual CI run — thanks @MysJofR
- Any agent can talk to Mochi: tag a hook payload with `coucou_agent` (e.g. `nb-hook --agent my-agent`) and it gets its own pill in the island (#7, #9) — thanks @lacatu5
- Gemini CLI and Antigravity (agy) hook support on macOS: install from Settings and their sessions show up in the island — thanks @corefusiion
