import Foundation

/// What the Home tab shows.
///
/// Home used to be whichever pill was in focus, which in practice meant the
/// VS Code card, always. This makes it a choice — and the default is that the
/// two messaging integrations take turns, so Home holds the last thing either
/// of them said and the notification is still there when you go back to it.
///
/// More than a pill id, because the timer is not a pill.
enum HomeContent: String, CaseIterable, Codable {
    /// Both message services as one queue, and the default. Listed first
    /// because the order here is the order of the picker.
    ///
    /// The newest message from either, same as `automatic` — what sets it
    /// apart is that nothing takes Home away from it. A song starting does
    /// not, and that is the point of choosing it: somebody who wants messages
    /// in front of them wants them there while music plays too.
    case notifications
    /// ClickMassa and Mattermost, whichever spoke most recently.
    case automatic
    case clickMassa
    case mattermost
    case timer
    /// The pill in focus — what Home did before this existed.
    case claudeCode

    var label: String {
        switch self {
        case .notifications: return "Notifications"
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
        case .notifications, .automatic: return lastSource
        case .clickMassa: return .clickMassa
        case .mattermost: return .mattermost
        case .timer, .claudeCode: return nil
        }
    }

    /// Whether Home should hand itself over to whatever is playing.
    ///
    /// Only while Home is on automatic. Automatic already means "whatever is
    /// most alive right now", and something actually playing is more alive than
    /// a message from an hour ago — but somebody who picked ClickMassa on
    /// purpose asked for ClickMassa, and a song starting is not a reason to
    /// take it away from them.
    ///
    /// Loaded rather than playing, because Home now holds the player itself
    /// rather than a glance at it: pressing pause on a card must not make the
    /// card it is on disappear.
    func showsMusic(hasTrack: Bool) -> Bool {
        switch self {
        case .automatic: return hasTrack
        default:         return false
        }
    }

    /// What the settings row says underneath, so the choice explains itself.
    var hint: String {
        switch self {
        case .notifications:
            return "ClickMassa and Mattermost as one queue — Home keeps the last thing either "
                 + "of them said, and keeps it while something is playing."
        case .automatic:
            return "ClickMassa and Mattermost take turns — Home keeps whichever spoke last, "
                 + "and hands over to whatever is playing while something is."
        case .clickMassa: return "Home keeps the last ClickMassa message."
        case .mattermost: return "Home keeps the last Mattermost message."
        case .timer:      return "Home is the focus timer."
        case .claudeCode: return "Home is the integration you have in focus."
        }
    }
}
