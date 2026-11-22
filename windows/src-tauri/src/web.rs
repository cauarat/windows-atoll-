// ChatGPT and the site, inside the island.
//
// On the Mac both are WKWebViews in the island's own view tree: ChatGPT in
// WebChatHostView's card under the island's tabs, the site in NotchSiteView
// over the whole island. Here each is a native webview laid over the card the
// island draws for it (island/pageHost.ts decides when, and sends the card's
// rect): a child webview of the island's own window on Windows — Tauri's
// multiwebview, behind its `unstable` feature — so the page moves, stacks and
// clips with the island as one window; on Linux, where Tauri packs a window's
// child webviews into its GtkBox and none can be put over the card, a
// borderless window glued over the same rect.
//
// The island draws everything around and under the page — the header row, the
// card, the dots while it loads, the words when it cannot load — and nothing it
// draws can sit on top of a native page. So a page is on screen only when there
// is something to see: once the load it was given has finished, as the Mac's
// fades in on didFinish. Until then, and whenever it is blocked or has failed,
// the island's own card is what shows.
//
// Both are created hidden on about:blank at launch, like every webview in this
// app — one built later, from a command, deadlocks WebView2 or comes up blank —
// and fetch nothing until they are first shown: nobody who has not asked for
// ChatGPT or the site has a page open to either. Out of sight they go quiet
// (muted), and then cold (back on about:blank): ChatGPT after the Mac's ten
// minutes, the site almost at once, as NotchSiteView blanks its page on close.
//
// What decides all of that — the states, when a page may be on screen, when it
// goes cold, which pixels it lands on — is page_model.rs, which has no Tauri in
// it. This file hosts the pages and talks to the island.
//
// The pages get no IPC. They are remote origins, and capabilities/default.json
// names the webviews it covers, theirs not among them, so every invoke from
// chatgpt.com or the site is refused. (Tauri still injects its scripts into
// every webview it creates; it is the ACL that says no.)

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant};

use serde::Serialize;
use tauri::webview::{Color, DownloadEvent, NewWindowResponse, PermissionKind, PermissionResponse};
use tauri::{AppHandle, Emitter, Manager, Url, Webview};

use crate::island;
use crate::log;
use crate::page_model::{self, Card, Page, Phase, Signal, Snapshot, BLANK};
use crate::platform;

pub const SITE_LABEL: &str = "site";
pub const CHAT_LABEL: &str = "webchat";

/// Both pages, in the order their slots are kept.
const LABELS: [&str; 2] = [CHAT_LABEL, SITE_LABEL];

/// chatgpt.com pulls assets and sign-in flows from a handful of OpenAI domains,
/// so the allowlist covers the family rather than the single host — the Mac's
/// `webChatAllowedHosts`. Everything else is opened in the user's real browser:
/// a card inside the island is the worst possible place to land on an
/// arbitrary web page.
const CHAT_HOSTS: [&str; 8] = [
    "chatgpt.com",
    "chat.openai.com",
    "openai.com",
    "auth.openai.com",
    "auth0.openai.com",
    "oaistatic.com",
    "oaiusercontent.com",
    "sora.com",
];

pub const CHAT_URL: &str = "https://chatgpt.com/";

/// Edge's own user agent. WebView2 identifies itself as an embedded view by
/// default, which is what the sign-in flow turns away — the Mac sends Safari's
/// for the same reason.
const CHAT_USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 \
     (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36 Edg/140.0.0.0";

/// ChatGPT's own data directory, under the app's local data: its own WebView2
/// profile, as the Mac gives it a WKWebsiteDataStore of its own. The profile is
/// what its dark scheme is set on, and what "Clear ChatGPT data" will delete.
const CHAT_DATA_DIR: &str = "webchat-webview";

/// A page must not be able to close the window it is drawn in. WebView2 answers
/// `window.close()` from a top-level page with no history by destroying the
/// webview's container, which would leave the island with a hole and a webview
/// handle pointing nowhere.
const NO_CLOSE: &str = "try { Object.defineProperty(window, 'close', \
     { value: function () {}, writable: false, configurable: false }); } catch (_) {}";

/// How long after a page was put away it still counts as the same visit for
/// the keyboard: the island takes a page off screen while it is moving and puts
/// it back once it has settled, and that must not pull the keyboard away from
/// whatever the user went on to type in.
const KEYBOARD_GRACE: Duration = Duration::from_secs(2);

/// The card's fill behind a page that has not painted: #141518.
fn card_color() -> Color {
    let (r, g, b) = page_model::CARD_RGB;
    Color(r, g, b, 255)
}

// ── Policy ───────────────────────────────────────────────────────────────────

/// True when `host` is an allowed host or a subdomain of one.
///
/// The suffix match is anchored on a dot so a lookalike cannot slip through:
/// "chatgpt.com" matches and "api.chatgpt.com" matches, but "notchatgpt.com"
/// and "chatgpt.com.evil.net" do not.
fn host_allowed(host: &str, allowed: &[&str]) -> bool {
    if host.is_empty() {
        return false;
    }
    let h = host.to_lowercase();
    allowed
        .iter()
        .any(|a| h == *a || h.ends_with(&format!(".{a}")))
}

/// True when a main-frame navigation to `url` stays inside the island —
/// `webChatKeepsInIsland`. Non-web schemes never stay: they are not ours to
/// render.
fn keeps_in_window(url: &Url, allowed: &[&str]) -> bool {
    if url.scheme() != "https" && url.scheme() != "http" {
        return false;
    }
    host_allowed(url.host_str().unwrap_or(""), allowed)
}

/// The Mac's `safeWebURL`: http or https, with a host. The only addresses a
/// page may hand to the browser.
fn safe_web_url(url: &Url) -> bool {
    matches!(url.scheme(), "http" | "https") && url.host_str().is_some_and(|h| !h.is_empty())
}

/// The placeholder a page holds while it is cold.
fn is_blank(url: &Url) -> bool {
    url.scheme() == "about" && url.path() == "blank"
}

/// One of the app's own origins: WebView2 serves Tauri's custom protocols —
/// the island's own page among them — under `*.localhost`, and a dev build is
/// served from Vite. A remote page must never be able to take a page onto one,
/// where it would count as local.
fn is_app_origin(app: &AppHandle, url: &Url) -> bool {
    if url.host_str().is_some_and(|h| h.to_ascii_lowercase().ends_with(".localhost")) {
        return true;
    }
    #[cfg(dev)]
    if let Some(dev) = app.config().build.dev_url.as_ref() {
        if dev.origin() == url.origin() {
            return true;
        }
    }
    let _ = app;
    false
}

/// The site stays on the host it was pointed at, as it always has here: a link
/// anywhere else opens in the browser. A blob the page made itself counts as
/// its own host's.
fn site_keeps(url: &Url, hosts: &[&str]) -> bool {
    if url.scheme() == "blob" {
        // `blob:https://host/uuid`: the address it was made by is its path.
        return Url::parse(url.path()).is_ok_and(|inner| keeps_in_window(&inner, hosts));
    }
    keeps_in_window(url, hosts)
}

/// The hosts the site may stay on: the one Settings points it at.
fn site_hosts(app: &AppHandle) -> Vec<String> {
    Url::parse(site_url(app).trim())
        .ok()
        .and_then(|u| u.host_str().map(|h| h.to_string()))
        .into_iter()
        .collect()
}

/// A link to something that is not a web page — mail, a phone number, an app's
/// own scheme — which NotchSiteWeb hands to the system when it was clicked.
/// Never a local file or a script.
fn opens_with_system(url: &str) -> bool {
    let Ok(url) = Url::parse(url) else { return false };
    !matches!(
        url.scheme(),
        "http" | "https" | "about" | "blob" | "file" | "data" | "javascript" | "vbscript"
    )
}

/// The page each label opens, or nothing when it has none: an empty or
/// non-web site setting. Pure, so the rule is testable.
fn page_url(label: &str, site: &str) -> Option<Url> {
    let raw = if label == CHAT_LABEL { CHAT_URL } else { site.trim() };
    let url = Url::parse(raw).ok()?;
    matches!(url.scheme(), "https" | "http").then_some(url)
}

/// The site Settings points at.
fn site_url(app: &AppHandle) -> String {
    app.try_state::<crate::Shared>()
        .map(|shared| shared.settings.lock().unwrap().site_url.clone())
        .unwrap_or_default()
}

/// Whether `url` stays in the page: ChatGPT's hosts for ChatGPT, the
/// configured host for the site — never one of the app's own origins.
fn stays(app: &AppHandle, label: &'static str, url: &Url) -> bool {
    if label == CHAT_LABEL {
        return keeps_in_window(url, &CHAT_HOSTS);
    }
    let hosts = site_hosts(app);
    let hosts: Vec<&str> = hosts.iter().map(String::as_str).collect();
    site_keeps(url, &hosts) && !is_app_origin(app, url)
}

/// Whether a main-frame navigation may happen in the page. Each keeps to its
/// hosts and hands any other web address to the browser — WebChatController's
/// rule, and the site's since it first had one. Neither may wander back onto
/// the placeholder unless the host is the one taking it there: going back past
/// the first page of a visit would land on a blank card.
fn allows(app: &AppHandle, label: &'static str, url: &Url) -> bool {
    if is_blank(url) {
        return with(label, |slot| std::mem::take(&mut slot.blanking)).unwrap_or(false);
    }
    if stays(app, label, url) {
        return true;
    }
    if safe_web_url(url) && !is_app_origin(app, url) {
        platform::open_url(url.as_str());
    }
    false
}

/// `target=_blank`, `window.open`: never a second webview. An address the page
/// may stay on loads in place, any other web address opens in the browser —
/// WebChatController.createWebViewWith, and the same rule for the site.
fn new_window(app: &AppHandle, label: &'static str, url: Url) {
    if stays(app, label, &url) {
        if let Some(page) = host::webview(app, label) {
            let _ = page.navigate(url);
        }
    } else if safe_web_url(&url) && !is_app_origin(app, &url) {
        platform::open_url(url.as_str());
    }
}

/// Downloads go to the browser — a response WebKit cannot show is opened there
/// by WebChatController — never into a folder from a chrome-less page.
fn download(event: DownloadEvent<'_>) -> bool {
    match event {
        DownloadEvent::Requested { url, .. } => {
            if safe_web_url(&url) {
                platform::open_url(url.as_str());
            }
            false
        }
        _ => true,
    }
}

/// Microphone and camera are refused without a prompt, as WebChatController
/// refuses every capture request: voice mode must not hang on a question asked
/// in a chrome-less card. Location and notifications too — WKWebView never
/// offers either.
fn permission(kind: PermissionKind) -> PermissionResponse {
    match kind {
        PermissionKind::Microphone
        | PermissionKind::Camera
        | PermissionKind::Geolocation
        | PermissionKind::Notifications => PermissionResponse::Deny,
        _ => PermissionResponse::Default,
    }
}

// ── State ────────────────────────────────────────────────────────────────────

/// What the host keeps about one page, beside its `Page`.
#[derive(Default)]
struct Slot {
    page: Page,
    /// The card it was last put over, logical px of the island window.
    card: Option<Card>,
    /// The address it was last given to load: the site loads again when
    /// Settings has pointed it elsewhere since.
    loaded: Option<String>,
    /// Where ChatGPT was when it went cold, to come back to — the address half
    /// of WebChatController's saved `interactionState`.
    resume: Option<String>,
    /// The host is taking it to about:blank: the one navigation to the
    /// placeholder the policy lets through.
    blanking: bool,
    /// A fresh load of the site is under way: its history starts over once it
    /// has loaded, as a new WKWebView's would.
    fresh: bool,
    /// What the host last did with it, so a change is acted on once.
    on_screen: bool,
    /// What the island was last told.
    said: Option<Snapshot>,
    /// When it was last put away, and whether the island had the keyboard then.
    hidden: Option<(Instant, bool)>,
}

static SLOTS: LazyLock<Mutex<[Slot; 2]>> = LazyLock::new(Default::default);

/// Runs `f` on a page's slot. The lock is never held while a webview is
/// called: WebView2 can raise an event from inside a call, and its handler
/// comes back here.
fn with<T>(label: &str, f: impl FnOnce(&mut Slot) -> T) -> Option<T> {
    let i = LABELS.iter().position(|l| *l == label)?;
    let mut slots = SLOTS.lock().unwrap();
    Some(f(&mut slots[i]))
}

fn known(label: &str) -> Result<&'static str, String> {
    LABELS
        .iter()
        .copied()
        .find(|l| *l == label)
        .ok_or_else(|| format!("no page called {label}"))
}

fn wanted(label: &str) -> bool {
    with(label, |slot| slot.page.wanted).unwrap_or(false)
}

fn on_screen(label: &str) -> bool {
    with(label, |slot| slot.on_screen).unwrap_or(false)
}

/// Whether a page in the island holds the keyboard — asked for and not put
/// away. While one does, the island stays able to take focus.
pub fn holds_keyboard() -> bool {
    LABELS.iter().any(|l| wanted(l))
}

// ── Talking to the island ────────────────────────────────────────────────────

/// The "page-state" event, and what `page_show` answers.
#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct PageState {
    label: &'static str,
    state: &'static str,
    /// The HTTP status, for `blocked`.
    #[serde(skip_serializing_if = "Option::is_none")]
    status: Option<u16>,
    /// The WebView2 error name, for `failed`.
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    title: Option<String>,
    can_go_back: bool,
}

impl PageState {
    fn of(label: &'static str, snapshot: Snapshot) -> Self {
        Self {
            label,
            state: snapshot.state,
            status: snapshot.status,
            error: snapshot.error,
            url: snapshot.url,
            title: snapshot.title,
            can_go_back: snapshot.can_go_back,
        }
    }
}

/// The "page-escape" event.
#[derive(Serialize, Clone)]
struct PageEscape {
    label: &'static str,
}

fn state(label: &'static str) -> PageState {
    let snapshot = with(label, |slot| slot.page.snapshot()).unwrap_or_else(|| Page::new().snapshot());
    PageState::of(label, snapshot)
}

/// Brings the screen and the island up to date with a page: shows or hides it
/// when that changed, and tells the island when what it knows changed.
fn settle(app: &AppHandle, label: &'static str) {
    let Some((visible, changed, news)) = with(label, |slot| {
        let visible = slot.page.visible();
        let changed = visible != slot.on_screen;
        slot.on_screen = visible;
        let snapshot = slot.page.snapshot();
        let news = (slot.said.as_ref() != Some(&snapshot)).then(|| {
            slot.said = Some(snapshot.clone());
            snapshot
        });
        (visible, changed, news)
    }) else {
        return;
    };
    if changed {
        host::set_visible(app, label, visible);
        if visible {
            host::give_keyboard(app, label);
        } else {
            host::keyboard_home(app);
        }
    }
    if let Some(snapshot) = news {
        let _ = app.emit_to(island::WINDOW_LABEL, "page-state", PageState::of(label, snapshot));
    }
}

// ── Showing, hiding, loading ─────────────────────────────────────────────────

/// What has to happen to a page's document.
enum Load {
    Nothing,
    Navigate(Url),
    Reload,
}

/// Decides whether a page that is being shown, or reloaded from cold, needs a
/// load, and marks it as loading if so.
fn plan_load(label: &'static str, slot: &mut Slot, site: &str) -> Load {
    let target = page_url(label, site);
    let moved = label == SITE_LABEL
        && slot.loaded.as_deref() != target.as_ref().map(Url::as_str);
    if slot.page.phase != Phase::Cold && !moved {
        return Load::Nothing;
    }
    let target = if label == CHAT_LABEL {
        slot.resume
            .take()
            .and_then(|u| Url::parse(&u).ok())
            .filter(|u| keeps_in_window(u, &CHAT_HOSTS))
            .or(target)
    } else {
        target
    };
    let Some(url) = target else {
        // An empty or broken Site setting: nothing to load, said as a failure
        // the island can show.
        slot.loaded = None;
        slot.page.phase = Phase::Failed("InvalidUrl".to_string());
        return Load::Nothing;
    };
    slot.page.begin_load(true);
    slot.loaded = Some(url.to_string());
    slot.fresh = label == SITE_LABEL;
    Load::Navigate(url)
}

fn run(label: &'static str, page: &Webview, load: Load) {
    let result = match load {
        Load::Nothing => return,
        Load::Navigate(url) => page.navigate(url),
        Load::Reload => page.reload(),
    };
    if let Err(err) = result {
        log::line(format!("{label} could not load — {err}"));
        with(label, |slot| slot.page.phase = Phase::Failed("UnexpectedError".to_string()));
    }
}

/// `page_show`: over `card`, loaded, and on screen once it has something to
/// show.
fn show(app: &AppHandle, label: &'static str, card: Card) -> Result<PageState, String> {
    if !card.usable() {
        return Err(format!("{label}: the card has no room for a page"));
    }
    let Some(page) = host::webview(app, label) else {
        // Its webview could not be built at launch. Said as a failure, so the
        // island shows its words and Try again rather than dots for ever.
        log::line(format!("{label} asked for, but it was never built"));
        let state = PageState::of(
            label,
            Snapshot {
                state: "failed",
                status: None,
                error: Some("Unavailable".to_string()),
                url: None,
                title: None,
                can_go_back: false,
            },
        );
        let _ = app.emit_to(island::WINDOW_LABEL, "page-state", state.clone());
        return Ok(state);
    };
    // One page on the island at a time, as there is one view at a time on the
    // Mac: the other one leaves first.
    for other in LABELS {
        if other != label && wanted(other) {
            hide(app, other);
        }
    }
    let site = site_url(app);
    let (arriving, bring_forward, load) = with(label, |slot| {
        let arriving = !slot.page.wanted;
        // Back within moments of being put away is the island settling, not
        // the user asking again: the keyboard goes back only if it was there.
        let bring_forward = match slot.hidden {
            Some((at, had)) if at.elapsed() < KEYBOARD_GRACE => had,
            _ => true,
        };
        slot.page.show();
        slot.card = Some(card);
        (arriving, bring_forward, plan_load(label, slot, &site))
    })
    .ok_or_else(|| format!("no page called {label}"))?;

    host::place(app, label, card, None);
    if arriving {
        platform::page_set_muted(&page, false);
        host::take_keyboard(app, bring_forward);
    }
    run(label, &page, load);
    settle(app, label);
    Ok(state(label))
}

/// `page_hide`: off screen at once, quiet, and cold once it has stayed away.
fn hide(app: &AppHandle, label: &'static str) {
    let had_keyboard = host::island_has_keyboard(app);
    let Some(Some(epoch)) = with(label, |slot| {
        let epoch = slot.page.hide();
        if epoch.is_some() {
            slot.hidden = Some((Instant::now(), had_keyboard));
        }
        epoch
    }) else {
        return;
    };
    if let Some(page) = host::webview(app, label) {
        platform::page_set_muted(&page, true);
    }
    settle(app, label);
    if !holds_keyboard() {
        host::release_keyboard(app);
    }
    let after = page_model::cold_after(label == CHAT_LABEL);
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(after).await;
        let handle = app.clone();
        let _ = app.run_on_main_thread(move || go_cold(&handle, label, Some(epoch)));
    });
}

/// Back on the placeholder, with nothing of the page left running — after its
/// time out of sight (`epoch`, from the hide that started the wait), or at
/// once (None) when Coucou is switched off.
fn go_cold(app: &AppHandle, label: &'static str, epoch: Option<u64>) {
    let went = with(label, |slot| {
        let due = match epoch {
            Some(epoch) => slot.page.cold_due(epoch),
            None => slot.page.phase != Phase::Cold,
        };
        if !due {
            return false;
        }
        if label == CHAT_LABEL {
            slot.resume = slot
                .page
                .url
                .clone()
                .filter(|u| Url::parse(u).is_ok_and(|u| keeps_in_window(&u, &CHAT_HOSTS)));
        }
        slot.page.go_cold();
        slot.loaded = None;
        slot.fresh = false;
        slot.blanking = true;
        true
    })
    .unwrap_or(false);
    if !went {
        return;
    }
    log::line(format!("{label} page is cold"));
    if let (Some(page), Ok(blank)) = (host::webview(app, label), Url::parse(BLANK)) {
        if page.navigate(blank).is_err() {
            with(label, |slot| slot.blanking = false);
        }
    }
    settle(app, label);
}

/// Try again, or the reload button: ChatGPT goes off screen until it has
/// loaded again (WebChatController.reload), the site stays up with its
/// spinner turning (NotchSiteWeb.reload).
fn reload(app: &AppHandle, label: &'static str) {
    let Some(page) = host::webview(app, label) else { return };
    let current = page.url().ok().filter(safe_web_url);
    let site = site_url(app);
    let Some(load) = with(label, |slot| {
        if slot.page.phase == Phase::Cold || slot.loaded.is_none() {
            return plan_load(label, slot, &site);
        }
        let hide = label == CHAT_LABEL
            || matches!(slot.page.phase, Phase::Failed(_) | Phase::Blocked(_));
        slot.page.begin_load(hide);
        // A page that never got past the placeholder has nothing to reload.
        match current {
            Some(_) => Load::Reload,
            None => slot
                .loaded
                .as_deref()
                .and_then(|u| Url::parse(u).ok())
                .map_or(Load::Nothing, Load::Navigate),
        }
    }) else {
        return;
    };
    run(label, &page, load);
    settle(app, label);
}

// ── What the pages report ────────────────────────────────────────────────────

fn on_signal(app: &AppHandle, label: &'static str, signal: Signal) {
    match signal {
        Signal::Started { id, url, by_user, cancelled } => {
            // A link to a mail address or an app, clicked on the site, is the
            // system's to open (NotchSiteWeb, `.linkActivated`). The policy
            // refuses every such address, so it is decided here from the
            // address alone, whichever of the two heard the navigation first.
            if label == SITE_LABEL && opens_with_system(&url) {
                if by_user {
                    platform::open_url(&url);
                }
                return;
            }
            // Refused by the policy, or the placeholder: not the page loading.
            if cancelled || Url::parse(&url).is_ok_and(|u| is_blank(&u)) {
                return;
            }
            // The site's spinner turns for every navigation; ChatGPT's state
            // only moves for how one ends (page_model::Page::started).
            with(label, |slot| slot.page.started(id, label == SITE_LABEL));
            settle(app, label);
        }
        Signal::Finished { id, success, status, error } => {
            let outcome = page_model::outcome(label == CHAT_LABEL, success, status, error);
            let fresh = with(label, |slot| {
                slot.page.finished(id, outcome);
                let done = slot.fresh && slot.page.phase == Phase::Ready;
                if done {
                    slot.fresh = false;
                }
                done
            })
            .unwrap_or(false);
            settle(app, label);
            if fresh {
                if let Some(page) = host::webview(app, label) {
                    let app = app.clone();
                    platform::page_reset_history(&page, move |can_go_back| {
                        with(label, |slot| slot.page.can_go_back = can_go_back);
                        settle(&app, label);
                    });
                }
            }
        }
        Signal::Source(url) => {
            with(label, |slot| slot.page.set_url(Some(url)));
            settle(app, label);
        }
        Signal::Title(title) => {
            with(label, |slot| slot.page.set_title(Some(title)));
            settle(app, label);
        }
        Signal::History { can_go_back } => {
            with(label, |slot| slot.page.can_go_back = can_go_back);
            settle(app, label);
        }
        Signal::Escape => {
            let _ = app.emit_to(island::WINDOW_LABEL, "page-escape", PageEscape { label });
        }
    }
}

// ── Commands ─────────────────────────────────────────────────────────────────

/// Puts a page over the card at `x, y, width, height` — CSS px of the island's
/// page, its card's `getBoundingClientRect()` — loading it first if it is cold,
/// and shows it once it is ready. Called again for the same page, it only
/// moves it.
#[tauri::command]
pub fn page_show(
    app: AppHandle,
    label: String,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
) -> Result<PageState, String> {
    let label = known(&label)?;
    show(&app, label, Card { x, y, w: width, h: height })
}

/// Hides a page at once — the island calls this before anything moves — and
/// starts its cold timer.
#[tauri::command]
pub fn page_hide(app: AppHandle, label: String) -> Result<(), String> {
    hide(&app, known(&label)?);
    Ok(())
}

/// Every page: the island folding, the close shortcut, Escape on the island.
#[tauri::command]
pub fn page_hide_all(app: AppHandle) {
    hide_all(&app);
}

#[tauri::command]
pub fn page_reload(app: AppHandle, label: String) -> Result<(), String> {
    reload(&app, known(&label)?);
    Ok(())
}

/// The site's back button. Nothing when it cannot go back, or for ChatGPT.
#[tauri::command]
pub fn page_back(app: AppHandle, label: String) -> Result<(), String> {
    let label = known(&label)?;
    if label == SITE_LABEL {
        if let Some(page) = host::webview(&app, label) {
            platform::page_go_back(&page);
        }
    }
    Ok(())
}

/// The page's address in the default browser — the site header's
/// arrow.up.right: where it is now, or the page it opens when it is nowhere.
#[tauri::command]
pub fn page_open_in_browser(app: AppHandle, label: String) -> Result<(), String> {
    let label = known(&label)?;
    let current = host::webview(&app, label)
        .and_then(|page| page.url().ok())
        .filter(safe_web_url);
    if let Some(url) = current.or_else(|| page_url(label, &site_url(&app))) {
        platform::open_url(url.as_str());
    }
    Ok(())
}

pub fn hide_all(app: &AppHandle) {
    for label in LABELS {
        hide(app, label);
    }
}

/// Coucou switched off: both pages away and released at once, as the Mac's
/// controller goes cold when the master switch goes off.
pub fn park(app: &AppHandle) {
    for label in LABELS {
        hide(app, label);
        go_cold(app, label, None);
    }
}

/// The commands the island used before `page_show`/`page_hide`: a page put
/// over the island's whole shape, or put away. Kept until no caller is left.
pub fn toggle(app: &AppHandle, label: &'static str) -> bool {
    if wanted(label) {
        hide(app, label);
        return false;
    }
    let Some(shared) = app.try_state::<crate::Shared>() else { return false };
    let r = *shared.gate.rect.lock().unwrap();
    show(app, label, Card { x: r.x, y: r.y, w: r.w, h: r.h }).is_ok()
}

/// Puts the pages back over their cards after the island moved or was
/// rescaled. A child webview moves with its window by itself; a glued window
/// (Linux) has to be told.
pub fn reanchor(app: &AppHandle) {
    replace(app, None);
}

fn replace(app: &AppHandle, scale: Option<f64>) {
    for label in LABELS {
        let card = with(label, |slot| slot.page.wanted.then_some(slot.card).flatten()).flatten();
        if let Some(card) = card {
            host::place(app, label, card, scale);
        }
    }
}

// ── Built at launch ──────────────────────────────────────────────────────────

/// Both pages, hidden on about:blank: called once from setup, after the
/// island's window exists.
pub fn create(app: &AppHandle) {
    host::create(app);
}

/// ChatGPT's data directory, or None when the app has none to give. It then
/// shares the island's profile, and is left in the system's colours: forcing
/// that profile dark would turn Settings dark with it.
fn chat_data_dir(app: &AppHandle) -> Option<std::path::PathBuf> {
    app.path().app_local_data_dir().ok().map(|dir| dir.join(CHAT_DATA_DIR))
}

/// ChatGPT in its dark theme, on a profile of its own.
fn force_dark(app: &AppHandle, page: &Webview) {
    if chat_data_dir(app).is_some() {
        platform::page_force_dark(page);
    }
}

/// What every page gets once its webview exists, whichever host made it.
fn prepare(app: &AppHandle, label: &'static str, page: &Webview) {
    let handle = app.clone();
    platform::page_hooks(page, move |signal| on_signal(&handle, label, signal));
    // The site keeps its swipe-back, as NotchSiteWeb does; ChatGPT does not
    // (WebChatController). Browser keys stay in a debug build, for F12.
    platform::page_settings(page, label == SITE_LABEL, cfg!(debug_assertions));
    platform::page_register(page);
    platform::page_set_muted(page, true);
    if label == CHAT_LABEL {
        force_dark(app, page);
    }
}

/// Keeps a window's webview answering to its window, now that Tauri's
/// multiwebview makes every webview a child: wry focused the one filling a
/// window whenever the window was focused, and told it when the window moved,
/// and only does so for webviews that fill their window. Without this a window
/// opened by Coucou — Settings, the welcome — takes the keyboard and its page
/// never sees a key until it is clicked.
pub fn keep_hosting(win: &tauri::WebviewWindow) {
    #[cfg(windows)]
    {
        let webview: &Webview = win.as_ref();
        let webview = webview.clone();
        win.on_window_event(move |event| match event {
            tauri::WindowEvent::Focused(true) => {
                let _ = webview.set_focus();
            }
            tauri::WindowEvent::Moved(_) => platform::notify_webview_moved(&webview),
            _ => {}
        });
    }
    #[cfg(not(windows))]
    let _ = win;
}

/// `NOTCHY_SMOKE_VIEW=webchat` (or `site`) in a debug build: once the island
/// is up and its greeting is over, it is asked to open that view, as if its
/// control had been pressed — for the CI run that screenshots a real runner.
#[cfg(debug_assertions)]
pub fn smoke(app: &AppHandle) {
    let Some(view) = std::env::var("NOTCHY_SMOKE_VIEW")
        .ok()
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
    else {
        return;
    };
    let app = app.clone();
    let started = std::thread::Builder::new().name("smoke-open-view".into()).spawn(move || {
        std::thread::sleep(Duration::from_secs(12));
        // Under a first-run welcome the island is parked: wait for it, a while.
        for _ in 0..60 {
            if crate::island_live(&app) {
                break;
            }
            std::thread::sleep(Duration::from_secs(1));
        }
        log::line(format!("smoke: opening {view}"));
        let _ = app.emit_to(island::WINDOW_LABEL, "smoke-open-view", view);
    });
    if let Err(err) = started {
        log::line(format!("thread smoke-open-view failed to start — {err}"));
    }
}

#[cfg(not(debug_assertions))]
pub fn smoke(_app: &AppHandle) {}

// ── Hosts ────────────────────────────────────────────────────────────────────
//
// Two ways to put a page over the card, with the same functions. Both are
// compiled on both systems, so each is type-checked wherever the other is
// built; the system picks which one runs.

#[cfg(windows)]
use child as host;
#[cfg(not(windows))]
use glued as host;

/// A child webview of the island's window (Windows).
#[cfg_attr(not(windows), allow(dead_code))]
mod child {
    use super::*;

    pub fn create(app: &AppHandle) {
        let Some(island) = island::window(app) else {
            log::line("island window missing — no pages");
            return;
        };
        for label in LABELS {
            let Ok(blank) = Url::parse(BLANK) else { return };
            let policy = app.clone();
            let opener = app.clone();
            let mut builder = tauri::webview::WebviewBuilder::new(label, tauri::WebviewUrl::External(blank))
                // The island's arguments exactly: WebView2 fixes them per
                // profile folder with the first webview, and a webview that
                // asks for others comes up blank, with no error anywhere.
                .additional_browser_args(crate::BROWSER_ARGS)
                .background_color(card_color())
                // Its own drops: a file dropped on ChatGPT is ChatGPT's.
                .disable_drag_drop_handler()
                .focused(false)
                .initialization_script(NO_CLOSE)
                .on_navigation(move |url| allows(&policy, label, url))
                .on_new_window(move |url, _| {
                    new_window(&opener, label, url);
                    NewWindowResponse::Deny
                })
                .on_download(|_, event| download(event))
                .on_permission_request(|_, kind| permission(kind));
            if label == CHAT_LABEL {
                builder = builder.user_agent(CHAT_USER_AGENT);
                if let Some(dir) = chat_data_dir(app) {
                    builder = builder.data_directory(dir);
                }
            }
            // Zero-sized until a page is shown: it cannot be seen before it is
            // hidden, a moment later.
            match island.add_child(
                builder,
                tauri::LogicalPosition::new(0.0, 0.0),
                tauri::LogicalSize::new(0.0, 0.0),
            ) {
                Ok(page) => {
                    let _ = page.hide();
                    prepare(app, label, &page);
                }
                Err(err) => log::line(format!("{label} page failed — {err}")),
            }
        }
        let handle = app.clone();
        island.on_window_event(move |event| match event {
            tauri::WindowEvent::Focused(true) => keyboard_follows(&handle),
            tauri::WindowEvent::Moved(_) => moved(&handle),
            tauri::WindowEvent::ScaleFactorChanged { scale_factor, .. } => {
                replace(&handle, Some(*scale_factor))
            }
            tauri::WindowEvent::ThemeChanged(_) => dark_again(&handle),
            _ => {}
        });
    }

    pub fn webview(app: &AppHandle, label: &str) -> Option<Webview> {
        app.get_webview(label)
    }

    /// Over the card, clipped to its rounded corners. Physical px, worked out
    /// here edge by edge, so the page and its clip agree on every pixel.
    pub fn place(app: &AppHandle, label: &str, card: Card, scale: Option<f64>) -> bool {
        let (Some(win), Some(page)) = (island::window(app), webview(app, label)) else {
            return false;
        };
        let scale = scale.unwrap_or_else(|| win.scale_factor().unwrap_or(1.0));
        let px = page_model::physical(card, scale);
        let bounds = tauri::Rect {
            position: tauri::PhysicalPosition::new(px.x, px.y).into(),
            size: tauri::PhysicalSize::new(px.w as u32, px.h as u32).into(),
        };
        if let Err(err) = page.set_bounds(bounds) {
            log::line(format!("{label} could not be placed — {err}"));
            return false;
        }
        platform::page_clip(&page, px.w, px.h, page_model::corner_ellipse(scale));
        true
    }

    pub fn set_visible(app: &AppHandle, label: &str, visible: bool) {
        let Some(page) = webview(app, label) else { return };
        if visible {
            let _ = page.show();
            // It was out of sight while the island moved.
            platform::notify_webview_moved(&page);
        } else {
            let _ = page.hide();
        }
    }

    pub fn island_has_keyboard(app: &AppHandle) -> bool {
        island::window(app).is_some_and(|win| platform::is_foreground(&win))
    }

    /// The page has something to show: the keyboard goes into it, if the
    /// island still has the keyboard to give.
    pub fn give_keyboard(app: &AppHandle, label: &str) {
        if island_has_keyboard(app) {
            if let Some(page) = webview(app, label) {
                let _ = page.set_focus();
            }
        }
    }

    /// A page went off screen while the island has the keyboard: it goes to the
    /// island's own page, never into one nobody can see.
    pub fn keyboard_home(app: &AppHandle) {
        if island_has_keyboard(app) {
            keyboard_follows(app);
        }
    }

    /// A page is arriving: the island may take focus while it is up — it is
    /// normally a window that never does — and comes forward, as the Mac's
    /// panel is made key, unless the page is only coming back after the island
    /// settled while the user was typing somewhere else.
    pub fn take_keyboard(app: &AppHandle, bring_forward: bool) {
        let Some(win) = island::window(app) else { return };
        platform::set_activating(&win, true);
        if bring_forward {
            let _ = win.set_focus();
        }
        if platform::is_foreground(&win) {
            keyboard_follows(app);
        }
    }

    /// No page is up any more: back to an island that never takes focus, with
    /// the keyboard on its own page while it still has it.
    pub fn release_keyboard(app: &AppHandle) {
        let Some(win) = island::window(app) else { return };
        if platform::is_foreground(&win) {
            keyboard_follows(app);
        }
        platform::set_activating(&win, false);
    }

    /// The island's window has the keyboard: it goes to the page on screen, or
    /// to the island's own page. What wry's hook on the window did for the one
    /// webview filling it, before the pages made it a window of several.
    pub fn keyboard_follows(app: &AppHandle) {
        let target = LABELS
            .iter()
            .find(|l| on_screen(l))
            .and_then(|l| app.get_webview(l))
            .or_else(|| island::webview(app));
        if let Some(target) = target {
            let _ = target.set_focus();
        }
    }

    /// Popups — a `<select>`'s list, the IME — open where the window is.
    fn moved(app: &AppHandle) {
        if let Some(view) = island::webview(app) {
            platform::notify_webview_moved(&view);
        }
        for label in LABELS {
            if on_screen(label) {
                if let Some(page) = webview(app, label) {
                    platform::notify_webview_moved(&page);
                }
            }
        }
    }

    /// Windows switched between light and dark: Tauri hands that to every
    /// webview of the window, ChatGPT included, right after this event. Dark
    /// again once it has.
    fn dark_again(app: &AppHandle) {
        let app = app.clone();
        let _ = std::thread::Builder::new().name("webchat-dark".into()).spawn(move || {
            let handle = app.clone();
            let _ = app.run_on_main_thread(move || {
                if let Some(page) = handle.get_webview(CHAT_LABEL) {
                    force_dark(&handle, &page);
                }
            });
        });
    }
}

/// A borderless window glued over the card (Linux).
#[cfg_attr(windows, allow(dead_code))]
mod glued {
    use super::*;
    use tauri::webview::PageLoadEvent;

    /// The navigation each page window is on, as WebKitGTK gives none: one per
    /// load it starts.
    static NAV: [AtomicU64; 2] = [AtomicU64::new(0), AtomicU64::new(0)];

    fn nav(label: &str) -> &'static AtomicU64 {
        &NAV[usize::from(label == SITE_LABEL)]
    }

    pub fn create(app: &AppHandle) {
        for label in LABELS {
            let Ok(blank) = Url::parse(BLANK) else { return };
            let policy = app.clone();
            let opener = app.clone();
            let loads = app.clone();
            let titles = app.clone();
            let mut builder = tauri::WebviewWindowBuilder::new(app, label, tauri::WebviewUrl::External(blank))
                .additional_browser_args(crate::BROWSER_ARGS)
                .title(if label == CHAT_LABEL { "ChatGPT" } else { "Site" })
                .inner_size(560.0, 546.0)
                // The card's size is the island's to decide (WC-24).
                .resizable(false)
                .decorations(false)
                .shadow(false)
                .background_color(card_color())
                .always_on_top(true)
                .visible_on_all_workspaces(true)
                .skip_taskbar(true)
                .visible(false)
                .focused(false)
                .disable_drag_drop_handler()
                .initialization_script(NO_CLOSE)
                .on_navigation(move |url| allows(&policy, label, url))
                .on_new_window(move |url, _| {
                    new_window(&opener, label, url);
                    NewWindowResponse::Deny
                })
                .on_download(|_, event| download(event))
                .on_permission_request(|_, kind| permission(kind))
                .on_page_load(move |_, payload| {
                    let url = payload.url().to_string();
                    let signal = match payload.event() {
                        PageLoadEvent::Started => Signal::Started {
                            id: nav(label).fetch_add(1, Ordering::Relaxed) + 1,
                            url,
                            by_user: false,
                            cancelled: false,
                        },
                        PageLoadEvent::Finished => {
                            on_signal(&loads, label, Signal::Source(url));
                            Signal::Finished {
                                id: nav(label).load(Ordering::Relaxed),
                                success: true,
                                status: 0,
                                error: 0,
                            }
                        }
                    };
                    on_signal(&loads, label, signal);
                })
                .on_document_title_changed(move |_, title| {
                    on_signal(&titles, label, Signal::Title(title));
                });
            if label == CHAT_LABEL {
                builder = builder.user_agent(CHAT_USER_AGENT);
                if let Some(dir) = chat_data_dir(app) {
                    builder = builder.data_directory(dir);
                }
            }
            match builder.build() {
                Ok(win) => {
                    let hider = app.clone();
                    win.on_window_event(move |event| {
                        if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                            // Never closed: it could not be built again.
                            api.prevent_close();
                            hide(&hider, label);
                        }
                    });
                    let escape = app.clone();
                    platform::page_watch_escape(&win, move || {
                        let _ = escape.emit_to(island::WINDOW_LABEL, "page-escape", PageEscape { label });
                    });
                    prepare(app, label, win.as_ref());
                }
                Err(err) => log::line(format!("{label} page failed — {err}")),
            }
        }
        // Where the island goes, the page goes.
        if let Some(island) = island::window(app) {
            let handle = app.clone();
            island.on_window_event(move |event| match event {
                tauri::WindowEvent::Moved(_) => replace(&handle, None),
                tauri::WindowEvent::ScaleFactorChanged { scale_factor, .. } => {
                    replace(&handle, Some(*scale_factor))
                }
                _ => {}
            });
        }
    }

    pub fn webview(app: &AppHandle, label: &str) -> Option<Webview> {
        app.get_webview(label)
    }

    /// Over the card: the island window's origin plus the card, in physical
    /// px. Where a compositor places windows itself (Wayland), it is wherever
    /// that puts it.
    pub fn place(app: &AppHandle, label: &str, card: Card, scale: Option<f64>) -> bool {
        let (Some(island), Some(win)) = (island::window(app), app.get_webview_window(label)) else {
            return false;
        };
        let Ok(origin) = island.outer_position() else { return false };
        let scale = scale.unwrap_or_else(|| island.scale_factor().unwrap_or(1.0));
        let px = page_model::glued((origin.x, origin.y), page_model::physical(card, scale));
        let size = tauri::PhysicalSize::new(px.w as u32, px.h as u32);
        let _ = win.set_size(size);
        let _ = win.set_position(tauri::PhysicalPosition::new(px.x, px.y));
        // Moving across displays can rescale the window: the size again.
        let _ = win.set_size(size);
        true
    }

    pub fn set_visible(app: &AppHandle, label: &str, visible: bool) {
        let Some(win) = app.get_webview_window(label) else { return };
        if visible {
            let _ = win.show();
            let _ = win.set_always_on_top(true);
        } else {
            let _ = win.hide();
        }
    }

    pub fn island_has_keyboard(app: &AppHandle) -> bool {
        LABELS
            .iter()
            .filter_map(|l| app.get_webview_window(l))
            .any(|win| win.is_focused().unwrap_or(false))
    }

    /// A window of its own: it takes the keyboard as it comes up.
    pub fn give_keyboard(app: &AppHandle, label: &str) {
        if let Some(win) = app.get_webview_window(label) {
            let _ = win.set_focus();
        }
    }

    /// The window manager hands the keyboard on when a window goes.
    pub fn keyboard_home(_app: &AppHandle) {}

    /// The island never takes the keyboard for a page here: the page's own
    /// window does.
    pub fn take_keyboard(_app: &AppHandle, _bring_forward: bool) {}

    pub fn release_keyboard(_app: &AppHandle) {}

    pub fn keyboard_follows(_app: &AppHandle) {}
}

#[cfg(test)]
mod tests {
    use super::*;

    fn allowed(url: &str, hosts: &[&str]) -> bool {
        keeps_in_window(&Url::parse(url).unwrap(), hosts)
    }

    fn url(s: &str) -> Url {
        Url::parse(s).unwrap()
    }

    #[test]
    fn the_family_stays_and_a_lookalike_does_not() {
        let hosts: Vec<&str> = CHAT_HOSTS.to_vec();
        assert!(allowed("https://chatgpt.com/", &hosts));
        assert!(allowed("https://api.chatgpt.com/x", &hosts));
        assert!(allowed("https://auth.openai.com/login", &hosts));
        assert!(!allowed("https://notchatgpt.com/", &hosts));
        assert!(!allowed("https://chatgpt.com.evil.net/", &hosts));
        assert!(!allowed("https://example.com/", &hosts));
    }

    #[test]
    fn a_non_web_scheme_is_never_ours_to_render() {
        let hosts: Vec<&str> = CHAT_HOSTS.to_vec();
        assert!(!allowed("file:///etc/passwd", &hosts));
        assert!(!allowed("mailto:someone@chatgpt.com", &hosts));
        assert!(!allowed("javascript:alert(1)", &hosts));
    }

    /// The Mac's list, host for host (WebChatPolicy.swift).
    #[test]
    fn the_hosts_are_the_macs() {
        let mut hosts = CHAT_HOSTS.to_vec();
        hosts.sort_unstable();
        assert_eq!(
            hosts,
            [
                "auth.openai.com",
                "auth0.openai.com",
                "chat.openai.com",
                "chatgpt.com",
                "oaistatic.com",
                "oaiusercontent.com",
                "openai.com",
                "sora.com",
            ]
        );
    }

    #[test]
    fn each_page_opens_its_own_address_or_none() {
        assert_eq!(page_url(CHAT_LABEL, "").unwrap().as_str(), CHAT_URL);
        assert_eq!(
            page_url(SITE_LABEL, " https://example.com/x ").unwrap().as_str(),
            "https://example.com/x"
        );
        assert!(page_url(SITE_LABEL, "").is_none());
        assert!(page_url(SITE_LABEL, "example.com").is_none());
        assert!(page_url(SITE_LABEL, "file:///etc/passwd").is_none());
        assert!(page_url(SITE_LABEL, "javascript:alert(1)").is_none());
    }

    #[test]
    fn only_a_web_address_goes_to_the_browser() {
        assert!(safe_web_url(&url("https://example.com/a")));
        assert!(safe_web_url(&url("http://example.com")));
        assert!(!safe_web_url(&url("file:///C:/Windows/notepad.exe")));
        assert!(!safe_web_url(&url("mailto:a@b.c")));
        assert!(!safe_web_url(&url("ms-settings:privacy")));
    }

    #[test]
    fn the_site_keeps_to_the_host_it_was_pointed_at() {
        let hosts = ["box.example.ts.net"];
        assert!(site_keeps(&url("https://box.example.ts.net/x"), &hosts));
        assert!(!site_keeps(&url("https://example.com/"), &hosts));
        // A blob the page made itself is its own host's; anyone else's is not.
        assert!(site_keeps(&url("blob:https://box.example.ts.net/1234"), &hosts));
        assert!(!site_keeps(&url("blob:https://example.com/1234"), &hosts));
        assert!(!site_keeps(&url("mailto:a@b.c"), &hosts));
        assert!(!site_keeps(&url("file:///etc/passwd"), &hosts));
        // Nothing is allowed by an empty host, however it is spelled.
        assert!(!host_allowed("", &hosts));
        assert!(!site_keeps(&url("https://box.example.ts.net/"), &[]));
    }

    #[test]
    fn a_clicked_link_to_an_app_opens_and_a_file_or_script_never_does() {
        assert!(opens_with_system("mailto:someone@example.com"));
        assert!(opens_with_system("tel:+33100000000"));
        assert!(opens_with_system("vscode://file/x"));
        assert!(!opens_with_system("https://example.com/"));
        assert!(!opens_with_system("file:///C:/Windows/system32/calc.exe"));
        assert!(!opens_with_system("javascript:alert(1)"));
        assert!(!opens_with_system("data:text/html,hi"));
        assert!(!opens_with_system("not a url"));
    }

    #[test]
    fn the_placeholder_is_recognised_however_it_is_spelled() {
        assert!(is_blank(&url("about:blank")));
        assert!(is_blank(&url("about:blank#x")));
        assert!(!is_blank(&url("about:srcdoc")));
        assert!(!is_blank(&url("https://blank.example/")));
    }

    #[test]
    fn the_island_hears_the_contracts_shape() {
        let state = PageState::of(
            CHAT_LABEL,
            Snapshot {
                state: "blocked",
                status: Some(403),
                error: None,
                url: Some("https://chatgpt.com/".into()),
                title: None,
                can_go_back: false,
            },
        );
        let json = serde_json::to_value(&state).unwrap();
        assert_eq!(
            json,
            serde_json::json!({
                "label": "webchat",
                "state": "blocked",
                "status": 403,
                "url": "https://chatgpt.com/",
                "canGoBack": false,
            })
        );
    }

    /// The pages are remote origins and must get no IPC: the capability names
    /// the webviews it covers, never a window — a window's capability covers
    /// every webview inside it, and the island's window holds the pages — and
    /// never theirs, and it opens nothing to a remote URL.
    #[test]
    fn no_capability_reaches_the_pages() {
        let capability: serde_json::Value =
            serde_json::from_str(include_str!("../capabilities/default.json")).unwrap();
        assert!(capability.get("windows").is_none(), "a window's capability reaches its child webviews");
        assert!(capability.get("remote").is_none(), "no remote URL may invoke anything");
        let webviews: Vec<&str> = capability["webviews"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_str().unwrap())
            .collect();
        assert!(webviews.contains(&island::WINDOW_LABEL));
        for label in webviews {
            assert!(!label.contains('*'), "a pattern could match a page: {label}");
            assert!(!LABELS.contains(&label), "{label} is a page");
            assert_ne!(label, "whatsapp");
        }
    }
}
