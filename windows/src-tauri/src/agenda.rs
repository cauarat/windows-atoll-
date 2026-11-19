// The Agenda — the network half of AgendaClient.swift.
//
// Today's meetings from Actuar's commercial panel, read the way its own
// Agenda reads them: the two case lists, narrowed to you. What counts as one
// of your meetings is decided in `agenda_proto`; the clock — which day it is,
// when to read again, when to give a heads-up — is the island's, in
// `windows/src/core/agenda.ts`, because the island knows the local time zone
// and Rust here does not.
//
// The account is the Actuar one Ato keeps (`ato-email`, `ato-password`); the
// panel signs in with the same e-mail and the same password digest. The token
// pair is the Agenda's own: the panel asks for it under its own `AppSource`,
// and two clients refreshing from one `TokenId` would take turns
// invalidating each other.
//
// Nothing here runs on its own. The front end asks, while the Agenda is on;
// off, nothing reaches the network.

use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde::Serialize;
use serde_json::{json, Value};

use crate::agenda_proto::{
    self, cases_request, login_body, meetings_from_cases, merged, next_page, person_id, refresh_body,
    rpc_url, AgendaMeeting, Department, ORGANIZATION_CONTEXT_RPC, PANEL, USER_SERVICE,
};
use crate::log;
use crate::message_proto::{ato_normalized_email, ato_password_digest, jwt_expiry_secs};
use crate::messages;
use crate::secrets;

const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MIN_LOGIN_INTERVAL: Duration = Duration::from_secs(60);
/// A token with less than this left is traded for the next one first.
const REFRESH_LEAD_SECS: i64 = 10 * 60;

const USER_AGENT: &str =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) \
     Chrome/124.0.0.0 Safari/537.36";

static HTTP: LazyLock<reqwest::Client> = LazyLock::new(|| {
    reqwest::Client::builder().timeout(REQUEST_TIMEOUT).build().unwrap_or_default()
});

/// One read at a time: the tab opening and the ten-minute timer can ask
/// together, and two sign-ins at once is exactly what the floor is for.
static READING: LazyLock<tokio::sync::Mutex<()>> = LazyLock::new(|| tokio::sync::Mutex::new(()));

#[derive(Default)]
struct Memory {
    /// Who you are in the panel, read once per account.
    person_id: Option<String>,
    /// The account `person_id` and the token belong to.
    fingerprint: Option<String>,
    /// An account whose password was refused. Not tried again until it changes.
    refused: Option<String>,
    last_login: Option<Instant>,
}

static MEMORY: LazyLock<Mutex<Memory>> = LazyLock::new(|| Mutex::new(Memory::default()));

/// What one read found, for the island.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    /// `ready`, `signed-out`, `no-access` or `failed`.
    pub status: &'static str,
    pub detail: Option<String>,
    pub meetings: Vec<AgendaMeeting>,
    pub fetched_at_ms: i64,
}

impl Snapshot {
    fn of(status: &'static str, detail: Option<String>) -> Self {
        Self { status, detail, meetings: Vec::new(), fetched_at_ms: now_millis() }
    }
}

struct Failure {
    text: String,
    no_access: bool,
}

impl Failure {
    fn new(text: impl Into<String>) -> Self { Self { text: text.into(), no_access: false } }
    fn no_access() -> Self {
        Self { text: "This Actuar account has no access to the commercial panel".into(), no_access: true }
    }
}

struct Account {
    email: String,
    digest: String,
}

impl Account {
    fn fingerprint(&self) -> String { format!("{}:{}", self.email, self.digest) }
}

fn account() -> Option<Account> {
    let email = ato_normalized_email(&secrets::get(messages::ATO_EMAIL_KEY)?);
    let password = secrets::get(messages::ATO_PASSWORD_KEY)?;
    let digest = ato_password_digest(&email, &password);
    Some(Account { email, digest })
}

// ── Reading ──────────────────────────────────────────────────────────────────

/// Your meetings in `[day_start_ms, day_end_ms)`.
pub async fn refresh(day_start_ms: i64, day_end_ms: i64) -> Snapshot {
    let _reading = READING.lock().await;

    let Some(account) = account() else {
        return Snapshot::of("signed-out", None);
    };
    let fingerprint = account.fingerprint();
    {
        let mut memory = MEMORY.lock().unwrap();
        if memory.fingerprint.as_deref() != Some(fingerprint.as_str()) {
            // Another account than the one we last read as: its session and
            // its person are somebody else's.
            memory.person_id = None;
            memory.refused = None;
            memory.fingerprint = Some(fingerprint.clone());
            let _ = secrets::set(messages::AGENDA_TOKEN_KEY, "");
            let _ = secrets::set(messages::AGENDA_TOKEN_ID_KEY, "");
        }
        if memory.refused.as_deref() == Some(fingerprint.as_str()) {
            return Snapshot::of("failed", Some("Wrong email or password".into()));
        }
    }

    match read(&account, (day_start_ms, day_end_ms)).await {
        Ok(meetings) => {
            log::line(format!("agenda: {} meeting(s) today", meetings.len()));
            Snapshot { status: "ready", detail: None, meetings, fetched_at_ms: now_millis() }
        }
        Err(failure) if failure.no_access => {
            MEMORY.lock().unwrap().person_id = None;
            Snapshot::of("no-access", None)
        }
        Err(failure) => {
            log::line(format!("agenda: {}", failure.text));
            Snapshot::of("failed", Some(failure.text))
        }
    }
}

async fn read(account: &Account, day: (i64, i64)) -> Result<Vec<AgendaMeeting>, Failure> {
    let known = MEMORY.lock().unwrap().person_id.clone();
    let person = match known {
        Some(person) => person,
        None => {
            let context = rpc(account, ORGANIZATION_CONTEXT_RPC, &json!({})).await?;
            let person = person_id(&context).ok_or_else(Failure::no_access)?;
            MEMORY.lock().unwrap().person_id = Some(person.clone());
            person
        }
    };

    let mut lists = Vec::new();
    for department in Department::ALL {
        lists.push(cases(account, department, &person, day).await?);
    }
    Ok(merged(lists))
}

/// Every page of one process's cases, read down to your meetings. A process
/// this account may not read is an empty one, not a failure.
async fn cases(account: &Account, department: Department, person: &str, day: (i64, i64))
    -> Result<Vec<AgendaMeeting>, Failure>
{
    let mut page = 1;
    let mut found = Vec::new();
    loop {
        let (name, body) = cases_request(department, person, day, page);
        let response = match rpc(account, name, &body).await {
            Ok(response) => response,
            Err(failure) if failure.no_access => return Ok(found),
            Err(failure) => return Err(failure),
        };
        found.extend(meetings_from_cases(&response, person, day));
        match next_page(&response, page) {
            Some(next) => page = next,
            None => return Ok(found),
        }
    }
}

/// One gateway call, signing in again once if the token is refused.
async fn rpc(account: &Account, name: &str, body: &Value) -> Result<Value, Failure> {
    let mut token = fresh_token(account).await?;
    for attempt in 0..2 {
        let sent = HTTP
            .post(rpc_url(name))
            .header("Accept", "application/json")
            .header("Content-Profile", "public")
            .header("Authorization", format!("Bearer {token}"))
            .header("User-Agent", USER_AGENT)
            .header("Origin", PANEL)
            .header("Referer", format!("{PANEL}/"))
            .json(body)
            .send()
            .await
            .map_err(|_| Failure::new("Server unreachable"))?;
        match sent.status().as_u16() {
            200..=299 => {
                return sent.json::<Value>().await
                    .map_err(|_| Failure::new("Unexpected response from server"));
            }
            401 if attempt == 0 => {
                // Two hours run out; the next token is a refresh away.
                let _ = secrets::set(messages::AGENDA_TOKEN_KEY, "");
                token = fresh_token(account).await?;
            }
            401 => {
                let _ = secrets::set(messages::AGENDA_TOKEN_ID_KEY, "");
                return Err(Failure::new("Session expired"));
            }
            403 => return Err(Failure::no_access()),
            other => return Err(Failure::new(format!("Server returned {other}"))),
        }
    }
    Err(Failure::new("Session expired"))
}

// ── Tokens ───────────────────────────────────────────────────────────────────

async fn fresh_token(account: &Account) -> Result<String, Failure> {
    if let Some(token) = secrets::get(messages::AGENDA_TOKEN_KEY) {
        let fresh = jwt_expiry_secs(&token).is_some_and(|exp| exp - now_millis() / 1_000 > REFRESH_LEAD_SECS);
        if fresh {
            return Ok(token);
        }
    }
    if let Some(token_id) = secrets::get(messages::AGENDA_TOKEN_ID_KEY) {
        if let Ok(token) = refresh_session(&token_id).await {
            return Ok(token);
        }
    }
    sign_in(account).await
}

async fn sign_in(account: &Account) -> Result<String, Failure> {
    let waited = MEMORY.lock().unwrap().last_login.map(|at| at.elapsed());
    if let Some(remaining) = waited.map(|w| MIN_LOGIN_INTERVAL.saturating_sub(w)).filter(|r| !r.is_zero()) {
        tokio::time::sleep(remaining).await;
    }
    MEMORY.lock().unwrap().last_login = Some(Instant::now());

    let response = HTTP
        .post(format!("{USER_SERVICE}/Auth/Login"))
        .header("Accept", "application/json")
        .header("User-Agent", USER_AGENT)
        .header("Origin", PANEL)
        .header("Referer", format!("{PANEL}/"))
        .json(&login_body(&account.email, &account.digest))
        .send()
        .await
        .map_err(|_| Failure::new("Server unreachable"))?;
    match response.status().as_u16() {
        200 | 201 => store_session(response).await,
        400 | 401 => {
            MEMORY.lock().unwrap().refused = Some(account.fingerprint());
            Err(Failure::new("Wrong email or password"))
        }
        403 => Err(Failure::new("This account cannot sign in")),
        429 => Err(Failure::new("Too many sign-in attempts — not a password problem. Try again in a minute.")),
        other => Err(Failure::new(format!("Server returned {other}"))),
    }
}

async fn refresh_session(token_id: &str) -> Result<String, Failure> {
    let response = HTTP
        .post(format!("{USER_SERVICE}/Auth/Refresh"))
        .header("Accept", "application/json")
        .header("User-Agent", USER_AGENT)
        .header("Origin", PANEL)
        .header("Referer", format!("{PANEL}/"))
        .json(&refresh_body(token_id))
        .send()
        .await
        .map_err(|_| Failure::new("Server unreachable"))?;
    match response.status().as_u16() {
        200 | 201 => store_session(response).await,
        _ => {
            let _ = secrets::set(messages::AGENDA_TOKEN_ID_KEY, "");
            Err(Failure::new("Session expired"))
        }
    }
}

async fn store_session(response: reqwest::Response) -> Result<String, Failure> {
    let body: Value = response.json().await
        .map_err(|_| Failure::new("Signed in, but could not read the account"))?;
    let token = body.get("Token").and_then(Value::as_str).filter(|t| !t.is_empty())
        .ok_or_else(|| Failure::new("Signed in, but could not read the account"))?;
    let _ = secrets::set(messages::AGENDA_TOKEN_KEY, token);
    if let Some(token_id) = body.get("TokenId").and_then(Value::as_str) {
        let _ = secrets::set(messages::AGENDA_TOKEN_ID_KEY, token_id);
    }
    Ok(token.to_string())
}

/// Where a click on a meeting goes: the panel's agenda for its process.
pub fn agenda_url(department: &str) -> String {
    let department = if department == "backoffice" { Department::Backoffice } else { Department::Onboarding };
    agenda_proto::agenda_url(department)
}

fn now_millis() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}
