// The two pages Coucou can put on screen: the site, and ChatGPT.
//
// On the Mac both of these are `WKWebView`s drawn inside the island, which
// stretches to hold them. A second WebView2 inside the island's window is not
// something Tauri does without its unstable multiwebview feature, so here each
// page is a window of its own — the same move the clipboard already made on
// this platform. Borderless, transparent and always on top, and anchored to the
// island every time it is shown: the island's width, lined up with its card and
// flush against it, so it reads as part of the island rather than as a browser
// that opened. It used to be `.center()`, which put it in the middle of the
// screen with no relationship to the island at all.
//
// Both are created hidden at launch for the reason the settings and clipboard
// windows are: a WebView2 window built after the island's webview silently
// comes up blank.

use std::sync::atomic::{AtomicBool, Ordering};

use tauri::webview::WebviewBuilder;
use tauri::{
    AppHandle, LogicalPosition, LogicalSize, Manager, PhysicalPosition, PhysicalSize, Url,
    WebviewUrl, WebviewWindowBuilder,
};

use crate::island;
use crate::log;
use crate::platform;

pub const SITE_LABEL: &str = "site";
pub const CHAT_LABEL: &str = "webchat";

/// chatgpt.com pulls assets and sign-in flows from a handful of OpenAI domains,
/// so the allowlist covers the family rather than the single host. Everything
/// else is opened in the user's real browser instead: a 640 px panel under the
/// island is the worst possible place to land on an arbitrary web page.
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

/// Edge's own user agent string. WebView2 identifies itself as an embedded view
/// by default, which is what the sign-in flow turns away.
const CHAT_USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 \
     (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36 Edg/140.0.0.0";

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

/// True when a navigation to `url` should stay inside the window. Non-web
/// schemes never stay: they are not ours to render.
fn keeps_in_window(url: &Url, allowed: &[&str]) -> bool {
    if url.scheme() != "https" && url.scheme() != "http" {
        return false;
    }
    host_allowed(url.host_str().unwrap_or(""), allowed)
}

/// The site the globe opens, and the hosts it may stay on.
fn site_url(app: &AppHandle) -> String {
    app.try_state::<crate::Shared>()
        .map(|shared| shared.settings.lock().unwrap().site_url.clone())
        .unwrap_or_default()
}

/// Everything the site is allowed to reach in its own window: the host it was
/// pointed at, and nothing else. A link anywhere else opens in the browser.
fn site_hosts(app: &AppHandle) -> Vec<String> {
    Url::parse(&site_url(app))
        .ok()
        .and_then(|u| u.host_str().map(|h| h.to_string()))
        .into_iter()
        .collect()
}

fn build(app: &AppHandle, label: &str, url: WebviewUrl, title: &str, agent: Option<&str>) {
    let handle = app.clone();
    let for_policy = label.to_string();
    let mut builder = WebviewWindowBuilder::new(app, label, url)
        // The island, the settings window and the clipboard all ask for these.
        // The flags are fixed by whichever webview is created first, so a window
        // that leaves them out comes up blank with no error anywhere — and these
        // two are built in the same setup, before the island.
        .additional_browser_args(crate::BROWSER_ARGS)
        .title(title)
        .inner_size(760.0, 620.0)
        .min_inner_size(420.0, 320.0)
        .resizable(true)
        .decorations(false)
        .transparent(true)
        .always_on_top(true)
        .skip_taskbar(true)
        .visible(false)
        // What it holds until `anchor` places it. `toggle` will not show a page
        // that could not be anchored, so this is never what reaches the screen
        // — it used to be, every time anchoring failed.
        .center()
        .on_navigation(move |target| {
            let allowed: Vec<String> = if for_policy == CHAT_LABEL {
                CHAT_HOSTS.iter().map(|h| (*h).to_string()).collect()
            } else {
                site_hosts(&handle)
            };
            let refs: Vec<&str> = allowed.iter().map(|s| s.as_str()).collect();
            // The first load is the page itself, and a page with nowhere to go
            // would be a blank window; an empty allowlist means the setting is
            // empty, which the island reports rather than this.
            if refs.is_empty() || keeps_in_window(target, &refs) {
                return true;
            }
            platform::open_url(target.as_str());
            false
        });
    if let Some(agent) = agent {
        builder = builder.user_agent(agent);
    }
    match builder.build() {
        Ok(win) => {
            // Closing must only hide it, or the page could never be reopened —
            // and rebuilding a WebView2 window after launch comes up blank.
            let hidden = win.clone();
            win.on_window_event(move |event| {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    api.prevent_close();
                    let _ = hidden.hide();
                }
            });
        }
        Err(err) => log::line(format!("{label} window failed: {err}")),
    }
}

/// ChatGPT drawn inside the island's own window rather than beside it.
///
/// The anchored page window lands flush against the card and still reads as a
/// browser that opened, because it is the bare site: no header, no island
/// background, square corners — where the Mac wraps its `WKWebView` in a
/// rounded card under a 34 pt header (`WebChatHostView.swift`). A child webview
/// is the only way to put a second WebView2 in one window, and Tauri keeps it
/// behind its `unstable` feature.
///
/// What a child webview cannot do, and the reason the chrome looks the way it
/// does: it is a native control laid over the window, so the island's own HTML
/// neither draws on top of it nor clips it. The header is an inset rather than
/// an overlay, and the page keeps square corners where the Mac rounds them.
pub const CHAT_INSIDE_LABEL: &str = "webchat-inside";

/// The island's own header, which the chat must not cover: 34 px of tabs (the
/// `#header` rule, and the Mac's `frame(height: 34)`) plus the 8 above them.
const INSIDE_HEADER: f64 = 42.0;

/// What the card keeps around its content, left, right and below.
const INSIDE_INSET: f64 = 8.0;

/// Whether it is on screen. `Webview` has no `is_visible`, unlike a window, so
/// the one caller that needs the answer has to remember it.
static INSIDE_UP: AtomicBool = AtomicBool::new(false);

/// Builds it hidden, during setup, and nowhere else.
///
/// `add_child` deadlocks on Windows when it is called from a synchronous
/// command or an event handler — which is exactly where the chat tab reaches
/// for it — so the webview has to exist before anyone asks. Tauri says so in
/// its own docs, pointing at wry#583. The page windows are already built here
/// for a neighbouring reason, and this joins them.
///
/// Worth saying out loud, because it is the one thing that would be bad and is
/// not obvious: this webview lives inside the `island` window, which the
/// capability file does name. It still reaches none of Coucou's commands.
/// A capability applies to remote origins only through its `remote` field, and
/// `capabilities/default.json` has none — so chatgpt.com gets the default, which
/// is nothing. Adding a `remote` entry there would hand an OpenAI page the same
/// commands the island has; do not.
pub fn create_inside(app: &AppHandle) {
    let Some(window) = app.get_window(island::WINDOW_LABEL) else {
        log::line("no island window to build the chat inside");
        return;
    };
    let Ok(url) = Url::parse(CHAT_URL) else {
        log::line(format!("the chat is not going inside: {CHAT_URL:?} is not a URL"));
        return;
    };
    let builder = WebviewBuilder::new(CHAT_INSIDE_LABEL, WebviewUrl::External(url))
        // The same flags every other webview here asks for: they are fixed by
        // whichever is created first, and one that leaves them out comes up
        // blank with no error anywhere.
        .additional_browser_args(crate::BROWSER_ARGS)
        .user_agent(CHAT_USER_AGENT)
        .on_navigation(|target| {
            if keeps_in_window(target, &CHAT_HOSTS) {
                return true;
            }
            platform::open_url(target.as_str());
            false
        });
    // A pixel at the origin, because the card's rect is not known yet and this
    // is hidden on the next line. `inside_toggle` gives it its real place.
    match window.add_child(
        builder,
        LogicalPosition::new(0.0, 0.0),
        LogicalSize::new(1.0, 1.0),
    ) {
        Ok(view) => {
            let _ = view.hide();
            INSIDE_UP.store(false, Ordering::Relaxed);
        }
        Err(err) => log::line(format!("the chat could not go inside the island: {err}")),
    }
}

/// Puts the chat over the island's card. Returns whether it is up afterwards,
/// which is what tells the island to hold itself open — the same contract
/// `toggle` has for a page window.
///
/// A show rather than a toggle, unlike the page windows: the chat is a view of
/// the island now, and which view is showing is the front end's to know. Two
/// places deciding that is how they end up disagreeing.
pub fn inside_show(app: &AppHandle) -> bool {
    let Some(view) = app.get_webview(CHAT_INSIDE_LABEL) else {
        log::line("the chat inside the island was never built");
        return false;
    };
    let Some(shared) = app.try_state::<crate::Shared>() else { return false };
    let card = *shared.gate.rect.lock().unwrap();
    if !place_inside(&view, card) {
        log::line("no island card to draw the chat in");
        return false;
    }
    let _ = view.show();
    let _ = view.set_focus();
    INSIDE_UP.store(true, Ordering::Relaxed);
    true
}

/// Lays it over the card, inside the header and the card's own margins.
///
/// Generic over the runtime rather than naming `Wry`: the concrete type is
/// handed in by the caller either way, and this never has to care.
fn place_inside<R: tauri::Runtime>(view: &tauri::Webview<R>, card: island::IslandRect) -> bool {
    // The same guard `page_placement` opens with: no card means the island is
    // folded away, and there is nothing to draw inside.
    if card.w < 1.0 || card.h < 1.0 {
        return false;
    }
    let w = (card.w - INSIDE_INSET * 2.0).max(1.0);
    let h = (card.h - INSIDE_HEADER - INSIDE_INSET).max(1.0);
    let _ = view.set_position(LogicalPosition::new(card.x + INSIDE_INSET, card.y + INSIDE_HEADER));
    let _ = view.set_size(LogicalSize::new(w, h));
    true
}

/// Follows the island, for every rect the front end pushes while the chat is up.
///
/// Without this the chat would be measured once, at the moment the tab is
/// clicked — which is before the island has finished opening to the height that
/// holds it, so it would be sized to the 160 px card it was leaving and stay
/// that size. The island animates; the chat has to animate with it.
pub fn inside_follow(app: &AppHandle, card: island::IslandRect) {
    if !INSIDE_UP.load(Ordering::Relaxed) {
        return;
    }
    if let Some(view) = app.get_webview(CHAT_INSIDE_LABEL) {
        place_inside(&view, card);
    }
}

/// Takes it away. Called wherever the pages are put away, for the same reason:
/// a chat drawn in a card that is no longer there would hang in mid-air.
pub fn inside_hide(app: &AppHandle) {
    if let Some(view) = app.get_webview(CHAT_INSIDE_LABEL) {
        let _ = view.hide();
    }
    INSIDE_UP.store(false, Ordering::Relaxed);
}

/// Both pages, created hidden at launch.
pub fn create(app: &AppHandle) {
    let site = site_url(app);
    if let Ok(parsed) = Url::parse(&site) {
        build(app, SITE_LABEL, WebviewUrl::External(parsed), "Site", None);
    } else {
        log::line(format!("site window not created: {site:?} is not a URL"));
    }
    if let Ok(parsed) = Url::parse(CHAT_URL) {
        build(
            app,
            CHAT_LABEL,
            WebviewUrl::External(parsed),
            "ChatGPT",
            Some(CHAT_USER_AGENT),
        );
    }
}

/// Puts a page where it reads as part of the island. Says whether it landed.
///
/// Called before every show, and again whenever the island moves — a display
/// change, a different screen or corner in Settings. There is nothing it can do
/// when the island has no card to hang off, or no room beside it for one.
///
/// A window already up then stays where it was, which is better than jumping
/// somewhere arbitrary — that is what `reanchor` wants. A window that has never
/// been shown has no "where it was": it is still at the builder's `.center()`.
/// So the answer is returned rather than swallowed, and `toggle` acts on it.
pub fn anchor(app: &AppHandle, label: &str) -> bool {
    let Some(win) = app.get_webview_window(label) else { return false };
    let Some(shared) = app.try_state::<crate::Shared>() else { return false };
    let (pref, position) = {
        let settings = shared.settings.lock().unwrap();
        (settings.screen.clone(), settings.position.clone())
    };
    let card = *shared.gate.rect.lock().unwrap();
    let Some((x, y, w, h)) = island::page_placement(app, &pref, &position, card) else {
        return false;
    };

    let _ = win.set_size(PhysicalSize::new(w, h));
    let _ = win.set_position(PhysicalPosition::new(x, y));
    // Moving across displays can rescale the window: re-assert the physical
    // size, exactly as `apply_geometry` does for the island itself.
    let _ = win.set_size(PhysicalSize::new(w, h));
    let _ = win.set_always_on_top(true);
    true
}

/// Follows the island. For anything that moves it: a display change, or the
/// screen or corner preference.
pub fn reanchor(app: &AppHandle) {
    for label in [SITE_LABEL, CHAT_LABEL] {
        let up = app
            .get_webview_window(label)
            .and_then(|win| win.is_visible().ok())
            .unwrap_or(false);
        if up {
            anchor(app, label);
        }
    }
}

/// Shows the page, or puts it away if it is already up. Returns whether it is
/// up afterwards, which is what tells the island whether to hold itself open.
pub fn toggle(app: &AppHandle, label: &str) -> bool {
    let Some(win) = app.get_webview_window(label) else {
        log::line(format!("{label} window missing"));
        return false;
    };
    if win.is_visible().unwrap_or(false) {
        let _ = win.hide();
        return false;
    }
    // Before the show, not after: a window that appears and then moves is a
    // window that was in the wrong place first.
    //
    // And only if it landed. A page that could not be placed used to be shown
    // regardless, which on the first use of a session meant the builder's
    // `.center()`: a 760×620 window floating in the middle of the display with
    // no relationship to the island at all — exactly the "it opened in a
    // separate window" this is supposed to prevent. Nothing, and a line saying
    // why, beats that.
    if !anchor(app, label) {
        log::line(format!("{label} has nowhere to hang off — not showing it"));
        return false;
    }
    let _ = win.show();
    let _ = win.set_focus();
    true
}

pub fn hide_all(app: &AppHandle) {
    for label in [SITE_LABEL, CHAT_LABEL] {
        if let Some(win) = app.get_webview_window(label) {
            let _ = win.hide();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn allowed(url: &str, hosts: &[&str]) -> bool {
        keeps_in_window(&Url::parse(url).unwrap(), hosts)
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

    #[test]
    fn the_site_keeps_to_the_host_it_was_pointed_at() {
        assert!(allowed("https://box.example.ts.net/x", &["box.example.ts.net"]));
        assert!(!allowed("https://example.com/", &["box.example.ts.net"]));
        // Nothing is allowed by an empty host, however it is spelled.
        assert!(!host_allowed("", &["box.example.ts.net"]));
    }
}
