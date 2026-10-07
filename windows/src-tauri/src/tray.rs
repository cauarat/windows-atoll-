// Notification-area icon: Open, Settings, the master switch, Quit.
//
// The switch replaces the old Pause rather than sitting beside it. Pause stopped
// the pollers but left the wake strip live, so sweeping the top of the screen
// brought the island straight back, and it was never written to disk — a restart
// undid it. Two half-working off switches in one menu is the problem, not the
// fix.
//
// It also never routes through the webview. That is the point: when Coucou is
// off the island window is hidden, so a menu item that emits an event to it
// would have nothing listening and no way back on.

use tauri::image::Image;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter};

use crate::island::WINDOW_LABEL;

const TRAY_ID: &str = "coucou";

/// "Turn Coucou off" says what the click does, which needs no checkmark
/// literacy and survives a theme where a tick is easy to miss.
fn menu(app: &AppHandle, enabled: bool) -> tauri::Result<Menu<tauri::Wry>> {
    // Opening the island while it is hidden would do nothing, so the item says
    // so by being greyed rather than by failing silently.
    let open = MenuItem::with_id(app, "open", "Open Coucou", enabled, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "Settings…", true, None::<&str>)?;
    let toggle = MenuItem::with_id(
        app,
        "toggle",
        if enabled { "Turn Coucou off" } else { "Turn Coucou on" },
        true,
        None::<&str>,
    )?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let sep1 = PredefinedMenuItem::separator(app)?;
    let sep2 = PredefinedMenuItem::separator(app)?;

    Menu::with_items(app, &[&open, &sep1, &settings, &toggle, &sep2, &quit])
}

/// Dimmed while off.
///
/// With the island hidden the tray icon is the only thing left on screen. If it
/// looked the same either way, "is it even running?" would be the first thing
/// anyone asked. Derived from the icon already shipped, so there is no second
/// asset to keep in step.
fn icon(app: &AppHandle, enabled: bool) -> Option<Image<'static>> {
    // Owned in both branches: the icon the app hands back borrows from it, and
    // the tray wants something that outlives this call.
    let base = app.default_window_icon()?;
    let mut rgba = base.rgba().to_vec();
    if !enabled {
        for pixel in rgba.chunks_exact_mut(4) {
            pixel[3] = (f32::from(pixel[3]) * 0.4) as u8;
        }
    }
    Some(Image::new_owned(rgba, base.width(), base.height()))
}

pub fn build(app: &AppHandle, enabled: bool) -> tauri::Result<()> {
    let mut builder = TrayIconBuilder::with_id(TRAY_ID)
        .tooltip(if enabled { "Coucou" } else { "Coucou — off" })
        .menu(&menu(app, enabled)?)
        .on_menu_event(|app: &AppHandle, event| match event.id.as_ref() {
            "quit" => app.exit(0),
            "settings" => crate::show_settings_window(app),
            // Straight into Rust, never via the island: see the note at the top.
            "toggle" => crate::toggle_enabled(app),
            id => {
                let _ = app.emit_to(WINDOW_LABEL, "tray", id.to_string());
            }
        });

    if let Some(image) = icon(app, enabled) {
        builder = builder.icon(image);
    }

    builder.build(app)?;
    Ok(())
}

/// Repaints the menu, tooltip and icon after the switch moves.
///
/// Rebuilding four items costs less than keeping `MenuItem` handles in managed
/// state, and avoids the lifetime question entirely.
pub fn refresh(app: &AppHandle, enabled: bool) {
    let Some(tray) = app.tray_by_id(TRAY_ID) else { return };
    if let Ok(menu) = menu(app, enabled) {
        let _ = tray.set_menu(Some(menu));
    }
    let _ = tray.set_tooltip(Some(if enabled { "Coucou" } else { "Coucou — off" }));
    // Some libappindicator builds on Linux ignore a runtime icon change; the
    // menu text and tooltip still carry the state, so nothing is lost.
    if let Some(image) = icon(app, enabled) {
        let _ = tray.set_icon(Some(image));
    }
}
