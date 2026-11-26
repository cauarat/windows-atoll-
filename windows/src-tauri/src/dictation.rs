//! Dictation: the island's connection to the transcription service.
//!
//! The speech model runs in dictation-service/ (Qwen3-ASR on open weights by
//! default), at the address set in Settings. The island's webview captures the
//! microphone and hands 100 ms frames of 16 kHz PCM16 here; this side keeps the
//! WebSocket — the page's CSP keeps it from reaching other hosts itself, and
//! the service may live on another machine — and passes every message the
//! service sends back to the island as a `dictation-message` event, for
//! core/dictation.ts to read. The Mac's twin is DictationSocket.swift.
//!
//! Also here: `/health` for Settings and the card, and what becomes of the
//! text — pasted where the cursor is (Windows: clipboard, Ctrl+V, clipboard
//! given back) or only copied (Linux, where Wayland lets no app type into
//! another).

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, State};
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message as WsMessage;

use crate::island;

const OPEN_DEADLINE: Duration = Duration::from_secs(5);
const HEALTH_DEADLINE: Duration = Duration::from_secs(3);

/// The one dictation in progress, if any.
#[derive(Default)]
pub struct DictationState {
    session: Mutex<Option<Session>>,
}

struct Session {
    id: u64,
    tx: mpsc::UnboundedSender<Outgoing>,
}

enum Outgoing {
    Audio(Vec<u8>),
    Text(String),
    Close,
}

static NEXT_SESSION: AtomicU64 = AtomicU64::new(1);

/// What the island hears about a session: a message from the service, as it
/// came, or the end of the connection.
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct SocketEvent {
    session: u64,
    /// The service's JSON, untouched — core/dictation.ts decodes it.
    message: Option<String>,
    /// "refused" (nothing answered at the address) or "lost" (it went away).
    closed: Option<&'static str>,
}

fn emit(app: &AppHandle, event: SocketEvent) {
    let _ = app.emit_to(island::WINDOW_LABEL, "dictation-socket", event);
}

/// Opens the connection and sends `start` (the island built it, with the
/// language). Any dictation still open is dropped first. Returns the session
/// id the events carry, so the island can ignore a stale one.
#[tauri::command]
pub fn dictation_start(app: AppHandle, state: State<'_, DictationState>, url: String, start: String) -> Result<u64, String> {
    if !(url.starts_with("ws://") || url.starts_with("wss://")) {
        return Err("not a WebSocket address".into());
    }
    let id = NEXT_SESSION.fetch_add(1, Ordering::Relaxed);
    let (tx, rx) = mpsc::unbounded_channel();
    if let Some(old) = state.session.lock().unwrap().replace(Session { id, tx }) {
        let _ = old.tx.send(Outgoing::Close);
    }
    tauri::async_runtime::spawn(run(app, id, url, start, rx));
    Ok(id)
}

async fn run(app: AppHandle, id: u64, url: String, start: String, mut rx: mpsc::UnboundedReceiver<Outgoing>) {
    let closed = move |kind: &'static str| SocketEvent { session: id, message: None, closed: Some(kind) };
    let socket = match tokio::time::timeout(OPEN_DEADLINE, tokio_tungstenite::connect_async(url.as_str())).await {
        Ok(Ok((socket, _response))) => socket,
        _ => return emit(&app, closed("refused")),
    };
    let (mut sink, mut stream) = socket.split();
    if sink.send(WsMessage::text(start)).await.is_err() {
        return emit(&app, closed("lost"));
    }

    // What the service says, as it says it. Reading also answers its pings,
    // which is what keeps a long wait for the final from being cut off. When
    // the service closes — it does after the final — the session is over, and
    // dropping it ends the writer below.
    let reader_app = app.clone();
    tauri::async_runtime::spawn(async move {
        loop {
            match stream.next().await {
                Some(Ok(WsMessage::Text(text))) => {
                    emit(&reader_app, SocketEvent { session: id, message: Some(text.to_string()), closed: None });
                }
                Some(Ok(WsMessage::Close(_))) | None | Some(Err(_)) => {
                    emit(&reader_app, closed("lost"));
                    break;
                }
                Some(Ok(_)) => {}
            }
        }
        forget(&reader_app, id);
    });

    // The microphone's frames and the control messages, in the order the
    // island sent them: `stop` can never overtake the last frame.
    while let Some(outgoing) = rx.recv().await {
        let sent = match outgoing {
            Outgoing::Audio(bytes) => sink.send(WsMessage::binary(bytes)).await,
            Outgoing::Text(text) => sink.send(WsMessage::text(text)).await,
            Outgoing::Close => {
                let _ = sink.close().await;
                break;
            }
        };
        if sent.is_err() {
            break;
        }
    }
    forget(&app, id);
}

/// Drops the session if it is still this one.
fn forget(app: &AppHandle, id: u64) {
    let state = app.state::<DictationState>();
    let mut current = state.session.lock().unwrap();
    if current.as_ref().is_some_and(|s| s.id == id) {
        *current = None;
    }
}

fn send(state: &DictationState, message: Outgoing) {
    if let Some(session) = state.session.lock().unwrap().as_ref() {
        let _ = session.tx.send(message);
    }
}

/// One frame of audio, as the request's raw body: binary over IPC, not a JSON
/// array of numbers ten times a second.
#[tauri::command]
pub fn dictation_audio(state: State<'_, DictationState>, request: tauri::ipc::Request<'_>) -> Result<(), String> {
    let tauri::ipc::InvokeBody::Raw(bytes) = request.body() else {
        return Err("expected raw PCM".into());
    };
    send(&state, Outgoing::Audio(bytes.clone()));
    Ok(())
}

/// All the audio is in: the service answers with the final.
#[tauri::command]
pub fn dictation_stop(state: State<'_, DictationState>) {
    send(&state, Outgoing::Text(r#"{"type":"stop"}"#.into()));
}

/// Drop the dictation; nothing more comes back.
#[tauri::command]
pub fn dictation_cancel(state: State<'_, DictationState>) {
    if let Some(session) = state.session.lock().unwrap().take() {
        let _ = session.tx.send(Outgoing::Text(r#"{"type":"cancel"}"#.into()));
        let _ = session.tx.send(Outgoing::Close);
    }
}

/// The service's `/health`, for Settings and the card.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HealthAnswer {
    /// The JSON it answered, for core/dictation.ts to read; None if it did not.
    body: Option<String>,
    /// Why not: "offline" (nothing answered) or "notTheService".
    problem: Option<&'static str>,
}

#[tauri::command]
pub async fn dictation_health(url: String) -> HealthAnswer {
    let client = match reqwest::Client::builder().timeout(HEALTH_DEADLINE).build() {
        Ok(client) => client,
        Err(_) => return HealthAnswer { body: None, problem: Some("offline") },
    };
    match client.get(&url).send().await {
        Err(_) => HealthAnswer { body: None, problem: Some("offline") },
        Ok(response) if !response.status().is_success() => HealthAnswer { body: None, problem: Some("notTheService") },
        Ok(response) => match response.text().await {
            Ok(body) => HealthAnswer { body: Some(body), problem: None },
            Err(_) => HealthAnswer { body: None, problem: Some("notTheService") },
        },
    }
}

/// Windows' own microphone privacy page, from the card when the microphone
/// was refused. A fixed address: `open_url` takes only web pages.
#[tauri::command]
pub fn dictation_microphone_settings() {
    #[cfg(windows)]
    crate::platform::open_url("ms-settings:privacy-microphone");
}

/// Puts the text where the cursor is, or only copies it. Answers what
/// happened: "pasted" or "copied" — the card says which.
#[tauri::command]
pub fn dictation_insert(text: String, mode: String) -> Result<&'static str, String> {
    if mode == "paste" && cfg!(windows) {
        paste::paste(&text)?;
        return Ok("pasted");
    }
    let mut board = arboard::Clipboard::new().map_err(|e| e.to_string())?;
    board.set_text(text).map_err(|e| e.to_string())?;
    Ok("copied")
}

#[cfg(windows)]
mod paste {
    //! Clipboard, Ctrl+V, clipboard given back — the Mac's DictationInserter.
    use std::time::Duration;
    use windows::Win32::UI::Input::KeyboardAndMouse::{
        SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS, KEYEVENTF_KEYUP, VIRTUAL_KEY,
        VK_CONTROL,
    };

    /// How long the pasted text stays on the clipboard before what was there
    /// comes back: some apps read a paste a beat late.
    const RESTORE_AFTER: Duration = Duration::from_millis(800);

    enum Saved {
        Text(String),
        Image(arboard::ImageData<'static>),
        Nothing,
    }

    pub fn paste(text: &str) -> Result<(), String> {
        let mut board = arboard::Clipboard::new().map_err(|e| e.to_string())?;
        let saved = match board.get_text() {
            Ok(previous) => Saved::Text(previous),
            Err(_) => match board.get_image() {
                Ok(image) => Saved::Image(image.to_owned_img()),
                Err(_) => Saved::Nothing,
            },
        };
        board.set_text(text.to_string()).map_err(|e| e.to_string())?;
        press_ctrl_v();
        let ours = text.to_string();
        std::thread::spawn(move || {
            std::thread::sleep(RESTORE_AFTER);
            let Ok(mut board) = arboard::Clipboard::new() else { return };
            // Copied something else meanwhile: theirs wins.
            if board.get_text().ok().as_deref() != Some(ours.as_str()) {
                return;
            }
            let _ = match saved {
                Saved::Text(previous) => board.set_text(previous),
                Saved::Image(image) => board.set_image(image),
                Saved::Nothing => board.clear(),
            };
        });
        Ok(())
    }

    fn key(vk: VIRTUAL_KEY, up: bool) -> INPUT {
        INPUT {
            r#type: INPUT_KEYBOARD,
            Anonymous: INPUT_0 {
                ki: KEYBDINPUT {
                    wVk: vk,
                    wScan: 0,
                    dwFlags: if up { KEYEVENTF_KEYUP } else { KEYBD_EVENT_FLAGS(0) },
                    time: 0,
                    dwExtraInfo: 0,
                },
            },
        }
    }

    fn press_ctrl_v() {
        // 'V' is the same virtual key on every layout: accelerators read it.
        let v = VIRTUAL_KEY(0x56);
        let inputs = [key(VK_CONTROL, false), key(v, false), key(v, true), key(VK_CONTROL, true)];
        unsafe {
            SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
        }
    }
}

#[cfg(not(windows))]
mod paste {
    pub fn paste(_text: &str) -> Result<(), String> {
        Err("pasting into other apps is Windows-only".into())
    }
}
