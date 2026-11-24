// Coucou for Windows — app wiring and the commands the island calls.

mod agenda;
mod agenda_proto;
mod claude;
mod clipboard;
mod ato;
mod files;
mod hooks;
mod i18n;
#[rustfmt::skip]
mod i18n_generated;
mod integrations;
mod mattermost;
mod media;
mod message_proto;
mod messages;
mod island;
mod log;
mod page_model;
mod pipe;
mod platform;
mod secrets;
mod settings;
mod shortcut;
mod tray;
mod update;
mod web;
mod whatsapp;

use std::process::Command;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_autostart::{ManagerExt, MacosLauncher};

use claude::{Chat, ChatContext, ChatReply};
use files::DroppedFile;
use island::{PollGate, ScreenInfo};
use pipe::Pending;
use settings::Settings;
use update::{UpdateState, Updates};

pub struct Shared {
    /// What was copied, while the user has asked for it to be watched.
    clipboard: clipboard::Clipboard,
    pub settings: Mutex<Settings>,
    pub gate: Arc<PollGate>,
    /// True when Windows restarted us after a crash — see `RECOVERED_ARG`.
    pub recovered: bool,
    /// Where the welcome stands — see `Welcome`.
    pub welcome: Mutex<Welcome>,
}

/// What Windows puts back on the command line when it relaunches Coucou after a
/// crash or a hang. Nothing else passes it, so seeing it means the last run died.
const RECOVERED_ARG: &str = "--recovered";

/// The master switch, for the background work that has to ask before running.
///
/// Defaults to on where the state is not reachable, so a race at startup or
/// shutdown can never silently stop answering Claude Code.
pub fn is_enabled(app: &AppHandle) -> bool {
    app.try_state::<Shared>()
        .map(|shared| shared.settings.lock().unwrap().enabled)
        .unwrap_or(true)
}

/// Whether the island is up and answering: on, and not parked under the
/// first-run welcome. What the hook relay asks before handing the island a
/// permission request — one sent to a parked island would sit on a card nobody
/// can see while Claude Code waited for it.
pub fn island_live(app: &AppHandle) -> bool {
    app.try_state::<Shared>()
        .map(|shared| {
            // One lock at a time: nothing here ever holds both.
            let enabled = shared.settings.lock().unwrap().enabled;
            enabled && !shared.welcome.lock().unwrap().parked
        })
        .unwrap_or(true)
}

/// Applies the switch to the window, the cursor thread and the tray.
///
/// The order is load-bearing in both directions: park the poll thread before
/// hiding, or it re-asserts click-through on a window that is no longer there;
/// show before waking it, or it computes hit-testing against a hidden window.
///
/// Under the first-run welcome the island stays parked whatever the switch
/// says — on in the settings, off on screen — until the welcome is over and
/// `finish_onboarding_now` comes back through here.
fn apply_enabled(app: &AppHandle, shared: &Shared, enabled: bool) {
    let live = enabled && !shared.welcome.lock().unwrap().parked;
    integrations::apply_master(live);
    if let Some(win) = island::window(app) {
        if live {
            let (screen, position, always_visible) = {
                let s = shared.settings.lock().unwrap();
                (s.screen.clone(), s.position.clone(), s.always_visible)
            };
            island::apply_geometry(app, &screen, &position, false, always_visible);
            shared.gate.collapsed.store(false, Ordering::Relaxed);
            if !platform::CURSOR_POLL {
                island::refresh_click_through(app, &shared.gate);
            }
            let _ = win.show();
            shared.gate.settle(false);
        } else {
            shared.gate.set_mode(island::Watch::Parked);
            // Belt and braces: if hide() is ignored by an exotic compositor,
            // nothing on the island can still take the mouse.
            island::set_ignore_cursor(app, true);
            // Hiding is what makes this an off switch rather than the old Pause:
            // the 240×6 wake strip goes with it, so sweeping that corner of the
            // screen no longer brings Mochi back.
            let _ = win.hide();
            // The pages are the island's, so off puts them away too, and lets
            // them go: the Mac's ChatGPT goes cold with the master switch.
            web::park(app);
        }
    }
    tray::refresh(app, enabled);
    // An app that is off has no island to close, and holds no keys other apps
    // could use. Here rather than in save_settings, so the tray's switch,
    // which never goes through it, lets go of them too.
    let current = shared.settings.lock().unwrap().clone();
    shortcut::apply(app, &current);
}

/// Flips the switch from anywhere: persists it, applies it, and tells both
/// windows. The tray calls this directly rather than going through the webview,
/// which is what lets it work while the island is hidden.
pub fn set_enabled_now(app: &AppHandle, enabled: bool) {
    let Some(shared) = app.try_state::<Shared>() else { return };
    let updated = {
        let mut current = shared.settings.lock().unwrap();
        if current.enabled == enabled {
            return;
        }
        current.enabled = enabled;
        if let Err(err) = settings::save(&current) {
            eprintln!("[coucou] could not save settings: {err}");
        }
        current.clone()
    };
    apply_enabled(app, &shared, enabled);
    let _ = app.emit("settings-changed", updated);
}

pub fn toggle_enabled(app: &AppHandle) {
    set_enabled_now(app, !is_enabled(app));
}

// ── The welcome ───────────────────────────────────────────────────────────────
//
// Seven screens in a window of their own (src/onboarding/), the twin of the
// Mac's OnboardingWindowController. A first run opens on it, with the island
// parked underneath exactly as if Notchy were off; Settings' "Show the welcome
// again…" opens it over an island that keeps running. Either way it ends in
// `finish_onboarding_now` — Open Notchy, Skip, its close button or Alt+F4 —
// and the island says hello, with the name it was just given.

/// The welcome's window. Created hidden at launch, like the settings window and
/// for the same reason (see `create_settings_window`), and only ever shown and
/// hidden after that.
const ONBOARDING_LABEL: &str = "onboarding";

/// The window's size in logical px — `OnboardingView.size` on the Mac.
const ONBOARDING_W: f64 = 520.0;
const ONBOARDING_H: f64 = 660.0;

/// The welcome's seven screens, in order — `ONBOARDING_STEPS` in
/// src/core/onboarding.ts and `OnboardingStep` on the Mac.
const ONBOARDING_STEPS: [&str; 7] = ["welcome", "name", "language", "look", "tools", "startup", "ready"];

/// Where the welcome stands.
#[derive(Default)]
pub struct Welcome {
    /// The screen it opened on while its window is up, None the rest of the
    /// time. Handed to the page in `BootInfo`, which is how a page that loads
    /// after the window was shown knows to start.
    step: Option<String>,
    /// A first run: the island is parked underneath and has not said hello yet.
    /// What `apply_enabled` and `island_live` read.
    parked: bool,
    /// Opened by `NOTCHY_ONBOARDING` for a screenshot: never marks it done.
    preview: bool,
}

/// `NOTCHY_ONBOARDING=<screen>` opens the welcome on that screen at launch
/// (`welcome`, `name`, `language`, `look`, `tools`, `startup`, `ready`), whatever
/// has been seen, and never marks it done — for screenshots, the Mac's
/// variable with the Mac's names. Anything else it says opens on the hello.
fn welcome_preview() -> Option<String> {
    let raw = std::env::var("NOTCHY_ONBOARDING").ok()?;
    let step = ONBOARDING_STEPS.iter().find(|s| **s == raw.trim()).copied().unwrap_or("welcome");
    Some(step.to_string())
}

/// Same dance as the settings page: dev builds are served by Vite.
fn onboarding_page_url(app: &AppHandle) -> WebviewUrl {
    #[cfg(dev)]
    if let Some(mut base) = app.config().build.dev_url.clone() {
        base.set_path("/onboarding.html");
        return WebviewUrl::External(base);
    }
    let _ = app;
    WebviewUrl::App("onboarding.html".into())
}

/// Built hidden at launch with the other windows: a WebView2 window created
/// after the island's comes up blank.
///
/// Frameless and transparent, so the page draws the Mac's dark panel with its
/// rounded corners and red close button itself; above other windows while it
/// is up, as the Mac's floats, because a welcome that opened behind a browser
/// could not be found again — there is no taskbar entry to find it by.
fn create_onboarding_window(app: &AppHandle) {
    let url = onboarding_page_url(app);
    match WebviewWindowBuilder::new(app, ONBOARDING_LABEL, url)
        .additional_browser_args(BROWSER_ARGS)
        // Only what shows while the webview is blank; the page keeps
        // `document.title` in the language it speaks.
        .title(i18n::t(&i18n::current(), "Welcome to Notchy"))
        .inner_size(ONBOARDING_W, ONBOARDING_H)
        .resizable(false)
        .maximizable(false)
        .minimizable(false)
        .decorations(false)
        .transparent(true)
        // The page draws its own edge. A system shadow would be cast by the
        // window's square, around the rounded panel.
        .shadow(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .visible(false)
        // Hidden until it is needed, and never focused while hidden: a page
        // focused as it is created takes the foreground with it, and a hidden
        // window holding the foreground takes the keyboard and the island's
        // clicks. `bring_up` focuses it when it is shown.
        .focused(false)
        .center()
        .build()
    {
        Ok(win) => {
            web::keep_hosting(&win);
            // Alt+F4, or anything else that asks it to close: a Skip, keeping
            // whatever was already chosen. Never a real close — it could not be
            // shown again.
            let app = app.clone();
            win.on_window_event(move |event| {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    api.prevent_close();
                    if let Some(shared) = app.try_state::<Shared>() {
                        finish_onboarding_now(&app, &shared);
                    }
                }
            });
        }
        Err(err) => log::line(format!("welcome window failed: {err}")),
    }
}

/// Puts the welcome on screen and gives it the keyboard.
///
/// Placed only when it comes up from hidden: one already on screen may have
/// been dragged somewhere, and bringing it forward must not snap it back.
fn show_onboarding_window(app: &AppHandle) {
    let Some(win) = app.get_webview_window(ONBOARDING_LABEL) else {
        log::line("welcome window missing");
        return;
    };
    if !win.is_visible().unwrap_or(false) {
        if let Some(shared) = app.try_state::<Shared>() {
            let (screen, position) = {
                let s = shared.settings.lock().unwrap();
                (s.screen.clone(), s.position.clone())
            };
            if let Some((x, y)) =
                island::welcome_origin(app, &screen, &position, (ONBOARDING_W, ONBOARDING_H))
            {
                let _ = win.set_position(tauri::PhysicalPosition::new(x, y));
                // Across displays the scale can change under it: keep the size.
                let _ = win.set_size(tauri::LogicalSize::new(ONBOARDING_W, ONBOARDING_H));
            }
        }
    }
    let _ = win.unminimize();
    let _ = win.show();
    web::bring_up(&win);
}

/// Whether the welcome's window is up.
fn welcome_up(app: &AppHandle) -> bool {
    app.try_state::<Shared>()
        .map(|shared| shared.welcome.lock().unwrap().step.is_some())
        .unwrap_or(false)
}

/// "Open Notchy" from outside the island — the tray, or launching it a second
/// time. While the welcome is up the island is waiting on it, so the welcome
/// is what comes back.
pub fn open_island(app: &AppHandle) {
    if welcome_up(app) {
        show_onboarding_window(app);
    } else {
        let _ = app.emit_to(island::WINDOW_LABEL, "tray", "open".to_string());
    }
}

/// The welcome is over, however it ended: stamps it as seen, puts its window
/// away, and lets the island say hello — the way switching Notchy on brings it
/// up, after a first run that kept it parked. Switched off from the tray while
/// the welcome was up, Notchy stays off.
///
/// Once per welcome: the page's button and a close request can both arrive.
/// Persisted and broadcast like any other change, so every page's copy of the
/// settings comes back stamped and no later save of theirs can undo it.
fn finish_onboarding_now(app: &AppHandle, shared: &Shared) {
    let welcome = std::mem::take(&mut *shared.welcome.lock().unwrap());
    if let Some(win) = app.get_webview_window(ONBOARDING_LABEL) {
        let _ = win.hide();
    }
    if welcome.step.is_none() {
        return;
    }
    let updated = {
        let mut current = shared.settings.lock().unwrap();
        // A screenshot run never marks it done.
        if !welcome.preview {
            current.onboarding_version = settings::ONBOARDING_VERSION;
        }
        current.clone()
    };
    if !welcome.preview {
        if let Err(err) = settings::save(&updated) {
            eprintln!("[coucou] could not save settings: {err}");
        }
    }
    log::line(format!(
        "welcome finished{}",
        if welcome.parked { " — the island starts" } else { "" }
    ));
    let _ = app.emit("settings-changed", updated.clone());
    // The page stops drawing and forgets where it was.
    let _ = app.emit_to(ONBOARDING_LABEL, "onboarding-finished", ());
    if !updated.enabled {
        return;
    }
    if welcome.parked {
        apply_enabled(app, shared, true);
    }
    let _ = app.emit_to(island::WINDOW_LABEL, "onboarding-finished", ());
}

/// Open Notchy, Skip, or the panel's red button — the welcome's ways out.
#[tauri::command]
fn finish_onboarding(app: AppHandle, shared: State<Shared>) {
    finish_onboarding_now(&app, &shared);
}

/// Settings' "Show the welcome again…".
///
/// The island keeps running underneath — it only folds away if it was open, as
/// it does for the Mac's — and replays its greeting once the welcome is over.
/// Asked while the welcome is already up, it brings that one forward instead
/// of starting it over.
#[tauri::command]
fn show_onboarding(app: AppHandle, shared: State<Shared>) {
    let fresh = {
        let mut welcome = shared.welcome.lock().unwrap();
        if welcome.step.is_some() {
            false
        } else {
            *welcome = Welcome { step: Some("welcome".into()), parked: false, preview: false };
            true
        }
    };
    if fresh {
        // The page starts over from the first screen with today's settings,
        // and the island gets out of the way.
        let _ = app.emit_to(ONBOARDING_LABEL, "onboarding-start", ());
        let _ = app.emit_to(island::WINDOW_LABEL, "onboarding-start", ());
    }
    show_onboarding_window(&app);
}

/// The welcome's top strip, pressed: it moves the window, as a title bar would.
/// A command of Coucou's own rather than `data-tauri-drag-region`, which would
/// need a window permission no page has (capabilities/default.json).
#[tauri::command]
fn drag_onboarding_window(app: AppHandle) {
    if let Some(win) = app.get_webview_window(ONBOARDING_LABEL) {
        let _ = win.start_dragging();
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BootInfo {
    settings: Settings,
    screen: ScreenInfo,
    version: String,
    hook_path: String,
    /// False where the OS has no global cursor (Wayland): the page then reports
    /// the cursor from its own mouse events.
    cursor_poll: bool,
    /// Whether this build can read what is playing — see `media.rs`.
    ///
    /// Windows has GSMTC; Linux would need MPRIS and does not have it yet. The
    /// page hides the Now Playing pill where it is false, rather than offering
    /// one of four integration slots for a card that can never fill.
    media: bool,
    /// The last run ended in a crash and Windows started this one. The island
    /// says so once, quietly; the log says it permanently.
    recovered: bool,
    /// The name on the account this runs under, raw — the sign-in name on
    /// Windows, the passwd entry's full name on Linux. What the greeting and
    /// the chat fall back to when nothing was typed under Your name; the front
    /// end decides whether it is a name at all (core/greetingName.ts).
    account_name: Option<String>,
    /// The screen the welcome opened on, while its window is up — "welcome",
    /// or the one `NOTCHY_ONBOARDING` asks for — and null the rest of the
    /// time. The welcome's page starts from it; the island, booting under a
    /// first-run welcome, holds its greeting until "onboarding-finished".
    welcome: Option<String>,
}

#[tauri::command]
fn boot(app: AppHandle, shared: State<Shared>) -> BootInfo {
    let mut settings = shared.settings.lock().unwrap().clone();
    // The real state of ~/.claude/settings.json wins over whatever we stored.
    settings.hooks_installed = hooks::status().installed;
    let screen = island::screen_info(&app, &settings.screen);
    BootInfo {
        settings,
        screen,
        version: env!("CARGO_PKG_VERSION").to_string(),
        hook_path: settings::hook_exe_path().to_string_lossy().to_string(),
        cursor_poll: platform::CURSOR_POLL,
        media: media::AVAILABLE,
        recovered: shared.recovered,
        account_name: platform::account_name(),
        welcome: shared.welcome.lock().unwrap().step.clone(),
    }
}

#[tauri::command]
fn save_settings(app: AppHandle, shared: State<Shared>, mut settings: Settings) {
    let (placement_changed, autostart_changed, enabled_changed, standby_changed, resting_changed, shortcut_changed) = {
        let mut current = shared.settings.lock().unwrap();
        // Rust's own field: which migrations this file has been through. A page
        // sends the whole object back, and one that booted from an older copy —
        // or one that predates the field — must not undo a migration.
        settings.settings_version = current.settings_version;
        let placement_changed =
            current.screen != settings.screen || current.position != settings.position;
        let autostart_changed = current.autostart != settings.autostart;
        let enabled_changed = current.enabled != settings.enabled;
        let standby_changed = current.standby != settings.standby;
        let resting_changed = current.always_visible != settings.always_visible;
        // The master switch is apply_enabled's to carry across.
        let shortcut_changed = current.close_shortcut_enabled != settings.close_shortcut_enabled
            || current.close_shortcut != settings.close_shortcut;
        *current = settings.clone();
        (
            placement_changed,
            autostart_changed,
            enabled_changed,
            standby_changed,
            resting_changed,
            shortcut_changed,
        )
    };
    if autostart_changed {
        let manager = app.autolaunch();
        let result = if settings.autostart { manager.enable() } else { manager.disable() };
        let error = match result {
            Ok(()) => None,
            Err(err) => {
                log::line(format!("autostart: {err}"));
                // As the Mac puts its checkbox back: what is stored follows what
                // the system actually has, and the broadcast below redraws the
                // box. The settings window then asks `autostart_error` why.
                let actual = manager.is_enabled().unwrap_or(!settings.autostart);
                settings.autostart = actual;
                shared.settings.lock().unwrap().autostart = actual;
                Some(err.to_string())
            }
        };
        if let Some(status) = app.try_state::<AutostartStatus>() {
            *status.0.lock().unwrap() = error;
        }
    }
    if let Err(err) = settings::save(&settings) {
        eprintln!("[coucou] could not save settings: {err}");
    }
    if placement_changed {
        let collapsed = shared.gate.collapsed.load(Ordering::Relaxed);
        island::apply_geometry(
            &app,
            &settings.screen,
            &settings.position,
            collapsed,
            settings.always_visible,
        );
        web::reanchor(&app);
    }
    if resting_changed {
        shared.gate.always_visible.store(settings.always_visible, Ordering::Relaxed);
        // Growing is instant, shrinking waits — the rule the page already
        // follows for the island itself. Turned on while Mochi has folded
        // away, the window has to be the bar before the page draws one in it,
        // or the bar comes up clipped to six pixels. Turned off, the page
        // un-collapses on the same event and the window grows from there, so
        // shrinking it to the wake strip here would be a blink of a clipped
        // bar on the way.
        if settings.always_visible {
            let collapsed = shared.gate.collapsed.load(Ordering::Relaxed);
            island::apply_geometry(&app, &settings.screen, &settings.position, collapsed, true);
        }
        island::refresh_click_through(&app, &shared.gate);
    }
    if enabled_changed {
        apply_enabled(&app, &shared, settings.enabled);
    }
    if shortcut_changed {
        shortcut::apply(&app, &settings);
    }
    if standby_changed {
        // Turning standby off while the island is already folded has to hand the
        // wake strip back at once, or the only way out would be a message.
        shared.gate.standby.store(settings.standby, Ordering::Relaxed);
        island::refresh_click_through(&app, &shared.gate);
    }
    if standby_changed || resting_changed {
        // Either switch can move a collapsed island between asleep and awake,
        // and the poll's mode has to follow. Never turned on with standby still
        // on was asleep and parked, and stayed parked: a bar on screen with
        // nothing to keep it on top, follow the display or give it the mouse
        // back. Open, this is Live, which it already was.
        shared.gate.settle(shared.gate.collapsed.load(Ordering::Relaxed));
    }
    // Keep the other window in step (island ⇄ settings window).
    let _ = app.emit("settings-changed", settings);
}

/// Why the last change to "Launch at startup" did not reach the system, for the
/// settings window's status bar — the Mac's "❌ Startup: …". None once a change
/// goes through.
#[derive(Default)]
struct AutostartStatus(Mutex<Option<String>>);

/// The reason the last "Launch at startup" change failed, if it did.
#[tauri::command]
fn autostart_error(status: State<AutostartStatus>) -> Option<String> {
    status.0.lock().unwrap().clone()
}

/// Island with nothing open → shrink the window and park the cursor poll;
/// anything else → full panel and 60 Hz polling.
///
/// What it shrinks to is `island::Fold`: the invisible wake strip where the
/// island folds into the screen edge, the compact bar itself where it never
/// folds away. Both are small enough that the poll parks, which is what makes
/// a resting Mochi cost what a hidden one used to.
#[tauri::command]
fn set_collapsed(app: AppHandle, shared: State<Shared>, collapsed: bool) {
    let (pref, position, always_visible) = {
        let s = shared.settings.lock().unwrap();
        (s.screen.clone(), s.position.clone(), s.always_visible)
    };
    shared.gate.collapsed.store(collapsed, Ordering::Relaxed);
    // Parked under the first-run welcome: the island is hidden, and whatever
    // the page asks for meanwhile — a fold at boot, a card opening for a timer
    // that ran out — must not wake the poll behind the welcome. The end of the
    // welcome puts the window back as switching Notchy on does.
    if shared.welcome.lock().unwrap().parked {
        return;
    }
    island::apply_geometry(&app, &pref, &position, collapsed, always_visible);
    // The strip — or the bar — must take the mouse unless standby says
    // otherwise, and a resize invalidates the flag either way.
    island::refresh_click_through(&app, &shared.gate);
    shared.gate.settle(collapsed);
}

/// What the webview says `navigator.language` resolves to, and the tray rebuilt
/// in that language.
///
/// The frontend sends this once it is up and again whenever the preference
/// changes. Rust cannot read the system language on Windows without a crate for
/// it, and the webview can -- see i18n::resolve.
#[tauri::command]
fn set_language(app: AppHandle, shared: State<Shared>, language: Option<String>) {
    i18n::set_reported(language);
    let enabled = shared.settings.lock().unwrap().enabled;
    tray::refresh(&app, enabled);
}

// ── Clipboard ─────────────────────────────────────────────────────────────────

#[tauri::command]
fn clipboard_entries(shared: State<Shared>) -> (Vec<clipboard::ClipEntry>, bool) {
    (shared.clipboard.entries(), shared.clipboard.is_watching())
}

/// Watching is off until it is asked for. The app does not start reading what
/// somebody copies because it was launched.
#[tauri::command]
fn clipboard_set_watching(shared: State<Shared>, on: bool) {
    shared.clipboard.set_watching(on);
}

/// Puts an entry back on the clipboard. Text only — see `clipboard::write_back`.
#[tauri::command]
fn clipboard_copy(shared: State<Shared>, id: String) -> bool {
    let entries = shared.clipboard.entries();
    let Some(entry) = entries.iter().find(|e| e.id == id) else { return false };
    clipboard::write_back(entry)
}

#[tauri::command]
fn clipboard_toggle_favourite(shared: State<Shared>, id: String) {
    shared.clipboard.toggle_favourite(&id);
}

#[tauri::command]
fn clipboard_remove(shared: State<Shared>, id: String) {
    shared.clipboard.remove(&id);
}

#[tauri::command]
fn clipboard_clear(shared: State<Shared>) {
    shared.clipboard.clear();
}

/// The front end pushes the island shape; Rust decides click-through from it.
#[tauri::command]
fn set_island_rect(app: AppHandle, shared: State<Shared>, x: f64, y: f64, width: f64, height: f64) {
    shared.gate.set_rect(island::IslandRect { x, y, w: width, h: height });
    // Without the cursor poll the input region is the click-through: it follows the island.
    if !platform::CURSOR_POLL {
        island::refresh_click_through(&app, &shared.gate);
    }
}

#[tauri::command]
fn focus_window(app: AppHandle, focused: bool) {
    if !focused {
        // The field let go, or the island is folding. The keyboard stays with
        // the island until it folds, as the Mac's panel stays key until then:
        // the fold's `page_hide_all` gives it back (web::hide_all). A page in
        // the island holds the keyboard while it is up.
        web::field_lets_go(&app);
        if web::holds_keyboard() {
            return;
        }
    }
    let Some(win) = island::window(&app) else { return };
    if focused {
        // Where the user was, for when the field lets go.
        web::field_takes_keyboard(&app);
    }
    platform::set_activating(&win, focused);
    if focused {
        let _ = win.set_focus();
        // The window's focus no longer reaches its page by itself — the island's
        // window holds several webviews — so the keyboard is put where it goes.
        if let Some(view) = island::webview(&app) {
            if !web::holds_keyboard() {
                let _ = view.set_focus();
            }
        }
    }
}

#[tauri::command]
fn reposition(app: AppHandle, shared: State<Shared>) {
    let (pref, position, always_visible) = {
        let s = shared.settings.lock().unwrap();
        (s.screen.clone(), s.position.clone(), s.always_visible)
    };
    let collapsed = shared.gate.collapsed.load(Ordering::Relaxed);
    island::apply_geometry(&app, &pref, &position, collapsed, always_visible);
    // A display change moves the island; a page anchored to it has to come too.
    web::reanchor(&app);
}

/// The island has been held long enough to come unstuck: from here it follows
/// the pointer. `centre` and `pointer` are both in the window's logical pixels.
#[tauri::command]
fn start_island_drag(
    app: AppHandle,
    shared: State<Shared>,
    centre_x: f64,
    centre_y: f64,
    pointer_x: f64,
    pointer_y: f64,
) {
    island::begin_drag(&app, &shared.gate, (centre_x, centre_y), (pointer_x, pointer_y));
}

/// Moves a picked-up island by how far the pointer has gone since the press, in
/// logical pixels.
///
/// Only Wayland calls this. Where there is a global cursor the poll thread does
/// the moving instead, in the same 16 ms tick it reads the pointer — a round
/// trip per frame would show as the island trailing the hand.
#[tauri::command]
fn drag_island(app: AppHandle, shared: State<Shared>, dx: f64, dy: f64) {
    island::drag_by(&app, &shared.gate, dx, dy);
}

/// Puts the island down where it is. Harmless if it was never picked up, which
/// is what makes it safe to call from a pointer-up that may have lost the race
/// with the poll thread noticing the button come back up.
#[tauri::command]
fn end_island_drag(app: AppHandle) {
    island::finish_drag(&app);
}

#[tauri::command]
fn open_url(url: String) {
    if !(url.starts_with("http://") || url.starts_with("https://")) {
        return;
    }
    platform::open_url(&url);
}

/// Open a message service the way the user actually reaches it: its web page,
/// or a desktop application they picked in Settings.
///
/// Resolved here rather than in the front end because the server address
/// lives in the secret store, which the front end deliberately cannot read —
/// it writes credentials and shows "(stored)", never the value back. So the
/// URL never leaves Rust; only the instruction to open it crosses.
///
/// An application that has since been uninstalled falls back to the web page
/// rather than doing nothing: a second click that goes quiet is
/// indistinguishable from a broken one.
#[tauri::command]
fn open_message_service(source: String) {
    let s = settings::load();
    // Ato has no address to store: it is one Actuar product, always at the
    // same console.
    let (website, target) = match source.as_str() {
        "mattermost" => (secrets::get(messages::MATTERMOST_URL_KEY), s.mattermost_open_target),
        "ato" => (Some(message_proto::ato_conversation_link(None)), s.ato_open_target),
        "whatsapp" => (Some(message_proto::WHATSAPP_URL.to_string()), s.whatsapp_open_target),
        _ => return,
    };
    let wants_app = !target.is_empty() && target != "website";
    if wants_app {
        let path = std::path::Path::new(&target);
        if path.is_absolute() && path.exists() && platform::open_application(path) {
            return;
        }
    }
    if let Some(url) = website {
        if url.starts_with("http://") || url.starts_with("https://") {
            platform::open_url(&url);
        }
    }
}

/// Launch an application the user picked in Settings, for the pill whose
/// second click opens a desktop app rather than a web page.
///
/// No shell, like `open_in_vscode` below: the path comes from a file picker
/// and may hold `&`, `^`, `%` or spaces, which a shell would read as syntax.
/// Absolute paths only — a bare name would be resolved against %PATH%, which
/// is not what a chooser produced.
#[tauri::command]
fn open_application(path: String) -> bool {
    let p = std::path::Path::new(&path);
    if !p.is_absolute() || !p.exists() {
        return false;
    }
    platform::open_application(p)
}

/// "Open terminal" opens the working folder in VS Code when `code` is on PATH,
/// and falls back to the file manager otherwise.
#[tauri::command]
fn open_in_vscode(path: Option<String>) -> bool {
    // No shell anywhere near this. The path is a project folder chosen by
    // whoever is using Claude Code, and a shell would happily read `&`, `^`, `%`
    // or `$` in a folder name as syntax. Finding the launcher ourselves and
    // handing the path over as a separate argument keeps it a path.
    let path = path.filter(|p| !p.is_empty());
    // It arrives in a hook payload: only an existing folder, given by its full
    // path, goes any further. `code` would read `--something` as an option, and
    // xdg-open would launch a file with whatever handles its type.
    if let Some(p) = path.as_deref() {
        let p = std::path::Path::new(p);
        if !(p.is_absolute() && p.is_dir()) {
            return false;
        }
    }
    if let Some(code) = platform::find_on_path("code") {
        let mut cmd = Command::new(code);
        if let Some(p) = path.as_deref() {
            cmd.arg(p);
        }
        if platform::no_console(&mut cmd).spawn().is_ok() {
            return true;
        }
    }
    if let Some(p) = path.as_deref() {
        platform::reveal_folder(p);
    }
    false
}

#[tauri::command]
fn quit_app(app: AppHandle) {
    app.exit(0);
}

// ── Updates ───────────────────────────────────────────────────────────────────

#[tauri::command]
fn update_state(app: AppHandle) -> UpdateState {
    update::state(&app)
}

/// The Check now button.
///
/// It runs whether or not the six-hourly check is switched on: asking once
/// because somebody clicked is not the thing that switch turns off.
#[tauri::command]
async fn update_check(app: AppHandle) {
    update::check_now(app, true).await;
}

/// Only ever called from an explicit click. Downloads the package, verifies its
/// signature, installs it and restarts.
#[tauri::command]
async fn update_install(app: AppHandle) {
    update::install(app).await;
}

/// The master switch, from the settings window.
///
/// Goes through the same path as the tray, so both end up persisted, applied
/// and broadcast rather than one of them only changing what is on screen.
#[tauri::command]
fn set_enabled(app: AppHandle, enabled: bool) {
    set_enabled_now(&app, enabled);
}

// ── Messages ─────────────────────────────────────────────────────────────────
//
// Both take `conversation_id` even though one addresses a Mattermost channel
// and the other an Ato conversation: the card holds one `conversationId` for
// either source, and naming the parameter after each world's own word meant the
// front end had to send every spelling and hope one matched.

/// Today's meetings from the commercial panel. The island hands in the day,
/// because it is the one that knows the local time zone.
#[tauri::command]
async fn agenda_refresh(day_start_ms: i64, day_end_ms: i64) -> agenda::Snapshot {
    agenda::refresh(day_start_ms, day_end_ms).await
}

/// The panel's agenda for one process, in the browser.
#[tauri::command]
fn agenda_open(department: String) {
    platform::open_url(&agenda::agenda_url(&department));
}

#[tauri::command]
async fn mattermost_send_reply(
    conversation_id: String,
    body: String,
    attachments: Vec<String>,
) -> Result<(), String> {
    mattermost::send_reply(conversation_id, body, attachments).await
}

#[tauri::command]
async fn ato_send_reply(
    conversation_id: String,
    body: String,
    attachments: Vec<String>,
) -> Result<(), String> {
    ato::send_reply(conversation_id, body, attachments).await
}

/// A received voice message's audio, as raw bytes rather than a JSON array of
/// numbers: the card makes a blob of it and plays that.
#[tauri::command]
async fn ato_voice_note(storage_file_id: String) -> Result<tauri::ipc::Response, String> {
    ato::voice_note_bytes(storage_file_id).await.map(tauri::ipc::Response::new)
}

/// A received Mattermost photo, as raw bytes the card makes a blob of: the
/// server's preview, or the file itself when it made none.
#[tauri::command]
async fn mattermost_photo(file_id: String, has_preview: bool) -> Result<tauri::ipc::Response, String> {
    mattermost::photo_bytes(file_id, false, has_preview).await.map(tauri::ipc::Response::new)
}

/// Opens a received Mattermost photo whole, in the system's image viewer.
#[tauri::command]
async fn mattermost_open_photo(file_id: String, name: String, mime_type: String) -> Result<(), String> {
    mattermost::open_photo(file_id, name, mime_type).await
}

#[tauri::command]
async fn whatsapp_send_reply(
    app: AppHandle,
    conversation_id: String,
    body: String,
    attachments: Vec<String>,
) -> Result<(), String> {
    whatsapp::send_reply(app, conversation_id, body, attachments).await
}

/// Shows WhatsApp Web for the QR code. Linking a phone is the sign-in.
#[tauri::command]
fn whatsapp_show_login(app: AppHandle) {
    whatsapp::show_login(&app);
}

/// Unlinks this machine and clears the page's profile.
#[tauri::command]
fn whatsapp_sign_out(app: AppHandle) {
    whatsapp::sign_out(&app);
}

/// Signs in to Ato now, throwing the stored session away first — for the
/// person who has just typed a password and is watching the dot.
#[tauri::command]
fn ato_sign_in(app: AppHandle) {
    ato::sign_in_now(app);
}

/// Signs in to Mattermost now, rather than waiting for the supervisor to look
/// again.
///
/// A supervisor refused by the server waits for the credentials to change
/// instead of retrying on a timer, and notices within a few seconds by itself.
/// This is for the person who has just typed a password and should not have to
/// wonder whether anything is happening.
#[tauri::command]
fn mattermost_sign_in(app: AppHandle) {
    mattermost::sign_in_now(app);
}

#[tauri::command]
fn approval_decision(app: AppHandle, request_id: String, decision: String) {
    pipe::answer(&app, &request_id, &decision);
}

/// The island has the card on screen, so the long wait for a human may begin.
/// Until this arrives the relay only waits a few hundred milliseconds, which is
/// what stops a paused or unresponsive island from freezing Claude Code.
#[tauri::command]
fn approval_ack(app: AppHandle, request_id: String) {
    pipe::acknowledge(&app, &request_id);
}

/// Nobody can act on this request — the island is paused, or another card is
/// already up. Claude Code falls back to asking in the terminal immediately.
#[tauri::command]
fn approval_decline(app: AppHandle, request_id: String) {
    pipe::decline(&app, &request_id);
}

// ── Chat, files and secrets ───────────────────────────────────────────────────

/// One chat turn. The API key and any file bytes stay on the Rust side.
///
/// `name` is what Mochi calls the user, as the island resolved it — what was
/// typed under Your name, or the account's first name — and goes into the
/// system prompt's first sentence. Optional, so a caller that sends none gets
/// the prompt as it always was.
#[tauri::command]
async fn chat_send(
    shared: State<'_, Shared>,
    chat: State<'_, Chat>,
    query: String,
    context: Option<ChatContext>,
    name: Option<String>,
) -> Result<ChatReply, String> {
    let model = shared.settings.lock().unwrap().model.clone();
    claude::send(&chat, &model, query, context, name.as_deref()).await
}

#[tauri::command]
fn chat_reset(chat: State<Chat>) {
    chat.reset();
}

/// Copies a dropped file into the inbox and reports its name back.
#[tauri::command]
fn ingest_file(path: String) -> Result<DroppedFile, String> {
    files::ingest(&path)
}

/// Writes pasted bytes into the inbox and reports the file back.
///
/// A copied *file* arrives from the webview as a path and needs nothing. A
/// copied *image* — a screenshot, a crop — has no file behind it, so one is
/// written here and everything downstream sees a path like any other. The
/// clipboard watcher cannot serve this: it keeps a 40 px thumbnail and throws
/// the original pixels away.
#[tauri::command]
fn ingest_bytes(name: String, bytes: Vec<u8>) -> Result<DroppedFile, String> {
    files::ingest_bytes(&name, &bytes)
}

/// The pages' old commands, from before the island drew them in a view of
/// their own (`web::page_show` and the rest). Kept working — a page over the
/// island's whole shape, or put away — until no caller is left.
///
/// Returns whether it is up afterwards.
#[tauri::command]
fn toggle_site_window(app: AppHandle) -> bool {
    web::toggle(&app, web::SITE_LABEL)
}

/// See `toggle_site_window`.
#[tauri::command]
fn toggle_webchat_window(app: AppHandle) -> bool {
    web::toggle(&app, web::CHAT_LABEL)
}

/// See `toggle_site_window`; `web::page_hide_all` now.
#[tauri::command]
fn hide_pages(app: AppHandle) {
    web::hide_all(&app);
}

/// What Claude Code has been doing, and what it cost — the AI Agents dashboard.
///
/// The island may only ask whether a key exists — never read it.
#[tauri::command]
fn secret_present(key: String) -> bool {
    secrets::present(&key)
}

#[tauri::command]
fn secret_set(key: String, value: String) -> Result<(), String> {
    secrets::set(&key, &value)
}

#[tauri::command]
fn secret_clear(key: String) -> Result<(), String> {
    secrets::clear(&key)
}

/// Lets the island write to the same log as the Rust side.
#[tauri::command]
fn log_line(message: String) {
    log::line(format!("ui  {message}"));
}

// ── Settings window ───────────────────────────────────────────────────────────

/// WebView2 allows exactly one browser environment per app, and its options are
/// fixed by whichever webview is created first. Every window must therefore ask
/// for the *same* arguments as the island (see `additionalBrowserArgs` in
/// tauri.conf.json) — a mismatch makes the second window come up blank, with no
/// error anywhere.
const BROWSER_ARGS: &str = "--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection --autoplay-policy=no-user-gesture-required";

/// In a dev build the pages are served by Vite, so the second window needs the
/// absolute dev URL; a bundled build resolves it inside the app bundle.
fn settings_page_url(app: &AppHandle) -> WebviewUrl {
    #[cfg(dev)]
    if let Some(mut base) = app.config().build.dev_url.clone() {
        base.set_path("/settings.html");
        return WebviewUrl::External(base);
    }
    let _ = app;
    WebviewUrl::App("settings.html".into())
}

/// The Settings window's content size and its floor, in logical px — the Mac's
/// (AppDelegate.openSettings).
const SETTINGS_W: f64 = 720.0;
const SETTINGS_H: f64 = 560.0;
const SETTINGS_MIN_W: f64 = 640.0;
const SETTINGS_MIN_H: f64 = 420.0;

/// Clear air kept between Settings and the island beside it, and between
/// Settings and the edges of the work area, in logical px — the Mac's 12pt.
const SETTINGS_GAP: f64 = 12.0;

/// Whether the Settings window has been on screen yet. GTK measures a window's
/// frame only once it is mapped: until then `outer_size` is where the window
/// is, not how big.
static SETTINGS_SHOWN: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// The settings window is created hidden at launch and only ever shown and
/// hidden afterwards. A WebView2 window created later — on the main thread or
/// not — silently comes up blank in this app, so the window that works is the
/// one that exists before the island's webview does.
fn create_settings_window(app: &AppHandle) {
    let url = settings_page_url(app);
    match WebviewWindowBuilder::new(app, "settings", url)
        .additional_browser_args(BROWSER_ARGS)
        // Only what shows while the webview is still blank: once settings/main.ts
        // runs it sets `document.title`, which is what Windows draws from then on
        // and what follows a language change.
        .title(i18n::t(&i18n::current(), "Settings — Notchy"))
        // The Mac's window: 720x560 content, never under 640x420. Where it
        // goes is decided on every open, by `place_settings_window`.
        .inner_size(SETTINGS_W, SETTINGS_H)
        .min_inner_size(SETTINGS_MIN_W, SETTINGS_MIN_H)
        .resizable(true)
        .visible(false)
        // Never focused while hidden (see the welcome's window).
        .focused(false)
        .center()
        .build()
    {
        Ok(win) => {
            web::keep_hosting(&win);
            // Closing it must only hide it, or it could never be reopened.
            let hidden = win.clone();
            win.on_window_event(move |event| {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    api.prevent_close();
                    let _ = hidden.hide();
                }
            });
        }
        Err(err) => log::line(format!("settings window failed: {err}")),
    }
}

/// Same dance as the settings page: dev builds are served by Vite.
fn clipboard_page_url(app: &AppHandle) -> WebviewUrl {
    #[cfg(dev)]
    if let Some(mut base) = app.config().build.dev_url.clone() {
        base.set_path("/clipboard.html");
        return WebviewUrl::External(base);
    }
    let _ = app;
    WebviewUrl::App("clipboard.html".into())
}

/// Created hidden at launch for the same reason the settings window is: a
/// WebView2 window built after the island's webview silently comes up blank.
fn create_clipboard_window(app: &AppHandle) {
    let url = clipboard_page_url(app);
    match WebviewWindowBuilder::new(app, "clipboard", url)
        .additional_browser_args(BROWSER_ARGS)
        .title("Clipboard Manager")
        .inner_size(380.0, 460.0)
        .min_inner_size(320.0, 320.0)
        .resizable(true)
        .decorations(false)
        .transparent(true)
        .always_on_top(true)
        .skip_taskbar(true)
        .visible(false)
        // Never focused while hidden (see the welcome's window).
        .focused(false)
        .center()
        .build()
    {
        Ok(win) => {
            web::keep_hosting(&win);
            // Its edges resize it. Tauri hangs that handle on a borderless
            // window when the webview filling it is created — and with the
            // multiwebview on (web.rs) no webview fills its window any more —
            // or when the window is made resizable, which this asks again.
            #[cfg(windows)]
            let _ = win.set_resizable(true);
            let hidden = win.clone();
            win.on_window_event(move |event| {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    api.prevent_close();
                    let _ = hidden.hide();
                }
            });
        }
        Err(err) => log::line(format!("clipboard window failed: {err}")),
    }
}

/// The island's clipboard button. Toggles, so the same button puts it away.
#[tauri::command]
fn toggle_clipboard_window(app: AppHandle) {
    let Some(win) = app.get_webview_window("clipboard") else {
        log::line("clipboard window missing".to_string());
        return;
    };
    if win.is_visible().unwrap_or(false) {
        let _ = win.hide();
        return;
    }
    let _ = win.show();
    web::bring_up(&win);
}

#[tauri::command]
fn close_clipboard_window(app: AppHandle) {
    if let Some(win) = app.get_webview_window("clipboard") {
        let _ = win.hide();
    }
}

/// Opens Settings, on `section` when one is given (a `SETTINGS_SECTIONS` id in
/// settings/sections.ts: "island" from the ring's gear, "hydration" from the
/// hydration card, …), otherwise on whichever pane it last showed.
///
/// As the Mac's AppDelegate.openSettings does, the island is folded first, so
/// an island that floats over everything cannot cover the window, and the
/// window is placed on the island's display every time it opens.
pub fn show_settings_window(app: &AppHandle, section: Option<&str>) {
    let Some(win) = app.get_webview_window("settings") else {
        log::line("settings window missing");
        return;
    };
    // Before it shows, so the pane is already the right one when it appears.
    if let Some(section) = section {
        let _ = app.emit_to("settings", "settings-section", section.to_string());
    }
    // The same path as the close shortcut and Escape: the island collapses an
    // open card (main.ts, "close-shortcut"), and does nothing when it is
    // already folded.
    let _ = app.emit_to(island::WINDOW_LABEL, "close-shortcut", ());
    let _ = win.unminimize();
    let placed_at = place_settings_window(app, &win);
    let _ = win.show();
    SETTINGS_SHOWN.store(true, Ordering::Relaxed);
    // A hidden window may take its new display's scale only as it is shown,
    // and keeps its logical size as it does: placed again, in those pixels.
    let rescaled = placed_at
        .zip(win.scale_factor().ok())
        .is_some_and(|(then, now)| (then - now).abs() > 1e-6);
    if rescaled {
        place_settings_window(app, &win);
    }
    web::bring_up(&win);
}

/// Puts the window on the island's display, centred across its work area and
/// clear of the island's resting bar, as AppDelegate.placeBelowIsland does:
/// 12 px under the bar when the island is at the top, and under or over a
/// dropped one, on the side it opens into; centred, above the bar, when the
/// island is at the bottom. A window coming up from hidden is the Mac's
/// 720x560 again, as a new NSWindow is there; one already on screen keeps its
/// size. Never taller than the room it is given, never off the work area.
///
/// Returns the scale factor the window was sized at, or None when there was
/// nothing to place.
fn place_settings_window(app: &AppHandle, win: &tauri::WebviewWindow) -> Option<f64> {
    let (screen, position) = {
        let shared = app.try_state::<Shared>()?;
        let s = shared.settings.lock().unwrap();
        (s.screen.clone(), s.position.clone())
    };
    let info = island::screen_info(app, &screen);
    let scale = info.scale;
    let px = |v: f64| (v * scale).round() as i32;
    let (work_x, work_y) = (px(info.work_x), px(info.work_y));
    let (work_w, work_h) = (px(info.work_width), px(info.work_height));
    let shown = win.is_visible().unwrap_or(false);

    // Onto the island's display before anything is measured or sized. A
    // window that crosses to a display at another scale is rescaled as it
    // lands, keeping its logical size, so sizes are logical from here on and
    // the pixels are read back once it is there.
    let on_target = win
        .current_monitor()
        .ok()
        .flatten()
        .is_some_and(|m| (m.position().x, m.position().y) == (px(info.x), px(info.y)));
    if !on_target {
        let _ = win.set_position(tauri::PhysicalPosition::new(
            work_x + (work_w - px(SETTINGS_W)) / 2,
            work_y + (work_h - px(SETTINGS_H)) / 2,
        ));
    }
    let ws = win.scale_factor().unwrap_or(scale);

    let (w, h) = match (shown, win.inner_size()) {
        (true, Ok(inner)) => (inner.width as f64 / ws, inner.height as f64 / ws),
        _ => (SETTINGS_W, SETTINGS_H),
    };
    // The title bar and borders are the OS's: whatever outer is over inner,
    // on this display. Nothing until GTK has framed the window once.
    let measured = cfg!(not(target_os = "linux")) || SETTINGS_SHOWN.load(Ordering::Relaxed);
    let (chrome_w, chrome_h) = match (measured, win.outer_size(), win.inner_size()) {
        (true, Ok(outer), Ok(inner)) => (
            outer.width.saturating_sub(inner.width) as f64 / ws,
            outer.height.saturating_sub(inner.height) as f64 / ws,
        ),
        _ => (0.0, 0.0),
    };
    let min_h = SETTINGS_MIN_H + chrome_h;

    let bar = island::resting_bar(&info, &position);
    let outer_w = (w + chrome_w).min(info.work_width).max(SETTINGS_MIN_W + chrome_w);
    let (_, outer_h) = settings_vertical(bar, info.work_height, h + chrome_h, min_h);
    let _ = win.set_size(tauri::LogicalSize::new(outer_w - chrome_w, outer_h - chrome_h));

    // Placed by the size it came out at, in this display's pixels.
    let (ow, oh, logical_h) = match (measured, win.outer_size()) {
        (true, Ok(outer)) => (outer.width as i32, outer.height as i32, outer.height as f64 / ws),
        _ => (px(outer_w), px(outer_h), outer_h),
    };
    let (top, _) = settings_vertical(bar, info.work_height, logical_h, min_h);
    // On a display too small for it the top-left wins, so the title bar can
    // still be grabbed.
    let x = (work_x + (work_w - ow) / 2).min(work_x + work_w - ow).max(work_x);
    let y = (work_y + px(top)).min(work_y + work_h - oh).max(work_y);
    let _ = win.set_position(tauri::PhysicalPosition::new(x, y));
    Some(ws)
}

/// Settings' top edge and outer height, in logical px from the top of a work
/// area `work_h` tall, for a window that would be `want_h` tall and is never
/// less than `min_h`, kept clear of the island's resting `bar`.
fn settings_vertical(bar: island::RestingBar, work_h: f64, want_h: f64, min_h: f64) -> (f64, f64) {
    let gap = SETTINGS_GAP;
    // Hung under the bar, as the Mac hangs it under the island: the top 12
    // below it, the height cut to leave 12 above the bottom of the work area.
    let under = |bar_bottom: f64| {
        let top = (bar_bottom + gap).max(0.0);
        let h = want_h.min((work_h - gap - top).max(min_h));
        (top.min(work_h - gap - h), h)
    };
    // Standing on it: the bottom 12 above it, as the welcome stands on it.
    let over = |bar_top: f64| {
        let bottom = bar_top - gap;
        let h = want_h.min((bottom - gap).max(min_h));
        ((bottom - h).max(gap), h)
    };
    let (top, h) = match bar {
        island::RestingBar::Top { bottom } => under(bottom),
        island::RestingBar::Bottom { top: bar_top } => {
            // Centred in the work area while that keeps it off the bar; else
            // centred in what is left above the bar.
            let h = want_h.min((work_h - 2.0 * gap).max(min_h));
            let top = (work_h - h) / 2.0;
            if top + h <= bar_top - gap {
                (top, h)
            } else {
                let room = bar_top - 2.0 * gap;
                let h = want_h.min(room.max(min_h));
                (gap + (room - h) / 2.0, h)
            }
        }
        island::RestingBar::Free { top: bar_top, bottom: bar_bottom, grows_down } => {
            // The side the island opens into, unless Settings does not fit
            // there and the other side has more room.
            let below = work_h - gap - (bar_bottom + gap);
            let above = bar_top - 2.0 * gap;
            let down = if grows_down {
                below >= min_h || below >= above
            } else {
                above < min_h && below > above
            };
            if down { under(bar_bottom) } else { over(bar_top) }
        }
    };
    // Never off the work area; on one too short for it the top wins.
    (top.min(work_h - h).max(0.0), h)
}

/// Settings from the front end — the island's gear, the ring, a card's
/// "Settings…" — on `section` when one is named.
#[tauri::command]
fn open_settings_window(app: AppHandle, section: Option<String>) {
    show_settings_window(&app, section.as_deref());
}

pub fn run() {
    // First of all, and before a single thread exists: the release profile is
    // `panic = "abort"` and the binary carries no console, so without this a
    // panic anywhere ends the process with nothing written down at all.
    log::install_panic_hook();
    // And if it dies anyway, the OS is what brings it back.
    platform::register_restart(RECOVERED_ARG);
    let recovered = std::env::args().any(|arg| arg == RECOVERED_ARG);

    platform::prepare_environment();
    let (loaded, settings_from_file) = settings::load_from_disk();
    let gate = Arc::new(PollGate::new());

    // The welcome comes before Notchy opens, on a first run — and on the first
    // run after an update whose welcome gained a screen — or on any run that
    // `NOTCHY_ONBOARDING` asks for one. Not while Notchy is off: the welcome
    // ends by opening the island, and an island that is off cannot.
    let preview = welcome_preview();
    let welcome_first = loaded.enabled && (preview.is_some() || loaded.onboarding_pending());
    let welcome = if welcome_first {
        Welcome {
            step: Some(preview.clone().unwrap_or_else(|| "welcome".to_string())),
            parked: true,
            preview: preview.is_some(),
        }
    } else {
        Welcome::default()
    };
    // What the island does at launch: on and answering, or parked — off, or
    // waiting under the welcome, which looks exactly the same from outside.
    let live = loaded.enabled && !welcome_first;

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            // Launching a second time must not quietly switch Coucou back on —
            // a desktop shortcut, or an autostart that races the first copy,
            // used to be enough to undo it. Off, the one window worth showing
            // is the one with the switch in it. On, it opens the island — or
            // brings the welcome back, while the island is waiting on it.
            if is_enabled(app) {
                open_island(app);
            } else {
                show_settings_window(app, None);
            }
        }))
        .plugin(tauri_plugin_autostart::init(MacosLauncher::LaunchAgent, None))
        // The native file picker behind the reply box's paperclip. A departure
        // from "everything that touches the OS goes through Coucou's own
        // commands" (capabilities/default.json), made deliberately: a file
        // chooser is one of the few things worth not hand-rolling twice.
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        // The shortcut that closes the island: see shortcut.rs.
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .manage(Shared {
            clipboard: clipboard::Clipboard::new(),
            settings: Mutex::new(loaded.clone()),
            gate: gate.clone(),
            recovered,
            welcome: Mutex::new(welcome),
        })
        .manage(Updates::default())
        .manage(shortcut::ShortcutStatus::default())
        .manage(AutostartStatus::default())
        .manage(Pending::default())
        .manage(Chat::default())
        // The island records voice notes, and a chrome-less, non-activating,
        // always-on-top window is the worst possible place for a webview's own
        // permission bubble: it would draw inside a card nobody can click.
        // Answering here is what keeps that prompt from ever appearing.
        //
        // The island is declared in tauri.conf.json, so there is no window
        // builder to hang this on — the app-level hook reaches it anyway,
        // because `prepare_webview` installs a per-webview handler for every
        // webview whenever this is set. The label check is what keeps it from
        // being app-*wide*: `web.rs` opens whatever site the user configured,
        // and that page must never get the microphone.
        //
        // `Default` for everything else is not a grant. On Windows it lets
        // WebView2 run its own flow; on Linux wry documents the default as
        // Deny. Underneath both sits the OS switch that no handler overrides —
        // on Windows, Settings > Privacy & security > Microphone > "Let
        // desktop apps access your microphone".
        .on_permission_request(|webview, kind| {
            use tauri::webview::{PermissionKind, PermissionResponse};
            match kind {
                PermissionKind::Microphone if webview.label() == island::WINDOW_LABEL => {
                    PermissionResponse::Allow
                }
                _ => PermissionResponse::Default,
            }
        })
        .invoke_handler(tauri::generate_handler![
            boot,
            save_settings,
            shortcut::close_shortcut_error,
            autostart_error,
            set_collapsed,
            set_language,
            set_island_rect,
            clipboard_entries,
            toggle_clipboard_window,
            close_clipboard_window,
            clipboard_set_watching,
            clipboard_copy,
            clipboard_toggle_favourite,
            clipboard_remove,
            clipboard_clear,
            media::media_command,
            focus_window,
            reposition,
            start_island_drag,
            drag_island,
            end_island_drag,
            open_url,
            open_message_service,
            open_application,
            open_in_vscode,
            quit_app,
            update_state,
            update_check,
            update_install,
            approval_decision,
            approval_ack,
            approval_decline,
            log_line,
            chat_send,
            chat_reset,
            ingest_file,
            ingest_bytes,
            toggle_site_window,
            toggle_webchat_window,
            hide_pages,
            web::page_show,
            web::page_hide,
            web::page_hide_all,
            web::page_reload,
            web::page_back,
            web::page_open_in_browser,
            secret_present,
            secret_set,
            secret_clear,
            open_settings_window,
            finish_onboarding,
            show_onboarding,
            drag_onboarding_window,
            set_enabled,
            mattermost_send_reply,
            ato_send_reply,
            ato_voice_note,
            mattermost_photo,
            mattermost_open_photo,
            ato_sign_in,
            agenda_refresh,
            agenda_open,
            mattermost_sign_in,
            whatsapp_send_reply,
            whatsapp_show_login,
            whatsapp_sign_out,
        ])
        .setup(move |app| {
            let handle = app.handle().clone();
            // Built with the state already in it, so the first menu someone
            // opens after launching off does not say "Turn Coucou off".
            tray::build(&handle, loaded.enabled)?;
            // Not under the welcome either: the message clients and the player
            // start as it ends, the way the Mac holds its messaging back.
            integrations::apply_master(live);
            shortcut::apply(&handle, &loaded);
            // The windows people open by hand are built here, at launch, so
            // they come up at once: one built later from a command — on the
            // main thread — deadlocks WebView2 or comes up blank. The island's
            // own already exists (tauri.conf.json), so the site goes first,
            // straight into its window, with its arguments. ChatGPT and
            // WhatsApp each run a WebView2 profile of their own, which is a
            // whole set of Edge processes, so they are built off the main
            // thread when they are first wanted instead (web.rs, whatsapp.rs).
            web::create(&handle);
            create_settings_window(&handle);
            create_clipboard_window(&handle);
            create_onboarding_window(&handle);

            if let Some(win) = island::window(&handle) {
                // Unconditional: on Linux this has to run before the first map,
                // whether or not the window is about to be shown.
                platform::make_non_activating(&win);
                if let Some(view) = island::webview(&handle) {
                    platform::enable_media_stream(&view);
                }
                // The other three windows hide themselves on a close, because
                // something can reopen them. Nothing reopens the island, so it
                // only ever refuses: `"closable": false` greys out the system
                // menu's Close but does not stop a WM_CLOSE from "End task", from
                // a third-party window manager, or from a stray tool — and a
                // destroyed island is, from the tray, the app having vanished.
                // Shutdown and logoff do not come through here; they are
                // WM_QUERYENDSESSION, and the tray's Quit is an exit, not a close.
                win.on_window_event(move |event| {
                    if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                        api.prevent_close();
                    }
                });
                if live {
                    island::apply_geometry(
                        &handle,
                        &loaded.screen,
                        &loaded.position,
                        false,
                        loaded.always_visible,
                    );
                    let _ = win.show();
                } else {
                    // tauri.conf.json declares the window visible, so an off
                    // state has to undo it here or every launch turns Coucou
                    // back on. Nothing has painted yet, so there is no flash.
                    // Under the welcome it is the same parked island: nothing
                    // on it can open, sound or take the keyboard from the name
                    // field, and the welcome's end brings it up.
                    let _ = win.hide();
                }
            }
            gate.collapsed.store(!live, Ordering::Relaxed);
            gate.standby.store(loaded.standby, Ordering::Relaxed);
            gate.always_visible.store(loaded.always_visible, Ordering::Relaxed);
            // Nothing drawn yet, so nothing takes the mouse until the page
            // reports the island's shape.
            if !platform::CURSOR_POLL {
                island::refresh_click_through(&handle, &gate);
            }
            // Off means off: the window is hidden, so there is nothing left to
            // keep reachable and the thread costs exactly nothing.
            if live {
                gate.settle(false);
            } else {
                gate.set_mode(island::Watch::Parked);
            }
            if welcome_first {
                show_onboarding_window(&handle);
            }
            island::spawn_cursor_poll(handle.clone(), gate.clone());
            clipboard::spawn(handle.clone());
            // Debug builds only: NOTCHY_SMOKE_VIEW opens a page for a screenshot.
            web::smoke(&handle);

            // Both ends of a run are logged, so a `started` with no `quit` before
            // it is a death — one `tail` instead of an afternoon. `(recovered)`
            // means the OS is the one that brought this copy back.
            log::line(format!(
                "--- Coucou {} started{} ---",
                env!("CARGO_PKG_VERSION"),
                if recovered { " (recovered)" } else { "" }
            ));
            hooks::ensure_hook_exe(&handle);
            pipe::start(handle.clone());
            media::start(handle.clone());
            // Both supervisors are safe to start here: neither opens a socket,
            // nor reaches the network at all, until its pill is on and the
            // credentials are stored. They watch for both on their own.
            mattermost::start(handle.clone());
            ato::start(handle.clone());
            // Blank until the pill is on and this machine is linked.
            whatsapp::start(handle.clone());
            // ClickMassa was removed; its stored password goes with it.
            secrets::forget_retired();
            // Last, and on a timer of its own: the first look at GitHub happens
            // a minute and a half from now, long after everything above has
            // settled. It installs nothing on its own.
            update::start(handle.clone());
            // The preference only ever reached the OS from `save_settings`, on a
            // change. A fresh install therefore defaulted to "launch at startup"
            // and never registered, so Coucou did not come back after a reboot —
            // which is most of what "it closes by itself" means over a week.
            //
            // A fresh install now starts off, as the Mac does. Without a
            // settings.json to say otherwise, what the OS has is the answer
            // (`autostart_at_launch`): an older build, whose default was on,
            // registered itself without ever writing the file, and the new
            // default must not unregister it.
            let manager = handle.autolaunch();
            let registered = manager.is_enabled().unwrap_or(false);
            let stored = settings_from_file.then_some(loaded.autostart);
            let wanted = settings::autostart_at_launch(stored, registered);
            if wanted != loaded.autostart {
                if let Some(shared) = handle.try_state::<Shared>() {
                    let updated = {
                        let mut current = shared.settings.lock().unwrap();
                        current.autostart = wanted;
                        current.clone()
                    };
                    log::line("autostart: no settings.json, kept what is registered");
                    let _ = handle.emit("settings-changed", updated);
                }
            }
            if registered != wanted {
                let result = if wanted {
                    manager.enable()
                } else {
                    manager.disable()
                };
                if let Err(err) = result {
                    log::line(format!("autostart: {err}"));
                }
            }
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while running Coucou")
        .run(|_app, event| match event {
            // `code` is what tells the three cases apart: None is the user or
            // the session (last window closed, logoff, shutdown), Some is us
            // (the tray's Quit, the updater's restart). Nothing is prevented
            // here — both of those have to be able to end the process.
            tauri::RunEvent::ExitRequested { code, .. } => {
                let why = match code {
                    Some(code) => format!("code {code}"),
                    None => "user or session".to_string(),
                };
                log::line(format!("exit requested — {why}"));
            }
            tauri::RunEvent::Exit => {
                log::line(format!("--- Coucou {} quit ---", env!("CARGO_PKG_VERSION")));
            }
            _ => {}
        });
}

#[cfg(test)]
mod settings_window_tests {
    use super::*;
    use island::RestingBar;

    /// A 1080p display at 100 % with a 48 px taskbar along the bottom.
    const WORK_H: f64 = 1032.0;
    /// The Mac's window with a 32 px title bar.
    const WANT: f64 = SETTINGS_H + 32.0;
    const MIN: f64 = SETTINGS_MIN_H + 32.0;

    fn near(a: f64, b: f64) -> bool {
        (a - b).abs() < 1e-6
    }

    #[test]
    fn it_hangs_under_an_island_at_the_top() {
        let (top, h) = settings_vertical(RestingBar::Top { bottom: 32.0 }, WORK_H, WANT, MIN);
        assert!(near(top, 32.0 + SETTINGS_GAP) && near(h, WANT), "{top}, {h}");
    }

    #[test]
    fn under_a_top_island_on_a_short_display_it_is_cut_to_fit() {
        // 1366x768 at 125 %: 576 logical px of work area.
        let (top, h) = settings_vertical(RestingBar::Top { bottom: 32.0 }, 576.0, WANT, MIN);
        assert!(near(top, 44.0) && near(top + h, 576.0 - SETTINGS_GAP), "{top}, {h}");
    }

    #[test]
    fn it_centres_over_an_island_at_the_bottom_with_room_to_spare() {
        let bar = RestingBar::Bottom { top: WORK_H - 2.0 - 32.0 };
        let (top, h) = settings_vertical(bar, WORK_H, WANT, MIN);
        assert!(near(top, (WORK_H - WANT) / 2.0) && near(h, WANT), "{top}, {h}");
    }

    #[test]
    fn it_never_reaches_down_over_an_island_at_the_bottom() {
        // 1080p at 175 %: the centred window would end on the bar.
        let work_h = 576.0;
        let bar_top = work_h - 2.0 - 32.0;
        let (top, h) = settings_vertical(RestingBar::Bottom { top: bar_top }, work_h, WANT, MIN);
        assert!(top + h <= bar_top - SETTINGS_GAP + 1e-6, "{top} + {h} reaches the bar at {bar_top}");
        assert!(top >= SETTINGS_GAP - 1e-6, "{top}");
    }

    #[test]
    fn it_keeps_clear_of_a_dropped_island() {
        // Dropped 40 % of the way down: it opens downward, and Settings hangs under it.
        let bar = RestingBar::Free { top: 396.8, bottom: 428.8, grows_down: true };
        let (top, h) = settings_vertical(bar, WORK_H, WANT, MIN);
        assert!(near(top, 428.8 + SETTINGS_GAP), "{top}");
        assert!(top + h <= WORK_H - SETTINGS_GAP + 1e-6, "{top} + {h}");
        // Dropped 70 % of the way down: it opens upward, and Settings stands on it.
        let bar = RestingBar::Free { top: 706.4, bottom: 738.4, grows_down: false };
        let (top, h) = settings_vertical(bar, WORK_H, WANT, MIN);
        assert!(near(top + h, 706.4 - SETTINGS_GAP), "{top} + {h}");
    }

    #[test]
    fn a_dropped_island_with_no_room_on_its_side_sends_it_to_the_other() {
        // Just under the middle: too little room below for even the smallest
        // window, and more above.
        let bar = RestingBar::Free { top: 600.0, bottom: 632.0, grows_down: true };
        let (top, h) = settings_vertical(bar, WORK_H, WANT, MIN);
        assert!(top + h <= 600.0 - SETTINGS_GAP + 1e-6, "{top} + {h} reaches the bar at 600");
    }

    #[test]
    fn it_never_leaves_the_work_area() {
        let (top, h) = settings_vertical(RestingBar::Top { bottom: 32.0 }, 300.0, WANT, MIN);
        assert!(near(top, 0.0) && near(h, MIN), "{top}, {h}");
    }
}
