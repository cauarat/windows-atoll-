import Foundation

/// Where a message came from, and what the UI may do with it.
///
/// Kept as one enum rather than switched on a string in each place that asks,
/// which is the mistake Atoll had to undo after the same switch drifted apart
/// across four files.
enum MessageSource: String, CaseIterable, Sendable {
    case mattermost
    case clickMassa = "clickmassa"
    /// Actuar's own support inbox, inside novo.actuar.com — the tool taking
    /// over from ClickMassa.
    case ato

    var displayName: String {
        switch self {
        case .mattermost: return "Mattermost"
        case .clickMassa: return "ClickMassa"
        case .ato:        return "Ato"
        }
    }

    /// The pill this source drives. These ids are contract values, like every
    /// other pill id: never rename one.
    var pillID: String {
        switch self {
        case .mattermost: return "integration_mattermost"
        case .clickMassa: return "integration_clickmassa"
        case .ato:        return "integration_ato"
        }
    }

    var accentHex: String {
        switch self {
        case .mattermost: return "#1B6FF3"
        case .clickMassa: return "#41BFEF"
        // The indigo of Ato's own mascot and of the inbox's accent.
        case .ato:        return "#5B5BF6"
        }
    }

    /// Whether a reply can be sent back. All three can; kept explicit because the
    /// card has to decide whether to offer the box.
    var supportsReply: Bool { true }

    /// Whether files can ride along with a reply. Both can, by different
    /// routes, which is why this is not a constant.
    ///
    /// Mattermost uploads first and posts second: `POST /api/v4/files` returns
    /// ids the post carries as `file_ids`.
    ///
    /// ClickMassa has no post for ids to ride on — every request *is* a
    /// message — so each file is its own `POST /messages/{ticketId}`, sent as
    /// multipart with the bytes under `medias`. That route is the same
    /// inference as the reply route beneath it (see `ClickMassaClient.post`),
    /// from the same Whaticket-family panel, and it is held to the same
    /// bargain: a 404 names the route it tried rather than leaving someone
    /// wondering where their file went.
    var supportsAttachments: Bool {
        switch self {
        case .mattermost: return true
        case .clickMassa: return true
        // Not yet. The agent console uploads a file to storage first and then
        // posts its id, and that first half has not been traced. Words only
        // until it has, rather than a clip that fails at send time.
        case .ato:        return false
        }
    }
}
