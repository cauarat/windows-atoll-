//! The hold-to-talk key: the Mac's DictationHoldGesture.swift (the gesture,
//! fixture for fixture) and DictationKeyTap.swift (the listener) for Windows.
//!
//! The listener is a low-level keyboard hook on a thread of its own. It never
//! swallows a key — every app still gets the right Ctrl or Alt as before — and
//! it reports nothing while the dictation key is up: what is typed never leaves
//! the hook. The gesture turns what it hears into four actions for the island:
//! arm (start the microphone and the connection), show (open the card), commit
//! (stop and transcribe) and cancel.
//!
//! Linux has no listener in this version: Wayland lets no app see keys meant
//! for another, so there dictation starts from the tray and the card's button.

use tauri::AppHandle;

/// Starts or stops listening for the key, as Settings say: only while Notchy
/// and dictation are both on, and a key is chosen.
pub fn apply(app: &AppHandle, settings: &crate::settings::Settings) {
    #[cfg(windows)]
    {
        let vk = match (settings.enabled && settings.dictation_enabled, settings.dictation_hold_key.as_str()) {
            (true, "rightCtrl") => Some(hook::VK_RIGHT_CTRL),
            (true, "rightAlt") => Some(hook::VK_RIGHT_ALT),
            _ => None,
        };
        match vk {
            Some(vk) => hook::start(app.clone(), vk),
            None => hook::stop(),
        }
    }
    #[cfg(not(windows))]
    {
        let _ = (app, settings);
    }
}

#[cfg(windows)]
mod hook {
    use crate::dictation_gesture::{Action, HoldGesture, Input, MAXIMUM_HOLD_MS, MINIMUM_HOLD_MS};
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::Mutex;
    use std::time::{Duration, Instant};
    use tauri::{AppHandle, Emitter};
    use windows::Win32::Foundation::{HINSTANCE, LPARAM, LRESULT, WPARAM};
    use windows::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows::Win32::System::Threading::GetCurrentThreadId;
    use windows::Win32::UI::Input::KeyboardAndMouse::{
        SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS, KEYEVENTF_KEYUP, VIRTUAL_KEY,
    };
    use windows::Win32::UI::WindowsAndMessaging::{
        CallNextHookEx, GetMessageW, PostThreadMessageW, SetWindowsHookExW, UnhookWindowsHookEx, HC_ACTION,
        KBDLLHOOKSTRUCT, LLKHF_INJECTED, MSG, WH_KEYBOARD_LL, WM_KEYDOWN, WM_KEYUP, WM_QUIT, WM_SYSKEYDOWN,
        WM_SYSKEYUP,
    };

    pub const VK_RIGHT_CTRL: u32 = 0xA3;
    pub const VK_RIGHT_ALT: u32 = 0xA5;
    const VK_LEFT_CTRL: u32 = 0xA2;
    const VK_ESCAPE: u32 = 0x1B;
    /// The left Ctrl that AltGr layouts send in front of every right Alt —
    /// and again with every repeat while it is held. Not "another key".
    const ALTGR_PHANTOM_SCAN: u32 = 0x21D;
    /// An unassigned key (AutoHotkey's menu mask): pressed once while a held
    /// right Alt is dictating, so letting go of it does not open the focused
    /// app's menu bar.
    const VK_MENU_MASK: u16 = 0xE8;

    struct Listening {
        vk: u32,
        down: bool,
        gesture: HoldGesture,
        app: AppHandle,
        epoch: Instant,
    }

    static LISTENING: Mutex<Option<Listening>> = Mutex::new(None);
    static THREAD: Mutex<Option<u32>> = Mutex::new(None);
    /// Bumped by every press, so a tick scheduled for an earlier hold is dropped.
    static HOLD: AtomicU64 = AtomicU64::new(0);

    pub fn start(app: AppHandle, vk: u32) {
        *LISTENING.lock().unwrap() =
            Some(Listening { vk, down: false, gesture: HoldGesture::default(), app, epoch: Instant::now() });
        let mut thread = THREAD.lock().unwrap();
        if thread.is_some() {
            return; // already hooked; the key was just updated
        }
        let (tx, rx) = std::sync::mpsc::channel();
        let spawned = std::thread::Builder::new().name("dictation-key".into()).spawn(move || unsafe {
            let module = GetModuleHandleW(None).ok().map(|m| HINSTANCE(m.0));
            let hook = SetWindowsHookExW(WH_KEYBOARD_LL, Some(callback), module, 0);
            let _ = tx.send(GetCurrentThreadId());
            let Ok(hook) = hook else { return };
            // A low-level hook is called on the thread that set it, through its
            // message loop; WM_QUIT from stop() ends it.
            let mut msg = MSG::default();
            while GetMessageW(&mut msg, None, 0, 0).as_bool() {}
            let _ = UnhookWindowsHookEx(hook);
        });
        if spawned.is_ok() {
            if let Ok(id) = rx.recv() {
                *thread = Some(id);
            }
        }
    }

    pub fn stop() {
        if let Some(id) = THREAD.lock().unwrap().take() {
            unsafe {
                let _ = PostThreadMessageW(id, WM_QUIT, WPARAM(0), LPARAM(0));
            }
        }
        *LISTENING.lock().unwrap() = None;
    }

    unsafe extern "system" fn callback(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
        if code == HC_ACTION as i32 {
            let key = &*(lparam.0 as *const KBDLLHOOKSTRUCT);
            // Our own Ctrl+V and menu mask come back through here; they are not
            // the person's keys.
            if key.flags.0 & LLKHF_INJECTED.0 == 0 {
                heard(key.vkCode, key.scanCode, wparam.0 as u32);
            }
        }
        CallNextHookEx(None, code, wparam, lparam)
    }

    fn heard(vk: u32, scan: u32, message: u32) {
        let pressed = message == WM_KEYDOWN || message == WM_SYSKEYDOWN;
        let released = message == WM_KEYUP || message == WM_SYSKEYUP;
        let mut guard = LISTENING.lock().unwrap();
        let Some(listening) = guard.as_mut() else { return };
        let input = if vk == listening.vk {
            if pressed && !listening.down {
                listening.down = true;
                Some(Input::Down)
            } else if released && listening.down {
                listening.down = false;
                Some(Input::Up)
            } else {
                None // the key's own repeat
            }
        } else if listening.down && pressed {
            if vk == VK_LEFT_CTRL && scan == ALTGR_PHANTOM_SCAN {
                None
            } else if vk == VK_ESCAPE {
                Some(Input::Escape)
            } else {
                Some(Input::Other)
            }
        } else {
            None // nothing is reported while the key is up
        };
        let Some(input) = input else { return };
        let at = listening.epoch.elapsed().as_millis() as u64;
        let actions = listening.gesture.handle(input, at);
        let app = listening.app.clone();
        let masks = listening.vk == VK_RIGHT_ALT;
        drop(guard);
        perform(&app, &actions, masks);
    }

    fn perform(app: &AppHandle, actions: &[Action], masks: bool) {
        for action in actions {
            match action {
                Action::Arm => schedule_ticks(),
                Action::Show if masks => mask_menu(),
                _ => {}
            }
            let _ = app.emit_to(crate::island::WINDOW_LABEL, "dictation-hold", *action);
        }
    }

    /// One tick at the minimum hold, one at the cap; the thread ends as soon
    /// as the hold does.
    fn schedule_ticks() {
        let hold = HOLD.fetch_add(1, Ordering::Relaxed) + 1;
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(MINIMUM_HOLD_MS));
            if !tick(hold) {
                return;
            }
            let mut waited = MINIMUM_HOLD_MS;
            while waited < MAXIMUM_HOLD_MS {
                std::thread::sleep(Duration::from_secs(1));
                waited += 1000;
                if HOLD.load(Ordering::Relaxed) != hold || !still_holding() {
                    return;
                }
            }
            tick(hold);
        });
    }

    fn still_holding() -> bool {
        LISTENING.lock().unwrap().as_ref().is_some_and(|l| l.gesture.is_holding())
    }

    /// Feeds a tick to the gesture; false once that hold is over.
    fn tick(hold: u64) -> bool {
        if HOLD.load(Ordering::Relaxed) != hold {
            return false;
        }
        let mut guard = LISTENING.lock().unwrap();
        let Some(listening) = guard.as_mut() else { return false };
        let at = listening.epoch.elapsed().as_millis() as u64;
        let actions = listening.gesture.handle(Input::Tick, at);
        let holding = listening.gesture.is_holding();
        let app = listening.app.clone();
        let masks = listening.vk == VK_RIGHT_ALT;
        drop(guard);
        perform(&app, &actions, masks);
        holding
    }

    fn mask_menu() {
        let key = |up: bool| INPUT {
            r#type: INPUT_KEYBOARD,
            Anonymous: INPUT_0 {
                ki: KEYBDINPUT {
                    wVk: VIRTUAL_KEY(VK_MENU_MASK),
                    wScan: 0,
                    dwFlags: if up { KEYEVENTF_KEYUP } else { KEYBD_EVENT_FLAGS(0) },
                    time: 0,
                    dwExtraInfo: 0,
                },
            },
        };
        unsafe {
            SendInput(&[key(false), key(true)], std::mem::size_of::<INPUT>() as i32);
        }
    }
}
