// The pages' pure half: what state a page is in, when it may be on screen,
// when it goes cold, and which pixels it lands on.
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
// built fresh on every open, and blanked once it has closed.

use std::time::Duration;

/// How long ChatGPT stays loaded once it is out of sight — WebChatController's
/// `coldTTL`. Long enough that closing the island and reopening it is free;
/// short enough that a forgotten chat does not talk to OpenAI all day.
pub const CHAT_COLD_AFTER: Duration = Duration::from_secs(600);

/// The site's: next to none. NotchSiteView blanks its page the moment it
/// disappears (`NotchSiteWeb.stop()`), and every open loads it fresh. The grace
/// is for the island, not the user: the island takes a page off screen while it
/// is still moving (island/pageHost.ts) and puts it back once it has settled,
/// and that must not cost the site its place. Well past any spring; short
/// enough that closing the site and opening it again is a fresh load, as there.
pub const SITE_COLD_AFTER: Duration = Duration::from_secs(5);

/// How long a page stays loaded once it is out of sight.
pub fn cold_after(is_chat: bool) -> Duration {
    if is_chat {
        CHAT_COLD_AFTER
    } else {
        SITE_COLD_AFTER
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
    /// A main-frame navigation began. `cancelled` when the navigation policy
    /// has already refused it; `by_user` when a click or a key started it.
    Started { id: u64, url: String, by_user: bool, cancelled: bool },
    /// A main-frame navigation ended. `status` is the HTTP status, 0 without a
    /// response; `error` the WebView2 web error status.
    Finished { id: u64, success: bool, status: u16, error: i32 },
    /// The address changed, a same-document navigation included.
    Source(String),
    Title(String),
    History { can_go_back: bool },
    /// Escape, pressed while the page has the keyboard.
    Escape,
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
    /// itself (first open, coming back from cold, Try again).
    pub painted: bool,
    /// Asked for by `page_show` and not put away since.
    pub wanted: bool,
    pub url: Option<String>,
    pub title: Option<String>,
    pub can_go_back: bool,
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
            nav: None,
            epoch: 0,
        }
    }

    /// Whether the host should have it on screen: asked for, and with
    /// something worth showing — WebChatHostView's `opacity(loadState ==
    /// .ready ? 1 : 0)`, plus a page that is already up and loading its next
    /// document on its own.
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
    fn chatgpt_goes_cold_after_the_macs_ten_minutes_and_the_site_almost_at_once() {
        assert_eq!(cold_after(true), Duration::from_secs(600));
        // Longer than the island takes to settle, so a page it puts back is
        // the page it took away; nowhere near ChatGPT's.
        assert!(cold_after(false) >= Duration::from_secs(2));
        assert!(cold_after(false) <= Duration::from_secs(10));
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
}
