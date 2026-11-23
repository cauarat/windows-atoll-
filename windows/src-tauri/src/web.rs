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
// is something to see: ChatGPT once the load it was given has finished, as the
// Mac's fades in on didFinish; the site from its first content, as
// NotchSiteView's page renders while it loads. Until then, and whenever it is
// blocked or has failed, the island's own card is what shows.
//
// Both are created hidden on about:blank at launch, like every webview in this
// app — one built later, from a command, deadlocks WebView2 or comes up blank —
// and fetch nothing until they are first shown: nobody who has not asked for
// ChatGPT or the site has a page open to either. Out of sight they go quiet
// (muted, and paused once really away), and then cold (back on about:blank):
// ChatGPT after the Mac's ten minutes, the site the moment it is left or
// closed, as NotchSiteView blanks its page on disappear.
//
// What decides all of that — the states, when a page may be on screen, when it
// goes cold, which pixels it lands on — is page_model.rs, which has no Tauri in
// it. This file hosts the pages and talks to the island.
//
// The pages get no IPC. They are remote origins, and capabilities/default.json
// names the webviews it covers, theirs not among them, so every invoke from
// chatgpt.com or the site is refused. (Tauri still injects its scripts into
// every webview it creates; it is the ACL that says no.)

use std::sync::atomic::{AtomicBool, AtomicIsize, Ordering};
use std::sync::{LazyLock, Mutex};

use serde::Serialize;
use tauri::webview::{Color, DownloadEvent, NewWindowResponse, PermissionKind, PermissionResponse};
use tauri::{AppHandle, Emitter, Manager, Url, Webview};

use crate::island;
use crate::log;
use crate::page_model::{self, Card, Leave, Page, Phase, Signal, Snapshot, BLANK};
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

/// No element fullscreen, in any frame: a page going fullscreen would take the
/// island's own window with it — tauri-runtime-wry makes the window of every
/// WebView2 follow its page into fullscreen, and the pages' window is the
/// island. WKWebView keeps element fullscreen off unless asked, and the Mac
/// never asks. The API says no as a browser that cannot go fullscreen does:
/// `fullscreenEnabled` is false, a request is refused, and a video's own
/// prefixed `webkitEnterFullscreen` does nothing.
///
/// The way out stays the browser's own. `exitFullscreen` is pinned on each
/// document, before any of the page's script runs, as the real one bound to
/// it, where the page can neither replace nor remove it: the host's backstop
/// (platform::page_hooks) calls it on a page that got to fullscreen some
/// other way — a video's own controls do not go through the API — and the
/// page cannot keep it there. Pinned as a property that cannot be redefined
/// and whose setter ignores what it is given, so a page assigning its own —
/// a fullscreen polyfill's line — changes nothing and does not throw.
const NO_FULLSCREEN: &str = r#"(() => {
  try {
    const refuse = function () {
      return Promise.reject(new TypeError("Fullscreen is not available here."));
    };
    for (const name of ["requestFullscreen", "webkitRequestFullscreen", "webkitRequestFullScreen"]) {
      if (name in Element.prototype) {
        Object.defineProperty(Element.prototype, name, { value: refuse, writable: true, configurable: true });
      }
    }
    if (typeof HTMLVideoElement === "function") {
      for (const name of ["webkitEnterFullscreen", "webkitEnterFullScreen"]) {
        if (name in HTMLVideoElement.prototype) {
          Object.defineProperty(HTMLVideoElement.prototype, name, {
            value: function () {},
            writable: true,
            configurable: true,
          });
        }
      }
    }
    for (const name of ["fullscreenEnabled", "webkitFullscreenEnabled"]) {
      if (name in Document.prototype) {
        Object.defineProperty(Document.prototype, name, { get: () => false, configurable: true });
      }
    }
    for (const name of ["exitFullscreen", "webkitExitFullscreen"]) {
      const exit = Document.prototype[name];
      if (typeof exit === "function") {
        const pinned = exit.bind(document);
        Object.defineProperty(document, name, {
          get: () => pinned,
          set: () => {},
          configurable: false,
          enumerable: false,
        });
      }
    }
  } catch (_) {}
})();"#;

/// What a page plays, kept track of so its media can stop when it goes out of
/// sight and go on when it is back: the Mac's
/// `setAllMediaPlaybackSuspended(true)` and `(false)` in WebChatController.
/// Mute alone would let a reading aloud run on unheard, and WebView2 will not
/// suspend a page that is playing audio (platform::page_suspend).
///
/// The top document's only, which is where the host's calls run
/// (`PAUSE_MEDIA`, `RESUME_MEDIA`). Every media element asked to play is
/// remembered, weakly — the ones made in script and never put in the
/// document too, as a reading aloud may be — beside every one in the
/// document. Pausing pauses those playing and remembers them; resuming plays
/// exactly those that are still paused, and forgets them.
const MEDIA: &str = r#"(() => {
  try {
    if (window.top !== window) return;
    const apply = Reflect.apply;
    const realPlay = HTMLMediaElement.prototype.play;
    const realPause = HTMLMediaElement.prototype.pause;
    const known = new WeakSet();
    const asked = new Set();
    const held = new Set();
    const remember = (el) => {
      if (known.has(el)) return;
      known.add(el);
      asked.add(new WeakRef(el));
      if (asked.size > 64) {
        for (const ref of asked) if (!ref.deref()) asked.delete(ref);
      }
    };
    const wrapped = {
      play() {
        try { remember(this); } catch (_) {}
        return apply(realPlay, this, []);
      },
    };
    Object.defineProperty(HTMLMediaElement.prototype, "play", {
      value: wrapped.play,
      writable: true,
      configurable: true,
    });
    const all = () => {
      const found = new Set(document.querySelectorAll("audio, video"));
      for (const ref of asked) {
        const el = ref.deref();
        if (el) found.add(el);
      }
      return found;
    };
    const media = Object.freeze({
      pause() {
        for (const el of all()) {
          if (!el.paused) {
            apply(realPause, el, []);
            held.add(el);
          }
        }
      },
      resume() {
        const playing = [...held];
        held.clear();
        for (const el of playing) {
          if (el.paused && !el.ended) {
            Promise.resolve(apply(realPlay, el, [])).catch(() => {});
          }
        }
      },
    });
    Object.defineProperty(window, "__notchyMedia", { value: media });
  } catch (_) {}
})();"#;

/// The page's media, paused and remembered (`MEDIA`).
const PAUSE_MEDIA: &str = "window.__notchyMedia && window.__notchyMedia.pause()";

/// What `PAUSE_MEDIA` paused, playing again (`MEDIA`).
const RESUME_MEDIA: &str = "window.__notchyMedia && window.__notchyMedia.resume()";

/// The card's fill behind a page that has not painted: #141518.
fn card_color() -> Color {
    let (r, g, b) = page_model::CARD_RGB;
    Color(r, g, b, 255)
}

// ── Policy ───────────────────────────────────────────────────────────────────
//
// Pure down to `page_url`, so the rules are tested without an app; what comes
// after asks the app, or acts on a decision.

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
/// page may hand to the browser — WhatsApp's window's too (whatsapp.rs).
pub(crate) fn safe_web_url(url: &Url) -> bool {
    matches!(url.scheme(), "http" | "https") && url.host_str().is_some_and(|h| !h.is_empty())
}

/// The placeholder a page holds while it is cold.
fn is_blank(url: &Url) -> bool {
    url.scheme() == "about" && url.path() == "blank"
}

/// One of the app's own origins: WebView2 serves Tauri's custom protocols —
/// the island's own page among them — under `*.localhost`, and a dev build is
/// served from Vite (`dev`). A blob counts as the origin that made it, and one
/// whose maker cannot be read counts as ours: refused rather than guessed. A
/// remote page must never be able to take a page onto one, where it would
/// count as local. Plain `localhost` is not one: the site may well be a
/// server of the user's own.
fn is_local_origin(url: &Url, dev: Option<&Url>) -> bool {
    let url = if url.scheme() == "blob" {
        // `blob:https://host/uuid`: the address it was made by is its path.
        match Url::parse(url.path()) {
            Ok(inner) => inner,
            Err(_) => return true,
        }
    } else {
        url.clone()
    };
    let host = url.host_str().unwrap_or("").trim_end_matches('.').to_ascii_lowercase();
    if host.ends_with(".localhost") {
        return true;
    }
    dev.is_some_and(|dev| dev.origin() == url.origin())
}

/// NotchSiteWeb's rule: a web page stays in the island, wherever it is —
/// http, https, about, and a blob a web page made. Anything else (mail, an
/// app's scheme, a file, a script) is not ours to render.
fn site_keeps(url: &Url) -> bool {
    match url.scheme() {
        "http" | "https" | "about" => true,
        "blob" => Url::parse(url.path()).is_ok_and(|inner| safe_web_url(&inner)),
        _ => false,
    }
}

/// Where a navigation goes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Route {
    /// It happens in the page.
    Stay,
    /// It is refused, and the address opens in the default browser.
    Browser,
    /// It is refused, and that is all.
    Refuse,
}

/// What becomes of a main-frame navigation to `url` — any but the
/// placeholder, which is the host's own (`allows`). ChatGPT keeps to its hosts
/// and hands any other web address to the browser: WebChatController's rule.
/// The site keeps any web page: NotchSiteWeb's. Neither ever goes onto one of
/// the app's own origins (`app_origin`), nor sends one to the browser.
fn route(label: &str, url: &Url, app_origin: bool) -> Route {
    let stays = if label == CHAT_LABEL {
        keeps_in_window(url, &CHAT_HOSTS)
    } else {
        site_keeps(url)
    };
    if app_origin {
        Route::Refuse
    } else if stays {
        Route::Stay
    } else if safe_web_url(url) {
        Route::Browser
    } else {
        Route::Refuse
    }
}

/// `route`, for a navigation that may be a frame's, not the page's: what
/// WebKitGTK's decide-policy reports on Linux, which Tauri's `on_navigation`
/// hears for every frame with no way to tell one from the other. The Mac lets
/// every subframe through — Turnstile, the sign-in frames — so a web address
/// loads, and nothing goes to the browser from here: a frame's address must
/// never open a tab by itself. A link from ChatGPT to another site then opens
/// in ChatGPT's own window there, rather than the browser
/// (docs/parity/README.md). Every other address is refused as before: an app's
/// own origin, a scheme that is not the web's, and the placeholder unless the
/// host is taking the page there (`allows`).
fn route_any_frame(label: &str, url: &Url, app_origin: bool) -> Route {
    match route(label, url, app_origin) {
        Route::Browser => Route::Stay,
        decided => decided,
    }
}

/// `target=_blank`, `window.open`: never a second webview. ChatGPT loads an
/// address it may stay on in place and opens any other web address in the
/// browser — WebChatController.createWebViewWith. The site loads any web
/// address in place, and nothing else — NotchSiteWeb.createWebViewWith.
fn route_new_window(label: &str, url: &Url, app_origin: bool) -> Route {
    if label == CHAT_LABEL {
        return route(label, url, app_origin);
    }
    if !app_origin && safe_web_url(url) {
        Route::Stay
    } else {
        Route::Refuse
    }
}

/// An address as it may be handed to the system: Chromium's
/// `EscapeExternalHandlerValue`. Letters, digits and the URL's own punctuation
/// (`;/?:@&=+$,!'()*-._~#[]`) stay as they are. Every other byte is
/// percent-escaped, above all a quote, a space, a backslash, a caret or a
/// pipe, which the command line of the program the system opens the address
/// with would read as its own. An escape already in the address stays as it
/// is.
///
/// The parsed address alone is not enough. A `mailto:` or `tel:` address has
/// an opaque path, and the URL parser leaves quotes and spaces in it, so
/// `tel:x" "C:\…` would come out of `Url::parse` unchanged.
fn for_the_system(url: &Url) -> String {
    const KEPT: &[u8] = b";/?:@&=+$,!'()*-._~#[]";
    let raw = url.as_str().as_bytes();
    let mut out = String::with_capacity(raw.len());
    for (i, &b) in raw.iter().enumerate() {
        let escaped_already = b == b'%'
            && raw.get(i + 1).is_some_and(u8::is_ascii_hexdigit)
            && raw.get(i + 2).is_some_and(u8::is_ascii_hexdigit);
        if b.is_ascii_alphanumeric() || KEPT.contains(&b) || escaped_already {
            out.push(char::from(b));
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// A link the system opens instead of the island: a mail address or a phone
/// number, which NotchSiteWeb hands to the system when it was clicked. Those
/// two only. Windows opens whatever it is given through the shell, so nothing
/// else a page writes may reach it: not an app's own scheme, not a search, not
/// a path (`C:\…` reads as a scheme of one letter). What goes is the parsed
/// address, escaped for a command line (`for_the_system`), never the page's
/// own string.
fn system_link(url: &str) -> Option<String> {
    Url::parse(url)
        .ok()
        .filter(|url| matches!(url.scheme(), "mailto" | "tel"))
        .map(|url| for_the_system(&url))
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

/// `is_local_origin`, with the dev server this build is served from.
fn is_app_origin(app: &AppHandle, url: &Url) -> bool {
    #[cfg(dev)]
    let dev = app.config().build.dev_url.clone();
    #[cfg(not(dev))]
    let dev: Option<Url> = {
        let _ = app;
        None
    };
    is_local_origin(url, dev.as_ref())
}

/// An address from a page, opened by the system: in the default browser, or
/// a mail address or phone number in whatever handles those. Escaped for a
/// command line first (`for_the_system`), whatever its scheme.
pub(crate) fn open_with_system(url: &Url) {
    platform::open_url(&for_the_system(url));
}

/// Whether a navigation may happen in the page (`route`). `any_frame` when
/// the webview asking cannot tell a frame from the page (`route_any_frame`,
/// Linux); WebView2's NavigationStarting is the top document's. Neither page
/// may wander back onto the placeholder unless the host is the one taking it
/// there: going back past the first page of a visit would land on a blank
/// card.
fn allows(app: &AppHandle, label: &'static str, url: &Url, any_frame: bool) -> bool {
    if is_blank(url) {
        return with(label, |slot| std::mem::take(&mut slot.blanking)).unwrap_or(false);
    }
    let app_origin = is_app_origin(app, url);
    let decided = if any_frame {
        route_any_frame(label, url, app_origin)
    } else {
        route(label, url, app_origin)
    };
    match decided {
        Route::Stay => true,
        Route::Browser => {
            open_with_system(url);
            false
        }
        Route::Refuse => false,
    }
}

/// A new-window request (`route_new_window`). One loaded in place is the host
/// navigating, never the user clicking, whatever WebView2 makes of it
/// (page_model::Initiator).
fn new_window(app: &AppHandle, label: &'static str, url: Url) {
    match route_new_window(label, &url, is_app_origin(app, &url)) {
        Route::Stay => {
            if let Some(page) = host::webview(app, label) {
                platform::page_resume(&page);
                with(label, |slot| slot.initiator.host_navigates());
                if page.navigate(url).is_err() {
                    with(label, |slot| slot.initiator.host_gave_up());
                }
            }
        }
        Route::Browser => open_with_system(&url),
        Route::Refuse => {}
    }
}

/// Downloads go to the browser — a response WebKit cannot show is opened there
/// by WebChatController — never into a folder from a chrome-less page.
fn download(event: DownloadEvent<'_>) -> bool {
    match event {
        DownloadEvent::Requested { url, .. } => {
            if safe_web_url(&url) {
                open_with_system(&url);
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
    /// What the host last did with it, so a change is acted on once.
    on_screen: bool,
    /// What the island was last told.
    said: Option<Snapshot>,
    /// The island took it away while moving, and whether the page itself had
    /// the keyboard then. Until the user leaves it, its coming back is the
    /// island settling, however long the move took. None once the user has
    /// left it.
    hidden: Option<bool>,
    /// The site is coming back from the island settling, and had the keyboard
    /// itself when it went: it gets it back as it comes up, if the island
    /// still has it to give (`give_keyboard`). Nothing is taken from another
    /// app, and nothing the site did not have — only what moving cost it.
    regain: bool,
    /// Which of its navigations count as the user's.
    initiator: page_model::Initiator,
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
    let Some((visible, changed, regain, news)) = with(label, |slot| {
        let visible = slot.page.visible();
        let changed = visible != slot.on_screen;
        slot.on_screen = visible;
        let regain = visible && changed && std::mem::take(&mut slot.regain);
        let snapshot = slot.page.snapshot();
        let news = (slot.said.as_ref() != Some(&snapshot)).then(|| {
            slot.said = Some(snapshot.clone());
            snapshot
        });
        (visible, changed, regain, news)
    }) else {
        return;
    };
    if changed {
        host::set_visible(app, label, visible);
        if visible {
            // ChatGPT takes the keyboard as it appears, if the island has it
            // to give. The site does not: it gets keys once it is clicked
            // into, as NotchSiteWeb does — or back after the island moved, if
            // it had them when it went (`Slot::regain`).
            if label == CHAT_LABEL || regain {
                host::give_keyboard(app, label);
            }
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
    // ChatGPT stays off screen until it has loaded (WebChatHostView); the site
    // comes up with its first content and renders as it loads (NotchSiteView).
    slot.page.begin_fresh_load(label == CHAT_LABEL);
    slot.loaded = Some(url.to_string());
    Load::Navigate(url)
}

fn run(label: &'static str, page: &Webview, load: Load) {
    let result = match load {
        Load::Nothing => return,
        Load::Navigate(url) => {
            // Woken before it is given anything to do.
            platform::page_resume(page);
            page.navigate(url)
        }
        Load::Reload => {
            platform::page_resume(page);
            page.reload()
        }
    };
    if let Err(err) = result {
        log::line(format!("{label} could not load — {err}"));
        with(label, |slot| slot.page.phase = Phase::Failed("UnexpectedError".to_string()));
    }
}

/// A page whose webview could not be built. Said as a failure, so the island
/// shows its words and Try again rather than dots for ever.
fn unavailable(app: &AppHandle, label: &'static str) -> PageState {
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
    state
}

/// `page_show`: over `card`, loaded, and on screen once it has something to
/// show.
fn show(app: &AppHandle, label: &'static str, card: Card) -> Result<PageState, String> {
    if !card.usable() {
        return Err(format!("{label}: the card has no room for a page"));
    }
    let Some(page) = host::webview(app, label) else {
        // ChatGPT's is built the first time it is asked for (`build_later`),
        // and comes up over this card once it is ready. Meanwhile it is what
        // it would be anyway: loading, off screen until it has.
        if host::build_later(app, label, card) {
            let mut loading = Page::new();
            loading.show();
            loading.begin_fresh_load(label == CHAT_LABEL);
            return Ok(PageState::of(label, loading.snapshot()));
        }
        return Ok(unavailable(app, label));
    };
    // One page on the island at a time, as there is one view at a time on the
    // Mac: the other one leaves first.
    for other in LABELS {
        if other != label && wanted(other) {
            hide(app, other, Leave::Away);
        }
    }
    let site = site_url(app);
    let (arriving, bring_forward, load) = with(label, |slot| {
        let arriving = !slot.page.wanted;
        // Back after the island took it away while moving is the island
        // settling, not the user asking again, however long the move took:
        // nothing comes forward for it, and the keyboard goes into it only if
        // the island still has it (`take_keyboard`, `give_keyboard`).
        let settling = slot.hidden.is_some();
        if arriving {
            slot.regain = label == SITE_LABEL && slot.hidden == Some(true);
        }
        slot.page.show();
        slot.card = Some(card);
        (arriving, !settling, plan_load(label, slot, &site))
    })
    .ok_or_else(|| format!("no page called {label}"))?;

    host::place(app, label, card, None);
    if arriving {
        platform::page_resume(&page);
        platform::page_set_muted(&page, false);
        // What it was playing when it went, playing on (`hide`).
        let _ = page.eval(RESUME_MEDIA);
        // Where the user was, for when the screen closes: the site included,
        // which they may click into. Nothing has been handed back before
        // this, a field of the island's that has just let go included — only
        // `hide_all` hands the keyboard back — so ChatGPT takes it from the
        // island itself.
        host::remember_foreground(app);
        if label == CHAT_LABEL {
            host::take_keyboard(app, bring_forward);
        } else {
            host::allow_keyboard(app);
        }
    }
    run(label, &page, load);
    settle(app, label);
    Ok(state(label))
}

/// `page_hide`: off screen at once and quiet — paused too unless the island is
/// only moving — and cold once it has stayed away: the site at once when the
/// user left it or closed it.
///
/// A page already out of sight is still told why it went: the island takes a
/// page away while it moves, and the user may leave it before it comes back.
fn hide(app: &AppHandle, label: &'static str, leave: Leave) {
    // Still being built: it is not to come up once it is.
    host::cancel_pending(label);
    // Read while the page is still up: whether it has the keyboard itself.
    let had_keyboard = host::page_has_keyboard(app, label);
    let Some(epoch) = with(label, |slot| {
        let epoch = slot.page.hide();
        slot.regain = false;
        if !leave.is_settling() {
            // Left: whenever it comes back, that is the user asking again.
            slot.hidden = None;
        } else if epoch.is_some() {
            slot.hidden = Some(had_keyboard);
        }
        epoch
    }) else {
        return;
    };
    let page = host::webview(app, label);
    if epoch.is_some() {
        if let Some(page) = &page {
            platform::page_set_muted(page, true);
        }
        settle(app, label);
        // A closed screen hands the keyboard back first (`hide_all`).
        if leave != Leave::Closed && !holds_keyboard() {
            host::release_keyboard(app);
        }
    }
    let after = smoke_cold_after(label).unwrap_or_else(|| page_model::cold_after(label == CHAT_LABEL, leave));
    if after.is_zero() {
        go_cold(app, label, None);
        return;
    }
    if leave.pauses() && with(label, |slot| slot.page.phase != Phase::Cold).unwrap_or(false) {
        if let Some(page) = &page {
            // Its media first, remembered for its next show: a page that is
            // playing audio is one WebView2 will not suspend.
            let _ = page.eval(PAUSE_MEDIA);
            platform::page_suspend(page);
        }
    }
    let Some(epoch) = epoch else { return };
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(after).await;
        let handle = app.clone();
        let _ = app.run_on_main_thread(move || go_cold(&handle, label, Some(epoch)));
    });
}

/// Back on the placeholder, with nothing of the page left running — after its
/// time out of sight (`epoch`, from the hide that started the wait), or at
/// once (None) when it was left, closed, or Coucou is switched off.
fn go_cold(app: &AppHandle, label: &'static str, epoch: Option<u64>) {
    let went = with(label, |slot| {
        let due = match epoch {
            Some(epoch) => slot.page.cold_due(epoch),
            None => slot.page.cold_now(),
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
        slot.blanking = true;
        true
    })
    .unwrap_or(false);
    if !went {
        return;
    }
    log::line(format!("{label} page is cold"));
    if host::release(app, label) {
        // Closed, not blanked: there is no navigation to let through.
        with(label, |slot| slot.blanking = false);
    } else if let (Some(page), Ok(blank)) = (host::webview(app, label), Url::parse(BLANK)) {
        platform::page_resume(&page);
        if page.navigate(blank).is_err() {
            with(label, |slot| slot.blanking = false);
        }
    }
    settle(app, label);
}

/// Try again, or the reload button: ChatGPT goes off screen until it has
/// loaded again (WebChatController.reload), the site stays up with its
/// spinner turning (NotchSiteWeb.reload) — unless it had failed, when it comes
/// back with its first content.
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
        Signal::Started { id, url, by_user, redirected, cancelled } => {
            // Never a redirect, nor a navigation the host started itself
            // (page_model::Initiator).
            let by_user = with(label, |slot| slot.initiator.started(id, by_user, redirected))
                .unwrap_or(false);
            // A mail address or a phone number, clicked on the site, is the
            // system's to open (NotchSiteWeb, `.linkActivated`). The policy
            // refuses every such address, so it is decided here.
            if label == SITE_LABEL {
                if let Some(link) = system_link(&url) {
                    if by_user {
                        platform::open_url(&link);
                    }
                    return;
                }
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
        Signal::Content { id, error_page } => {
            with(label, |slot| slot.page.content(id, error_page, label == SITE_LABEL));
            settle(app, label);
        }
        Signal::Finished { id, success, status, error } => {
            let outcome = page_model::outcome(label == CHAT_LABEL, success, status, error);
            // The site's history starts over once a fresh load is in, as a
            // new WKWebView's would.
            let reset = with(label, |slot| {
                slot.page.finished(id, outcome);
                slot.page.fresh_load_done(label == SITE_LABEL)
            })
            .unwrap_or(false);
            settle(app, label);
            if reset {
                if let Some(page) = host::webview(app, label) {
                    let app = app.clone();
                    platform::page_reset_history(&page, move |can_go_back| {
                        with(label, |slot| slot.page.history_reset(can_go_back));
                        settle(&app, label);
                    });
                }
            }
        }
        Signal::Source(url) => {
            with(label, |slot| {
                slot.initiator.address_changed();
                slot.page.set_url(Some(url));
            });
            settle(app, label);
        }
        Signal::Title(title) => {
            with(label, |slot| slot.page.set_title(Some(title)));
            settle(app, label);
        }
        Signal::History { can_go_back } => {
            with(label, |slot| slot.page.history_changed(can_go_back));
            settle(app, label);
        }
        Signal::Escape => {
            let _ = app.emit_to(island::WINDOW_LABEL, "page-escape", PageEscape { label });
        }
        Signal::Fullscreen => host::leave_fullscreen(app),
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
///
/// `away` when the user went to another of the island's views: the site goes
/// cold at once, ChatGPT keeps its ten minutes, and the keyboard stays with
/// the island, which is still open. Without it, the island is only moving or
/// settling, and puts the page back once it is still.
#[tauri::command]
pub fn page_hide(app: AppHandle, label: String, away: Option<bool>) -> Result<(), String> {
    let leave = if away.unwrap_or(false) { Leave::Away } else { Leave::Moving };
    hide(&app, known(&label)?, leave);
    Ok(())
}

/// The screen was closed — Escape, either X, the close shortcut, the island
/// folding: every page away, the site cold at once, ChatGPT warm for its ten
/// minutes, and the keyboard back to the window it came from.
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
        open_with_system(&url);
    }
    Ok(())
}

/// The screen closed (`page_hide_all`). The keyboard goes back at once to the
/// window the user was in last, other than the island (the Mac's panel
/// resigning key), if the island still holds it. Only then is the island back
/// to a window that never takes focus.
pub fn hide_all(app: &AppHandle) {
    for label in LABELS {
        hide(app, label, Leave::Closed);
    }
    host::give_foreground_back(app);
    host::release_keyboard(app);
}

/// Coucou switched off: both pages away and released at once, as the Mac's
/// controller goes cold when the master switch goes off.
pub fn park(app: &AppHandle) {
    hide_all(app);
    for label in LABELS {
        go_cold(app, label, None);
    }
}

/// The commands the island used before `page_show`/`page_hide`: a page put
/// over the island's whole shape, or put away. Kept until no caller is left.
pub fn toggle(app: &AppHandle, label: &'static str) -> bool {
    if wanted(label) {
        hide_all(app);
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

/// Whether one of the island's own fields has the keyboard (`focus_window`).
static FIELD: AtomicBool = AtomicBool::new(false);

/// The island is taking the keyboard for one of its own fields, the chat's
/// prompt or a reply (`focus_window`): where the user was, for when it lets
/// go.
pub fn field_takes_keyboard(app: &AppHandle) {
    FIELD.store(true, Ordering::Relaxed);
    host::remember_foreground(app);
}

/// The island's field let go of the keyboard (`focus_window`). Nothing is
/// handed back here. The Mac's panel stays key from one card to the next, and
/// resigns only when the island folds or Escape closes it; on Windows that is
/// `hide_all`, which the island sends on every fold and which gives the
/// keyboard back at once.
pub fn field_lets_go(_app: &AppHandle) {
    FIELD.store(false, Ordering::Relaxed);
}

/// The watchdog saw the foreground move to `window` (island.rs). It is the
/// last window the user was in, whatever the island is doing — where the
/// keyboard goes back to when a visit has nowhere else. While the island has
/// the keyboard or may take it (a page up, a field holding it), it is also
/// one of the visit's: where the keyboard goes back to now. The Mac's panel
/// resigning key leaves the keyboard with whichever app is active then, not
/// with the one the visit began in.
pub fn foreground_moved(app: &AppHandle, window: isize) {
    let visit = FIELD.load(Ordering::Relaxed) || holds_keyboard();
    host::note_foreground(app, window, visit);
}

// ── Built at launch ──────────────────────────────────────────────────────────

/// The pages, hidden on about:blank: called once from setup, after the
/// island's window exists. On Windows ChatGPT waits until it is first shown
/// (`child::create`).
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

/// Keeps a window's webview told where its window is, now that Tauri's
/// multiwebview makes every webview a child: wry did that for the webview
/// filling a window, and only for one that fills it. Without it a `<select>`
/// list or the IME opens where the window used to be.
///
/// The keyboard is not handled here. The windows are created hidden and
/// unfocused, and `bring_up` puts the keyboard in a page as its window is
/// shown. Doing it in answer to a focus event fails twice over. Giving a
/// webview the keyboard costs it the keyboard for a moment and hands it back,
/// which is another focus event. And with more than one window doing it, each
/// takes the keyboard back from the other as soon as it gets it. On a runner
/// that meant four hidden windows passing the foreground around five times a
/// second, about 140 focus changes a second with nothing on screen, and every
/// click on the island taken away from it within a millisecond.
pub fn keep_hosting(win: &tauri::WebviewWindow) {
    #[cfg(windows)]
    {
        let webview: &Webview = win.as_ref();
        let webview = webview.clone();
        win.on_window_event(move |event| {
            if let tauri::WindowEvent::Moved(_) = event {
                platform::notify_webview_moved(&webview);
            }
        });
    }
    #[cfg(not(windows))]
    let _ = win;
}

/// Brings a window forward with the keyboard in its page: what showing one
/// of Coucou's windows means. A child webview does not get the keyboard with
/// its window. Tauri gives it back to whichever webview had it last, and a
/// page that never had it gets nothing, so typing goes nowhere until a click.
pub fn bring_up(win: &tauri::WebviewWindow) {
    let _ = win.set_focus();
    #[cfg(windows)]
    {
        let webview: &Webview = win.as_ref();
        let _ = webview.set_focus();
    }
}

/// `NOTCHY_SMOKE_VIEW=webchat` (or `site`, or `whatsapp`) in a debug build:
/// once the island is up and its greeting is over, it is asked to open that
/// view, as if its control had been pressed — for the CI run that screenshots
/// a real runner.
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
        std::thread::sleep(std::time::Duration::from_secs(12));
        // Under a first-run welcome the island is parked: wait for it, a while.
        for _ in 0..60 {
            if crate::island_live(&app) {
                break;
            }
            std::thread::sleep(std::time::Duration::from_secs(1));
        }
        log::line(format!("smoke: opening {view}"));
        // WhatsApp's sign-in window, built for the occasion as Settings'
        // Connect button builds it: the proof that a window built after launch
        // loads its page.
        if view == "whatsapp" {
            crate::whatsapp::show_login(&app);
            return;
        }
        let _ = app.emit_to(island::WINDOW_LABEL, "smoke-open-view", view);
    });
    if let Err(err) = started {
        log::line(format!("thread smoke-open-view failed to start — {err}"));
    }
}

#[cfg(not(debug_assertions))]
pub fn smoke(_app: &AppHandle) {}

/// `NOTCHY_SMOKE_CHAT_COLD_SECS` in a debug build: ChatGPT goes cold that
/// many seconds after it is put away, rather than ten minutes — so the CI run
/// can watch its webview close and be built again within one run.
#[cfg(debug_assertions)]
fn smoke_cold_after(label: &str) -> Option<std::time::Duration> {
    if label != CHAT_LABEL {
        return None;
    }
    let secs: u64 = std::env::var("NOTCHY_SMOKE_CHAT_COLD_SECS").ok()?.trim().parse().ok()?;
    Some(std::time::Duration::from_secs(secs))
}

#[cfg(not(debug_assertions))]
fn smoke_cold_after(_label: &str) -> Option<std::time::Duration> {
    None
}

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

    /// The windows the user was in during this visit: where the keyboard goes
    /// back to when the island folds or its screen closes (page_model::Recent).
    /// Taken as the island takes the keyboard (`remember_foreground`), and kept
    /// current by the watchdog (`note_foreground`).
    static RECENT: Mutex<page_model::Recent> = Mutex::new(page_model::Recent::new());

    /// The last window the user was in that could have the keyboard back,
    /// whatever the island was doing: where it goes when the visit has
    /// nowhere (`Recent::take_back`) — one opened from the taskbar or the
    /// tray, which are never kept. Kept by the watchdog, and as the island
    /// takes the keyboard.
    static LAST: AtomicIsize = AtomicIsize::new(0);

    /// ChatGPT's webview is on screen to the host only once it is built and
    /// hooked up: until then `webview` does not hand it out, so nothing can
    /// navigate it before its navigations are being listened to.
    static CHAT_READY: AtomicBool = AtomicBool::new(false);
    /// A thread is building it now.
    static CHAT_BUILDING: AtomicBool = AtomicBool::new(false);
    /// Shown while it was being built: the card it was last asked over, to
    /// show it there once it is ready. Taken away again if it is hidden first.
    static CHAT_PENDING: Mutex<Option<Card>> = Mutex::new(None);

    /// The site, hidden on about:blank: called once from setup, after the
    /// island's window exists.
    ///
    /// Not ChatGPT. It runs on a WebView2 profile of its own (`chat_data_dir`),
    /// and a profile is a whole set of Edge processes — browser, GPU, network,
    /// storage, crash reporter — that used to start with Notchy for everyone,
    /// though ChatGPT is off until it is switched on in Settings. It is built
    /// the first time it is shown (`build_later`) and closed when it goes
    /// cold (`release`), which takes its processes with it; its profile, and
    /// the sign-in in it, stay on disk for the next time.
    pub fn create(app: &AppHandle) {
        let Some(island) = island::window(app) else {
            log::line("island window missing — no pages");
            return;
        };
        build(app, &island, SITE_LABEL);
        let handle = app.clone();
        // Not the keyboard on focus: the island's is moved by what moves it
        // (take_keyboard, release_keyboard, focus_window), never in answer to
        // a focus event — see `keep_hosting`.
        island.on_window_event(move |event| match event {
            tauri::WindowEvent::Moved(_) => moved(&handle),
            tauri::WindowEvent::ScaleFactorChanged { scale_factor, .. } => {
                replace(&handle, Some(*scale_factor))
            }
            tauri::WindowEvent::ThemeChanged(_) => dark_again(&handle),
            _ => {}
        });
    }

    /// One page's webview, a hidden child of the island's window on
    /// about:blank, with everything `prepare` gives it. Never from inside a
    /// command, which runs on the main thread: WebView2 deadlocks building a
    /// webview there, or comes up blank (lib.rs, setup).
    fn build(app: &AppHandle, island: &tauri::Window, label: &'static str) -> Option<Webview> {
        let blank = Url::parse(BLANK).ok()?;
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
            .initialization_script(MEDIA)
            .initialization_script_for_all_frames(NO_FULLSCREEN)
            // WebView2's NavigationStarting: the top document's only.
            .on_navigation(move |url| allows(&policy, label, url, false))
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
                Some(page)
            }
            Err(err) => {
                log::line(format!("{label} page failed — {err}"));
                None
            }
        }
    }

    /// `show` found no webview for `label`: ChatGPT's is built now, on a
    /// thread of its own, and shown over `card` as soon as it is ready —
    /// over the card it was last asked over, if the island has moved since.
    /// False for a page that is not built late, which then has none at all.
    pub fn build_later(app: &AppHandle, label: &'static str, card: Card) -> bool {
        if label != CHAT_LABEL {
            return false;
        }
        *CHAT_PENDING.lock().unwrap() = Some(card);
        if CHAT_BUILDING.swap(true, Ordering::SeqCst) {
            return true;
        }
        let app = app.clone();
        let started = std::thread::Builder::new().name("webchat-build".into()).spawn(move || {
            let built = island::window(&app).and_then(|island| build(&app, &island, label)).is_some();
            if built {
                log::line("webchat page built");
            }
            let handle = app.clone();
            // Queued behind everything `prepare` asked of the main thread, so
            // by the time this runs the page is listened to.
            let _ = app.run_on_main_thread(move || {
                CHAT_BUILDING.store(false, Ordering::SeqCst);
                CHAT_READY.store(built, Ordering::Release);
                let Some(card) = CHAT_PENDING.lock().unwrap().take() else { return };
                if built {
                    // The ordinary way from here: the island hears of it
                    // through `page-state`, as it does of every change.
                    let _ = show(&handle, label, card);
                } else {
                    // Asked again, it is tried again; not in a loop from here.
                    unavailable(&handle, label);
                }
            });
        });
        if let Err(err) = started {
            CHAT_BUILDING.store(false, Ordering::SeqCst);
            log::line(format!("thread webchat-build failed to start — {err}"));
            return false;
        }
        true
    }

    /// The page was put away before it was ready: it is not to come up.
    pub fn cancel_pending(label: &str) {
        if label == CHAT_LABEL {
            CHAT_PENDING.lock().unwrap().take();
        }
    }

    /// A page gone cold: ChatGPT's webview is closed, and its profile's
    /// processes with it. True when that is what happened, false for a page
    /// that is kept, which goes back to the placeholder instead.
    pub fn release(app: &AppHandle, label: &str) -> bool {
        if label != CHAT_LABEL || !CHAT_READY.swap(false, Ordering::SeqCst) {
            return false;
        }
        platform::page_forget(label);
        if let Some(page) = app.get_webview(label) {
            if let Err(err) = page.close() {
                log::line(format!("{label} could not be closed — {err}"));
            }
        }
        true
    }

    pub fn webview(app: &AppHandle, label: &str) -> Option<Webview> {
        if label == CHAT_LABEL && !CHAT_READY.load(Ordering::Acquire) {
            return None;
        }
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

    /// Whether the page itself has the keyboard: the island's focus is in it
    /// (`platform::page_has_focus`). Only read, never answered with a focus
    /// call (`keep_hosting`).
    pub fn page_has_keyboard(app: &AppHandle, label: &str) -> bool {
        island::window(app).is_some_and(|win| platform::page_has_focus(&win, label))
    }

    /// A page has something to show and is to have the keyboard — ChatGPT,
    /// or the site getting back what moving cost it: the keyboard goes into
    /// it, if the island still has the keyboard to give.
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

    /// ChatGPT is arriving: the island may take focus while it is up — it is
    /// normally a window that never does — and comes forward, as the Mac's
    /// panel is made key (`bring_forward`). Coming back after the island
    /// settled, nothing comes forward — the user may be typing somewhere else
    /// by now — and the keyboard goes into the page only if the island is
    /// still the foreground window.
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

    /// The site is arriving: the island may take focus while it is up, so a
    /// click into the page gives it the keyboard, but nothing comes forward
    /// for it. The Mac's panel is made key for ChatGPT and the chat, and for
    /// nothing else; NotchSiteWeb gets keys once it is clicked.
    pub fn allow_keyboard(app: &AppHandle) {
        if let Some(win) = island::window(app) {
            platform::set_activating(&win, true);
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

    /// The island's window has the keyboard: it goes to ChatGPT when it is on
    /// screen, or to the island's own page. What wry's hook on the window did
    /// for the one webview filling it, before the pages made it a window of
    /// several. Never to the site, which takes it only from a click.
    pub fn keyboard_follows(app: &AppHandle) {
        let target = on_screen(CHAT_LABEL)
            .then(|| app.get_webview(CHAT_LABEL))
            .flatten()
            .or_else(|| island::webview(app));
        if let Some(target) = target {
            let _ = target.set_focus();
        }
    }

    /// The island is about to take the keyboard, or may (a page arriving, a
    /// field of its own): remembers the window the user is in. Nothing to
    /// remember when the island has the keyboard already, because the windows
    /// from before are still the ones to go back to. A page put back after the
    /// island moved remembers too: the windows from before stay behind the one
    /// the user is in now.
    pub fn remember_foreground(app: &AppHandle) {
        let Some(win) = island::window(app) else { return };
        if platform::is_foreground(&win) {
            return;
        }
        note(&win, platform::foreground_window(), true);
    }

    /// The watchdog saw the user go to `window`: the last window at all, and
    /// one of the visit's too while the island has the keyboard or could take
    /// it (`visit`, `foreground_moved`).
    pub fn note_foreground(app: &AppHandle, window: isize, visit: bool) {
        if let Some(win) = island::window(app) {
            note(&win, window, visit);
        }
    }

    /// Kept only if the keyboard could go back to it: never the island, nor a
    /// hidden, minimised or cloaked window, nor the taskbar
    /// (`platform::takes_foreground_back`).
    fn note(win: &tauri::Window, window: isize, visit: bool) {
        if platform::takes_foreground_back(win, window) {
            LAST.store(window, Ordering::Relaxed);
            if visit {
                RECENT.lock().unwrap().note(window);
            }
        }
    }

    /// The island folded or its screen closed: the keyboard goes back at once
    /// to the newest window the user was in that can still have it, or, when
    /// the visit has none, to the last one they were in at all (`LAST`).
    /// That is the Windows half of the Mac's `resignKey`. A hidden child
    /// webview gives nothing back by itself, as a hidden window would, and the
    /// island stays the foreground window until something says otherwise.
    ///
    /// Only while the island still holds the foreground. If it does not, the
    /// user has gone somewhere already, and the keyboard is there. The visit's
    /// windows are forgotten either way, because the visit is over.
    pub fn give_foreground_back(app: &AppHandle) {
        let mut recent = std::mem::take(&mut *RECENT.lock().unwrap());
        let last = LAST.load(Ordering::Relaxed);
        let Some(win) = island::window(app) else { return };
        if !platform::is_foreground(&win) {
            return;
        }
        if let Some(window) = recent.take_back(last, |w| platform::takes_foreground_back(&win, w)) {
            platform::give_foreground(&win, window);
        }
    }

    /// A page put an element in fullscreen, and tauri-runtime-wry has already
    /// asked for the island's window to follow — it does that for every
    /// WebView2 it makes, and the pages' window is the island. Asked back,
    /// after wry's request: `run_on_main_thread` from the main thread runs at
    /// once, ahead of it, so it is sent from another thread and queued behind.
    pub fn leave_fullscreen(app: &AppHandle) {
        let app = app.clone();
        let started = std::thread::Builder::new().name("page-fullscreen".into()).spawn(move || {
            let handle = app.clone();
            let _ = app.run_on_main_thread(move || {
                if let Some(win) = island::window(&handle) {
                    let _ = win.set_fullscreen(false);
                }
            });
        });
        if let Err(err) = started {
            log::line(format!("thread page-fullscreen failed to start — {err}"));
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

    pub fn create(app: &AppHandle) {
        for label in LABELS {
            let Ok(blank) = Url::parse(BLANK) else { return };
            let policy = app.clone();
            let opener = app.clone();
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
                .initialization_script(MEDIA)
                .initialization_script_for_all_frames(NO_FULLSCREEN)
                // WebKitGTK's decide-policy: any frame's, with no telling
                // which (`route_any_frame`).
                .on_navigation(move |url| allows(&policy, label, url, true))
                .on_new_window(move |url, _| {
                    new_window(&opener, label, url);
                    NewWindowResponse::Deny
                })
                .on_download(|_, event| download(event))
                .on_permission_request(|_, kind| permission(kind))
                // Its loads — how each one starts, arrives and ends — are
                // WebKit's own signals (platform::page_hooks), as WebView2's
                // are on Windows.
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
                            hide_all(&hider);
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

    /// Both pages are built at launch here, and kept.
    pub fn build_later(_app: &AppHandle, _label: &'static str, _card: Card) -> bool {
        false
    }

    pub fn cancel_pending(_label: &str) {}

    pub fn release(_app: &AppHandle, _label: &str) -> bool {
        false
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

    /// Never asked here: a page's own window gets the keyboard back from the
    /// window manager, if from anything, and the host has nothing to regain
    /// for it after the island moved.
    pub fn page_has_keyboard(_app: &AppHandle, _label: &str) -> bool {
        false
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

    pub fn allow_keyboard(_app: &AppHandle) {}

    pub fn release_keyboard(_app: &AppHandle) {}

    pub fn keyboard_follows(_app: &AppHandle) {}

    /// The window manager gives the keyboard back when the page's window goes.
    pub fn remember_foreground(_app: &AppHandle) {}

    pub fn note_foreground(_app: &AppHandle, _window: isize, _visit: bool) {}

    pub fn give_foreground_back(_app: &AppHandle) {}

    /// A page's own window, whose WebKit has element fullscreen turned off
    /// (platform::page_settings): nothing of the island's to put back.
    pub fn leave_fullscreen(_app: &AppHandle) {}
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

    /// WebChatController's rule, unchanged: the family stays, any other web
    /// address goes to the browser, nothing else goes anywhere.
    #[test]
    fn chatgpt_keeps_to_its_hosts_and_sends_the_web_to_the_browser() {
        assert_eq!(route(CHAT_LABEL, &url("https://chatgpt.com/c/1"), false), Route::Stay);
        assert_eq!(route(CHAT_LABEL, &url("https://auth.openai.com/x"), false), Route::Stay);
        assert_eq!(route(CHAT_LABEL, &url("https://github.com/"), false), Route::Browser);
        assert_eq!(route(CHAT_LABEL, &url("mailto:a@b.c"), false), Route::Refuse);
        assert_eq!(route(CHAT_LABEL, &url("about:srcdoc"), false), Route::Refuse);
        assert_eq!(route(CHAT_LABEL, &url("blob:https://chatgpt.com/1"), false), Route::Refuse);
        // A link ChatGPT opens in a new window follows the same rule.
        assert_eq!(route_new_window(CHAT_LABEL, &url("https://chatgpt.com/x"), false), Route::Stay);
        assert_eq!(route_new_window(CHAT_LABEL, &url("https://example.com/"), false), Route::Browser);
        assert_eq!(route_new_window(CHAT_LABEL, &url("ms-settings:privacy"), false), Route::Refuse);
    }

    /// NotchSiteWeb's rule: any web page stays in the island, a new window
    /// included, and nothing else does.
    #[test]
    fn the_site_keeps_any_web_page_in_the_island() {
        for stays in [
            "https://box.example.ts.net/x",
            "https://github.com/cauarat",
            "http://192.168.1.10:8123/",
            "http://localhost:3000/",
            "about:srcdoc",
            "blob:https://example.com/1234",
        ] {
            assert_eq!(route(SITE_LABEL, &url(stays), false), Route::Stay, "{stays}");
        }
        for refused in [
            "mailto:a@b.c",
            "tel:+33100000000",
            "file:///etc/passwd",
            "data:text/html,hi",
            "javascript:alert(1)",
            "vscode://file/x",
            "blob:null/1234",
            "blob:file:///x",
        ] {
            assert_eq!(route(SITE_LABEL, &url(refused), false), Route::Refuse, "{refused}");
        }
        // Never the browser: there is nowhere the site would send it.
        assert_eq!(route(SITE_LABEL, &url("https://example.com/"), false), Route::Stay);

        // target=_blank and window.open: a web address loads in place.
        assert_eq!(route_new_window(SITE_LABEL, &url("https://github.com/"), false), Route::Stay);
        assert_eq!(route_new_window(SITE_LABEL, &url("http://example.com/x"), false), Route::Stay);
        assert_eq!(route_new_window(SITE_LABEL, &url("about:blank"), false), Route::Refuse);
        assert_eq!(route_new_window(SITE_LABEL, &url("mailto:a@b.c"), false), Route::Refuse);
        assert_eq!(route_new_window(SITE_LABEL, &url("blob:https://example.com/1"), false), Route::Refuse);
    }

    #[test]
    fn neither_page_ever_goes_onto_one_of_the_apps_own_origins() {
        for label in LABELS {
            for app in ["http://tauri.localhost/index.html", "https://chatgpt.com/"] {
                assert_eq!(route(label, &url(app), true), Route::Refuse, "{label} {app}");
                assert_eq!(route_new_window(label, &url(app), true), Route::Refuse, "{label} {app}");
                assert_eq!(route_any_frame(label, &url(app), true), Route::Refuse, "{label} {app}");
            }
        }
    }

    /// Linux, where the policy hears every frame with no way to tell one from
    /// the page: nothing ever goes to the browser from a navigation, and a
    /// web address loads in either page, as the Mac lets every subframe
    /// through — Cloudflare's challenge, Google's sign-in.
    #[test]
    fn a_navigation_that_may_be_a_frames_never_opens_the_browser() {
        for label in LABELS {
            for web in [
                "https://challenges.cloudflare.com/cdn-cgi/challenge-platform/h/b/turnstile/if/ov2",
                "https://accounts.google.com/gsi/iframe/select?client_id=x",
                "https://chatgpt.com/c/1",
                "https://github.com/",
                "http://example.com/x",
            ] {
                assert_eq!(route_any_frame(label, &url(web), false), Route::Stay, "{label} {web}");
            }
            for refused in [
                "mailto:a@b.c",
                "tel:+33100000000",
                "file:///etc/passwd",
                "data:text/html,hi",
                "javascript:alert(1)",
                "vscode://file/x",
                "ms-settings:privacy",
                "blob:null/1234",
            ] {
                assert_eq!(route_any_frame(label, &url(refused), false), Route::Refuse, "{label} {refused}");
            }
        }
        // Each page keeps what it already kept: the site its about: and web
        // blobs, ChatGPT none of those.
        assert_eq!(route_any_frame(SITE_LABEL, &url("about:srcdoc"), false), Route::Stay);
        assert_eq!(route_any_frame(SITE_LABEL, &url("blob:https://example.com/1"), false), Route::Stay);
        assert_eq!(route_any_frame(CHAT_LABEL, &url("about:srcdoc"), false), Route::Refuse);
        assert_eq!(route_any_frame(CHAT_LABEL, &url("blob:https://chatgpt.com/1"), false), Route::Refuse);
        // Windows is unchanged: its policy hears the top document only, and
        // ChatGPT sends another site to the browser.
        assert_eq!(route(CHAT_LABEL, &url("https://github.com/"), false), Route::Browser);
    }

    #[test]
    fn the_apps_own_origins_are_recognised_however_they_are_spelled() {
        for own in [
            "http://tauri.localhost/index.html",
            "https://tauri.localhost/settings.html",
            "http://ipc.localhost/plugin",
            "http://TAURI.LOCALHOST./",
            "blob:http://tauri.localhost/1234",
            // A blob whose maker cannot be read is refused, not guessed.
            "blob:nonsense",
        ] {
            assert!(is_local_origin(&url(own), None), "{own}");
        }
        for other in [
            "https://example.com/",
            "http://localhost:3000/",
            "http://127.0.0.1:8080/",
            "blob:https://example.com/1234",
            "https://localhost.example.com/",
        ] {
            assert!(!is_local_origin(&url(other), None), "{other}");
        }
        // A dev build's Vite server, and only its exact origin.
        let dev = url("http://localhost:1420");
        assert!(is_local_origin(&url("http://localhost:1420/index.html"), Some(&dev)));
        assert!(!is_local_origin(&url("http://localhost:1421/"), Some(&dev)));
        assert!(!is_local_origin(&url("https://localhost:1420/"), Some(&dev)));
    }

    #[test]
    fn only_mail_and_phone_links_reach_the_system() {
        assert_eq!(system_link("mailto:someone@example.com").unwrap(), "mailto:someone@example.com");
        assert_eq!(system_link("tel:+33100000000").unwrap(), "tel:+33100000000");
        // What goes is the parsed address, never the page's own string.
        assert_eq!(
            system_link("mailto:a@b.c?subject=hello world").unwrap(),
            "mailto:a@b.c?subject=hello%20world"
        );
        // Their paths are opaque, and the parser leaves a page's quotes and
        // spaces in them. Nothing a command line would read as its own gets
        // to one.
        for (link, sent) in [
            (
                "tel:x\" \"C:\\Windows\\System32\\calc.exe",
                "tel:x%22%20%22C:%5CWindows%5CSystem32%5Ccalc.exe",
            ),
            ("mailto:a@b.c\" /q \"x", "mailto:a@b.c%22%20/q%20%22x"),
            ("tel:a^b|c&d", "tel:a%5Eb%7Cc&d"),
            ("tel:+1 555 0100", "tel:+1%20555%200100"),
            ("mailto:<a>{b}`c`@d", "mailto:%3Ca%3E%7Bb%7D%60c%60@d"),
            ("mailto:a@b.c?body=\"x y\"", "mailto:a@b.c?body=%22x%20y%22"),
            // An escape already there stays one; a lone % does not.
            ("tel:%22%20x", "tel:%22%20x"),
            ("tel:100%", "tel:100%25"),
            ("tel:100%4", "tel:100%254"),
        ] {
            assert_eq!(system_link(link).unwrap(), sent, "{link}");
        }
        for never in [
            "vscode://file/x",
            "search-ms:query=invoice&crumb=location:\\\\attacker.example@SSL\\DavWWWRoot",
            "shell:System\\calc.exe",
            "ms-msdt:/id PCWDiagnostic",
            "ms-settings:privacy",
            "C:\\Windows\\System32\\calc.exe",
            "c:/Windows/System32/calc.exe",
            "file:///C:/Windows/system32/calc.exe",
            "https://example.com/",
            "javascript:alert(1)",
            "data:text/html,hi",
            "not a url",
        ] {
            assert!(system_link(never).is_none(), "{never}");
        }
    }

    /// Every address a page hands the system is escaped the same way: a web
    /// address for the browser too, where the parser leaves a pipe, a caret,
    /// braces or a backslash in the query, and a quote in the host.
    #[test]
    fn what_a_page_hands_the_system_is_escaped_for_a_command_line() {
        // An ordinary address goes as it is.
        for plain in [
            "https://example.com/a?b=c&d=e#f",
            "https://github.com/cauarat/coucou/issues/1",
            "http://[::1]:8080/x",
            "https://example.com/caf%C3%A9?q=a+b&r=%2F",
        ] {
            assert_eq!(for_the_system(&url(plain)), plain);
        }
        assert_eq!(
            for_the_system(&url("https://example.com/a|b^c?q={x}`y`\\z#f|g")),
            "https://example.com/a%7Cb%5Ec?q=%7Bx%7D%60y%60%5Cz#f%7Cg"
        );
        assert_eq!(for_the_system(&url("https://x\"y.com/")), "https://x%22y.com/");
        // Whatever comes in, none of a command line's own characters comes out.
        for nasty in [
            "tel:x\" \"C:\\Windows\\System32\\calc.exe",
            "mailto:a@b.c\" /q \"x",
            "tel:a^b|c&d<e>f`g{h}i\\j",
            "mailto:caf\u{e9}@example.com?body=\u{1F600}\t\"",
            "https://example.com/?a=\"b c\"&d=|^`{}\\<>",
        ] {
            let sent = for_the_system(&url(nasty));
            assert!(
                sent.bytes().all(|b| b.is_ascii_graphic()
                    && !b"\"\\^|<>`{}".contains(&b)),
                "{nasty} -> {sent}"
            );
        }
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

    /// Coucou's own pages are never meant to be framed by anything: a page in
    /// the island could otherwise run one, with every app command, inside its
    /// own webview. Said by whatever serves them. A bundled build's come from
    /// Tauri's own protocol, which sends `csp` with each one (and `devCsp`,
    /// for a dev build Tauri serves itself). A desktop `tauri dev` build's
    /// come straight from Vite, with no header of Tauri's, so its dev server
    /// sends the same itself (vite.config.ts).
    #[test]
    fn no_page_of_coucous_can_be_framed() {
        let conf: serde_json::Value = serde_json::from_str(include_str!("../tauri.conf.json")).unwrap();
        for key in ["csp", "devCsp"] {
            let csp = conf["app"]["security"][key].as_str().unwrap();
            assert!(csp.contains("frame-ancestors 'self'"), "{key}: {csp}");
        }
        let vite = include_str!("../../vite.config.ts");
        let start = vite.find("server: {").expect("vite.config.ts has a server block");
        let mut depth = 0;
        let end = vite[start..]
            .char_indices()
            .find_map(|(i, c)| {
                match c {
                    '{' => depth += 1,
                    '}' => {
                        depth -= 1;
                        if depth == 0 {
                            return Some(start + i);
                        }
                    }
                    _ => {}
                }
                None
            })
            .expect("the server block ends");
        let server = &vite[start..end];
        assert!(
            server.contains(r#"headers: { "Content-Security-Policy": "frame-ancestors 'self'" }"#),
            "the dev server sends no frame-ancestors: {server}"
        );
    }
}
