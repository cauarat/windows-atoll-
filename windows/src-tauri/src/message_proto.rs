// The parts of the message clients that are pure functions.
//
// Split out deliberately. Everything here is decided by its inputs alone, so it
// is unit-tested against real frames — and these are the decisions that hurt
// when wrong: get Ato's filter backwards and the notch either stays silent or
// shows the whole company's conversations.
//
// Ported from AtoRules.swift, SignalRConnection.swift and
// MattermostClient.swift.

use std::time::Duration;

use serde_json::Value;

// ── Addresses ────────────────────────────────────────────────────────────────

/// Trims a server address the way someone actually pastes it and returns a base
/// with no trailing slash.
///
/// A missing scheme becomes https. An empty or host-less string returns None,
/// which callers report as "not configured" rather than as a failure.
pub fn normalized_base(raw: &str) -> Option<String> {
    // Order matters: trimming slashes first turns a bare "https://" into
    // "https:", which then looks scheme-less and becomes "https://https:".
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }

    let with_scheme = if trimmed.contains("://") {
        trimmed.to_string()
    } else {
        format!("https://{trimmed}")
    };

    // A host is what makes it an address; without one there is nothing to
    // connect to however well-formed the rest looks.
    url_host(&with_scheme)?;

    let cleaned = with_scheme.trim_end_matches('/').to_string();
    (!cleaned.is_empty()).then_some(cleaned)
}

/// Host of a URL, without pulling in a URL parser for one field.
fn url_host(url: &str) -> Option<String> {
    let after_scheme = url.split_once("://")?.1;
    let authority = after_scheme
        .split(['/', '?', '#'])
        .next()
        .unwrap_or_default();
    let host = authority.rsplit_once('@').map_or(authority, |(_, h)| h);
    let host = host.split(':').next().unwrap_or_default();
    (!host.is_empty()).then(|| host.to_string())
}

/// http(s) base to ws(s), for socket endpoints.
pub fn websocket_scheme(base: &str) -> String {
    if let Some(rest) = base.strip_prefix("https://") {
        format!("wss://{rest}")
    } else if let Some(rest) = base.strip_prefix("http://") {
        format!("ws://{rest}")
    } else {
        base.to_string()
    }
}

// ── Reconnect ────────────────────────────────────────────────────────────────

/// 1s doubling to 30s, with jitter.
///
/// The jitter is not decoration: when a network comes back both clients wake at
/// once, and without it they retry in lockstep forever.
pub fn backoff_delay(attempt: u32, jitter_source: u64) -> Duration {
    const FLOOR_MS: u64 = 1_000;
    const CEILING_MS: u64 = 30_000;

    let exponential = FLOOR_MS.saturating_mul(1u64 << attempt.min(5));
    let capped = exponential.min(CEILING_MS);
    let jitter = jitter_source % (capped / 4 + 1);
    Duration::from_millis(capped + jitter)
}

/// Jitter taken from the clock, so nothing needs a random-number dependency.
pub fn clock_jitter() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| u64::from(d.subsec_nanos()))
        .unwrap_or(0)
}

// ── Ato: addresses ───────────────────────────────────────────────────────────
//
// Fixed rather than typed in: Ato is one Actuar product, not a panel each
// customer hosts, and these are the hosts the novo.actuar.com console itself is
// built against. Same values as `AtoEndpoints` in AtoRules.swift.

/// Sign-in and token refresh.
pub const ATO_USER_SERVICE: &str = "https://userservice-api.prd.o.actuar.cloud";
/// The inbox: agents, conversations, messages, and the `SupportHub`.
pub const ATO_SUPPORT_SERVICE: &str = "https://supportservice-api.prd.o.actuar.cloud";
/// The console people actually open.
pub const ATO_APP: &str = "https://novo.actuar.com";
/// Where a file goes before a message can carry it: `FileUpload/Upload`
/// answers a `StorageObjectId`, and the message names it.
pub const ATO_STORAGE_SERVICE: &str = "https://storageservice-api.prd.o.actuar.cloud";
/// The `Chat` case of the console's storage folder enum.
pub const ATO_CHAT_UPLOAD_FOLDER: &str = "19";
/// The console refuses a file over 25 MB before uploading it; so does this.
pub const ATO_MAX_UPLOAD_BYTES: usize = 26_214_400;

/// The `StorageObjectId` an upload answered, or None when it answered none —
/// which the console treats as a failed upload.
pub fn ato_storage_object_id(body: &str) -> Option<String> {
    let value: Value = serde_json::from_str(body).ok()?;
    let id = value.get("StorageObjectId")?.as_str()?.trim();
    if id.is_empty() {
        None
    } else {
        Some(id.to_string())
    }
}
/// The page the sign-in requests come from, for `Origin`/`Referer`.
pub const ATO_ACCOUNTS: &str = "https://accounts.actuar.com";

/// `wss://…/SupportHub?access_token=…` — the console's own route, with the
/// token in the query because a WebSocket cannot carry headers.
pub fn ato_hub_url(token: &str) -> String {
    let host = ATO_SUPPORT_SERVICE.trim_start_matches("https://");
    format!("wss://{host}/SupportHub?access_token={}", percent_encode(token))
}

/// The console, opened on one conversation.
pub fn ato_conversation_link(conversation_id: Option<&str>) -> String {
    match conversation_id.filter(|id| !id.is_empty()) {
        Some(id) => format!("{ATO_APP}/support/workspace?conversation={}", percent_encode(id)),
        None => format!("{ATO_APP}/support/workspace"),
    }
}

/// Percent-encodes everything outside RFC 3986's unreserved set.
pub fn percent_encode(value: &str) -> String {
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

// ── Ato: sign-in ─────────────────────────────────────────────────────────────

/// What `/Auth/Login` takes as `Password`: `md5(lowercased email + password)`,
/// hex — the panel's `encryptMd5`, computed before anything is sent. Not a
/// security measure on our side, only the format the server expects.
pub fn ato_password_digest(email: &str, password: &str) -> String {
    use md5::{Digest, Md5};
    let input = format!("{}{password}", ato_normalized_email(email));
    let digest = Md5::digest(input.as_bytes());
    digest.iter().map(|b| format!("{b:02x}")).collect()
}

/// Lowercased and trimmed, as the panel sends it.
pub fn ato_normalized_email(email: &str) -> String {
    email.trim().to_lowercase()
}

/// When a bearer token stops working, in seconds since the epoch, from its own
/// `exp` claim.
pub fn jwt_expiry_secs(token: &str) -> Option<i64> {
    let payload = token.split('.').nth(1)?;
    let bytes = base64url_decode(payload)?;
    let claims: Value = serde_json::from_slice(&bytes).ok()?;
    claims.get("exp").and_then(|v| v.as_f64()).map(|v| v as i64)
}

/// Unpadded base64url, the JWT alphabet. Two dozen lines rather than a crate
/// for the one claim this ever reads.
fn base64url_decode(text: &str) -> Option<Vec<u8>> {
    fn value(c: u8) -> Option<u32> {
        match c {
            b'A'..=b'Z' => Some(u32::from(c - b'A')),
            b'a'..=b'z' => Some(u32::from(c - b'a') + 26),
            b'0'..=b'9' => Some(u32::from(c - b'0') + 52),
            b'-' | b'+' => Some(62),
            b'_' | b'/' => Some(63),
            _ => None,
        }
    }
    let mut out = Vec::with_capacity(text.len() * 3 / 4);
    let mut buffer: u32 = 0;
    let mut bits = 0;
    for c in text.bytes().filter(|c| *c != b'=') {
        buffer = (buffer << 6) | value(c)?;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((buffer >> bits) as u8);
            buffer &= (1 << bits) - 1;
        }
    }
    Some(out)
}

// ── Ato: SignalR framing ─────────────────────────────────────────────────────

/// SignalR's JSON protocol ends every message with this byte, and one frame
/// can carry several.
pub const SIGNALR_SEPARATOR: char = '\u{1e}';
/// The handshake a client opens with.
pub const SIGNALR_HANDSHAKE: &str = "{\"protocol\":\"json\",\"version\":1}\u{1e}";
/// The ping a client must send: the server drops a connection it has not
/// heard from in 30 seconds.
pub const SIGNALR_PING: &str = "{\"type\":6}\u{1e}";

/// The JSON records in one frame.
pub fn signalr_records(frame: &str) -> Vec<&str> {
    frame
        .split(SIGNALR_SEPARATOR)
        .filter(|record| !record.trim().is_empty())
        .collect()
}

// ── Ato: who gets notified ───────────────────────────────────────────────────

/// Ato's enums arrive as numbers. Values read off the console's own
/// definitions (`It`, `St` in its bundle), not guessed.
pub const ATO_SENDER_CUSTOMER: i64 = 1;
pub const ATO_STATUS_CLOSED: i64 = 4;
pub const ATO_STATUS_ARCHIVED: i64 = 5;

/// The fields of an `onConversationUpdated` argument that decide anything.
///
/// Not `onMessagePosted`: that only reaches connections that joined the
/// conversation. A listener that has joined nothing sees a customer write only
/// as this update, with the text in `lastMessagePreview` — and it is the event
/// the console itself rings its bell on.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct AtoUpdate {
    pub conversation_id: String,
    pub workspace_id: Option<String>,
    pub contact_id: Option<String>,
    pub status_type: Option<i64>,
    pub assigned_to_agent_id: Option<String>,
    pub queue_id: Option<String>,
    pub last_message_on_utc: Option<String>,
    pub last_message_preview: Option<String>,
    pub last_message_sender_type: Option<i64>,
}

impl AtoUpdate {
    pub fn from_value(value: &Value) -> Option<AtoUpdate> {
        let text = |key: &str| {
            value
                .get(key)
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|v| !v.is_empty())
                .map(str::to_string)
        };
        Some(AtoUpdate {
            conversation_id: text("conversationId")?,
            workspace_id: text("workspaceId"),
            contact_id: text("contactId"),
            status_type: value.get("statusType").and_then(Value::as_i64),
            assigned_to_agent_id: text("assignedToAgentId"),
            queue_id: text("queueId"),
            last_message_on_utc: text("lastMessageOnUtc"),
            last_message_preview: text("lastMessagePreview"),
            last_message_sender_type: value.get("lastMessageSenderType").and_then(Value::as_i64),
        })
    }
}

/// One row of `GET /Agents/me`: who you are in one workspace.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct AtoMembership {
    pub agent_id: String,
    pub workspace_id: String,
    pub display_name: Option<String>,
    pub queue_ids: Vec<String>,
}

/// Reads `GET /Agents/me`. Rows missing either id are skipped rather than
/// failing the whole answer.
pub fn ato_memberships(body: &Value) -> Vec<AtoMembership> {
    body.as_array()
        .map(|rows| {
            rows.iter()
                .filter_map(|row| {
                    Some(AtoMembership {
                        agent_id: row.get("AgentId")?.as_str()?.to_string(),
                        workspace_id: row.get("WorkspaceId")?.as_str()?.to_string(),
                        display_name: row
                            .get("DisplayName")
                            .and_then(Value::as_str)
                            .map(str::trim)
                            .filter(|v| !v.is_empty())
                            .map(str::to_string),
                        queue_ids: row
                            .get("QueueIds")
                            .and_then(Value::as_array)
                            .map(|ids| {
                                ids.iter().filter_map(Value::as_str).map(str::to_string).collect()
                            })
                            .unwrap_or_default(),
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

/// Whether an update is a customer's new message that belongs to you.
///
/// The hub streams the whole workspace — every conversation, every agent, and
/// the bot talking to customers before anyone is assigned. So, the rule the
/// console uses for its own alerts and the one ClickMassa used before it:
/// the customer spoke last, the conversation is open, and it is yours —
/// assigned to you, or unassigned and waiting in one of your queues.
pub fn ato_should_notify(update: &AtoUpdate, memberships: &[AtoMembership]) -> bool {
    if update.last_message_sender_type != Some(ATO_SENDER_CUSTOMER) {
        return false;
    }
    if matches!(update.status_type, Some(ATO_STATUS_CLOSED) | Some(ATO_STATUS_ARCHIVED)) {
        return false;
    }
    // Without knowing who we are there is no "mine", and notifying on
    // everything would be worse than notifying on nothing.
    let Some(workspace) = update.workspace_id.as_deref() else { return false };
    let Some(membership) =
        memberships.iter().find(|m| m.workspace_id.eq_ignore_ascii_case(workspace))
    else {
        return false;
    };

    if let Some(assigned) = update.assigned_to_agent_id.as_deref() {
        return assigned.eq_ignore_ascii_case(&membership.agent_id);
    }
    let Some(queue) = update.queue_id.as_deref() else { return false };
    membership.queue_ids.iter().any(|q| q.eq_ignore_ascii_case(queue))
}

/// One id per customer message, stable across the repeats: the hub sends an
/// update for every change to a conversation, and several carry the same last
/// message. Its time is what tells a new one from a repeat.
pub fn ato_message_id(update: &AtoUpdate) -> String {
    format!(
        "ato:{}:{}",
        update.conversation_id,
        update.last_message_on_utc.as_deref().unwrap_or("")
    )
}

/// WhatsApp push names arrive as Ato stores them: `~cato`. The tilde is
/// WhatsApp saying "not in your contacts", which is noise on a card.
pub fn ato_display_name(raw: Option<&str>) -> Option<String> {
    let name = raw?.trim().trim_start_matches('~').trim();
    (!name.is_empty()).then(|| name.to_string())
}

// ── Mattermost: what kind of message this is ─────────────────────────────────

/// The kinds the island knows about, as the strings the event carries.
pub const KIND_DIRECT: &str = "directMessage";
pub const KIND_MENTION: &str = "mention";
pub const KIND_CHANNEL: &str = "channel";

/// Classifies a Mattermost `posted` event, or returns None to stay silent.
///
/// Mirrors the Swift exactly, including the order: own posts and system
/// messages are dropped before anything else is considered, because a join
/// notice that happens to mention you is still a join notice.
#[allow(clippy::too_many_arguments)]
pub fn classify_post(
    sender_id: &str,
    own_id: &str,
    post_type: Option<&str>,
    channel_type: Option<&str>,
    channel_name: Option<&str>,
    channel_display_name: Option<&str>,
    mentions: &[String],
    monitored_channels: &[String],
) -> Option<&'static str> {
    if sender_id == own_id {
        return None;
    }
    if post_type.is_some_and(|t| t.starts_with("system_")) {
        return None;
    }

    // D = direct, G = group. Both are conversations rather than rooms.
    if matches!(channel_type, Some("D") | Some("G")) {
        return Some(KIND_DIRECT);
    }

    if mentions.iter().any(|id| id == own_id) {
        return Some(KIND_MENTION);
    }

    if matches_monitored(channel_name, channel_display_name, monitored_channels) {
        return Some(KIND_CHANNEL);
    }

    // An ordinary message in an ordinary channel stays silent. It used to
    // notify for every channel you were a member of, which in a busy workspace
    // is most of the day.
    None
}

/// Channels are listed by either their internal name or the one shown in the
/// app, because people copy whichever they are looking at.
pub fn matches_monitored(
    channel_name: Option<&str>,
    channel_display_name: Option<&str>,
    monitored: &[String],
) -> bool {
    monitored.iter().any(|wanted| {
        let wanted = wanted.trim();
        if wanted.is_empty() {
            return false;
        }
        channel_name.is_some_and(|n| n.eq_ignore_ascii_case(wanted))
            || channel_display_name.is_some_and(|n| n.eq_ignore_ascii_case(wanted))
    })
}

/// Mattermost sends `data.post` and `data.mentions` as JSON **strings** inside
/// the event, so they need a second decode. Missing or malformed is normal
/// rather than exceptional — not every event carries them.
pub fn decode_nested_json(raw: Option<&str>) -> Option<Value> {
    serde_json::from_str(raw?).ok()
}

// ── Sign-in failures ─────────────────────────────────────────────────────────

/// What a refused `POST /api/v4/users/login` actually means, and whether
/// anything we do on our own could change the answer.
///
/// 401 is not one thing. Mattermost answers it for a wrong password, for an
/// account that still owes a second factor, for one locked by failed attempts,
/// for one whose address was never verified and for one that has been
/// deactivated. All five used to come out as "Wrong username or password",
/// which sends four of those people changing a password that was always right.
///
/// The server names which one it is in the body — `{"id":"…","message":"…"}` —
/// and the id is a Mattermost error code, never anything that was typed, so it
/// is safe to read and safe to log.
pub fn login_failure(status: u16, id: &str) -> (String, bool) {
    let fatal = |text: &str| (text.to_string(), true);
    match status {
        401 | 403 if id.contains("mfa") => {
            fatal("This account asks for a two-factor code, which Coucou cannot send yet")
        }
        401 | 403 if id.contains("login_attempts") => {
            fatal("Too many failed attempts — the server has locked this account for now")
        }
        401 | 403 if id.contains("not_verified") => {
            fatal("This account's email address has not been verified yet")
        }
        401 | 403 if id.contains("inactive") => fatal("This account has been deactivated on the server"),
        400 | 401 | 403 if id.contains("use_auth_service") => {
            fatal("This account signs in through SSO, so a password will not work here")
        }
        401 => fatal("Wrong username or password"),
        403 => fatal("This account is not allowed to sign in"),
        404 => fatal("No Mattermost API at that address"),
        // Worth another go: the limit clears on its own.
        429 => ("The server is rate-limiting us".to_string(), false),
        other => (format!("Server returned {other}"), false),
    }
}

// ── What a file says it is ───────────────────────────────────────────────────

/// The MIME type to declare for an upload, from the file's name.
///
/// Shared by both clients because both panels decide what a file *is* from the
/// name it arrives under, and a wrong answer is not cosmetic: a voice note sent
/// as `application/octet-stream` reaches the other person as an unplayable
/// blob, and one sent as `video/webm` reaches them as a video.
///
/// The hand-kept third of a trio — `AttachmentKind.mimeType(forExtension:)` in
/// Swift and `mimeTypeFor` in `core/attachments.ts` are the other two, and
/// `scripts/test-reply-attachments.sh` diffs only those two against each other.
/// Nothing catches this one drifting, so the audio rows are pinned by a test
/// below instead.
pub fn mime_for(name: &str) -> &'static str {
    let ext: String = std::path::Path::new(name)
        .extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    match ext.as_str() {
        "jpg" | "jpeg" => "image/jpeg",
        "png" => "image/png",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "heic" => "image/heic",
        "heif" => "image/heif",
        "tiff" => "image/tiff",
        "bmp" => "image/bmp",
        "pdf" => "application/pdf",
        "m4a" => "audio/mp4",
        "mp3" => "audio/mpeg",
        "wav" => "audio/wav",
        "aac" => "audio/aac",
        // A bare `.opus` file is Opus in an Ogg container, so it is audio/ogg
        // too; `audio/opus` names the codec and no server looks it up.
        "ogg" | "opus" => "audio/ogg",
        "flac" => "audio/flac",
        "amr" => "audio/amr",
        "txt" => "text/plain",
        "md" => "text/markdown",
        "csv" => "text/csv",
        "json" => "application/json",
        "xml" => "application/xml",
        "yaml" | "yml" => "application/yaml",
        "rtf" => "application/rtf",
        "zip" => "application/zip",
        _ => "application/octet-stream",
    }
}

// ── WhatsApp ─────────────────────────────────────────────────────────────────
//
// The twin of WhatsAppRules.swift. The page is WhatsApp Web, driven by the
// bridge in shared/whatsapp-bridge.js; what comes back from it is read here.

pub const WHATSAPP_URL: &str = "https://web.whatsapp.com/";

/// Hosts the hidden page may load in its main frame.
pub const WHATSAPP_HOSTS: [&str; 3] = ["web.whatsapp.com", "whatsapp.com", "whatsapp.net"];

/// One thing the bridge reported.
#[derive(Debug, Clone, PartialEq)]
pub enum WhatsAppEvent {
    Message { key: String, chat: String, body: String, timestamp_ms: i64 },
    /// "qr", "connected" or "loading".
    State(&'static str),
    Sent { request_id: Option<String> },
    SendFailed { request_id: Option<String>, reason: String },
}

fn non_empty(value: Option<&Value>) -> Option<String> {
    let text = value.and_then(Value::as_str)?.trim();
    if text.is_empty() {
        None
    } else {
        Some(text.to_string())
    }
}

/// Reads one event. Anything that is not one of ours, or lacks what it needs,
/// is None rather than a guess.
pub fn whatsapp_event(value: &Value) -> Option<WhatsAppEvent> {
    let object = value.as_object()?;
    match object.get("type")?.as_str()? {
        "message" => {
            let key = non_empty(object.get("key"))?;
            let chat = non_empty(object.get("chat"))?;
            let body = object.get("body").and_then(Value::as_str).unwrap_or("").to_string();
            let timestamp_ms = object.get("ts").and_then(Value::as_f64).map(|t| t as i64).unwrap_or(0);
            Some(WhatsAppEvent::Message { key, chat, body, timestamp_ms })
        }
        "state" => match object.get("state")?.as_str()? {
            "qr" => Some(WhatsAppEvent::State("qr")),
            "connected" => Some(WhatsAppEvent::State("connected")),
            "loading" => Some(WhatsAppEvent::State("loading")),
            _ => None,
        },
        "sent" => Some(WhatsAppEvent::Sent { request_id: non_empty(object.get("requestId")) }),
        "sendFailed" => Some(WhatsAppEvent::SendFailed {
            request_id: non_empty(object.get("requestId")),
            reason: non_empty(object.get("reason")).unwrap_or_else(|| "unknown".to_string()),
        }),
        _ => None,
    }
}

/// What a drain of the outbox returned: the JSON of an array of events. An
/// engine that hands back the array as a JSON string is read through as well.
pub fn whatsapp_events(raw: &str) -> Vec<WhatsAppEvent> {
    let Ok(mut value) = serde_json::from_str::<Value>(raw) else { return Vec::new() };
    if let Value::String(inner) = &value {
        match serde_json::from_str::<Value>(inner) {
            Ok(parsed) => value = parsed,
            Err(_) => return Vec::new(),
        }
    }
    value
        .as_array()
        .map(|items| items.iter().filter_map(whatsapp_event).collect())
        .unwrap_or_default()
}

/// The name on the card, without the `~` WhatsApp puts on someone who is not
/// in your contacts.
pub fn whatsapp_display_name(raw: &str) -> Option<String> {
    let name = raw.trim().trim_start_matches('~').trim();
    if name.is_empty() {
        None
    } else {
        Some(name.to_string())
    }
}

/// WhatsApp's own "several messages" notification speaks for no conversation.
pub fn whatsapp_is_summary(chat: &str) -> bool {
    chat.trim().eq_ignore_ascii_case("WhatsApp")
}

pub fn whatsapp_message_id(key: &str) -> String {
    format!("whatsapp:{key}")
}

/// True for an allowed host or a subdomain of one, over https; about:, blob:
/// and data: are the page's own.
pub fn whatsapp_keeps_in_webview(url: &str) -> bool {
    let lower = url.trim().to_lowercase();
    if lower.starts_with("about:") || lower.starts_with("blob:") || lower.starts_with("data:") {
        return true;
    }
    let Some(rest) = lower.strip_prefix("https://") else { return false };
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    let host = authority.rsplit('@').next().unwrap_or("").split(':').next().unwrap_or("");
    if host.is_empty() {
        return false;
    }
    WHATSAPP_HOSTS
        .iter()
        .any(|allowed| host == *allowed || host.ends_with(&format!(".{allowed}")))
}

/// Standard base64, for handing a file to the page. A dozen lines rather than a
/// crate for one call.
pub fn base64_encode(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity((bytes.len() + 2) / 3 * 4);
    for chunk in bytes.chunks(3) {
        let b = [chunk[0], *chunk.get(1).unwrap_or(&0), *chunk.get(2).unwrap_or(&0)];
        let n = (u32::from(b[0]) << 16) | (u32::from(b[1]) << 8) | u32::from(b[2]);
        out.push(TABLE[(n >> 18) as usize & 63] as char);
        out.push(TABLE[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 { TABLE[(n >> 6) as usize & 63] as char } else { '=' });
        out.push(if chunk.len() > 2 { TABLE[n as usize & 63] as char } else { '=' });
    }
    out
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_ato_upload_answers_the_id_a_message_names() {
        assert_eq!(
            ato_storage_object_id(r#"{"StorageObjectId":"0f3c-9a","Url":null}"#).as_deref(),
            Some("0f3c-9a")
        );
        assert_eq!(ato_storage_object_id(r#"{"StorageObjectId":""}"#), None);
        assert_eq!(ato_storage_object_id("<html>"), None);
    }

    // ── WhatsApp ────────────────────────────────────────────────────────────

    #[test]
    fn whatsapp_events_read_back_the_way_the_bridge_sent_them() {
        let raw = r#"[
            {"type":"message","key":"nabc-1","chat":"~Maria","body":"Oi","tag":null,"ts":1763200000000},
            {"type":"state","state":"qr"},
            {"type":"sent","requestId":"r1"},
            {"type":"sendFailed","requestId":"r2","reason":"could not open Maria"},
            {"type":"state","state":"banned"},
            {"type":"message","chat":"no key"},
            {"hello":"world"}
        ]"#;
        let events = whatsapp_events(raw);
        assert_eq!(events.len(), 4);
        assert_eq!(
            events[0],
            WhatsAppEvent::Message {
                key: "nabc-1".into(),
                chat: "~Maria".into(),
                body: "Oi".into(),
                timestamp_ms: 1_763_200_000_000
            }
        );
        assert_eq!(events[1], WhatsAppEvent::State("qr"));
        assert_eq!(events[2], WhatsAppEvent::Sent { request_id: Some("r1".into()) });
        assert_eq!(
            events[3],
            WhatsAppEvent::SendFailed { request_id: Some("r2".into()), reason: "could not open Maria".into() }
        );
    }

    #[test]
    fn a_drain_handed_back_as_a_string_is_read_through() {
        let raw = serde_json::to_string(&r#"[{"type":"state","state":"connected"}]"#).unwrap();
        assert_eq!(whatsapp_events(&raw), vec![WhatsAppEvent::State("connected")]);
        assert!(whatsapp_events("null").is_empty());
        assert!(whatsapp_events("not json").is_empty());
    }

    #[test]
    fn whatsapp_names_and_summaries() {
        assert_eq!(whatsapp_display_name("~cato").as_deref(), Some("cato"));
        assert_eq!(whatsapp_display_name(" +55 11 98888-7777 ").as_deref(), Some("+55 11 98888-7777"));
        assert_eq!(whatsapp_display_name(" ~ "), None);
        assert!(whatsapp_is_summary("WhatsApp"));
        assert!(!whatsapp_is_summary("WhatsApp Suporte"));
        assert_eq!(whatsapp_message_id("nabc-1"), "whatsapp:nabc-1");
    }

    #[test]
    fn the_hidden_page_stays_on_whatsapp() {
        assert!(whatsapp_keeps_in_webview("https://web.whatsapp.com/"));
        assert!(whatsapp_keeps_in_webview("https://mmg.whatsapp.net/v/t62/abc"));
        assert!(whatsapp_keeps_in_webview("https://www.whatsapp.com/download"));
        assert!(whatsapp_keeps_in_webview("about:blank"));
        assert!(whatsapp_keeps_in_webview("blob:https://web.whatsapp.com/1234"));
        assert!(!whatsapp_keeps_in_webview("http://web.whatsapp.com/"));
        assert!(!whatsapp_keeps_in_webview("https://web.whatsapp.com.evil.net/"));
        assert!(!whatsapp_keeps_in_webview("https://notwhatsapp.com/"));
        assert!(!whatsapp_keeps_in_webview("https://evil.net/@web.whatsapp.com"));
        assert!(!whatsapp_keeps_in_webview("https://example.com/"));
    }

    #[test]
    fn base64_matches_the_standard() {
        assert_eq!(base64_encode(b""), "");
        assert_eq!(base64_encode(b"f"), "Zg==");
        assert_eq!(base64_encode(b"fo"), "Zm8=");
        assert_eq!(base64_encode(b"foo"), "Zm9v");
        assert_eq!(base64_encode(b"foobar"), "Zm9vYmFy");
        assert_eq!(base64_encode(&[0xff, 0xfe, 0x00]), "//4A");
    }

    // Frames captured off the real SupportHub on 2026-11-15, conversation #323.
    // The same cases as tests/AtoRulesTests.swift.
    const WORKSPACE: &str = "019fcd42-9db6-7e62-88b1-ffa24983e487";
    const ME: &str = "01a17db4-ee0d-7819-b69a-0569e6ab2c67";
    const MY_QUEUE: &str = "01a1d1ba-c280-73ae-b633-e87c4460c83d";
    const OTHER_QUEUE: &str = "01a1d1bb-0619-7fee-928a-8d114ad49c8e";
    const COLLEAGUE: &str = "01a17db4-f2ee-7929-88e7-d5fc396a50bd";

    fn me() -> Vec<AtoMembership> {
        ato_memberships(&serde_json::json!([{
            "AgentId": ME, "WorkspaceId": WORKSPACE, "WorkspaceName": "Atendimento WhatsApp",
            "DisplayName": "Caua Toledo", "QueueIds": [MY_QUEUE]
        }]))
    }

    fn update(status: i64, assigned: Option<&str>, queue: Option<&str>, sender: i64) -> AtoUpdate {
        AtoUpdate::from_value(&serde_json::json!({
            "conversationId": "052278c9-80c1-4b5c-8b16-35ad0966cb14",
            "workspaceId": WORKSPACE,
            "contactId": "6b31de8c-a7f2-4789-a3f2-3956090a830e",
            "statusType": status,
            "assignedToAgentId": assigned,
            "queueId": queue,
            "lastMessageOnUtc": "2026-11-15T19:33:53Z",
            "lastMessagePreview": "Oi",
            "lastMessageSenderType": sender,
            "unansweredCount": 82
        }))
        .unwrap()
    }

    #[test]
    fn ato_notifies_only_on_what_is_yours() {
        let m = me();
        assert_eq!(m.len(), 1);
        assert!(ato_should_notify(&update(1, Some(ME), Some(OTHER_QUEUE), 1), &m));
        assert!(ato_should_notify(&update(1, None, Some(MY_QUEUE), 1), &m));
        // The captured #323: waiting in Sistema, which is not yours.
        assert!(!ato_should_notify(&update(1, None, Some(OTHER_QUEUE), 1), &m));
        assert!(!ato_should_notify(&update(1, Some(COLLEAGUE), Some(MY_QUEUE), 1), &m));
        assert!(!ato_should_notify(&update(1, None, None, 1), &m));
        assert!(ato_should_notify(&update(1, Some(&ME.to_uppercase()), None, 1), &m));
        assert!(!ato_should_notify(&update(1, Some(ME), None, 1), &[]));
    }

    #[test]
    fn ato_ignores_everyone_but_the_customer_and_finished_conversations() {
        let m = me();
        for sender in [2, 3, 4] {
            assert!(!ato_should_notify(&update(1, Some(ME), None, sender), &m));
        }
        assert!(!ato_should_notify(&update(4, Some(ME), None, 1), &m));
        assert!(!ato_should_notify(&update(5, Some(ME), None, 1), &m));
        assert!(ato_should_notify(&update(3, Some(ME), None, 1), &m));
    }

    #[test]
    fn ato_repeats_share_an_id_and_names_lose_the_tilde() {
        let a = update(1, Some(ME), None, 1);
        let b = update(1, None, Some(MY_QUEUE), 1);
        assert_eq!(ato_message_id(&a), ato_message_id(&b));
        assert_eq!(ato_display_name(Some("~cato")).as_deref(), Some("cato"));
        assert_eq!(ato_display_name(Some(" ~ ")), None);
        assert_eq!(ato_display_name(None), None);
    }

    #[test]
    fn ato_password_digest_matches_the_panel() {
        // md5("ana@example.com" + "segredo"), with the email lowercased first.
        assert_eq!(
            ato_password_digest(" Ana@Example.com ", "segredo"),
            ato_password_digest("ana@example.com", "segredo")
        );
        assert_eq!(ato_password_digest("", ""), "d41d8cd98f00b204e9800998ecf8427e");
    }

    #[test]
    fn ato_reads_a_token_expiry_and_builds_its_addresses() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3OTQ3NzgwMDB9.sig";
        assert_eq!(jwt_expiry_secs(jwt), Some(1_794_778_000));
        assert_eq!(jwt_expiry_secs("opaque"), None);
        assert_eq!(
            ato_hub_url("abc"),
            "wss://supportservice-api.prd.o.actuar.cloud/SupportHub?access_token=abc"
        );
        assert_eq!(
            ato_conversation_link(Some("052278c9")),
            "https://novo.actuar.com/support/workspace?conversation=052278c9"
        );
        assert_eq!(signalr_records("{}\u{1e}{\"type\":6}\u{1e}"), vec!["{}", "{\"type\":6}"]);
    }

    #[test]
    fn normalizes_what_people_paste() {
        assert_eq!(normalized_base("chat.example.com").as_deref(), Some("https://chat.example.com"));
        assert_eq!(normalized_base("https://chat.example.com/").as_deref(), Some("https://chat.example.com"));
        assert_eq!(normalized_base("http://localhost:8065").as_deref(), Some("http://localhost:8065"));
        assert_eq!(normalized_base("   "), None);
        assert_eq!(normalized_base(""), None);
        assert_eq!(normalized_base("https://"), None);
    }

    #[test]
    fn maps_scheme_to_websocket() {
        assert_eq!(websocket_scheme("https://a.b"), "wss://a.b");
        assert_eq!(websocket_scheme("http://a.b"), "ws://a.b");
    }

    #[test]
    fn backoff_rises_and_is_capped() {
        assert_eq!(backoff_delay(0, 0), Duration::from_millis(1_000));
        assert_eq!(backoff_delay(1, 0), Duration::from_millis(2_000));
        assert_eq!(backoff_delay(5, 0), Duration::from_millis(30_000));
        // Never beyond the ceiling plus its own quarter of jitter.
        assert!(backoff_delay(99, u64::MAX) <= Duration::from_millis(30_000 + 7_500));
    }

    #[test]
    fn classifies_mattermost_posts() {
        let none: Vec<String> = vec![];
        let monitored = vec!["deploys".to_string()];

        // Own post.
        assert_eq!(classify_post("me", "me", None, Some("O"), None, None, &[], &none), None);
        // Joins and leaves.
        assert_eq!(
            classify_post("other", "me", Some("system_join_channel"), Some("O"), None, None, &[], &none),
            None
        );
        // Direct and group.
        assert_eq!(classify_post("o", "me", None, Some("D"), None, None, &[], &none), Some(KIND_DIRECT));
        assert_eq!(classify_post("o", "me", None, Some("G"), None, None, &[], &none), Some(KIND_DIRECT));
        // Mentioned in an ordinary channel.
        assert_eq!(
            classify_post("o", "me", None, Some("O"), Some("random"), None, &["me".into()], &none),
            Some(KIND_MENTION)
        );
        // A monitored channel, by internal name and by display name.
        assert_eq!(
            classify_post("o", "me", None, Some("O"), Some("deploys"), None, &[], &monitored),
            Some(KIND_CHANNEL)
        );
        assert_eq!(
            classify_post("o", "me", None, Some("O"), Some("x"), Some("Deploys"), &[], &monitored),
            Some(KIND_CHANNEL)
        );
        // An ordinary message in an ordinary channel: silence.
        assert_eq!(classify_post("o", "me", None, Some("O"), Some("random"), None, &[], &monitored), None);
        // A system message that happens to mention you is still a system message.
        assert_eq!(
            classify_post("o", "me", Some("system_add_to_channel"), Some("O"), None, None, &["me".into()], &none),
            None
        );
    }

    #[test]
    fn decodes_the_nested_json_strings() {
        assert_eq!(decode_nested_json(Some(r#"{"id":"1"}"#)).unwrap()["id"], "1");
        assert!(decode_nested_json(None).is_none());
        assert!(decode_nested_json(Some("not json")).is_none());
    }

    #[test]
    fn a_401_is_not_only_a_wrong_password() {
        let text = |status, id| login_failure(status, id).0;
        assert_eq!(
            text(401, "api.user.login.invalid_credentials_email_username"),
            "Wrong username or password"
        );
        // The four below used to read as a wrong password, which is the one
        // thing none of them is.
        assert!(text(401, "api.user.check_user_mfa.bad_code.app_error").contains("two-factor"));
        assert!(text(401, "mfa.validate_token.authenticate.app_error").contains("two-factor"));
        assert!(text(401, "api.user.check_user_login_attempts.max.app_error").contains("locked"));
        assert!(text(401, "api.user.login.not_verified.app_error").contains("verified"));
        assert!(text(401, "api.user.login.inactive.app_error").contains("deactivated"));
        assert!(text(400, "api.user.login.use_auth_service.app_error").contains("SSO"));
    }

    #[test]
    fn only_a_server_that_might_answer_differently_is_worth_retrying() {
        let fatal = |status, id| login_failure(status, id).1;
        assert!(fatal(401, ""));
        assert!(fatal(403, ""));
        assert!(fatal(404, ""));
        // A rate limit clears itself; an unknown code has not said it will not.
        assert!(!fatal(429, ""));
        assert!(!fatal(503, ""));
        assert_eq!(login_failure(503, "").0, "Server returned 503");
    }

    #[test]
    fn an_unnamed_failure_still_says_something_useful() {
        // A server behind a proxy that answers before Mattermost does sends no
        // id at all, so every branch has to hold with an empty one.
        assert_eq!(login_failure(401, "").0, "Wrong username or password");
        assert_eq!(login_failure(404, "").0, "No Mattermost API at that address");
    }

    /// The audio rows, because this table is the one copy no parity script
    /// compares. A voice note is the whole reason they exist.
    #[test]
    fn audio_declares_itself_as_audio() {
        assert_eq!(mime_for("Voice message.m4a"), "audio/mp4");
        assert_eq!(mime_for("note.WAV"), "audio/wav");
        assert_eq!(mime_for("clip.opus"), "audio/ogg");
        assert_eq!(mime_for("shot.png"), "image/png");
        // Deliberately not audio: every MIME table calls it video, so a clip
        // named this way is delivered as one. The recorder writes WAV instead.
        assert_eq!(mime_for("clip.webm"), "application/octet-stream");
        assert_eq!(mime_for("no-extension"), "application/octet-stream");
    }
}
