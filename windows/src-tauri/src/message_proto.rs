// The parts of the message clients that are pure functions.
//
// Split out deliberately. Everything here is decided by its inputs alone, so it
// is unit-tested against real frames — and these are the decisions that hurt
// when wrong: get ClickMassa's filter backwards and the notch either stays
// silent or shows the whole company's conversations.
//
// Ported from ClickMassaClient.swift, MattermostClient.swift and
// SocketIOConnection.swift.

use std::collections::HashSet;
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

/// ClickMassa's API host is the panel host with `api` appended to its first
/// label: `enterprise-419.clickmassa.com.br` → `enterprise-419api.clickmassa.com.br`,
/// which is the host ClickMassa itself puts in the webhook URLs it hands out.
///
/// The tenant label has to survive. Replacing it with a bare `api` — as this
/// did — collapses every tenant onto one host that answers for none of them,
/// and the only symptom is a login that fails as if the password were wrong.
pub fn clickmassa_api_base(panel_base: &str) -> Option<String> {
    let (scheme, rest) = panel_base.split_once("://")?;
    let (host, tail) = match rest.find('/') {
        Some(i) => (&rest[..i], &rest[i..]),
        None => (rest, ""),
    };
    let mut labels: Vec<String> = host.split('.').map(str::to_string).collect();
    let first = labels.first()?;
    if first.is_empty() {
        return None;
    }
    // Idempotent: a panel address someone already pasted in its API form must
    // not become `…apiapi`.
    if !first.ends_with("api") {
        labels[0] = format!("{first}api");
    }
    Some(format!("{scheme}://{}{tail}", labels.join(".")))
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

// ── Socket.IO framing ────────────────────────────────────────────────────────

/// One frame off a Socket.IO v5 / Engine.IO v4 socket.
///
/// The wire format, for whoever reads this next. Every frame is a digit or two
/// of prefix and then, optionally, JSON:
///
/// ```text
/// 0{"sid":"…","pingInterval":25000}   Engine.IO OPEN, server → client
/// 40                                  Socket.IO CONNECT, client → server
/// 40{"sid":"…"}                       CONNECT accepted, server → client
/// 42["event",{…}]                     EVENT (this is the one that matters)
/// 2 / 3                               PING / PONG
/// ```
///
/// A whole Socket.IO dependency for one read-only listener would be a great
/// deal of surface for very little.
#[derive(Debug, PartialEq)]
pub enum SocketFrame {
    Open(Value),
    Connected,
    Event { name: String, payload: Option<Value> },
    Ping,
    Pong,
    Other,
}

pub fn parse_socket_frame(text: &str) -> SocketFrame {
    if text == "2" {
        return SocketFrame::Ping;
    }
    if text == "3" {
        return SocketFrame::Pong;
    }
    if let Some(rest) = text.strip_prefix('0') {
        return SocketFrame::Open(serde_json::from_str(rest).unwrap_or(Value::Null));
    }
    if let Some(rest) = text.strip_prefix("42") {
        // ["event", payload?]
        let Ok(Value::Array(items)) = serde_json::from_str::<Value>(rest) else {
            return SocketFrame::Other;
        };
        let Some(Value::String(name)) = items.first().cloned() else {
            return SocketFrame::Other;
        };
        return SocketFrame::Event { name, payload: items.get(1).cloned() };
    }
    if text.starts_with("40") {
        return SocketFrame::Connected;
    }
    SocketFrame::Other
}

/// The CONNECT frame a client sends once the server has sent OPEN.
pub const SOCKET_CONNECT: &str = "40";
/// The answer to the server's PING. Engine.IO drops a socket that stops
/// answering, so this is not optional.
pub const SOCKET_PONG: &str = "3";

// ── ClickMassa: who gets notified ────────────────────────────────────────────

/// What `should_notify` needs to know about an incoming ClickMassa message.
#[derive(Debug, Default, Clone)]
pub struct ClickMassaTicket {
    pub user_id: Option<i64>,
    pub queue_id: Option<i64>,
    pub status: Option<String>,
}

/// Whether a ClickMassa message should reach the notch.
///
/// Pure so it can be tested against real frames, which matters more here than
/// anywhere else: the socket carries **every ticket in the company**, so
/// notifying on all of it would open the notch dozens of times a minute.
pub fn should_notify(
    from_me: bool,
    ticket: Option<&ClickMassaTicket>,
    user_id: Option<i64>,
    queue_ids: &HashSet<i64>,
) -> bool {
    // `fromMe` is the company side, so this covers your own replies and those
    // of every colleague on the same conversation.
    if from_me {
        return false;
    }
    let Some(ticket) = ticket else { return false };
    // Without knowing who we are there is no "mine", and notifying on
    // everything would be worse than notifying on nothing.
    let Some(user_id) = user_id else { return false };

    if ticket.user_id == Some(user_id) {
        return true;
    }

    let unclaimed = ticket.user_id.is_none() || ticket.status.as_deref() == Some("pending");
    if unclaimed {
        if let Some(queue_id) = ticket.queue_id {
            return queue_ids.contains(&queue_id);
        }
    }

    false
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

#[cfg(test)]
mod tests {
    use super::*;

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
    fn derives_the_clickmassa_api_host() {
        // The tenant label keeps its name and gains `api` — the same rule the
        // Swift client follows, and the host ClickMassa's own webhooks use.
        assert_eq!(
            clickmassa_api_base("https://enterprise-419.clickmassa.com.br").as_deref(),
            Some("https://enterprise-419api.clickmassa.com.br")
        );
        // Already in its API form: applying the rule twice must change nothing.
        assert_eq!(
            clickmassa_api_base("https://enterprise-419api.clickmassa.com.br").as_deref(),
            Some("https://enterprise-419api.clickmassa.com.br")
        );
        // A single-label host is still a host someone may be self-hosting on.
        assert_eq!(clickmassa_api_base("https://localhost").as_deref(), Some("https://localhostapi"));
        assert_eq!(clickmassa_api_base("not-a-url"), None);
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
    fn parses_the_frames_that_matter() {
        assert_eq!(parse_socket_frame("2"), SocketFrame::Ping);
        assert_eq!(parse_socket_frame("3"), SocketFrame::Pong);
        assert_eq!(parse_socket_frame("40"), SocketFrame::Connected);
        assert!(matches!(parse_socket_frame("0{\"sid\":\"x\"}"), SocketFrame::Open(_)));

        match parse_socket_frame(r#"42["chat:create",{"id":"7"}]"#) {
            SocketFrame::Event { name, payload } => {
                assert_eq!(name, "chat:create");
                assert_eq!(payload.unwrap()["id"], "7");
            }
            other => panic!("expected an event, got {other:?}"),
        }

        // An event with no payload is legal and must not panic.
        assert!(matches!(parse_socket_frame(r#"42["ping"]"#), SocketFrame::Event { .. }));
        assert_eq!(parse_socket_frame("nonsense"), SocketFrame::Other);
        assert_eq!(parse_socket_frame("42not-json"), SocketFrame::Other);
    }

    fn ticket(user: Option<i64>, queue: Option<i64>, status: &str) -> ClickMassaTicket {
        ClickMassaTicket { user_id: user, queue_id: queue, status: Some(status.into()) }
    }

    #[test]
    fn notifies_only_on_what_is_mine_or_waiting_in_my_queue() {
        let mine: HashSet<i64> = [10, 11].into_iter().collect();

        // Assigned to me.
        assert!(should_notify(false, Some(&ticket(Some(7), Some(10), "open")), Some(7), &mine));
        // A colleague's ticket, even in my queue.
        assert!(!should_notify(false, Some(&ticket(Some(99), Some(10), "open")), Some(7), &mine));
        // Unclaimed and waiting in my queue.
        assert!(should_notify(false, Some(&ticket(None, Some(10), "open")), Some(7), &mine));
        // Pending counts as unclaimed even with someone on it.
        assert!(should_notify(false, Some(&ticket(Some(99), Some(11), "pending")), Some(7), &mine));
        // Unclaimed but in a queue that is not mine.
        assert!(!should_notify(false, Some(&ticket(None, Some(42), "open")), Some(7), &mine));
        // Anything the company side sent, including my own replies.
        assert!(!should_notify(true, Some(&ticket(Some(7), Some(10), "open")), Some(7), &mine));
        // No ticket, or we do not know who we are.
        assert!(!should_notify(false, None, Some(7), &mine));
        assert!(!should_notify(false, Some(&ticket(Some(7), Some(10), "open")), None, &mine));
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
}
