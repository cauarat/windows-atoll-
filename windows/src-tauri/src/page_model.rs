// The pages' pure half: what state a page is in, when it may be on screen,
// when it goes cold, which of its navigations count as a click, which pixels
// it lands on, and where the keyboard goes back to when the island lets go of
// it.
//
// `web.rs` hosts ChatGPT and the site inside the island and drives everything
// that touches a webview; every decision it makes is asked of this file. No
// Tauri and no Win32 in here, on purpose: the rules can be checked on any
// machine with `rustc --edition 2021 --test src/page_model.rs`, and CI runs
// them with the rest of `cargo test`.
//
// The Mac is the source of truth. ChatGPT follows WebChatController: hidden
// until the load it started has finished, refused when the main frame answers
// 403 or 503, released after 600 s out of sight. The site follows NotchSiteWeb:
// on screen while it loads, built fresh on every open, and blanked the moment
// it is left or closed.

use std::time::Duration;

/// How long ChatGPT stays loaded once it is out of sight — WebChatController's
/// `coldTTL`. Long enough that closing the island and reopening it is free;
/// short enough that a forgotten chat does not talk to OpenAI all day.
pub const CHAT_COLD_AFTER: Duration = Duration::from_secs(600);

/// The site's, while the island is only moving. NotchSiteView blanks its page
/// the moment it disappears (`NotchSiteWeb.stop()`), and the site here goes
/// cold at once when the user leaves it or closes it (`Leave`). This grace is
/// for the island, not the user: the island takes a page off screen while it
/// is still moving (island/pageHost.ts) and puts it back once it has settled,
/// and that must not cost the site its place. Well past any spring.
pub const SITE_COLD_AFTER: Duration = Duration::from_secs(5);

/// Why a page was put away: `page_hide`'s `away`, or `page_hide_all`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Leave {
    /// The island is moving or settling, and puts the page back once it is
    /// still: nothing about the page changes.
    Moving,
    /// The user went to another of the island's views. The island is still
    /// open and in use, so the keyboard stays with it.
    Away,
    /// The screen was closed: Escape, either X, the close shortcut, the island
    /// folding. The keyboard goes back to the window the user came from.
    Closed,
}

impl Leave {
    /// Whether a page shown again after this is the island settling — the
    /// same visit, for the keyboard, however long the move took — rather than
    /// the user asking again.
    pub fn is_settling(self) -> bool {
        self == Leave::Moving
    }

    /// Whether the page is out of sight for more than a moment: paused, as the
    /// Mac suspends a page's media when it goes (WebChatController.deactivate).
    pub fn pauses(self) -> bool {
        self != Leave::Moving
    }
}

/// How long a page stays loaded once it is out of sight; zero is at once.
///
/// ChatGPT keeps its ten minutes however it went. The site is blanked as soon
/// as the user leaves it or closes it — NotchSiteView builds a fresh page on
/// every open and blanks it on disappear — and keeps a few seconds only while
/// the island is moving.
pub fn cold_after(is_chat: bool, leave: Leave) -> Duration {
    match (is_chat, leave) {
        (true, _) => CHAT_COLD_AFTER,
        (false, Leave::Moving) => SITE_COLD_AFTER,
        (false, Leave::Away | Leave::Closed) => Duration::ZERO,
    }
}

/// Corner radius of the card a page sits in, logical px — the
/// `RoundedRectangle(cornerRadius: 16)` of WebChatHostView and NotchSiteView.
pub const CARD_RADIUS: f64 = 16.0;

/// The card's fill, #141518: what shows where a page has not painted yet.
pub const CARD_RGB: (u8, u8, u8) = (0x14, 0x15, 0x18);

/// The placeholder a page holds while it is cold.
pub const BLANK: &str = "about:blank";

/// Where a page is in its life. The names are the contract's `state` values.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Phase {
    /// On the placeholder: nothing of the page is running.
    Cold,
    /// A main-frame navigation is under way.
    Loading,
    /// The page has finished loading.
    Ready,
    /// The main frame answered 403 or 503: the site turned the embedded view
    /// away. ChatGPT only, as WebChatController.
    Blocked(u16),
    /// The navigation failed; the WebView2 error name.
    Failed(String),
}

impl Phase {
    pub fn name(&self) -> &'static str {
        match self {
            Phase::Cold => "cold",
            Phase::Loading => "loading",
            Phase::Ready => "ready",
            Phase::Blocked(_) => "blocked",
            Phase::Failed(_) => "failed",
        }
    }
}

/// How one main-frame navigation ended.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Outcome {
    Ready,
    Blocked(u16),
    Failed(String),
    /// Stopped before it finished: cancelled by the navigation policy, taken
    /// over by a newer navigation, or turned into a download.
    Canceled,
}

// COREWEBVIEW2_WEB_ERROR_STATUS, by value.
const ERROR_UNKNOWN: i32 = 0;
const ERROR_CANCELED: i32 = 14;
const ERROR_AUTH_REQUIRED: i32 = 17;
const ERROR_PROXY_AUTH_REQUIRED: i32 = 18;

/// The name of a WebView2 web error status, as the WebView2 documentation
/// spells it (CoreWebView2WebErrorStatus). What the `failed` state carries; the
/// island turns it into words.
pub fn web_error_name(code: i32) -> &'static str {
    web_error_name_of(code)
}

/// The WebView2 web error status called `name`: `web_error_name` backwards,
/// for a webview that reports its failures some other way (WebKitGTK, on
/// Linux), so they reach the island under the names it has words for.
/// Unknown for a name WebView2 does not have.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub fn web_error_code(name: &str) -> i32 {
    (ERROR_UNKNOWN..=ERROR_PROXY_AUTH_REQUIRED)
        .find(|&code| web_error_name_of(code) == name)
        .unwrap_or(ERROR_UNKNOWN)
}

fn web_error_name_of(code: i32) -> &'static str {
    match code {
        1 => "CertificateCommonNameIsIncorrect",
        2 => "CertificateExpired",
        3 => "ClientCertificateContainsErrors",
        4 => "CertificateRevoked",
        5 => "CertificateIsInvalid",
        6 => "ServerUnreachable",
        7 => "Timeout",
        8 => "ErrorHttpInvalidServerResponse",
        9 => "ConnectionAborted",
        10 => "ConnectionReset",
        11 => "Disconnected",
        12 => "CannotConnect",
        13 => "HostNameNotResolved",
        14 => "OperationCanceled",
        15 => "RedirectFailed",
        16 => "UnexpectedError",
        17 => "ValidAuthenticationCredentialsRequired",
        18 => "ValidProxyAuthenticationRequired",
        _ => "Unknown",
    }
}

/// How a finished main-frame navigation counts, from what WebView2 reports
/// about it: `success` (IsSuccess), `status` (HttpStatusCode, 0 when no
/// response came back) and `error` (WebErrorStatus).
///
/// `watch_refusal` is ChatGPT's: a 403 or 503 on the main frame is Cloudflare
/// or OpenAI turning the embedded view away, and reads as a message instead of
/// a blank island (WebChatController.decidePolicyFor navigationResponse). The
/// site has no such state; its 403 is its own page.
///
/// Any other answer from the server is a page on screen, as WebKit shows it:
/// WebView2 reports a 404 as unsuccessful, the Mac's didFinish does not.
pub fn outcome(watch_refusal: bool, success: bool, status: u16, error: i32) -> Outcome {
    if watch_refusal && (status == 403 || status == 503) {
        return Outcome::Blocked(status);
    }
    if success {
        return Outcome::Ready;
    }
    if error == ERROR_CANCELED {
        return Outcome::Canceled;
    }
    let answered = status >= 100
        && matches!(error, ERROR_UNKNOWN | ERROR_AUTH_REQUIRED | ERROR_PROXY_AUTH_REQUIRED);
    if answered {
        return Outcome::Ready;
    }
    Outcome::Failed(web_error_name(error).to_string())
}

/// What a page's webview reports, as the host hears it: WebView2's events on
/// Windows (platform/windows.rs), the builder's page-load and title callbacks
/// on Linux.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Signal {
    /// A main-frame navigation began, or one of its redirects did
    /// (`redirected`, under the same id). `cancelled` when the navigation
    /// policy has already refused it; `by_user` when a click or a key started
    /// it, as the webview says — never for a redirect. Whose it really is,
    /// the host decides (`Initiator`).
    Started { id: u64, url: String, by_user: bool, redirected: bool, cancelled: bool },
    /// A main-frame navigation ended. `status` is the HTTP status, 0 without a
    /// response; `error` the WebView2 web error status.
    Finished { id: u64, success: bool, status: u16, error: i32 },
    /// The document a main-frame navigation brought has started to arrive
    /// (ContentLoading; WebKit's COMMITTED). `error_page` when it is the
    /// webview's own page for a failure.
    Content { id: u64, error_page: bool },
    /// The address changed, a same-document navigation included.
    Source(String),
    Title(String),
    History { can_go_back: bool },
    /// Escape, pressed while the page has the keyboard.
    Escape,
    /// The page put an element in fullscreen. Never the island's window.
    Fullscreen,
}

/// Whether what the webview says about going back can be believed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum History {
    /// It can: it is about this visit.
    Heard,
    /// A fresh load is under way, with the last visit still behind it in the
    /// webview — the placeholder, and whatever came before it went cold — so
    /// what it says is about that, and is not heard.
    Stale,
    /// The site's history is being started over, as NotchSiteWeb is a new
    /// WKWebView with none on every open: the answer to that is what counts.
    Resetting,
}

/// What the island is told about a page — the `page-state` event less its
/// label.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Snapshot {
    pub state: &'static str,
    pub status: Option<u16>,
    pub error: Option<String>,
    pub url: Option<String>,
    pub title: Option<String>,
    pub can_go_back: bool,
}

/// One page: the island's ChatGPT, or the site.
#[derive(Clone, Debug)]
pub struct Page {
    pub phase: Phase,
    /// Real content has been on screen since the last load the host started.
    /// A navigation the page then makes on its own loads in plain sight, as a
    /// tab would: WebChatController only hides the page for loads it starts
    /// itself (first open, coming back from cold, Try again). The site's is set
    /// as soon as its document starts to arrive (`content`).
    pub painted: bool,
    /// Asked for by `page_show` and not put away since.
    pub wanted: bool,
    pub url: Option<String>,
    pub title: Option<String>,
    pub can_go_back: bool,
    /// Whether the webview's word on going back is heard.
    pub history: History,
    /// The main-frame navigation whose end decides the state, while one is in
    /// flight. An end that is not this one's has been overtaken.
    nav: Option<u64>,
    /// Bumped by every show and hide, so a cold timer started by a hide finds
    /// out whether anything happened since.
    epoch: u64,
}

impl Default for Page {
    fn default() -> Self {
        Self::new()
    }
}

impl Page {
    pub fn new() -> Self {
        Self {
            phase: Phase::Cold,
            painted: false,
            wanted: false,
            url: None,
            title: None,
            can_go_back: false,
            history: History::Heard,
            nav: None,
            epoch: 0,
        }
    }

    /// Whether the host should have it on screen: asked for, and with
    /// something worth showing — WebChatHostView's `opacity(loadState ==
    /// .ready ? 1 : 0)`, plus a page that is already up and loading its next
    /// document on its own, and the site from its first content on.
    pub fn visible(&self) -> bool {
        self.wanted
            && match self.phase {
                Phase::Ready => true,
                Phase::Loading => self.painted,
                _ => false,
            }
    }

    /// `page_show`.
    pub fn show(&mut self) {
        self.wanted = true;
        self.epoch += 1;
    }

    /// `page_hide`. Returns the epoch a cold timer has to find unchanged, or
    /// None when the page was not up — hiding it again must not cancel the
    /// timer the first hide started.
    pub fn hide(&mut self) -> Option<u64> {
        if !self.wanted {
            return None;
        }
        self.wanted = false;
        self.epoch += 1;
        Some(self.epoch)
    }

    /// Whether a cold timer started at `epoch` should release the page now:
    /// still out of sight, not shown or hidden again since, and not cold
    /// already.
    pub fn cold_due(&self, epoch: u64) -> bool {
        !self.wanted && self.epoch == epoch && self.phase != Phase::Cold
    }

    /// Whether the page should go cold right now, whatever timer is running:
    /// out of sight, and not cold already.
    pub fn cold_now(&self) -> bool {
        !self.wanted && self.phase != Phase::Cold
    }

    /// The host starts a load: the first open, coming back from cold, or Try
    /// again. `hide_until_ready` is the Mac's `loadState = .loading`, which
    /// takes the page off screen until it has finished.
    pub fn begin_load(&mut self, hide_until_ready: bool) {
        self.phase = Phase::Loading;
        if hide_until_ready {
            self.painted = false;
        }
        // Whatever was in flight is overtaken by the load just started.
        self.nav = None;
    }

    /// The host loads the page anew — the first open, or back from cold — with
    /// nothing of the visit before it to go back to: the back button is gone
    /// until this load says otherwise, and the webview, which still has the
    /// placeholder behind it, is not heard on it until then.
    pub fn begin_fresh_load(&mut self, hide_until_ready: bool) {
        self.begin_load(hide_until_ready);
        self.can_go_back = false;
        self.history = History::Stale;
    }

    /// A fresh load is in: whether its history is to be started over now,
    /// once. The site's is (`resets_history`), and the webview is heard again
    /// only once that answers (`history_reset`); ChatGPT's is heard from here.
    pub fn fresh_load_done(&mut self, resets_history: bool) -> bool {
        if self.history != History::Stale || self.phase != Phase::Ready {
            return false;
        }
        if resets_history {
            self.history = History::Resetting;
            true
        } else {
            self.history = History::Heard;
            false
        }
    }

    /// What the webview says about going back (HistoryChanged, a navigation's
    /// end). Not heard while the page is cold, nor while its history is the
    /// last visit's.
    pub fn history_changed(&mut self, can_go_back: bool) {
        if self.phase != Phase::Cold && self.history == History::Heard {
            self.can_go_back = can_go_back;
        }
    }

    /// The answer to starting the history over: the real value, unless the
    /// page has gone cold since.
    pub fn history_reset(&mut self, can_go_back: bool) {
        if self.phase != Phase::Cold && self.history == History::Resetting {
            self.history = History::Heard;
            self.can_go_back = can_go_back;
        }
    }

    /// The document of the navigation under way has started to arrive.
    ///
    /// `shows_early` is the site's: NotchSiteView has its page in the card at
    /// full opacity for the whole load, so it renders as it arrives rather than
    /// once every image has. ChatGPT stays off until its load is in
    /// (WebChatHostView's opacity follows `.ready`). The webview's own page for
    /// a failure is never shown, on either: the island has its own words for
    /// that, so it takes the page off screen at once. That includes ChatGPT
    /// up and `ready`, failing a navigation it started itself (`started`
    /// leaves it ready): it goes off screen and back to loading, so that the
    /// navigation's end is heard as the failure it is.
    pub fn content(&mut self, id: u64, error_page: bool, shows_early: bool) {
        if self.nav != Some(id) {
            return;
        }
        match self.phase {
            Phase::Loading if error_page => self.painted = false,
            Phase::Loading if shows_early => self.painted = true,
            Phase::Ready if error_page => {
                self.phase = Phase::Loading;
                self.painted = false;
            }
            _ => {}
        }
    }

    /// A main-frame navigation started (NavigationStarting, not cancelled).
    ///
    /// `shows_loading` is the site's: NotchSiteWeb turns its header's spinner
    /// on for every navigation (didStartProvisionalNavigation). ChatGPT's
    /// controller has no such handler — its state moves only for the loads it
    /// starts and for how a navigation ends — so a link followed inside
    /// ChatGPT leaves it `ready`, and only the end of it counts.
    pub fn started(&mut self, id: u64, shows_loading: bool) {
        if self.phase == Phase::Cold {
            // Nothing of ours is loading: the placeholder itself.
            return;
        }
        self.nav = Some(id);
        if !shows_loading {
            return;
        }
        match self.phase {
            // Refused stays refused until the host loads again — the Mac
            // ignores every navigation the page makes after a 403.
            Phase::Blocked(_) => {}
            // A failed page is off screen, and stays off until something
            // loads: the Mac's opacity follows `.ready` only.
            Phase::Failed(_) => {
                self.painted = false;
                self.phase = Phase::Loading;
            }
            _ => self.phase = Phase::Loading,
        }
    }

    /// A main-frame navigation ended (NavigationCompleted).
    pub fn finished(&mut self, id: u64, outcome: Outcome) {
        if self.nav != Some(id) {
            // Overtaken by a newer navigation, or one this never followed.
            return;
        }
        self.nav = None;
        match outcome {
            Outcome::Canceled => {
                if self.phase == Phase::Loading {
                    // A page already up keeps what it shows; a load of ours
                    // that never got anywhere is a failure, as the Mac's
                    // didFailProvisionalNavigation makes it.
                    self.phase = if self.painted {
                        Phase::Ready
                    } else {
                        Phase::Failed(web_error_name(ERROR_CANCELED).to_string())
                    };
                }
            }
            // WebChatController.didFinish: `if case .blocked = loadState { return }`.
            Outcome::Ready if matches!(self.phase, Phase::Blocked(_)) => {}
            Outcome::Ready => {
                self.phase = Phase::Ready;
                self.painted = true;
            }
            Outcome::Blocked(status) => self.phase = Phase::Blocked(status),
            Outcome::Failed(error) => self.phase = Phase::Failed(error),
        }
    }

    /// Back on the placeholder: nothing of the page is left running.
    pub fn go_cold(&mut self) {
        self.phase = Phase::Cold;
        self.painted = false;
        self.nav = None;
        self.url = None;
        self.title = None;
        self.can_go_back = false;
        // A reset still in flight answers for a visit that is over.
        self.history = History::Heard;
    }

    /// The address the page is on, as the island may see it: never the
    /// placeholder.
    pub fn set_url(&mut self, url: Option<String>) {
        self.url = url.filter(|u| !u.is_empty() && u != BLANK);
    }

    /// The page's title, as the island may see it: never empty, never the
    /// placeholder's.
    pub fn set_title(&mut self, title: Option<String>) {
        self.title = title.filter(|t| !t.trim().is_empty() && t != BLANK);
    }

    pub fn snapshot(&self) -> Snapshot {
        let (status, error) = match &self.phase {
            Phase::Blocked(status) => (Some(*status), None),
            Phase::Failed(error) => (None, Some(error.clone())),
            _ => (None, None),
        };
        let cold = self.phase == Phase::Cold;
        Snapshot {
            state: self.phase.name(),
            status,
            error,
            url: if cold { None } else { self.url.clone() },
            title: if cold { None } else { self.title.clone() },
            can_go_back: !cold && self.can_go_back,
        }
    }
}

// ── Whose navigation it is ─────────────────────────────────────────────────

/// Who started a page's main-frame navigations, for the one thing that asks:
/// only a click or a key hands a mail address or a phone number to the system
/// (web.rs `system_link`), as NotchSiteWeb does only for `.linkActivated`.
///
/// The webview's word comes first, and a redirect is never a click
/// (platform/windows.rs). What the host starts itself is never the user's
/// either, though WebView2 counts every navigation its API starts as theirs: a
/// page's `window.open` loaded in place (web.rs `new_window`) is the host
/// navigating, as the Mac's `webView.load` is `.other`. The host says so just
/// before it navigates. The next navigation to start is that one, and every
/// redirect of it after.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Initiator {
    /// The host is about to navigate: the next navigation to start is its.
    pending: bool,
    /// The host's navigation, by id.
    host: Option<u64>,
}

impl Initiator {
    /// The host is about to start a navigation in the page.
    pub fn host_navigates(&mut self) {
        self.pending = true;
    }

    /// It could not: nothing is coming.
    pub fn host_gave_up(&mut self) {
        self.pending = false;
    }

    /// A main-frame navigation started, or a redirect of one (`redirected`,
    /// same id): whether it counts as the user's. `by_user` is the webview's
    /// word on it.
    pub fn started(&mut self, id: u64, by_user: bool, redirected: bool) -> bool {
        if self.pending && !redirected {
            self.pending = false;
            self.host = Some(id);
        }
        by_user && !redirected && self.host != Some(id)
    }

    /// The page's address changed. A navigation the host was about to start
    /// and that has not started by now was a same-document one, which WebView2
    /// makes without starting a navigation: it is over, and the next one to
    /// start is somebody else's.
    pub fn address_changed(&mut self) {
        self.pending = false;
    }
}

// ── Where a page lands ─────────────────────────────────────────────────────

/// The card a page fills, in the island page's CSS px — logical px of the
/// island window's client area, as `getBoundingClientRect()` gives them.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Card {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

impl Card {
    /// Whether it is a rectangle a page can be put in: finite, and at least a
    /// pixel each way.
    pub fn usable(&self) -> bool {
        [self.x, self.y, self.w, self.h].iter().all(|v| v.is_finite()) && self.w >= 1.0 && self.h >= 1.0
    }
}

/// A rectangle in physical px.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Px {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

/// The card in physical px at `scale`.
///
/// Each edge is rounded on its own rather than the origin and the size, so the
/// page covers exactly the pixel rows and columns the island's own card does:
/// at 125 % a card at x 20.4 wide 559.2 ends at 724.5 → 725 either way, but
/// rounding the width alone would end it at 724.
pub fn physical(card: Card, scale: f64) -> Px {
    let x0 = (card.x * scale).round();
    let y0 = (card.y * scale).round();
    let x1 = ((card.x + card.w) * scale).round();
    let y1 = ((card.y + card.h) * scale).round();
    Px {
        x: x0 as i32,
        y: y0 as i32,
        w: (x1 - x0).max(1.0) as i32,
        h: (y1 - y0).max(1.0) as i32,
    }
}

/// The corner ellipse of the page's clip, physical px: `CreateRoundRectRgn`
/// takes the ellipse's width and height, which is twice the radius.
pub fn corner_ellipse(scale: f64) -> i32 {
    (2.0 * CARD_RADIUS * scale).round().max(0.0) as i32
}

/// The rectangle handed to `CreateRoundRectRgn` for a page `w`×`h` physical px:
/// its right and bottom edges are exclusive, so one past the page.
pub fn region_extent(w: i32, h: i32) -> (i32, i32) {
    (w + 1, h + 1)
}

/// Where a page that is a window of its own goes (Linux, where a child webview
/// cannot be placed): over the card, from the island window's origin in
/// physical px.
pub fn glued(origin: (i32, i32), card: Px) -> Px {
    Px { x: origin.0 + card.x, y: origin.1 + card.y, w: card.w, h: card.h }
}

// ── Where the keyboard goes back to ────────────────────────────────────────

/// The windows the user was in while the island had the keyboard or could
/// take it (a page up, one of its own fields holding it), newest last, each
/// once. When the island lets go, the keyboard goes back to the newest one
/// still worth having it. On the Mac, the panel resigning key leaves the
/// keyboard with whichever app is active then, not the one the visit began in.
/// Bare window handles; 0 is none and is never kept.
///
/// More than one, because the newest may be gone by then: closed, minimised,
/// on another virtual desktop, or a Start menu that has folded away. The one
/// before it is then the window the user expects.
#[derive(Debug, Default)]
pub struct Recent(Vec<isize>);

impl Recent {
    /// How many are kept. Past a few, none is still where the user was.
    pub const KEPT: usize = 4;

    pub const fn new() -> Self {
        Recent(Vec::new())
    }

    /// The user is in `window` now.
    pub fn note(&mut self, window: isize) {
        if window == 0 {
            return;
        }
        self.0.retain(|w| *w != window);
        self.0.push(window);
        let over = self.0.len().saturating_sub(Self::KEPT);
        self.0.drain(..over);
    }

    /// The window the keyboard goes back to: the newest one `fit` accepts
    /// (still there, and worth having it). Every one is forgotten either way,
    /// because the visit is over.
    pub fn take_newest(&mut self, fit: impl Fn(isize) -> bool) -> Option<isize> {
        std::mem::take(&mut self.0).into_iter().rev().find(|w| fit(*w))
    }

    /// `take_newest`, with somewhere to go when the visit has nowhere: `last`,
    /// the last window the user was in at all, which the watchdog keeps
    /// whatever the island is doing — the visit may have begun from the
    /// taskbar or the tray, which are never kept — if `fit` still accepts it.
    /// On the Mac the panel resigning key always leaves the keyboard with an
    /// app; it never stays with a folded island.
    pub fn take_back(&mut self, last: isize, fit: impl Fn(isize) -> bool) -> Option<isize> {
        self.take_newest(&fit).or_else(|| (last != 0 && fit(last)).then_some(last))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn loaded() -> Page {
        let mut page = Page::new();
        page.show();
        page.begin_load(true);
        page.started(1, true);
        page.finished(1, Outcome::Ready);
        page
    }

    // ── The cold rule ──────────────────────────────────────────────────────

    #[test]
    fn chatgpt_goes_cold_after_the_macs_ten_minutes_however_it_went() {
        for leave in [Leave::Moving, Leave::Away, Leave::Closed] {
            assert_eq!(cold_after(true, leave), Duration::from_secs(600), "{leave:?}");
        }
    }

    #[test]
    fn the_site_is_blanked_the_moment_it_is_left_or_closed() {
        // NotchSiteView blanks its page on disappear.
        assert_eq!(cold_after(false, Leave::Away), Duration::ZERO);
        assert_eq!(cold_after(false, Leave::Closed), Duration::ZERO);
        // Only the island moving keeps it: longer than the island takes to
        // settle, so a page it puts back is the page it took away.
        let moving = cold_after(false, Leave::Moving);
        assert!(moving >= Duration::from_secs(2));
        assert!(moving <= Duration::from_secs(10));
    }

    #[test]
    fn only_the_island_moving_is_the_same_visit() {
        assert!(Leave::Moving.is_settling());
        assert!(!Leave::Away.is_settling());
        assert!(!Leave::Closed.is_settling());
        // And only a page that is really away is paused.
        assert!(!Leave::Moving.pauses());
        assert!(Leave::Away.pauses());
        assert!(Leave::Closed.pauses());
    }

    #[test]
    fn a_page_goes_cold_now_only_out_of_sight_and_not_cold_already() {
        let mut page = loaded();
        assert!(!page.cold_now(), "on screen");
        page.hide();
        assert!(page.cold_now());
        page.go_cold();
        assert!(!page.cold_now(), "already cold");
        assert!(!Page::new().cold_now(), "never loaded");
    }

    #[test]
    fn a_hidden_page_goes_cold_only_if_nothing_happened_since() {
        let mut page = loaded();
        let epoch = page.hide().unwrap();
        assert!(page.cold_due(epoch));

        // Shown again before the timer ran: it stays.
        page.show();
        assert!(!page.cold_due(epoch));

        // Hidden again: the older timer is stale, the newer one counts.
        let later = page.hide().unwrap();
        assert!(!page.cold_due(epoch));
        assert!(page.cold_due(later));

        // Already cold: nothing to release.
        page.go_cold();
        assert!(!page.cold_due(later));
    }

    #[test]
    fn hiding_a_page_that_is_not_up_keeps_its_timer() {
        let mut page = loaded();
        let epoch = page.hide().unwrap();
        // Every page away at once — the island folding after ChatGPT closed.
        assert_eq!(page.hide(), None);
        assert!(page.cold_due(epoch), "the first hide's timer still releases it");
    }

    #[test]
    fn going_cold_forgets_where_the_page_was() {
        let mut page = loaded();
        page.set_url(Some("https://chatgpt.com/c/1".into()));
        page.set_title(Some("A chat".into()));
        page.can_go_back = true;
        page.hide();
        page.go_cold();
        let s = page.snapshot();
        assert_eq!(s.state, "cold");
        assert_eq!((s.url, s.title, s.can_go_back), (None, None, false));
        assert!(!page.visible());
    }

    // ── States ─────────────────────────────────────────────────────────────

    #[test]
    fn a_page_is_hidden_until_the_load_it_was_given_has_finished() {
        let mut page = Page::new();
        page.show();
        assert!(!page.visible(), "cold");
        page.begin_load(true);
        page.started(7, true);
        assert_eq!(page.phase, Phase::Loading);
        assert!(!page.visible(), "loading");
        page.finished(7, Outcome::Ready);
        assert!(page.visible(), "ready");
    }

    #[test]
    fn a_page_the_island_does_not_want_is_never_on_screen() {
        let mut page = loaded();
        page.hide();
        assert_eq!(page.phase, Phase::Ready);
        assert!(!page.visible());
    }

    #[test]
    fn a_page_that_is_up_loads_its_own_next_document_in_sight() {
        // The site: its spinner turns, and the page stays up.
        let mut page = loaded();
        page.started(2, true);
        assert_eq!(page.snapshot().state, "loading");
        assert!(page.visible(), "a link followed inside the page keeps the page up");
        page.finished(2, Outcome::Ready);
        assert!(page.visible());
    }

    #[test]
    fn chatgpt_stays_ready_through_its_own_navigations_and_their_end_still_counts() {
        let mut page = loaded();
        page.started(2, false);
        assert_eq!(page.snapshot().state, "ready");
        assert!(page.visible());
        // The sign-in round trip comes back refused: that is what counts.
        page.finished(2, Outcome::Blocked(403));
        assert_eq!(page.snapshot().state, "blocked");
        assert!(!page.visible());

        // A failure, then a navigation from the error page: hidden, and still
        // `failed`, until it has loaded.
        let mut page = loaded();
        page.started(3, false);
        page.finished(3, Outcome::Failed("Timeout".into()));
        page.started(4, false);
        assert_eq!(page.snapshot().state, "failed");
        assert!(!page.visible());
        page.finished(4, Outcome::Ready);
        assert!(page.visible());
    }

    #[test]
    fn try_again_takes_chatgpt_off_screen_and_keeps_the_site_up() {
        // ChatGPT: reload() sets `.loading`, opacity 0.
        let mut chat = loaded();
        chat.begin_load(true);
        assert!(!chat.visible());
        // The site: reload() only spins the header's spinner.
        let mut site = loaded();
        site.begin_load(false);
        assert!(site.visible());
    }

    #[test]
    fn refused_stays_refused_until_the_host_loads_again() {
        let mut page = Page::new();
        page.show();
        page.begin_load(true);
        page.started(1, true);
        page.finished(1, Outcome::Blocked(403));
        assert_eq!(page.snapshot().status, Some(403));
        assert!(!page.visible());

        // The challenge page navigates itself and comes back 200: the Mac's
        // didFinish returns early on `.blocked`.
        page.started(2, true);
        assert_eq!(page.phase, Phase::Blocked(403));
        page.finished(2, Outcome::Ready);
        assert_eq!(page.phase, Phase::Blocked(403));
        assert!(!page.visible());

        // Try again.
        page.begin_load(true);
        page.started(3, true);
        page.finished(3, Outcome::Ready);
        assert!(page.visible());
    }

    #[test]
    fn a_failure_hides_the_page_until_something_loads() {
        let mut page = loaded();
        page.started(2, true);
        page.finished(2, Outcome::Failed("HostNameNotResolved".into()));
        let s = page.snapshot();
        assert_eq!((s.state, s.error.as_deref()), ("failed", Some("HostNameNotResolved")));
        assert!(!page.visible());

        // Something navigates from the error page: still off screen until it
        // has finished.
        page.started(3, true);
        assert!(!page.visible());
        page.finished(3, Outcome::Ready);
        assert!(page.visible());
    }

    #[test]
    fn an_overtaken_navigation_decides_nothing() {
        let mut page = loaded();
        page.started(2, true);
        page.started(3, true);
        page.finished(2, Outcome::Canceled);
        assert_eq!(page.phase, Phase::Loading);
        page.finished(3, Outcome::Ready);
        assert_eq!(page.phase, Phase::Ready);
    }

    #[test]
    fn a_load_of_ours_overtakes_whatever_was_in_flight() {
        let mut page = loaded();
        page.started(2, true);
        page.begin_load(true);
        page.finished(2, Outcome::Failed("ConnectionReset".into()));
        assert_eq!(page.phase, Phase::Loading, "the old navigation's end is not ours");
    }

    #[test]
    fn a_cancelled_navigation_leaves_a_page_that_is_up_as_it_was() {
        let mut page = loaded();
        page.started(2, true);
        page.finished(2, Outcome::Canceled);
        assert_eq!(page.phase, Phase::Ready);
        assert!(page.visible());
    }

    #[test]
    fn a_first_load_that_is_cancelled_is_a_failure() {
        let mut page = Page::new();
        page.show();
        page.begin_load(true);
        page.started(1, true);
        page.finished(1, Outcome::Canceled);
        assert_eq!(page.phase, Phase::Failed("OperationCanceled".into()));
    }

    // ── The site on screen while it loads ──────────────────────────────────

    #[test]
    fn the_site_is_on_screen_from_its_first_content() {
        let mut page = Page::new();
        page.show();
        page.begin_fresh_load(false);
        page.started(1, true);
        assert!(!page.visible(), "nothing has arrived yet: the card shows");
        page.content(1, false, true);
        assert!(page.visible(), "it renders as it loads, as NotchSiteView's page");
        assert_eq!(page.snapshot().state, "loading", "the spinner still turns");
        page.finished(1, Outcome::Ready);
        assert!(page.visible());
    }

    #[test]
    fn chatgpt_waits_for_its_load_whatever_arrives_first() {
        let mut page = Page::new();
        page.show();
        page.begin_fresh_load(true);
        page.started(1, false);
        page.content(1, false, false);
        assert!(!page.visible());
        page.finished(1, Outcome::Ready);
        assert!(page.visible());
    }

    #[test]
    fn the_webviews_own_error_page_is_never_on_screen() {
        // A first load that fails.
        let mut page = Page::new();
        page.show();
        page.begin_fresh_load(false);
        page.started(1, true);
        page.content(1, true, true);
        assert!(!page.visible());

        // A page already up whose next load fails: off at once, not at its end.
        let mut page = loaded();
        page.started(2, true);
        assert!(page.visible());
        page.content(2, true, true);
        assert!(!page.visible());
        page.finished(2, Outcome::Failed("Timeout".into()));
        assert!(!page.visible());

        // ChatGPT up, failing a navigation it started itself: it stays
        // `ready` through it, and still goes off at once, not at its end.
        let mut chat = loaded();
        chat.started(2, false);
        assert!(chat.visible());
        chat.content(2, true, false);
        assert!(!chat.visible());
        assert_eq!(chat.phase, Phase::Loading);
        chat.finished(2, outcome(true, false, 0, 13));
        assert_eq!(chat.snapshot().state, "failed", "its end is heard as the failure");
        assert!(!chat.visible());

        // Its own next document arriving is no failure: it stays up.
        let mut chat = loaded();
        chat.started(3, false);
        chat.content(3, false, false);
        assert!(chat.visible());
        assert_eq!(chat.phase, Phase::Ready);
    }

    #[test]
    fn content_from_a_navigation_this_is_not_following_changes_nothing() {
        let mut page = Page::new();
        page.show();
        page.begin_fresh_load(false);
        page.started(2, true);
        page.content(1, false, true);
        assert!(!page.painted);
        assert!(!page.visible());

        // ChatGPT up: an error page for a navigation it is not following
        // takes nothing off screen.
        let mut chat = loaded();
        chat.started(3, false);
        chat.content(2, true, false);
        assert_eq!(chat.phase, Phase::Ready);
        assert!(chat.visible());

        // The placeholder's own content, while cold: nothing painted, so a
        // fresh load after it does not come up before its own content.
        let mut cold = Page::new();
        cold.show();
        cold.started(1, true);
        cold.content(1, false, true);
        assert!(!cold.painted);
        assert_eq!(cold.phase, Phase::Cold);
        cold.begin_fresh_load(false);
        cold.started(5, true);
        assert!(!cold.visible());
    }

    #[test]
    fn try_again_shows_the_site_once_real_content_arrives() {
        let mut page = loaded();
        page.started(2, true);
        page.finished(2, Outcome::Failed("Disconnected".into()));
        // web.rs::reload after a failure: off screen until something loads.
        page.begin_load(true);
        page.started(3, true);
        assert!(!page.visible());
        // Still offline: WebView2's error page arrives, and is not shown.
        page.content(3, true, true);
        assert!(!page.visible());
        page.finished(3, Outcome::Failed("Disconnected".into()));
        // Back online.
        page.begin_load(true);
        page.started(4, true);
        page.content(4, false, true);
        assert!(page.visible());
    }

    // ── Going back ─────────────────────────────────────────────────────────

    #[test]
    fn a_fresh_load_has_no_back_button_until_it_is_in_and_started_over() {
        // The site, reopened after going cold: WebView2 has the placeholder
        // and the last visit behind it.
        let mut page = loaded();
        page.can_go_back = true;
        page.hide();
        page.go_cold();
        page.history_changed(true); // the placeholder's own load ending
        assert!(!page.can_go_back, "not heard while cold");
        assert!(!page.snapshot().can_go_back, "cold");

        page.show();
        page.begin_fresh_load(false);
        assert!(!page.can_go_back);
        page.started(5, true);
        page.history_changed(true);
        assert!(!page.snapshot().can_go_back, "still the last visit's history");
        page.finished(5, Outcome::Ready);
        assert!(page.fresh_load_done(true), "the site's history starts over");
        page.history_changed(true); // the load's own HistoryChanged, before the reset answers
        assert!(!page.can_go_back);
        page.history_reset(false);
        assert!(!page.can_go_back);
        assert!(!page.fresh_load_done(true), "once");

        // From here the page's own navigations count.
        page.history_changed(true);
        assert!(page.snapshot().can_go_back);
    }

    #[test]
    fn a_failed_fresh_load_keeps_the_back_button_away_until_one_loads() {
        let mut page = Page::new();
        page.show();
        page.begin_fresh_load(false);
        page.started(1, true);
        page.finished(1, Outcome::Failed("HostNameNotResolved".into()));
        assert!(!page.fresh_load_done(true));
        page.history_changed(true);
        assert!(!page.snapshot().can_go_back, "next to the failure copy, no arrow");

        // Try again loads it: then its history starts over.
        page.begin_load(true);
        page.started(2, true);
        page.finished(2, Outcome::Ready);
        assert!(page.fresh_load_done(true));
    }

    #[test]
    fn chatgpt_is_heard_again_once_its_fresh_load_is_in() {
        let mut page = Page::new();
        page.show();
        page.begin_fresh_load(true);
        page.started(1, false);
        page.history_changed(true);
        assert!(!page.can_go_back);
        page.finished(1, Outcome::Ready);
        assert!(!page.fresh_load_done(false), "nothing to start over");
        page.history_changed(true);
        assert!(page.can_go_back);
    }

    #[test]
    fn a_reset_answering_after_the_page_went_cold_changes_nothing() {
        let mut page = Page::new();
        page.show();
        page.begin_fresh_load(false);
        page.started(1, true);
        page.finished(1, Outcome::Ready);
        assert!(page.fresh_load_done(true));
        page.hide();
        page.go_cold();
        page.history_reset(true);
        assert!(!page.can_go_back);
        assert_eq!(page.history, History::Heard);
    }

    #[test]
    fn the_placeholder_is_not_a_page() {
        let mut page = Page::new();
        page.started(1, true);
        assert_eq!(page.phase, Phase::Cold, "about:blank loading is not the page loading");
        page.set_url(Some(BLANK.into()));
        assert_eq!(page.url, None);
        page.set_title(Some(BLANK.into()));
        assert_eq!(page.title, None);
    }

    #[test]
    fn the_island_hears_the_contracts_names() {
        assert_eq!(Phase::Cold.name(), "cold");
        assert_eq!(Phase::Loading.name(), "loading");
        assert_eq!(Phase::Ready.name(), "ready");
        assert_eq!(Phase::Blocked(503).name(), "blocked");
        assert_eq!(Phase::Failed(String::new()).name(), "failed");
    }

    // ── Outcomes ───────────────────────────────────────────────────────────

    #[test]
    fn chatgpt_refusing_the_view_is_blocked_and_the_sites_403_is_its_own_page() {
        assert_eq!(outcome(true, false, 403, 0), Outcome::Blocked(403));
        assert_eq!(outcome(true, true, 503, 0), Outcome::Blocked(503));
        assert_eq!(outcome(false, false, 403, 0), Outcome::Ready);
        // Other errors from the server are the server's page, on both.
        assert_eq!(outcome(true, false, 500, 0), Outcome::Ready);
        assert_eq!(outcome(false, false, 404, 0), Outcome::Ready);
    }

    #[test]
    fn no_answer_at_all_is_a_failure_with_webview2s_name() {
        assert_eq!(outcome(true, false, 0, 13), Outcome::Failed("HostNameNotResolved".into()));
        assert_eq!(outcome(false, false, 0, 7), Outcome::Failed("Timeout".into()));
        assert_eq!(outcome(false, false, 0, 99), Outcome::Failed("Unknown".into()));
        // A response cut off half way is a failure, not a page.
        assert_eq!(outcome(false, false, 200, 9), Outcome::Failed("ConnectionAborted".into()));
    }

    #[test]
    fn a_cancelled_navigation_is_its_own_outcome() {
        assert_eq!(outcome(true, false, 0, 14), Outcome::Canceled);
        assert_eq!(outcome(false, false, 200, 14), Outcome::Canceled);
        assert_eq!(outcome(true, true, 200, 0), Outcome::Ready);
    }

    #[test]
    fn every_web_error_status_has_a_name() {
        for code in 0..=18 {
            assert!(!web_error_name(code).is_empty());
        }
        assert_eq!(web_error_name(14), "OperationCanceled");
        assert_eq!(web_error_name(-1), "Unknown");
    }

    /// Linux reports its failures by name, and they must land on the same
    /// statuses — and so the same words — as WebView2's.
    #[test]
    fn every_web_error_name_comes_back_to_its_status() {
        for code in 0..=18 {
            assert_eq!(web_error_code(web_error_name(code)), code);
        }
        assert_eq!(web_error_code("HostNameNotResolved"), 13);
        assert_eq!(web_error_code("Timeout"), 7);
        assert_eq!(web_error_code("ConnectionAborted"), 9);
        assert_eq!(web_error_code("OperationCanceled"), 14);
        assert_eq!(web_error_code("NotAName"), 0);
        assert_eq!(
            outcome(false, false, 0, web_error_code("HostNameNotResolved")),
            Outcome::Failed("HostNameNotResolved".into())
        );
        assert_eq!(outcome(true, false, 0, web_error_code("OperationCanceled")), Outcome::Canceled);
        assert_eq!(outcome(false, false, 0, web_error_code("Unknown")), Outcome::Failed("Unknown".into()));
    }

    // ── Whose navigation it is ─────────────────────────────────────────────

    #[test]
    fn a_click_is_the_users_and_a_redirect_never_is() {
        let mut who = Initiator::default();
        assert!(who.started(1, true, false));
        // A server answering it with a 30x to tel: is not the user clicking.
        assert!(!who.started(1, true, true));
        // What the webview says no to stays no.
        assert!(!who.started(2, false, false));
    }

    #[test]
    fn a_navigation_the_host_starts_is_never_the_users_nor_any_hop_of_it() {
        // A page's window.open, loaded in place: WebView2 counts the host's
        // navigation as user initiated.
        let mut who = Initiator::default();
        who.host_navigates();
        assert!(!who.started(5, true, false));
        assert!(!who.started(5, true, true), "its redirect");
        assert!(!who.started(5, true, false), "the same navigation again");
        // The user's next click is theirs.
        assert!(who.started(6, true, false));
    }

    #[test]
    fn only_a_navigation_starting_takes_the_hosts_mark() {
        // A redirect of a navigation already under way is not the host's.
        let mut who = Initiator::default();
        who.host_navigates();
        assert!(!who.started(4, true, true));
        assert!(!who.started(5, true, false), "the host's own, next");
        assert!(who.started(6, true, false));

        // Nothing came of it: the next navigation is the user's.
        let mut who = Initiator::default();
        who.host_navigates();
        who.host_gave_up();
        assert!(who.started(7, true, false));

        // A same-document navigation starts nothing, and is over once the
        // address has changed.
        let mut who = Initiator::default();
        who.host_navigates();
        who.address_changed();
        assert!(who.started(8, true, false));

        // An address changing after the host's navigation started leaves it
        // the host's.
        let mut who = Initiator::default();
        who.host_navigates();
        assert!(!who.started(9, true, false));
        who.address_changed();
        assert!(!who.started(9, true, true));
    }

    // ── Geometry ───────────────────────────────────────────────────────────

    #[test]
    fn the_card_lands_on_whole_pixels_edge_by_edge() {
        let card = Card { x: 20.0, y: 84.0, w: 560.0, h: 546.0 };
        assert_eq!(physical(card, 1.0), Px { x: 20, y: 84, w: 560, h: 546 });
        assert_eq!(physical(card, 2.0), Px { x: 40, y: 168, w: 1120, h: 1092 });
        // 125 %: 20 × 1.25 = 25, (20 + 560) × 1.25 = 725.
        assert_eq!(physical(card, 1.25), Px { x: 25, y: 105, w: 700, h: 683 });
        // An edge on a half pixel: both edges round, so the far edge is where
        // the island's own card ends.
        let odd = Card { x: 20.4, y: 0.0, w: 559.2, h: 10.0 };
        let px = physical(odd, 1.25);
        assert_eq!(px.x + px.w, ((20.4 + 559.2) * 1.25_f64).round() as i32);
    }

    #[test]
    fn the_corner_is_the_macs_sixteen_points_at_every_scale() {
        assert_eq!(corner_ellipse(1.0), 32);
        assert_eq!(corner_ellipse(1.25), 40);
        assert_eq!(corner_ellipse(1.5), 48);
        assert_eq!(corner_ellipse(2.0), 64);
        assert_eq!(region_extent(560, 546), (561, 547));
    }

    #[test]
    fn only_a_real_rectangle_is_usable() {
        assert!(Card { x: 0.0, y: 0.0, w: 1.0, h: 1.0 }.usable());
        assert!(!Card { x: 0.0, y: 0.0, w: 0.0, h: 546.0 }.usable());
        assert!(!Card { x: 0.0, y: 0.0, w: 560.0, h: -1.0 }.usable());
        assert!(!Card { x: f64::NAN, y: 0.0, w: 560.0, h: 546.0 }.usable());
        assert!(!Card { x: 0.0, y: 0.0, w: f64::INFINITY, h: 546.0 }.usable());
    }

    #[test]
    fn a_page_window_is_glued_over_the_card() {
        let card = physical(Card { x: 20.0, y: 84.0, w: 560.0, h: 546.0 }, 1.5);
        let px = glued((1000, 200), card);
        assert_eq!((px.x, px.y), (1000 + 30, 200 + 126));
        assert_eq!((px.w, px.h), (card.w, card.h));
    }

    // ── Where the keyboard goes back to ────────────────────────────────────

    const VS_CODE: isize = 0x1001;
    const WORD: isize = 0x1002;
    const START: isize = 0x1003;

    #[test]
    fn the_keyboard_goes_back_to_where_the_user_was_last() {
        // Opened from VS Code, then the user went to Word and came back.
        let mut recent = Recent::new();
        recent.note(VS_CODE);
        recent.note(WORD);
        assert_eq!(recent.take_newest(|_| true), Some(WORD));
    }

    #[test]
    fn a_window_gone_since_gives_way_to_the_one_before() {
        // The Start menu was opened and folded away again: cloaked, so not
        // fit. VS Code, from before it, is.
        let mut recent = Recent::new();
        recent.note(VS_CODE);
        recent.note(START);
        assert_eq!(recent.take_newest(|w| w != START), Some(VS_CODE));
        // Nothing fit: nothing is handed anything.
        let mut recent = Recent::new();
        recent.note(START);
        assert_eq!(recent.take_newest(|_| false), None);
    }

    #[test]
    fn a_window_gone_back_to_is_the_newest_again() {
        let mut recent = Recent::new();
        recent.note(VS_CODE);
        recent.note(WORD);
        recent.note(VS_CODE);
        assert_eq!(recent.take_newest(|_| true), Some(VS_CODE));
        // Each one once: with VS Code refused, Word is next, not VS Code again.
        let mut recent = Recent::new();
        for w in [VS_CODE, WORD, VS_CODE] {
            recent.note(w);
        }
        assert_eq!(recent.take_newest(|w| w != VS_CODE), Some(WORD));
    }

    #[test]
    fn the_visit_is_over_once_the_keyboard_went_back() {
        let mut recent = Recent::new();
        recent.note(VS_CODE);
        assert_eq!(recent.take_newest(|_| true), Some(VS_CODE));
        assert_eq!(recent.take_newest(|_| true), None);
        // Forgotten even when none was fit.
        recent.note(VS_CODE);
        assert_eq!(recent.take_newest(|_| false), None);
        assert_eq!(recent.take_newest(|_| true), None);
    }

    #[test]
    fn only_the_last_few_windows_are_kept_and_never_none() {
        let mut recent = Recent::new();
        recent.note(0);
        assert_eq!(recent.take_newest(|_| true), None);
        for w in 1..=(Recent::KEPT as isize + 2) {
            recent.note(w);
        }
        // The two oldest are gone: with every newer one refused, nothing is left.
        let newest = Recent::KEPT as isize + 2;
        assert_eq!(recent.take_newest(|w| w <= 2), None);
        let mut recent = Recent::new();
        for w in 1..=newest {
            recent.note(w);
        }
        assert_eq!(recent.take_newest(|w| w <= 3), Some(3));
    }

    const NOTEPAD: isize = 0x1004;

    #[test]
    fn with_nowhere_from_the_visit_the_keyboard_goes_to_the_last_window_at_all() {
        // Opened from the taskbar or the tray, neither of which is kept: the
        // visit has nothing, and Notepad, where the user was before, has it.
        let mut recent = Recent::new();
        assert_eq!(recent.take_back(NOTEPAD, |_| true), Some(NOTEPAD));
        // The visit's own come first.
        let mut recent = Recent::new();
        recent.note(WORD);
        assert_eq!(recent.take_back(NOTEPAD, |_| true), Some(WORD));
        // None of the visit's is fit any more.
        let mut recent = Recent::new();
        recent.note(START);
        assert_eq!(recent.take_back(NOTEPAD, |w| w != START), Some(NOTEPAD));
        // The last one is asked again, too: gone since, it gets nothing.
        let mut recent = Recent::new();
        assert_eq!(recent.take_back(NOTEPAD, |w| w != NOTEPAD), None);
        // Never none.
        let mut recent = Recent::new();
        assert_eq!(recent.take_back(0, |_| true), None);
        // The visit is forgotten either way.
        let mut recent = Recent::new();
        recent.note(WORD);
        assert_eq!(recent.take_back(NOTEPAD, |w| w == NOTEPAD), Some(NOTEPAD));
        assert_eq!(recent.take_back(0, |_| true), None);
    }
}
