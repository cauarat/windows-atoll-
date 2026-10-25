import Foundation

// MARK: - Pill category

enum PillCategory: String, CaseIterable {
    case workspace
    case service

    var title: String {
        switch self {
        case .workspace: return "Where you code"
        case .service:   return "Services"
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
    /// twenty trademarks. ClickMassa is the single exception, added on request.
    /// Drawing it keeps the promise the rest of the app already keeps — the
    /// character and the site mark are paths too, so `Assets.xcassets` goes on
    /// holding nothing but the app's own icons. A second one is a licensing
    /// question to settle before it is a drawing problem.
    ///
    /// A path cannot fail to resolve the way a symbol name can, so a pill with
    /// a logo needs no initial underneath it.
    var logo:       PillLogo? = nil
    let source:     AgentSource
    var comingSoon: Bool = false
    var githubOnly: Bool = false

    /// A face this pill ships with, for one that is not standing in for an
    /// outside brand and so has nobody else's look to borrow. Only a default:
    /// a character chosen for the pill in Settings still wins.
    var character:  MochiCharacter? = nil

    /// Label shown in the active-session card header (workspace/agent pills only).
    var sessionSubtitle: String {
        switch id {
        case "integration_claude": return "Claude Code"
        case "agent_cursor":       return "Cursor"
        case "agent_codex":        return "Codex"
        default:                   return "Agent"
        }
    }
}

// MARK: - Catalog

enum PillCatalog {
    // All declared pills in display order.
    static let all: [PillDefinition] = [
        // ── Where you code ───────────────────────────────────────────────────
        // Always loaded, and the only one that is. `HookServer` routes every
        // Claude Code session to this id, and the session card reads its name
        // and colour from here — without an entry a live session draws as an
        // unconfigured stranger. It used to be loaded because it happened to
        // be `mainPillId`; now it is loaded because it is this one.
        //
        // Named for what it is. "VS Code" was the editor it was first wired
        // to, and it has not meant that for a long time.
        .init(id: "integration_claude",  name: "Claude Code", color: "#F5F6F8",
              category: .workspace, subtitle: "Integration",  icon: "chevron.left.forwardslash.chevron.right", source: .claudeCode),
        // ── Services ─────────────────────────────────────────────────────────
        .init(id: "integration_music",   name: "Now Playing", color: "#FA2D48",
              category: .service,   subtitle: "Integration",  icon: "music.note", source: .n8n, githubOnly: true),
        .init(id: "integration_mattermost", name: "Mattermost", color: "#1B6FF3",
              category: .service,   subtitle: "Messages",     logo: .mattermost, source: .n8n, githubOnly: true),
        .init(id: "integration_clickmassa", name: "ClickMassa", color: MessageSource.clickMassa.accentHex,
              category: .service,   subtitle: "Messages",     logo: .clickMassa, source: .n8n, githubOnly: true),
        // One pill over both message services. White because it stands for no
        // brand: every other pill wears the colour of the thing behind it, and
        // this one is the island's own. Its Mochi takes that white, the way
        // every pill's Mochi takes its pill's colour.
        .init(id: "integration_notifications", name: "Notifications", color: "#FFFFFF",
              category: .service,   subtitle: "Messages",     icon: "bell.fill", source: .n8n, githubOnly: true,
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

    /// The pill that loads whether or not it was switched on, because the
    /// hook server needs somewhere to put a session that just arrived.
    ///
    /// This replaces `mainPillId`, which was a choice between four editors
    /// when there were four. With one, the choice was a picker with a single
    /// option — so it is a constant, and it costs none of the four slots.
    static let alwaysLoadedID = "integration_claude"

    /// Looks up a definition by task ID (nil if not in catalog).
    static func definition(for id: String) -> PillDefinition? {
        all.first { $0.id == id }
    }
}
