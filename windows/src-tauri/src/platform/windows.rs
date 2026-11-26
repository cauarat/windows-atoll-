// Windows: Win32 for the island window and the cursor, %APPDATA% for files.

use std::cell::RefCell;
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::process::Command;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

use tauri::{AppHandle, Manager, Webview, WebviewWindow, Window};

use ::webview2_com::Microsoft::Web::WebView2::Win32::{
    ICoreWebView2, ICoreWebView2Controller, ICoreWebView2NavigationCompletedEventArgs2,
    ICoreWebView2Profile2, ICoreWebView2Settings3, ICoreWebView2Settings6, ICoreWebView2_13,
    ICoreWebView2_3,
    ICoreWebView2_8, COREWEBVIEW2_KEY_EVENT_KIND, COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN,
    COREWEBVIEW2_PHYSICAL_KEY_STATUS, COREWEBVIEW2_PREFERRED_COLOR_SCHEME_DARK,
    COREWEBVIEW2_SCRIPT_DIALOG_KIND, COREWEBVIEW2_SCRIPT_DIALOG_KIND_BEFOREUNLOAD,
    COREWEBVIEW2_WEB_ERROR_STATUS,
};
use ::webview2_com::{
    take_pwstr, AcceleratorKeyPressedEventHandler, CallDevToolsProtocolMethodCompletedHandler,
    ClearBrowsingDataCompletedHandler,
    ContainsFullScreenElementChangedEventHandler, ContentLoadingEventHandler,
    DocumentTitleChangedEventHandler, ExecuteScriptCompletedHandler, HistoryChangedEventHandler,
    NavigationCompletedEventHandler, NavigationStartingEventHandler,
    ScriptDialogOpeningEventHandler, SourceChangedEventHandler, TrySuspendCompletedHandler,
};
// WebView2's own bindings are built on windows 0.62; Coucou's code on 0.61.
// The two never mix: 0.62's types only ever touch WebView2, and a window
// handle crosses over as its raw pointer.
use ::windows_core::Interface as _;
use ::windows::core::{BOOL, PCWSTR};
use ::windows::Win32::Foundation::{HWND, LPARAM, POINT};
use ::windows::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_CLOAKED};
use ::windows::Win32::Graphics::Gdi::{CreateRoundRectRgn, DeleteObject, SetWindowRgn};
use ::windows::Win32::System::DataExchange::GetClipboardSequenceNumber;
use ::windows::Win32::System::Ole::RevokeDragDrop;
use ::windows::Win32::System::Recovery::{
    RegisterApplicationRestart, REGISTER_APPLICATION_RESTART_FLAGS,
};
use ::windows::Win32::System::SystemInformation::GetLocalTime;
use ::windows::Win32::UI::Input::KeyboardAndMouse::{GetAsyncKeyState, VK_LBUTTON};
use ::windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CLSCTX_ALL, COINIT_APARTMENTTHREADED};
use ::windows::Win32::UI::Shell::{IVirtualDesktopManager, VirtualDesktopManager};
use ::windows::Win32::UI::WindowsAndMessaging::{
    EnumChildWindows, GetClassNameW, GetCursorPos, GetForegroundWindow, GetGUIThreadInfo,
    GetWindowLongPtrW, GetWindowThreadProcessId, IsChild, IsIconic, IsWindow, IsWindowVisible,
    SetForegroundWindow, SetWindowLongPtrW, SetWindowPos, GUITHREADINFO, GWL_EXSTYLE,
    HWND_TOPMOST, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOSIZE, WS_EX_TOOLWINDOW, WS_EX_TRANSPARENT,
};

use super::LocalTime;
use crate::island::{Align, Edge, WINDOW_LABEL};
use crate::page_model::{self, Signal};

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

/// %LOCALAPPDATA%\Coucou — where the inbox and the log live.
///
/// Builds before the coding agents went also staged coucou-hook.exe, Claude
/// Code's relay, in `bin\` here. Nothing writes or removes it any more: a
/// settings.json may still name it, and with nobody listening it exits at once
/// and says nothing (see nsis/hooks.nsh).
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
fn no_console(cmd: &mut Command) -> &mut Command {
    cmd.creation_flags(CREATE_NO_WINDOW)
}

pub fn open_url(url: &str) {
    let _ = no_console(Command::new("rundll32.exe").args(["url.dll,FileProtocolHandler", url]))
        .spawn();
}

/// Launch an application by path. Spawned directly rather than through a
/// shell, so a folder name with `&` or `%` in it stays a folder name.
pub fn open_application(path: &std::path::Path) -> bool {
    let mut cmd = Command::new(path);
    no_console(&mut cmd).spawn().is_ok()
}

// ── Who we are ────────────────────────────────────────────────────────────────

/// The name on the account, raw, for a greeting with nothing typed under
/// Settings › Your name.
///
/// `USERNAME` is the sign-in name rather than a display name, which most of the
/// time is a handle like "cauat" — and the front end throws a handle away
/// (`firstNameFromFullName` in core/greetingName.ts), so this only ever greets
/// someone whose sign-in name already reads as a name.
pub fn account_name() -> Option<String> {
    std::env::var("USERNAME").ok().filter(|name| !name.trim().is_empty())
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

fn hwnd_of(win: &Window) -> Option<HWND> {
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
/// The island's own webview only. ChatGPT and the site live in the same window
/// now, and their WebView2 targets are exactly what must stay: a file dropped on
/// ChatGPT is ChatGPT's to attach, as on the Mac, where the drop view stands down
/// while the page is up.
///
/// Cheap and idempotent, so it is simply re-run whenever a drag might be starting.
pub fn unblock_webview_drops(app: &AppHandle) {
    for label in [WINDOW_LABEL, "settings"] {
        let Some(win) = app.get_window(label) else { continue };
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
        if class == "Chrome_RenderWidgetHostHWND" && !inside_a_page(hwnd) {
            let _ = unsafe { RevokeDragDrop(hwnd) };
        }
    }
    true.into()
}

/// WebView2 exposes `getUserMedia` already; only its permission prompt needed
/// answering, and `Builder::on_permission_request` in `lib.rs` does that. The
/// Linux twin has real work to do — see `platform/linux.rs`.
pub fn enable_media_stream(_webview: &Webview) {}

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
pub fn make_non_activating(win: &Window) {
    reassert_above(win);
}

/// Temporarily allow activation so a text field inside the island can be typed in.
///
/// Through tao rather than `SetWindowLongPtrW`, because tao owns
/// `WS_EX_NOACTIVATE` now (see `make_non_activating`). Clearing the bit by hand
/// would be the worse half of that bargain: tao would put it straight back on the
/// next click-through toggle, and a reply box that will not take a keystroke is
/// harder to recognise than one that never opened.
pub fn set_activating(win: &Window, activating: bool) {
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

/// The number Windows raises each time anything at all is put on the clipboard.
///
/// Reading it opens nothing, so the clipboard poll asks it first and opens the
/// clipboard only when it has moved. Before, every tick opened it and read it
/// whole — with a screenshot on it, a full image decoded twice a second, all
/// day, and the clipboard held open under every other program that wanted it.
/// `None` where this session cannot see the clipboard at all (Windows answers
/// 0 then): the poll goes on reading every tick, as it always did.
pub fn clipboard_sequence() -> Option<u32> {
    let n = unsafe { GetClipboardSequenceNumber() };
    (n != 0).then_some(n)
}

/// Puts the island back on top of the topmost band, and back out of Alt-Tab.
///
/// `win.set_always_on_top(true)` cannot do the first half. tao diffs the request
/// against its cached flags and returns before touching the window when the bit
/// is already set (tao window_state.rs:313-320) — so it is a no-op in precisely
/// the case that matters, which is the island still believing it is topmost while
/// sitting behind something. This is the raw `SetWindowPos` tao declines to make.
pub fn reassert_above(win: &Window) {
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

/// Whether the island lets the mouse through right now, read off the window.
///
/// `WS_EX_TRANSPARENT` is what tao's `set_ignore_cursor_events` sets. The cursor
/// poll keeps a mirror of it so it only calls the OS on a change, and a mirror is
/// only what was last pushed: two threads push, and the main thread applies
/// their requests in its own order. The resting tick asks the window instead,
/// because a resting bar left click-through is an island nobody can reach.
pub fn is_click_through(win: &Window) -> Option<bool> {
    let hwnd = hwnd_of(win)?;
    let ex = unsafe { GetWindowLongPtrW(hwnd, GWL_EXSTYLE) };
    Some((ex & WS_EX_TRANSPARENT.0 as isize) != 0)
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
pub fn follow_virtual_desktop(win: &Window) {
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
pub fn set_input_region(_win: &Window, _rect: Option<(f64, f64, f64, f64)>) {}

/// Layer-shell anchoring is a Wayland idea. Windows places the island by
/// coordinates, which `island::apply_geometry` has already worked out.
pub fn set_layer_anchor(_win: &Window, _edge: Edge, _align: Align) {}

/// Same, for an island that was dropped somewhere of its own.
pub fn set_layer_free(_win: &Window, _x: f64, _y: f64) {}

/// Whether the island is the window the keyboard goes to right now.
pub fn is_foreground(win: &Window) -> bool {
    hwnd_of(win).is_some_and(|hwnd| unsafe { GetForegroundWindow() } == hwnd)
}

/// Whether the keyboard may go back from the island to `window` (a
/// `foreground_window` handle). It must still exist and be on screen on this
/// desktop:
/// - not hidden: Coucou's own windows wait hidden, and a hidden window holding
///   the foreground takes the keyboard and the island's clicks;
/// - not minimised;
/// - not cloaked, as a window on another virtual desktop is, or a Start menu
///   that has folded away. Giving the foreground to a window on another
///   desktop would switch the user back to that desktop.
///
/// And it is neither the island nor the taskbar, which the user clicks on the
/// way somewhere but never works in.
pub fn takes_foreground_back(win: &Window, window: isize) -> bool {
    let Some(island) = hwnd_of(win) else { return false };
    let target = HWND(window as *mut _);
    if window == 0 || target == island {
        return false;
    }
    unsafe {
        if !IsWindow(Some(target)).as_bool()
            || !IsWindowVisible(target).as_bool()
            || IsIconic(target).as_bool()
        {
            return false;
        }
        let mut cloaked: u32 = 0;
        let asked = DwmGetWindowAttribute(
            target,
            DWMWA_CLOAKED,
            (&mut cloaked as *mut u32).cast(),
            std::mem::size_of::<u32>() as u32,
        );
        if asked.is_ok() && cloaked != 0 {
            return false;
        }
    }
    !is_taskbar(target)
}

/// The taskbar, on the main display or another one.
fn is_taskbar(hwnd: HWND) -> bool {
    let mut name = [0u16; 64];
    let len = unsafe { GetClassNameW(hwnd, &mut name) };
    if len <= 0 {
        return false;
    }
    let class = String::from_utf16_lossy(&name[..len as usize]);
    class == "Shell_TrayWnd" || class == "Shell_SecondaryTrayWnd"
}

/// Hands the foreground from the island to `window`, a window the user was
/// in (`takes_foreground_back`). The Mac's panel gives the keyboard back the
/// same way, by resigning key. Hiding a child webview gives nothing back by
/// itself, as hiding a window would.
///
/// Only while the island holds the foreground, which is what allows a process
/// to pass it on. Returns whether the foreground went.
pub fn give_foreground(win: &Window, window: isize) -> bool {
    if !is_foreground(win) || !takes_foreground_back(win, window) {
        return false;
    }
    unsafe { SetForegroundWindow(HWND(window as *mut _)).as_bool() }
}

// ── Pages inside the island ───────────────────────────────────────────────────
//
// ChatGPT and the site are child webviews of the island's window (web.rs).
// What they need from WebView2 beyond what Tauri exposes is here: the main
// frame's navigations with their HTTP status and error, Escape, the rounded
// clip, mute, the dark scheme, the browser keys and gestures WKWebView does not
// have, and telling a webview its window moved. All of it goes through
// `with_webview`, which hands over the page's controller on the main thread.

/// The page containers — the WRY_WEBVIEW child window wry made for each page —
/// as raw handles, by the page's label. Their WebView2 drop targets are the
/// ones `unblock_webview_drops` must leave alone, and the keyboard is in a
/// page when it is in its container (`page_has_focus`).
static PAGE_CONTAINERS: Mutex<Vec<(String, isize)>> = Mutex::new(Vec::new());

/// Virtual-key code of Escape.
const KEY_ESCAPE: u32 = 0x1B;

/// What a page that went fullscreen anyway is told (`page_hooks`). Its
/// document's `exitFullscreen` is the browser's own: web.rs's NO_FULLSCREEN
/// pins it there before any of the page's script runs, where the page can
/// neither replace nor remove it.
const EXIT_FULLSCREEN: &str = "document.exitFullscreen && document.exitFullscreen()";

/// Whether `hwnd` is inside one of the pages.
fn inside_a_page(hwnd: HWND) -> bool {
    let containers = PAGE_CONTAINERS.lock().unwrap();
    containers
        .iter()
        .any(|(_, raw)| unsafe { IsChild(HWND(*raw as *mut _), hwnd) }.as_bool())
}

/// Whether the keyboard is in the page called `label` right now: the focus of
/// the island's thread is its container or a window inside it, WebView2's
/// own included. Only read — nothing here, or in what asks, answers it with a
/// focus call (web.rs `keep_hosting`).
pub fn page_has_focus(win: &Window, label: &str) -> bool {
    let Some(island) = hwnd_of(win) else { return false };
    let container = PAGE_CONTAINERS
        .lock()
        .unwrap()
        .iter()
        .find(|(page, _)| page == label)
        .map(|(_, raw)| HWND(*raw as *mut _));
    let Some(container) = container else { return false };
    unsafe {
        let thread = GetWindowThreadProcessId(island, None);
        if thread == 0 {
            return false;
        }
        let mut info = GUITHREADINFO {
            cbSize: std::mem::size_of::<GUITHREADINFO>() as u32,
            ..Default::default()
        };
        if GetGUIThreadInfo(thread, &mut info).is_err() || info.hwndFocus.is_invalid() {
            return false;
        }
        info.hwndFocus == container || IsChild(container, info.hwndFocus).as_bool()
    }
}

/// The window WebView2 draws a page into: the WRY_WEBVIEW child wry created
/// for it, which `CreateCoreWebView2Controller` was handed as its parent.
fn container(controller: &ICoreWebView2Controller) -> Option<HWND> {
    let mut raw: *mut core::ffi::c_void = std::ptr::null_mut();
    // WebView2's HWND is windows 0.62's: the same pointer, so it is read as one.
    unsafe { controller.ParentWindow((&mut raw as *mut *mut core::ffi::c_void).cast()) }.ok()?;
    (!raw.is_null()).then_some(HWND(raw))
}

fn core_of(controller: &ICoreWebView2Controller) -> Option<ICoreWebView2> {
    unsafe { controller.CoreWebView2() }.ok()
}

/// Remembers a page's container, so file drops onto the page stay the page's
/// and the host can tell whether the keyboard is in it.
pub fn page_register(page: &Webview) {
    let label = page.label().to_string();
    let _ = page.with_webview(move |webview| {
        if let Some(hwnd) = container(&webview.controller()) {
            let mut containers = PAGE_CONTAINERS.lock().unwrap();
            // A page built again after it was closed (web.rs `release`)
            // replaces the container it had.
            containers.retain(|(page, _)| *page != label);
            containers.push((label, hwnd.0 as isize));
        }
    });
}

/// A page's webview was closed: its container is gone with it.
pub fn page_forget(label: &str) {
    PAGE_CONTAINERS.lock().unwrap().retain(|(page, _)| page != label);
}

/// Reports what a page's webview does, as `Signal`s, and keeps it from doing
/// what a WKWebView in the Mac's island cannot.
///
/// Main frame only: WebView2's NavigationStarting, ContentLoading and
/// NavigationCompleted are the top document's, the Mac's
/// `targetFrame.isMainFrame` guard, so the Turnstile and sign-in iframes never
/// move the state.
///
/// A main-frame address Tauri cannot parse is refused here, redirects
/// included: tauri-runtime-wry lets such a navigation through without asking
/// the policy, and a document at one could crash the app through the IPC's own
/// parse of its address. Fail closed.
///
/// Escape is always an accelerator key in WebView2, so it is seen here before
/// the page sees it. It is marked handled — the Mac's key monitor swallows it —
/// and becomes the island's own Escape. A held key's repeats are not.
///
/// No script dialog is ever shown, as a WKWebView with no UI delegate shows
/// none: alert, confirm and prompt are dismissed, and "Leave site?" is
/// answered yes — the host blanking a page that guards a draft must not stop
/// on a question nobody asked for.
///
/// And no element fullscreen: web.rs keeps the API off in every frame, a
/// video's prefixed calls included. A page that gets there anyway — a video's
/// own controls do not go through the API — is asked out with the browser's
/// own `exitFullscreen`, which the page cannot replace (EXIT_FULLSCREEN), and
/// the island's window is put back whatever the page does
/// (`Signal::Fullscreen`).
pub fn page_hooks(page: &Webview, signal: impl Fn(Signal) + Send + 'static) {
    let label = page.label().to_string();
    let _ = page.with_webview(move |webview| {
        let signal: Rc<dyn Fn(Signal)> = Rc::new(signal);
        if let Err(err) = hook_page(&webview.controller(), signal) {
            crate::log::line(format!("{label} page events — {err}"));
        }
    });
}

fn hook_page(
    controller: &ICoreWebView2Controller,
    signal: Rc<dyn Fn(Signal)>,
) -> ::windows_core::Result<()> {
    let core = unsafe { controller.CoreWebView2() }?;
    // Registered for the life of the page, like wry's own handlers.
    let mut token = 0i64;

    let on = signal.clone();
    let starting = NavigationStartingEventHandler::create(Box::new(move |_, args| {
        let Some(args) = args else { return Ok(()) };
        let mut id = 0u64;
        let mut uri = ::windows_core::PWSTR::null();
        let mut by_user = ::windows_core::BOOL::default();
        let mut redirected = ::windows_core::BOOL::default();
        let mut cancelled = ::windows_core::BOOL::default();
        unsafe {
            args.NavigationId(&mut id)?;
            args.Uri(&mut uri)?;
            let _ = args.IsUserInitiated(&mut by_user);
            // Set already when the navigation policy (wry's handler, which runs
            // first) refused it.
            let _ = args.Cancel(&mut cancelled);
        }
        // A redirect is never a click: the server answering a load — one the
        // host started too, which WebView2 counts as user initiated — with a
        // 30x to a phone number must not ring it. Unknown counts as one.
        let redirected = unsafe { args.IsRedirected(&mut redirected) }.is_err() || redirected.as_bool();
        let url = take_pwstr(uri);
        let mut cancelled = cancelled.as_bool();
        // The policy was never asked about an address that does not parse.
        if !cancelled && tauri::Url::parse(&url).is_err() && unsafe { args.SetCancel(true) }.is_ok() {
            cancelled = true;
        }
        on(Signal::Started {
            id,
            url,
            by_user: by_user.as_bool() && !redirected,
            redirected,
            cancelled,
        });
        Ok(())
    }));
    unsafe { core.add_NavigationStarting(&starting, &mut token) }?;

    let on = signal.clone();
    let content = ContentLoadingEventHandler::create(Box::new(move |_, args| {
        let Some(args) = args else { return Ok(()) };
        let mut id = 0u64;
        let mut error_page = ::windows_core::BOOL::default();
        unsafe { args.NavigationId(&mut id) }?;
        // Unknown counts as WebView2's own page: never shown early.
        let error_page = unsafe { args.IsErrorPage(&mut error_page) }.is_err() || error_page.as_bool();
        on(Signal::Content { id, error_page });
        Ok(())
    }));
    unsafe { core.add_ContentLoading(&content, &mut token) }?;

    let on = signal.clone();
    let completed = NavigationCompletedEventHandler::create(Box::new(move |sender, args| {
        let Some(args) = args else { return Ok(()) };
        let mut id = 0u64;
        let mut success = ::windows_core::BOOL::default();
        let mut error = COREWEBVIEW2_WEB_ERROR_STATUS::default();
        let mut status = 0i32;
        unsafe {
            args.NavigationId(&mut id)?;
            args.IsSuccess(&mut success)?;
            let _ = args.WebErrorStatus(&mut error);
            if let Ok(args2) = args.cast::<ICoreWebView2NavigationCompletedEventArgs2>() {
                let _ = args2.HttpStatusCode(&mut status);
            }
        }
        on(Signal::Finished {
            id,
            success: success.as_bool(),
            status: status.clamp(0, u16::MAX as i32) as u16,
            error: error.0,
        });
        if let Some(core) = sender {
            report_history(&core, &*on);
        }
        Ok(())
    }));
    unsafe { core.add_NavigationCompleted(&completed, &mut token) }?;

    let on = signal.clone();
    let source = SourceChangedEventHandler::create(Box::new(move |sender, _| {
        if let Some(core) = sender {
            let mut uri = ::windows_core::PWSTR::null();
            if unsafe { core.Source(&mut uri) }.is_ok() {
                on(Signal::Source(take_pwstr(uri)));
            }
        }
        Ok(())
    }));
    unsafe { core.add_SourceChanged(&source, &mut token) }?;

    let on = signal.clone();
    let history = HistoryChangedEventHandler::create(Box::new(move |sender, _| {
        if let Some(core) = sender {
            report_history(&core, &*on);
        }
        Ok(())
    }));
    unsafe { core.add_HistoryChanged(&history, &mut token) }?;

    let on = signal.clone();
    let title = DocumentTitleChangedEventHandler::create(Box::new(move |sender, _| {
        if let Some(core) = sender {
            let mut text = ::windows_core::PWSTR::null();
            if unsafe { core.DocumentTitle(&mut text) }.is_ok() {
                on(Signal::Title(take_pwstr(text)));
            }
        }
        Ok(())
    }));
    unsafe { core.add_DocumentTitleChanged(&title, &mut token) }?;

    // With the default dialogs off (`page_settings`), one not accepted here is
    // dismissed.
    let dialogs = ScriptDialogOpeningEventHandler::create(Box::new(|_, args| {
        let Some(args) = args else { return Ok(()) };
        let mut kind = COREWEBVIEW2_SCRIPT_DIALOG_KIND::default();
        unsafe { args.Kind(&mut kind) }?;
        if kind == COREWEBVIEW2_SCRIPT_DIALOG_KIND_BEFOREUNLOAD {
            unsafe { args.Accept() }?;
        }
        Ok(())
    }));
    unsafe { core.add_ScriptDialogOpening(&dialogs, &mut token) }?;

    // tauri-runtime-wry's own handler, registered first, has already asked
    // for the island's window to go fullscreen with the page by the time this
    // runs.
    let on = signal.clone();
    let fullscreen = ContainsFullScreenElementChangedEventHandler::create(Box::new(move |sender, _| {
        let Some(core) = sender else { return Ok(()) };
        let mut contains = ::windows_core::BOOL::default();
        unsafe { core.ContainsFullScreenElement(&mut contains) }?;
        if contains.as_bool() {
            let script = ::windows_core::HSTRING::from(EXIT_FULLSCREEN);
            let done = ExecuteScriptCompletedHandler::create(Box::new(|_, _| Ok(())));
            let _ = unsafe { core.ExecuteScript(&script, &done) };
            on(Signal::Fullscreen);
        }
        Ok(())
    }));
    unsafe { core.add_ContainsFullScreenElementChanged(&fullscreen, &mut token) }?;

    let on = signal;
    let keys = AcceleratorKeyPressedEventHandler::create(Box::new(move |_, args| {
        let Some(args) = args else { return Ok(()) };
        let mut key = 0u32;
        let mut kind = COREWEBVIEW2_KEY_EVENT_KIND::default();
        let mut physical = COREWEBVIEW2_PHYSICAL_KEY_STATUS::default();
        unsafe {
            args.VirtualKey(&mut key)?;
            args.KeyEventKind(&mut kind)?;
            let _ = args.PhysicalKeyStatus(&mut physical);
        }
        if key != KEY_ESCAPE {
            return Ok(());
        }
        // Down and up both, so the page never sees half a key press.
        unsafe { args.SetHandled(true) }?;
        if kind == COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN && !physical.WasKeyDown.as_bool() {
            on(Signal::Escape);
        }
        Ok(())
    }));
    unsafe { controller.add_AcceleratorKeyPressed(&keys, &mut token) }?;
    Ok(())
}

fn report_history(core: &ICoreWebView2, on: &dyn Fn(Signal)) {
    let mut can = ::windows_core::BOOL::default();
    if unsafe { core.CanGoBack(&mut can) }.is_ok() {
        on(Signal::History { can_go_back: can.as_bool() });
    }
}

/// What WKWebView does not have, taken away: swipe navigation (WebChat sets
/// `allowsBackForwardNavigationGestures = false`; the site keeps it, as
/// NotchSiteWeb does), the browser's own keys — print, find, reload, the
/// developer tools — which a chrome-less page inside the island has no use
/// for, and WebView2's own script dialogs (`page_hooks` answers them). Zoom
/// hotkeys and pinch zoom are already off: Tauri's default.
pub fn page_settings(page: &Webview, swipe: bool, browser_keys: bool) {
    let _ = page.with_webview(move |webview| {
        let Some(core) = core_of(&webview.controller()) else { return };
        let Ok(settings) = (unsafe { core.Settings() }) else { return };
        let _ = unsafe { settings.SetAreDefaultScriptDialogsEnabled(false) };
        if let Ok(settings) = settings.cast::<ICoreWebView2Settings3>() {
            let _ = unsafe { settings.SetAreBrowserAcceleratorKeysEnabled(browser_keys) };
        }
        if let Ok(settings) = settings.cast::<ICoreWebView2Settings6>() {
            let _ = unsafe { settings.SetIsSwipeNavigationEnabled(swipe) };
        }
    });
}

/// ChatGPT in its dark theme whatever Windows is set to — the Mac's
/// `appearance = .darkAqua`. Per profile, which is why ChatGPT has a data
/// directory of its own: the shared one would turn Settings dark too.
pub fn page_force_dark(page: &Webview) {
    let _ = page.with_webview(|webview| {
        let Some(core) = core_of(&webview.controller()) else { return };
        let Ok(core) = core.cast::<ICoreWebView2_13>() else { return };
        if let Ok(profile) = unsafe { core.Profile() } {
            let _ = unsafe { profile.SetPreferredColorScheme(COREWEBVIEW2_PREFERRED_COLOR_SCHEME_DARK) };
        }
    });
}

/// Clears everything a webview's profile keeps — cookies, storage, cache —
/// and waits, up to `timeout`, for WebView2 to say it has. Tauri's own
/// `clear_all_browsing_data` only starts it, which is not enough for a window
/// about to be destroyed: whatever was left would sign the next visit back in.
/// Off the main thread only, which is where the answer arrives. False if it
/// could not be started or did not finish in time.
pub fn clear_profile_and_wait(page: &Webview, timeout: std::time::Duration) -> bool {
    let (done, finished) = std::sync::mpsc::channel::<bool>();
    let asked = page.with_webview(move |webview| {
        let started = (|| {
            let core = core_of(&webview.controller())?;
            let core = core.cast::<ICoreWebView2_13>().ok()?;
            let profile = unsafe { core.Profile() }.ok()?.cast::<ICoreWebView2Profile2>().ok()?;
            let answer = done.clone();
            let handler = ClearBrowsingDataCompletedHandler::create(Box::new(move |result| {
                let _ = answer.send(result.is_ok());
                Ok(())
            }));
            unsafe { profile.ClearBrowsingDataAll(&handler) }.ok()
        })();
        if started.is_none() {
            let _ = done.send(false);
        }
    });
    asked.is_ok() && finished.recv_timeout(timeout).unwrap_or(false)
}

/// Silences a page that is out of sight — the backstop to `page_suspend`.
/// Voice playback would otherwise go on from a closed island.
pub fn page_set_muted(page: &Webview, muted: bool) {
    let _ = page.with_webview(move |webview| {
        let Some(core) = core_of(&webview.controller()) else { return };
        if let Ok(core) = core.cast::<ICoreWebView2_8>() {
            let _ = unsafe { core.SetIsMuted(muted) };
        }
    });
}

/// Puts a page that is out of sight to sleep, its scripts and timers waiting
/// with it — beside its media, which web.rs pauses first, the Mac's
/// `setAllMediaPlaybackSuspended(true)` in WebChatController.deactivate.
/// WebView2 only suspends a webview that is hidden, and does it as best it
/// can: by the Sleeping Tabs rules it will not, for one, put a page playing
/// audio to sleep. A refusal changes nothing, and is said in a debug build.
pub fn page_suspend(page: &Webview) {
    let label = page.label().to_string();
    let _ = page.with_webview(move |webview| {
        let Some(core) = core_of(&webview.controller()) else { return };
        let Ok(core) = core.cast::<ICoreWebView2_3>() else { return };
        let asked = label.clone();
        let done = TrySuspendCompletedHandler::create(Box::new(move |result, suspended| {
            if cfg!(debug_assertions) && !suspended {
                let why = result.err().map_or("refused".to_string(), |err| err.to_string());
                crate::log::line(format!("{asked} page not suspended — {why}"));
            }
            Ok(())
        }));
        if let Err(err) = unsafe { core.TrySuspend(&done) } {
            if cfg!(debug_assertions) {
                crate::log::line(format!("{label} page not suspended — {err}"));
            }
        }
    });
}

/// Wakes a page `page_suspend` paused: before it is shown again, and before it
/// is given anything to load. Harmless on a page that is not suspended.
pub fn page_resume(page: &Webview) {
    let _ = page.with_webview(|webview| {
        let Some(core) = core_of(&webview.controller()) else { return };
        if let Ok(core) = core.cast::<ICoreWebView2_3>() {
            let _ = unsafe { core.Resume() };
        }
    });
}

/// Clips a page `w`×`h` physical px to the card's rounded corners.
///
/// A window region on the page's container: Windows clips the container and
/// every WebView2 window inside it. It cannot anti-alias, and the Mac's corner
/// is a continuous curve; the island's own card is drawn underneath in the same
/// #141518, so what the region's stair-steps reveal is the card itself.
///
/// The region survives resizes, so it is set again whenever the page is placed
/// — size and scale are the only inputs.
pub fn page_clip(page: &Webview, w: i32, h: i32, ellipse: i32) {
    let _ = page.with_webview(move |webview| {
        let Some(hwnd) = container(&webview.controller()) else { return };
        let (right, bottom) = page_model::region_extent(w, h);
        unsafe {
            let region = CreateRoundRectRgn(0, 0, right, bottom, ellipse, ellipse);
            if region.is_invalid() {
                return;
            }
            // The system owns a region it accepted; one it refused is still ours.
            if SetWindowRgn(hwnd, Some(region), true) == 0 {
                let _ = DeleteObject(region.into());
            }
        }
    });
}

/// The site's back button.
pub fn page_go_back(page: &Webview) {
    let _ = page.with_webview(|webview| {
        let Some(core) = core_of(&webview.controller()) else { return };
        let mut can = ::windows_core::BOOL::default();
        if unsafe { core.CanGoBack(&mut can) }.is_ok() && can.as_bool() {
            let _ = unsafe { core.GoBack() };
        }
    });
}

/// Starts a page's history over, so the back button only ever goes where this
/// visit went — NotchSiteWeb is a new WKWebView, with no history, on every
/// open. `then` hears whether there is still somewhere to go back to, and
/// hears it even when the reset could not be asked for: the page is not heard
/// on going back until it does (page_model::History).
pub fn page_reset_history(page: &Webview, then: impl FnOnce(bool) + Send + 'static) {
    let _ = page.with_webview(move |webview| {
        let Some(core) = core_of(&webview.controller()) else { return };
        let then = Rc::new(RefCell::new(Some(then)));
        let answer = {
            let then = then.clone();
            move |core: &ICoreWebView2| {
                let mut can = ::windows_core::BOOL::default();
                let _ = unsafe { core.CanGoBack(&mut can) };
                if let Some(then) = then.borrow_mut().take() {
                    then(can.as_bool());
                }
            }
        };
        let after = core.clone();
        let answered = answer.clone();
        let done = CallDevToolsProtocolMethodCompletedHandler::create(Box::new(move |_, _| {
            answered(&after);
            Ok(())
        }));
        let method = ::windows_core::HSTRING::from("Page.resetNavigationHistory");
        let params = ::windows_core::HSTRING::from("{}");
        if let Err(err) = unsafe { core.CallDevToolsProtocolMethod(&method, &params, &done) } {
            crate::log::line(format!("page history not reset — {err}"));
            answer(&core);
        }
    });
}

/// Tells a webview its window moved. wry used to do this from its own hook on
/// the window, which only webviews that fill their window get; with Tauri's
/// multiwebview on, every webview is a child, and without it WebView2's popups —
/// a `<select>`'s list, the IME's candidates — open where the window used to be.
pub fn notify_webview_moved(webview: &Webview) {
    let _ = webview.with_webview(|webview| {
        let _ = unsafe { webview.controller().NotifyParentWindowPositionChanged() };
    });
}

/// Escape inside a page window — the Linux page's. Here the page is a child of
/// the island and its controller reports Escape itself (`page_hooks`).
pub fn page_watch_escape(_win: &WebviewWindow, _on_escape: impl Fn() + Send + 'static) {}
