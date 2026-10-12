import Foundation

/// Hosts the island web view is allowed to show in its main frame.
///
/// chatgpt.com pulls assets and sign-in flows from a handful of OpenAI domains, so the
/// allowlist covers the family rather than the single host. Everything else is opened in
/// the user's real browser instead: a 620pt-wide panel glued under the notch is the worst
/// possible place to land on an arbitrary web page.
let webChatAllowedHosts: Set<String> = [
    "chatgpt.com",
    "chat.openai.com",
    "openai.com",
    "auth.openai.com",
    "auth0.openai.com",
    "oaistatic.com",
    "oaiusercontent.com",
    "sora.com",
]

/// True when `host` is an allowed host or a subdomain of one.
///
/// The suffix match is anchored on a dot so a lookalike cannot slip through: "chatgpt.com"
/// matches and "api.chatgpt.com" matches, but "notchatgpt.com" and "chatgpt.com.evil.net"
/// do not.
func isChatGPTHost(_ host: String?) -> Bool {
    guard let host, !host.isEmpty else { return false }
    let h = host.lowercased()
    for allowed in webChatAllowedHosts {
        if h == allowed || h.hasSuffix("." + allowed) { return true }
    }
    return false
}

/// True when a main-frame navigation to `url` should stay inside the island.
/// Non-web schemes never stay: they are not ours to render.
func webChatKeepsInIsland(_ url: URL?) -> Bool {
    guard let url, let scheme = url.scheme?.lowercased(),
          scheme == "https" || scheme == "http" else { return false }
    return isChatGPTHost(url.host)
}
