import ActivityKit
import Foundation

// MARK: - Starting, updating and ending the Live Activity
//
// iOS lets an app start a Live Activity only while it is in front, and with no push server the app
// updates it itself, while it runs. So Mochi goes to the Lock Screen when an agent is busy and Notchy
// is open, follows the session while the app lives, and is ended when every agent is idle again, when
// the phone is unpaired, or when the user turns it off. A stale one is dimmed by iOS after a while.

@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    static let enabledKey = "phoneLiveActivity"

    private var activity: Activity<MochiActivityAttributes>?
    private var last: MochiActivityAttributes.ContentState?

    private var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    func update(sessions: [SessionInfo], approval: ApprovalRequest?, question: QuestionRequest?) {
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let busy = sessions.filter { $0.state != .idle && $0.state != .sleeping }
        let lead = approval.flatMap { a in sessions.first { $0.pillId == a.pillId } }
            ?? question.flatMap { q in sessions.first { $0.pillId == q.pillId } }
            ?? busy.first { $0.state.isBusy } ?? busy.first
        guard let lead else {
            end()
            return
        }
        let waiting = approval != nil || question != nil
        let detail: String
        if let approval { detail = String(localized: "\(approval.tool) needs permission") }
        else if question != nil { detail = String(localized: "Claude is asking you something") }
        else if lead.state == .finished { detail = lead.finalLine ?? String(localized: "Finished") }
        else { detail = lead.statusText }
        let state = MochiActivityAttributes.ContentState(
            agent: lead.agent, project: lead.project,
            state: waiting ? (approval != nil ? BotState.approval.rawValue : BotState.question.rawValue) : lead.state.rawValue,
            detail: String(detail.prefix(120)), color: lead.pillId == "integration_claude" ? nil : lead.color,
            waiting: waiting, stepIndex: lead.stepIndex, stepCount: lead.stepCount,
            accessory: lead.character.accessory?.rawValue, eye: lead.character.eye?.rawValue, shape: lead.character.shape?.rawValue,
            others: max(0, busy.count - 1))
        guard state != last else { return }
        last = state
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(15 * 60))
        if let activity, activity.activityState == .active {
            let id = activity.id
            Task.detached {
                for a in Activity<MochiActivityAttributes>.activities where a.id == id { await a.update(content) }
            }
        } else if lead.state != .finished || waiting {
            let attributes = MochiActivityAttributes(computer: PhoneStore.shared.computerName)
            activity = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        }
    }

    func end() {
        last = nil
        activity = nil
        // Every one of ours, including one left from a run of the app that was killed.
        Task.detached {
            for a in Activity<MochiActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
