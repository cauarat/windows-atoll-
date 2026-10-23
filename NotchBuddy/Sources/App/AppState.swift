import Foundation
import SwiftUI
import Combine
import Synchronization

/// The master switch, as the background work sees it.
///
/// The seven pollers and `HookServer.handleClient` all run off the main actor.
/// Hopping to it just to ask whether to run would be wasteful everywhere and,
/// in the hook's case, would introduce exactly the delay the hook exists to
/// avoid. `AppState.isEnabled` is the source of truth; this follows it.
private let masterEnabledGate = Atomic<Bool>(true)


@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// The master switch. Off: no island, no pollers, no sound, and Claude Code
    /// is answered at once so a session is never left waiting.
    @Published var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "coucouEnabled")
            masterEnabledGate.store(isEnabled, ordering: .relaxed)
        }
    }

    /// Readable from any thread, for the work that runs off the main actor.
    nonisolated static var isEnabledNow: Bool {
        masterEnabledGate.load(ordering: .relaxed)
    }

    // Island state
    @Published var mode: IslandMode = .hidden
    @Published var view: IslandView = .overview

    // Tasks
    @Published var tasks: [AgentTask] = []
    @Published var focusId: String? = nil

    // Bot state override
    @Published var stateOverride: BotState? = nil

    /// Display UUIDs Mochi may appear on. Empty means every display.
    ///
    /// Keyed by `IslandDisplays.identifier(for:)`, which is the ColorSync UUID
    /// rather than the `CGDirectDisplayID`: the latter is handed out afresh on
    /// every reconnect, so a preference written with it would stop matching the
    /// moment the monitor was unplugged.
    @Published var displaySelection: Set<String> = [] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(displaySelection)) {
                UserDefaults.standard.set(data, forKey: "displaySelection")
            }
        }
    }

    /// Resting height on a display with a notch, in points. `nil` measures the
    /// cutout, which is what it has always done.
    @Published var notchDisplayHeight: CGFloat? = nil {
        didSet { Self.store(notchDisplayHeight, forKey: "notchDisplayHeight") }
    }

    /// Resting height on a display without a notch. The measured bar is 24 pt
    /// tall and 80 wide, which is a small thing to find with a pointer.
    @Published var plainDisplayHeight: CGFloat? = nil {
        didSet { Self.store(plainDisplayHeight, forKey: "plainDisplayHeight") }
    }

    /// Whether the AI Agents panel is offered.
    ///
    /// Off by default, and that is not timidity. Turning it on reads a file in
    /// the home directory and puts an account name on screen; in an app that
    /// promises no telemetry that should never happen without somebody asking
    /// for it. Off, nothing is read and no watcher is scheduled.
    @Published var showAgentsPanel: Bool = false {
        didSet { UserDefaults.standard.set(showAgentsPanel, forKey: "showAgentsPanel") }
    }

    /// The wheel on the mouse: both buttons together opens it.
    @Published var radialEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(radialEnabled, forKey: "radialEnabled")
            if radialEnabled { RadialChordTap.shared.start() }
            else { RadialChordTap.shared.stop() }
        }
    }

    /// Set when the tap could not be created. The permission was refused or
    /// taken away; trust this over `AXIsProcessTrusted`, which lags a revoke.
    @Published var radialTapFailed: Bool = false

    /// The wedges, in order. Unknown names are dropped on load, so removing an
    /// action in a later version cannot leave a wheel that will not open.
    @Published var radialSlots: [String] = RadialAction.defaults.map(\.rawValue) {
        didSet {
            if let d = try? JSONEncoder().encode(radialSlots) {
                UserDefaults.standard.set(d, forKey: "radialSlots")
            }
        }
    }

    var radialActions: [RadialAction] { radialSlots.compactMap(RadialAction.init(rawValue:)) }

    /// How big a `.large` view gets. `nil` takes the designed size.
    @Published var largeIslandWidth: CGFloat? = nil {
        didSet { Self.store(largeIslandWidth, forKey: "largeIslandWidth") }
    }
    @Published var largeIslandHeight: CGFloat? = nil {
        didSet { Self.store(largeIslandHeight, forKey: "largeIslandHeight") }
    }

    /// What a `.large` view actually gets.
    var largeIslandSize: CGSize {
        CGSize(width:  largeIslandWidth  ?? IslandConst.defaultLargeSize.width,
               height: largeIslandHeight ?? IslandConst.defaultLargeSize.height)
    }

    static let largeWidthRange:  ClosedRange<CGFloat> = 360...600
    static let largeHeightRange: ClosedRange<CGFloat> = 240...800

    /// Range the sliders offer, and what the toggles start from.
    static let notchHeightRange: ClosedRange<CGFloat> = 32...60
    static let plainHeightRange: ClosedRange<CGFloat> = 22...60
    static let defaultCustomNotchHeight: CGFloat = 40
    static let defaultCustomPlainHeight: CGFloat = 32

    /// `nil` has to round-trip, so the key is removed rather than written as 0.
    private static func store(_ value: CGFloat?, forKey key: String) {
        if let value { UserDefaults.standard.set(Double(value), forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    /// The island's measurements for the display it is currently on.
    ///
    /// Published, and that matters: these used to be three plain stored
    /// properties, which was fine while they were written once before the first
    /// frame. They now change whenever the island moves to another display or a
    /// height preference moves, and a plain property on an ObservableObject
    /// redraws nothing — so the sliders did nothing and, after a move, the
    /// island was still drawn with the previous screen's size while the hit test
    /// already used the new one. Drawn in one place, clickable in another.
    @Published var screenGeometry = IslandScreenGeometry(
        screenWidth: 0, safeAreaTop: IslandConst.notchHeight,
        auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil,
        menuBarHeight: IslandConst.notchHeight
    )

    // Real notch dimensions, read from the geometry above so the call sites that
    // already use them keep working.
    var notchWidth:  CGFloat { screenGeometry.width }
    var notchHeight: CGFloat { screenGeometry.height }
    var hasNotch: Bool { screenGeometry.hasNotch }

    /// Island size for the site view — as much of the screen as it can have.
    /// Measured by IslandWindowController, which also grows the panel to match.

    // Last app active before NotchBuddy (for window context capture)
    var lastExternalApp: NSRunningApplication? = nil

    // Bot drag-attach state (hides original bot while ghost follows cursor)
    @Published var isDraggingBot: Bool = false

    /// The island's left edge in screen coordinates, as the controller last
    /// placed it.
    ///
    /// Mochi's eyes follow the pointer, which means working out how far away it
    /// is — and that stopped being "the middle of the screen" the moment the
    /// island could be dropped anywhere.
    var islandScreenMinX: CGFloat = 0

    // Mouse tracking
    var mousePosition: CGPoint = .zero
    var lastMouseMove: Date = .now
    var lastActivity: Date = .now
    var isPresent: Bool = true

    // Pinned (alerts that stay open, never auto-close)
    var isPinned: Bool = false

    /// Seconds a notification stays open, by default.
    static let defaultAutoClose: TimeInterval = 5
    /// Values this preference defaulted to before it meant "how long a
    /// notification stays up". Migrated on load; see `autoCloseInterval`.
    static let supersededAutoClose: Set<TimeInterval> = [15, 60]

    /// When the island will fold a notification away, or nil if nothing is
    /// counting down. Mirrors the FSM's hold timer so the countdown hairline can
    /// draw it; the controller clears it the moment the pointer arrives.
    var holdingUntil: Date?

    /// Someone has the cursor in the message card's reply field.
    ///
    /// Separate from `isPinned`, which any view may set and the controller
    /// clears on its own: this one feeds `fsm.isHeldOpen`, so the auto-close
    /// timer cannot take a half-written sentence away mid-word.
    var isReplying: Bool = false

    /// A message is half-written in the built-in chat, or its answer is still
    /// coming.
    ///
    /// The chat's own field, unlike the reply box, never set `isReplying` — so
    /// the pointer leaving the island folded the card 0.12 s later and took the
    /// sentence with it. Fed to `fsm.holdsHomeOpen` rather than `isHeldOpen`:
    /// the chat stays while it is being used, and Escape and the tabs still
    /// close it.
    var chatInProgress: Bool = false

    /// A file picker is up for the reply box.
    ///
    /// `NSOpenPanel` takes the keyboard, which drops `isReplying`, which would
    /// let the auto-close timer fold the card away while the user is still
    /// choosing — and take the draft and the other attachments with it. Held
    /// alongside `isReplying` in `fsm.isHeldOpen` for exactly that reason.
    var isPickingFile: Bool = false

    /// Files staged on the reply being written, in the order they arrived.
    ///
    /// Deliberately not `droppedFile`: that one belongs to the upload → choose
    /// flow and survives it, while these live only until the reply is sent or
    /// the card is dismissed.
    @Published var replyAttachments: [ReplyAttachment] = []

    /// A file is hovering over an open reply box, rather than over the notch
    /// with nothing to catch it. Drives the chip row's highlight; the bin morph
    /// deliberately does not run for this one.
    @Published var replyDragOver: Bool = false

    /// Why the last file was turned away, or nil. One line, shown under the
    /// chips and cleared as soon as the staged set changes.
    @Published var replyNotice: String? = nil

    // Upload progress (0-1) — set to 1.0 only at completion; animation is time-based
    @Published var uploadProgress: Double = 0

    // Upload animation timing (non-published — TimelineViews read these directly)
    var uploadStartTime: Date?
    var uploadDuration: Double = 2.4

    // File drag-over state (mailbox morph glow + mouth spring)
    @Published var fileDragOver: Bool = false

    // Sound enabled — persisted
    @Published var soundEnabled: Bool = true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }

    /// Whether an arriving Mattermost or ClickMassa message also gets a macOS
    /// notification banner — persisted.
    ///
    /// On by default: the notch card is easy to miss behind a full-screen
    /// window or on another display, and a message nobody saw is the one case
    /// where staying out of the way is the wrong answer.
    @Published var messageBanners: Bool = true {
        didSet { UserDefaults.standard.set(messageBanners, forKey: "messageBanners") }
    }

    /// How far the player's two skip buttons jump, in seconds — persisted.
    ///
    /// Apart, because they are not one setting: thirty seconds forward skips
    /// an ad, and ten back is catching the sentence you missed. Ten each is
    /// what the video players everyone already uses default to.
    ///
    /// `NowPlayingCardView` writes the number onto the button, so these are
    /// also a label. SF Symbols draws the numbered dial for 5, 10, 15, 30, 45,
    /// 60, 75 and 90; anything else gets the plain dial with the number
    /// written on, which is why `skipSecondsRange` is wider than that list.
    @Published var skipBackSeconds: Int = 10 {
        didSet { UserDefaults.standard.set(skipBackSeconds, forKey: "skipBackSeconds") }
    }
    @Published var skipForwardSeconds: Int = 10 {
        didSet { UserDefaults.standard.set(skipForwardSeconds, forKey: "skipForwardSeconds") }
    }
    /// A skip longer than two minutes is a scrub, and the bar is better at it.
    static let skipSecondsRange = 1...120

    static func clampSkip(_ seconds: Int) -> Int {
        min(max(seconds, skipSecondsRange.lowerBound), skipSecondsRange.upperBound)
    }

    // Claude model used by the chat and the search — persisted
    static let defaultClaudeModel = "claude-sonnet-4-6"
    @Published var claudeModel: String = AppState.defaultClaudeModel {
        didSet { UserDefaults.standard.set(claudeModel, forKey: "claudeModel") }
    }

    // In-chat provider + model — picked via the model selector in the prompt view
    /// Where the island sits: one of the six names, or `free:fx,fy` for an
    /// island that was held and dragged somewhere of its own.
    ///
    /// A string rather than an enum, and one field rather than two, because the
    /// Windows and Linux preference is the same string — see IslandAnchor.swift
    /// and windows/src/core/anchor.ts. Anything unrecognised resolves to the
    /// default, so a value written by a newer build leaves the island somewhere
    /// reachable instead of nowhere.
    @Published var islandPosition: String = IslandAnchor.defaultPosition {
        didSet {
            UserDefaults.standard.set(islandPosition, forKey: "islandPosition")
            NotificationCenter.default.post(name: .islandPositionChanged, object: nil)
        }
    }

    @Published var chatProvider: ChatProvider = .anthropic {
        didSet { UserDefaults.standard.set(chatProvider.rawValue, forKey: "chatProvider") }
    }
    @Published var googleChatModel: String = ChatProvider.google.defaultModel {
        didSet { UserDefaults.standard.set(googleChatModel, forKey: "googleChatModel") }
    }
    @Published var openAIChatModel: String = ChatProvider.openai.defaultModel {
        didSet { UserDefaults.standard.set(openAIChatModel, forKey: "openAIChatModel") }
    }
    @Published var ollamaChatModel: String = ChatProvider.ollama.defaultModel {
        didSet { UserDefaults.standard.set(ollamaChatModel, forKey: "ollamaChatModel") }
    }
    @Published var lmstudioChatModel: String = ChatProvider.lmstudio.defaultModel {
        didSet { UserDefaults.standard.set(lmstudioChatModel, forKey: "lmstudioChatModel") }
    }
    @Published var ollamaServerURL: String = "" {
        didSet { UserDefaults.standard.set(ollamaServerURL, forKey: "ollamaServerURL") }
    }
    @Published var lmstudioServerURL: String = "" {
        didSet { UserDefaults.standard.set(lmstudioServerURL, forKey: "lmstudioServerURL") }
    }

    /// What the Home tab shows. Defaults to the two messaging integrations
    /// taking turns — see `HomeContent`.
    @Published var homeContent: HomeContent = .notifications {
        didSet { UserDefaults.standard.set(homeContent.rawValue, forKey: "homeContent") }
    }

    // The always-on workspace pill (default: VS Code). Persisted.

    // Dynamically fetched model lists for the in-chat picker (keyed by provider)
    @Published var fetchedProviderModels: [ChatProvider: [(id: String, label: String)]] = [:]
    @Published var providerModelFetchError: [ChatProvider: String] = [:]
    @Published var loadingProviderModels: Set<ChatProvider> = []

    /// Fetches models for `provider` if not already loaded or loading.
    /// Sets `providerModelFetchError` if the key is absent or the request fails.
    func fetchModelsIfNeeded(for provider: ChatProvider) {
        guard !loadingProviderModels.contains(provider),
              fetchedProviderModels[provider] == nil else { return }
        // Local providers: fetch from server URL (no API key needed)
        if provider.isLocal {
            let baseURL = provider == .ollama ? ollamaServerURL : lmstudioServerURL
            let normalised = LocalChat.normaliseURL(baseURL)
            guard !normalised.isEmpty else {
                providerModelFetchError[provider] = provider == .ollama
                    ? "Connect Ollama in Settings → Chat first."
                    : "Connect LM Studio in Settings → Chat first."
                return
            }
            loadingProviderModels.insert(provider)
            providerModelFetchError.removeValue(forKey: provider)
            Task {
                let result = await LocalChat.fetchModelsResult(baseURL: normalised)
                loadingProviderModels.remove(provider)
                switch result {
                case .success(let models) where models.isEmpty:
                    providerModelFetchError[provider] = provider == .ollama
                        ? "No models yet. Download one in Ollama first."
                        : "No models yet. Download one in LM Studio first."
                case .success(let models):
                    fetchedProviderModels[provider] = models
                    let current = provider == .ollama ? ollamaChatModel : lmstudioChatModel
                    if !models.contains(where: { $0.id == current }) {
                        let first = models.first!.id
                        if provider == .ollama { ollamaChatModel = first }
                        else                   { lmstudioChatModel = first }
                    }
                case .failure:
                    providerModelFetchError[provider] = "Cannot reach \(normalised). Is the server running?"
                }
            }
            return
        }
        // Remote providers: require API key
        guard let apiKey = KeychainStore.shared.get(provider.keychainKey), !apiKey.isEmpty else {
            providerModelFetchError[provider] = "No API key — add it in Settings."
            return
        }
        loadingProviderModels.insert(provider)
        providerModelFetchError.removeValue(forKey: provider)
        Task {
            let models: [(id: String, label: String)]
            switch provider {
            case .anthropic: models = await ClaudeService.fetchModels(apiKey: apiKey)
            case .google:    models = await ClaudeService.fetchGoogleModels(apiKey: apiKey)
            case .openai:    models = await ClaudeService.fetchOpenAIModels(apiKey: apiKey)
            case .ollama, .lmstudio: models = []  // handled above
            }
            loadingProviderModels.remove(provider)
            if models.isEmpty {
                providerModelFetchError[provider] = "Failed to load models. Check your API key."
            } else {
                fetchedProviderModels[provider] = models
                switch provider {
                case .anthropic:
                    if !models.contains(where: { $0.id == claudeModel }) {
                        claudeModel = models.first(where: { $0.id.contains("sonnet") })?.id ?? models.first!.id
                    }
                case .google:
                    if !models.contains(where: { $0.id == googleChatModel }) {
                        googleChatModel = models.first(where: { $0.id.contains("flash") })?.id ?? models.first!.id
                    }
                case .openai:
                    if !models.contains(where: { $0.id == openAIChatModel }) {
                        openAIChatModel = models.first(where: { $0.id.contains("mini") })?.id ?? models.first!.id
                    }
                case .ollama, .lmstudio: break
                }
            }
        }
    }

    /// The model currently active for chat (provider-aware).
    var activeChatModel: String {
        switch chatProvider {
        case .anthropic: return claudeModel
        case .google:    return googleChatModel
        case .openai:    return openAIChatModel
        case .ollama:    return ollamaChatModel
        case .lmstudio:  return lmstudioChatModel
        }
    }

    // Sound volume (0–0.2) — persisted, synced to SoundEngine
    @Published var soundVolume: Double = 0.12 {
        didSet {
            UserDefaults.standard.set(soundVolume, forKey: "soundVolume")
            SoundEngine.shared.volume = Float(soundVolume)
        }
    }

    // Context for prompt (window attach / file)
    @Published var promptContext: PromptContext? = nil

    // Dropped file (set during upload flow)
    @Published var droppedFile: DroppedFile? = nil

    /// Everything that came in on the same drop, `droppedFile` included.
    ///
    /// The flow still asks its question about the first one — a prompt or a
    /// mail is about a file, singular — but the label and the inbox copy
    /// account for all of them, which is what the spec's "3 fichiers" means.
    @Published var droppedFiles: [DroppedFile] = []

    /// What the upload views call what was dropped.
    var droppedLabel: String {
        droppedFiles.count > 1
            ? "\(droppedFiles.count) files"
            : (droppedFile?.name ?? "file")
    }

    // Short note message (shown in NoteView)
    @Published var noteMessage: String? = nil

    // Auto-close delay — persisted
    /// Seconds a notification holds the island open before folding away.
    /// Counted from the end of the open animation, so it is readable throughout.
    @Published var autoCloseInterval: TimeInterval = AppState.defaultAutoClose {
        didSet { UserDefaults.standard.set(autoCloseInterval, forKey: "autoCloseInterval") }
    }

    // Absence interval — persisted
    var absenceInterval: TimeInterval = 3 * 60 {
        didSet { UserDefaults.standard.set(absenceInterval, forKey: "absenceInterval") }
    }

    // Greeting threshold — how long hidden before greeting on reappear (default 2 min)
    var greetThresholdSeconds: TimeInterval = 120 {
        didSet { UserDefaults.standard.set(greetThresholdSeconds, forKey: "greetThreshold") }
    }

    // Hotkey to show island (e.g. ⌘⇧N)
    @Published var hotkeyEnabled: Bool = false {
        didSet { UserDefaults.standard.set(hotkeyEnabled, forKey: "hotkeyEnabled") }
    }
    var hotkeyFlags: UInt = NSEvent.ModifierFlags([.command, .shift]).rawValue {
        didSet { UserDefaults.standard.set(Int(hotkeyFlags), forKey: "hotkeyFlags") }
    }
    var hotkeyCode: UInt16 = 45 {  // 'n'
        didSet { UserDefaults.standard.set(Int(hotkeyCode), forKey: "hotkeyCode") }
    }

    /// Whether the characters are drawn at all.
    ///
    /// Not the master switch. Everything the island does it goes on doing —
    /// the player, the messages, the timer, the pills, a file you drop — and
    /// every card closes the gutter it was leaving for a face. Two places keep
    /// theirs: the compact bar, and the drop, where Mochi *is* the progress.
    @Published var hideCharacters: Bool = false {
        didSet { UserDefaults.standard.set(hideCharacters, forKey: "hideCharacters") }
    }

    // Which character each pill wears, and the one everything else gets.
    //
    // Keyed by pill id, which is a stable contract value, so a stored choice
    // survives renames of everything else. Not a field on AgentTask: those are
    // rebuilt from PillCatalog whenever a pill is toggled, and anything kept
    // there would be thrown away with them.
    @Published var pillCharacters: [String: MochiCharacter] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(pillCharacters) {
                UserDefaults.standard.set(data, forKey: "pillCharacters")
            }
        }
    }

    @Published var defaultCharacter = MochiCharacter() {
        didSet {
            UserDefaults.standard.set(defaultCharacter.storageString, forKey: "defaultCharacter")
        }
    }

    /// The character a given pill wears, falling back to the default.
    func character(for pillId: String?) -> MochiCharacter {
        guard let pillId else { return defaultCharacter }
        if let own = pillCharacters[pillId] { return own }
        // A pill may ship with a face of its own. Fallback only: a character
        // chosen for it still wins, and a pill without one goes on getting the
        // default exactly as before.
        return PillCatalog.definition(for: pillId)?.character ?? defaultCharacter
    }

    // Active integration pills (main workspace pill excluded). Max 4.
    /// What a fresh install starts with, and what a wiped-out upgrade falls
    /// back to. Named so both uses read the same list.
    static let defaultActiveIntegrations: Set<String> = [
        "integration_notifications", "integration_mattermost",
        "integration_clickmassa", "integration_music",
    ]

    @Published var activeIntegrations: Set<String> = AppState.defaultActiveIntegrations {
        didSet {
            if let data = try? JSONEncoder().encode(Array(activeIntegrations)) {
                UserDefaults.standard.set(data, forKey: "activeIntegrations")
            }
        }
    }

    /// The buttons hung off the island's edges, in the order they sit there.
    ///
    /// Deliberately independent of `activeIntegrations`. That set says which
    /// pills have a task and appear inside the island; this says what the
    /// pointer can reach without opening it, and the two are different
    /// questions — a pill you rarely need can still be worth a button, and
    /// `openPill` makes its task when it is first used. Keeping them apart is
    /// also what lets the ring ignore the cap of four the old pill rail left
    /// behind.
    ///
    /// `nil` means "not chosen yet" and is filled from the active pills on
    /// first use, so an existing install arrives with a sensible ring instead
    /// of an empty one.
    @Published var islandEdgeButtons: [IslandEdgeButton]? = nil {
        didSet {
            if let islandEdgeButtons, let data = try? JSONEncoder().encode(islandEdgeButtons) {
                UserDefaults.standard.set(data, forKey: "islandEdgeButtons")
            } else {
                UserDefaults.standard.removeObject(forKey: "islandEdgeButtons")
            }
        }
    }

    /// What the ring actually shows: the user's choice, or a default dealt from
    /// the pills they already made active.
    var edgeButtons: [IslandEdgeButton] {
        if let islandEdgeButtons { return islandEdgeButtons }
        let ordered = PillCatalog.available
            .map(\.id)
            .filter { activeIntegrations.contains($0) }
        return IslandEdgeLayout.defaults(pills: ordered)
    }

    // Pending API result
    @Published var searchResult: SearchResult? = nil

    // Chat conversation history
    @Published var chatHistory: [ChatMessage] = []

    // Pending approval request from Claude Code hook
    @Published var pendingApproval: ApprovalInfo? = nil

    // Pending AskUserQuestion from Claude Code hook
    @Published var pendingQuestion: AskQuestion? = nil

    // Per-pill flat list of FileDiffs, in order of reception.
    // Not @Published — steps[] changes already trigger redraws.
    var sessionDiffs: [String: [FileDiff]] = [:]
    private var sessionDiffTimers: [String: DispatchWorkItem] = [:]
    // Monotonically increasing — never reset, not even in clearSessionDiffs.
    private var nextDiffId: Int = 0

    @discardableResult
    func appendSessionDiff(_ diff: FileDiff, for pillId: String) -> Int {
        var d = diff
        d.id = nextDiffId
        nextDiffId += 1
        if sessionDiffs[pillId] == nil { sessionDiffs[pillId] = [] }
        sessionDiffs[pillId]!.append(d)
        // Keep at most 50 diffs per pill; drop oldest first
        while sessionDiffs[pillId]!.count > 50 {
            sessionDiffs[pillId]!.removeFirst()
        }
        resetSessionDiffTimer(for: pillId)
        return d.id
    }

    func clearSessionDiffs(for pillId: String) {
        sessionDiffTimers[pillId]?.cancel()
        sessionDiffTimers.removeValue(forKey: pillId)
        sessionDiffs.removeValue(forKey: pillId)
        // nextDiffId intentionally NOT reset — ids remain unique across sessions
    }

    /// Unique touched files for a pill, in first-touch order, with summed totals.
    func touchedFiles(for pillId: String) -> [(path: String, added: Int, removed: Int)] {
        guard let diffs = sessionDiffs[pillId] else { return [] }
        var seen: [String: (added: Int, removed: Int)] = [:]
        var order: [String] = []
        for d in diffs {
            if seen[d.path] == nil { order.append(d.path) }
            let p = seen[d.path] ?? (0, 0)
            seen[d.path] = (p.added + d.added, p.removed + d.removed)
        }
        return order.map { path in let t = seen[path]!; return (path, t.added, t.removed) }
    }

    private func resetSessionDiffTimer(for pillId: String) {
        sessionDiffTimers[pillId]?.cancel()
        // Scheduled on main, like every other DispatchWorkItem in the app.
        // This type is @MainActor, so the item's body is too, and Swift 6
        // checks that where it runs: an hour later, on a global queue, that
        // check would have taken the app down with it.
        let work = DispatchWorkItem { [weak self] in
            self?.clearSessionDiffs(for: pillId)
        }
        sessionDiffTimers[pillId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3600, execute: work)
    }

    #if !APPSTORE
    @Published var musicPlaying: Bool = false
    /// Something is loaded, playing or paused.
    ///
    /// Mirrored out of `MusicController` because geometry is decided from
    /// `AppState` — `homeShowsPlayer` below is read by the window controller and
    /// by `BotPlacement`, neither of which observes the controller.
    @Published var musicHasTrack: Bool = false
    @Published var musicAutomationDenied: Bool = false
    #endif

    // Claude plan gauge. Two sources now feed this; see applyPlanUsage.
    @Published var claudePlanUsage: PlanUsage? = nil {
        didSet {
            if let u = claudePlanUsage,
               let data = try? JSONEncoder().encode(u) {
                UserDefaults.standard.set(data, forKey: "claudePlanUsage")
            }
        }
    }

    #if !APPSTORE
    // Cached relay-installed state — updated at launch, after install/uninstall, on Settings open
    @Published var planRelayInstalled: Bool = false

    func refreshPlanRelayState() {
        planRelayInstalled = HookServer.statusLineInstalled()
    }

    /// Read Claude Code's own login token and ask Anthropic for the figures
    /// `/usage` shows.
    ///
    /// Off until asked for. The first read makes macOS put up a dialog naming
    /// Notchy and Claude Code's keychain item, and nobody should meet that
    /// cold. It is also the only route to these numbers for someone running the
    /// Claude Code desktop app, which never executes a status line.
    @Published var claudePlanAPIEnabled: Bool = false {
        didSet { UserDefaults.standard.set(claudePlanAPIEnabled, forKey: "claudePlanAPIEnabled") }
    }

    /// Set when the Keychain read was refused or the token rejected, so the
    /// poller stops rather than raising that dialog again every minute.
    ///
    /// Not persisted, on purpose. A Debug build is unsigned, so every rebuild is
    /// a stranger to the Keychain and the grant has to be given again; written
    /// to disk, one development-time Deny would become permanent.
    @Published var claudePlanAPIBlocked: Bool = false

    /// Whether anything at all can feed the plan gauges.
    ///
    /// The cards used to ask whether the relay was installed, from when that was
    /// the only source. What they actually want to know is whether a number can
    /// arrive — otherwise the ring shows 55 % while the card behind it offers to
    /// connect Claude Code.
    var planUsageConnected: Bool {
        planRelayInstalled || claudePlanAPIEnabled
    }

    /// The one way a reading gets in, from either source. Newest wins, whole.
    ///
    /// Not a per-window merge. Both sources report the same two windows as of
    /// one moment, so a record stitched from two of them would carry an
    /// `updatedAt` describing neither half, and the card's "2 min ago" line
    /// would be about nothing. Taking the newest whole gives the behaviour
    /// wanted without a special case: while a Claude Code terminal is running
    /// the relay fires every few seconds and simply stays ahead, the API carries
    /// it the rest of the time, and for someone who only uses the desktop app
    /// the API is the only source there has ever been.
    func applyPlanUsage(_ usage: PlanUsage) {
        if let current = claudePlanUsage,
           current.updatedAt > usage.updatedAt,
           // A clock that jumped forward once must not latch out every later
           // reading, so a stored timestamp from the future never wins.
           current.updatedAt <= Date() {
            return
        }
        claudePlanUsage = usage
    }

    // AI Agents dashboard — spend/tokens read from Claude Code's transcripts.
    // Nil until the dashboard has been opened at least once; the reader only
    // runs while that view is on screen.
    @Published var agentUsage: AgentUsageSnapshot? = nil
    @Published var agentUsageLoading: Bool = false

    #endif

    // ChatGPT website in the island. Off by default: nothing contacts OpenAI until the user
    // asks for it, which is what keeps "network calls only to services the user configured"
    // literally true.
    @Published var webChatEnabled: Bool = false {
        didSet { UserDefaults.standard.set(webChatEnabled, forKey: "webChatEnabled") }
    }
    /// When on, the chat tab opens the website instead of the built-in chat.
    @Published var useWebChat: Bool = false {
        didSet { UserDefaults.standard.set(useWebChat, forKey: "useWebChat") }
    }

    /// The view the chat tab should open.
    var chatTabView: IslandView {
        #if APPSTORE
        return .prompt
        #else
        return (webChatEnabled && useWebChat) ? .webchat : .prompt
        #endif
    }

    /// True while what is on the island is a screen rather than a card.
    ///
    /// A card is something that happened — it arrives, it is read, it folds
    /// away on its own. A screen is somewhere the user went: the site, the
    /// ChatGPT page. Nothing but the user may take one away, so this blocks
    /// every timer, every hold and every alert that would otherwise replace it
    /// mid-sentence. `closeScreen()` is the way out.
    ///
    /// Read from the layout table rather than listed here, because `.large` is
    /// already the word that table uses for exactly this distinction.
    ///
    /// Only while the island is open: a view left behind by a collapse must not
    /// keep holding a compact island that is no longer showing it.
    var viewHoldsIslandOpen: Bool { mode == .expanded && view.isScreen }

    /// The built-in chat is on screen with something in it — see
    /// `chatInProgress`.
    ///
    /// The view has to be asked for as well as the flag: `IslandContentView`
    /// builds every view at once, so the chat is alive behind Home and would
    /// otherwise go on holding the island open from a tab nobody is looking at.
    var chatHoldsIsland: Bool { view == .prompt && chatInProgress }

    // MARK: - Init (loads persisted settings)

    private init() {
        let ud = UserDefaults.standard

        if let v = ud.object(forKey: "coucouEnabled") as? Bool  { isEnabled    = v }
        if let v = ud.object(forKey: "soundEnabled") as? Bool   { soundEnabled = v }
        if let v = ud.object(forKey: "messageBanners") as? Bool { messageBanners = v }
        // Clamped on the way in: a number out of range would draw a button
        // that lies about where it lands.
        if let v = ud.object(forKey: "skipBackSeconds") as? Int {
            skipBackSeconds = Self.clampSkip(v)
        }
        if let v = ud.object(forKey: "skipForwardSeconds") as? Int {
            skipForwardSeconds = Self.clampSkip(v)
        }
        if let v = ud.object(forKey: "soundVolume")  as? Double { soundVolume  = v }
        if let v = ud.string(forKey: "claudeModel"),
           !v.trimmingCharacters(in: .whitespaces).isEmpty { claudeModel = v }
        if let v = ud.string(forKey: "chatProvider"), let p = ChatProvider(rawValue: v) { chatProvider = p }
        if let v = ud.string(forKey: "islandPosition"), !v.isEmpty { islandPosition = v }
        if let v = ud.string(forKey: "googleChatModel"), !v.isEmpty { googleChatModel = v }
        if let v = ud.string(forKey: "openAIChatModel"), !v.isEmpty { openAIChatModel = v }
        if let v = ud.string(forKey: "ollamaChatModel"), !v.isEmpty { ollamaChatModel = v }
        if let v = ud.string(forKey: "lmstudioChatModel"), !v.isEmpty { lmstudioChatModel = v }
        if let v = ud.string(forKey: "ollamaServerURL"), !v.isEmpty { ollamaServerURL = v }
        if let v = ud.string(forKey: "lmstudioServerURL"), !v.isEmpty { lmstudioServerURL = v }
        // Migrate old 60s default → 15s
        if let v = ud.object(forKey: "autoCloseInterval") as? Double {
            // 60 and 15 were both defaults back when this number also governed
            // how long the island lingered after the mouse left. The island now
            // follows the pointer, so this only has to be long enough to read a
            // notification — and nobody chose either of the old values.
            autoCloseInterval = AppState.supersededAutoClose.contains(v)
                ? AppState.defaultAutoClose : v
        }
        if let v = ud.object(forKey: "absenceInterval")   as? Double { absenceInterval   = v }
        if let v = ud.object(forKey: "greetThreshold")    as? Double { greetThresholdSeconds = v }
        if let v = ud.object(forKey: "hotkeyEnabled") as? Bool  { hotkeyEnabled = v }
        if let v = ud.object(forKey: "hotkeyFlags")   as? Int   { hotkeyFlags = UInt(v) }
        if let v = ud.object(forKey: "hotkeyCode")    as? Int   { hotkeyCode = UInt16(v) }
        if let v = ud.object(forKey: "notchDisplayHeight") as? Double { notchDisplayHeight = CGFloat(v) }
        if let v = ud.object(forKey: "plainDisplayHeight") as? Double { plainDisplayHeight = CGFloat(v) }
        if let v = ud.string(forKey: "homeContent"),
           let parsed = HomeContent(rawValue: v) { homeContent = parsed }
        if let d = ud.data(forKey: "displaySelection"),
           let a = try? JSONDecoder().decode([String].self, from: d) { displaySelection = Set(a) }
        if let d = ud.data(forKey: "activeIntegrations"),
           let a = try? JSONDecoder().decode([String].self, from: d) { activeIntegrations = Set(a) }
        if let d = ud.data(forKey: "pillCharacters"),
           let m = try? JSONDecoder().decode([String: MochiCharacter].self, from: d) {
            pillCharacters = m
        }
        if let v = ud.string(forKey: "defaultCharacter") {
            defaultCharacter = MochiCharacter(storage: v)
        }
        hideCharacters = ud.bool(forKey: "hideCharacters")
        showAgentsPanel = ud.bool(forKey: "showAgentsPanel")
        radialEnabled = ud.bool(forKey: "radialEnabled")
        if let d = ud.data(forKey: "radialSlots"),
           let a = try? JSONDecoder().decode([String].self, from: d) { radialSlots = a }
        // A size stored under an older build can sit outside the range the
        // slider now offers. Clamp on the way in, so the number in Settings and
        // the size the island actually takes never disagree.
        if ud.object(forKey: "largeIslandWidth") != nil {
            let w = CGFloat(ud.double(forKey: "largeIslandWidth"))
            largeIslandWidth = min(max(w, Self.largeWidthRange.lowerBound),
                                   Self.largeWidthRange.upperBound)
        }
        if ud.object(forKey: "largeIslandHeight") != nil {
            let h = CGFloat(ud.double(forKey: "largeIslandHeight"))
            largeIslandHeight = min(max(h, Self.largeHeightRange.lowerBound),
                                    Self.largeHeightRange.upperBound)
        }
        if let d = ud.data(forKey: "islandEdgeButtons"),
           let b = try? JSONDecoder().decode([IslandEdgeButton].self, from: d) { islandEdgeButtons = b }
        if let d = ud.data(forKey: "claudePlanUsage"),
           let u = try? JSONDecoder().decode(PlanUsage.self, from: d) { claudePlanUsage = u }
        #if !APPSTORE
        planRelayInstalled = HookServer.statusLineInstalled()
        claudePlanAPIEnabled = ud.bool(forKey: "claudePlanAPIEnabled")
        migrateAgentsSatelliteIntoRing(ud)
        #endif
        if let v = ud.object(forKey: "webChatEnabled") as? Bool { webChatEnabled = v }
        if let v = ud.object(forKey: "useWebChat") as? Bool { useWebChat = v }

        // Sync SoundEngine volume on launch
        SoundEngine.shared.volume = Float(soundVolume)

        // Always load integration pills
        loadIntegrationTasks()
    }

    #if !APPSTORE
    /// The sparkles satellite became an ordinary ring button, so that it could
    /// be moved, removed and added back like every other one. Without this,
    /// everyone who had it on screen would simply lose it on update and have
    /// no way to guess where it went.
    ///
    /// Runs once. It has to write `islandEdgeButtons` rather than nudge
    /// `edgeButtons`, which is computed — so for anyone still on the dealt
    /// default this also freezes that default, exactly as adding a button in
    /// Settings already does.
    private func migrateAgentsSatelliteIntoRing(_ ud: UserDefaults) {
        let done = "agentsDashboardInRing"
        guard !ud.bool(forKey: done) else { return }
        ud.set(true, forKey: done)

        // `whenAwake` is the default the satellite shipped with, so a missing
        // key means they had it. Only an explicit "never" opted out.
        guard ud.string(forKey: "agentsIconVisibility") != "never" else { return }

        let id = IslandEdgeAction.agentsDashboard.rawValue
        guard !edgeButtons.contains(where: { $0.action == id }) else { return }
        // Below the island, where the satellite always sat.
        islandEdgeButtons = edgeButtons + [IslandEdgeButton(id, .bottom)]
    }
    #endif

    // MARK: - Computed

    /// Home is holding the player, with something in it.
    ///
    /// Two routes reach the same card: Home on automatic while something plays,
    /// or the Now Playing pill in focus. Both need the taller geometry, and an
    /// empty player needs neither — it is one line of text, which fits the 160
    /// Home has always had and leaves Mochi in the gutter where every other
    /// empty card keeps him.
    var homeShowsPlayer: Bool {
        #if !APPSTORE
        // The rule lives in HomeContent so that the card and the geometry ask
        // one question, and so that it can be tested without an AppState.
        return homeContent.playerTakesHome(hasTrack: musicHasTrack,
                                           focusedPillID: focusTask?.id)
        #else
        return false
        #endif
    }

    var focusTask: AgentTask? {
        tasks.first { $0.id == focusId } ?? tasks.first
    }

    /// The pill whose character and colour the island should be wearing.
    ///
    /// Not `focusTask`: a view that speaks for one service outranks whatever
    /// was clicked last, or clicking Now Playing while Mattermost's list is up
    /// drops Now Playing's face into Mattermost's card. `IslandOwner` holds the
    /// rule, away from here, so it can be tested without opening the island.
    var characterOwnerID: String? {
        let inbox = MessageInbox.shared
        switch IslandOwner.owner(view: view,
                                 listSource: inbox.listSource?.pillID,
                                 listShowsAll: inbox.listShowsAll,
                                 activeMessageSource: inbox.active?.source.pillID,
                                 focusID: focusTask?.id) {
        case .pill(let id):   return id
        case .everyService:   return PillCatalog.notificationsID
        case .none:           return nil
        }
    }

    /// The brand colour that goes with `characterOwnerID`, or nil for a task
    /// pill, whose body is painted from its state instead.
    var characterOwnerColor: String? {
        guard let id: String = characterOwnerID else { return nil }
        let task: AgentTask? = tasks.first { $0.id == id }
        // A Claude Code session is not an integration and keeps its gradient.
        if let task, !task.isIntegration { return nil }
        if let brand: String = PillCatalog.definition(for: id)?.color { return brand }
        return task?.color
    }

    var effectiveState: BotState {
        stateOverride ?? focusTask?.state ?? .idle
    }

    // MARK: - Task management

    func addTask(_ task: AgentTask) {
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        tasks.append(task)
        if focusId == nil { focusId = task.id }
        syncMode()
        syncView()
    }

    func removeTask(id: String) {
        // Declared pills reset to idle rather than vanishing; the always-loaded
        // one counts as declared whether or not it is in `activeIntegrations`.
        let isProtected = id == PillCatalog.alwaysLoadedID
        let isActiveDecl = PillCatalog.definition(for: id) != nil && activeIntegrations.contains(id)
        if isProtected || isActiveDecl {
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                let catalogName = PillCatalog.definition(for: id)?.name
                tasks[idx].state      = .idle
                tasks[idx].steps      = []
                tasks[idx].stepIndex  = 0
                tasks[idx].pillBadge  = nil
                if let n = catalogName { tasks[idx].name = n }
            }
            return
        }
        // Undeclared or declared-but-not-active: remove
        tasks.removeAll { $0.id == id }
        if focusId == id { focusId = tasks.first?.id }
        syncMode()
        syncView()
    }

    func updateTask(id: String, state: BotState) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].state = state
    }

    func setFocus(_ id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        focusId = id
        tasks[idx].pillBadge = nil  // clear badge when user brings task to focus
    }

    func syncMode() {
        // Off, nothing arriving may put the island back on screen: a task
        // landing here would otherwise set .compact behind the controller's back.
        guard isEnabled else { mode = .hidden; return }
        // If no tasks and not expanded/peek, go hidden
        if tasks.isEmpty && mode == .compact {
            mode = .hidden
        } else if !tasks.isEmpty && mode == .hidden && isPresent {
            mode = .compact
        }
    }

    func syncView() {
        guard mode == .expanded else { return }
        if view == .empty && !tasks.isEmpty { view = .overview }
        else if view == .overview && tasks.isEmpty { view = .empty }
    }

    /// Load catalog pills into tasks, respecting activeIntegrations. Safe to call multiple times.
    func loadIntegrationTasks() {
        let catalog = PillCatalog.available
        // Sanitize: remove saved IDs not in catalog
        let catalogIds = Set(catalog.map { $0.id })
        let kept = activeIntegrations.filter { catalogIds.contains($0) }
        // Everything the user had chosen may have just been deleted from the
        // catalog. Writing the empty result back would destroy their choices
        // and leave an island with no pills, no tasks and no edge ring — so an
        // empty result means "seed the survivors" rather than "they chose
        // nothing". Someone who really wants none can still switch all four
        // off, because that set is non-empty on the way in.
        activeIntegrations = kept.isEmpty ? Self.defaultActiveIntegrations : kept
        // The same deletion can leave dead ids hung off the island's edges,
        // where nothing filtered them: they drew as grey buttons labelled with
        // the raw id and did nothing when clicked.
        if let saved = islandEdgeButtons {
            let live = saved.filter { catalogIds.contains($0.action)
                                   || IslandEdgeAction(rawValue: $0.action) != nil }
            if live.count != saved.count { islandEdgeButtons = live }
        }
        // The always-loaded pill never sits in `activeIntegrations`: it would
        // spend one of the four slots on something the user cannot turn off.
        activeIntegrations.remove(PillCatalog.alwaysLoadedID)
        for def in catalog {
            let shouldLoad = def.id == PillCatalog.alwaysLoadedID || activeIntegrations.contains(def.id)
            let loaded = tasks.contains(where: { $0.id == def.id })
            if shouldLoad && !loaded {
                let task = AgentTask(id: def.id, name: def.name, color: def.color,
                                     state: .idle, steps: [], source: def.source, isIntegration: true)
                tasks.append(task)
            }
            if !shouldLoad && loaded {
                tasks.removeAll { $0.id == def.id }
            }
        }
        sortTasksByCatalog()
        if focusId == nil { focusId = tasks.first?.id }
        syncMode()
    }

    /// Toggle a catalog pill on/off.
    /// The always-loaded pill is not toggleable: it has no off state.
    /// Max 4 of the rest active at once.
    func toggleIntegration(_ id: String) {
        guard id != PillCatalog.alwaysLoadedID else { return }
        guard PillCatalog.available.contains(where: { $0.id == id }) else { return }
        if activeIntegrations.contains(id) {
            activeIntegrations.remove(id)
            tasks.removeAll { $0.id == id }
            if focusId == id { focusId = tasks.first?.id }
        } else {
            guard activeIntegrations.count < 4 else { return }
            activeIntegrations.insert(id)
            if let def = PillCatalog.available.first(where: { $0.id == id }),
               !tasks.contains(where: { $0.id == id }) {
                let task = AgentTask(id: def.id, name: def.name, color: def.color,
                                     state: .idle, steps: [], source: def.source, isIntegration: true)
                tasks.append(task)
                sortTasksByCatalog()
            }
        }
        syncMode()
    }

    /// Sort tasks so catalog pills are in catalog order, undeclared pills sit right after
    /// integration_claude (matching HookServer insertion behaviour), and the rest follows.
    private func sortTasksByCatalog() {
        let order = PillCatalog.available.enumerated()
            .reduce(into: [String: Int]()) { $0[$1.element.id] = $1.offset }
        let catalogPills    = tasks.filter { order[$0.id] != nil }
        let undeclaredPills = tasks.filter { order[$0.id] == nil }
        let sortedCatalog   = catalogPills.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        if let claudeIdx = sortedCatalog.firstIndex(where: { $0.id == PillCatalog.alwaysLoadedID }) {
            var result: [AgentTask] = Array(sortedCatalog[...claudeIdx])
            result.append(contentsOf: undeclaredPills)
            if claudeIdx + 1 < sortedCatalog.count {
                result.append(contentsOf: sortedCatalog[(claudeIdx + 1)...])
            }
            tasks = result
        } else {
            tasks = undeclaredPills + sortedCatalog
        }
    }

}

// MARK: - Supporting types

enum PromptContext {
    case window(appName: String, title: String, url: String?)
    case file(name: String, fileURL: URL?)
}

struct DroppedFile {
    var url: URL
    var name: String
}

struct SearchResult {
    var title: String
    var items: [ResultItem]
    var note: String?
}

struct ResultItem {
    var label: String
    var detail: String
    var url: String?
}

// MARK: - Vercel

enum ChatRole { case user, assistant }

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: ChatRole
    var content: String   // var for streaming updates
}
