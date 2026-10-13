// What Claude Code has been doing, and what it cost.
//
// Port of ClaudeUsageReader.swift + ClaudeUsagePricing.swift. Reads Claude
// Code's own transcripts (`~/.claude/projects/**/*.jsonl`) and turns them into
// spend, tokens and activity for the AI Agents dashboard.
//
// Two things make this cheap enough to run live:
//
// * **Incremental.** Every file is remembered by size + mtime + the byte offset
//   already folded in. An untouched file costs one `stat`; a file the running
//   session just appended to costs only the new bytes.
// * **Bounded.** Only the last `WINDOW_DAYS` of history is kept, so the cache
//   and the dedup set do not grow without limit.
//
// Deduplication is not optional. Resumed and forked sessions replay earlier
// turns into new transcripts, so counting them twice inflates spend by roughly
// 2.3x on a machine that resumes often. The `message.id` is globally unique per
// assistant turn, and is the key.

use std::collections::HashMap;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use crate::platform;

/// Days of history kept on disk. A little more than the grid draws, so a
/// timezone edge never empties the oldest column.
const WINDOW_DAYS: i64 = 100;
/// The activity grid is exactly 13 weeks, like Claude Code's own.
const ACTIVITY_DAYS: i64 = 91;

// ── Token counts ──────────────────────────────────────────────────────────────
//
// Claude Code records cache creation twice: once lumped into
// `cache_creation_input_tokens`, and once split by TTL inside
// `cache_creation.{ephemeral_5m_input_tokens, ephemeral_1h_input_tokens}`. The
// two TTLs are billed differently, so they are kept apart.

#[derive(Debug, Default, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct TokenCounts {
    #[serde(default)]
    pub input: i64,
    #[serde(default)]
    pub output: i64,
    #[serde(default)]
    pub cache_write_5m: i64,
    #[serde(default)]
    pub cache_write_1h: i64,
    #[serde(default)]
    pub cache_read: i64,
}

impl TokenCounts {
    pub fn total(&self) -> i64 {
        self.input + self.output + self.cache_write_5m + self.cache_write_1h + self.cache_read
    }

    /// Share of the total that was served from cache (0–1). 0 when nothing moved.
    pub fn cache_share(&self) -> f64 {
        let t = self.total();
        if t > 0 {
            self.cache_read as f64 / t as f64
        } else {
            0.0
        }
    }

    pub fn add(&mut self, o: &TokenCounts) {
        self.input += o.input;
        self.output += o.output;
        self.cache_write_5m += o.cache_write_5m;
        self.cache_write_1h += o.cache_write_1h;
        self.cache_read += o.cache_read;
    }

    /// Decodes one `message.usage` object from a transcript.
    ///
    /// Records written before the per-TTL split existed carry only the lump,
    /// which is attributed to the 5-minute cache — the cheaper of the two, so
    /// an old record is never over-charged.
    fn from_usage(usage: &serde_json::Value) -> TokenCounts {
        let int = |v: Option<&serde_json::Value>| v.and_then(|x| x.as_i64()).unwrap_or(0);
        let mut c = TokenCounts {
            input: int(usage.get("input_tokens")),
            output: int(usage.get("output_tokens")),
            cache_read: int(usage.get("cache_read_input_tokens")),
            ..Default::default()
        };
        if let Some(split) = usage.get("cache_creation") {
            c.cache_write_5m = int(split.get("ephemeral_5m_input_tokens"));
            c.cache_write_1h = int(split.get("ephemeral_1h_input_tokens"));
        }
        if c.cache_write_5m + c.cache_write_1h == 0 {
            c.cache_write_5m = int(usage.get("cache_creation_input_tokens"));
        }
        c
    }
}

// ── Pricing ───────────────────────────────────────────────────────────────────

/// US dollars per million tokens.
#[derive(Debug, Clone, Copy)]
pub struct ModelPrice {
    pub input: f64,
    pub output: f64,
    pub cache_read: f64,
}

impl ModelPrice {
    /// Writing to the 5-minute cache costs 1.25x the input rate, the 1-hour
    /// cache 2x. Both multipliers were measured on the Mac, not assumed.
    fn cache_write_5m(&self) -> f64 {
        self.input * 1.25
    }
    fn cache_write_1h(&self) -> f64 {
        self.input * 2.00
    }
}

const fn p(input: f64, output: f64, cache_read: f64) -> ModelPrice {
    ModelPrice {
        input,
        output,
        cache_read,
    }
}

/// Prices every model Claude Code can write into a transcript. Same table as
/// `ClaudePricing.table`, which was calibrated against Claude Code's own
/// `cost-state` records to the cent.
const TABLE: [(&str, ModelPrice); 14] = [
    ("claude-opus-5-5", p(4.00, 20.00, 0.20)),
    ("claude-opus-5", p(5.00, 25.00, 0.50)),
    ("claude-opus-4-8", p(5.00, 25.00, 0.50)),
    ("claude-opus-4-7", p(5.00, 25.00, 0.50)),
    ("claude-opus-4-6", p(5.00, 25.00, 0.50)),
    ("claude-fable-5-1", p(10.00, 50.00, 0.25)),
    ("claude-fable-5", p(10.00, 50.00, 1.00)),
    ("claude-mythos-5-1", p(10.00, 50.00, 0.25)),
    ("claude-mythos-5", p(10.00, 50.00, 1.00)),
    ("claude-sonnet-5-5", p(2.00, 10.00, 0.20)),
    ("claude-sonnet-5", p(2.00, 10.00, 0.20)),
    ("claude-sonnet-4-6", p(3.00, 15.00, 0.30)),
    ("claude-haiku-5-5", p(0.10, 0.50, 0.01)),
    ("claude-haiku-4-5", p(1.00, 5.00, 0.10)),
];

/// Fallback for a model released after this build. Opus-tier, so a new model is
/// over-stated rather than silently free; the dashboard flags it.
const UNKNOWN_FALLBACK: ModelPrice = p(5.00, 25.00, 0.50);

/// Models that carry no cost and must never reach the pricer.
fn is_billable(model: &str) -> bool {
    !model.is_empty() && model != "<synthetic>"
}

/// Resolves a transcript model string to a price.
///
/// Handles two shapes the raw records use beyond the plain id: a `[1m]` suffix
/// for the long-context variant (same rates), and a dated suffix such as
/// `claude-haiku-4-5-20251001`.
pub fn price_for(model: &str) -> (ModelPrice, bool) {
    let base = model.replace("[1m]", "");
    for (id, price) in TABLE.iter() {
        if base == *id {
            return (*price, true);
        }
    }
    // Longest matching prefix wins, so `claude-opus-5-5-2026…` does not resolve
    // to `claude-opus-5`.
    let mut best: Option<(&str, ModelPrice)> = None;
    for (id, price) in TABLE.iter() {
        if base.starts_with(id) && best.map(|(b, _)| id.len() > b.len()).unwrap_or(true) {
            best = Some((id, *price));
        }
    }
    match best {
        Some((_, price)) => (price, true),
        None => (UNKNOWN_FALLBACK, false),
    }
}

/// Dollar value of a bundle of tokens for one model.
pub fn cost(model: &str, counts: &TokenCounts) -> f64 {
    let (price, _) = price_for(model);
    counts.input as f64 / 1_000_000.0 * price.input
        + counts.output as f64 / 1_000_000.0 * price.output
        + counts.cache_write_5m as f64 / 1_000_000.0 * price.cache_write_5m()
        + counts.cache_write_1h as f64 / 1_000_000.0 * price.cache_write_1h()
        + counts.cache_read as f64 / 1_000_000.0 * price.cache_read
}

/// Short label for the dashboard, e.g. `claude-opus-5-5` → "Opus 5.5".
pub fn display_name(model: &str) -> String {
    let long_context = model.contains("[1m]");
    let s = model.replace("[1m]", "");
    let Some(rest) = s.strip_prefix("claude-") else {
        return model.to_string();
    };
    let parts: Vec<&str> = rest
        .split('-')
        .filter(|part| !(part.len() == 8 && part.chars().all(|c| c.is_ascii_digit())))
        .collect();
    let Some(family) = parts.first().filter(|f| !f.is_empty()) else {
        return model.to_string();
    };
    let version = parts[1..].join(".");
    let mut name = String::new();
    let mut chars = family.chars();
    if let Some(first) = chars.next() {
        name.extend(first.to_uppercase());
        name.push_str(chars.as_str());
    }
    let label = if version.is_empty() {
        name
    } else {
        format!("{name} {version}")
    };
    if long_context {
        format!("{label} 1M")
    } else {
        label
    }
}

// ── Dates ─────────────────────────────────────────────────────────────────────
//
// The day and hour a record belongs to are local ones: somebody reading "today"
// means their own midnight, not UTC's. There is no date library here — the two
// civil-calendar conversions below are Howard Hinnant's, and the local offset is
// measured once per scan off `platform::local_time()`.

/// Days since 1970-01-01 for a civil date. `days_from_civil`.
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// The inverse: a civil date from days since 1970-01-01.
fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// Seconds the local clock is ahead of UTC, measured now.
///
/// A fixed offset rather than a full timezone database: the only records it can
/// put in the wrong bucket are ones within an hour of midnight on a day the
/// clocks changed, and the alternative is a date library for one subtraction.
fn local_offset_secs() -> i64 {
    let t = platform::local_time();
    let local = days_from_civil(t.year as i64, t.month as i64, t.day as i64) * 86_400
        + t.hour as i64 * 3600
        + t.minute as i64 * 60
        + t.second as i64;
    local - now_secs()
}

fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// `2026-10-12T18:04:11.231Z` → epoch seconds. Claude Code writes UTC, and
/// anything that does not parse is skipped rather than guessed at.
fn parse_timestamp(s: &str) -> Option<i64> {
    let bytes = s.as_bytes();
    if bytes.len() < 19 || bytes[4] != b'-' || bytes[7] != b'-' {
        return None;
    }
    let num = |from: usize, to: usize| s.get(from..to)?.parse::<i64>().ok();
    let year = num(0, 4)?;
    let month = num(5, 7)?;
    let day = num(8, 10)?;
    let hour = num(11, 13)?;
    let minute = num(14, 16)?;
    let second = num(17, 19)?;
    Some(days_from_civil(year, month, day) * 86_400 + hour * 3600 + minute * 60 + second)
}

fn day_key(local_secs: i64) -> String {
    let (y, m, d) = civil_from_days(local_secs.div_euclid(86_400));
    format!("{y:04}-{m:02}-{d:02}")
}

fn hour_of(local_secs: i64) -> i64 {
    local_secs.rem_euclid(86_400) / 3600
}

fn hour_key(local_secs: i64) -> String {
    format!("{} {:02}", day_key(local_secs), hour_of(local_secs))
}

// ── Cache ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct Cursor {
    size: u64,
    mtime: f64,
    offset: u64,
}

#[derive(Debug, Serialize, Deserialize)]
struct Cache {
    version: u32,
    cursors: HashMap<String, Cursor>,
    /// message id → day key, so expired ids can be pruned with their day.
    seen_ids: HashMap<String, String>,
    by_day_model: HashMap<String, HashMap<String, TokenCounts>>,
    by_hour_model: HashMap<String, HashMap<String, TokenCounts>>,
    /// day → project → model → counts. Keeping the model lets a project's spend
    /// be priced exactly instead of approximated.
    by_day_project: HashMap<String, HashMap<String, HashMap<String, TokenCounts>>>,
    last_activity: Option<i64>,
    saw_unknown_model: bool,
}

const CACHE_VERSION: u32 = 1;

impl Default for Cache {
    fn default() -> Self {
        Self {
            version: CACHE_VERSION,
            cursors: HashMap::new(),
            seen_ids: HashMap::new(),
            by_day_model: HashMap::new(),
            by_hour_model: HashMap::new(),
            by_day_project: HashMap::new(),
            last_activity: None,
            saw_unknown_model: false,
        }
    }
}

static CACHE: Mutex<Option<Cache>> = Mutex::new(None);

fn cache_path() -> PathBuf {
    platform::config_dir().join("usage-cache.json")
}

fn projects_root() -> PathBuf {
    platform::home_dir().join(".claude").join("projects")
}

// ── Snapshot ──────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize)]
pub struct UsageRow {
    pub name: String,
    pub spend: f64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivityDay {
    /// `yyyy-MM-dd`, local. A string rather than an epoch because it is a label
    /// and a key, never arithmetic, on the other side.
    pub day: String,
    pub spend: f64,
}

/// Everything the AI Agents dashboard draws.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub spend_today: f64,
    pub tokens_today: i64,
    pub cache_share_today: f64,
    /// 24 buckets, local midnight → 23:00, in dollars.
    pub hourly_today: Vec<f64>,
    /// Today, richest first.
    pub by_model: Vec<UsageRow>,
    pub by_project: Vec<UsageRow>,
    /// The whole window, oldest first.
    pub activity: Vec<ActivityDay>,
    pub window_spend: f64,
    pub window_weeks: i64,
    pub active_days: i64,
    pub busiest_day: Option<ActivityDay>,
    /// Epoch seconds, UTC.
    pub last_activity: Option<i64>,
    /// A model with no entry in the price table was seen; figures are estimates.
    pub has_unknown_model: bool,
    /// No transcripts found at all — Claude Code has never run here.
    pub is_empty: bool,
}

impl Default for Snapshot {
    fn default() -> Self {
        Self {
            spend_today: 0.0,
            tokens_today: 0,
            cache_share_today: 0.0,
            hourly_today: vec![0.0; 24],
            by_model: Vec::new(),
            by_project: Vec::new(),
            activity: Vec::new(),
            window_spend: 0.0,
            window_weeks: ACTIVITY_DAYS / 7,
            active_days: 0,
            busiest_day: None,
            last_activity: None,
            has_unknown_model: false,
            is_empty: true,
        }
    }
}

// ── Scanning ──────────────────────────────────────────────────────────────────

fn transcript_paths(root: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let Ok(projects) = std::fs::read_dir(root) else {
        return out;
    };
    for project in projects.flatten() {
        let Ok(files) = std::fs::read_dir(project.path()) else {
            continue;
        };
        for file in files.flatten() {
            let path = file.path();
            if path.extension().and_then(|e| e.to_str()) == Some("jsonl") {
                out.push(path);
            }
        }
    }
    out
}

/// `/Users/me/my.app` → `-Users-me-my-app`, matching Claude Code.
fn encode_path(path: &str) -> String {
    path.chars()
        .map(|c| if c == '/' || c == '.' { '-' } else { c })
        .collect()
}

/// Last resort when a record carries no `cwd`.
fn fallback_name(directory: &str) -> String {
    directory
        .split('-')
        .filter(|s| !s.is_empty())
        .next_back()
        .unwrap_or(directory)
        .to_string()
}

/// Works out which project a turn belongs to.
///
/// Claude Code names a transcript's directory after the project root, with
/// every `/` and `.` replaced by `-`. That encoding is lossy — a directory
/// called `windows-atoll-` is indistinguishable from a path separator — so
/// rather than decode it we re-encode each ancestor of the record's `cwd` and
/// keep the one that matches. Git worktrees are then folded back into their
/// repository: a dozen worktrees of one repo are one project to the person
/// reading the card, not a dozen.
fn project_name(cwd: Option<&str>, directory: &str) -> String {
    let Some(cwd) = cwd.filter(|c| !c.is_empty()) else {
        return fallback_name(directory);
    };
    // Claude Code writes POSIX separators in `cwd` on every platform it
    // encodes a directory name from, and a Windows path is encoded the same
    // way once its backslashes are read as separators.
    let unified = cwd.replace('\\', "/");
    let mut root = unified.clone();
    let mut probe = unified.as_str();
    loop {
        if encode_path(probe) == directory {
            root = probe.to_string();
            break;
        }
        match probe.rfind('/') {
            Some(0) | None => break,
            Some(cut) => probe = &probe[..cut],
        }
    }
    if let Some(marker) = root.find("/.claude/worktrees/") {
        root.truncate(marker);
    }
    let name = root.rsplit('/').find(|s| !s.is_empty()).unwrap_or("");
    if name.is_empty() {
        fallback_name(directory)
    } else {
        name.to_string()
    }
}

/// Folds one transcript line into the cache. Returns false when there was
/// nothing in it to count, which is most lines.
fn fold(cache: &mut Cache, line: &str, directory: &str, offset_secs: i64, cutoff: i64) {
    // Cheap reject before the JSON parser: only assistant turns carry usage.
    if !line.contains("\"usage\"") {
        return;
    }
    let Ok(obj) = serde_json::from_str::<serde_json::Value>(line) else {
        return;
    };
    let Some(message) = obj.get("message") else {
        return;
    };
    let (Some(usage), Some(model)) = (
        message.get("usage"),
        message.get("model").and_then(|m| m.as_str()),
    ) else {
        return;
    };
    if !is_billable(model) {
        return;
    }
    let Some(id) = message.get("id").and_then(|i| i.as_str()) else {
        return;
    };
    if cache.seen_ids.contains_key(id) {
        return; // replayed turn — already counted
    }
    let Some(stamp) = obj.get("timestamp").and_then(|t| t.as_str()) else {
        return;
    };
    let Some(utc) = parse_timestamp(stamp) else {
        return;
    };
    if utc < cutoff {
        return;
    }
    let counts = TokenCounts::from_usage(usage);
    if counts.total() <= 0 {
        return;
    }

    let local = utc + offset_secs;
    let day = day_key(local);
    let hour = hour_key(local);
    let project = project_name(obj.get("cwd").and_then(|c| c.as_str()), directory);

    cache.seen_ids.insert(id.to_string(), day.clone());
    cache
        .by_day_model
        .entry(day.clone())
        .or_default()
        .entry(model.to_string())
        .or_default()
        .add(&counts);
    cache
        .by_hour_model
        .entry(hour)
        .or_default()
        .entry(model.to_string())
        .or_default()
        .add(&counts);
    cache
        .by_day_project
        .entry(day)
        .or_default()
        .entry(project)
        .or_default()
        .entry(model.to_string())
        .or_default()
        .add(&counts);
    if !price_for(model).1 {
        cache.saw_unknown_model = true;
    }
    if cache.last_activity.map(|prev| utc > prev).unwrap_or(true) {
        cache.last_activity = Some(utc);
    }
}

/// Streams complete lines from `offset` and folds them in. Returns the offset
/// just past the last *complete* line, so a transcript being appended to right
/// now is resumed cleanly next pass.
fn ingest(path: &Path, from: u64, directory: &str, cache: &mut Cache, offset_secs: i64, cutoff: i64) -> u64 {
    let Ok(mut file) = std::fs::File::open(path) else {
        return from;
    };
    if file.seek(SeekFrom::Start(from)).is_err() {
        return from;
    }
    let mut consumed = from;
    let mut remainder: Vec<u8> = Vec::new();
    let mut chunk = vec![0u8; 1 << 20];
    loop {
        let read = match file.read(&mut chunk) {
            Ok(0) | Err(_) => break,
            Ok(n) => n,
        };
        remainder.extend_from_slice(&chunk[..read]);
        let mut start = 0;
        while let Some(nl) = remainder[start..].iter().position(|b| *b == b'\n') {
            let end = start + nl;
            if let Ok(line) = std::str::from_utf8(&remainder[start..end]) {
                fold(cache, line, directory, offset_secs, cutoff);
            }
            consumed += (end - start + 1) as u64;
            start = end + 1;
        }
        remainder.drain(..start);
    }
    consumed
}

fn scan(cache: &mut Cache, offset_secs: i64) {
    let cutoff = now_secs() - WINDOW_DAYS * 86_400;
    let paths = transcript_paths(&projects_root());
    let live: std::collections::HashSet<String> = paths
        .iter()
        .map(|p| p.to_string_lossy().to_string())
        .collect();
    // Forget transcripts that have been deleted.
    cache.cursors.retain(|key, _| live.contains(key));

    for path in paths {
        let key = path.to_string_lossy().to_string();
        let Ok(meta) = std::fs::metadata(&path) else {
            continue;
        };
        let size = meta.len();
        let mtime = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs_f64())
            .unwrap_or(0.0);

        let mut cursor = cache.cursors.get(&key).cloned().unwrap_or_default();
        if cursor.size == size && cursor.mtime == mtime {
            continue; // untouched
        }
        if size < cursor.offset {
            cursor = Cursor::default(); // rewritten from the start
        }

        let directory = path
            .parent()
            .and_then(|p| p.file_name())
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();
        cursor.offset = ingest(&path, cursor.offset, &directory, cache, offset_secs, cutoff);
        cursor.size = size;
        cursor.mtime = mtime;
        cache.cursors.insert(key, cursor);
    }
}

fn prune(cache: &mut Cache, offset_secs: i64) {
    let now_local = now_secs() + offset_secs;
    let cutoff_key = day_key(now_local - WINDOW_DAYS * 86_400);
    cache.by_day_model.retain(|day, _| *day >= cutoff_key);
    cache.by_day_project.retain(|day, _| *day >= cutoff_key);
    cache.seen_ids.retain(|_, day| *day >= cutoff_key);
    // Hourly detail is only ever drawn for today; three days is ample.
    let hour_cutoff = day_key(now_local - 3 * 86_400);
    cache
        .by_hour_model
        .retain(|key, _| key.get(..10).map(|d| d >= hour_cutoff.as_str()).unwrap_or(false));
}

// ── Snapshot ──────────────────────────────────────────────────────────────────

fn spend(per_model: &HashMap<String, TokenCounts>) -> f64 {
    per_model.iter().map(|(model, c)| cost(model, c)).sum()
}

fn build_snapshot(cache: &Cache, offset_secs: i64) -> Snapshot {
    let mut snap = Snapshot {
        has_unknown_model: cache.saw_unknown_model,
        last_activity: cache.last_activity,
        is_empty: cache.cursors.is_empty(),
        ..Default::default()
    };

    let now_local = now_secs() + offset_secs;
    let today = day_key(now_local);

    let empty = HashMap::new();
    let today_models = cache.by_day_model.get(&today).unwrap_or(&empty);
    snap.spend_today = spend(today_models);
    let mut totals = TokenCounts::default();
    for counts in today_models.values() {
        totals.add(counts);
    }
    snap.tokens_today = totals.total();
    snap.cache_share_today = totals.cache_share();

    snap.by_model = today_models
        .iter()
        .map(|(model, counts)| UsageRow {
            name: display_name(model),
            spend: cost(model, counts),
        })
        .filter(|row| row.spend > 0.0)
        .collect();
    snap.by_model
        .sort_by(|a, b| b.spend.total_cmp(&a.spend));

    let no_projects = HashMap::new();
    snap.by_project = cache
        .by_day_project
        .get(&today)
        .unwrap_or(&no_projects)
        .iter()
        .map(|(project, per_model)| UsageRow {
            name: project.clone(),
            spend: spend(per_model),
        })
        .filter(|row| row.spend > 0.0)
        .collect();
    snap.by_project
        .sort_by(|a, b| b.spend.total_cmp(&a.spend));

    // Trend — 24 hourly buckets for today.
    for hour in 0..24 {
        let key = format!("{today} {hour:02}");
        if let Some(models) = cache.by_hour_model.get(&key) {
            snap.hourly_today[hour as usize] = spend(models);
        }
    }

    // Activity — one cell per day across the window, oldest first.
    for back in (0..ACTIVITY_DAYS).rev() {
        let key = day_key(now_local - back * 86_400);
        let value = cache.by_day_model.get(&key).map(spend).unwrap_or(0.0);
        let cell = ActivityDay {
            day: key,
            spend: value,
        };
        snap.window_spend += value;
        if value > 0.0 {
            snap.active_days += 1;
        }
        if value > snap.busiest_day.as_ref().map(|d| d.spend).unwrap_or(0.0) {
            snap.busiest_day = Some(cell.clone());
        }
        snap.activity.push(cell);
    }
    snap.window_weeks = ACTIVITY_DAYS / 7;
    snap
}

// ── Entry point ───────────────────────────────────────────────────────────────

/// Rescans what changed and returns a fresh snapshot.
///
/// Blocking: called from a command, which Tauri already runs off the UI thread.
pub fn refresh() -> Snapshot {
    let offset_secs = local_offset_secs();
    let mut guard = match CACHE.lock() {
        Ok(guard) => guard,
        // A panic inside a previous scan must not take the dashboard with it.
        Err(poisoned) => poisoned.into_inner(),
    };
    let cache = guard.get_or_insert_with(load_cache);
    scan(cache, offset_secs);
    prune(cache, offset_secs);
    persist(cache);
    build_snapshot(cache, offset_secs)
}

fn load_cache() -> Cache {
    let Ok(bytes) = std::fs::read(cache_path()) else {
        return Cache::default();
    };
    match serde_json::from_slice::<Cache>(&bytes) {
        Ok(cache) if cache.version == CACHE_VERSION => cache,
        _ => Cache::default(),
    }
}

fn persist(cache: &Cache) {
    let dir = platform::config_dir();
    if platform::ensure_private_dir(&dir).is_err() {
        return;
    }
    if let Ok(bytes) = serde_json::to_vec(cache) {
        let _ = std::fs::write(cache_path(), bytes);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn civil_dates_round_trip() {
        assert_eq!(days_from_civil(1970, 1, 1), 0);
        assert_eq!(civil_from_days(0), (1970, 1, 1));
        for day in [-10_000i64, -1, 0, 1, 19_000, 20_373, 40_000] {
            let (y, m, d) = civil_from_days(day);
            assert_eq!(days_from_civil(y, m, d), day, "day {day}");
        }
    }

    #[test]
    fn timestamps_parse_both_shapes() {
        // 2026-10-12T18:04:11Z
        let plain = parse_timestamp("2026-10-12T18:04:11Z").unwrap();
        let fractional = parse_timestamp("2026-10-12T18:04:11.231Z").unwrap();
        assert_eq!(plain, fractional);
        assert_eq!(day_key(plain), "2026-10-12");
        assert_eq!(hour_of(plain), 18);
        assert_eq!(hour_key(plain), "2026-10-12 18");
        assert!(parse_timestamp("not a date").is_none());
        assert!(parse_timestamp("").is_none());
    }

    #[test]
    fn a_day_key_is_local_midnight_to_midnight() {
        let utc = parse_timestamp("2026-10-12T02:30:00Z").unwrap();
        // Three hours behind UTC: still the 11th where the user is.
        assert_eq!(day_key(utc - 3 * 3600), "2026-10-11");
        assert_eq!(hour_of(utc - 3 * 3600), 23);
    }

    #[test]
    fn prices_resolve_through_suffixes() {
        assert!(price_for("claude-opus-5-5").1);
        assert_eq!(price_for("claude-opus-5-5").0.input, 4.00);
        // The long-context variant bills at the same rates.
        assert_eq!(price_for("claude-opus-5-5[1m]").0.input, 4.00);
        // A dated suffix resolves to the longest matching prefix, not the
        // shorter family above it.
        assert_eq!(price_for("claude-opus-5-5-20260101").0.input, 4.00);
        assert_eq!(price_for("claude-opus-5-20260101").0.input, 5.00);
        // Something newer than this build is priced at the Opus tier and flagged.
        assert!(!price_for("claude-marvel-9").1);
        assert_eq!(price_for("claude-marvel-9").0.input, UNKNOWN_FALLBACK.input);
    }

    #[test]
    fn a_turn_costs_what_claude_code_says_it_does() {
        let counts = TokenCounts {
            input: 1_000,
            output: 2_000,
            cache_write_5m: 10_000,
            cache_write_1h: 0,
            cache_read: 100_000,
        };
        // 1k in at $4/M, 2k out at $20/M, 10k 5m-writes at 1.25x input, 100k
        // reads at $0.20/M.
        let expected = 0.004 + 0.04 + 0.05 + 0.02;
        assert!((cost("claude-opus-5-5", &counts) - expected).abs() < 1e-9);
    }

    #[test]
    fn model_names_read_as_people_write_them() {
        assert_eq!(display_name("claude-opus-5-5"), "Opus 5.5");
        assert_eq!(display_name("claude-haiku-4-5-20251001"), "Haiku 4.5");
        assert_eq!(display_name("claude-fable-5-1[1m]"), "Fable 5.1 1M");
        assert_eq!(display_name("gpt-4o"), "gpt-4o");
    }

    #[test]
    fn usage_counts_both_shapes_of_cache_creation() {
        let split = serde_json::json!({
            "input_tokens": 5,
            "output_tokens": 7,
            "cache_read_input_tokens": 11,
            "cache_creation_input_tokens": 999,
            "cache_creation": { "ephemeral_5m_input_tokens": 3, "ephemeral_1h_input_tokens": 2 },
        });
        let counts = TokenCounts::from_usage(&split);
        assert_eq!(counts.cache_write_5m, 3);
        assert_eq!(counts.cache_write_1h, 2);
        assert_eq!(counts.total(), 5 + 7 + 11 + 3 + 2);

        // Written before the split existed: the lump is attributed to the
        // cheaper 5-minute cache rather than being dropped.
        let lump = serde_json::json!({
            "input_tokens": 1,
            "cache_creation_input_tokens": 40,
        });
        let counts = TokenCounts::from_usage(&lump);
        assert_eq!(counts.cache_write_5m, 40);
        assert_eq!(counts.cache_write_1h, 0);
    }

    #[test]
    fn a_replayed_turn_is_counted_once() {
        let mut cache = Cache::default();
        let line = r#"{"timestamp":"2026-10-12T18:04:11.231Z","cwd":"/Users/me/app","message":{"id":"msg_1","model":"claude-opus-5-5","usage":{"input_tokens":1000,"output_tokens":1000}}}"#;
        let cutoff = parse_timestamp("2020-01-01T00:00:00Z").unwrap();
        fold(&mut cache, line, "-Users-me-app", 0, cutoff);
        fold(&mut cache, line, "-Users-me-app", 0, cutoff);
        let counts = cache.by_day_model["2026-10-12"]["claude-opus-5-5"];
        assert_eq!(counts.input, 1000, "a resumed session replays the same turn");
        assert_eq!(cache.seen_ids.len(), 1);
    }

    #[test]
    fn a_record_outside_the_window_is_skipped() {
        let mut cache = Cache::default();
        let line = r#"{"timestamp":"2019-01-01T00:00:00Z","message":{"id":"old","model":"claude-opus-5-5","usage":{"input_tokens":1000}}}"#;
        let cutoff = parse_timestamp("2020-01-01T00:00:00Z").unwrap();
        fold(&mut cache, line, "-x", 0, cutoff);
        assert!(cache.by_day_model.is_empty());
    }

    #[test]
    fn lines_without_usage_cost_nothing_to_reject() {
        let mut cache = Cache::default();
        fold(&mut cache, r#"{"type":"user","message":{"content":"hi"}}"#, "-x", 0, 0);
        fold(&mut cache, "", "-x", 0, 0);
        fold(&mut cache, "not json at all", "-x", 0, 0);
        assert!(cache.by_day_model.is_empty());
    }

    #[test]
    fn a_project_is_named_after_its_root() {
        // The encoded directory matches the root exactly.
        assert_eq!(project_name(Some("/Users/me/windows-atoll-"), "-Users-me-windows-atoll-"), "windows-atoll-");
        // Started deep inside the tree: the ancestor that re-encodes to the
        // directory is the root.
        assert_eq!(project_name(Some("/Users/me/app/src/deep"), "-Users-me-app"), "app");
        // A worktree folds back into the repository it belongs to.
        assert_eq!(
            project_name(Some("/Users/me/app/.claude/worktrees/feature-x"), "-Users-me-app--claude-worktrees-feature-x"),
            "app",
        );
        // No cwd at all: the last segment of the encoded directory.
        assert_eq!(project_name(None, "-Users-me-app"), "app");
        assert_eq!(project_name(Some(""), "-Users-me-app"), "app");
    }

    #[test]
    fn a_windows_cwd_is_read_the_same_way() {
        assert_eq!(
            project_name(Some(r"C:\Users\me\app"), "C:-Users-me-app"),
            "app",
        );
    }
}
