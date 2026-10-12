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

    /// The message the card is on when one was picked out of a list.
    ///
    /// Nil means "whatever is newest and unread", which is how the card behaved
    /// before the list existed and how it still behaves for a message that
    /// arrives on its own.
    @Published private(set) var activeID: String?

    /// The source whose list is open, nil when nobody is in one.
    ///
    /// What tells the card where to go back to: a reply sent from the list
    /// returns to the list, a reply to a message that announced itself does not.
    @Published private(set) var listSource: MessageSource?

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

        // What arrives takes the card, the way it did before the list existed —
        // but not out from under someone reading one they picked themselves.
        if listSource == nil { activeID = message.id }
        recount()
        syncPill(for: message.source)

        NotificationCenter.default.post(name: .inboxMessageArrived, object: nil)
        // The card is what answers a message; the banner is what makes sure it
        // was seen. Posted after the island has been told, so the notch is
        // already showing the card by the time Notification Center draws.
        MessageNotifier.shared.present(message)
    }

    func markAllRead() {
        for index in messages.indices where !messages[index].isRead {
            messages[index].isRead = true
            MessageNotifier.shared.withdraw(messages[index].id)
        }
        activeID = nil
        recount()
        for source in MessageSource.allCases { syncPill(for: source) }
    }

    func markRead(_ id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isRead = true
        // Answering the one on the card hands on to the next thing waiting —
        // inside the same source while a list is open, so a reply never drops
        // someone into another service's messages.
        if activeID == id {
            activeID = messages.first {
                !$0.isRead && (listSource == nil || $0.source == listSource)
            }?.id
        }
        recount()
        syncPill(for: messages[index].source)
        // Answered here, so the banner must stop offering its own Reply box.
        MessageNotifier.shared.withdraw(id)
    }

    func messages(from source: MessageSource) -> [InboxMessage] {
        messages.filter { $0.source == source }
    }

    /// Everything still waiting from one source, newest first.
    ///
    /// Sorted rather than trusted in array order: ``ingest`` always inserts at
    /// the front, so a reconnect replaying its history would otherwise stack
    /// older messages above newer ones.
    func unread(from source: MessageSource) -> [InboxMessage] {
        messages
            .filter { $0.source == source && !$0.isRead }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func unreadCount(for source: MessageSource) -> Int {
        messages.filter { $0.source == source && !$0.isRead }.count
    }

    // MARK: - What the card shows

    /// Everything still waiting, newest first.
    var unread: [InboxMessage] { messages.filter { !$0.isRead } }

    /// The one the card is showing: the message picked out of a list, or the
    /// newest thing not yet answered.
    var active: InboxMessage? {
        if let activeID, let picked = messages.first(where: { $0.id == activeID }) {
            return picked
        }
        return unread.first
    }

    // MARK: - The list

    /// Puts the card on one particular message, chosen from a list.
    func select(_ id: String) {
        guard messages.contains(where: { $0.id == id }) else { return }
        activeID = id
    }

    /// Opens a source's list. Nothing is picked out of it yet.
    func openList(_ source: MessageSource) {
        listSource = source
        activeID = nil
    }

    /// Leaves the list, so the card goes back to announcing what arrives.
    ///
    /// Called on every collapse, so it has to be free when no list was open:
    /// clearing the selection then would drop the card someone left mid-read.
    func closeList() {
        guard listSource != nil else { return }
        listSource = nil
        activeID = nil
    }

    // MARK: - Replying

    /// Sends a reply to wherever the message came from.
    ///
    /// Marking it read is part of answering it, so the card can hand straight on
    /// to whatever else is waiting.
    func reply(to message: InboxMessage,
               text: String,
               attachments: [ReplyAttachment] = []) async throws {
        guard let conversationID = message.conversationID, !conversationID.isEmpty else {
            throw ReplyError.noConversation
        }
        guard attachments.isEmpty || message.source.supportsAttachments else {
            throw ReplyError.noAttachments(message.source.displayName)
        }

        switch message.source {
        case .mattermost:
            try await MattermostClient.shared.sendMessage(
                channelID: conversationID,
                message: text,
                attachments: attachments.map(\.url)
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
        case noAttachments(String)

        var errorDescription: String? {
            switch self {
            case .noConversation:
                return "There is nowhere to reply to this one."
            case .noAttachments(let source):
                // Reachable only if a card offered the clip for a source that
                // cannot take one — a bug, but one worth saying out loud
                // rather than dropping the files silently.
                return "\(source) can't take files."
            }
        }
    }

    private func recount() {
        unreadCount = messages.filter { !$0.isRead }.count
    }

    /// Puts what is waiting on the pill: who it is from, and what they said.
    ///
    /// The sender alone was not enough. Once the card folds away, the pill is
    /// all that is left of a message, and a name with no text says only that
    /// something happened. The ticker already scrolls two lines for every other
    /// pill in the island, so the message goes there -- the same shape the
    /// Windows build gives it, so the two do not drift apart.
    private func syncPill(for source: MessageSource) {
        guard let index = AppState.shared.tasks.firstIndex(where: { $0.id == source.pillID })
        else { return }

        let fallback = PillCatalog.definition(for: source.pillID)?.name ?? source.displayName

        guard let latest = messages.first(where: { $0.source == source && !$0.isRead }) else {
            AppState.shared.tasks[index].name = fallback
            AppState.shared.tasks[index].state = .idle
            AppState.shared.tasks[index].steps = []
            AppState.shared.tasks[index].stepIndex = 0
            AppState.shared.tasks[index].pillBadge = nil
            return
        }

        let channel = latest.channel?.trimmed ?? ""
        let origin = channel.isEmpty ? source.displayName : "in \(channel)"
        AppState.shared.tasks[index].name = latest.sender.isEmpty ? fallback : latest.sender
        AppState.shared.tasks[index].state = .question
        AppState.shared.tasks[index].steps = [origin, latest.body]
        AppState.shared.tasks[index].stepIndex = 1
        // The badge is the pill saying "this one, not the one you are looking
        // at" -- pointless on the pill already in focus.
        AppState.shared.tasks[index].pillBadge =
            AppState.shared.focusId == source.pillID ? nil : .approval
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

    /// The message an open reply box is addressed to, or nil when no reply
    /// surface is showing.
    ///
    /// The two surfaces draw different messages on purpose — the pop-up shows
    /// the newest unread, Home shows the last thing a chosen source said — so
    /// the answer depends on which one is up.
    func replyTarget(for view: IslandView) -> InboxMessage? {
        switch view {
        case .message:  return active
        case .overview: return homeMessage
        default:        return nil
        }
    }

    /// Whether a file dropped right now would have somewhere to go.
    ///
    /// Both halves matter: a message with no `conversationID` cannot be
    /// replied to at all, and a source that cannot carry files must not take
    /// a drop it would then have to refuse at send time.
    func replyAcceptsFiles(for view: IslandView) -> Bool {
        guard let message = replyTarget(for: view),
              let conversation = message.conversationID, !conversation.isEmpty
        else { return false }
        return message.source.supportsReply && message.source.supportsAttachments
    }
}

extension Notification.Name {
    /// Posted when any source delivers a message, for the island to react to.
    static let inboxMessageArrived = Notification.Name("notchy.inboxMessageArrived")
    /// Somebody asked to see a source's messages, rather than one arriving.
    static let showMessageCard = Notification.Name("notchy.showMessageCard")
}

extension String {
    /// Whitespace-trimmed, for validating settings fields before a sign-in.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Why the list is empty

/// Deliberately here and not beside the enum in MessageSource.swift. That file
/// is compiled by the test runners, which take a short closed list of sources,
/// and this reaches for the two clients — which are not on that list and drag
/// in the rest of the app behind them. The enum stays testable; this does not
/// need to be.
extension MessageSource {

    /// Why nothing is waiting, when the reason is the connection rather than a
    /// quiet morning. Nil while connected, because then an empty list means
    /// exactly what it says.
    ///
    /// The two clients publish the same four cases from two separate nested
    /// enums; this is the one place that has to know both.
    @MainActor var connectionProblem: String? {
        switch self {
        case .mattermost:
            switch MattermostClient.shared.state {
            case .connected:    return nil
            case .connecting:   return String(localized: "Connecting…")
            case .disconnected: return String(localized: "Not connected.")
            case .failed(let reason): return reason
            }
        case .clickMassa:
            switch ClickMassaClient.shared.state {
            case .connected:    return nil
            case .connecting:   return String(localized: "Connecting…")
            case .disconnected: return String(localized: "Not connected.")
            case .failed(let reason): return reason
            }
        }
    }
}
