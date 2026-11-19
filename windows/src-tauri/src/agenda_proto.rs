// The Agenda's rules — the Rust twin of AgendaRules.swift.
//
// Which of the commercial panel's meetings are yours on a given day, read out
// of the two case lists the panel's own Agenda reads. Everything here is pure
// and tested against the same pages the Swift tests read
// (`tests/fixtures/agenda/`): what the panel drew on 2026-11-19, with every
// name and id replaced.
//
// The day itself is not decided here. Rust has no idea of the local time zone
// without another dependency, and the island's JavaScript has one for free, so
// the front end hands in the day as two instants and keeps the clock: the
// heads-up timing lives in `windows/src/core/agenda.ts`.

use serde::Serialize;
use serde_json::{json, Value};

pub const USER_SERVICE: &str = "https://userservice-api.prd.o.actuar.cloud";
pub const GATEWAY: &str = "https://query-gateway.actuar.group";
pub const PANEL: &str = "https://dash-comercial.pages.dev";
/// The panel's own `AppSource`. Ato signs in as `actuar` alone; the panel's
/// gateway is used to tokens minted for all three brands.
pub const APP_SOURCE: &str = "Actuar,FacilFit,Ediz";
pub const ORGANIZATION_CONTEXT_RPC: &str = "get_current_organization_context";
pub const MAX_PAGES: u32 = 40;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Department {
    Onboarding,
    Backoffice,
}

impl Department {
    pub const ALL: [Department; 2] = [Department::Onboarding, Department::Backoffice];

    /// The panel's rule: a `contact` stage is the Backoffice's, every other is
    /// Onboarding's — whichever list the case came from.
    pub fn of_stage(stage_key: &str) -> Self {
        if stage_key == "contact" { Department::Backoffice } else { Department::Onboarding }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Department::Onboarding => "onboarding",
            Department::Backoffice => "backoffice",
        }
    }
}

/// One effective attempt of one meeting of yours. Keyed by the attempt: a
/// remarcação is a new attempt, so a moved meeting is a new row.
#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgendaMeeting {
    pub attempt_id: String,
    pub meeting_id: String,
    pub case_id: String,
    pub department: &'static str,
    pub stage_key: String,
    pub start_ms: i64,
    pub end_ms: i64,
    pub title: String,
    pub public_id: Option<String>,
    pub attempt_sequence: i64,
    pub attempt_state: String,
    pub meeting_state: String,
}

// ── Requests ─────────────────────────────────────────────────────────────────

pub fn rpc_url(name: &str) -> String {
    format!("{GATEWAY}/rest/v1/rpc/{name}")
}

pub fn agenda_url(department: Department) -> String {
    format!("{PANEL}/agenda?process={}", department.as_str())
}

pub fn login_body(email: &str, password_digest: &str) -> Value {
    json!({ "Email": email, "Password": password_digest, "AppSource": APP_SOURCE })
}

pub fn refresh_body(token_id: &str) -> Value {
    json!({ "TokenId": token_id, "AppSource": APP_SOURCE })
}

/// The RPC and body the panel sends for one page of one process's cases,
/// narrowed to one person — its own "Eu" filter. `day` is `[start, end)` in
/// epoch milliseconds.
pub fn cases_request(department: Department, person_id: &str, day: (i64, i64), page: u32) -> (&'static str, Value) {
    let from = iso_millis(day.0);
    let to = iso_millis(day.1 - 1);
    match department {
        Department::Onboarding => ("get_onboarding_board_cards_v1", json!({
            "p_date_from": from,
            "p_date_to": to,
            "p_include_open_carryover": true,
            "p_products": null,
            "p_search": null,
            "p_scope": "all",
            "p_responsible_person_id": person_id,
            "p_unassigned_only": false,
            "p_include_scheduled_pre_release": true,
            "p_entry_from": null,
            "p_entry_to": null,
            "p_page": page,
            "p_page_size": 200,
        })),
        Department::Backoffice => ("get_backoffice_cases", json!({
            "p_date_from": from,
            "p_date_to": to,
            "p_include_open_carryover": true,
            "p_status": "all",
            "p_department": "all",
            "p_pipeline_id": null,
            "p_products": null,
            "p_search": null,
            "p_scope": "all",
            "p_responsible_person_id": person_id,
            "p_unassigned_only": false,
            "p_page": page,
            "p_page_size": 50,
            "p_entry_from": null,
            "p_entry_to": null,
        })),
    }
}

/// The page after `page`, or None when that was the last. The Onboarding board
/// says `has_more`; the Backoffice list only gives a total.
pub fn next_page(body: &Value, page: u32) -> Option<u32> {
    if page >= MAX_PAGES {
        return None;
    }
    if let Some(more) = body.get("has_more").and_then(Value::as_bool) {
        return more.then_some(page + 1);
    }
    let total = body.get("total_count")?.as_u64()?;
    let size = body.get("page_size")?.as_u64().filter(|s| *s > 0)?;
    (u64::from(page) * size < total).then_some(page + 1)
}

// ── Who you are ──────────────────────────────────────────────────────────────

/// `person_id` out of `get_current_organization_context`; None for an account
/// with no person behind it, which has no agenda of its own.
pub fn person_id(context: &Value) -> Option<String> {
    let object = if context.is_array() { context.get(0)? } else { context };
    let id = object.get("person_id")?.as_str()?.trim();
    (!id.is_empty()).then(|| id.to_string())
}

// ── Meetings ─────────────────────────────────────────────────────────────────

/// Your meetings in `day` out of one page of cases, from either list. Read
/// loosely: a case the parser does not understand is skipped, not fatal.
pub fn meetings_from_cases(page: &Value, person_id: &str, day: (i64, i64)) -> Vec<AgendaMeeting> {
    let cases = page.get("data").and_then(Value::as_array)
        .or_else(|| page.as_array())
        .cloned()
        .unwrap_or_default();
    let me = person_id.to_lowercase();
    let mut out = Vec::new();

    for item in &cases {
        let Some(case_id) = item.get("id").and_then(Value::as_str) else { continue };
        let Some(stages) = item.pointer("/operational_meeting_kanban/stages").and_then(Value::as_array) else {
            continue;
        };
        let customer = item.get("customer_name").and_then(Value::as_str).unwrap_or("");
        let code = public_id(customer, item.get("opportunity_id").and_then(Value::as_str));

        for stage in stages {
            let Some(stage_key) = stage.get("stageKey").and_then(Value::as_str) else { continue };
            for meeting in meetings_of(stage) {
                let Some(meeting_id) = meeting.get("id").and_then(Value::as_str) else { continue };
                let responsible = meeting.get("responsiblePersonId").and_then(Value::as_str).unwrap_or("");
                if responsible.to_lowercase() != me {
                    continue;
                }
                let meeting_state = meeting.get("state").and_then(Value::as_str).unwrap_or("open");
                if meeting_state == "cancelled" {
                    continue;
                }
                let attempts = meeting.get("attempts").and_then(Value::as_array).cloned().unwrap_or_default();
                for attempt in &attempts {
                    if attempt.get("isEffective").and_then(Value::as_bool) != Some(true) {
                        continue;
                    }
                    let Some(attempt_id) = attempt.get("id").and_then(Value::as_str) else { continue };
                    let attempt_state = attempt.get("state").and_then(Value::as_str).unwrap_or("");
                    if attempt_state == "cancelled" || attempt.get("cancelledAt").is_some_and(|v| !v.is_null()) {
                        continue;
                    }
                    let Some(start) = attempt.get("startAt").and_then(Value::as_str).and_then(parse_iso) else {
                        continue;
                    };
                    if start < day.0 || start >= day.1 {
                        continue;
                    }
                    let end = attempt.get("endAt").and_then(Value::as_str).and_then(parse_iso)
                        .filter(|end| *end > start)
                        .unwrap_or(start + 3_600_000);
                    out.push(AgendaMeeting {
                        attempt_id: attempt_id.to_string(),
                        meeting_id: meeting_id.to_string(),
                        case_id: case_id.to_string(),
                        department: Department::of_stage(stage_key).as_str(),
                        stage_key: stage_key.to_string(),
                        start_ms: start,
                        end_ms: end,
                        title: attendee_name(customer, code.as_deref(),
                                             meeting.get("displayAttendeeName").and_then(Value::as_str)),
                        public_id: code.clone(),
                        attempt_sequence: attempt.get("sequence").and_then(Value::as_i64).unwrap_or(1),
                        attempt_state: attempt_state.to_string(),
                        meeting_state: meeting_state.to_string(),
                    });
                }
            }
        }
    }
    merged(vec![out])
}

/// A stage's meetings with their attempts: `meetings` on a canonical stage,
/// or the one `meeting` with the attempts beside it on the stage.
fn meetings_of(stage: &Value) -> Vec<Value> {
    if let Some(list) = stage.get("meetings").and_then(Value::as_array) {
        if !list.is_empty() {
            return list.clone();
        }
    }
    let Some(single) = stage.get("meeting").filter(|m| m.is_object()) else { return Vec::new() };
    let mut single = single.clone();
    if single.get("attempts").is_none() {
        if let Some(attempts) = stage.get("attempts") {
            single["attempts"] = attempts.clone();
        }
    }
    vec![single]
}

/// One list from several: an attempt read from both lists is one meeting, and
/// the day reads in order.
pub fn merged(lists: Vec<Vec<AgendaMeeting>>) -> Vec<AgendaMeeting> {
    let mut seen = std::collections::HashSet::new();
    let mut out: Vec<AgendaMeeting> = lists.into_iter().flatten()
        .filter(|m| seen.insert(m.attempt_id.clone()))
        .collect();
    out.sort_by(|a, b| a.start_ms.cmp(&b.start_ms).then_with(|| a.title.to_lowercase().cmp(&b.title.to_lowercase())));
    out
}

// ── Titles ───────────────────────────────────────────────────────────────────

/// The case code the panel shows as a chip: an opportunity id that is one, or
/// else the last code in the customer's name ("… Actuar GM3941").
///
/// The panel's pattern is `(?:[A-Z][A-Z0-9]*-)?[A-Z]{2}\d{4}` between
/// non-alphanumerics, case-insensitive; read here as runs of alphanumerics,
/// since there is no regex crate in this build.
pub fn public_id(customer_name: &str, opportunity_id: Option<&str>) -> Option<String> {
    if let Some(opportunity) = opportunity_id.map(str::trim).filter(|o| !o.is_empty()) {
        if is_whole_code(opportunity) {
            return Some(opportunity.to_uppercase());
        }
    }
    let chars: Vec<char> = customer_name.chars().collect();
    let mut runs: Vec<(usize, usize)> = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        if chars[i].is_alphanumeric() {
            let start = i;
            while i < chars.len() && chars[i].is_alphanumeric() { i += 1; }
            runs.push((start, i));
        } else {
            i += 1;
        }
    }
    let mut found: Option<String> = None;
    for (index, &(start, end)) in runs.iter().enumerate() {
        let run: String = chars[start..end].iter().collect();
        if !is_code(&run) {
            continue;
        }
        // A prefix joined by a hyphen: "X-GM1234".
        let mut code = run.to_uppercase();
        if index > 0 && start > 0 && chars[start - 1] == '-' {
            let (ps, pe) = runs[index - 1];
            let prefix: String = chars[ps..pe].iter().collect();
            if pe == start - 1 && is_prefix(&prefix) {
                code = format!("{}-{}", prefix.to_uppercase(), code);
            }
        }
        found = Some(code);
    }
    found
}

fn is_code(run: &str) -> bool {
    let bytes = run.as_bytes();
    bytes.len() == 6
        && bytes[..2].iter().all(u8::is_ascii_alphabetic)
        && bytes[2..].iter().all(u8::is_ascii_digit)
}

fn is_prefix(run: &str) -> bool {
    let bytes = run.as_bytes();
    !bytes.is_empty() && bytes[0].is_ascii_alphabetic() && bytes.iter().all(u8::is_ascii_alphanumeric)
}

fn is_whole_code(text: &str) -> bool {
    match text.rsplit_once('-') {
        Some((prefix, code)) => is_prefix(prefix) && is_code(code),
        None => is_code(text),
    }
}

fn is_separator(c: char) -> bool {
    matches!(c, '|' | '·' | '-' | '–' | ',' | ':')
}

/// The card's title: the display name when the meeting has one, else the
/// customer's name without the code the chip already shows. Empty when there
/// is no name at all; the view says so in words.
pub fn attendee_name(customer_name: &str, public_id: Option<&str>, display_name: Option<&str>) -> String {
    if let Some(display) = display_name.map(str::trim).filter(|d| !d.is_empty()) {
        return display.to_string();
    }
    let original = customer_name.trim();
    let Some(code) = public_id.filter(|c| !c.is_empty()) else { return original.to_string() };

    // Every occurrence of the code, with the separators hugging it, becomes
    // one space.
    let chars: Vec<char> = original.chars().collect();
    let needle: Vec<char> = code.chars().flat_map(char::to_lowercase).collect();
    let lower: Vec<char> = chars.iter().flat_map(|c| c.to_lowercase()).collect();
    let mut text: Vec<char> = Vec::new();
    let mut i = 0;
    if lower.len() == chars.len() {
        while i < chars.len() {
            if i + needle.len() <= lower.len() && lower[i..i + needle.len()] == needle[..] {
                while text.last().is_some_and(|c| c.is_whitespace() || is_separator(*c)) { text.pop(); }
                text.push(' ');
                i += needle.len();
                while i < chars.len() && (chars[i].is_whitespace() || is_separator(chars[i])) { i += 1; }
            } else {
                text.push(chars[i]);
                i += 1;
            }
        }
    } else {
        text = chars.clone();
    }

    // A trailing run of separators goes, with the space before it; a leading
    // one, with the space after it.
    let mut end = text.len();
    if end > 0 && is_separator(text[end - 1]) {
        while end > 0 && is_separator(text[end - 1]) { end -= 1; }
        while end > 0 && text[end - 1].is_whitespace() { end -= 1; }
    }
    let mut start = 0;
    if start < end && is_separator(text[start]) {
        while start < end && is_separator(text[start]) { start += 1; }
        while start < end && text[start].is_whitespace() { start += 1; }
    }
    let collapsed = text[start..end].iter().collect::<String>()
        .split_whitespace().collect::<Vec<_>>().join(" ");
    if collapsed.is_empty() { original.to_string() } else { collapsed }
}

// ── Time ─────────────────────────────────────────────────────────────────────

/// `2026-11-19T03:00:00.000Z` — the panel's window bounds.
pub fn iso_millis(millis: i64) -> String {
    let secs = millis.div_euclid(1_000);
    let ms = millis.rem_euclid(1_000);
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    format!("{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}.{ms:03}Z", rem / 3_600, rem % 3_600 / 60, rem % 60)
}

/// Postgres timestamps: `Z` or `±HH:MM`, fractions of any length.
pub fn parse_iso(text: &str) -> Option<i64> {
    let text = text.trim();
    let (date, clock) = text.split_once('T')?;
    let mut d = date.split('-');
    let year: i64 = d.next()?.parse().ok()?;
    let month: i64 = d.next()?.parse().ok()?;
    let day: i64 = d.next()?.parse().ok()?;

    let (clock, offset_secs) = if let Some(stripped) = clock.strip_suffix(['Z', 'z']) {
        (stripped, 0)
    } else if let Some(at) = clock.rfind(['+', '-']) {
        let (clock, zone) = clock.split_at(at);
        let sign = if zone.starts_with('-') { -1 } else { 1 };
        let mut z = zone[1..].split(':');
        let hours: i64 = z.next()?.parse().ok()?;
        let minutes: i64 = z.next().unwrap_or("0").parse().ok()?;
        (clock, sign * (hours * 3_600 + minutes * 60))
    } else {
        (clock, 0)
    };

    let mut c = clock.split(':');
    let hour: i64 = c.next()?.parse().ok()?;
    let minute: i64 = c.next()?.parse().ok()?;
    let seconds = c.next().unwrap_or("0");
    let (whole, fraction) = seconds.split_once('.').unwrap_or((seconds, ""));
    let second: i64 = whole.parse().ok()?;
    let mut millis = 0;
    for (index, character) in fraction.chars().take(3).enumerate() {
        millis += i64::from(character.to_digit(10)?) * 10i64.pow(2 - index as u32);
    }
    let secs = days_from_civil(year, month, day) * 86_400 + hour * 3_600 + minute * 60 + second - offset_secs;
    Some(secs * 1_000 + millis)
}

fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let year_of_era = year - era * 400;
    let shifted_month = (month + 9) % 12;
    let day_of_year = (153 * shifted_month + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let day_of_era = z - era * 146_097;
    let year_of_era = (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let mp = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = year_of_era + era * 400 + i64::from(month <= 2);
    (year, month, day)
}

// ── Tests: the same assertions as tests/AgendaRulesTests.swift ───────────────

#[cfg(test)]
mod tests {
    use super::*;

    const ANA: &str = "11111111-1111-4111-8111-111111111111";
    const BRUNO: &str = "22222222-2222-4222-8222-222222222222";
    const PESSOA7: &str = "00000000-0000-4000-8000-000000000038";
    const PESSOA8: &str = "00000000-0000-4000-8000-000000000048";
    const BOARD: &str = include_str!("../../../tests/fixtures/agenda/onboarding-board-cards.json");
    const CASES: &str = include_str!("../../../tests/fixtures/agenda/backoffice-cases.json");

    /// São Paulo's day: UTC-3 all year.
    fn sp_day(date: &str) -> (i64, i64) {
        let start = parse_iso(&format!("{date}T03:00:00Z")).unwrap();
        (start, start + 86_400_000)
    }

    fn hm(ms: i64) -> String {
        let local = ms - 3 * 3_600_000;
        let iso = iso_millis(local);
        iso[11..16].to_string()
    }

    fn describe(meetings: &[AgendaMeeting]) -> String {
        meetings.iter().map(|m| format!(
            "{}-{} {} [{}] {} {} #{} {}",
            hm(m.start_ms), hm(m.end_ms), m.title, m.public_id.as_deref().unwrap_or("-"),
            m.department, m.stage_key, m.attempt_sequence, m.attempt_state,
        )).collect::<Vec<_>>().join(" | ")
    }

    fn parse(text: &str) -> Value { serde_json::from_str(text).unwrap() }

    #[test]
    fn who_you_are() {
        assert_eq!(person_id(&json!({ "person_id": ANA, "scope": "own" })).as_deref(), Some(ANA));
        assert_eq!(person_id(&json!([{ "person_id": BRUNO }])).as_deref(), Some(BRUNO));
        assert_eq!(person_id(&json!({ "person_id": null })), None);
        assert_eq!(person_id(&json!("html")), None);
    }

    #[test]
    fn the_onboarding_board() {
        let board = parse(BOARD);
        let nov19 = sp_day("2026-11-19");
        assert_eq!(describe(&meetings_from_cases(&board, ANA, nov19)),
            "09:00-10:30 Studio 2 / actuar [ZQ1002] onboarding connection #2 confirmed \
             | 10:30-12:00 Cliente 3 [-] onboarding connection_2 #1 confirmed \
             | 14:30-16:00 Academia 1 | TOLETUS [ZQ1001] onboarding connection_2 #1 confirmed");
        assert_eq!(meetings_from_cases(&board, &ANA.to_uppercase(), nov19).len(), 3);
        assert_eq!(describe(&meetings_from_cases(&board, BRUNO, nov19)), "");
        assert_eq!(describe(&meetings_from_cases(&board, ANA, sp_day("2026-11-12"))), "");
    }

    #[test]
    fn the_backoffice_list() {
        let cases = parse(CASES);
        let nov19 = sp_day("2026-11-19");
        assert_eq!(describe(&meetings_from_cases(&cases, BRUNO, nov19)),
            "11:00-12:00 Studio 6 / actuar [ZQ1006] backoffice contact #1 confirmed \
             | 15:00-16:00 Cliente 7 [-] backoffice contact #1 confirmed \
             | 16:00-17:00 cliente 8 da silva - Toletus AB4008 - Actuar [ZQ1008] backoffice contact #1 confirmed");
        assert_eq!(describe(&meetings_from_cases(&cases, PESSOA7, nov19)),
            "11:00-12:00 Academia 9 | TOLETUS [ZQ1009] onboarding connection #1 confirmed");
        assert_eq!(describe(&meetings_from_cases(&cases, PESSOA8, nov19)), "");
        assert_eq!(describe(&meetings_from_cases(&cases, PESSOA8, sp_day("2026-11-24"))),
            "09:30-11:00 cliente 12 da silva - Toletus AB4012 - Actuar [ZQ1012] onboarding connection #2 confirmed");
    }

    #[test]
    fn odd_payloads() {
        let nov19 = sp_day("2026-11-19");
        assert!(meetings_from_cases(&json!("nope"), ANA, nov19).is_empty());
        let board = parse(BOARD);
        assert_eq!(meetings_from_cases(&board["data"], ANA, nov19).len(), 3);
        let cancelled = json!({ "data": [{ "id": "c1", "customer_name": "X", "operational_meeting_kanban": { "stages": [{
            "stageKey": "connection",
            "meeting": { "id": "m1", "state": "cancelled", "responsiblePersonId": ANA },
            "attempts": [{ "id": "a1", "isEffective": true, "state": "confirmed",
                           "startAt": "2026-11-19T12:00:00+00:00", "endAt": "2026-11-19T13:00:00+00:00" }] }] } }] });
        assert!(meetings_from_cases(&cancelled, ANA, nov19).is_empty());
        let no_end = json!({ "data": [{ "id": "c1", "customer_name": "", "operational_meeting_kanban": { "stages": [{
            "stageKey": "follow_up",
            "meeting": { "id": "m1", "state": "open", "responsiblePersonId": ANA },
            "attempts": [{ "id": "a1", "isEffective": true, "state": "pending",
                           "startAt": "2026-11-19T20:00:00Z", "endAt": null }] }] } }] });
        assert_eq!(describe(&meetings_from_cases(&no_end, ANA, nov19)), "17:00-18:00  [-] onboarding follow_up #1 pending");
        let a = meetings_from_cases(&board, ANA, nov19);
        assert_eq!(merged(vec![a.clone(), a, meetings_from_cases(&parse(CASES), ANA, nov19)]).len(), 3);
    }

    #[test]
    fn titles_and_chips() {
        let welber = "welber vieira freire santos - Toletus GK7045 - Actuar GM3941";
        assert_eq!(public_id(welber, Some("lHdlnPydN7xCZvivRkCi")).as_deref(), Some("GM3941"));
        assert_eq!(attendee_name(welber, Some("GM3941"), None), "welber vieira freire santos - Toletus GK7045 - Actuar");
        let gessika = "géssika milliane toletus PA4083 / actuar GB5940";
        assert_eq!(attendee_name(gessika, public_id(gessika, None).as_deref(), None), "géssika milliane toletus PA4083 / actuar");
        assert_eq!(attendee_name("gm3941 - Fulano", Some("GM3941"), None), "Fulano");
        assert_eq!(public_id("L.A. Esportes", None), None);
        assert_eq!(public_id("TOLETUSGM3941", None), None);
        assert_eq!(public_id(welber, Some("ab1234")).as_deref(), Some("AB1234"));
        assert_eq!(attendee_name(welber, Some("GM3941"), Some(" Welber ")), "Welber");
        assert_eq!(public_id("Loja X-GM1234", None).as_deref(), Some("X-GM1234"));
    }

    #[test]
    fn what_the_panel_is_asked() {
        let nov19 = sp_day("2026-11-19");
        let (rpc, body) = cases_request(Department::Onboarding, ANA, nov19, 1);
        assert_eq!(rpc, "get_onboarding_board_cards_v1");
        assert_eq!(body, json!({
            "p_date_from": "2026-11-19T03:00:00.000Z", "p_date_to": "2026-11-20T02:59:59.999Z",
            "p_entry_from": null, "p_entry_to": null, "p_include_open_carryover": true,
            "p_include_scheduled_pre_release": true, "p_page": 1, "p_page_size": 200, "p_products": null,
            "p_responsible_person_id": ANA, "p_scope": "all", "p_search": null, "p_unassigned_only": false }));
        let (rpc, body) = cases_request(Department::Backoffice, BRUNO, nov19, 2);
        assert_eq!(rpc, "get_backoffice_cases");
        assert_eq!(body, json!({
            "p_date_from": "2026-11-19T03:00:00.000Z", "p_date_to": "2026-11-20T02:59:59.999Z",
            "p_department": "all", "p_entry_from": null, "p_entry_to": null, "p_include_open_carryover": true,
            "p_page": 2, "p_page_size": 50, "p_pipeline_id": null, "p_products": null,
            "p_responsible_person_id": BRUNO, "p_scope": "all", "p_search": null, "p_status": "all",
            "p_unassigned_only": false }));
        assert_eq!(login_body("a@b.c", "d41d"), json!({ "AppSource": "Actuar,FacilFit,Ediz", "Email": "a@b.c", "Password": "d41d" }));
        assert_eq!(rpc_url(ORGANIZATION_CONTEXT_RPC), "https://query-gateway.actuar.group/rest/v1/rpc/get_current_organization_context");
    }

    #[test]
    fn paging() {
        assert_eq!(next_page(&parse(BOARD), 1), None);
        assert_eq!(next_page(&json!({ "has_more": true }), 1), Some(2));
        assert_eq!(next_page(&json!({ "total_count": 103, "page_size": 50 }), 1), Some(2));
        assert_eq!(next_page(&json!({ "total_count": 103, "page_size": 50 }), 3), None);
        assert_eq!(next_page(&json!({ "has_more": true }), MAX_PAGES), None);
    }

    #[test]
    fn days_and_timestamps() {
        assert_eq!(iso_millis(sp_day("2026-11-19").0), "2026-11-19T03:00:00.000Z");
        assert_eq!(iso_millis(parse_iso("2026-11-16T11:19:53.30099+00:00").unwrap()), "2026-11-16T11:19:53.300Z");
        assert_eq!(parse_iso("2026-11-19T09:00:00-03:00"), parse_iso("2026-11-19T12:00:00Z"));
        assert_eq!(parse_iso("not a date"), None);
    }
}
