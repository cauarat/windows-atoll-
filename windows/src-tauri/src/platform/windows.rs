// Windows: Win32 for the island window and the cursor, %APPDATA% for files.

use std::cell::RefCell;
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};

use tauri::{AppHandle, Manager, WebviewWindow};

use ::windows::core::{BOOL, PCWSTR, PWSTR};
use ::windows::Win32::Foundation::{CloseHandle, HANDLE, HLOCAL, HWND, LPARAM, LocalFree, POINT};
use ::windows::Win32::Security::Authorization::ConvertSidToStringSidW;
use ::windows::Win32::Security::{GetTokenInformation, TokenUser, TOKEN_QUERY, TOKEN_USER};
use ::windows::Win32::System::Ole::RevokeDragDrop;
use ::windows::Win32::System::Recovery::{
    RegisterApplicationRestart, REGISTER_APPLICATION_RESTART_FLAGS,
};
use ::windows::Win32::System::SystemInformation::GetLocalTime;
use ::windows::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};
use ::windows::Win32::UI::Input::KeyboardAndMouse::{GetAsyncKeyState, VK_LBUTTON};
use ::windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CLSCTX_ALL, COINIT_APARTMENTTHREADED};
use ::windows::Win32::UI::Shell::{IVirtualDesktopManager, VirtualDesktopManager};
use ::windows::Win32::UI::WindowsAndMessaging::{
    EnumChildWindows, GetClassNameW, GetCursorPos, GetForegroundWindow, GetWindowLongPtrW,
    SetWindowLongPtrW, SetWindowPos, GWL_EXSTYLE, HWND_TOPMOST, SWP_NOACTIVATE, SWP_NOMOVE,
    SWP_NOSIZE, WS_EX_TOOLWINDOW,
};

use super::LocalTime;
use crate::island::{Align, Edge, WINDOW_LABEL};

/// File name of the Claude Code relay.
pub const HOOK_EXE: &str = "coucou-hook.exe";

/// Environment variable holding the home directory.
pub const HOME_VAR: &str = "USERPROFILE";

/// Keeps spawned helpers from flashing a console window.
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

// ── Files ─────────────────────────────────────────────────────────────────────

/// %APPDATA%\Coucou — preferences.
pub fn config_dir() -> PathBuf {
    let base = std::env::var_os("APPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("Coucou")
}

/// %LOCALAPPDATA%\Coucou — where coucou-hook.exe, the inbox and the log live.
pub fn local_dir() -> PathBuf {
    let base = std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("Coucou")
}

/// %APPDATA% and %LOCALAPPDATA% are already private to the user.
pub fn ensure_private_dir(dir: &std::path::Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dir)
}

/// Nothing to set up before the webview starts.
pub fn prepare_environment() {}

pub fn local_time() -> LocalTime {
    let t = unsafe { GetLocalTime() };
    LocalTime {
        year: t.wYear.into(),
        month: t.wMonth.into(),
        day: t.wDay.into(),
        hour: t.wHour.into(),
        minute: t.wMinute.into(),
        second: t.wSecond.into(),
    }
}

// ── Recovery ──────────────────────────────────────────────────────────────────

/// Asks Windows to start Coucou again if this process crashes or hangs.
///
/// Worth more than a watchdog of our own. The OS covers both a crash and a hang;
/// it refuses to relaunch a copy that ran less than a minute, so a crash loop
/// stops itself without a counter to tune; and it waits until this process is
/// really gone, which is what keeps `tauri_plugin_single_instance` from turning
/// the replacement away at the door.
///
/// A deliberate quit is never a crash, so the tray's Quit and the updater's
/// restart are unaffected and there is nothing to unregister.
pub fn register_restart(marker: &str) {
    // Windows prepends the executable itself, so this is only the marker that
    // tells the next copy why it is running.
    let wide: Vec<u16> = marker.encode_utf16().chain(std::iter::once(0)).collect();
    // No RESTART_NO_* flags: we want both the crash and the hang.
    let flags = REGISTER_APPLICATION_RESTART_FLAGS(0);
    if let Err(err) = unsafe { RegisterApplicationRestart(PCWSTR(wide.as_ptr()), flags) } {
        crate::log::line(format!("restart registration failed — {err}"));
    }
}

// ── Processes ─────────────────────────────────────────────────────────────────

/// Spawned helpers must never flash a console window.
pub fn no_console(cmd: &mut Command) -> &mut Command {
    cmd.creation_flags(CREATE_NO_WINDOW)
}

pub fn open_url(url: &str) {
    let _ = no_console(Command::new("rundll32.exe").args(["url.dll,FileProtocolHandler", url]))
        .spawn();
}

pub fn reveal_folder(path: &str) {
    let _ = Command::new("explorer").arg(path).spawn();
}

/// Launch an application by path. Spawned directly rather than through a
/// shell, so a folder name with `&` or `%` in it stays a folder name.
pub fn open_application(path: &std::path::Path) -> bool {
    let mut cmd = Command::new(path);
    no_console(&mut cmd).spawn().is_ok()
}

/// Our own `where`: walks %PATH% against %PATHEXT%, no shell involved.
/// Rust quotes arguments correctly for `.cmd`/`.bat` targets since 1.77, so
/// spawning `code.cmd` directly is safe.
pub fn find_on_path(stem: &str) -> Option<PathBuf> {
    let exts = std::env::var("PATHEXT").unwrap_or_else(|_| ".COM;.EXE;.BAT;.CMD".into());
    let dirs = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&dirs) {
        for ext in exts.split(';').filter(|e| !e.is_empty()) {
            let candidate = dir.join(format!("{stem}{}", ext.to_lowercase()));
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }
    None
}

// ── Who we are ────────────────────────────────────────────────────────────────
//
// Named pipes share one machine-wide namespace, so the SID in the name is what
// keeps two accounts on the same machine from ever meeting on `coucou-*`.
// coucou-hook computes the same string (hook/src/win.rs) and additionally checks
// that the process serving the pipe really is us.

/// The SID of the account this process runs as, as `S-1-5-21-…`.
pub fn current_user_sid() -> Option<String> {
    unsafe {
        let mut token = HANDLE::default();
        OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token).ok()?;

        // First call sizes the buffer, second fills it.
        let mut needed = 0u32;
        let _ = GetTokenInformation(token, TokenUser, None, 0, &mut needed);
        if needed == 0 {
            let _ = CloseHandle(token);
            return None;
        }
        let mut buf = vec![0u8; needed as usize];
        let ok = GetTokenInformation(
            token,
            TokenUser,
            Some(buf.as_mut_ptr().cast()),
            needed,
            &mut needed,
        )
        .is_ok();
        let _ = CloseHandle(token);
        if !ok {
            return None;
        }

        let user = &*(buf.as_ptr() as *const TOKEN_USER);
        let mut text = PWSTR::null();
        ConvertSidToStringSidW(user.User.Sid, &mut text).ok()?;
        let sid = text.to_string().ok();
        let _ = LocalFree(Some(HLOCAL(text.0 as *mut _)));
        sid
    }
}

// ── Cursor ────────────────────────────────────────────────────────────────────

/// The 60 Hz poll reads the cursor and flips click-through from it.
pub const CURSOR_POLL: bool = true;

/// Cursor position in physical screen pixels.
pub fn cursor_physical() -> Option<(f64, f64)> {
    let mut p = POINT::default();
    unsafe { GetCursorPos(&mut p).ok()? };
    Some((p.x as f64, p.y as f64))
}

/// True while the left mouse button is held — the only signal we get that a
/// drag might be in flight before it reaches the window.
pub fn left_button_down() -> bool {
    unsafe { (GetAsyncKeyState(VK_LBUTTON.0 as i32) as u16 & 0x8000) != 0 }
}

// ── Island window ─────────────────────────────────────────────────────────────

fn hwnd_of(win: &WebviewWindow) -> Option<HWND> {
    let raw = win.hwnd().ok()?.0 as isize;
    if raw == 0 {
        return None;
    }
    Some(HWND(raw as *mut _))
}

/// Lets dropped files reach the app again.
///
/// wry installs its drop target by walking the webview's child windows **once**,
/// when the webview is created. WebView2 creates `Chrome_RenderWidgetHostHWND`
/// later and registers its own target on it; being the innermost window, that one
/// wins, and since the page has no HTML5 drop handler it refuses everything — the
/// "no drop" cursor, with nothing reaching Tauri. Revoking it makes OLE fall
/// through to the target wry registered on the parent widget, which is the one
/// that feeds Tauri's drag events.
///
/// Cheap and idempotent, so it is simply re-run whenever a drag might be starting.
pub fn unblock_webview_drops(app: &AppHandle) {
    for label in [WINDOW_LABEL, "settings"] {
        let Some(win) = app.get_webview_window(label) else { continue };
        let Some(hwnd) = hwnd_of(&win) else { continue };
        unsafe {
            let _ = EnumChildWindows(Some(hwnd), Some(revoke_render_widget), LPARAM(0));
        }
    }
}

unsafe extern "system" fn revoke_render_widget(hwnd: HWND, _: LPARAM) -> BOOL {
    let mut name = [0u16; 64];
    let len = unsafe { GetClassNameW(hwnd, &mut name) };
    if len > 0 {
        let class = String::from_utf16_lossy(&name[..len as usize]);
        if class == "Chrome_RenderWidgetHostHWND" {
            let _ = unsafe { RevokeDragDrop(hwnd) };
        }
    }
    true.into()
}

/// Keeps the island out of Alt-Tab and out of "Show desktop".
///
/// `WS_EX_NOACTIVATE` is deliberately not set here, though it used to be. tao
/// keeps its own copy of the window flags and rewrites the *whole* `GWL_EXSTYLE`
/// from them on every `apply_diff` (tao window_state.rs:410-413) — which the
/// cursor poll triggers on each click-through toggle, so within a frame of the
/// first one. A bit set behind tao's back lasts seconds. It is asked for through
/// tao instead, as `"focusable": false` in tauri.conf.json, which is where
/// `to_window_styles` puts the same bit back every time (window_state.rs:292-294).
/// The Linux island has always been declared that way; Windows was the one
/// setting it by hand and watching it disappear.
///
/// `WS_EX_TOOLWINDOW` has no such route: tao never sets it for an app window —
/// `skipTaskbar` is `ITaskbarList::DeleteTab`, which is the taskbar and not
/// Alt-Tab — so this one stays ours, and `reassert_above` puts it back after tao
/// has wiped it.
pub fn make_non_activating(win: &WebviewWindow) {
    reassert_above(win);
}

/// Temporarily allow activation so a text field inside the island can be typed in.
///
/// Through tao rather than `SetWindowLongPtrW`, because tao owns
/// `WS_EX_NOACTIVATE` now (see `make_non_activating`). Clearing the bit by hand
/// would be the worse half of that bargain: tao would put it straight back on the
/// next click-through toggle, and a reply box that will not take a keystroke is
/// harder to recognise than one that never opened.
pub fn set_activating(win: &WebviewWindow, activating: bool) {
    let _ = win.set_focusable(activating);
}

// ── Keeping the island where it belongs ───────────────────────────────────────
//
// macOS gives a panel a window *level*: set once, it stays above everything, on
// every Space, over full-screen apps, for as long as the window lives
// (IslandWindowController.swift:347-348). Linux has the layer-shell OVERLAY,
// which is the same promise. Windows has neither. `HWND_TOPMOST` is a band and
// not a rank — the last topmost window to be activated sits in front of the rest
// of them — and a window belongs to the virtual desktop it was created on.
//
// So on Windows the island has to be put back, and there are exactly two ways it
// gets moved: something else took the front of the band, or the user switched
// desktop. The cursor poll's watchdog tick answers both.

/// One line per run, not one per tick.
fn warn_once(message: String) {
    static SAID: AtomicBool = AtomicBool::new(false);
    if !SAID.swap(true, Ordering::Relaxed) {
        crate::log::line(message);
    }
}

/// The window the user is working in, as a bare handle value.
///
/// Only ever compared against the previous tick's. A change is the one cheap
/// signal that the Z-order may have been rearranged; re-asserting on every tick
/// regardless would shuffle the topmost band twice a second for nothing.
pub fn foreground_window() -> isize {
    unsafe { GetForegroundWindow().0 as isize }
}

/// Puts the island back on top of the topmost band, and back out of Alt-Tab.
///
/// `win.set_always_on_top(true)` cannot do the first half. tao diffs the request
/// against its cached flags and returns before touching the window when the bit
/// is already set (tao window_state.rs:313-320) — so it is a no-op in precisely
/// the case that matters, which is the island still believing it is topmost while
/// sitting behind something. This is the raw `SetWindowPos` tao declines to make.
pub fn reassert_above(win: &WebviewWindow) {
    let Some(hwnd) = hwnd_of(win) else { return };
    unsafe {
        let ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        let want = ex | WS_EX_TOOLWINDOW.0 as isize;
        if ex != want {
            SetWindowLongPtrW(hwnd, GWL_EXSTYLE, want);
        }
        let _ = SetWindowPos(
            hwnd,
            Some(HWND_TOPMOST),
            0,
            0,
            0,
            0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
        );
    }
}

thread_local! {
    /// The desktop manager, created on first use by whichever thread polls.
    ///
    /// Three states, because "could not create it" has to be remembered: the
    /// outer `None` is "not tried yet", `Some(None)` is "tried, unavailable —
    /// stop asking", and `Some(Some(_))` is ready. COM objects are not `Send`,
    /// and the watchdog is the only caller, so a thread-local is the whole story.
    static DESKTOPS: RefCell<Option<Option<IVirtualDesktopManager>>> =
        const { RefCell::new(None) };
}

/// Brings the island to the virtual desktop the user is looking at.
///
/// A window belongs to the desktop it was created on, so switching desktops
/// leaves the island behind on the old one — which on a Mac `.canJoinAllSpaces`
/// answers, and on Linux never comes up because a layer surface belongs to an
/// output rather than to a workspace.
///
/// Following rather than pinning. Pinning is `IVirtualDesktopPinnedApps`, which
/// Microsoft does not document and whose interface id moves between Windows
/// builds; `IVirtualDesktopManager` is documented and has not moved. What the
/// user sees is the same either way: Mochi is on the desktop they are on.
pub fn follow_virtual_desktop(win: &WebviewWindow) {
    let Some(hwnd) = hwnd_of(win) else { return };
    DESKTOPS.with(|cell| {
        let mut slot = cell.borrow_mut();
        if slot.is_none() {
            *slot = Some(unsafe {
                // Already-initialised is not a failure: this thread may well have
                // been given COM by something else first.
                let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
                let created: ::windows::core::Result<IVirtualDesktopManager> =
                    CoCreateInstance(&VirtualDesktopManager, None, CLSCTX_ALL);
                match created {
                    Ok(desktops) => Some(desktops),
                    Err(err) => {
                        crate::log::line(format!("virtual desktops unavailable — {err}"));
                        None
                    }
                }
            });
        }
        let Some(Some(desktops)) = slot.as_ref() else { return };
        unsafe {
            // An error here means "cannot tell", which is not the same as "is on
            // another desktop" — moving the window on a guess would be worse than
            // leaving it alone.
            let Ok(here) = desktops.IsWindowOnCurrentVirtualDesktop(hwnd) else { return };
            if here.as_bool() {
                return;
            }
            let Ok(id) = desktops.GetWindowDesktopId(GetForegroundWindow()) else { return };
            if let Err(err) = desktops.MoveWindowToDesktop(hwnd, &id) {
                // Documented to refuse some windows, and a tool window may be one
                // of them. Said once, because the alternative is twice a second
                // for as long as Coucou runs.
                warn_once(format!("could not follow the virtual desktop — {err}"));
            }
        }
    });
}

/// Click-through here is the poll's WS_EX_TRANSPARENT toggle, not a region.
pub fn set_input_region(_win: &WebviewWindow, _rect: Option<(f64, f64, f64, f64)>) {}

/// Layer-shell anchoring is a Wayland idea. Windows places the island by
/// coordinates, which `island::apply_geometry` has already worked out.
pub fn set_layer_anchor(_win: &WebviewWindow, _edge: Edge, _align: Align) {}

/// Same, for an island that was dropped somewhere of its own.
pub fn set_layer_free(_win: &WebviewWindow, _x: f64, _y: f64) {}
