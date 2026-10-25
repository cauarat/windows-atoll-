// Coucou for Windows — app wiring and the commands the island calls.

mod claude;
mod clipboard;
mod clickmassa;
mod files;
mod hooks;
mod integrations;
mod mattermost;
mod media;
mod message_proto;
mod messages;
mod island;
mod log;
mod pipe;
mod platform;
mod secrets;
mod settings;
mod tray;
mod update;
mod usage;
mod web;

use std::process::Command;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_autostart::{ManagerExt, MacosLauncher};

use claude::{Chat, ChatContext, ChatReply};
use files::DroppedFile;
use hooks::{HookPreview, HookStatus};
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

/// Applies the switch to the window, the cursor thread and the tray.
///
/// The order is load-bearing in both directions: park the poll thread before
/// hiding, or it re-asserts click-through on a window that is no longer there;
/// show before waking it, or it computes hit-testing against a hidden window.
fn apply_enabled(app: &AppHandle, shared: &Shared, enabled: bool) {
    integrations::apply_master(enabled);
    if let Some(win) = island::window(app) {
        if enabled {
            let (screen, position) = {
                let s = shared.settings.lock().unwrap();
                (s.screen.clone(), s.position.clone())
            };
            island::apply_geometry(app, &screen, &position, false);
            shared.gate.collapsed.store(false, Ordering::Relaxed);
            if !platform::CURSOR_POLL {
                island::refresh_click_through(app, &shared.gate);
            }
            let _ = win.show();
            shared.gate.set_active(true);
        } else {
            shared.gate.set_active(false);
            // Belt and braces: if hide() is ignored by an exotic compositor,
            // nothing on the island can still take the mouse.
            island::set_ignore_cursor(app, true);
            // Hiding is what makes this an off switch rather than the old Pause:
            // the 240×6 wake strip goes with it, so sweeping that corner of the
            // screen no longer brings Mochi back.
            let _ = win.hide();
            // The pages the island opens are the island's, so off puts them
            // away too — an always-on-top ChatGPT left over a switched-off
            // Coucou would be the one thing still on screen.
            web::hide_all(app);
        }
    }
    tray::refresh(app, enabled);
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
        media: cfg!(windows),
        recovered: shared.recovered,
    }
}

#[tauri::command]
fn save_settings(app: AppHandle, shared: State<Shared>, settings: Settings) {
    let (placement_changed, autostart_changed, enabled_changed, standby_changed) = {
        let mut current = shared.settings.lock().unwrap();
        let placement_changed =
            current.screen != settings.screen || current.position != settings.position;
        let autostart_changed = current.autostart != settings.autostart;
        let enabled_changed = current.enabled != settings.enabled;
        let standby_changed = current.standby != settings.standby;
        *current = settings.clone();
        (placement_changed, autostart_changed, enabled_changed, standby_changed)
    };
    if let Err(err) = settings::save(&settings) {
        eprintln!("[coucou] could not save settings: {err}");
    }
    if autostart_changed {
        let manager = app.autolaunch();
        let result = if settings.autostart { manager.enable() } else { manager.disable() };
        if let Err(err) = result {
            eprintln!("[coucou] autostart: {err}");
        }
    }
    if placement_changed {
        let collapsed = shared.gate.collapsed.load(Ordering::Relaxed);
        island::apply_geometry(&app, &settings.screen, &settings.position, collapsed);
        web::reanchor(&app);
    }
    if enabled_changed {
        apply_enabled(&app, &shared, settings.enabled);
    }
    if standby_changed {
        // Turning standby off while the island is already folded has to hand the
        // wake strip back at once, or the only way out would be a message.
        shared.gate.standby.store(settings.standby, Ordering::Relaxed);
        island::refresh_click_through(&app, &shared.gate);
    }
    // Keep the other window in step (island ⇄ settings window).
    let _ = app.emit("settings-changed", settings);
}

/// Hidden island → shrink the window to the invisible wake strip and park the
/// cursor poll; anything else → full panel and 60 Hz polling.
#[tauri::command]
fn set_collapsed(app: AppHandle, shared: State<Shared>, collapsed: bool) {
    let (pref, position) = {
        let s = shared.settings.lock().unwrap();
        (s.screen.clone(), s.position.clone())
    };
    shared.gate.collapsed.store(collapsed, Ordering::Relaxed);
    island::apply_geometry(&app, &pref, &position, collapsed);
    // The wake strip must take the mouse unless standby says otherwise, and a
    // resize invalidates the flag either way.
    island::refresh_click_through(&app, &shared.gate);
    shared.gate.set_active(!collapsed);
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
    let Some(win) = island::window(&app) else { return };
    platform::set_activating(&win, focused);
    if focused {
        let _ = win.set_focus();
    }
}

#[tauri::command]
fn reposition(app: AppHandle, shared: State<Shared>) {
    let (pref, position) = {
        let s = shared.settings.lock().unwrap();
        (s.screen.clone(), s.position.clone())
    };
    let collapsed = shared.gate.collapsed.load(Ordering::Relaxed);
    island::apply_geometry(&app, &pref, &position, collapsed);
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
    let (url_key, target) = match source.as_str() {
        "mattermost" => (messages::MATTERMOST_URL_KEY, s.mattermost_open_target),
        "clickmassa" => (messages::CLICKMASSA_URL_KEY, s.clickmassa_open_target),
        _ => return,
    };
    let wants_app = !target.is_empty() && target != "website";
    if wants_app {
        let path = std::path::Path::new(&target);
        if path.is_absolute() && path.exists() && platform::open_application(path) {
            return;
        }
    }
    if let Some(url) = secrets::get(url_key) {
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
// and the other a ClickMassa ticket: the card holds one `conversationId` for
// either source, and naming the parameter after each world's own word meant the
// front end had to send every spelling and hope one matched.

#[tauri::command]
async fn mattermost_send_reply(
    conversation_id: String,
    body: String,
    attachments: Vec<String>,
) -> Result<(), String> {
    mattermost::send_reply(conversation_id, body, attachments).await
}

#[tauri::command]
async fn clickmassa_send_reply(conversation_id: String, body: String) -> Result<(), String> {
    clickmassa::send_reply(conversation_id, body).await
}

/// Signs in to Mattermost now, rather than waiting for the supervisor to look
/// again.
///
/// A supervisor refused by the server waits for the credentials to change
/// instead of retrying on a timer, and notices within a few seconds by itself.
/// This is for the person who has just typed a password and should not have to
/// wonder whether anything is happening. ClickMassa needs no equivalent: it has
/// waited and re-read the credentials on its own all along.
#[tauri::command]
fn mattermost_sign_in(app: AppHandle) {
    mattermost::sign_in_now(app);
}

// ── Claude Code hooks ─────────────────────────────────────────────────────────

#[tauri::command]
fn hooks_status() -> HookStatus {
    hooks::status()
}

/// Returns the diff the user has to look at before anything is written.
#[tauri::command]
fn hooks_preview(install: bool) -> Result<HookPreview, String> {
    hooks::preview(install)
}

/// Only ever called from an explicit click in the settings window.
#[tauri::command]
fn hooks_apply(
    app: AppHandle,
    shared: State<Shared>,
    install: bool,
    fingerprint: String,
) -> Result<String, String> {
    // The fingerprint comes from the preview the user actually looked at, so a
    // settings.json that changed in between is refused rather than overwritten.
    let backup = hooks::write(install, &fingerprint)?;
    let updated = {
        let mut current = shared.settings.lock().unwrap();
        current.hooks_installed = install;
        let _ = settings::save(&current);
        current.clone()
    };
    let _ = app.emit("settings-changed", updated);
    Ok(backup)
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
#[tauri::command]
async fn chat_send(
    shared: State<'_, Shared>,
    chat: State<'_, Chat>,
    query: String,
    context: Option<ChatContext>,
) -> Result<ChatReply, String> {
    let model = shared.settings.lock().unwrap().model.clone();
    claude::send(&chat, &model, query, context).await
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

/// The globe on the island: the configured page, anchored to the island.
///
/// Returns whether it is on screen afterwards. The island holds itself open
/// while a page is up: anchored to the card, a page whose island folded away
/// underneath it would be left hanging in mid-air.
#[tauri::command]
fn toggle_site_window(app: AppHandle) -> bool {
    web::toggle(&app, web::SITE_LABEL)
}

/// The chat tab, when it is set to open the website rather than the built-in
/// chat.
#[tauri::command]
fn toggle_webchat_window(app: AppHandle) -> bool {
    web::toggle(&app, web::CHAT_LABEL)
}

/// Puts both pages away.
///
/// Called when the island stops being expanded, by any route. A page is
/// anchored flush against the island's card, so it cannot outlive it on screen:
/// left up, it would hang in mid-air beside an island that is no longer there.
#[tauri::command]
fn hide_pages(app: AppHandle) {
    web::hide_all(&app);
}

/// What Claude Code has been doing, and what it cost — the AI Agents dashboard.
///
/// Rescanning reads only what was appended since the last pass, but the first
/// one after a launch reads every transcript, so it runs on the blocking pool
/// rather than holding up the island's webview.
#[tauri::command]
async fn agent_usage() -> Result<usage::Snapshot, String> {
    tauri::async_runtime::spawn_blocking(usage::refresh)
        .await
        .map_err(|err| err.to_string())
}

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

/// The settings window is created hidden at launch and only ever shown and
/// hidden afterwards. A WebView2 window created later — on the main thread or
/// not — silently comes up blank in this app, so the window that works is the
/// one that exists before the island's webview does.
fn create_settings_window(app: &AppHandle) {
    let url = settings_page_url(app);
    match WebviewWindowBuilder::new(app, "settings", url)
        .additional_browser_args(BROWSER_ARGS)
        .title("Settings — Coucou")
        .inner_size(560.0, 680.0)
        .min_inner_size(460.0, 480.0)
        .resizable(true)
        .visible(false)
        .center()
        .build()
    {
        Ok(win) => {
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
        .center()
        .build()
    {
        Ok(win) => {
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
    let _ = win.set_focus();
}

#[tauri::command]
fn close_clipboard_window(app: AppHandle) {
    if let Some(win) = app.get_webview_window("clipboard") {
        let _ = win.hide();
    }
}

pub fn show_settings_window(app: &AppHandle) {
    let Some(win) = app.get_webview_window("settings") else {
        log::line("settings window missing");
        return;
    };
    let _ = win.unminimize();
    let _ = win.show();
    let _ = win.set_focus();
}

#[tauri::command]
fn open_settings_window(app: AppHandle) {
    show_settings_window(&app);
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
    let loaded = settings::load();
    let gate = Arc::new(PollGate::new());

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            // Launching a second time must not quietly switch Coucou back on —
            // a desktop shortcut, or an autostart that races the first copy,
            // used to be enough to undo it. Off, the one window worth showing
            // is the one with the switch in it.
            if is_enabled(app) {
                let _ = app.emit_to(island::WINDOW_LABEL, "tray", "open".to_string());
            } else {
                show_settings_window(app);
            }
        }))
        .plugin(tauri_plugin_autostart::init(MacosLauncher::LaunchAgent, None))
        // The native file picker behind the reply box's paperclip. A departure
        // from "everything that touches the OS goes through Coucou's own
        // commands" (capabilities/default.json), made deliberately: a file
        // chooser is one of the few things worth not hand-rolling twice.
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .manage(Shared {
            clipboard: clipboard::Clipboard::new(),
            settings: Mutex::new(loaded.clone()),
            gate: gate.clone(),
            recovered,
        })
        .manage(Updates::default())
        .manage(Pending::default())
        .manage(Chat::default())
        .invoke_handler(tauri::generate_handler![
            boot,
            save_settings,
            set_collapsed,
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
            hooks_status,
            hooks_preview,
            hooks_apply,
            approval_decision,
            approval_ack,
            approval_decline,
            log_line,
            chat_send,
            chat_reset,
            ingest_file,
            ingest_bytes,
            agent_usage,
            toggle_site_window,
            toggle_webchat_window,
            hide_pages,
            secret_present,
            secret_set,
            secret_clear,
            open_settings_window,
            set_enabled,
            mattermost_send_reply,
            clickmassa_send_reply,
            mattermost_sign_in,
        ])
        .setup(move |app| {
            let handle = app.handle().clone();
            // Built with the state already in it, so the first menu someone
            // opens after launching off does not say "Turn Coucou off".
            tray::build(&handle, loaded.enabled)?;
            integrations::apply_master(loaded.enabled);
            // Before the island: see create_settings_window.
            create_settings_window(&handle);
            create_clipboard_window(&handle);
            web::create(&handle);

            if let Some(win) = island::window(&handle) {
                // Unconditional: on Linux this has to run before the first map,
                // whether or not the window is about to be shown.
                platform::make_non_activating(&win);
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
                if loaded.enabled {
                    island::apply_geometry(&handle, &loaded.screen, &loaded.position, false);
                    let _ = win.show();
                } else {
                    // tauri.conf.json declares the window visible, so an off
                    // state has to undo it here or every launch turns Coucou
                    // back on. Nothing has painted yet, so there is no flash.
                    let _ = win.hide();
                }
            }
            gate.collapsed.store(!loaded.enabled, Ordering::Relaxed);
            gate.standby.store(loaded.standby, Ordering::Relaxed);
            // Nothing drawn yet, so nothing takes the mouse until the page
            // reports the island's shape.
            if !platform::CURSOR_POLL {
                island::refresh_click_through(&handle, &gate);
            }
            gate.set_active(loaded.enabled);
            island::spawn_cursor_poll(handle.clone(), gate.clone());
            clipboard::spawn(handle.clone());

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
            clickmassa::start(handle.clone());
            // Last, and on a timer of its own: the first look at GitHub happens
            // a minute and a half from now, long after everything above has
            // settled. It installs nothing on its own.
            update::start(handle.clone());
            // The preference only ever reached the OS from `save_settings`, on a
            // change. A fresh install therefore defaulted to "launch at startup"
            // and never registered, so Coucou did not come back after a reboot —
            // which is most of what "it closes by itself" means over a week.
            let manager = handle.autolaunch();
            if manager.is_enabled().unwrap_or(false) != loaded.autostart {
                let result = if loaded.autostart {
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
