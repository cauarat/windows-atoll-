// The global shortcut that closes the island.
//
// Registered here rather than from the page: the island is a non-activating
// window, so a keydown listener in it never hears a key while another app has
// the keyboard, which is the whole time a message is on screen. A registration
// made from JavaScript would also need a capability and would die with the
// window that made it. Rust holds it for the life of the app and sends the
// island an event, the way the tray does.
//
// The Mac does the same with Carbon's RegisterEventHotKey (CloseHotKey.swift).

use std::sync::Mutex;

use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

use crate::island::WINDOW_LABEL;
use crate::settings::Settings;

/// Why the last registration failed, for the settings window to say so. None
/// when it took, or when nothing was asked for.
#[derive(Default)]
pub struct ShortcutStatus(Mutex<Option<String>>);

/// Drops whatever is registered and registers the shortcut `settings` asks for.
///
/// Off with the master switch too: an app that is off has no island to close,
/// and has no business holding keys other apps could use.
pub fn apply(app: &AppHandle, settings: &Settings) {
    let result = register(app, settings);
    if let Err(err) = &result {
        eprintln!("[coucou] close shortcut: {err}");
    }
    if let Some(status) = app.try_state::<ShortcutStatus>() {
        *status.0.lock().unwrap() = result.err();
    }
}

fn register(app: &AppHandle, settings: &Settings) -> Result<(), String> {
    let shortcuts = app.global_shortcut();
    shortcuts.unregister_all().map_err(|e| e.to_string())?;
    if !settings.enabled || !settings.close_shortcut_enabled {
        return Ok(());
    }
    let shortcut: Shortcut = settings
        .close_shortcut
        .parse()
        .map_err(|e| format!("{e}"))?;
    shortcuts
        .on_shortcut(shortcut, |app, _shortcut, event| {
            if event.state() == ShortcutState::Pressed {
                let _ = app.emit_to(WINDOW_LABEL, "close-shortcut", ());
            }
        })
        .map_err(|e| e.to_string())
}

/// The reason the close shortcut is not registered, if it was asked for and the
/// system refused it — taken by another app, or (on Wayland) not something an
/// app may register at all.
#[tauri::command]
pub fn close_shortcut_error(status: tauri::State<ShortcutStatus>) -> Option<String> {
    status.0.lock().unwrap().clone()
}
