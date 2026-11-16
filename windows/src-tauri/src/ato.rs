// Ato — the Rust port of AtoClient.swift.
//
// Ato is Actuar's support inbox, inside novo.actuar.com, and it took over from
// ClickMassa. It speaks two protocols: REST for signing in, finding out who you
// are and replying, and a SignalR hub that pushes every conversation in the
// workspace. This file is the running half; everything decided purely by its
// inputs lives in `message_proto`, where it is unit-tested against frames
// captured off the real hub.
//
// What was learned the hard way, and is not decoration:
//
// 1. **The filter.** The hub carries the whole workspace — every agent, and
//    the bot talking to customers before anyone is assigned.
//    `message_proto::ato_should_notify` is what keeps the island from opening
//    for the whole company's WhatsApp.
//
// 2. **Sign-in is Actuar's, and it is rate-limited like any other.** The
//    session is held and reused, refreshed through `/Auth/Refresh` ahead of its
//    two-hour expiry, and a full sign-in happens at most once a minute however
//    badly the socket behaves.
//
// 3. **Listening never changes your presence.** The console's `Heartbeat` is
//    what marks an agent online, and this client never invokes it.
//
// Nothing here connects, and nothing reaches the network, until the user has
// switched the Ato pill on and stored an email and a password.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use tauri::AppHandle;
use tokio_tungstenite::tungstenite::Message as WsMessage;

use crate::integrations::PAUSED;
use crate::log;
use crate::message_proto::{
    ato_conversation_link, ato_display_name, ato_hub_url, ato_memberships, ato_message_id,
    ato_engagement, ato_needs_answerer_lookup, ato_normalized_email, ato_password_digest, ato_should_notify, backoff_delay, clock_jitter,
    ato_storage_object_id, jwt_expiry_secs, mime_for, percent_encode, signalr_records,
    AtoEngagement, AtoMembership, AtoUpdate, ATO_SENDER_AGENT, ATO_ENGAGEMENT_LIFETIME_SECS, ATO_ACCOUNTS, ATO_APP, ATO_CHAT_UPLOAD_FOLDER, ATO_MAX_UPLOAD_BYTES,
    ATO_STORAGE_SERVICE, ATO_SUPPORT_SERVICE, ATO_USER_SERVICE, KIND_DIRECT,
    SIGNALR_HANDSHAKE, SIGNALR_PING,
};
use crate::messages;
use crate::secrets;

// ── Timings, matching the Swift client's ─────────────────────────────────────

const REQUEST_TIMEOUT: Duration = Duration::from_secs(20);
/// How long the hub has to answer the handshake.
const OPEN_DEADLINE: Duration = Duration::from_secs(20);
/// SignalR's server pings every 15 seconds; this much silence is three missed.
const IDLE_LIMIT: Duration = Duration::from_secs(45);
/// The server drops a client it has not heard from in 30 seconds.
const PING_INTERVAL: Duration = Duration::from_secs(15);
const POLL_SLICE: Duration = Duration::from_secs(2);
const IDLE_POLL: Duration = Duration::from_secs(5);
const UNCONFIGURED_POLL: Duration = Duration::from_secs(15);
/// The floor between two full sign-ins.
const MIN_LOGIN_INTERVAL: Duration = Duration::from_secs(60);
/// How long before a token's `exp` to trade it for the next one.
const REFRESH_LEAD_SECS: i64 = 10 * 60;
/// A stored token with less than this left is not worth opening a socket on.
const USABLE_FOR_SECS: i64 = 5 * 60;

const USER_AGENT: &str =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) \
     Chrome/124.0.0.0 Safari/537.36";

// ── State ────────────────────────────────────────────────────────────────────

/// Who we are, from `/Agents/me`, plus the names worth putting on a card.
#[derive(Clone, Debug, Default)]
struct Session {
    token: String,
    memberships: Vec<AtoMembership>,
    queue_names: HashMap<String, String>,
    username: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct Config {
    email: String,
    password: String,
}

static GENERATION: AtomicU64 = AtomicU64::new(0);
static STOPPED: AtomicBool = AtomicBool::new(true);
static SESSION: Mutex<Option<Session>> = Mutex::new(None);
static LAST_LOGIN: Mutex<Option<Instant>> = Mutex::new(None);
static BYPASS_LOGIN_FLOOR: AtomicBool = AtomicBool::new(false);

/// Contact names by id: an update names the contact by id only, and the same
/// few people write again and again.
static CONTACTS: LazyLock<Mutex<HashMap<String, String>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
/// Conversations you replied to, by lowercased id, with when — see
/// `message_proto::ato_engagement`. On disk as well as here: a restart between
/// your reply and the customer's answer must not make the answer someone
/// else's. Ids only, nothing anyone said.
static ENGAGED: LazyLock<Mutex<HashMap<String, i64>>> =
    LazyLock::new(|| Mutex::new(load_engaged()));

/// Conversations already asked about this session, so a busy one costs one
/// request rather than one per message.
static ANSWERER_CHECKED: LazyLock<Mutex<std::collections::HashSet<String>>> =
    LazyLock::new(|| Mutex::new(std::collections::HashSet::new()));

/// The last customer message already announced, per conversation.
static ANNOUNCED: LazyLock<Mutex<HashMap<String, String>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Uploads get longer than a request: a 25 MB file on a slow line.
static UPLOADS: LazyLock<reqwest::Client> = LazyLock::new(|| {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(120))
        .build()
        .unwrap_or_default()
});

static HTTP: LazyLock<reqwest::Client> = LazyLock::new(|| {
    reqwest::Client::builder()
        .timeout(REQUEST_TIMEOUT)
        .build()
        .unwrap_or_default()
});

// ── Public surface ───────────────────────────────────────────────────────────

/// Starts the Ato supervisor. Safe at boot: it connects nothing until the pill
/// is on and the credentials are there. Calling it again replaces the running
/// supervisor rather than adding a second one.
pub fn start(app: AppHandle) {
    STOPPED.store(false, Ordering::SeqCst);
    let generation = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
    tauri::async_runtime::spawn(async move {
        supervise(app, generation).await;
    });
}

/// Starts again now, throwing the stored session away and skipping the
/// sign-in floor once. Only for a person pressing Sign in.
pub fn sign_in_now(app: AppHandle) {
    // Both halves: a refresh would otherwise bring back the session of
    // whoever was signed in before.
    forget_session();
    let _ = secrets::set(messages::ATO_TOKEN_ID_KEY, "");
    BYPASS_LOGIN_FLOOR.store(true, Ordering::SeqCst);
    start(app);
}

#[allow(dead_code)]
pub fn disconnect() {
    STOPPED.store(true, Ordering::SeqCst);
    GENERATION.fetch_add(1, Ordering::SeqCst);
}

/// Replies to a conversation from the card.
///
/// Files go the console's way: each is uploaded to the storage service's chat
/// folder first, which answers a `StorageObjectId`, and the one message then
/// carries the text and every file as `Attachments`. A voice message is an
/// audio file among them, as it is there.
pub async fn send_reply(
    conversation_id: String,
    message: String,
    attachments: Vec<String>,
) -> Result<(), String> {
    let text = message.trim().to_string();
    if text.is_empty() && attachments.is_empty() {
        return Ok(());
    }
    let conversation_id = conversation_id.trim().to_string();
    if conversation_id.is_empty() {
        return Err("There is nowhere to reply to this one.".to_string());
    }
    let Some(config) = configuration() else {
        return Err("Not signed in to Ato".to_string());
    };

    // Read up front, so a file that cannot go is said before anything has.
    let mut files = Vec::new();
    for path in &attachments {
        let name = std::path::Path::new(path)
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| "file".to_string());
        let bytes = std::fs::read(path).map_err(|_| format!("Could not read {name}"))?;
        if bytes.len() > ATO_MAX_UPLOAD_BYTES {
            return Err(format!("{name} is larger than Ato takes (25 MB)"));
        }
        files.push(PendingFile { mime: mime_for(&name), name, bytes });
    }

    // What has been uploaded survives a token running out halfway.
    let mut uploaded: Vec<Value> = Vec::new();
    let client_id = client_message_id();
    let token = usable_token().unwrap_or_default();
    let sent = match send_once(&token, &conversation_id, &client_id, &text, &files, &mut uploaded).await {
        Ok(()) => Ok(()),
        Err(error) if error.unauthorized => {
            // Two hours is short enough to run out between a card arriving and
            // the reply being typed.
            BYPASS_LOGIN_FLOOR.store(true, Ordering::SeqCst);
            let token = fresh_token(&config).await.map_err(|e| e.text)?;
            send_once(&token, &conversation_id, &client_id, &text, &files, &mut uploaded)
                .await
                .map_err(|e| e.text)
        }
        Err(error) => Err(error.text),
    };
    // Answered from the card: the customer's next word is yours, without
    // waiting for the echo on the hub to say so.
    if sent.is_ok() {
        set_engaged(&conversation_id, true);
    }
    sent
}

// ── Conversations you are answering ──────────────────────────────────────────

/// Asks Ato who answered this conversation last.
async fn last_answerer_is_me(token: &str, session: &Session, update: &AtoUpdate) -> bool {
    let Some(membership) = session.memberships.iter().find(|m| {
        update.workspace_id.as_deref().is_some_and(|w| w.eq_ignore_ascii_case(&m.workspace_id))
    }) else {
        return false;
    };
    let url = format!(
        "{ATO_SUPPORT_SERVICE}/OData/Messages?$filter={}&$orderby={}&$top=1&$select=SenderId",
        percent_encode(&format!(
            "ConversationId eq {} and SenderType eq 'Agent'",
            update.conversation_id
        )),
        percent_encode("AddedOnUtc desc"),
    );
    let Ok(response) = get(token, &url).await else { return false };
    if response.status().as_u16() != 200 {
        return false;
    }
    let Ok(page) = response.json::<Value>().await else { return false };
    page.pointer("/value/0/SenderId")
        .and_then(Value::as_str)
        .is_some_and(|id| id.eq_ignore_ascii_case(&membership.agent_id))
}

fn engaged_path() -> std::path::PathBuf {
    crate::settings::local_dir().join("ato-engaged.json")
}

fn load_engaged() -> HashMap<String, i64> {
    let now = now_millis() / 1_000;
    std::fs::read(engaged_path())
        .ok()
        .and_then(|bytes| serde_json::from_slice::<HashMap<String, i64>>(&bytes).ok())
        .unwrap_or_default()
        .into_iter()
        .filter(|(_, at)| now - at < ATO_ENGAGEMENT_LIFETIME_SECS)
        .collect()
}

fn set_engaged(conversation_id: &str, on: bool) {
    let key = conversation_id.to_lowercase();
    let now = now_millis() / 1_000;
    let Ok(mut map) = ENGAGED.lock() else { return };
    if on {
        map.insert(key, now);
    } else if map.remove(&key).is_none() {
        return;
    }
    map.retain(|_, at| now - *at < ATO_ENGAGEMENT_LIFETIME_SECS);
    if let Ok(json) = serde_json::to_vec(&*map) {
        if crate::platform::ensure_private_dir(&crate::settings::local_dir()).is_ok() {
            let _ = std::fs::write(engaged_path(), json);
        }
    }
}

struct PendingFile {
    name: String,
    mime: &'static str,
    bytes: Vec<u8>,
}

async fn send_once(
    token: &str,
    conversation_id: &str,
    client_id: &str,
    text: &str,
    files: &[PendingFile],
    uploaded: &mut Vec<Value>,
) -> Result<(), ClientError> {
    while uploaded.len() < files.len() {
        let file = &files[uploaded.len()];
        let id = upload_file(token, file).await?;
        uploaded.push(json!({
            "StorageFileId": id,
            "FileName": file.name,
            "ContentType": file.mime,
            "SizeBytes": file.bytes.len(),
        }));
    }
    post_reply(token, conversation_id, client_id, text, uploaded).await
}

/// `POST /FileUpload/Upload?folder=19`: the file and its content type as form
/// fields, answering the `StorageObjectId` a message attaches.
async fn upload_file(token: &str, file: &PendingFile) -> Result<String, ClientError> {
    if token.is_empty() {
        return Err(ClientError::unauthorized("Not signed in to Ato"));
    }
    let part = reqwest::multipart::Part::bytes(file.bytes.clone())
        .file_name(file.name.clone())
        .mime_str(file.mime)
        .map_err(|e| ClientError::new(format!("Ato did not accept {}: {e}", file.name)))?;
    let form = reqwest::multipart::Form::new()
        .part("file", part)
        .text("contentType", file.mime.to_string());
    let sent = UPLOADS
        .post(format!("{ATO_STORAGE_SERVICE}/FileUpload/Upload?folder={ATO_CHAT_UPLOAD_FOLDER}"))
        .header("Accept", "application/json")
        .header("Authorization", format!("Bearer {token}"))
        .header("User-Agent", USER_AGENT)
        .header("Origin", ATO_APP)
        .header("Referer", format!("{ATO_APP}/"))
        .multipart(form)
        .send()
        .await;
    let response = match sent {
        Ok(response) => response,
        Err(error) => return Err(ClientError::transport(format!("Could not send: {error}"))),
    };
    match response.status().as_u16() {
        200 | 201 => {
            let body = response.text().await.unwrap_or_default();
            ato_storage_object_id(&body)
                .ok_or_else(|| ClientError::new(format!("Ato did not accept {}", file.name)))
        }
        401 => Err(ClientError::unauthorized("Session expired")),
        413 => Err(ClientError::new(format!("{} is larger than Ato takes (25 MB)", file.name))),
        _ => Err(ClientError::new(format!("Ato did not accept {}", file.name))),
    }
}

// ── Supervisor ───────────────────────────────────────────────────────────────

enum Outcome {
    Stop,
    Retry { reason: String, was_connected: bool },
    Fatal(ClientError),
}

async fn supervise(app: AppHandle, generation: u64) {
    let mut attempt: u32 = 0;
    let mut announced: Option<(&'static str, Option<String>)> = None;

    loop {
        if is_stale(generation) {
            break;
        }

        if PAUSED.load(Ordering::Relaxed) || !messages::pill_enabled(&app, messages::ATO_PILL) {
            announce(&app, &mut announced, "disconnected", None);
            if !sleep_unless_stale(IDLE_POLL, generation).await {
                break;
            }
            continue;
        }

        let Some(config) = configuration() else {
            announce(&app, &mut announced, "failed",
                     Some("Add your Actuar email and password".to_string()));
            if !sleep_unless_stale(UNCONFIGURED_POLL, generation).await {
                break;
            }
            continue;
        };

        announce(&app, &mut announced, "connecting", None);

        match run_attempt(&app, &config, generation, &mut announced).await {
            Outcome::Stop => continue,
            Outcome::Retry { reason, was_connected } => {
                announce(&app, &mut announced, "failed", Some(reason));
                if was_connected {
                    attempt = 0;
                }
                let delay = backoff_delay(attempt, clock_jitter());
                attempt = attempt.saturating_add(1);
                if !sleep_unless_stale(delay, generation).await {
                    break;
                }
            }
            Outcome::Fatal(error) => {
                forget_session();
                attempt = 0;
                announce(&app, &mut announced, "failed", Some(error.text.clone()));
                log::line(format!("ato: {}", error.text));

                if let Some(wait) = error.retry_after {
                    if !sleep_unless_stale(wait + Duration::from_secs(1), generation).await {
                        break;
                    }
                    continue;
                }
                // A wrong password does not fix itself; sit still until the
                // credentials actually change.
                if !park_until_changed(&app, &config, generation).await {
                    break;
                }
            }
        }
    }

    if STOPPED.load(Ordering::SeqCst) {
        announce(&app, &mut announced, "disconnected", None);
    }
}

async fn park_until_changed(app: &AppHandle, failed_with: &Config, generation: u64) -> bool {
    loop {
        if !sleep_unless_stale(UNCONFIGURED_POLL, generation).await {
            return false;
        }
        if PAUSED.load(Ordering::Relaxed) || !messages::pill_enabled(app, messages::ATO_PILL) {
            return true;
        }
        if configuration().as_ref() != Some(failed_with) {
            return true;
        }
    }
}

async fn run_attempt(
    app: &AppHandle,
    config: &Config,
    generation: u64,
    announced: &mut Option<(&'static str, Option<String>)>,
) -> Outcome {
    let token = match fresh_token(config).await {
        Ok(token) => token,
        Err(error) if error.transport => {
            return Outcome::Retry { reason: error.text, was_connected: false }
        }
        Err(error) => return Outcome::Fatal(error),
    };

    let session = match load_session(&token, &config.email).await {
        Ok(session) => session,
        Err(error) if error.unauthorized => {
            // Refused outright: forget it, and the next pass signs in again.
            forget_session();
            return Outcome::Retry { reason: error.text, was_connected: false };
        }
        Err(error) if error.transport => {
            return Outcome::Retry { reason: error.text, was_connected: false }
        }
        Err(error) => return Outcome::Fatal(error),
    };
    if let Ok(mut guard) = SESSION.lock() {
        *guard = Some(session.clone());
    }

    if is_stale(generation) {
        return Outcome::Stop;
    }
    run_socket(app, config, &session, generation, announced).await
}

// ── The hub ──────────────────────────────────────────────────────────────────

async fn run_socket(
    app: &AppHandle,
    config: &Config,
    session: &Session,
    generation: u64,
    announced: &mut Option<(&'static str, Option<String>)>,
) -> Outcome {
    let url = ato_hub_url(&session.token);
    let opened = tokio::time::timeout(OPEN_DEADLINE, tokio_tungstenite::connect_async(url)).await;
    let mut stream = match opened {
        Err(_) => return Outcome::Retry { reason: "Server did not answer".into(), was_connected: false },
        Ok(Err(error)) => {
            return Outcome::Retry {
                reason: format!("Could not open the socket: {error}"),
                was_connected: false,
            }
        }
        Ok(Ok((stream, _response))) => stream,
    };

    if stream.send(WsMessage::text(SIGNALR_HANDSHAKE.to_string())).await.is_err() {
        return Outcome::Retry { reason: "Could not greet the server".into(), was_connected: false };
    }

    let mut connected = false;
    let started = Instant::now();
    let mut last_frame = Instant::now();
    let mut last_ping = Instant::now();
    let mut token = session.token.clone();

    loop {
        if is_stale(generation)
            || PAUSED.load(Ordering::Relaxed)
            || !messages::pill_enabled(app, messages::ATO_PILL)
        {
            let _ = stream.close(None).await;
            return Outcome::Stop;
        }

        if !connected && started.elapsed() >= OPEN_DEADLINE {
            return Outcome::Retry { reason: "Server did not answer".into(), was_connected: false };
        }

        if connected && last_ping.elapsed() >= PING_INTERVAL {
            last_ping = Instant::now();
            if stream.send(WsMessage::text(SIGNALR_PING.to_string())).await.is_err() {
                return Outcome::Retry { reason: "Connection closed".into(), was_connected: true };
            }
        }

        // The open socket was authorised when it opened; renewing the token
        // keeps REST calls and the next connection working without a gap.
        if connected && expires_within(&token, REFRESH_LEAD_SECS) {
            match fresh_token(config).await {
                Ok(next) => token = next,
                Err(error) => {
                    forget_session();
                    return Outcome::Retry { reason: error.text, was_connected: true };
                }
            }
        }

        let received = tokio::time::timeout(POLL_SLICE, stream.next()).await;
        let message = match received {
            Err(_) => {
                if last_frame.elapsed() >= IDLE_LIMIT {
                    return Outcome::Retry {
                        reason: "Connection went quiet".into(),
                        was_connected: connected,
                    };
                }
                continue;
            }
            Ok(None) => return Outcome::Retry { reason: "Connection closed".into(), was_connected: connected },
            Ok(Some(Err(error))) => {
                return Outcome::Retry { reason: format!("{error}"), was_connected: connected }
            }
            Ok(Some(Ok(message))) => message,
        };
        last_frame = Instant::now();

        let text: String = match message {
            WsMessage::Text(value) => value.to_string(),
            WsMessage::Binary(bytes) => String::from_utf8_lossy(&bytes).to_string(),
            WsMessage::Ping(payload) => {
                let _ = stream.send(WsMessage::Pong(payload)).await;
                continue;
            }
            WsMessage::Pong(_) | WsMessage::Frame(_) => continue,
            WsMessage::Close(_) => {
                return Outcome::Retry { reason: "Connection closed".into(), was_connected: connected }
            }
        };

        for record in signalr_records(&text) {
            let Ok(value) = serde_json::from_str::<Value>(record) else { continue };

            if !connected {
                // The first record answers the handshake: `{}` or an error.
                if let Some(error) = value.get("error").and_then(Value::as_str) {
                    forget_session();
                    return Outcome::Retry { reason: error.to_string(), was_connected: false };
                }
                connected = true;
                last_ping = Instant::now();
                announce(app, announced, "connected", Some(session.username.clone()));
                log::line(format!("ato: connected, {} workspace(s)", session.memberships.len()));
                continue;
            }

            match value.get("type").and_then(Value::as_i64) {
                Some(1) => {
                    if value.get("target").and_then(Value::as_str) != Some("onConversationUpdated") {
                        continue;
                    }
                    if let Some(argument) = value.pointer("/arguments/0") {
                        handle_update(app, session, &token, argument);
                    }
                }
                Some(7) => {
                    let reason = value
                        .get("error")
                        .and_then(Value::as_str)
                        .unwrap_or("Connection closed")
                        .to_string();
                    return Outcome::Retry { reason, was_connected: true };
                }
                _ => {}
            }
        }
    }
}

fn handle_update(app: &AppHandle, session: &Session, token: &str, argument: &Value) {
    let Some(update) = AtoUpdate::from_value(argument) else { return };

    // Before the rule: your own reply is what makes the customer's next
    // message yours, and it arrives on this same stream.
    match ato_engagement(&update, &session.memberships) {
        AtoEngagement::Engage => set_engaged(&update.conversation_id, true),
        AtoEngagement::Release => set_engaged(&update.conversation_id, false),
        AtoEngagement::Keep => {}
    }
    let key = update.conversation_id.to_lowercase();
    // Any agent speaking settles it on the stream from here on, so an earlier
    // "not yours" answer for this conversation is stale.
    if update.last_message_sender_type == Some(ATO_SENDER_AGENT) {
        if let Ok(mut checked) = ANSWERER_CHECKED.lock() {
            checked.remove(&key);
        }
    }
    let engaged: std::collections::HashSet<String> = ENGAGED
        .lock()
        .map(|map| map.keys().cloned().collect())
        .unwrap_or_default();
    if !ato_should_notify(&update, &session.memberships, &engaged) {
        let ask = ANSWERER_CHECKED
            .lock()
            .map(|mut checked| {
                let ask = ato_needs_answerer_lookup(&update, &session.memberships, &engaged, &checked);
                if ask {
                    checked.insert(key.clone());
                }
                ask
            })
            .unwrap_or(false);
        if ask {
            let app = app.clone();
            let session = session.clone();
            let token = token.to_string();
            let argument = argument.clone();
            tauri::async_runtime::spawn(async move {
                if last_answerer_is_me(&token, &session, &update).await {
                    set_engaged(&update.conversation_id, true);
                    handle_update(&app, &session, &token, &argument);
                }
            });
        }
        return;
    }

    // The same customer message comes back on every later change to the
    // conversation — a queue set, a tag added. Announced once.
    let stamp = update.last_message_on_utc.clone().unwrap_or_default();
    if let Ok(mut announced) = ANNOUNCED.lock() {
        if announced.get(&update.conversation_id) == Some(&stamp) {
            return;
        }
        announced.insert(update.conversation_id.clone(), stamp);
    }

    let membership = session
        .memberships
        .iter()
        .find(|m| Some(m.workspace_id.to_lowercase()) == update.workspace_id.as_ref().map(|w| w.to_lowercase()));
    let mine = match (&update.assigned_to_agent_id, membership) {
        (Some(assigned), Some(m)) => assigned.eq_ignore_ascii_case(&m.agent_id),
        _ => false,
    };
    // The queue is only worth showing when it is why you are being told.
    let channel = if mine {
        None
    } else {
        update.queue_id.as_ref().and_then(|q| session.queue_names.get(&q.to_lowercase()).cloned())
    };

    let app = app.clone();
    let token = token.to_string();
    tauri::async_runtime::spawn(async move {
        let sender = contact_name(&token, update.contact_id.as_deref())
            .await
            .unwrap_or_else(|| "Ato".to_string());
        let body = update
            .last_message_preview
            .clone()
            .unwrap_or_else(|| "\u{1F4CE} Sent a file".to_string());
        let timestamp_ms = update
            .last_message_on_utc
            .as_deref()
            .and_then(iso8601_millis)
            .unwrap_or_else(now_millis);

        messages::emit_message(
            &app,
            messages::MessageEvent {
                id: ato_message_id(&update),
                source: messages::ATO,
                kind: KIND_DIRECT,
                sender,
                channel,
                conversation_id: Some(update.conversation_id.clone()),
                body,
                timestamp_ms,
                link: Some(ato_conversation_link(Some(&update.conversation_id))),
            },
        );
    });
}

// ── Who we are ───────────────────────────────────────────────────────────────

async fn load_session(token: &str, email: &str) -> Result<Session, ClientError> {
    let response = get(token, &format!("{ATO_SUPPORT_SERVICE}/Agents/me")).await?;
    let status = response.status().as_u16();
    match status {
        200 => {}
        401 | 403 => return Err(ClientError::unauthorized("Session expired")),
        other => return Err(ClientError::new(format!("Server returned {other}"))),
    }
    let body: Value = response
        .json()
        .await
        .map_err(|_| ClientError::new("Unexpected response from server"))?;
    let memberships = ato_memberships(&body);
    if memberships.is_empty() {
        return Err(ClientError::new("This account is not an agent in any Ato workspace"));
    }

    // Best effort: a card without a queue name is still a card.
    let mut queue_names = HashMap::new();
    for membership in &memberships {
        let url = format!(
            "{ATO_SUPPORT_SERVICE}/OData/Queues?$filter={}&$select=QueueId,Name",
            percent_encode(&format!("WorkspaceId eq {}", membership.workspace_id))
        );
        let Ok(response) = get(token, &url).await else { continue };
        if response.status().as_u16() != 200 {
            continue;
        }
        let Ok(page) = response.json::<Value>().await else { continue };
        for row in page.get("value").and_then(Value::as_array).into_iter().flatten() {
            if let (Some(id), Some(name)) = (
                row.get("QueueId").and_then(Value::as_str),
                row.get("Name").and_then(Value::as_str),
            ) {
                queue_names.insert(id.to_lowercase(), name.to_string());
            }
        }
    }

    let username = memberships
        .first()
        .and_then(|m| m.display_name.clone())
        .unwrap_or_else(|| email.to_string());
    Ok(Session { token: token.to_string(), memberships, queue_names, username })
}

async fn contact_name(token: &str, contact_id: Option<&str>) -> Option<String> {
    let contact_id = contact_id?;
    if let Some(known) = CONTACTS.lock().ok()?.get(contact_id).cloned() {
        return Some(known);
    }
    let url = format!(
        "{ATO_SUPPORT_SERVICE}/OData/Contacts?$filter={}&$select=ContactId,DisplayName,PhoneE164",
        percent_encode(&format!("ContactId eq {contact_id}"))
    );
    let response = get(token, &url).await.ok()?;
    if response.status().as_u16() != 200 {
        return None;
    }
    let page: Value = response.json().await.ok()?;
    let row = page.pointer("/value/0")?;
    let name = ato_display_name(row.get("DisplayName").and_then(Value::as_str)).or_else(|| {
        row.get("PhoneE164").and_then(Value::as_str).map(|phone| format!("+{phone}"))
    })?;
    if let Ok(mut contacts) = CONTACTS.lock() {
        contacts.insert(contact_id.to_string(), name.clone());
    }
    Some(name)
}

// ── Tokens ───────────────────────────────────────────────────────────────────

/// A token good for at least a few more minutes: the stored one, a refreshed
/// one, or a fresh sign-in, in that order of preference.
async fn fresh_token(config: &Config) -> Result<String, ClientError> {
    if let Some(token) = usable_token() {
        if !expires_within(&token, REFRESH_LEAD_SECS) {
            return Ok(token);
        }
    }
    if let Some(token_id) = secrets::get(messages::ATO_TOKEN_ID_KEY) {
        if let Ok(token) = refresh(&token_id).await {
            return Ok(token);
        }
    }
    wait_for_login_window().await;
    sign_in(config).await
}

fn usable_token() -> Option<String> {
    let token = secrets::get(messages::ATO_TOKEN_KEY)?;
    (!expires_within(&token, USABLE_FOR_SECS)).then_some(token)
}

fn expires_within(token: &str, seconds: i64) -> bool {
    match jwt_expiry_secs(token) {
        Some(exp) => exp - now_millis() / 1_000 <= seconds,
        None => true,
    }
}

async fn sign_in(config: &Config) -> Result<String, ClientError> {
    if let Ok(mut guard) = LAST_LOGIN.lock() {
        *guard = Some(Instant::now());
    }
    let email = ato_normalized_email(&config.email);
    let sent = HTTP
        .post(format!("{ATO_USER_SERVICE}/Auth/Login"))
        .header("Accept", "application/json")
        .header("User-Agent", USER_AGENT)
        .header("Origin", ATO_ACCOUNTS)
        .header("Referer", format!("{ATO_ACCOUNTS}/"))
        .json(&json!({
            "Email": email,
            "Password": ato_password_digest(&email, &config.password),
            "Origin": "actuar",
        }))
        .send()
        .await;
    let response = match sent {
        Ok(response) => response,
        Err(error) => return Err(ClientError::transport(format!("Server unreachable: {error}"))),
    };

    match response.status().as_u16() {
        200 | 201 => store_session(response).await,
        400 | 401 => Err(ClientError::new("Wrong email or password")),
        403 => Err(ClientError::new("This account cannot sign in")),
        429 => Err(ClientError::waiting(
            "Too many sign-in attempts — not a password problem. Try again in a minute.",
            MIN_LOGIN_INTERVAL,
        )),
        status @ 500..=599 => Err(ClientError::waiting(
            format!("Server returned {status}"),
            MIN_LOGIN_INTERVAL,
        )),
        other => Err(ClientError::new(format!("Server returned {other}"))),
    }
}

/// `/Auth/Refresh`: the `TokenId` for a new two-hour token.
async fn refresh(token_id: &str) -> Result<String, ClientError> {
    let mut request = HTTP
        .post(format!("{ATO_USER_SERVICE}/Auth/Refresh"))
        .header("Accept", "application/json")
        .header("User-Agent", USER_AGENT)
        .header("Origin", ATO_APP)
        .header("Referer", format!("{ATO_APP}/"))
        .json(&json!({ "TokenId": token_id, "AppSource": "Actuar" }));
    if let Some(token) = secrets::get(messages::ATO_TOKEN_KEY) {
        request = request.header("Authorization", format!("Bearer {token}"));
    }
    let response = request
        .send()
        .await
        .map_err(|error| ClientError::transport(format!("Server unreachable: {error}")))?;
    match response.status().as_u16() {
        200 | 201 => store_session(response).await,
        _ => Err(ClientError::unauthorized("Session expired")),
    }
}

async fn store_session(response: reqwest::Response) -> Result<String, ClientError> {
    let body: Value = response
        .json()
        .await
        .map_err(|_| ClientError::new("Signed in, but could not read the account"))?;
    // Signed in but handed no token: an account linked to several people asks
    // the browser which one to be, and that is not a choice to make for them.
    let token = body
        .get("Token")
        .and_then(Value::as_str)
        .filter(|t| !t.is_empty())
        .ok_or_else(|| ClientError::new("Signed in, but could not read the account"))?;
    let _ = secrets::set(messages::ATO_TOKEN_KEY, token);
    if let Some(token_id) = body.get("TokenId").and_then(Value::as_str) {
        let _ = secrets::set(messages::ATO_TOKEN_ID_KEY, token_id);
    }
    Ok(token.to_string())
}

fn forget_session() {
    if let Ok(mut guard) = SESSION.lock() {
        *guard = None;
    }
    let _ = secrets::set(messages::ATO_TOKEN_KEY, "");
}

async fn wait_for_login_window() {
    if BYPASS_LOGIN_FLOOR.swap(false, Ordering::SeqCst) {
        return;
    }
    let waited: Option<Duration> = {
        let guard = LAST_LOGIN.lock().ok();
        guard.and_then(|g| g.map(|at| at.elapsed()))
    };
    let Some(waited) = waited else { return };
    let remaining = MIN_LOGIN_INTERVAL.saturating_sub(waited);
    if remaining > Duration::ZERO {
        tokio::time::sleep(remaining).await;
    }
}

// ── Sending ──────────────────────────────────────────────────────────────────

/// The console's own route and body: a `ClientMessageId` it can match its echo
/// against. The reply returns as an update whose last sender is an agent,
/// which the filter drops, so nothing comes back as a card.
async fn post_reply(
    token: &str,
    conversation_id: &str,
    client_id: &str,
    text: &str,
    attachments: &[Value],
) -> Result<(), ClientError> {
    if token.is_empty() {
        return Err(ClientError::unauthorized("Not signed in to Ato"));
    }
    let mut body = json!({ "ClientMessageId": client_id });
    if !text.is_empty() {
        body["Body"] = json!(text);
    }
    if !attachments.is_empty() {
        body["Attachments"] = json!(attachments);
    }
    let sent = HTTP
        .post(format!(
            "{ATO_SUPPORT_SERVICE}/Conversations/{}/messages",
            percent_encode(conversation_id)
        ))
        .header("Accept", "application/json")
        .header("Authorization", format!("Bearer {token}"))
        .header("User-Agent", USER_AGENT)
        .header("Origin", ATO_APP)
        .header("Referer", format!("{ATO_APP}/"))
        .json(&body)
        .send()
        .await;
    let response = match sent {
        Ok(response) => response,
        Err(error) => return Err(ClientError::transport(format!("Could not send: {error}"))),
    };
    match response.status().as_u16() {
        200 | 201 | 204 => Ok(()),
        401 => Err(ClientError::unauthorized("Session expired")),
        403 => Err(ClientError::new("Ato did not let this account reply to that conversation")),
        404 => Err(ClientError::new("That conversation no longer exists in Ato")),
        422 => Err(ClientError::new(
            "Ato refused the reply — the conversation may be closed or assigned to someone else",
        )),
        other => Err(ClientError::new(format!("Server returned {other}"))),
    }
}

/// A version-4-shaped id from the clock, so nothing needs a UUID crate. Only
/// ever compared with itself, by the console, to match a reply to its echo.
fn client_message_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let mixed = nanos ^ (u128::from(clock_jitter()) << 64) ^ 0x9e37_79b9_7f4a_7c15_f39c_c060_5ced_c834;
    let hex = format!("{mixed:032x}");
    format!(
        "{}-{}-4{}-a{}-{}",
        &hex[0..8], &hex[8..12], &hex[13..16], &hex[17..20], &hex[20..32]
    )
}

async fn get(token: &str, url: &str) -> Result<reqwest::Response, ClientError> {
    HTTP.get(url)
        .header("Accept", "application/json")
        .header("Authorization", format!("Bearer {token}"))
        .header("User-Agent", USER_AGENT)
        .header("Origin", ATO_APP)
        .header("Referer", format!("{ATO_APP}/"))
        .send()
        .await
        .map_err(|error| ClientError::transport(format!("Server unreachable: {error}")))
}

// ── Errors ───────────────────────────────────────────────────────────────────

#[derive(Clone, Debug)]
struct ClientError {
    text: String,
    retry_after: Option<Duration>,
    unauthorized: bool,
    transport: bool,
}

impl ClientError {
    fn new(text: impl Into<String>) -> Self {
        Self { text: text.into(), retry_after: None, unauthorized: false, transport: false }
    }
    fn waiting(text: impl Into<String>, retry_after: Duration) -> Self {
        Self { text: text.into(), retry_after: Some(retry_after), unauthorized: false, transport: false }
    }
    fn unauthorized(text: impl Into<String>) -> Self {
        Self { text: text.into(), retry_after: None, unauthorized: true, transport: false }
    }
    fn transport(text: impl Into<String>) -> Self {
        Self { text: text.into(), retry_after: None, unauthorized: false, transport: true }
    }
}

// ── Configuration and small helpers ──────────────────────────────────────────

fn configuration() -> Option<Config> {
    let email = secrets::get(messages::ATO_EMAIL_KEY)?;
    let password = secrets::get(messages::ATO_PASSWORD_KEY)?;
    Some(Config { email, password })
}

fn is_stale(generation: u64) -> bool {
    GENERATION.load(Ordering::SeqCst) != generation
}

async fn sleep_unless_stale(total: Duration, generation: u64) -> bool {
    let mut left = total;
    while left > Duration::ZERO {
        if is_stale(generation) {
            return false;
        }
        let slice = if left < POLL_SLICE { left } else { POLL_SLICE };
        tokio::time::sleep(slice).await;
        left = left.saturating_sub(slice);
    }
    !is_stale(generation)
}

fn announce(
    app: &AppHandle,
    announced: &mut Option<(&'static str, Option<String>)>,
    state: &'static str,
    detail: Option<String>,
) {
    let next = (state, detail);
    if announced.as_ref() == Some(&next) {
        return;
    }
    messages::emit_status(app, messages::ATO, next.0, next.1.clone());
    *announced = Some(next);
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Days from 1970-01-01 to a proleptic-Gregorian date (Howard Hinnant's
/// `days_from_civil`).
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let year_of_era = year - era * 400;
    let shifted_month = (month + 9) % 12;
    let day_of_year = (153 * shifted_month + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

/// `2026-11-15T19:33:53Z` and `…19:33:54.8855382Z` — .NET writes up to seven
/// fractional digits; the first three are kept. Always UTC from Ato.
fn iso8601_millis(text: &str) -> Option<i64> {
    let text = text.trim().trim_end_matches(['Z', 'z']);
    let (date, clock) = text.split_once('T')?;
    let mut d = date.split('-');
    let year: i64 = d.next()?.parse().ok()?;
    let month: i64 = d.next()?.parse().ok()?;
    let day: i64 = d.next()?.parse().ok()?;
    let mut c = clock.split(':');
    let hour: i64 = c.next()?.parse().ok()?;
    let minute: i64 = c.next()?.parse().ok()?;
    let seconds = c.next().unwrap_or("0");
    let (whole, fraction) = seconds.split_once('.').unwrap_or((seconds, ""));
    let second: i64 = whole.parse().ok()?;
    let mut millis: i64 = 0;
    for (index, character) in fraction.chars().take(3).enumerate() {
        millis += i64::from(character.to_digit(10)?) * 10i64.pow(2 - index as u32);
    }
    let secs = days_from_civil(year, month, day) * 86_400 + hour * 3_600 + minute * 60 + second;
    Some(secs * 1_000 + millis)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_dotnet_timestamps() {
        assert_eq!(iso8601_millis("2026-11-15T19:33:53Z"), Some(1_794_771_233_000));
        assert_eq!(iso8601_millis("2026-11-15T19:33:54.8855382Z"), Some(1_794_771_234_885));
        assert_eq!(iso8601_millis("not a date"), None);
    }

    #[test]
    fn client_message_ids_look_like_uuids() {
        let id = client_message_id();
        assert_eq!(id.len(), 36);
        assert_eq!(id.matches('-').count(), 4);
        assert_eq!(&id[14..15], "4");
    }
}
