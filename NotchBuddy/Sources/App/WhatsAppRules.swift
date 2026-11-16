import Foundation

/// What the WhatsApp Web bridge says, and what the inbox makes of it.
///
/// Pure Foundation, so `scripts/test-whatsapp-rules.sh` can compile it on its
/// own. The bridge itself is `shared/whatsapp-bridge.js`; its Rust twin is in
/// `windows/src-tauri/src/message_proto.rs`, and the two must agree.
enum WhatsAppRules {

    /// Where the page lives.
    static let webURL = URL(string: "https://web.whatsapp.com/")!

    /// What the injected script reports.
    enum Event: Equatable {
        case message(Incoming)
        case state(PageState)
        case sent(requestID: String?)
        case sendFailed(requestID: String?, reason: String)
    }

    /// One notification the page tried to show.
    struct Incoming: Equatable {
        /// The bridge's own handle for the notification, which is what opens
        /// that conversation again when a reply goes out.
        let key: String
        /// The conversation's name as WhatsApp shows it: a contact, a number,
        /// or a group.
        let chat: String
        let body: String
        let timestamp: Date
    }

    enum PageState: String, Equatable {
        /// Asking for the QR code: nobody is signed in.
        case qr
        /// The chat list is on screen.
        case connected
        /// Neither yet.
        case loading
    }

    /// Reads one message from the bridge. Anything that is not one of ours,
    /// or is missing what it needs, is nil rather than a guess.
    static func event(from body: Any?) -> Event? {
        guard let dict = body as? [String: Any],
              let type = dict["type"] as? String else { return nil }
        switch type {
        case "message":
            guard let key = nonEmpty(dict["key"] as? String),
                  let chat = nonEmpty(dict["chat"] as? String) else { return nil }
            let millis = (dict["ts"] as? NSNumber)?.doubleValue
            return .message(Incoming(
                key: key,
                chat: chat,
                body: (dict["body"] as? String) ?? "",
                timestamp: millis.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            ))
        case "state":
            guard let raw = dict["state"] as? String,
                  let state = PageState(rawValue: raw) else { return nil }
            return .state(state)
        case "sent":
            return .sent(requestID: dict["requestId"] as? String)
        case "sendFailed":
            return .sendFailed(requestID: dict["requestId"] as? String,
                               reason: nonEmpty(dict["reason"] as? String) ?? "unknown")
        default:
            return nil
        }
    }

    /// The name on the card. A name WhatsApp prefixes with `~` is one that is
    /// not in your contacts: the tilde is WhatsApp's note to itself, noise on
    /// a card.
    static func displayName(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix("~") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// The words on the card, or nil when the notification carried none — a
    /// photo or sticker sent without a caption.
    static func body(_ raw: String) -> String? {
        nonEmpty(raw)
    }

    /// A notification WhatsApp draws when several arrive at once — titled
    /// "WhatsApp" and speaking for no one conversation. Worth showing, not
    /// worth offering a reply to: there is nobody to address it to.
    static func isSummary(chat: String) -> Bool {
        chat.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("WhatsApp") == .orderedSame
    }

    /// Inbox ids carry the bridge's key, which is how a reply finds the
    /// notification it answers without a second table.
    static let idPrefix = "whatsapp:"

    static func messageID(key: String) -> String { idPrefix + key }

    static func key(fromMessageID id: String) -> String? {
        guard id.hasPrefix(idPrefix) else { return nil }
        return nonEmpty(String(id.dropFirst(idPrefix.count)))
    }

    // MARK: - Where the page may go

    /// Hosts the hidden page may load in its main frame. Everything else is
    /// the browser's job: a link in a message opens there, not in a web view
    /// nobody can see.
    static let allowedHosts: Set<String> = [
        "web.whatsapp.com",
        "whatsapp.com",
        "whatsapp.net",
    ]

    /// True for an allowed host or a subdomain of one, anchored on a dot so a
    /// lookalike such as `whatsapp.com.evil.net` does not pass.
    static func keepsInWebView(_ url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "about" || scheme == "blob" || scheme == "data" { return true }
        guard scheme == "https", let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return allowedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
