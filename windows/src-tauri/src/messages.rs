// Message sources — the Rust side of MattermostClient.swift and
// AtoClient.swift.
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
    /// "mattermost", "ato" or "whatsapp".
    pub source: &'static str,
    /// "directMessage", "mention", "channel" or "generic".
    pub kind: &'static str,
    pub sender: String,
    /// None for a direct message, where the sender is the conversation.
    pub channel: Option<String>,
    /// What a reply is addressed to: a Mattermost channel, an Ato conversation.
    pub conversation_id: Option<String>,
    pub body: String,
    /// Milliseconds since the epoch, which is what JS `Date` wants.
    pub timestamp_ms: i64,
    pub link: Option<String>,
    /// A voice message, when that is what this was — Ato only, so far. `body`
    /// then holds its transcript, or says it is a voice message while there
    /// is none, so the list, the pill and the ticker need to know nothing
    /// about audio.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub audio: Option<crate::message_proto::AtoAudio>,
    /// A photo, when one came — Mattermost only, so far. `body` then says so,
    /// with what was written beside it; the card draws the photo itself.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub photo: Option<crate::message_proto::MessagePhoto>,
}

/// A message already on the island, changed — a voice message's transcript
/// arriving after it. Never announced again: the id is what the island keys on.
#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct MessageUpdate {
    pub id: String,
    pub body: String,
    pub audio: Option<crate::message_proto::AtoAudio>,
    /// Left off when the update is not about a photo, so a transcript
    /// arriving never takes one away.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub photo: Option<crate::message_proto::MessagePhoto>,
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

/// The settings window, which draws the same dots the island does.
const SETTINGS_LABEL: &str = "settings";

pub const MATTERMOST: &str = "mattermost";
pub const ATO: &str = "ato";
pub const WHATSAPP: &str = "whatsapp";

/// Pill ids, which are contract values exactly like every other pill id.
pub const MATTERMOST_PILL: &str = "integration_mattermost";
pub const ATO_PILL: &str = "integration_ato";
pub const WHATSAPP_PILL: &str = "integration_whatsapp";

/// Credential Manager keys, alongside the ones `integrations.ts` already maps.
pub const MATTERMOST_URL_KEY: &str = "mattermost-url";
pub const MATTERMOST_LOGIN_KEY: &str = "mattermost-login";
pub const MATTERMOST_PASSWORD_KEY: &str = "mattermost-password";
pub const MATTERMOST_TOKEN_KEY: &str = "mattermost-token";
pub const ATO_EMAIL_KEY: &str = "ato-email";
pub const ATO_PASSWORD_KEY: &str = "ato-password";
pub const ATO_TOKEN_KEY: &str = "ato-token";
pub const ATO_TOKEN_ID_KEY: &str = "ato-token-id";
/// The Agenda's own session with the commercial panel. Its account is Ato's:
/// the panel signs in with the same Actuar e-mail and password.
pub const AGENDA_TOKEN_KEY: &str = "agenda-token";
pub const AGENDA_TOKEN_ID_KEY: &str = "agenda-token-id";
/// Not a secret: "1" once this machine has been linked to a phone. Kept with
/// the others because `integrations.ts` reads a pill's "configured" from here.
/// The WhatsApp session itself lives in the page's own WebView2 profile.
pub const WHATSAPP_LINKED_KEY: &str = "whatsapp-linked";

/// ClickMassa's keys, kept only so a fresh start can delete what an older
/// build left in the Credential Manager — one of them is a password.
pub const RETIRED_CLICKMASSA_KEYS: [&str; 4] =
    ["clickmassa-url", "clickmassa-email", "clickmassa-password", "clickmassa-token"];

pub fn emit_message(app: &AppHandle, message: MessageEvent) {
    let _ = app.emit_to(WINDOW_LABEL, "message", message);
}

pub fn emit_message_update(app: &AppHandle, update: MessageUpdate) {
    let _ = app.emit_to(WINDOW_LABEL, "message-updated", update);
}

/// Both windows that draw a dot for a source hear this.
///
/// The island paints the one on the pill, the settings window the one beside
/// the credentials. Addressing only the island left Settings with no live
/// status at all: it fell back to what was stored, so a failure it had once
/// latched stayed on screen however the credentials changed -- see the note
/// above the `message-status` listener in settings/main.ts.
pub fn emit_status(app: &AppHandle, source: &'static str, state: &'static str, detail: Option<String>) {
    let status = ConnectionStatus { source, state, detail };
    let _ = app.emit_to(WINDOW_LABEL, "message-status", status.clone());
    let _ = app.emit_to(SETTINGS_LABEL, "message-status", status);
}

/// True when the user has this source's pill switched on.
///
/// Asked before any socket is opened: a source that is off holds no socket and
/// makes no request.
pub fn pill_enabled(app: &AppHandle, pill_id: &str) -> bool {
    app.try_state::<crate::Shared>()
        .map(|shared| {
            let settings = shared.settings.lock().unwrap();
            settings.active_integrations.iter().any(|x| x == pill_id)
        })
        .unwrap_or(false)
}
