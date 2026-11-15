//
//  AtoRules.swift
//  Notchy
//
//  What Ato sends, and which of it deserves the notch. Pure, so
//  scripts/test-ato-rules.sh can hold it to frames captured off the real hub.
//

import Foundation

// MARK: - Addresses

/// Where Ato lives. Fixed rather than typed in: Ato is one Actuar product,
/// not a panel each customer hosts, and these are the hosts the
/// novo.actuar.com console itself is built against.
enum AtoEndpoints {
    /// Sign-in and token refresh.
    static let userService = URL(string: "https://userservice-api.prd.o.actuar.cloud")!
    /// The inbox: agents, conversations, messages, and the `SupportHub`.
    static let supportService = URL(string: "https://supportservice-api.prd.o.actuar.cloud")!
    /// The console people actually open.
    static let app = URL(string: "https://novo.actuar.com")!
    /// The page the sign-in requests come from, for `Origin`/`Referer`.
    static let accounts = URL(string: "https://accounts.actuar.com")!

    /// `wss://…/SupportHub?access_token=…` — the console's own route, with the
    /// token in the query because a WebSocket cannot carry headers.
    static func hubURL(token: String) -> URL? {
        guard var components = URLComponents(url: supportService, resolvingAgainstBaseURL: false)
        else { return nil }
        components.scheme = "wss"
        components.path = "/SupportHub"
        components.queryItems = [URLQueryItem(name: "access_token", value: token)]
        return components.url
    }

    /// The console, opened on one conversation.
    static func conversationLink(_ conversationID: String?) -> URL {
        var components = URLComponents(url: app, resolvingAgainstBaseURL: false)!
        components.path = "/support/workspace"
        if let conversationID, !conversationID.isEmpty {
            components.queryItems = [URLQueryItem(name: "conversation", value: conversationID)]
        }
        return components.url!
    }
}

// MARK: - Wire format

/// Ato's enums arrive as numbers on the hub. Values read off the console's
/// own definitions (`It`, `St` in its bundle), not guessed.
enum AtoSenderType: Int {
    case customer = 1, agent = 2, system = 3, ai = 4
}

enum AtoStatusType: Int {
    case open = 1, waitingCustomer = 2, waitingAgent = 3, closed = 4, archived = 5
}

/// The `onConversationUpdated` payload — the event that carries a customer's
/// message to everyone in the workspace.
///
/// Not `onMessagePosted`: that one only reaches connections that have joined
/// the conversation, which is what the console does when you open one. A
/// listener that has joined nothing sees a customer write only as this
/// update, with the text in `lastMessagePreview`. That is also the event the
/// console itself rings its bell on.
struct AtoConversationUpdate: Decodable, Equatable {
    let conversationId: String
    let number: Int?
    let workspaceId: String?
    let contactId: String?
    let channelType: Int?
    let statusType: Int?
    /// Nil while nobody has picked the conversation up.
    let assignedToAgentId: String?
    let queueId: String?
    let lastMessageOnUtc: String?
    let lastMessagePreview: String?
    let lastMessageSenderType: Int?
    let lastMessageSenderId: String?
}

/// One row of `GET /Agents/me`: who you are in one workspace.
struct AtoMembership: Decodable, Equatable {
    let AgentId: String
    let WorkspaceId: String
    let WorkspaceName: String?
    let DisplayName: String?
    let QueueIds: [String]?
}

/// What `/Auth/Login` and `/Auth/Refresh` answer with.
struct AtoAuthorization: Decodable {
    let Token: String?
    let TokenId: String?
    let PersonId: String?
    let TenantId: String?
    let IsValid: Bool?
}

// MARK: - Rules

enum AtoRules {
    /// Whether an update is a customer's new message that belongs to you.
    ///
    /// The hub streams the whole workspace — every conversation, every agent,
    /// and the bot talking to customers before anyone is assigned. Notifying
    /// on all of it would open the notch for the whole company's WhatsApp. So,
    /// the same rule the console uses for its own alerts and the same one
    /// Notchy already applies to ClickMassa:
    ///
    /// - the customer spoke last (not you, a colleague, the bot or the AI);
    /// - the conversation is still open;
    /// - and it is yours: assigned to you, or unassigned and waiting in one of
    ///   your queues.
    static func shouldNotify(_ update: AtoConversationUpdate, memberships: [AtoMembership]) -> Bool {
        guard update.lastMessageSenderType == AtoSenderType.customer.rawValue else { return false }

        if let status = update.statusType.flatMap(AtoStatusType.init(rawValue:)),
           status == .closed || status == .archived {
            return false
        }

        // Without knowing who we are there is no "mine", and notifying on
        // everything would be worse than notifying on nothing.
        guard let workspace = update.workspaceId?.lowercased(),
              let membership = memberships.first(where: { $0.WorkspaceId.lowercased() == workspace })
        else { return false }

        if let assigned = update.assignedToAgentId {
            return assigned.lowercased() == membership.AgentId.lowercased()
        }

        guard let queue = update.queueId?.lowercased() else { return false }
        return (membership.QueueIds ?? []).contains { $0.lowercased() == queue }
    }

    /// One id per customer message, stable across the repeats.
    ///
    /// The hub sends an update for every change to a conversation — the bot
    /// answering, a queue being set — and several can carry the same last
    /// message. The time of that message is what tells a new one from a
    /// repeat, so it is half of the id ``MessageInbox`` deduplicates on.
    static func messageID(_ update: AtoConversationUpdate) -> String {
        "ato:\(update.conversationId):\(update.lastMessageOnUtc ?? "")"
    }

    /// The card's text, or nil when there is none — a file carries no
    /// preview, and the caller says so in words rather than drawing a blank
    /// card.
    static func body(_ update: AtoConversationUpdate) -> String? {
        let text = (update.lastMessagePreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// WhatsApp push names arrive as Ato stores them: `~cato`. The tilde is
    /// WhatsApp saying "not in your contacts", which is noise on a card.
    static func displayName(_ raw: String?) -> String? {
        guard var name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }
        while name.hasPrefix("~") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// `2026-11-15T19:33:53Z` and `2026-11-15T19:33:54.8855382Z` both occur —
    /// .NET writes up to seven fractional digits, which `ISO8601DateFormatter`
    /// will not read. Trimmed to milliseconds first.
    static func date(_ text: String?) -> Date? {
        guard var text, !text.isEmpty else { return nil }
        if let dot = text.firstIndex(of: "."),
           let zone = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            let fraction = text[text.index(after: dot)..<zone].prefix(3)
            text = String(text[..<dot]) + "." + fraction + String(text[zone...])
        }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = precise.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }

    /// When a bearer token stops working, from its own `exp` claim.
    static func expiry(ofJWT token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = claims["exp"] as? Double
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
