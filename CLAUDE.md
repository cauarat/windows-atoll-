# Coucou — guide for AI coding agents

Coucou is a native macOS app (`NotchBuddy/`); `windows/` is the Tauri version for Windows and Linux. Mochi, a small animated character living in the MacBook notch, shows AI coding agent sessions (Claude Code, Gemini CLI, Antigravity and more) and a few integrations, and lets the user approve, answer, chat and drop files from the notch.

## Where things are
- `NotchBuddy/Sources/App/` — all Swift code. `NotchBuddy/Resources/sounds/` — the 28 WAV sounds. `NotchBuddy/project.yml` — XcodeGen project (never edit the `.xcodeproj` by hand).
- `NotchBuddy/Sources/App/PillCatalog.swift` — single source of truth for all declared pills (workspace tools, agents, AI providers, services). Every pill ID, color, category and subtitle lives here.
- `docs/SPEC.md`, `docs/INTEGRATIONS.md` — behaviour, views, states, integrations (in French).
- `design/prototype/notch-buddy.html` — original prototype, the visual source of truth. `design/captures/` — target screenshots.
- `windows/` — the Tauri app for Windows and Linux: Rust in `src-tauri/`, TypeScript in `src/`, the `coucou-hook` relay in `hook/`. `windows/README.md` lists what differs from the Mac.
- `docs/*.html` — the GitHub Pages site (privacy, terms, support, legal notice).

## Build
```
cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build
```
Every Debug build copies itself over `/Applications/Notchy.app` and registers it (`scripts/install-mac.sh`, a post-build script) — one bundle, whichever worktree built it. That matters: a worktree per task otherwise means a `Notchy.app` per worktree, all indexed and indistinguishable, and the app you open is whichever one you happened to find. `project.yml` used to pin `SYMROOT` to the same end; it cannot, because a custom `SYMROOT` is a legacy build location and Swift packages — Sparkle, for the updater — are refused in that mode.

Before trusting what you see in the running app, check that the binary is the one you just built — `nm -U <app>/Contents/MacOS/* | grep <ATypeYouAdded>`. A green build somewhere else looks exactly like a fix that works. Mind the glob: a Debug `Notchy` is a stub and the code is in `Notchy.debug.dylib` beside it, so naming the executable alone always comes back empty.

Windows and Linux: `cd windows && npm install && npm run tauri dev`

## Rules
- Branch from an up-to-date `notchy`, push the branch, and integrate through a PR. Not housekeeping: a worktree per task, branched from wherever `notchy` was that week and never merged back, is how this repo once reached twenty branches and four days of work that no single build contained. A branch that only exists on one Mac is work nobody else has.
- Swift 6, SwiftUI + AppKit. Sparkle, for the updater, is the one third-party dependency, and it is fenced behind `#if !APPSTORE`; nothing else is added without a reason that good. The character is drawn in code (`Canvas` + `TimelineView`), no Rive/Lottie/images.
- Secrets live in the Keychain, never on disk or in git.
- No telemetry. Network calls only to services the user configured.
- Never block Claude Code: if the app doesn't answer, the hook exits immediately.
- Never overwrite `~/.claude/settings.json`: dated backup, merge, show the diff, write only after the user confirms.
- Never send an email or approve a Claude Code or Codex permission without an explicit click.
- Performance: 0 % CPU when the island is hidden.
- Keep the bundle identifier `fr.louisraille.NotchBuddy` (Keychain items, preferences and permissions depend on it).
- Never restyle what already ships (pills, cards, Settings, chat…): existing views stay exactly as they are in `main`, which is the App Store build. Change the look of an existing view only when explicitly asked.
- Pill IDs are stable contract values (Keychain, UserDefaults, hook routing): never rename an existing pill ID.
- New views follow the existing app style. `design/prototype/notch-buddy.html` and `design/captures/` are references for new work, not a reason to change existing views.
