import Foundation

// MARK: - Pill category

/// One category now. "Where you code" held Claude Code alone, and went with it;
/// the enum stays because Settings and the welcome draw their lists by it.
enum PillCategory: String, CaseIterable {
    case service

    var title: String {
        switch self {
        case .service: return "Services"
        }
    }
}

// MARK: - Pill definition

struct PillDefinition {
    let id:         String
    let name:       String
    let color:      String
    let category:   PillCategory
    /// Label shown next to the task name in the idle card header.
    let subtitle:   String
    /// An SF Symbol for the button on the island's edge.
    ///
    /// There is no brand artwork in this repository and adding twenty logos
    /// would be a licensing question of its own, so each pill borrows a symbol
    /// that says what it is for. A name macOS does not know draws nothing, so
    /// the button falls back to the pill's initial on its own colour — which is
    /// how it already tells itself apart everywhere else.
    ///
    /// Ignored when `logo` is set.
    var icon:       String = "circle.fill"
    /// A mark drawn in code, for a pill that has one. Takes over from `icon`.
    ///
    /// The rule above still holds: no bitmaps, and no helping yourself to
    /// twenty trademarks. Ato is the single exception, added on request.
    /// Drawing it keeps the promise the rest of the app already keeps — the
    /// character and the site mark are paths too, so `Assets.xcassets` goes on
    /// holding nothing but the app's own icons. A second one is a licensing
    /// question to settle before it is a drawing problem.
    ///
    /// A path cannot fail to resolve the way a symbol name can, so a pill with
    /// a logo needs no initial underneath it.
    var logo:       PillLogo? = nil
    var comingSoon: Bool = false
    var githubOnly: Bool = false

    /// A face this pill ships with, for one that is not standing in for an
    /// outside brand and so has nobody else's look to borrow. Only a default:
    /// a character chosen for the pill in Settings still wins.
    var character:  MochiCharacter? = nil
}

// MARK: - Catalog

enum PillCatalog {
    /// All declared pills in display order.
    ///
    /// `integration_claude` (Claude Code, the one pill under "Where you code")
    /// is retired with the coding agents. Like every pill id it is a contract
    /// value: never reuse it. A stored list that still names it loses it on load.
    static let all: [PillDefinition] = [
        // ── Services ─────────────────────────────────────────────────────────
        .init(id: "integration_music",   name: "Now Playing", color: "#FA2D48",
              category: .service,   subtitle: "Integration",  icon: "music.note", githubOnly: true),
        .init(id: "integration_mattermost", name: "Mattermost", color: "#1B6FF3",
              category: .service,   subtitle: "Messages",     logo: .mattermost, githubOnly: true),
        // Actuar's support inbox, inside novo.actuar.com. It took over from
        // ClickMassa, whose `integration_clickmassa` id is retired, not reused.
        .init(id: "integration_ato", name: "Ato", color: MessageSource.ato.accentHex,
              category: .service,   subtitle: "Messages",     logo: .ato, githubOnly: true),
        // The user's own WhatsApp, through WhatsApp Web. A symbol and not the
        // logo: drawing a second trademark is the licensing question PillLogo
        // asks to settle first.
        .init(id: "integration_whatsapp", name: "WhatsApp", color: MessageSource.whatsapp.accentHex,
              category: .service,   subtitle: "Messages",     icon: "phone.bubble.fill", githubOnly: true),
        // One pill over both message services. White because it stands for no
        // brand: every other pill wears the colour of the thing behind it, and
        // this one is the island's own. Its Mochi takes that white, the way
        // every pill's Mochi takes its pill's colour.
        .init(id: "integration_notifications", name: "Notifications", color: "#FFFFFF",
              category: .service,   subtitle: "Messages",     icon: "bell.fill", githubOnly: true,
              // An antenna and pixel eyes: this one listens for things arriving.
              // White comes from the pill, as it does for every Mochi.
              character: MochiCharacter(accessory: .antenna, eye: .pixel)),
    ]

    /// The pill that stands for both message services. A contract value like
    /// every other pill id: never rename it.
    static let notificationsID = "integration_notifications"

    /// Pills available in the current build target.
    static var available: [PillDefinition] {
        #if APPSTORE
        all.filter { !$0.githubOnly }
        #else
        all
        #endif
    }

    /// Looks up a definition by task ID (nil if not in catalog).
    static func definition(for id: String) -> PillDefinition? {
        all.first { $0.id == id }
    }
}
