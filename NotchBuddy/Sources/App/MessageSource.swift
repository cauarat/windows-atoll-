import Foundation

/// Where a message came from, and what the UI may do with it.
///
/// Kept as one enum rather than switched on a string in each place that asks,
/// which is the mistake Atoll had to undo after the same switch drifted apart
/// across four files.
enum MessageSource: String, CaseIterable, Sendable {
    case mattermost
    case clickMassa = "clickmassa"

    var displayName: String {
        switch self {
        case .mattermost: return "Mattermost"
        case .clickMassa: return "ClickMassa"
        }
    }

    /// The pill this source drives. These ids are contract values, like every
    /// other pill id: never rename one.
    var pillID: String {
        switch self {
        case .mattermost: return "integration_mattermost"
        case .clickMassa: return "integration_clickmassa"
        }
    }

    var accentHex: String {
        switch self {
        case .mattermost: return "#1B6FF3"
        case .clickMassa: return "#41BFEF"
        }
    }

    /// Whether a reply can be sent back. Both can; kept explicit because the
    /// card has to decide whether to offer the box.
    var supportsReply: Bool { true }

    /// Whether files can ride along with a reply.
    ///
    /// Mattermost can: `POST /api/v4/files` returns ids the post carries as
    /// `file_ids`. ClickMassa cannot, and not merely because it is unbuilt —
    /// the reply route itself is an inference (see `ClickMassaClient.post`),
    /// there is no documented upload route to aim at, and the inbound model
    /// carries `mediaType` as a display tag with no id beside it. Until that
    /// is known, the card offers nothing rather than a button that fails.
    var supportsAttachments: Bool {
        switch self {
        case .mattermost: return true
        case .clickMassa: return false
        }
    }
}
