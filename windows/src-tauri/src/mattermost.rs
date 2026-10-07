// Mattermost — the Rust side of MattermostClient.swift.
//
// Talks to a Mattermost server directly over its v4 REST + WebSocket API. There
// is no helper daemon: username and password go in, `posted` events come out,
// and the island owns the badge, the sound and the pop-up.
//
// Everything decided purely by its inputs — address normalisation, the backoff
// curve, which posts are worth the notch — lives in `message_proto`, where it is
// unit-tested. What is left here is the part that needs a socket and a clock.
//
// Three details are worth knowing before changing anything:
//
//   * the session token comes back in the **`Token` response header** of
//     `/users/login`, not in the body, which is the User;
//   * we are not connected when the socket opens. Mattermost only confirms the
//     authentication challenge by sending `hello`, and claiming success earlier
//     shows a green dot to someone whose password is about to be rejected;
//   * `data.post` and `data.mentions` arrive as JSON **strings** inside the
//     event and need a second decode.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{LazyLock, Mutex};
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use tauri::AppHandle;
use tokio_tungstenite::tungstenite::Message as WsMessage;

use crate::log;
use crate::message_proto as proto;
use crate::messages;
use crate::secrets;

// ── Timings, matching the Swift client's ─────────────────────────────────────

const REQUEST_TIMEOUT: Duration = Duration::from_secs(20);
/// Our own liveness check: a Wi-Fi drop leaves a read hanging rather than
/// erroring, so something has to go out over the socket on its own.
const PING_INTERVAL: Duration = Duration::from_secs(30);
/// A socket can sit in CONNECTING forever after a sleep — no open, no close, no
/// error, just silence. Without this the client looks alive and receives
/// nothing.
const OPEN_DEADLINE: Duration = Duration::from_secs(20);
/// How long a read waits before we come up for air. This is what makes the ping,
/// the open deadline and `disconnect()` land promptly on a quiet socket.
const READ_TICK: Duration = Duration::from_secs(5);
/// How often the supervisor looks again while the pill is off or unconfigured.
/// Nothing reaches the network on these passes.
const IDLE_POLL: Duration = Duration::from_secs(5);

/// Lets the mm-verificar-style self-test work here too: a message you send
/// yourself carrying this marker is allowed through, so the whole chain —
/// server, socket, filter, notch, sound — can be checked without needing
/// another person to be around.
const SELF_TEST_MARKER: &str = "[mm-notify-autoteste]";

/// Shown when an attachment-only post has no text of its own. A blank peek is
/// worse than saying what happened.
const FILE_ONLY_BODY: &str = "📎 Sent a file";

// ── Lifetime ─────────────────────────────────────────────────────────────────

/// Every attempt gets a number, so a socket we have already walked away from
/// cannot schedule a second reconnect, and `disconnect()` needs nothing but an
/// increment to orphan whatever is in flight.
static GENERATION: AtomicU64 = AtomicU64::new(0);

/// Channels that alert even without a mention, by internal or display name.
/// Empty — the default — means direct messages and mentions only, which is what
/// makes this usable in a busy workspace.
static MONITORED: LazyLock<Mutex<Vec<String>>> = LazyLock::new(|| Mutex::new(Vec::new()));

/// Starts (or restarts) the connection loop.
///
/// Safe to call again: the new generation orphans the previous supervisor, so
/// there is never more than one socket.
pub fn start(app: AppHandle) {
    let generation: u64 = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
    tauri::async_runtime::spawn(async move {
        supervise(app, generation).await;
    });
}

/// Tears the connection down. Nothing reconnects until `start` is called again.
pub fn disconnect() {
    GENERATION.fetch_add(1, Ordering::SeqCst);
}

/// `disconnect`, plus the status the island needs to grey its dot.
pub fn stop(app: &AppHandle) {
    disconnect();
    messages::emit_status(app, messages::MATTERMOST, "disconnected", None);
}

/// Replaces the monitored-channel list. A leading `#` is dropped, because people
/// copy whichever form they are looking at.
pub fn set_monitored_channels(channels: Vec<String>) {
    let cleaned: Vec<String> = channels
        .into_iter()
        .map(|channel| channel.trim().trim_start_matches('#').trim().to_string())
        .filter(|channel| !channel.is_empty())
        .collect();
    if let Ok(mut guard) = MONITORED.lock() {
        *guard = cleaned;
    }
}

pub fn monitored_channels() -> Vec<String> {
    match MONITORED.lock() {
        Ok(guard) => (*guard).clone(),
        Err(_) => Vec::new(),
    }
}

fn current(generation: u64) -> bool {
    GENERATION.load(Ordering::SeqCst) == generation
}

// ── Supervisor ───────────────────────────────────────────────────────────────

/// How a session ended, and therefore what the supervisor does next.
enum Outcome {
    /// This supervisor has been replaced, or the app is shutting down.
    Stopped,
    /// The pill went off, or the app was paused. Go back to waiting, quietly.
    Idle,
    /// Wrong credentials will not fix themselves. Stop, rather than hammer the
    /// server until it rate-limits us.
    Fatal(String),
    Retry { reason: String, saw_hello: bool },
}

async fn supervise(app: AppHandle, generation: u64) {
    let mut attempt: u32 = 0;
    let mut announced_idle: bool = false;

    loop {
        if !current(generation) {
            return;
        }

        // A source that is off holds no socket and makes no request — the same
        // rule `integrations::spawn` follows, for the same reason.
        if !ready(&app) {
            if !announced_idle {
                announced_idle = true;
                messages::emit_status(&app, messages::MATTERMOST, "disconnected", None);
            }
            tokio::time::sleep(IDLE_POLL).await;
            continue;
        }
        announced_idle = false;

        match session(&app, generation).await {
            Outcome::Stopped => return,
            Outcome::Idle => {
                attempt = 0;
            }
            Outcome::Fatal(reason) => {
                log::line(format!("mattermost: {reason}"));
                messages::emit_status(&app, messages::MATTERMOST, "failed", Some(reason));
                return;
            }
            Outcome::Retry { reason, saw_hello } => {
                // A session that got as far as `hello` was a working one; only a
                // run of failures should push the delay up.
                if saw_hello {
                    attempt = 0;
                }
                log::line(format!("mattermost: {reason}"));
                messages::emit_status(&app, messages::MATTERMOST, "failed", Some(reason));

                let delay: Duration = proto::backoff_delay(attempt, proto::clock_jitter());
                attempt = attempt.saturating_add(1);
                tokio::time::sleep(delay).await;
            }
        }
    }
}

/// True when the user has switched the pill on, the app is not paused, and there
/// is something to connect to.
fn ready(app: &AppHandle) -> bool {
    if crate::integrations::PAUSED.load(Ordering::Relaxed) {
        return false;
    }
    if !messages::pill_enabled(app, messages::MATTERMOST_PILL) {
        return false;
    }
    credentials().is_some()
}

/// The server address, login and password, or None when any of the three is
/// missing. Reported as "not configured" rather than as a failure.
fn credentials() -> Option<(String, String, String)> {
    let raw_base: String = secrets::get(messages::MATTERMOST_URL_KEY)?;
    let base: String = proto::normalized_base(&raw_base)?;
    let login: String = secrets::get(messages::MATTERMOST_LOGIN_KEY)?;
    let password: String = secrets::get(messages::MATTERMOST_PASSWORD_KEY)?;
    Some((base, login, password))
}

// ── One session ──────────────────────────────────────────────────────────────

/// Everything a running connection needs to turn an event into a message.
struct Session {
    base: String,
    token: String,
    own_id: String,
    username: String,
    /// Team id → URL slug, for permalinks.
    team_slugs: HashMap<String, String>,
    fallback_team: Option<String>,
}

async fn session(app: &AppHandle, generation: u64) -> Outcome {
    let Some((base, login, password)) = credentials() else {
        return Outcome::Fatal("Enter the server address, username and password".to_string());
    };

    messages::emit_status(app, messages::MATTERMOST, "connecting", None);

    let http: reqwest::Client = client();
    let session: Session = match open_session(&http, &base, &login, &password).await {
        Ok(session) => session,
        Err(err) => {
            return if err.fatal {
                Outcome::Fatal(err.text)
            } else {
                Outcome::Retry { reason: err.text, saw_hello: false }
            };
        }
    };

    if !current(generation) {
        return Outcome::Stopped;
    }

    let ws_url: String = format!("{}/api/v4/websocket", proto::websocket_scheme(&session.base));
    let stream = match tokio_tungstenite::connect_async(ws_url).await {
        Ok((stream, _response)) => stream,
        // Never the error text: a self-hosted address can carry credentials.
        Err(_) => {
            return Outcome::Retry { reason: "Server unreachable".to_string(), saw_hello: false }
        }
    };
    let (mut write, mut read) = stream.split();

    // The token goes in the challenge, not in an upgrade header: sending both
    // makes an authentication failure ambiguous.
    let challenge: String = json!({
        "seq": 1,
        "action": "authentication_challenge",
        "data": { "token": session.token.clone() }
    })
    .to_string();
    if write.send(WsMessage::text(challenge)).await.is_err() {
        return Outcome::Retry { reason: "Could not authenticate".to_string(), saw_hello: false };
    }

    // Still connecting. Only `hello` makes this connected.
    let mut saw_hello: bool = false;
    let opened_at = tokio::time::Instant::now();
    let mut last_ping = tokio::time::Instant::now();

    loop {
        if !current(generation) {
            return Outcome::Stopped;
        }
        if !ready(app) {
            messages::emit_status(app, messages::MATTERMOST, "disconnected", None);
            return Outcome::Idle;
        }

        match tokio::time::timeout(READ_TICK, read.next()).await {
            // Nothing arrived in this tick, which is the normal case.
            Err(_elapsed) => {
                if !saw_hello && opened_at.elapsed() >= OPEN_DEADLINE {
                    return Outcome::Retry {
                        reason: "Server did not answer".to_string(),
                        saw_hello: false,
                    };
                }
                if last_ping.elapsed() >= PING_INTERVAL {
                    last_ping = tokio::time::Instant::now();
                    if write.send(WsMessage::Ping(Default::default())).await.is_err() {
                        return Outcome::Retry {
                            reason: "Connection lost".to_string(),
                            saw_hello,
                        };
                    }
                }
            }
            Ok(None) | Ok(Some(Err(_))) => {
                return Outcome::Retry { reason: "Connection lost".to_string(), saw_hello };
            }
            Ok(Some(Ok(message))) => {
                let text: String = match message {
                    WsMessage::Text(text) => text.to_string(),
                    WsMessage::Binary(bytes) => String::from_utf8_lossy(&bytes).to_string(),
                    WsMessage::Close(_) => {
                        return Outcome::Retry {
                            reason: "Connection lost".to_string(),
                            saw_hello,
                        };
                    }
                    // Ping, pong and raw frames: tungstenite answers pings for
                    // us on the next read.
                    _ => continue,
                };

                match handle_frame(app, &session, &text) {
                    Incoming::Hello => {
                        if !saw_hello {
                            saw_hello = true;
                            log::line("mattermost: connected");
                            messages::emit_status(
                                app,
                                messages::MATTERMOST,
                                "connected",
                                Some(session.username.clone()),
                            );
                        }
                    }
                    Incoming::AuthFailed(reason) => {
                        // The stored session was refused. Drop it so the next
                        // attempt logs in from the password instead of replaying
                        // a dead token.
                        let _ = secrets::set(messages::MATTERMOST_TOKEN_KEY, "");
                        return Outcome::Fatal(reason);
                    }
                    Incoming::Ignored => {}
                }
            }
        }
    }
}

// ── Events ───────────────────────────────────────────────────────────────────

enum Incoming {
    Ignored,
    Hello,
    AuthFailed(String),
}

fn handle_frame(app: &AppHandle, session: &Session, text: &str) -> Incoming {
    let Ok(frame) = serde_json::from_str::<Value>(text) else {
        return Incoming::Ignored;
    };

    let event: Option<&str> = frame.get("event").and_then(Value::as_str);

    // A reply to an action — the authentication challenge, for instance —
    // carries no `event`, which is how it is told apart from a real event.
    if event.is_none() {
        let status: Option<&str> = frame.get("status").and_then(Value::as_str);
        let error: Option<&Value> = frame.get("error");
        if status == Some("FAIL") || error.is_some() {
            let reason: String = error
                .and_then(|value| value.get("message"))
                .and_then(Value::as_str)
                .filter(|message| !message.is_empty())
                .unwrap_or("Authentication failed")
                .to_string();
            return Incoming::AuthFailed(reason);
        }
        return Incoming::Ignored;
    }

    if event == Some("hello") {
        return Incoming::Hello;
    }
    if event != Some("posted") {
        return Incoming::Ignored;
    }

    let Some(data) = frame.get("data") else {
        return Incoming::Ignored;
    };
    // `post` is a JSON string inside the event, not an object.
    let Some(post) = proto::decode_nested_json(data.get("post").and_then(Value::as_str)) else {
        return Incoming::Ignored;
    };

    let id: String = post.get("id").and_then(Value::as_str).unwrap_or_default().to_string();
    if id.is_empty() {
        return Incoming::Ignored;
    }

    let sender_id: &str = post.get("user_id").and_then(Value::as_str).unwrap_or_default();
    let message_text: &str = post.get("message").and_then(Value::as_str).unwrap_or_default();
    let post_type: Option<&str> = post.get("type").and_then(Value::as_str);
    let channel_type: Option<&str> = data.get("channel_type").and_then(Value::as_str);
    let channel_name: Option<&str> = data.get("channel_name").and_then(Value::as_str);
    let channel_display_name: Option<&str> =
        data.get("channel_display_name").and_then(Value::as_str);

    // `mentions` is a JSON string too, and absent when nobody is mentioned.
    let mentions: Vec<String> =
        match proto::decode_nested_json(data.get("mentions").and_then(Value::as_str)) {
            Some(Value::Array(items)) => items
                .iter()
                .filter_map(|item| item.as_str().map(|id| id.to_string()))
                .collect(),
            _ => Vec::new(),
        };

    let monitored: Vec<String> = monitored_channels();

    let kind: &'static str = if sender_id == session.own_id.as_str() {
        // Never alert on your own messages — including ones sent from another
        // device, which arrive over this same socket. The self-test marker is
        // the single exception.
        if message_text.contains(SELF_TEST_MARKER) {
            proto::KIND_DIRECT
        } else {
            return Incoming::Ignored;
        }
    } else {
        match proto::classify_post(
            sender_id,
            &session.own_id,
            post_type,
            channel_type,
            channel_name,
            channel_display_name,
            &mentions,
            &monitored,
        ) {
            Some(kind) => kind,
            // An ordinary message in an ordinary channel stays silent.
            None => return Incoming::Ignored,
        }
    };

    let trimmed: &str = message_text.trim();
    let body: String = if !trimmed.is_empty() {
        trimmed.to_string()
    } else if post
        .get("file_ids")
        .and_then(Value::as_array)
        .map(|files| !files.is_empty())
        .unwrap_or(false)
    {
        FILE_ONLY_BODY.to_string()
    } else {
        // Neither text nor files: nothing worth opening the notch for.
        return Incoming::Ignored;
    };

    let sender: String = post
        .get("props")
        .and_then(|props| props.get("override_username"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .map(|name| name.to_string())
        .or_else(|| {
            data.get("sender_name")
                .and_then(Value::as_str)
                .map(|name| name.trim_matches(|c: char| c == '@' || c.is_whitespace()).to_string())
                .filter(|name| !name.is_empty())
        })
        .unwrap_or_else(|| "Mattermost".to_string());

    let is_direct: bool = kind == proto::KIND_DIRECT;
    let channel: Option<String> = if is_direct {
        // The sender is the conversation; a channel name would be noise.
        None
    } else {
        channel_display_name
            .map(str::trim)
            .filter(|name| !name.is_empty())
            .map(|name| name.to_string())
    };

    let conversation_id: Option<String> = post
        .get("channel_id")
        .and_then(Value::as_str)
        .filter(|channel_id| !channel_id.is_empty())
        .map(|channel_id| channel_id.to_string());

    // Mattermost stamps in milliseconds, which is already what JS `Date` wants.
    let timestamp_ms: i64 = post.get("create_at").and_then(Value::as_i64).unwrap_or_else(now_ms);

    let link: Option<String> =
        permalink(session, data.get("team_id").and_then(Value::as_str), &id);

    messages::emit_message(
        app,
        messages::MessageEvent {
            id,
            source: messages::MATTERMOST,
            kind,
            sender,
            channel,
            conversation_id,
            body,
            timestamp_ms,
            link,
        },
    );

    Incoming::Ignored
}

/// `{server}/{team}/pl/{post}`. A direct message carries no team id, but the
/// permalink route resolves the post whichever team slug is in the path.
fn permalink(session: &Session, team_id: Option<&str>, post_id: &str) -> Option<String> {
    let slug: String = team_id
        .map(str::trim)
        .filter(|id| !id.is_empty())
        .and_then(|id| session.team_slugs.get(id).cloned())
        .or_else(|| session.fallback_team.clone())?;
    Some(format!("{}/{}/pl/{}", session.base, slug, post_id))
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as i64)
        .unwrap_or(0)
}

// ── REST ─────────────────────────────────────────────────────────────────────

struct ClientError {
    text: String,
    /// Nothing we retry will help — wrong password, wrong address.
    fatal: bool,
    /// The token was refused, so a caller holding one may log in again.
    unauthorized: bool,
}

impl ClientError {
    fn fatal(text: &str) -> Self {
        Self { text: text.to_string(), fatal: true, unauthorized: false }
    }

    fn retry(text: &str) -> Self {
        Self { text: text.to_string(), fatal: false, unauthorized: false }
    }

    fn unauthorized(text: &str) -> Self {
        Self { text: text.to_string(), fatal: false, unauthorized: true }
    }

    fn status(code: u16) -> Self {
        Self { text: format!("Server returned {code}"), fatal: false, unauthorized: false }
    }
}

fn client() -> reqwest::Client {
    reqwest::Client::builder().timeout(REQUEST_TIMEOUT).build().unwrap_or_default()
}

/// Reuses the stored session while it lasts; a Mattermost session is good for
/// about a month, so logging in on every launch would be rude to the server.
async fn open_session(
    http: &reqwest::Client,
    base: &str,
    login: &str,
    password: &str,
) -> Result<Session, ClientError> {
    if let Some(stored) = secrets::get(messages::MATTERMOST_TOKEN_KEY) {
        match fetch_me(http, base, &stored).await {
            Ok(Some((own_id, username))) => {
                let (team_slugs, fallback_team) = load_teams(http, base, &stored).await;
                return Ok(Session {
                    base: base.to_string(),
                    token: stored,
                    own_id,
                    username,
                    team_slugs,
                    fallback_team,
                });
            }
            // Expired or revoked: fall through to a fresh login.
            Ok(None) => {}
            Err(err) => return Err(err),
        }
    }

    let token: String = log_in(http, base, login, password).await?;
    let Some((own_id, username)) = fetch_me(http, base, &token).await? else {
        return Err(ClientError::fatal("Signed in, but the server would not accept the session"));
    };
    let (team_slugs, fallback_team) = load_teams(http, base, &token).await;
    Ok(Session { base: base.to_string(), token, own_id, username, team_slugs, fallback_team })
}

/// POST /api/v4/users/login. The session token comes back in the `Token`
/// response **header**; the body is the User.
async fn log_in(
    http: &reqwest::Client,
    base: &str,
    login: &str,
    password: &str,
) -> Result<String, ClientError> {
    let url: String = format!("{base}/api/v4/users/login");
    let body: Value = json!({ "login_id": login, "password": password });

    let response = match http.post(&url).json(&body).send().await {
        Ok(response) => response,
        // Never the error text: it carries the address, which may hold a secret.
        Err(_) => return Err(ClientError::retry("Server unreachable")),
    };

    match response.status().as_u16() {
        200 => {}
        401 => return Err(ClientError::fatal("Wrong username or password")),
        403 => {
            return Err(ClientError::fatal(
                "This account cannot sign in — it may be locked or need MFA",
            ))
        }
        404 => return Err(ClientError::fatal("No Mattermost API at that address")),
        429 => return Err(ClientError::retry("The server is rate-limiting us")),
        other => return Err(ClientError::status(other)),
    }

    let token: String = response
        .headers()
        .get("Token")
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
        .filter(|token| !token.is_empty())
        .unwrap_or_default()
        .to_string();
    if token.is_empty() {
        return Err(ClientError::fatal("Signed in, but the server sent no session token"));
    }

    // A month of not asking for the password again.
    let _ = secrets::set(messages::MATTERMOST_TOKEN_KEY, &token);
    Ok(token)
}

/// GET /api/v4/users/me. `Ok(None)` means the token is no longer good, so the
/// caller logs in again rather than treating it as a failure.
async fn fetch_me(
    http: &reqwest::Client,
    base: &str,
    token: &str,
) -> Result<Option<(String, String)>, ClientError> {
    if token.is_empty() {
        return Ok(None);
    }
    let url: String = format!("{base}/api/v4/users/me");

    let response = match http
        .get(&url)
        .header("Authorization", format!("Bearer {token}"))
        .send()
        .await
    {
        Ok(response) => response,
        Err(_) => return Err(ClientError::retry("Server unreachable")),
    };

    match response.status().as_u16() {
        200 => {}
        401 | 403 => return Ok(None),
        404 => return Err(ClientError::fatal("No Mattermost API at that address")),
        other => return Err(ClientError::status(other)),
    }

    let Ok(user) = response.json::<Value>().await else {
        return Err(ClientError::fatal("That address did not answer like a Mattermost server"));
    };
    let own_id: String = user.get("id").and_then(Value::as_str).unwrap_or_default().to_string();
    if own_id.is_empty() {
        return Err(ClientError::fatal("That address did not answer like a Mattermost server"));
    }
    let username: String =
        user.get("username").and_then(Value::as_str).unwrap_or_default().to_string();

    Ok(Some((own_id, username)))
}

/// Best effort: teams only affect permalinks, so every failure here is silent.
async fn load_teams(
    http: &reqwest::Client,
    base: &str,
    token: &str,
) -> (HashMap<String, String>, Option<String>) {
    let mut slugs: HashMap<String, String> = HashMap::new();
    let mut fallback: Option<String> = None;

    let url: String = format!("{base}/api/v4/users/me/teams");
    let Ok(response) = http
        .get(&url)
        .header("Authorization", format!("Bearer {token}"))
        .send()
        .await
    else {
        return (slugs, fallback);
    };
    if !response.status().is_success() {
        return (slugs, fallback);
    }
    let Ok(Value::Array(teams)) = response.json::<Value>().await else {
        return (slugs, fallback);
    };

    for team in teams {
        let id: &str = team.get("id").and_then(Value::as_str).unwrap_or_default();
        // The URL slug, not the display name.
        let name: &str = team.get("name").and_then(Value::as_str).unwrap_or_default();
        if id.is_empty() || name.is_empty() {
            continue;
        }
        if fallback.is_none() {
            fallback = Some(name.to_string());
        }
        slugs.entry(id.to_string()).or_insert_with(|| name.to_string());
    }

    (slugs, fallback)
}

/// Posts a reply into a channel, for the reply box on the notification card.
///
/// A stored session lasts about a month, so it may well be stale by the time
/// someone answers — a 401 logs in again and retries once rather than handing
/// back a failure the person can do nothing about, with their card still open.
pub async fn send_reply(channel_id: String, message: String) -> Result<(), String> {
    let text: String = message.trim().to_string();
    if text.is_empty() {
        return Ok(());
    }
    let channel_id: String = channel_id.trim().to_string();
    if channel_id.is_empty() {
        return Err("No conversation to reply to".to_string());
    }

    let Some((base, login, password)) = credentials() else {
        return Err("Mattermost is not configured".to_string());
    };
    let http: reqwest::Client = client();
    let token: String = secrets::get(messages::MATTERMOST_TOKEN_KEY).unwrap_or_default();

    match post_message(&http, &base, &token, &channel_id, &text).await {
        Ok(()) => return Ok(()),
        Err(err) => {
            if !err.unauthorized {
                return Err(err.text);
            }
        }
    }

    let fresh: String = log_in(&http, &base, &login, &password).await.map_err(|err| err.text)?;
    post_message(&http, &base, &fresh, &channel_id, &text).await.map_err(|err| err.text)
}

async fn post_message(
    http: &reqwest::Client,
    base: &str,
    token: &str,
    channel_id: &str,
    message: &str,
) -> Result<(), ClientError> {
    if token.is_empty() {
        return Err(ClientError::unauthorized("Not signed in"));
    }
    let url: String = format!("{base}/api/v4/posts");
    let body: Value = json!({ "channel_id": channel_id, "message": message });

    let response = match http
        .post(&url)
        .header("Authorization", format!("Bearer {token}"))
        .json(&body)
        .send()
        .await
    {
        Ok(response) => response,
        Err(_) => return Err(ClientError::retry("Could not reach the server")),
    };

    match response.status().as_u16() {
        200 | 201 => Ok(()),
        401 | 403 => Err(ClientError::unauthorized("Session expired")),
        other => Err(ClientError::status(other)),
    }
}
