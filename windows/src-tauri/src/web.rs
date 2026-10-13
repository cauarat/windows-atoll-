// The two pages Coucou can put on screen: the site, and ChatGPT.
//
// On the Mac both of these are `WKWebView`s drawn inside the island, which
// stretches to hold them. A second WebView2 inside the island's window is not
// something Tauri does without its unstable multiwebview feature, so here each
// page is a window of its own — the same move the clipboard already made on
// this platform. Borderless, transparent and always on top, so it reads as part
// of the island rather than as a browser that opened.
//
// Both are created hidden at launch for the reason the settings and clipboard
// windows are: a WebView2 window built after the island's webview silently
// comes up blank.

use tauri::{AppHandle, Manager, Url, WebviewUrl, WebviewWindowBuilder};

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

/// Shows the page, or puts it away if it is already up.
pub fn toggle(app: &AppHandle, label: &str) {
    let Some(win) = app.get_webview_window(label) else {
        log::line(format!("{label} window missing"));
        return;
    };
    if win.is_visible().unwrap_or(false) {
        let _ = win.hide();
        return;
    }
    let _ = win.show();
    let _ = win.set_focus();
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
