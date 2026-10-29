/*
 * Notchy
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

import AppKit
import UserNotifications

/// A macOS notification banner for every message the inbox takes in.
///
/// The notch card is still where a message is answered; this only makes sure it
/// is seen. The island lives in the notch, and the notch is covered by a
/// full-screen window, absent on a second display, and folded away on a timer --
/// so a message that arrived while someone was elsewhere left nothing behind
/// but a name on a pill. A banner stays in Notification Center, carries the
/// text and not just the sender, and can be answered without reaching for the
/// notch at all.
///
/// Everything here is best-effort: refused permission, an unbundled process or
/// a banner that fails to post must never cost the card its message.
@MainActor
final class MessageNotifier: NSObject {
    static let shared = MessageNotifier()

    /// Contract values, like the pill ids: they are written into delivered
    /// notifications, which outlive a launch. Never rename one.
    /// `nonisolated` so the delegate callbacks, which arrive off the main
    /// actor, can read them without a hop.
    nonisolated private static let categoryID = "notchy.message"
    nonisolated private static let replyActionID = "notchy.message.reply"
    nonisolated private static let openActionID = "notchy.message.open"
    nonisolated private static let messageIDKey = "messageID"

    /// Nil when the process is not a bundled app -- `UNUserNotificationCenter`
    /// traps there rather than failing, which would take the whole app down in
    /// a `swift test` run or a stray command-line build.
    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleIdentifier == nil ? nil : .current()

    /// Set once the category and delegate are installed, so `prepare()` can be
    /// called from every source turning on without asking twice.
    private var prepared = false

    private override init() { super.init() }

    // MARK: - Setup

    /// Registers the reply action and asks for permission, once.
    ///
    /// Called when a message source is switched on rather than at launch: the
    /// system prompt is worth showing to someone who has just connected a chat
    /// account, and not to someone who only ever uses Coucou for Claude Code.
    func prepare() {
        guard let center, !prepared else { return }
        prepared = true

        let reply = UNTextInputNotificationAction(
            identifier: Self.replyActionID,
            title: L("Reply"),
            options: [],
            textInputButtonTitle: L("Send"),
            textInputPlaceholder: L("Reply…")
        )
        let open = UNNotificationAction(
            identifier: Self.openActionID,
            title: L("Open"),
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [reply, open],
            intentIdentifiers: [],
            options: []
        )

        center.delegate = self
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert]) { _, error in
            if let error { logMessages("authorization refused: \(error.localizedDescription)") }
        }
    }

    // MARK: - Posting

    /// Shows `message` as a banner, if banners are on and Coucou is not off.
    func present(_ message: InboxMessage) {
        guard let center, AppState.shared.isEnabled, AppState.shared.messageBanners else { return }
        prepare()

        let content = UNMutableNotificationContent()
        content.title = message.sender.isEmpty ? message.source.displayName : message.sender
        content.subtitle = Self.origin(message)
        content.body = message.body
        // No ticket, no channel: the Reply box would take a sentence and drop
        // it, so the banner goes out without one.
        content.categoryIdentifier = message.conversationID == nil ? "" : Self.categoryID
        content.userInfo = [Self.messageIDKey: message.id]
        // One stack per conversation, so a burst from the same person does not
        // bury everything else that came in.
        content.threadIdentifier = message.conversationID ?? message.source.rawValue
        // Silent on purpose: the island already plays "question" for this very
        // message, and two alerts for one message is one too many.
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: Self.requestID(for: message.id),
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error { logMessages("banner failed: \(error.localizedDescription)") }
        }
    }

    /// Takes a banner back once its message has been answered, so Notification
    /// Center does not keep offering a Reply box for a finished conversation.
    func withdraw(_ messageID: String) {
        guard let center else { return }
        let id = Self.requestID(for: messageID)
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Clears every banner Coucou has posted -- what the master switch owes
    /// someone who has just turned it off.
    func withdrawAll() {
        guard let center else { return }
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Helpers

    /// The same line the card shows under the sender, so the banner and the
    /// notch do not describe one message two ways.
    private static func origin(_ message: InboxMessage) -> String {
        if let channel = message.channel, !channel.isEmpty { return "in \(channel)" }
        return "\(message.source.displayName) · direct"
    }

    /// Prefixed so `withdrawAll` can never reach past Coucou's own banners, and
    /// so a re-ingested id replaces its banner instead of stacking a second one.
    private static func requestID(for messageID: String) -> String {
        "notchy.message.\(messageID)"
    }
}

// MARK: - Delegate

extension MessageNotifier: UNUserNotificationCenterDelegate {
    /// Coucou is an accessory app and almost never frontmost, but Settings
    /// makes it so -- and a message that arrives while someone is typing their
    /// password into the ClickMassa box is exactly the one worth showing.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let messageID = response.notification.request.content.userInfo[Self.messageIDKey] as? String
        let typed = (response as? UNTextInputNotificationResponse)?.userText

        // Only Sendable values cross: the notification itself stays here.
        Task { @MainActor in
            MessageNotifier.shared.handle(action: action, messageID: messageID, typed: typed)
        }
        completionHandler()
    }

    /// What a click on the banner, or on one of its buttons, does.
    private func handle(action: String, messageID: String?, typed: String?) {
        guard let messageID,
              let message = MessageInbox.shared.messages.first(where: { $0.id == messageID })
        else {
            // The message is gone (answered elsewhere, or the app restarted):
            // the island is still the right place to land.
            if action == UNNotificationDefaultActionIdentifier { showCard() }
            return
        }

        switch action {
        case Self.replyActionID:
            let text = (typed ?? "").trimmed
            guard !text.isEmpty else { return }
            Task { @MainActor in
                do {
                    try await MessageInbox.shared.reply(to: message, text: text)
                    SoundEngine.shared.play("send")
                } catch {
                    // Nothing can be typed into a banner twice, so the card is
                    // what gets the second try -- with the message still unread.
                    logMessages("reply from banner failed: \(error.localizedDescription)")
                    self.showCard()
                }
            }

        case Self.openActionID:
            if let link = message.link { NSWorkspace.shared.open(link) }
            MessageInbox.shared.markRead(message.id)

        case UNNotificationDefaultActionIdentifier:
            showCard()

        default:
            break   // dismissed: it stays unread, and the pill still says so
        }
    }

    /// Brings the island up on this message, the way the card arriving would.
    private func showCard() {
        guard AppState.shared.isEnabled else { return }
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.message)
    }
}
