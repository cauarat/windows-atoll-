/*
 * Notchy
 *
 * The message model and inbox behind the Mattermost and ClickMassa pills.
 * Adapted from Atoll (DynamicIsland), GPL v3, whose AppNotification and
 * NotificationBridgeManager this replaces in much smaller form. See NOTICE.
 *
 * Copyright (C) 2024-2026 Atoll Contributors
 * Copyright (C) 2026 Notchy Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

// MARK: - Source


// MARK: - Message

struct InboxMessage: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case directMessage
        case mention
        case channel
        case generic
    }

    let id: String
    let source: MessageSource
    let kind: Kind
    let sender: String
    /// Nil for a direct message, where the sender is the conversation.
    let channel: String?
    /// What a reply is addressed to — a Mattermost channel, a ClickMassa ticket.
    let conversationID: String?
    let body: String
    let timestamp: Date
    let link: URL?
    var isRead: Bool = false

    /// How long ago this arrived.
    ///
    /// Anything inside a minute reads as "now", on either side of it: a server
    /// whose clock runs milliseconds ahead of the Mac stamps a message in the
    /// future, and a formatter reports that faithfully as "in 0 seconds".
    func timeAgo(relativeTo reference: Date = Date()) -> String {
        let elapsed = reference.timeIntervalSince(timestamp)
        guard elapsed >= 60 else { return "now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: reference)
    }
}

// MARK: - Inbox

/// What has arrived, from either source.
///
/// Deliberately much smaller than Atoll's NotificationBridgeManager: no disk
/// persistence, no popup styles, no freshness window. Notchy's island already
/// owns how things are presented, so this only has to hold the messages and
/// keep the pills honest.
@MainActor
final class MessageInbox: ObservableObject {
    static let shared = MessageInbox()

    /// Enough to scroll, not enough to grow without bound.
    private static let maxMessages = 50

    @Published private(set) var messages: [InboxMessage] = []
    @Published private(set) var unreadCount = 0

    /// The newest from each source, kept whether or not it has been read.
    ///
    /// `active` is `unread.first`, so the card empties the moment a message is
    /// answered. Home needs the opposite: the last thing each source said, still
    /// there after the notification has folded away. That is what this is for.
    @Published private(set) var lastBySource: [MessageSource: InboxMessage] = [:]

    /// Who spoke most recently — what "take turns" resolves to.
    @Published private(set) var lastSource: MessageSource?

    private init() {}

    // MARK: - Ingest

    /// Accepts a message. Safe to call with one already held: duplicates are
    /// dropped by id, so a reconnect that replays history cannot re-announce it.
    func ingest(_ message: InboxMessage) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }

        messages.insert(message, at: 0)
        if messages.count > Self.maxMessages {
            messages.removeLast(messages.count - Self.maxMessages)
        }
        // Set before the cap trims anything: these two outlive the history.
        lastBySource[message.source] = message
        lastSource = message.source
        recount()
        syncPill(for: message.source)

        NotificationCenter.default.post(name: .inboxMessageArrived, object: nil)
    }

    func markAllRead() {
        for index in messages.indices { messages[index].isRead = true }
        recount()
        for source in MessageSource.allCases { syncPill(for: source) }
    }

    func markRead(_ id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isRead = true
        recount()
        syncPill(for: messages[index].source)
    }

    func messages(from source: MessageSource) -> [InboxMessage] {
        messages.filter { $0.source == source }
    }

    func unreadCount(for source: MessageSource) -> Int {
        messages.filter { $0.source == source && !$0.isRead }.count
    }

    // MARK: - What the card shows

    /// Everything still waiting, newest first.
    var unread: [InboxMessage] { messages.filter { !$0.isRead } }

    /// The one the card is showing: the newest thing not yet answered.
    var active: InboxMessage? { unread.first }

    // MARK: - Replying

    /// Sends a reply to wherever the message came from.
    ///
    /// Marking it read is part of answering it, so the card can hand straight on
    /// to whatever else is waiting.
    func reply(to message: InboxMessage, text: String) async throws {
        guard let conversationID = message.conversationID, !conversationID.isEmpty else {
            throw ReplyError.noConversation
        }

        switch message.source {
        case .mattermost:
            try await MattermostClient.shared.sendMessage(
                channelID: conversationID, message: text
            )
        case .clickMassa:
            try await ClickMassaClient.shared.sendMessage(
                ticketID: conversationID, message: text
            )
        }

        markRead(message.id)
    }

    /// Why a reply could not be sent, in words the card can show as they are.
    enum ReplyError: LocalizedError {
        case noConversation

        var errorDescription: String? {
            switch self {
            case .noConversation: return "There is nowhere to reply to this one."
            }
        }
    }

    private func recount() {
        unreadCount = messages.filter { !$0.isRead }.count
    }

    /// Shows the latest sender on the pill, the way the music pill shows the
    /// playing track, and falls back to the catalog name when nothing is unread.
    private func syncPill(for source: MessageSource) {
        guard let index = AppState.shared.tasks.firstIndex(where: { $0.id == source.pillID })
        else { return }

        let latestUnread = messages.first { $0.source == source && !$0.isRead }
        let fallback = PillCatalog.definition(for: source.pillID)?.name ?? source.displayName
        AppState.shared.tasks[index].name = latestUnread?.sender ?? fallback
    }
}

extension MessageInbox {
    /// The message Home should show for a choice, or nil when that source has
    /// never said anything.
    ///
    /// Pure over the two stored values, so the rule is testable without an app.
    static func resolveHomeMessage(for content: HomeContent,
                                   last: [MessageSource: InboxMessage],
                                   lastSource: MessageSource?) -> InboxMessage? {
        guard let source = content.source(lastSource: lastSource) else { return nil }
        return last[source]
    }

    var homeMessage: InboxMessage? {
        Self.resolveHomeMessage(for: AppState.shared.homeContent,
                                last: lastBySource, lastSource: lastSource)
    }
}

extension Notification.Name {
    /// Posted when any source delivers a message, for the island to react to.
    static let inboxMessageArrived = Notification.Name("notchy.inboxMessageArrived")
}

extension String {
    /// Whitespace-trimmed, for validating settings fields before a sign-in.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
