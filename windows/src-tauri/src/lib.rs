// Coucou for Windows — app wiring and the commands the island calls.

mod claude;
mod clickmassa;
mod files;
mod hooks;
mod integrations;
mod mattermost;
mod message_proto;
mod messages;
mod island;
mod log;
mod pipe;
mod platform;
mod secrets;
mod settings;
mod tray;

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

pub struct Shared {
    pub settings: Mutex<Settings>,
    pub gate: Arc<PollGate>,
}

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
    }
}

#[tauri::command]
fn save_settings(app: AppHandle, shared: State<Shared>, settings: Settings) {
    let (placement_changed, autostart_changed, enabled_changed) = {
        let mut current = shared.settings.lock().unwrap();
        let placement_changed =
            current.screen != settings.screen || current.position != settings.position;
        let autostart_changed = current.autostart != settings.autostart;
        let enabled_changed = current.enabled != settings.enabled;
        *current = settings.clone();
        (placement_changed, autostart_changed, enabled_changed)
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
    }
    if enabled_changed {
        apply_enabled(&app, &shared, settings.enabled);
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
    // The wake strip must always take the mouse, and a resize invalidates the flag.
    island::refresh_click_through(&app, &shared.gate);
    shared.gate.set_active(!collapsed);
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
}

#[tauri::command]
fn open_url(url: String) {
    if !(url.starts_with("http://") || url.starts_with("https://")) {
        return;
    }
    platform::open_url(&url);
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
async fn mattermost_send_reply(conversation_id: String, body: String) -> Result<(), String> {
    mattermost::send_reply(conversation_id, body).await
}

#[tauri::command]
async fn clickmassa_send_reply(conversation_id: String, body: String) -> Result<(), String> {
    clickmassa::send_reply(conversation_id, body).await
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

/// Opens the configured n8n instance — the URL lives in the Credential Manager.
#[tauri::command]
fn open_n8n() {
    if let Some(url) = secrets::get("n8n-url") {
        open_url(url);
    }
}

/// Refresh buttons in the integration cards.
#[tauri::command]
async fn refresh_integration(app: AppHandle, id: String) {
    integrations::poll_once(app, &id).await;
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
        .manage(Shared {
            settings: Mutex::new(loaded.clone()),
            gate: gate.clone(),
        })
        .manage(Pending::default())
        .manage(Chat::default())
        .invoke_handler(tauri::generate_handler![
            boot,
            save_settings,
            set_collapsed,
            set_island_rect,
            focus_window,
            reposition,
            open_url,
            open_in_vscode,
            quit_app,
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
            secret_present,
            secret_set,
            secret_clear,
            refresh_integration,
            open_n8n,
            open_settings_window,
            set_enabled,
            mattermost_send_reply,
            clickmassa_send_reply,
        ])
        .setup(move |app| {
            let handle = app.handle().clone();
            // Built with the state already in it, so the first menu someone
            // opens after launching off does not say "Turn Coucou off".
            tray::build(&handle, loaded.enabled)?;
            integrations::apply_master(loaded.enabled);
            // Before the island: see create_settings_window.
            create_settings_window(&handle);

            if let Some(win) = island::window(&handle) {
                // Unconditional: on Linux this has to run before the first map,
                // whether or not the window is about to be shown.
                platform::make_non_activating(&win);
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
            // Nothing drawn yet, so nothing takes the mouse until the page
            // reports the island's shape.
            if !platform::CURSOR_POLL {
                island::refresh_click_through(&handle, &gate);
            }
            gate.set_active(loaded.enabled);
            island::spawn_cursor_poll(handle.clone(), gate.clone());

            log::line(format!("--- Coucou {} started ---", env!("CARGO_PKG_VERSION")));
            hooks::ensure_hook_exe(&handle);
            pipe::start(handle.clone());
            integrations::start(handle.clone());
            // Both supervisors are safe to start here: neither opens a socket,
            // nor reaches the network at all, until its pill is on and the
            // credentials are stored. They watch for both on their own.
            mattermost::start(handle.clone());
            clickmassa::start(handle.clone());
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running Coucou");
}
