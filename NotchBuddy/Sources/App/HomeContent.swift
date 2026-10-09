import Foundation

/// What the Home tab shows.
///
/// Home used to be whichever pill was in focus, which in practice meant the
/// VS Code card, always. This makes it a choice — and the default is that the
/// two messaging integrations take turns, so Home holds the last thing either
/// of them said and the notification is still there when you go back to it.
///
/// Separate from `AppState.mainPillId`, which is validated as a **workspace**
/// pill and so can never be Mattermost or ClickMassa; and it has to be more than
/// a pill id anyway, because the timer is not a pill.
enum HomeContent: String, CaseIterable, Codable {
    /// ClickMassa and Mattermost, whichever spoke most recently. The default.
    case automatic
    case clickMassa
    case mattermost
    case timer
    /// The pill in focus — what Home did before this existed.
    case claudeCode

    var label: String {
        switch self {
        case .automatic:  return "Last message"
        case .clickMassa: return "ClickMassa"
        case .mattermost: return "Mattermost"
        case .timer:      return "Timer"
        case .claudeCode: return "Claude Code"
        }
    }

    /// Which source Home should draw, or nil when this choice is not a message.
    ///
    /// The whole of "they take turns" is here, over two plain values, so it can
    /// be tested without an app. Looking the message up afterwards is a
    /// dictionary read and needs no rule.
    func source(lastSource: MessageSource?) -> MessageSource? {
        switch self {
        case .automatic:  return lastSource
        case .clickMassa: return .clickMassa
        case .mattermost: return .mattermost
        case .timer, .claudeCode: return nil
        }
    }

    /// What the settings row says underneath, so the choice explains itself.
    var hint: String {
        switch self {
        case .automatic:
            return "ClickMassa and Mattermost take turns — Home keeps whichever spoke last."
        case .clickMassa: return "Home keeps the last ClickMassa message."
        case .mattermost: return "Home keeps the last Mattermost message."
        case .timer:      return "Home is the focus timer."
        case .claudeCode: return "Home is the integration you have in focus."
        }
    }
}
