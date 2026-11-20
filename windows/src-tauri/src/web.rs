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
// comes up blank. They are created on `about:blank`, though, and only fetch
// their page the first time it is opened — as on the Mac, where nothing loads
// chatgpt.com or the site until the user asks for it. Building them on the real
// URLs made every install contact both services at every launch, whether or
// not anyone ever used them.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use tauri::{AppHandle, Manager, PhysicalPosition, PhysicalSize, Url, WebviewUrl, WebviewWindowBuilder};

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

/// What both windows hold until their page is first opened.
const BLANK_URL: &str = "about:blank";

/// The page each window has been pointed at, by label. Empty until the first
/// open, so launch fetches nothing; compared on every open, so a site changed in
/// Settings is the one the next open shows rather than the one from launch.
fn loaded() -> &'static Mutex<HashMap<String, String>> {
    static LOADED: OnceLock<Mutex<HashMap<String, String>>> = OnceLock::new();
    LOADED.get_or_init(|| Mutex::new(HashMap::new()))
}

/// The page a window should show when it is opened, or nothing when it has
/// none: an empty or non-web site setting. Pure, so the rule is testable.
fn page_url(label: &str, site: &str) -> Option<Url> {
    let raw = if label == CHAT_LABEL { CHAT_URL } else { site.trim() };
    let url = Url::parse(raw).ok()?;
    matches!(url.scheme(), "https" | "http").then_some(url)
}

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
            // The placeholder every window starts on. Without this it would be
            // handed to the browser like any other foreign URL.
            if target.as_str() == BLANK_URL {
                return true;
            }
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

/// Both pages, created hidden and blank at launch. Nothing is fetched until a
/// page is opened: see `open_page`.
pub fn create(app: &AppHandle) {
    let Ok(blank) = Url::parse(BLANK_URL) else { return };
    build(app, SITE_LABEL, WebviewUrl::External(blank.clone()), "Site", None);
    build(app, CHAT_LABEL, WebviewUrl::External(blank), "ChatGPT", Some(CHAT_USER_AGENT));
}

/// Points a window at its page if it is not already there. Says whether there
/// is a page to show at all.
fn open_page(app: &AppHandle, win: &tauri::WebviewWindow, label: &str) -> bool {
    let Some(url) = page_url(label, &site_url(app)) else {
        log::line(format!("{label} has no page to open"));
        return false;
    };
    let mut loaded = loaded().lock().unwrap();
    if loaded.get(label).map(String::as_str) != Some(url.as_str()) {
        if let Err(err) = win.navigate(url.clone()) {
            log::line(format!("{label} could not load its page: {err}"));
            return false;
        }
        loaded.insert(label.to_string(), url.to_string());
    }
    true
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
    if !open_page(app, &win, label) {
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
    fn nothing_is_fetched_until_a_page_is_opened() {
        // Both windows are built on the placeholder; the policy lets it load.
        assert_eq!(Url::parse(BLANK_URL).unwrap().as_str(), "about:blank");
        assert!(loaded().lock().unwrap().is_empty());
    }

    #[test]
    fn each_window_opens_its_own_page_or_none() {
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
    fn the_site_keeps_to_the_host_it_was_pointed_at() {
        assert!(allowed("https://box.example.ts.net/x", &["box.example.ts.net"]));
        assert!(!allowed("https://example.com/", &["box.example.ts.net"]));
        // Nothing is allowed by an empty host, however it is spelled.
        assert!(!host_allowed("", &["box.example.ts.net"]));
    }
}
