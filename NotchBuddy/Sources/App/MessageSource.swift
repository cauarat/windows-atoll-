import Foundation

/// Where a message came from, and what the UI may do with it.
///
/// Kept as one enum rather than switched on a string in each place that asks,
/// which is the mistake Atoll had to undo after the same switch drifted apart
/// across four files.
enum MessageSource: String, CaseIterable, Sendable {
    case mattermost
    /// Actuar's own support inbox, inside novo.actuar.com. It replaced
    /// ClickMassa, whose source and pill are gone.
    case ato
    /// The user's own WhatsApp, through WhatsApp Web kept running out of sight.
    /// There is no API for a personal account; see ``WhatsAppWebController``.
    case whatsapp

    var displayName: String {
        switch self {
        case .mattermost: return "Mattermost"
        case .ato:        return "Ato"
        case .whatsapp:   return "WhatsApp"
        }
    }

    /// The pill this source drives. These ids are contract values, like every
    /// other pill id: never rename one.
    var pillID: String {
        switch self {
        case .mattermost: return "integration_mattermost"
        case .ato:        return "integration_ato"
        case .whatsapp:   return "integration_whatsapp"
        }
    }

    var accentHex: String {
        switch self {
        case .mattermost: return "#1B6FF3"
        // The blue of Ato's mascot — its front layer, Actuar's own #1B2FEB.
        case .ato:        return "#1B2FEB"
        // WhatsApp's own green.
        case .whatsapp:   return "#25D366"
        }
    }

    /// Whether a reply can be sent back. All of them can; kept explicit because the
    /// card has to decide whether to offer the box.
    var supportsReply: Bool { true }

    /// Whether files can ride along with a reply.
    ///
    /// Mattermost uploads first and posts second: `POST /api/v4/files` returns
    /// ids the post carries as `file_ids`.
    var supportsAttachments: Bool {
        switch self {
        case .mattermost: return true
        // The agent console's way: each file is uploaded to the storage
        // service's chat folder, and the message names what it answered.
        case .ato:        return true
        // The page itself takes the file: pasted for an image, dropped on the
        // conversation for anything else, the way a person would.
        case .whatsapp:   return true
        }
    }
}
