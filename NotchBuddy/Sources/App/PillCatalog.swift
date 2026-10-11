import Foundation

// MARK: - Pill category

enum PillCategory: String, CaseIterable {
    case workspace
    case agent
    case ai
    case service

    var title: String {
        switch self {
        case .workspace: return "Where you code"
        case .agent:     return "Agents"
        case .ai:        return "AI for the chat"
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
        .init(id: "integration_claude",  name: "VS Code",     color: "#F5F6F8",
              category: .workspace, subtitle: "Integration",  icon: "chevron.left.forwardslash.chevron.right", source: .claudeCode),
        .init(id: "agent_cursor",        name: "Cursor",      color: "#C0C4CC",
              category: .workspace, subtitle: "Integration",  icon: "cursorarrow", source: .agent),
        .init(id: "agent_antigravity",   name: "Antigravity", color: "#E879F9",
              category: .workspace, subtitle: "Integration",  icon: "arrow.up.circle.fill", source: .agent,  githubOnly: true),
        .init(id: "agent_codex",         name: "Codex",       color: "#2DD4BF",
              category: .workspace, subtitle: "Integration",  icon: "terminal.fill", source: .agent,  githubOnly: true),
        // ── Agents ───────────────────────────────────────────────────────────
        .init(id: "agent_gemini",        name: "Gemini CLI",  color: "#8AB4F8",
              category: .agent,     subtitle: "Agent",        icon: "sparkles", source: .agent,  githubOnly: true),
        // ── AI for the chat ──────────────────────────────────────────────────
        .init(id: "ai_anthropic",        name: "Anthropic",   color: ChatProvider.anthropic.accentHex,
              category: .ai,        subtitle: "Chat",         icon: "bubble.left.fill", source: .n8n),
        .init(id: "ai_google",           name: "Google AI",   color: ChatProvider.google.accentHex,
              category: .ai,        subtitle: "Chat",         icon: "magnifyingglass", source: .n8n),
        .init(id: "ai_openai",           name: "OpenAI",      color: ChatProvider.openai.accentHex,
              category: .ai,        subtitle: "Chat",         icon: "circle.hexagongrid.fill", source: .n8n),
        .init(id: "ai_ollama",           name: "Ollama",      color: ChatProvider.ollama.accentHex,
              category: .ai,        subtitle: "Chat",         icon: "cpu", source: .n8n),
        .init(id: "ai_lmstudio",         name: "LM Studio",   color: ChatProvider.lmstudio.accentHex,
              category: .ai,        subtitle: "Chat",         icon: "desktopcomputer", source: .n8n),
        // ── Services ─────────────────────────────────────────────────────────
        .init(id: "integration_resend",  name: "Resend",      color: "#22C55E",
              category: .service,   subtitle: "Integration",  icon: "envelope.fill", source: .n8n),
        .init(id: "integration_n8n",     name: "n8n",         color: "#F29B38",
              category: .service,   subtitle: "Integration",  icon: "arrow.triangle.branch", source: .n8n),
        .init(id: "integration_vercel",  name: "Vercel",      color: "#7C5CFF",
              category: .service,   subtitle: "Integration",  icon: "triangle.fill", source: .n8n),
        .init(id: "integration_github",  name: "GitHub",      color: "#F4505E",
              category: .service,   subtitle: "Integration",  icon: "curlybraces", source: .n8n),
        .init(id: "integration_notion",  name: "Notion",      color: "#8C8C8C",
              category: .service,   subtitle: "Integration",  icon: "note.text", source: .n8n),
        .init(id: "integration_calcom",  name: "Cal.com",     color: "#C9956A",
              category: .service,   subtitle: "Integration",  icon: "calendar", source: .n8n),
        .init(id: "integration_stripe",  name: "Stripe",      color: "#0570DE",
              category: .service,   subtitle: "Integration",  icon: "creditcard.fill", source: .n8n),
        .init(id: "integration_music",   name: "Now Playing", color: "#FA2D48",
              category: .service,   subtitle: "Integration",  icon: "music.note", source: .n8n, githubOnly: true),
        .init(id: "integration_mattermost", name: "Mattermost", color: "#1B6FF3",
              category: .service,   subtitle: "Messages",     logo: .mattermost, source: .n8n, githubOnly: true),
        .init(id: "integration_clickmassa", name: "ClickMassa", color: MessageSource.clickMassa.accentHex,
              category: .service,   subtitle: "Messages",     logo: .clickMassa, source: .n8n, githubOnly: true),
    ]

    /// Pills available in the current build target.
    static var available: [PillDefinition] {
        #if APPSTORE
        all.filter { !$0.githubOnly }
        #else
        all
        #endif
    }

    /// Default ID for the always-on main workspace pill.
    static let defaultMainPillId = "integration_claude"

    /// Looks up a definition by task ID (nil if not in catalog).
    static func definition(for id: String) -> PillDefinition? {
        all.first { $0.id == id }
    }
}
