import UIKit
import UserNotifications

// MARK: - Notifications on the phone
//
// Made by the app itself, from what arrives on the link: there is no push server, so they come while
// the app is in front or in the short time iOS leaves it after it goes to the background. A permission
// request gets Deny and Allow; Allow opens the app and asks for Face ID before anything is sent. The
// command itself is never shown on the lock screen (the notification only says a command waits).

@MainActor
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifications()

    static let approvalCategory = "approval"
    static let truncatedCategory = "approval-deny-only"
    static let allowAction = "allow"
    static let denyAction = "deny"

    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let deny = UNNotificationAction(identifier: Self.denyAction, title: String(localized: "Deny"), options: [.destructive])
        let allow = UNNotificationAction(identifier: Self.allowAction, title: String(localized: "Allow"),
                                         options: [.authenticationRequired, .foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.approvalCategory, actions: [deny, allow], intentIdentifiers: [],
                                   hiddenPreviewsBodyPlaceholder: String(localized: "A command waits for your OK"), options: []),
            UNNotificationCategory(identifier: Self.truncatedCategory, actions: [deny], intentIdentifiers: [], options: []),
        ])
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private var inFront: Bool { UIApplication.shared.applicationState == .active }

    func approval(_ request: ApprovalRequest, agent: String, computer: String) {
        guard !inFront else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(agent) needs permission")
        content.subtitle = computer
        content.body = String(localized: "\(request.tool) wants to run a command. Open to see it.")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = request.truncated ? Self.truncatedCategory : Self.approvalCategory
        content.userInfo = ["fingerprint": request.fingerprint]
        content.threadIdentifier = "approvals"
        post(id: request.fingerprint, content)
    }

    func question(_ request: QuestionRequest, agent: String, computer: String) {
        guard !inFront else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(agent) is asking")
        content.subtitle = computer
        content.body = request.questions.first?.question ?? ""
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["fingerprint": request.fingerprint]
        content.threadIdentifier = "questions"
        post(id: request.fingerprint, content)
    }

    func finished(_ session: SessionInfo, computer: String) {
        guard !inFront, UserDefaults.standard.object(forKey: "notifyFinished") as? Bool ?? true else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(session.agent) finished")
        content.subtitle = computer
        content.body = session.finalLine ?? String(localized: "Your agent is done.")
        content.sound = .default
        content.threadIdentifier = "finished"
        post(id: "finished-" + session.pillId, content)
    }

    func remove(fingerprint: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [fingerprint])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [fingerprint])
    }

    func clearDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    private func post(id: String, _ content: UNMutableNotificationContent) {
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        // In front, the island shows it; no banner on top of it.
        []
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let fingerprint = response.notification.request.content.userInfo["fingerprint"] as? String
        let action = response.actionIdentifier
        guard let fingerprint else { return }
        switch action {
        case Self.allowAction:
            await PhoneStore.shared.decideFromNotification(fingerprint: fingerprint, allow: true)
        case Self.denyAction:
            await PhoneStore.shared.decideFromNotification(fingerprint: fingerprint, allow: false)
        default:
            break
        }
    }
}
