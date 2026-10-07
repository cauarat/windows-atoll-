// ClickMassa — the Rust port of ClickMassaClient.swift.
//
// A ClickMassa tenant speaks two protocols: a REST API for signing in and for
// sending, and a Socket.IO v5 socket that pushes every message in the company.
// This file is the running half; everything decided purely by its inputs lives
// in `message_proto`, where it is unit-tested.
//
// Three things in here were learned the hard way and are not decoration:
//
// 1. **The filter.** The socket carries every ticket in the tenant, belonging to
//    every agent. `message_proto::should_notify` is what keeps the notch from
//    opening dozens of times a minute.
//
// 2. **Reconnecting must not re-run the login.** The session is held and reused.
//    A socket that would not stay up used to POST `/auth/login` at 1s, 2s, 4s,
//    8s… until the server answered 429 — which reads exactly like a wrong
//    password and sent someone retyping one that was never in question. Signing
//    in happens at most once a minute however badly the socket behaves.
//
// 3. **The browser-shaped headers.** The panel is a web app, so the API sees a
//    browser. Bot protection in front of a login route turns away anything with
//    no `User-Agent`.
//
// Nothing here connects, and nothing reaches the network, until the user has
// switched the ClickMassa pill on and stored an address, an email and a
// password.

use std::collections::{HashMap, HashSet};
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
    backoff_delay, clickmassa_api_base, clock_jitter, normalized_base, parse_socket_frame,
    should_notify, websocket_scheme, ClickMassaTicket, SocketFrame, KIND_DIRECT, SOCKET_CONNECT,
    SOCKET_PONG,
};
use crate::messages;
use crate::secrets;

// ── Timings, matching the Swift client's ─────────────────────────────────────

/// How long a REST call may take before it counts as unreachable.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(20);

/// How long the socket has to answer the handshake before the attempt is
/// written off.
const OPEN_DEADLINE: Duration = Duration::from_secs(20);

/// A socket with nothing at all on it for this long is dead, whatever the TCP
/// layer still believes. Engine.IO pings every 25s by default, so a minute of
/// silence is already two missed pings.
const IDLE_LIMIT: Duration = Duration::from_secs(60);

/// How often the receive loop comes up for air to re-check the pill, the pause
/// switch and `disconnect()`. Short enough that switching the pill off feels
/// immediate.
const POLL_SLICE: Duration = Duration::from_secs(2);

/// How often the supervisor looks again while the pill is off.
const IDLE_POLL: Duration = Duration::from_secs(5);

/// How often the supervisor looks again while there are no credentials.
const UNCONFIGURED_POLL: Duration = Duration::from_secs(15);

/// The floor between two sign-ins. See the note at the top of this file: this
/// single constant is what stands between a flapping socket and a 429.
const MIN_LOGIN_INTERVAL: Duration = Duration::from_secs(60);

/// How long a server-imposed wait can be before it stops being something the
/// client sits through on its own.
const MAX_UNATTENDED_RETRY: Duration = Duration::from_secs(15 * 60);

/// The panel itself is a web app, so the API sees a browser. A request with no
/// `User-Agent` is the shape bot protection rejects out of hand.
const USER_AGENT: &str =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) \
     Chrome/124.0.0.0 Safari/537.36";

// ── State ────────────────────────────────────────────────────────────────────

/// Who we are, from the login response.
///
/// Held in memory so reconnecting the socket can reuse the session rather than
/// signing in again. A relaunch costs one login, which is the price of not
/// keeping the account on disk.
#[derive(Clone, Debug)]
struct Session {
    user_id: i64,
    tenant_id: i64,
    username: String,
    token: String,
    queue_ids: HashSet<i64>,
    queue_names: HashMap<i64, String>,
}

/// The non-secret-but-still-stored half of the configuration.
#[derive(Clone, Debug, PartialEq, Eq)]
struct Config {
    /// The panel address, as the user pasted it, normalised.
    panel: String,
    email: String,
    password: String,
}

/// Bumped by `disconnect()` and by every `start()`. A task whose generation is
/// no longer the current one unwinds at its next check, which is how a
/// synchronous `disconnect()` stops an async loop without a channel.
static GENERATION: AtomicU64 = AtomicU64::new(0);

/// Whether the last thing asked for was a stop rather than a restart.
///
/// A supervisor that finds itself stale cannot tell on its own whether
/// `disconnect()` retired it or a fresh `start()` replaced it, and announcing
/// "disconnected" in the second case would stamp over the new supervisor's
/// "connecting".
static STOPPED: AtomicBool = AtomicBool::new(true);

static SESSION: Mutex<Option<Session>> = Mutex::new(None);

/// When the last sign-in was actually sent, for `MIN_LOGIN_INTERVAL`.
static LAST_LOGIN: Mutex<Option<Instant>> = Mutex::new(None);

/// A person pressing Sign In has earned an immediate attempt — correcting a
/// typo must not wait out a cooldown meant for the reconnect loop.
static BYPASS_LOGIN_FLOOR: AtomicBool = AtomicBool::new(false);

static HTTP: LazyLock<reqwest::Client> = LazyLock::new(|| {
    reqwest::Client::builder()
        .timeout(REQUEST_TIMEOUT)
        .build()
        .unwrap_or_default()
});

// ── Public surface ───────────────────────────────────────────────────────────

/// Starts the ClickMassa supervisor.
///
/// Safe to call at boot: it connects nothing until the pill is on and the
/// credentials are there, and it keeps watching for both. Calling it again
/// replaces the running supervisor rather than adding a second one.
pub fn start(app: AppHandle) {
    // Cleared before the bump, so the supervisor this one replaces reads it as
    // a restart and retires quietly.
    STOPPED.store(false, Ordering::SeqCst);
    let generation = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
    tauri::async_runtime::spawn(async move {
        supervise(app, generation).await;
    });
}

/// Starts the supervisor and lets the next sign-in skip the one-a-minute floor,
/// once.
///
/// Only for a person pressing Sign In. The reconnect loop must never take this
/// door: the floor is the one thing keeping a flapping socket from turning into
/// a login flood.
pub fn sign_in_now(app: AppHandle) {
    BYPASS_LOGIN_FLOOR.store(true, Ordering::SeqCst);
    start(app);
}

/// Stops the supervisor and closes the socket.
///
/// The held session survives, because reconnecting is free and signing in is
/// what the server counts. Use `sign_out` to actually forget it.
pub fn disconnect() {
    // Set before the bump, so the supervisor cannot see itself stale while this
    // still reads as a restart.
    STOPPED.store(true, Ordering::SeqCst);
    GENERATION.fetch_add(1, Ordering::SeqCst);
}

/// Forgets the session and the stored token, then stops.
pub fn sign_out() {
    disconnect();
    invalidate_session();
}

/// Replies to a ticket from the notification card.
///
/// Nothing comes back as a notification: the reply returns on the socket as a
/// `chat:create` with `fromMe: true`, which `should_notify` drops on its first
/// line.
pub async fn send_reply(ticket_id: String, message: String) -> Result<(), String> {
    let text = message.trim().to_string();
    if text.is_empty() {
        return Ok(());
    }
    let ticket_id = ticket_id.trim().to_string();
    if ticket_id.is_empty() {
        return Err("No ticket to reply to".to_string());
    }

    let Some(config) = configuration() else {
        return Err("No ClickMassa server configured".to_string());
    };

    let token = cached_session()
        .map(|session| session.token)
        .or_else(|| secrets::get(messages::CLICKMASSA_TOKEN_KEY))
        .unwrap_or_default();

    match post_reply(&config.panel, &token, &ticket_id, &text).await {
        Ok(()) => Ok(()),
        Err(error) if error.unauthorized => {
            // A session lasts about eight hours, so it can expire between the
            // notification arriving and the reply being typed.
            invalidate_session();
            // Someone is waiting on this one with a card open, so it does not
            // queue behind the reconnect loop's sign-in floor.
            BYPASS_LOGIN_FLOOR.store(true, Ordering::SeqCst);
            let session = obtain_session(&config).await.map_err(|e| e.text)?;
            post_reply(&config.panel, &session.token, &ticket_id, &text)
                .await
                .map_err(|e| e.text)
        }
        Err(error) => Err(error.text),
    }
}

// ── Supervisor ───────────────────────────────────────────────────────────────

/// What one attempt ended as.
enum Outcome {
    /// The pill went off, the app was paused, or `disconnect()` was called.
    Stop,
    /// The socket ended. The session is kept: reconnecting says nothing about
    /// the credentials.
    Retry { reason: String, was_connected: bool },
    /// The credentials, the address or the route is wrong. The session is gone.
    Fatal(ClientError),
}

async fn supervise(app: AppHandle, generation: u64) {
    let mut attempt: u32 = 0;
    // Remembered so the same status is not emitted over and over while the
    // supervisor idles on a pill that is off or credentials that are missing.
    let mut announced: Option<(&'static str, Option<String>)> = None;

    loop {
        if is_stale(generation) {
            break;
        }

        if PAUSED.load(Ordering::Relaxed) || !messages::pill_enabled(&app, messages::CLICKMASSA_PILL) {
            announce(&app, &mut announced, "disconnected", None);
            if !sleep_unless_stale(IDLE_POLL, generation).await {
                break;
            }
            continue;
        }

        let Some(config) = configuration() else {
            announce(
                &app,
                &mut announced,
                "failed",
                Some("Add your ClickMassa address, email and password".to_string()),
            );
            if !sleep_unless_stale(UNCONFIGURED_POLL, generation).await {
                break;
            }
            continue;
        };

        announce(&app, &mut announced, "connecting", None);

        match run_attempt(&app, &config, generation, &mut announced).await {
            Outcome::Stop => {
                // Back to the top, which re-reads the pill and the generation.
                continue;
            }
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
                // The session is worthless whatever it was; the next attempt
                // signs in again, still behind the floor.
                invalidate_session();
                attempt = 0;
                announce(&app, &mut announced, "failed", Some(error.text.clone()));
                log::line(format!("clickmassa: {}", error.text));

                // A server that said how long to wait gets waited out — that is
                // how a rate limit clears itself without anyone having to come
                // back and press a button.
                if let Some(wait) = error.retry_after {
                    if wait > Duration::ZERO && wait <= MAX_UNATTENDED_RETRY {
                        // The extra second keeps the retry on the far side of
                        // the window rather than on its edge.
                        if !sleep_unless_stale(wait + Duration::from_secs(1), generation).await {
                            break;
                        }
                        continue;
                    }
                }

                // Otherwise this needs a person: a wrong password does not fix
                // itself, and retrying it on a timer is how a login flood
                // starts. Sit still until the credentials actually change.
                if !park_until_changed(&app, &config, generation).await {
                    break;
                }
            }
        }
    }

    // Retired. Say so only if this was a stop — a `start()` that replaced us
    // has already said "connecting", and stamping "disconnected" over it would
    // leave the island lying about a socket that is opening.
    if STOPPED.load(Ordering::SeqCst) {
        announce(&app, &mut announced, "disconnected", None);
    }
}

/// Waits for the stored credentials to change, or for the pill to go off.
///
/// Returns false when the supervisor should unwind.
async fn park_until_changed(app: &AppHandle, failed_with: &Config, generation: u64) -> bool {
    loop {
        if !sleep_unless_stale(UNCONFIGURED_POLL, generation).await {
            return false;
        }
        if PAUSED.load(Ordering::Relaxed) || !messages::pill_enabled(app, messages::CLICKMASSA_PILL) {
            return true;
        }
        if configuration().as_ref() != Some(failed_with) {
            return true;
        }
    }
}

/// One sign-in-and-listen attempt. Returns when the socket ends or the gating
/// changes.
async fn run_attempt(
    app: &AppHandle,
    config: &Config,
    generation: u64,
    announced: &mut Option<(&'static str, Option<String>)>,
) -> Outcome {
    let session = match obtain_session(config).await {
        Ok(session) => session,
        Err(error) if error.transport => {
            return Outcome::Retry { reason: error.text, was_connected: false }
        }
        Err(error) => return Outcome::Fatal(error),
    };

    if is_stale(generation) {
        return Outcome::Stop;
    }

    run_socket(app, config, &session, generation, announced).await
}

// ── The socket ───────────────────────────────────────────────────────────────

async fn run_socket(
    app: &AppHandle,
    config: &Config,
    session: &Session,
    generation: u64,
    announced: &mut Option<(&'static str, Option<String>)>,
) -> Outcome {
    let Some(url) = socket_url(&config.panel, &session.token) else {
        return Outcome::Fatal(ClientError::new(
            "Could not build a socket URL for this server",
        ));
    };

    let opened = tokio::time::timeout(OPEN_DEADLINE, tokio_tungstenite::connect_async(url)).await;
    let mut stream = match opened {
        Err(_) => {
            return Outcome::Retry {
                reason: "Server did not answer".to_string(),
                was_connected: false,
            }
        }
        Ok(Err(error)) => {
            return Outcome::Retry {
                reason: format!("Could not open the socket: {error}"),
                was_connected: false,
            }
        }
        Ok(Ok((stream, _response))) => stream,
    };

    // The tenant's own room: "{tenantId}:ticketList".
    let ticket_list_event = format!("{}:ticketList", session.tenant_id);
    let mut connected = false;
    let mut logged_unmatched = false;
    let started = Instant::now();
    let mut last_frame = Instant::now();

    loop {
        if is_stale(generation)
            || PAUSED.load(Ordering::Relaxed)
            || !messages::pill_enabled(app, messages::CLICKMASSA_PILL)
        {
            let _ = stream.close(None).await;
            return Outcome::Stop;
        }

        if !connected && started.elapsed() >= OPEN_DEADLINE {
            return Outcome::Retry {
                reason: "Server did not answer".to_string(),
                was_connected: false,
            };
        }

        let received = tokio::time::timeout(POLL_SLICE, stream.next()).await;
        let message = match received {
            // Nothing this slice. Loop so the checks above run again; a socket
            // that goes quiet past IDLE_LIMIT is gone whatever TCP thinks.
            Err(_) => {
                if last_frame.elapsed() >= IDLE_LIMIT {
                    return Outcome::Retry {
                        reason: "Connection went quiet".to_string(),
                        was_connected: connected,
                    };
                }
                continue;
            }
            Ok(None) => {
                return Outcome::Retry {
                    reason: "Connection closed".to_string(),
                    was_connected: connected,
                }
            }
            Ok(Some(Err(error))) => {
                return Outcome::Retry { reason: format!("{error}"), was_connected: connected }
            }
            Ok(Some(Ok(message))) => message,
        };
        last_frame = Instant::now();

        let text: String = match message {
            WsMessage::Text(value) => value.to_string(),
            WsMessage::Binary(bytes) => String::from_utf8_lossy(&bytes).to_string(),
            // The WebSocket-level ping, below Engine.IO's own.
            WsMessage::Ping(payload) => {
                let _ = stream.send(WsMessage::Pong(payload)).await;
                continue;
            }
            WsMessage::Pong(_) | WsMessage::Frame(_) => continue,
            WsMessage::Close(_) => {
                return Outcome::Retry {
                    reason: "Connection closed".to_string(),
                    was_connected: connected,
                }
            }
        };

        // Two Socket.IO packets the shared parser leaves as `Other`, both of
        // which change what happens next rather than merely being ignorable.
        if let Some(body) = text.strip_prefix("44") {
            // CONNECT_ERROR is where a Socket.IO auth middleware turns a bad
            // token away, so the held session is worthless. Dropping it means
            // the next attempt signs in — still behind the sign-in floor, so a
            // server that refuses every token cannot turn this into a flood.
            invalidate_session();
            return Outcome::Retry {
                reason: connect_error_message(body),
                was_connected: connected,
            };
        }
        if text.starts_with("41") {
            return Outcome::Retry {
                reason: "Connection closed".to_string(),
                was_connected: connected,
            };
        }

        match parse_socket_frame(&text) {
            SocketFrame::Open(_) => {
                // Join the default namespace. The token goes in the CONNECT
                // frame as well as the query string: which of the two this
                // build of ClickMassa reads is not documented, and sending both
                // costs nothing.
                let auth = json!({ "token": session.token });
                let frame = format!("{SOCKET_CONNECT}{auth}");
                if stream.send(WsMessage::text(frame)).await.is_err() {
                    return Outcome::Retry {
                        reason: "Could not greet the server".to_string(),
                        was_connected: connected,
                    };
                }
            }
            SocketFrame::Ping => {
                // Not optional: Engine.IO drops a socket that stops answering.
                if stream.send(WsMessage::text(SOCKET_PONG.to_string())).await.is_err() {
                    return Outcome::Retry {
                        reason: "Connection closed".to_string(),
                        was_connected: connected,
                    };
                }
            }
            SocketFrame::Connected => {
                connected = true;
                announce(app, announced, "connected", Some(session.username.clone()));
            }
            SocketFrame::Event { name, payload } => {
                if name == ticket_list_event {
                    if let Some(payload) = payload {
                        handle_ticket_list(app, config, session, &payload);
                    }
                } else if !logged_unmatched {
                    // Once per connection, so a tenant that names its room
                    // differently can be diagnosed without flooding the log.
                    logged_unmatched = true;
                    log::line(format!(
                        "clickmassa: ignoring event '{name}' (listening for '{ticket_list_event}')"
                    ));
                }
            }
            SocketFrame::Pong | SocketFrame::Other => {}
        }
    }
}

/// `{"type": "chat:create", "payload": {…}}`, the argument of the
/// `{tenantId}:ticketList` event.
fn handle_ticket_list(app: &AppHandle, config: &Config, session: &Session, envelope: &Value) {
    if envelope.get("type").and_then(Value::as_str) != Some("chat:create") {
        return;
    }
    let Some(message) = envelope.get("payload") else { return };

    let from_me = message.get("fromMe").and_then(Value::as_bool).unwrap_or(false);
    let ticket = message.get("ticket").map(|raw| ClickMassaTicket {
        user_id: raw.get("userId").and_then(Value::as_i64),
        queue_id: raw.get("queueId").and_then(Value::as_i64),
        status: raw.get("status").and_then(Value::as_str).map(|s| s.to_string()),
    });

    // The whole tenant arrives on this socket. Without this line the notch
    // would show the entire company's conversations.
    if !should_notify(from_me, ticket.as_ref(), Some(session.user_id), &session.queue_ids) {
        return;
    }

    let Some(body) = body_for(message) else { return };

    let sender = text_field(message.pointer("/contact/name"))
        .or_else(|| text_field(message.pointer("/ticket/contact/name")))
        .unwrap_or_else(|| "ClickMassa".to_string());

    // The queue is only worth showing when it is why you are being told — on
    // your own tickets it is noise.
    let assigned_to_me = ticket.as_ref().and_then(|t| t.user_id) == Some(session.user_id);
    let channel: Option<String> = if assigned_to_me {
        None
    } else {
        ticket
            .as_ref()
            .and_then(|t| t.queue_id)
            .and_then(|id| session.queue_names.get(&id).cloned())
    };

    let ticket_id: Option<String> = id_field(message.get("ticketId"))
        .or_else(|| id_field(message.pointer("/ticket/id")));

    let id = id_field(message.get("id")).unwrap_or_else(|| format!("clickmassa-{}", now_millis()));

    let timestamp_ms = message
        .get("createdAt")
        .and_then(Value::as_str)
        .and_then(iso8601_millis)
        .unwrap_or_else(now_millis);

    messages::emit_message(
        app,
        messages::MessageEvent {
            id,
            source: messages::CLICKMASSA,
            kind: KIND_DIRECT,
            sender,
            channel,
            conversation_id: ticket_id.clone(),
            body,
            timestamp_ms,
            link: Some(ticket_link(&config.panel, ticket_id.as_deref())),
        },
    );
}

/// An attachment carries no text; a blank card would say nothing.
fn body_for(message: &Value) -> Option<String> {
    let text = message.get("body").and_then(Value::as_str).unwrap_or("").trim().to_string();
    if !text.is_empty() {
        return Some(text);
    }
    let media = message.get("mediaType").and_then(Value::as_str)?;
    if media == "text" {
        return None;
    }
    Some("\u{1F4CE} Sent a file".to_string())
}

/// The login response lists `atendimento` among the account's routes, so the
/// panel deep-links there. If that guess is wrong the Open button still lands on
/// ClickMassa, which is no worse than not having a link.
fn ticket_link(panel: &str, ticket_id: Option<&str>) -> String {
    match ticket_id {
        Some(id) => format!("{panel}/atendimento/{}", percent_encode(id)),
        None => panel.to_string(),
    }
}

// ── Session and sign-in ──────────────────────────────────────────────────────

/// The session, reused wherever possible.
///
/// This is the fix for the 429. Every attempt used to sign in from scratch, and
/// a socket failure restarts an attempt, so a socket that would not stay up
/// meant a POST to `/auth/login` at 1s, 2s, 4s, 8s… and then twice a minute
/// forever.
async fn obtain_session(config: &Config) -> Result<Session, ClientError> {
    if let Some(session) = cached_session() {
        if !session.token.is_empty() {
            return Ok(session);
        }
    }

    wait_for_login_window().await;

    let session = sign_in(config).await?;
    let _ = secrets::set(messages::CLICKMASSA_TOKEN_KEY, &session.token);
    store_session(session.clone());
    Ok(session)
}

fn cached_session() -> Option<Session> {
    let guard = SESSION.lock().ok()?;
    guard.clone()
}

fn store_session(session: Session) {
    if let Ok(mut guard) = SESSION.lock() {
        *guard = Some(session);
    }
}

/// Forgets the session. Only for a token the server actually refused, or for a
/// deliberate sign-out.
fn invalidate_session() {
    if let Ok(mut guard) = SESSION.lock() {
        *guard = None;
    }
    let _ = secrets::set(messages::CLICKMASSA_TOKEN_KEY, "");
}

/// Holds the next sign-in until `MIN_LOGIN_INTERVAL` has passed.
async fn wait_for_login_window() {
    if BYPASS_LOGIN_FLOOR.swap(false, Ordering::SeqCst) {
        return;
    }
    // The guard is read and dropped before the await: a std Mutex held across
    // one would make this future non-Send.
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

async fn sign_in(config: &Config) -> Result<Session, ClientError> {
    let Some(api) = clickmassa_api_base(&config.panel) else {
        return Err(ClientError::new("Could not derive the API address from that URL"));
    };

    if let Ok(mut guard) = LAST_LOGIN.lock() {
        *guard = Some(Instant::now());
    }

    let sent = HTTP
        .post(format!("{api}/auth/login"))
        .header("Accept", "application/json")
        // The same headers the panel's own login sends. Bot protection in front
        // of a login route routinely turns away anything that does not look
        // like the browser it expects, and 429 is one of the answers it gives.
        .header("User-Agent", USER_AGENT)
        .header("Origin", config.panel.clone())
        .header("Referer", format!("{}/", config.panel))
        .json(&json!({ "email": config.email, "password": config.password }))
        .send()
        .await;

    let response = match sent {
        Ok(response) => response,
        // A network error says nothing about the credentials, so it must not
        // park the supervisor the way a wrong password does.
        Err(error) => return Err(ClientError::transport(format!("Server unreachable: {error}"))),
    };

    let status = response.status().as_u16();
    let retry_after = header(&response, "retry-after");
    let rate_limit_reset = header(&response, "x-ratelimit-reset");

    match status {
        200 | 201 => {
            let body: Value = response
                .json()
                .await
                .map_err(|_| ClientError::new("Signed in, but could not read the account"))?;
            account_from(&body, &config.email)
                .ok_or_else(|| ClientError::new("Signed in, but could not read the account"))
        }
        401 => Err(ClientError::new("Wrong email or password")),
        403 => Err(ClientError::new("This account cannot sign in")),
        // A 404 means the sign-in route is somewhere else on this build, and
        // the message says so rather than leaving it to guesswork.
        404 => Err(ClientError::new(
            "No sign-in endpoint at /auth/login — the route may differ on this server",
        )),
        429 => {
            // Not a credential problem: the server refuses on volume before it
            // ever looks at the password, so this reads the same whether the
            // password is right or wrong. Saying "429" and nothing else sent
            // one person retyping a password that was never in question.
            let wait = retry_delay(retry_after.as_deref(), rate_limit_reset.as_deref());
            Err(ClientError::waiting(rate_limit_message(wait), wait))
        }
        500..=599 => Err(ClientError::waiting(
            format!("The ClickMassa server returned an error ({status})"),
            Some(MIN_LOGIN_INTERVAL),
        )),
        other => Err(ClientError::new(format!("Server returned {other}"))),
    }
}

/// Reads the login response. Lenient on purpose: a build that nests the account
/// under `user` should not read as a broken sign-in.
fn account_from(body: &Value, fallback_username: &str) -> Option<Session> {
    let token = text_field(body.get("token"))
        .or_else(|| text_field(body.pointer("/data/token")))
        .or_else(|| text_field(body.get("accessToken")))?;

    let user_id = body
        .get("userId")
        .and_then(Value::as_i64)
        .or_else(|| body.pointer("/user/id").and_then(Value::as_i64))?;

    let tenant_id = body
        .get("tenantId")
        .and_then(Value::as_i64)
        .or_else(|| body.pointer("/user/tenantId").and_then(Value::as_i64))?;

    let username = text_field(body.get("username"))
        .or_else(|| text_field(body.pointer("/user/name")))
        .unwrap_or_else(|| fallback_username.to_string());

    let raw_queues = body
        .get("queues")
        .or_else(|| body.pointer("/user/queues"))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();

    let mut queue_ids: HashSet<i64> = HashSet::new();
    let mut queue_names: HashMap<i64, String> = HashMap::new();
    for raw in raw_queues.iter() {
        let Some(id) = raw.get("id").and_then(Value::as_i64) else { continue };
        queue_ids.insert(id);
        if let Some(name) = text_field(raw.get("queue")).or_else(|| text_field(raw.get("name"))) {
            queue_names.entry(id).or_insert(name);
        }
    }

    Some(Session { user_id, tenant_id, username, token, queue_ids, queue_names })
}

// ── Sending ──────────────────────────────────────────────────────────────────

async fn post_reply(
    panel: &str,
    token: &str,
    ticket_id: &str,
    text: &str,
) -> Result<(), ClientError> {
    if token.is_empty() {
        return Err(ClientError::unauthorized("Not signed in to ClickMassa"));
    }
    let Some(api) = clickmassa_api_base(panel) else {
        return Err(ClientError::new("Could not derive the API address from that URL"));
    };

    let sent = HTTP
        .post(format!("{api}/messages/{}", percent_encode(ticket_id)))
        .header("Accept", "application/json")
        .header("Authorization", format!("Bearer {token}"))
        .header("User-Agent", USER_AGENT)
        .header("Origin", panel.to_string())
        .header("Referer", format!("{panel}/"))
        // `fromMe` is what puts the message on the company's side of the
        // conversation — without it the panel would show your own reply as if
        // the customer had written it.
        .json(&json!({ "body": text, "fromMe": true, "read": true }))
        .send()
        .await;

    let response = match sent {
        Ok(response) => response,
        Err(error) => return Err(ClientError::transport(format!("Could not send: {error}"))),
    };

    let status = response.status().as_u16();
    let retry_after = header(&response, "retry-after");
    let rate_limit_reset = header(&response, "x-ratelimit-reset");

    match status {
        200 | 201 | 204 => Ok(()),
        401 | 403 => Err(ClientError::unauthorized("Session expired")),
        404 => Err(ClientError::new(format!(
            "No route at /messages/{ticket_id} — sending may live elsewhere on this server"
        ))),
        429 => {
            let wait = retry_delay(retry_after.as_deref(), rate_limit_reset.as_deref());
            Err(ClientError::waiting(rate_limit_message(wait), wait))
        }
        other => Err(ClientError::new(format!("Server returned {other}"))),
    }
}

// ── Errors ───────────────────────────────────────────────────────────────────

#[derive(Clone, Debug)]
struct ClientError {
    text: String,
    /// Set when the server said how long to wait, so the client can sit the wait
    /// out instead of handing the problem back to a person.
    retry_after: Option<Duration>,
    /// The session was refused, so signing in again is worth one attempt.
    unauthorized: bool,
    /// The network failed. Says nothing about the credentials, so the
    /// supervisor retries with backoff rather than parking.
    transport: bool,
}

impl ClientError {
    fn new(text: impl Into<String>) -> Self {
        Self { text: text.into(), retry_after: None, unauthorized: false, transport: false }
    }

    fn waiting(text: impl Into<String>, retry_after: Option<Duration>) -> Self {
        Self { text: text.into(), retry_after, unauthorized: false, transport: false }
    }

    fn unauthorized(text: impl Into<String>) -> Self {
        Self { text: text.into(), retry_after: None, unauthorized: true, transport: false }
    }

    fn transport(text: impl Into<String>) -> Self {
        Self { text: text.into(), retry_after: None, unauthorized: false, transport: true }
    }
}

// ── Rate limiting ────────────────────────────────────────────────────────────

/// How long to wait, from whichever header the server chose to send.
///
/// `Retry-After` is either a count of seconds or an HTTP date; `X-RateLimit-Reset`
/// is either seconds remaining or a Unix timestamp. All four are in the wild, so
/// all four are read here.
fn retry_delay(retry_after: Option<&str>, rate_limit_reset: Option<&str>) -> Option<Duration> {
    if let Some(value) = retry_after.map(str::trim).filter(|v| !v.is_empty()) {
        if let Ok(seconds) = value.parse::<f64>() {
            return seconds_to_duration(seconds);
        }
        if let Some(millis) = http_date_millis(value) {
            return seconds_to_duration((millis - now_millis()) as f64 / 1_000.0);
        }
    }

    if let Some(value) = rate_limit_reset.map(str::trim).filter(|v| !v.is_empty()) {
        if let Ok(number) = value.parse::<f64>() {
            // Past a billion it is a Unix timestamp, not a duration; no rate
            // limit asks anyone to wait thirty years.
            let seconds = if number > 1_000_000_000.0 {
                number - (now_millis() as f64 / 1_000.0)
            } else {
                number
            };
            return seconds_to_duration(seconds);
        }
    }

    None
}

/// `Duration::from_secs_f64` panics on anything that is not a finite,
/// non-negative number, so nothing reaches it unchecked.
fn seconds_to_duration(seconds: f64) -> Option<Duration> {
    if !seconds.is_finite() {
        return None;
    }
    let clamped = seconds.clamp(0.0, 86_400.0);
    Some(Duration::from_secs_f64(clamped))
}

/// Says what 429 means in words, because the number reads as a mystery and gets
/// mistaken for a rejected password.
fn rate_limit_message(retry_after: Option<Duration>) -> String {
    let Some(wait) = retry_after.filter(|d| *d > Duration::ZERO) else {
        return "Too many sign-in attempts — the server is rate-limiting, not rejecting your \
                password. Wait a few minutes before trying again."
            .to_string();
    };
    if wait <= Duration::from_secs(60) {
        return "Too many sign-in attempts — not a password problem. Try again in a minute."
            .to_string();
    }
    let minutes = wait.as_secs().div_ceil(60);
    format!("Too many sign-in attempts — not a password problem. Try again in {minutes} minutes.")
}

// ── Configuration and addresses ──────────────────────────────────────────────

fn configuration() -> Option<Config> {
    let raw = secrets::get(messages::CLICKMASSA_URL_KEY)?;
    let panel = normalized_base(&raw)?;
    let email = secrets::get(messages::CLICKMASSA_EMAIL_KEY)?;
    let password = secrets::get(messages::CLICKMASSA_PASSWORD_KEY)?;
    Some(Config { panel, email, password })
}

fn socket_url(panel: &str, token: &str) -> Option<String> {
    let api = clickmassa_api_base(panel)?;
    let socket = websocket_scheme(&api);
    Some(format!(
        "{socket}/socket.io/?EIO=4&transport=websocket&token={}",
        percent_encode(token)
    ))
}

/// Percent-encodes everything outside RFC 3986's unreserved set. A JWT is
/// already URL-safe, but a token is whatever the server hands out.
fn percent_encode(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for byte in value.as_bytes() {
        let b = *byte;
        if b.is_ascii_alphanumeric() || b == b'-' || b == b'.' || b == b'_' || b == b'~' {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

fn connect_error_message(body: &str) -> String {
    serde_json::from_str::<Value>(body)
        .ok()
        .and_then(|value| text_field(value.get("message")))
        .unwrap_or_else(|| "The server refused the session".to_string())
}

// ── Small helpers ────────────────────────────────────────────────────────────

fn is_stale(generation: u64) -> bool {
    GENERATION.load(Ordering::SeqCst) != generation
}

/// Sleeps in slices so `disconnect()` is felt within a couple of seconds rather
/// than at the end of a thirty-second backoff. Returns false when the caller
/// should unwind.
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

/// Emits a status only when it is not the one already showing.
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
    messages::emit_status(app, messages::CLICKMASSA, next.0, next.1.clone());
    *announced = Some(next);
}

/// A non-blank string field.
fn text_field(value: Option<&Value>) -> Option<String> {
    let text = value?.as_str()?.trim();
    (!text.is_empty()).then(|| text.to_string())
}

/// An id that may arrive as a string or as a number.
fn id_field(value: Option<&Value>) -> Option<String> {
    match value? {
        Value::String(text) => {
            let trimmed = text.trim();
            (!trimmed.is_empty()).then(|| trimmed.to_string())
        }
        Value::Number(number) => Some(number.to_string()),
        _ => None,
    }
}

fn header(response: &reqwest::Response, name: &str) -> Option<String> {
    response.headers().get(name)?.to_str().ok().map(|v| v.to_string())
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

// ── Dates ────────────────────────────────────────────────────────────────────
//
// Two formats, one calendar. A date crate for two parsers that run once per
// message would be a dependency for very little.

/// Days from 1970-01-01 to a proleptic-Gregorian date (Howard Hinnant's
/// `days_from_civil`).
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let year_of_era = year - era * 400; // [0, 399]
    let shifted_month = (month + 9) % 12; // March = 0
    let day_of_year = (153 * shifted_month + 2) / 5 + day - 1; // [0, 365]
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

/// `2023-11-14T15:49:16.256Z`, which is what ClickMassa sends. An explicit
/// ±hh:mm offset is read too; a missing zone is taken as UTC.
fn iso8601_millis(text: &str) -> Option<i64> {
    let text = text.trim();
    let (date_part, rest) = match text.split_once('T') {
        Some(split) => split,
        None => text.split_once(' ')?,
    };

    let mut date = date_part.split('-');
    let year: i64 = date.next()?.trim().parse().ok()?;
    let month: i64 = date.next()?.parse().ok()?;
    let day: i64 = date.next()?.parse().ok()?;

    let (clock, offset_seconds): (&str, i64) = if let Some(stripped) = rest
        .strip_suffix('Z')
        .or_else(|| rest.strip_suffix('z'))
    {
        (stripped, 0)
    } else if let Some(index) = rest.rfind(|c: char| c == '+' || c == '-') {
        let (clock, zone) = rest.split_at(index);
        (clock, parse_utc_offset(zone).unwrap_or(0))
    } else {
        (rest, 0)
    };

    let mut parts = clock.split(':');
    let hour: i64 = parts.next()?.parse().ok()?;
    let minute: i64 = parts.next().unwrap_or("0").parse().unwrap_or(0);
    let seconds_text = parts.next().unwrap_or("0");
    let (whole, fraction) = match seconds_text.split_once('.') {
        Some(split) => split,
        None => (seconds_text, ""),
    };
    let second: i64 = whole.parse().unwrap_or(0);

    // ".256" → 256 ms, ".2" → 200 ms, ".256789" → 256 ms.
    let mut millis: i64 = 0;
    for (index, character) in fraction.chars().take(3).enumerate() {
        let digit = i64::from(character.to_digit(10).unwrap_or(0));
        millis += digit * 10i64.pow(2 - index as u32);
    }

    let seconds =
        days_from_civil(year, month, day) * 86_400 + hour * 3_600 + minute * 60 + second
            - offset_seconds;
    Some(seconds * 1_000 + millis)
}

/// `+03:00`, `-0300`, `+03` → seconds east of UTC.
fn parse_utc_offset(zone: &str) -> Option<i64> {
    let mut characters = zone.chars();
    let sign: i64 = match characters.next()? {
        '+' => 1,
        '-' => -1,
        _ => return None,
    };
    let digits: String = characters.filter(|c| c.is_ascii_digit()).collect();
    if digits.len() < 2 {
        return None;
    }
    let hours: i64 = digits.get(0..2)?.parse().ok()?;
    let minutes: i64 = match digits.get(2..4) {
        Some(text) => text.parse().unwrap_or(0),
        None => 0,
    };
    Some(sign * (hours * 3_600 + minutes * 60))
}

/// `Tue, 14 Nov 2023 22:18:20 GMT`, the other shape of `Retry-After`.
fn http_date_millis(value: &str) -> Option<i64> {
    let value = value.trim();
    let body = match value.split_once(',') {
        Some((_, rest)) => rest.trim(),
        None => value,
    };
    let mut parts = body.split_whitespace();
    let day: i64 = parts.next()?.parse().ok()?;
    let month = month_from_name(parts.next()?)?;
    let year: i64 = parts.next()?.parse().ok()?;

    let mut clock = parts.next()?.split(':');
    let hour: i64 = clock.next()?.parse().ok()?;
    let minute: i64 = clock.next()?.parse().ok()?;
    let second: i64 = clock.next().unwrap_or("0").parse().unwrap_or(0);

    let seconds =
        days_from_civil(year, month, day) * 86_400 + hour * 3_600 + minute * 60 + second;
    Some(seconds * 1_000)
}

fn month_from_name(name: &str) -> Option<i64> {
    const MONTHS: [&str; 12] = [
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
    ];
    let lowered = name.to_ascii_lowercase();
    MONTHS
        .iter()
        .position(|m| lowered.starts_with(m))
        .map(|index| index as i64 + 1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_clickmassa_timestamps() {
        // 2023-11-14T15:49:16.256Z
        assert_eq!(iso8601_millis("2023-11-14T15:49:16.256Z"), Some(1_699_976_956_256));
        assert_eq!(iso8601_millis("2023-11-14T15:49:16Z"), Some(1_699_976_956_000));
        // The same instant written with an offset.
        assert_eq!(iso8601_millis("2023-11-14T12:49:16.256-03:00"), Some(1_699_976_956_256));
        assert_eq!(iso8601_millis("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(iso8601_millis("not a date"), None);
    }

    #[test]
    fn reads_http_dates() {
        assert_eq!(http_date_millis("Tue, 14 Nov 2023 22:18:20 GMT"), Some(1_700_000_300_000));
        assert_eq!(http_date_millis("nonsense"), None);
    }

    #[test]
    fn encodes_what_a_url_cannot_carry() {
        assert_eq!(percent_encode("abc-123_x.y~z"), "abc-123_x.y~z");
        assert_eq!(percent_encode("a/b c+d"), "a%2Fb%20c%2Bd");
    }

    #[test]
    fn builds_the_socket_address() {
        assert_eq!(
            socket_url("https://enterprise-419.clickmassa.com.br", "tok en").as_deref(),
            Some(
                "wss://enterprise-419api.clickmassa.com.br\
                 /socket.io/?EIO=4&transport=websocket&token=tok%20en"
            )
        );
    }

    #[test]
    fn says_what_429_actually_means() {
        assert!(rate_limit_message(None).contains("not rejecting your password"));
        assert!(rate_limit_message(Some(Duration::from_secs(30))).contains("in a minute"));
        assert!(rate_limit_message(Some(Duration::from_secs(300))).contains("5 minutes"));
    }

    #[test]
    fn prefers_whichever_rate_limit_header_arrived() {
        assert_eq!(retry_delay(Some("120"), None), Some(Duration::from_secs(120)));
        assert_eq!(retry_delay(None, Some("45")), Some(Duration::from_secs(45)));
        assert_eq!(retry_delay(None, None), None);
        // Nothing unparseable reaches Duration::from_secs_f64.
        assert_eq!(retry_delay(Some("soon"), Some("also soon")), None);
    }

    #[test]
    fn reads_the_login_response() {
        let body = serde_json::json!({
            "userId": 7,
            "tenantId": 3,
            "username": "Ana",
            "token": "abc",
            "queues": [{ "id": 10, "queue": "Suporte" }, { "id": 11, "queue": "Vendas" }]
        });
        let session = account_from(&body, "ana@example.com").unwrap();
        assert_eq!(session.user_id, 7);
        assert_eq!(session.tenant_id, 3);
        assert_eq!(session.username, "Ana");
        assert!(session.queue_ids.contains(&10) && session.queue_ids.contains(&11));
        assert_eq!(session.queue_names.get(&10).map(String::as_str), Some("Suporte"));
        // No token is not a session.
        assert!(account_from(&serde_json::json!({ "userId": 7, "tenantId": 3 }), "x").is_none());
    }

    #[test]
    fn an_attachment_still_says_something() {
        assert_eq!(body_for(&serde_json::json!({ "body": " oi " })).as_deref(), Some("oi"));
        assert!(body_for(&serde_json::json!({ "body": "", "mediaType": "text" })).is_none());
        assert!(body_for(&serde_json::json!({ "body": "", "mediaType": "image" })).is_some());
        assert!(body_for(&serde_json::json!({})).is_none());
    }
}
