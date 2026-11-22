// WhatsApp — the Tauri half of WhatsAppWebController.swift.
//
// WhatsApp has no API for a personal account, so this is WhatsApp Web itself,
// in a window of its own that stays hidden except while the QR code is being
// scanned. `shared/whatsapp-bridge.js`, the same file the Mac injects, is what
// turns the page into a message source: it takes the notifications the page
// would draw, tells the page it is in a background tab so nothing is marked
// read, and types replies in.
//
// The page gets no IPC at all, on purpose. A capability for web.whatsapp.com
// would make it a remote origin that can reach the app's commands. Instead the
// bridge keeps its events in an outbox and rings by flipping an invisible
// character on the end of the page title; the title change is heard here, and
// the outbox is drained with an eval whose result comes back to Rust.
//
// Created hidden at launch like every other window (a WebView2 window built
// later comes up blank), but pointed at about:blank until the pill is on and
// this machine has been linked: nobody who has not asked to connect has a
// page open to WhatsApp.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{LazyLock, Mutex};
use std::time::Duration;

use serde_json::json;
use tauri::{AppHandle, Manager, Url, WebviewUrl, WebviewWindow, WebviewWindowBuilder};
use tokio::sync::oneshot;

use crate::integrations::PAUSED;
use crate::log;
use crate::message_proto::{
    base64_encode, mime_for, whatsapp_display_name, whatsapp_events, whatsapp_is_summary,
    whatsapp_keeps_in_webview, whatsapp_message_id, WhatsAppEvent, KIND_DIRECT, WHATSAPP_URL,
};
use crate::messages;
use crate::platform;
use crate::secrets;

pub const LABEL: &str = "whatsapp";

/// The bridge, the one the Mac bundles.
const BRIDGE: &str = include_str!("../../../shared/whatsapp-bridge.js");

/// Edge's own user agent. WhatsApp Web turns away a browser it does not know,
/// and WebView2's default names itself as embedded.
const USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 \
     (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36 Edg/140.0.0.0";

const SUPERVISOR_POLL: Duration = Duration::from_secs(5);
/// Long enough for a reply with a few files; the bridge gives up on each step
/// well before this.
const SEND_TIMEOUT: Duration = Duration::from_secs(120);

/// Whether the page is meant to be running, as last applied.
static RUNNING: AtomicBool = AtomicBool::new(false);
/// What the page last said about itself, for the status dot.
static PAGE_STATE: Mutex<&'static str> = Mutex::new("disconnected");
/// Replies waiting for the bridge to say how they went, by request id.
static PENDING: LazyLock<Mutex<HashMap<String, oneshot::Sender<Result<(), String>>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
/// The newest notification per conversation: its key is what opens that exact
/// chat when a reply goes out.
static LAST_KEY: LazyLock<Mutex<HashMap<String, String>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

// ── Window ───────────────────────────────────────────────────────────────────

/// The window, hidden, holding about:blank. Called once during setup.
pub fn create(app: &AppHandle) {
    let data_dir = app
        .path()
        .app_local_data_dir()
        .map(|dir| dir.join("whatsapp-webview"))
        .ok();
    let Ok(blank) = Url::parse("about:blank") else { return };

    let ring = app.clone();
    let mut builder = WebviewWindowBuilder::new(app, LABEL, WebviewUrl::External(blank))
        // Must match the island's, or the window comes up blank with no error.
        .additional_browser_args(crate::BROWSER_ARGS)
        .title("WhatsApp")
        .inner_size(1000.0, 720.0)
        .min_inner_size(640.0, 480.0)
        .resizable(true)
        .skip_taskbar(false)
        .visible(false)
        // Never focused while hidden, which is nearly always (see the welcome's
        // window in lib.rs).
        .focused(false)
        .center()
        .user_agent(USER_AGENT)
        .initialization_script(BRIDGE)
        .on_navigation(|target| {
            if whatsapp_keeps_in_webview(target.as_str()) {
                return true;
            }
            platform::open_url(target.as_str());
            false
        })
        .on_document_title_changed(move |window, _title| {
            // The bridge's doorbell, or WhatsApp's own unread count changing.
            // Either way, whatever is waiting is collected; an empty outbox
            // costs one eval.
            drain(&ring, &window);
        });
    if let Some(dir) = data_dir {
        // Its own profile, so unlinking can clear it without signing anyone
        // out of ChatGPT in the other window.
        builder = builder.data_directory(dir);
    }

    match builder.build() {
        Ok(win) => {
            crate::web::keep_hosting(&win);
            let hidden = win.clone();
            win.on_window_event(move |event| {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    // Hide, never close: it cannot be rebuilt after launch.
                    api.prevent_close();
                    let _ = hidden.hide();
                    set_shown(&hidden, false);
                }
            });
        }
        Err(err) => log::line(format!("whatsapp window failed: {err}")),
    }
}

fn window(app: &AppHandle) -> Option<WebviewWindow> {
    app.get_webview_window(LABEL)
}

fn set_shown(win: &WebviewWindow, shown: bool) {
    let _ = win.eval(format!("window.__notchy && window.__notchy.setShown({shown})"));
}

fn navigate(win: &WebviewWindow, url: &str) {
    if let Ok(parsed) = Url::parse(url) {
        let _ = win.navigate(parsed);
    }
}

// ── Supervisor ───────────────────────────────────────────────────────────────

/// Whether this machine has been linked to a phone at least once.
pub fn is_linked() -> bool {
    secrets::get(messages::WHATSAPP_LINKED_KEY).is_some_and(|v| v == "1")
}

/// Keeps the page running exactly while the pill is on and the machine is
/// linked (or a sign-in is under way), and blank otherwise. Polls a setting,
/// not the network.
pub fn start(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        loop {
            let wanted = !PAUSED.load(Ordering::Relaxed)
                && messages::pill_enabled(&app, messages::WHATSAPP_PILL)
                && is_linked();
            apply(&app, wanted);
            tokio::time::sleep(SUPERVISOR_POLL).await;
        }
    });
}

fn apply(app: &AppHandle, wanted: bool) {
    let was = RUNNING.load(Ordering::SeqCst);
    if wanted == was {
        return;
    }
    let Some(win) = window(app) else { return };
    if wanted {
        RUNNING.store(true, Ordering::SeqCst);
        set_state(app, "connecting", None);
        navigate(&win, WHATSAPP_URL);
        log::line("whatsapp: page started");
    } else {
        // A sign-in window on screen is somebody linking; leave it alone.
        if win.is_visible().unwrap_or(false) {
            return;
        }
        RUNNING.store(false, Ordering::SeqCst);
        navigate(&win, "about:blank");
        set_state(app, "disconnected", None);
        log::line("whatsapp: page stopped");
    }
}

fn set_state(app: &AppHandle, state: &'static str, detail: Option<String>) {
    {
        let mut current = PAGE_STATE.lock().unwrap();
        if *current == state && detail.is_none() {
            return;
        }
        *current = state;
    }
    messages::emit_status(app, messages::WHATSAPP, state, detail);
}

/// Shows the page for the QR code, starting it first if need be. The window
/// hides itself once the phone has scanned.
pub fn show_login(app: &AppHandle) {
    let Some(win) = window(app) else {
        log::line("whatsapp window missing");
        return;
    };
    if !RUNNING.swap(true, Ordering::SeqCst) {
        navigate(&win, WHATSAPP_URL);
        set_state(app, "connecting", None);
    }
    let _ = win.center();
    let _ = win.show();
    crate::web::bring_up(&win);
    set_shown(&win, true);
}

/// Unlinks this machine: the page goes blank and its profile is cleared.
pub fn sign_out(app: &AppHandle) {
    let _ = secrets::set(messages::WHATSAPP_LINKED_KEY, "");
    if let Some(win) = window(app) {
        let _ = win.hide();
        let _ = win.clear_all_browsing_data();
        navigate(&win, "about:blank");
    }
    RUNNING.store(false, Ordering::SeqCst);
    LAST_KEY.lock().unwrap().clear();
    set_state(app, "disconnected", None);
    log::line("whatsapp: signed out");
}

// ── Events ───────────────────────────────────────────────────────────────────

fn drain(app: &AppHandle, win: &WebviewWindow) {
    let app = app.clone();
    let _ = win.eval_with_callback(
        "(window.__notchy ? window.__notchy.drain() : [])",
        move |raw| {
            for event in whatsapp_events(&raw) {
                handle(&app, event);
            }
        },
    );
}

fn handle(app: &AppHandle, event: WhatsAppEvent) {
    match event {
        WhatsAppEvent::State("connected") => {
            if !is_linked() {
                let _ = secrets::set(messages::WHATSAPP_LINKED_KEY, "1");
            }
            set_state(app, "connected", None);
            // Linked: the sign-in window has done its job.
            if let Some(win) = window(app) {
                if win.is_visible().unwrap_or(false) {
                    let handle = win.clone();
                    tauri::async_runtime::spawn(async move {
                        tokio::time::sleep(Duration::from_millis(1200)).await;
                        let _ = handle.hide();
                        set_shown(&handle, false);
                    });
                }
            }
        }
        WhatsAppEvent::State("qr") => set_state(
            app,
            "failed",
            Some("Scan the QR code in Settings to connect WhatsApp.".to_string()),
        ),
        WhatsAppEvent::State(_) => {}
        WhatsAppEvent::Message { key, chat, body, timestamp_ms } => {
            let summary = whatsapp_is_summary(&chat);
            if !summary {
                LAST_KEY.lock().unwrap().insert(chat.clone(), key.clone());
            }
            let body = body.trim().to_string();
            messages::emit_message(
                app,
                messages::MessageEvent {
                    id: whatsapp_message_id(&key),
                    source: messages::WHATSAPP,
                    kind: KIND_DIRECT,
                    sender: whatsapp_display_name(&chat).unwrap_or_else(|| "WhatsApp".to_string()),
                    channel: None,
                    conversation_id: if summary { None } else { Some(chat) },
                    body: if body.is_empty() { "📎 Sent a file".to_string() } else { body },
                    timestamp_ms,
                    link: Some(WHATSAPP_URL.to_string()),
                    audio: None,
                },
            );
        }
        WhatsAppEvent::Sent { request_id } => finish(request_id, Ok(())),
        WhatsAppEvent::SendFailed { request_id, reason } => {
            log::line(format!("whatsapp: send failed: {reason}"));
            finish(request_id, Err("WhatsApp did not take the reply".to_string()));
        }
    }
}

fn finish(request_id: Option<String>, result: Result<(), String>) {
    let Some(id) = request_id else { return };
    if let Some(waiting) = PENDING.lock().unwrap().remove(&id) {
        let _ = waiting.send(result);
    }
}

// ── Replies ──────────────────────────────────────────────────────────────────

/// Replies in a conversation by driving the page: open it, type, send, then
/// attach each file and send that.
pub async fn send_reply(
    app: AppHandle,
    conversation_id: String,
    message: String,
    attachments: Vec<String>,
) -> Result<(), String> {
    let chat = conversation_id.trim().to_string();
    if chat.is_empty() {
        return Err("There is nowhere to reply to this one.".to_string());
    }
    if *PAGE_STATE.lock().unwrap() != "connected" {
        return Err("WhatsApp is not connected".to_string());
    }
    let Some(win) = window(&app) else {
        return Err("WhatsApp is not connected".to_string());
    };

    let mut files = Vec::new();
    for path in &attachments {
        let name = std::path::Path::new(path)
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| "file".to_string());
        let bytes = std::fs::read(path).map_err(|_| format!("Could not read {name}"))?;
        files.push(json!({ "name": name, "mime": mime_for(&name), "base64": base64_encode(&bytes) }));
    }

    let request_id = format!(
        "w{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    );
    let key = LAST_KEY.lock().unwrap().get(&chat).cloned().unwrap_or_default();
    let request = json!({
        "requestId": request_id,
        "chat": chat,
        "key": key,
        "text": message,
        "files": files,
    });

    let (tx, rx) = oneshot::channel();
    PENDING.lock().unwrap().insert(request_id.clone(), tx);
    if win
        .eval(format!("window.__notchy && window.__notchy.send({request})"))
        .is_err()
    {
        PENDING.lock().unwrap().remove(&request_id);
        return Err("WhatsApp did not take the reply".to_string());
    }

    match tokio::time::timeout(SEND_TIMEOUT, rx).await {
        Ok(Ok(result)) => result,
        _ => {
            PENDING.lock().unwrap().remove(&request_id);
            Err("WhatsApp did not take the reply".to_string())
        }
    }
}
