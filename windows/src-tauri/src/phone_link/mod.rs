// The phone link: Notchy for iPhone and Notchy for Android pair with this computer
// over the local network, see the agents' sessions and answer permission requests.
// Protocol v1, docs/PHONE_LINK.md — the Mac speaks exactly the same
// (NotchBuddy/Sources/App/PhoneLink/), so a phone cannot tell a Mac from a PC.
//
// Ported from Coucou's Windows/Linux server, `windows/src-tauri/src/phone_link/` in
// Louis-CFM/coucou at commit 202082ee0204bbc4fb78d8178cea3f0c6fcc34e4 (MIT, by
// Rhytam Biswas; the same commit Notchy for Android was ported from). What changed
// on the way, so the PC matches the Mac:
//   * Notchy's names: `notchy://pair`, DNS-SD `_notchy._tcp`, port 47830 — a phone
//     paired with Coucou is never offered a Notchy, and the other way round;
//   * the capabilities the Mac offers, behind the Mac's switches: `details`,
//     `diffs`, `answers`, `chat`, and Notchy's `character` (no switch: what Mochi
//     wears says nothing about the user's work). Coucou's `usage`, `services`,
//     `recap`, `launch`, `prefs` and `relay` are left out, as on the Mac;
//   * no relay (relay_client.rs, relay_crypto.rs): nothing between the phone and
//     the computer, ever;
//   * chat calls the one provider Settings › Chat has here, Anthropic.
//
// Off by default and opt-in (Settings › General › Phone). While it is on, a TLS
// server listens on the local network and the computer is announced; while it is
// off nothing listens, nothing is announced and no timer runs. No telemetry: the
// only traffic is between this computer and the phones paired with it.
//
// The island keeps owning the sessions and the pending request. It publishes a
// picture of them (`phone_link_publish`), the hub works out what changed, and a
// phone's decision comes back through `TauriHost`, which answers the waiting
// `coucou-hook` exactly as a click on the island would — but only for the request
// that is still pending (hub.rs). The island's own card keeps working all along.

mod admission;
mod chat;
mod chat_backend;
mod discovery;
mod hub;
#[cfg(test)]
mod interop;
mod pairing;
mod server;
#[cfg(test)]
mod tests;

use std::net::{Ipv4Addr, SocketAddr, TcpListener as StdListener};
use std::sync::{Arc, Mutex};

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, State, WebviewWindow};

use crate::{clipboard, island, log, pipe, secrets, settings, Shared};
use hub::{ApprovalIn, Host, Hub, SessionIn};
use pairing::SecretStore;

/// The port the pairing link offers, the Mac's; another is taken if it is busy.
pub const DEFAULT_PORT: u16 = 47830;

/// The OS keystore (secrets.rs), through the entries only Rust may touch.
struct Keystore;

impl SecretStore for Keystore {
    fn get(&self, key: &str) -> Option<String> {
        secrets::get_internal(key)
    }
    fn set(&self, key: &str, value: &str) -> Result<(), String> {
        secrets::set_internal(key, value)
    }
}

/// A phone's decision, applied as a click on the island would be.
struct TauriHost {
    app: AppHandle,
}

impl Host for TauriHost {
    fn decide(&self, request_id: &str, allow: bool) {
        let word = if allow { "allow" } else { "deny" };
        log::line(format!("phone link: {word} from the phone, id={request_id}"));
        pipe::answer(&self.app, request_id, word);
        // The card on the island closes; it was answered elsewhere.
        let _ = self.app.emit_to(island::WINDOW_LABEL, "phone-link-decided", request_id.to_string());
    }

    fn get_diff(&self, sub_id: u64, pill_id: &str, file_id: u64) {
        // The island has the diffs; it answers with phone_link_send_diff. Nothing about the file is logged.
        let _ = self.app.emit_to(island::WINDOW_LABEL, "phone-link-getdiff", serde_json::json!({ "conn": sub_id, "pillId": pill_id, "fileId": file_id }));
    }

    // `answer` keeps the trait's default, which does nothing: the island here has no AskUserQuestion card yet
    // (docs/parity, Phase 5), so it never publishes a question and no phone can ever be asked one. The question
    // goes back to the agent the day the island answers questions itself, through the same path as its own card.
}

/// The switches in Settings › General › Phone, read again for every connection.
struct TauriFeatures {
    app: AppHandle,
}

impl TauriFeatures {
    fn read(&self) -> settings::Settings {
        self.app.state::<Shared>().settings.lock().unwrap().clone()
    }
}

impl server::Features for TauriFeatures {
    fn details(&self) -> bool {
        self.read().phone_details
    }
    fn answers(&self) -> bool {
        self.read().phone_answers
    }
    fn diffs(&self) -> bool {
        self.read().phone_diffs
    }
}

struct Running {
    handle: server::Handle,
    shared: Arc<server::Shared>,
    port: u16,
    identity: pairing::Identity,
}

pub struct PhoneLink {
    app: AppHandle,
    hub: Arc<Hub>,
    /// Chat from the phone; offered to phones only while the user's switch is on (chat.rs).
    chat: Arc<chat::ChatLink>,
    store: Arc<dyn SecretStore>,
    /// The announcement on the local network (discovery.rs): exists only while the link runs.
    advertiser: discovery::Advertiser,
    running: Mutex<Option<Running>>,
    error: Mutex<Option<String>>,
}

impl PhoneLink {
    pub fn new(app: AppHandle) -> Self {
        Self {
            chat: chat::ChatLink::new(Arc::new(chat_backend::AppChat::new(app.clone()))),
            hub: Hub::new(Arc::new(TauriHost { app: app.clone() })),
            app,
            store: Arc::new(Keystore),
            advertiser: discovery::Advertiser::new(Arc::new(discovery::MdnsPublisher::new())),
            running: Mutex::new(None),
            error: Mutex::new(None),
        }
    }

    /// Starts listening. Fails without side effects if the keystore is missing:
    /// nothing is ever kept on disk instead.
    pub fn start(&self) -> Result<(), String> {
        let mut running = self.running.lock().unwrap();
        if running.is_some() {
            return Ok(());
        }
        match self.start_inner() {
            Ok(r) => {
                log::line(format!("phone link: listening on port {}", r.port));
                // So the phone can find this computer again after a Wi-Fi change. The link works without it.
                match self.advertiser.start(&pairing::computer_name(), r.port, &r.identity.fingerprint) {
                    Ok(()) => log::line("phone link: announced on the local network"),
                    Err(e) => log::line(format!("phone link: not announced on the local network: {e}")),
                }
                *running = Some(r);
                *self.error.lock().unwrap() = None;
                Ok(())
            }
            Err(e) => {
                log::line(format!("phone link: could not start: {e}"));
                *self.error.lock().unwrap() = Some(e.clone());
                Err(e)
            }
        }
    }

    fn start_inner(&self) -> Result<Running, String> {
        let identity = pairing::load_or_create_identity(&*self.store)
            .map_err(|e| format!("no secure storage for the certificate: {e}"))?;
        let token = pairing::token(&*self.store).map_err(|e| format!("no secure storage for the pairing code: {e}"))?;
        let std_listener = StdListener::bind(SocketAddr::from((Ipv4Addr::UNSPECIFIED, DEFAULT_PORT)))
            .or_else(|_| StdListener::bind(SocketAddr::from((Ipv4Addr::UNSPECIFIED, 0))))
            .map_err(|e| format!("cannot listen: {e}"))?;
        std_listener.set_nonblocking(true).map_err(|e| e.to_string())?;
        let port = std_listener.local_addr().map_err(|e| e.to_string())?.port();
        let acceptor = server::tls_acceptor(&identity)?;
        let shared = server::Shared::with_features(
            self.hub.clone(), token, pairing::computer_name(), Some(self.chat.clone()), Arc::new(TauriFeatures { app: self.app.clone() }),
        );
        let handle = {
            let shared = shared.clone();
            tauri::async_runtime::block_on(async move {
                let listener = tokio::net::TcpListener::from_std(std_listener).map_err(|e| e.to_string())?;
                Ok::<_, String>(server::serve(listener, acceptor, shared))
            })?
        };
        Ok(Running { handle, shared, port, identity })
    }

    pub fn stop(&self) {
        self.advertiser.stop();
        if let Some(r) = self.running.lock().unwrap().take() {
            // Phones are told and closed, and a running answer stops (server::Handle::stop).
            r.handle.stop();
            log::line("phone link: stopped");
        }
        *self.error.lock().unwrap() = None;
    }

    fn is_running(&self) -> bool {
        self.running.lock().unwrap().is_some()
    }
}

// ── Which window may call which command ───────────────────────────────────────

/// The window a command that changes something may be called from. Every such command checks it, and `tests.rs`
/// reads this file to prove that none was added without a check.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Caller {
    Settings,
    Island,
}

fn caller_allowed(label: &str, who: Caller) -> bool {
    match who {
        Caller::Settings => label == "settings",
        Caller::Island => label == island::WINDOW_LABEL,
    }
}

/// It starts a network server and hands out the pairing secret: only the settings window may.
fn only_settings(window: &WebviewWindow) -> Result<(), String> {
    if caller_allowed(window.label(), Caller::Settings) {
        Ok(())
    } else {
        Err("only the settings window may change what the phone can use".into())
    }
}

/// The island is the one window that knows the sessions and the pending request; what it publishes goes to phones,
/// so no other window may publish.
fn only_island(window: &WebviewWindow) -> Result<(), String> {
    if caller_allowed(window.label(), Caller::Island) {
        Ok(())
    } else {
        Err("only the island may publish to the phone".into())
    }
}

// ── Commands ──────────────────────────────────────────────────────────────────

/// What the box in Settings › General › Phone shows. Never a secret.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    pub enabled: bool,
    pub running: bool,
    pub port: u16,
    /// Phones connected right now.
    pub phones: usize,
    pub error: Option<String>,
    pub details: bool,
    pub diffs: bool,
    pub answers: bool,
    pub chat: bool,
}

fn status_of(link: &PhoneLink, shared: &Shared) -> Status {
    let s = shared.settings.lock().unwrap().clone();
    let running = link.running.lock().unwrap();
    Status {
        enabled: s.phone_link,
        running: running.is_some(),
        port: running.as_ref().map_or(0, |r| r.port),
        phones: link.hub.clients(),
        error: link.error.lock().unwrap().clone(),
        details: s.phone_details,
        diffs: s.phone_diffs,
        answers: s.phone_answers,
        chat: s.phone_chat,
    }
}

#[tauri::command]
pub fn phone_link_status(link: State<PhoneLink>, shared: State<Shared>) -> Status {
    status_of(&link, &shared)
}

/// Saves the switches and tells every window, as `save_settings` does for the rest.
fn store(app: &AppHandle, shared: &Shared, change: impl FnOnce(&mut settings::Settings)) {
    let updated = {
        let mut current = shared.settings.lock().unwrap();
        change(&mut current);
        if let Err(err) = settings::save(&current) {
            log::line(format!("could not save settings: {err}"));
        }
        current.clone()
    };
    let _ = app.emit("settings-changed", updated);
}

/// "Show my agent sessions on my phone": starts the listener, or stops everything. A failure to start is kept in
/// the status, and the switch stays on so Settings can say why, as the Mac does.
#[tauri::command]
pub fn phone_link_set_enabled(
    app: AppHandle,
    window: WebviewWindow,
    link: State<PhoneLink>,
    shared: State<Shared>,
    enabled: bool,
) -> Result<Status, String> {
    only_settings(&window)?;
    store(&app, &shared, |s| s.phone_link = enabled);
    if enabled {
        let _ = link.start();
    } else {
        link.stop();
    }
    Ok(status_of(&link, &shared))
}

/// The field behind each of the four switches, by the name the settings window uses.
fn feature_field<'a>(s: &'a mut settings::Settings, feature: &str) -> Option<&'a mut bool> {
    match feature {
        "details" => Some(&mut s.phone_details),
        "diffs" => Some(&mut s.phone_diffs),
        "answers" => Some(&mut s.phone_answers),
        "chat" => Some(&mut s.phone_chat),
        _ => None,
    }
}

fn store_feature(app: &AppHandle, shared: &Shared, feature: &str, enabled: bool) -> Result<(), String> {
    if feature_field(&mut settings::Settings::default(), feature).is_none() {
        return Err(format!("unknown phone feature {feature}"));
    }
    store(app, shared, |s| {
        if let Some(field) = feature_field(s, feature) {
            *field = enabled;
        }
    });
    Ok(())
}

/// One of the four switches under it. Phones reconnect once, to be told what is offered now; turning chat off also
/// stops a running answer and forgets the phone's conversation (the Mac's `switchesChanged`).
#[tauri::command]
pub fn phone_link_set_feature(
    app: AppHandle,
    window: WebviewWindow,
    link: State<PhoneLink>,
    shared: State<Shared>,
    feature: String,
    enabled: bool,
) -> Result<Status, String> {
    only_settings(&window)?;
    store_feature(&app, &shared, &feature, enabled)?;
    link.hub.kick_all("closed", "settings changed");
    if feature == "chat" && !enabled {
        link.chat.shutdown();
    }
    log::line(format!("phone link: {feature} {}", if enabled { "on" } else { "off" }));
    Ok(status_of(&link, &shared))
}

/// What the settings window shows to pair a phone: the link and its QR code. `link` is None when this computer has
/// no address on a local network, which the box says in so many words.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Pairing {
    pub link: Option<String>,
    pub qr_svg: String,
}

fn pairing_of(r: &Running) -> Pairing {
    let Some(host) = pairing::lan_address().map(|ip| ip.to_string()) else {
        return Pairing { link: None, qr_svg: String::new() };
    };
    let token = r.shared.token.lock().unwrap().clone();
    let link = pairing::pairing_link(&host, r.port, &r.identity.fingerprint, &token, &r.shared.name);
    let qr_svg = pairing::qr_svg(&link).unwrap_or_default();
    Pairing { link: Some(link), qr_svg }
}

/// The pairing code, shown only after a click. Only the settings window may ask: the token is the secret that lets
/// a phone in.
#[tauri::command]
pub fn phone_link_pairing(window: WebviewWindow, link: State<PhoneLink>) -> Result<Pairing, String> {
    only_settings(&window)?;
    let running = link.running.lock().unwrap();
    let r = running.as_ref().ok_or("the phone link is off")?;
    Ok(pairing_of(r))
}

/// Cuts every connected phone off, then makes a new token. The phones go first and unconditionally: if the token
/// cannot be stored (a locked keystore), "Pair again" must still take effect on the connections, and the error is
/// reported afterwards instead of leaving the phones connected.
fn renew_pairing(hub: &Hub, token: &Mutex<String>, store: &dyn SecretStore) -> Result<(), String> {
    hub.kick_all("auth", "unpaired");
    *token.lock().unwrap() = pairing::new_token(store)?;
    Ok(())
}

/// "Pair again": a new code. The phone that had the old one is disconnected and must scan again.
#[tauri::command]
pub fn phone_link_new_pairing(window: WebviewWindow, link: State<PhoneLink>) -> Result<Pairing, String> {
    only_settings(&window)?;
    let running = link.running.lock().unwrap();
    let r = running.as_ref().ok_or("the phone link is off")?;
    renew_pairing(&link.hub, &r.shared.token, &*link.store)?;
    link.chat.shutdown();
    log::line("phone link: paired again, phones disconnected");
    Ok(pairing_of(r))
}

/// "Copy the link": the pairing link on the clipboard, kept by no clipboard history (clipboard::write_secret). The
/// link is made here, from the running link, rather than sent back by the window.
#[tauri::command]
pub fn phone_link_copy_pairing(app: AppHandle, window: WebviewWindow, link: State<PhoneLink>) -> Result<bool, String> {
    only_settings(&window)?;
    let text = {
        let running = link.running.lock().unwrap();
        let r = running.as_ref().ok_or("the phone link is off")?;
        pairing_of(r).link.ok_or("no local network address")?
    };
    Ok(clipboard::write_secret(&app, &text))
}

/// The island's picture of its sessions and of the request waiting for an answer.
#[tauri::command]
pub fn phone_link_publish(window: WebviewWindow, link: State<PhoneLink>, sessions: Vec<SessionIn>, approval: Option<ApprovalIn>) -> Result<(), String> {
    only_island(&window)?;
    if !link.is_running() {
        return Ok(());
    }
    link.hub.publish(sessions, approval, server::now_ms());
    Ok(())
}

/// The question Claude Code is waiting on (None: none), for phones that may answer it.
#[tauri::command]
pub fn phone_link_publish_question(window: WebviewWindow, link: State<PhoneLink>, question: Option<hub::QuestionIn>) -> Result<(), String> {
    only_island(&window)?;
    if !link.is_running() {
        return Ok(());
    }
    link.hub.publish_question(question, server::now_ms());
    Ok(())
}

/// The island's answer to a phone's request for a file's diff (event "phone-link-getdiff").
#[tauri::command]
pub fn phone_link_send_diff(window: WebviewWindow, link: State<PhoneLink>, conn: u64, diff: hub::DiffIn) -> Result<(), String> {
    only_island(&window)?;
    if !link.is_running() {
        return Ok(());
    }
    link.hub.send_diff(conn, diff);
    Ok(())
}

/// Called once at launch: the link comes back if the user had turned it on. A failure is kept in the status and
/// the log; the setting stays on so the user sees why in Settings instead of finding it silently off.
pub fn start_if_enabled(app: &AppHandle) {
    let enabled = app.state::<Shared>().settings.lock().unwrap().phone_link;
    if enabled {
        let _ = app.state::<PhoneLink>().start();
    }
}

/// The app is quitting: withdraw the announcement so phones forget this computer at once.
pub fn stop_on_exit(app: &AppHandle) {
    if let Some(link) = app.try_state::<PhoneLink>() {
        link.stop();
    }
}
