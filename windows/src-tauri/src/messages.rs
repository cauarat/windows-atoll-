// Message sources — the Rust side of MattermostClient.swift and
// ClickMassaClient.swift.
//
// These are not pollers. Both hold a socket open, so they sit beside
// `integrations.rs` rather than inside it: `spawn()` there is a ticker that
// declines to work while paused, which is the wrong shape for a connection
// that has to be torn down and rebuilt.
//
// What they share with the pollers is the contract: emit an event and let the
// island own the badge, the sound and the pop-up. Nothing connects until the
// user has switched the pill on and stored credentials.
//
// Everything decided purely by its inputs lives in `message_proto`, where it
// is unit-tested. This file is the part that needs a running app.

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};

use crate::island::WINDOW_LABEL;

/// A message that arrived. One shape for both sources, so the island never
/// switches on a source string — the mistake Atoll had to undo after the same
/// `switch` drifted apart across four files.
#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct MessageEvent {
    /// The source's own id, used to drop duplicates when a reconnect replays
    /// history.
    pub id: String,
    /// "mattermost" or "clickmassa".
    pub source: &'static str,
    /// "directMessage", "mention", "channel" or "generic".
    pub kind: &'static str,
    pub sender: String,
    /// None for a direct message, where the sender is the conversation.
    pub channel: Option<String>,
    /// What a reply is addressed to: a Mattermost channel, a ClickMassa ticket.
    pub conversation_id: Option<String>,
    pub body: String,
    /// Milliseconds since the epoch, which is what JS `Date` wants.
    pub timestamp_ms: i64,
    pub link: Option<String>,
}

/// Where a source stands. Drives the dot in settings and the pill's idle card.
#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ConnectionStatus {
    pub source: &'static str,
    /// "disconnected", "connecting", "connected" or "failed".
    pub state: &'static str,
    /// The username when connected, the reason when failed.
    pub detail: Option<String>,
}

pub const MATTERMOST: &str = "mattermost";
pub const CLICKMASSA: &str = "clickmassa";

/// Pill ids, which are contract values exactly like every other pill id.
pub const MATTERMOST_PILL: &str = "integration_mattermost";
pub const CLICKMASSA_PILL: &str = "integration_clickmassa";

/// Credential Manager keys, alongside the ones `integrations.ts` already maps.
pub const MATTERMOST_URL_KEY: &str = "mattermost-url";
pub const MATTERMOST_LOGIN_KEY: &str = "mattermost-login";
pub const MATTERMOST_PASSWORD_KEY: &str = "mattermost-password";
pub const MATTERMOST_TOKEN_KEY: &str = "mattermost-token";
pub const CLICKMASSA_URL_KEY: &str = "clickmassa-url";
pub const CLICKMASSA_EMAIL_KEY: &str = "clickmassa-email";
pub const CLICKMASSA_PASSWORD_KEY: &str = "clickmassa-password";
pub const CLICKMASSA_TOKEN_KEY: &str = "clickmassa-token";

pub fn emit_message(app: &AppHandle, message: MessageEvent) {
    let _ = app.emit_to(WINDOW_LABEL, "message", message);
}

pub fn emit_status(app: &AppHandle, source: &'static str, state: &'static str, detail: Option<String>) {
    let _ = app.emit_to(WINDOW_LABEL, "message-status", ConnectionStatus { source, state, detail });
}

/// True when the user has this source's pill switched on.
///
/// The same question `integrations::enabled` asks, and the same answer: a
/// source that is off holds no socket and makes no request.
pub fn pill_enabled(app: &AppHandle, pill_id: &str) -> bool {
    app.try_state::<crate::Shared>()
        .map(|shared| {
            let settings = shared.settings.lock().unwrap();
            settings.active_integrations.iter().any(|x| x == pill_id)
        })
        .unwrap_or(false)
}
