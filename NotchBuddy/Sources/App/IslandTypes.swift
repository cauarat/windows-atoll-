import Foundation

// MARK: - Island Mode

enum IslandMode: String, CaseIterable {
    case hidden, compact, expanded
}

// MARK: - Island View

enum IslandView: String, CaseIterable {
    case overview, empty, approval, question, error, finished
    case confused, upload, uploading, choose, mail, prompt
    case searching, result, note, greeting
    case message, agents
    /// What is waiting from one service, newest first.
    case messages
    /// A site, opened from a button on the island's border.
    case web
    /// Not a tab: the geometry Home takes while it is holding the player.
    ///
    /// The player lives in the Now Playing section now rather than a view of its
    /// own, but `viewLayouts` is keyed by this enum and read through a
    /// force-unwrap, so the measurements still need a key. `layoutTwin` is what
    /// points Home at it.
    case media
    /// The integration pills, moved off Home so it shows one thing.
    /// Focus and break countdowns.
    case timer
    /// The ChatGPT website in the island. Gated out of the App Store build entirely, so a
    /// leak of the feature is a compile error rather than a shipped surprise. Safe to gate:
    /// nothing in the app constructs an IslandView from its raw value.
    #if !APPSTORE
    case webchat
    #endif

}

// MARK: - AI Agents icon visibility

// MARK: - Bot State

enum BotState: String, CaseIterable {
    case idle, working, thinking, searching
    case approval, question, error, finished
    case ratelimit, sleeping, dizzy
}

// MARK: - Bot Emote

enum BotEmote: String, CaseIterable {
    case love, surprised, proud, wink, yawn, happy, annoyed
}

// MARK: - Approval info (pending PermissionRequest from Claude Code)

struct ApprovalInfo: Sendable {
    var sessionId: String
    var tool: String
    var command: String
    /// tool_input serialized to JSON with sortedKeys, "" if absent — used to match PostToolUse.
    var inputKey: String
    /// Pill that owns this approval: "integration_claude", "agent_cursor", or "agent_codex".
    var pillId: String
}

// MARK: - Pill badge (shown on pill edge when non-focused task has an alert)

enum PillBadge { case approval, finished, error }

// MARK: - Agent Task

struct AgentTask: Identifiable, Equatable {
    var id: String
    var name: String
    var color: String          // hex
    var state: BotState
    var stepIndex: Int = 0
    var steps: [String]
    var source: AgentSource
    var isIntegration: Bool = false  // true for persistent integration pills
    var emote: BotEmote? = nil
    var miniEye: EyeShape? = nil
    var pillBadge: PillBadge? = nil  // alert badge shown on pill when not focused
    var sessionCwd: String?  = nil  // last known working directory (Claude Code sessions)
    var finalLine: String?   = nil  // last assistant message shown as static text after Stop
}

enum AgentSource: Equatable {
    case claudeCode
    case n8n
    case agent   // third-party agent via coucou_agent field
}

// MARK: - Chat provider

enum ChatProvider: String, CaseIterable, Codable {
    case anthropic = "anthropic"
    case google    = "google"
    case openai    = "openai"
    case ollama    = "ollama"
    case lmstudio  = "lmstudio"

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .google:    "Google"
        case .openai:    "OpenAI"
        case .ollama:    "Ollama"
        case .lmstudio:  "LM Studio"
        }
    }

    var accentHex: String {
        switch self {
        case .anthropic: "#E07950"
        case .google:    "#4285F4"
        case .openai:    "#10A37F"
        case .ollama:    "#FACC15"
        case .lmstudio:  "#A3E635"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: "claude-sonnet-4-6"
        case .google:    "gemini-2.0-flash"
        case .openai:    "gpt-4o"
        case .ollama:    "llama3.2"
        case .lmstudio:  "local-model"
        }
    }

    var keychainKey: String {
        switch self {
        case .anthropic: "anthropic-api-key"
        case .google:    "google-api-key"
        case .openai:    "openai-api-key"
        case .ollama:    ""
        case .lmstudio:  ""
        }
    }

    var isLocal: Bool {
        self == .ollama || self == .lmstudio
    }

}

// MARK: - View dimensions (from VIEWS in prototype)

struct ViewLayout {
    let height: CGFloat
    let botX: CGFloat
    let botY: CGFloat?         // nil = auto-centered
    let botDiameter: CGFloat
    let agentMode: AgentLayoutMode

    /// How wide this view wants the island. 640 — the width every card in the
    /// app is laid out against — unless a view says otherwise, which is why
    /// every row that shipped is silent here.
    var width: CGFloat = IslandConst.expandedWidth

    /// `.large` means the numbers above are floors and the real size is the one
    /// the user chose. A view holding a month of agenda is not a card, and
    /// writing a number for it in this table would make the preference a lie.
    var sizeClass: IslandSizeClass = .standard
}

/// Whether a view is a card or a screen.
enum IslandSizeClass: String, Codable {
    case standard, large
}

enum AgentLayoutMode {
    case none, grid, pills, column
}

// MARK: - Constants (from NW, NH, EW in prototype)

enum IslandConst {
    static let notchWidth: CGFloat  = IslandScreenGeometry.fallbackNotchWidth
    static let notchHeight: CGFloat = 32
    static let expandedWidth: CGFloat = 640

    /// What a `.large` view gets when the user has not said otherwise, and the
    /// top of `AppState.largeWidthRange`. Sized against a 1512x982 display:
    /// the island stays an overlay hanging from the notch rather than growing
    /// into a window.
    static let defaultLargeSize = CGSize(width: 600, height: 650)
    static let earRadius: CGFloat   = 14

    /// The cards inside the island.
    ///
    /// Black, like the island itself, so the content reads as part of the notch
    /// rather than as a panel sitting inside one. Named once because four files
    /// drew this surface independently and a shade is exactly the kind of thing
    /// that drifts.
    static let cardHex = "#000000"

    /// How much room at the top of the screen other windows leave for the
    /// island. Deliberately not the panel's height: the panel is far taller
    /// than the island ever is, so that buttons and particles have somewhere to
    /// live, and a window that cleared *it* would sit absurdly low.
    static let topReservation: CGFloat = 320
    static let roundedCorner: CGFloat = 14    // hidden/peek/compact
    static let expandedCorner: CGFloat = 22



    private static let fixedViewLayouts: [IslandView: ViewLayout] = [
        // Home is the reference: height 150
        .overview:  ViewLayout(height: 160, botX: 68,  botY: nil, botDiameter: 58, agentMode: .pills),
        // All non-chat views match home height (150) — law
        .empty:     ViewLayout(height: 160, botX: 70,  botY: nil, botDiameter: 62, agentMode: .none),
        .approval:  ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 56, agentMode: .column),
        .question:  ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 56, agentMode: .column),
        .error:     ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 58, agentMode: .column),
        .finished:  ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 58, agentMode: .column),
        .confused:  ViewLayout(height: 160, botX: 76,  botY: nil, botDiameter: 66, agentMode: .column),
        .upload:    ViewLayout(height: 176, botX: 140, botY: 104, botDiameter: 62, agentMode: .column),
        .uploading: ViewLayout(height: 176, botX: 46,  botY: 118, botDiameter: 20, agentMode: .none),
        .choose:    ViewLayout(height: 176, botX: 60,  botY: 101, botDiameter: 52, agentMode: .column),
        .mail:      ViewLayout(height: 240, botX: 56,  botY: nil, botDiameter: 46, agentMode: .column),
        .prompt:    ViewLayout(height: 160, botX: 52,  botY: nil, botDiameter: 44, agentMode: .column),
        .searching: ViewLayout(height: 160, botX: 52,  botY: nil, botDiameter: 44, agentMode: .column),
        .result:    ViewLayout(height: 160, botX: 52,  botY: nil, botDiameter: 44, agentMode: .column),
        .note:      ViewLayout(height: 160, botX: 60,  botY: nil, botDiameter: 50, agentMode: .column),
        // Three rows — who, body, reply — inside the same 160 as every other
        // non-chat view.
        // Both message views park the shared Mochi: each message carries its
        // own, small, where the source's dot used to be, so there is nobody in
        // the gutter and the card gets the width back.
        .message:   ViewLayout(height: 160, botX: 0,   botY: nil, botDiameter: 0,  agentMode: .column),
        // The one view that is a stack rather than a card, at mail's height:
        // a list nobody can scroll through is only the card again.
        // 300, not 240: a list nobody can scroll through is only the card again,
        // and 240 paid for its header and padding out of the rows. 300 holds
        // four or five and shows the scrollbar from there — a fixed height
        // rather than one that follows the count, because the island is only
        // resized when the view or the mode changes, so a height that tracked
        // the queue would be right until the next message arrived.
        .messages:  ViewLayout(height: 300, botX: 0,   botY: nil, botDiameter: 0,  agentMode: .column),
        // Greeting: bot drawn by GreetingCanvasView; no BotPlacement needed
        .greeting:  ViewLayout(height: 150, botX: 320, botY: 90,  botDiameter: 0,  agentMode: .none),
        // Media: what Home measures itself by while the player is on it — see
        // `layoutTwin`. `botDiameter: 0` hides Mochi, the way greeting does,
        // which frees the 108 pt gutter every other card pads around by hand;
        // that is exactly where the album artwork goes, with Mochi's mini self
        // on its corner. Taller than the 160 pt law because the card is
        // artwork, two lines, a scrubber and transport.
        .media:     ViewLayout(height: 190, botX: 0,   botY: nil, botDiameter: 0,  agentMode: .none),
        // Integrations: the pills, with room for all of them rather than the
        // Timer: presets or a running countdown, inside the same 160 as the
        // other non-chat views.
        // Taller than the 160 law: the tiles, their labels and the buttons do
        // not fit in it, and the presets sit beside them.
        .timer:     ViewLayout(height: 190, botX: 54, botY: nil, botDiameter: 46, agentMode: .none),
        // The site is a screen, not a card: it takes the size the user chose
        // for large views rather than a number written here. Mochi steps out
        // of it — `botDiameter: 0`, the way greeting and media already do.
        .web:       ViewLayout(height: 600, botX: 0,  botY: 0,   botDiameter: 0,  agentMode: .none,
                               width: IslandConst.defaultLargeSize.width, sizeClass: .large),
        // The AI Agents dashboard is the one view that breaks the 160 law: it
        // stacks seven cards and scrolls. No Mochi and no left gutter, so the
        // cards run the full width.
        .agents:    ViewLayout(height: 560, botX: 0,   botY: nil, botDiameter: 0,  agentMode: .none),
    ]

    /// Every view's layout. `viewLayouts[view]!` is force-unwrapped by `islandSize` and
    /// `botPosition`, so a case missing here is a crash, not a fallback.
    static let viewLayouts: [IslandView: ViewLayout] = {
        var m = fixedViewLayouts
        #if !APPSTORE
        // A website fills the card, so Mochi moves to the header strip (y 8...42, centre 25)
        // in the gap right of the tabs (x 14...114), rather than keeping the chat's 84pt
        // gutter. Same trick as .uploading, which rides a 20pt Mochi at a fixed point.
        // A screen, like the site view it sits beside: it fills its card and draws its own
        // header, so there is no shared gutter for Mochi and the layout carries none.
        m[.webchat] = ViewLayout(height: IslandConst.defaultLargeSize.height, botX: 0, botY: 0,
                                 botDiameter: 0, agentMode: .none,
                                 width: IslandConst.defaultLargeSize.width, sizeClass: .large)
        #endif
        return m
    }()

    // Project colors — keyed by lowercase display name or slug
    static let projectColors: [String: String] = [
        "korus":             "#FF5A4E",
        "sbe hub":           "#2EC4A0",
        "morning ai brief":  "#F29B38",
        "publication ig":    "#7C5CFF",
        "ig post":           "#7C5CFF",
        "louisraille.fr":    "#38BDF8",
        "louisraille":       "#38BDF8",
        "notch buddy":       "#EC4899",
        "notch-buddy":       "#EC4899",
        "notchbuddy":        "#EC4899",
    ]

    static let fallbackColors = ["#22C55E", "#EAB308", "#60A5FA", "#E879F9"]

    /// Returns the fixed project color for a display name, or a stable fallback.
    static func colorForProject(_ name: String) -> String {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let c = projectColors[key] { return c }
        // partial match (e.g. "korus-api" → "korus")
        for (k, c) in projectColors where key.hasPrefix(k) || key.contains(k) { return c }
        return fallbackColors[abs(name.hashValue) % fallbackColors.count]
    }

    // State card wash colors (radial gradient from bottom)
    static let washColors: [IslandView: String] = [
        .approval:  "rgba(245,165,36,0.42)",
        .question:  "rgba(34,211,238,0.38)",
        .error:     "rgba(244,80,94,0.55)",
        .finished:  "rgba(52,211,153,0.5)",
        .confused:  "rgba(244,114,182,0.55)",
        .searching: "rgba(99,102,241,0.5)",
        .result:    "rgba(52,211,153,0.22)",
        .prompt:    "rgba(99,102,241,0.22)",
        .message:   "rgba(99,102,241,0.38)",
        .messages:  "rgba(99,102,241,0.38)",
    ]
}

extension IslandView {
    /// A screen rather than a card: somewhere the user went, which takes the
    /// size they chose and stays until they leave it.
    ///
    /// The same `.large` the layout table already uses, read back as a question
    /// about behaviour. `AppState.viewHoldsIslandOpen` is this plus "and the
    /// island is actually open on it".
    var isScreen: Bool { IslandConst.viewLayouts[self]?.sizeClass == .large }

    /// Which view's layout this one is measured by.
    ///
    /// Home is the only one that varies: it can be holding the timer, and the
    /// timer needs the room its own tab gets. Expressed as a twin rather than a
    /// second height table so geometry, the Mochi placement and the tall-view
    /// rule all agree without each remembering the exception.
    func layoutTwin(home: HomeContent, player: Bool = false) -> IslandView {
        guard self == .overview else { return self }
        if home == .timer { return .timer }
        // Home holding the player takes the player's geometry: 190 pt for the
        // artwork, and `botDiameter: 0` so the big Mochi steps out — his mini
        // self is on the artwork's corner instead. Both come back on their own
        // when nothing is loaded, which is the empty card.
        if player { return .media }
        // Home wearing a message face is the message card, so it takes the
        // message card's geometry — `botDiameter: 0` above all, because that
        // card carries its own small Mochi in the who-row now and the big one
        // would stand in front of the text the gutter used to keep clear of
        // him. Same borrowing as the player, for the same reason.
        switch home {
        case .notifications, .automatic, .clickMassa, .mattermost: return .message
        case .timer, .claudeCode: return self
        }
    }

    /// How tall a reply card has to be to show what is attached to it.
    ///
    /// 160 with nothing staged, which is the height the card has always had and
    /// the one every other non-chat view keeps. A chip row is only ever one row
    /// — the chips scroll sideways rather than wrapping — so this is a single
    /// step, not a per-file sum, and `.prompt`'s growth-by-count is not the
    /// pattern here.
    ///
    /// Deliberately the only place the number lives. `.prompt` has its formula
    /// copied into four files that must agree, and one of them being wrong is
    /// how Mochi ends up floating outside the card.
    static func messageHeight(attachmentCount: Int, notice: Bool) -> CGFloat {
        let base = IslandConst.viewLayouts[.message]?.height ?? 160
        guard attachmentCount > 0 else { return base }
        return base + chipRowHeight + (notice ? noticeHeight : 0)
    }

    /// A 26 pt row of chips plus the 6 pt the card puts between its rows.
    static let chipRowHeight: CGFloat = 32
    /// One line of small red text, when a file was turned away.
    static let noticeHeight: CGFloat = 14
}
