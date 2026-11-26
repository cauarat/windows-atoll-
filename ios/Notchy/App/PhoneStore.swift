import LocalAuthentication
import SwiftUI
import UIKit

// MARK: - Everything the phone knows, and everything it can do
//
// One store for the app, on the main actor: what the computer last said (sessions, the request that
// waits, the question, a diff being read, the chat), and the few things the phone can send back.
// Allow and an answer to a question ask for Face ID (or the phone's passcode) first; Deny does not.
// With no screen lock set up, Allow is refused: whoever picks up an unlocked phone must not be able
// to run a command on the computer.

@MainActor
final class PhoneStore: ObservableObject {
    static let shared = PhoneStore()

    @Published private(set) var computer: PairedComputer?
    @Published private(set) var status: LinkClient.Status = .idle
    @Published private(set) var caps: Set<String> = []
    @Published private(set) var sessions: [SessionInfo] = []
    @Published private(set) var approval: ApprovalRequest?
    @Published private(set) var question: QuestionRequest?
    /// A link scanned or opened from outside, waiting for the user to confirm it.
    @Published var pendingPairing: PairedComputer?
    /// A short line shown under the island for a few seconds.
    @Published var toast: String?
    @Published var focusedPillId: String?

    // Diffs, read on request and forgotten when the sheet closes.
    @Published private(set) var diff: DiffState?

    // Chat.
    @Published private(set) var chatModels: [ChatModel] = []
    @Published var chatModelId: String?
    @Published private(set) var chat: [ChatEntry] = []
    @Published private(set) var chatRunningId: String?

    struct DiffState: Equatable {
        var pillId: String
        var fileId: Int
        var name: String
        var added: Int
        var removed: Int
        var tooLarge = false
        var gone = false
        var truncated = false
        var parts: [Int: [DiffRow]] = [:]
        var partCount = 0
        var loading: Bool { partCount == 0 || parts.count < partCount }
        var rows: [DiffRow] { (0..<max(partCount, 0)).flatMap { parts[$0] ?? [] } }
    }

    struct ChatEntry: Identifiable, Equatable {
        enum Role { case user, assistant, error }
        let id: String
        var role: Role
        var text: String
    }

    private let client: LinkClient
    private var lastStates: [String: BotState] = [:]
    private var toastItem: DispatchWorkItem?
    /// A decision made from a notification before the link was back up: sent as soon as the computer
    /// shows the same request again, and dropped if it does not.
    private var deferredDecision: (fingerprint: String, allow: Bool)?

    private init() {
        client = LinkClient(deviceName: UIDevice.current.name)
        client.onMessage = { [weak self] message in
            Task { @MainActor in self?.receive(message) }
        }
        client.onStatus = { [weak self] status in
            Task { @MainActor in self?.statusChanged(status) }
        }
        client.onMoved = { moved in
            Task { @MainActor in
                PairingStore.save(moved)
                PhoneStore.shared.computer = moved
            }
        }
        computer = PairingStore.load()
        if let computer { client.start(computer) }
    }

    // MARK: Pairing

    /// A `notchy://pair` link from the camera, a scan or the clipboard: shown for confirmation, never paired silently.
    func offer(link: String) -> Bool {
        guard let parsed = PairingLink.parse(link) else { return false }
        pendingPairing = parsed
        return true
    }

    func handle(url: URL) {
        if !offer(link: url.absoluteString) {
            show(String(localized: "That link is not a Notchy pairing link."))
        }
    }

    func confirmPairing() {
        guard let new = pendingPairing else { return }
        pendingPairing = nil
        client.stop()
        resetPicture()
        PairingStore.save(new)
        computer = new
        client.start(new)
    }

    func unpair() {
        client.stop()
        PairingStore.clear()
        computer = nil
        resetPicture()
        LiveActivityController.shared.end()
    }

    func retry() { client.retryNow() }

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    var computerName: String {
        if case .connected(let desktop, _) = status, !desktop.isEmpty { return desktop }
        return computer?.name ?? ""
    }

    // MARK: Scene

    func scenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            client.retryNow()
            Notifications.shared.clearDelivered()
        case .background:
            // iOS gives an app a little time before it is suspended; the link stays up for it, so a
            // request that arrives right after the phone is put away still makes a notification.
            BackgroundGrace.begin()
        default:
            break
        }
    }

    // MARK: From the computer

    private func statusChanged(_ new: LinkClient.Status) {
        status = new
        switch new {
        case .connected:
            break
        case .unauthorized:
            caps = []
            show(String(localized: "Your computer no longer knows this phone. Pair again from its Settings."))
        default:
            caps = []
        }
    }

    private func receive(_ message: ServerMessage) {
        #if DEBUG
        defer { DemoSeed.observe(message) }
        #endif
        switch message {
        case .welcome(_, _, _, let offered):
            caps = offered
            if offered.contains("chat") { client.send(["type": "chatModels"]) }
        case .sessions(let list):
            let before = lastStates
            sessions = list
            lastStates = Dictionary(list.map { ($0.pillId, $0.state) }, uniquingKeysWith: { a, _ in a })
            if focusedPillId == nil || !list.contains(where: { $0.pillId == focusedPillId }) {
                focusedPillId = list.first(where: { $0.state != .idle })?.pillId ?? list.first?.pillId
            }
            for s in list where before[s.pillId] != nil && before[s.pillId] != s.state {
                sessionChanged(s, from: before[s.pillId]!)
            }
            LiveActivityController.shared.update(sessions: list, approval: approval, question: question)
        case .approval(let request):
            approval = request
            focusedPillId = request.pillId
            SoundEngine.shared.play("approval")
            Notifications.shared.approval(request, agent: agentName(request.pillId), computer: computerName)
            if let deferred = deferredDecision, deferred.fingerprint == request.fingerprint {
                deferredDecision = nil
                sendDecision(request, allow: deferred.allow)
            }
            LiveActivityController.shared.update(sessions: sessions, approval: request, question: question)
        case .approvalResolved(let fp):
            if approval?.fingerprint == fp { approval = nil }
            if question?.fingerprint == fp { question = nil }
            Notifications.shared.remove(fingerprint: fp)
            LiveActivityController.shared.update(sessions: sessions, approval: approval, question: question)
        case .question(let request):
            question = request
            focusedPillId = request.pillId
            SoundEngine.shared.play("question")
            Notifications.shared.question(request, agent: agentName(request.pillId), computer: computerName)
            LiveActivityController.shared.update(sessions: sessions, approval: approval, question: request)
        case .diff(let part):
            guard var d = diff, d.pillId == part.pillId, d.fileId == part.fileId else { return }
            d.name = part.name.isEmpty ? d.name : part.name
            d.added = part.added
            d.removed = part.removed
            d.tooLarge = part.tooLarge
            d.gone = part.gone
            d.truncated = part.truncated
            d.partCount = part.parts
            d.parts[part.part] = part.lines
            diff = d
        case .chatModels(let models):
            chatModels = models
            if chatModelId == nil || !models.contains(where: { $0.id == chatModelId }) { chatModelId = models.first?.id }
        case .chatDelta(let id, let text):
            if let i = chat.firstIndex(where: { $0.id == id }) {
                chat[i].text += text
            } else {
                chat.append(ChatEntry(id: id, role: .assistant, text: text))
            }
        case .chatDone(let id, let text):
            if let text {
                if let i = chat.firstIndex(where: { $0.id == id }) { chat[i].text = text }
                else { chat.append(ChatEntry(id: id, role: .assistant, text: text)) }
            }
            if chatRunningId == id { chatRunningId = nil }
            SoundEngine.shared.play("pop")
        case .chatError(let id, let reason, let message):
            if chatRunningId == id { chatRunningId = nil }
            guard reason != "canceled" else { return }
            chat.append(ChatEntry(id: id + "-error", role: .error, text: Self.chatErrorText(reason) ?? message))
        case .error, .pong, .other:
            break
        }
    }

    private func sessionChanged(_ s: SessionInfo, from old: BotState) {
        switch s.state {
        case .finished:
            SoundEngine.shared.play("finish")
            Notifications.shared.finished(s, computer: computerName)
        case .error:
            SoundEngine.shared.play("error")
        default:
            break
        }
    }

    private func resetPicture() {
        sessions = []
        approval = nil
        question = nil
        caps = []
        diff = nil
        chat = []
        chatModels = []
        chatRunningId = nil
        lastStates = [:]
        focusedPillId = nil
        status = .idle
    }

    func agentName(_ pillId: String) -> String {
        sessions.first { $0.pillId == pillId }?.agent ?? (pillId == "integration_claude" ? "Claude Code" : "Agent")
    }

    // MARK: Decisions

    /// Deny goes at once. Allow asks for Face ID or the passcode first, and is never offered for a command
    /// the phone could not show in full.
    func decide(allow: Bool) async {
        guard let request = approval else { return }
        if allow {
            guard !request.truncated else { return }
            guard await Self.unlock(reason: String(localized: "Allow this command on your computer")) else { return }
            // The request may have been answered on the computer while Face ID was up.
            guard approval?.fingerprint == request.fingerprint else { return }
        }
        sendDecision(request, allow: allow)
    }

    private func sendDecision(_ request: ApprovalRequest, allow: Bool) {
        client.send(["type": "decision", "fingerprint": request.fingerprint, "decision": allow ? "allow" : "deny"])
        approval = nil
        Notifications.shared.remove(fingerprint: request.fingerprint)
        SoundEngine.shared.play(allow ? "approve" : "close")
        show(allow ? String(localized: "Allowed. Your computer runs it now.") : String(localized: "Denied."))
        LiveActivityController.shared.update(sessions: sessions, approval: nil, question: question)
    }

    /// From a notification: the app may only just have been woken, with the link still coming back.
    func decideFromNotification(fingerprint: String, allow: Bool) async {
        if allow {
            guard await Self.unlock(reason: String(localized: "Allow this command on your computer")) else { return }
        }
        if let request = approval, request.fingerprint == fingerprint {
            if allow && request.truncated { return }
            sendDecision(request, allow: allow)
        } else {
            deferredDecision = (fingerprint, allow)
            client.retryNow()
            // Not shown again within a few seconds: it was answered elsewhere or expired.
            try? await Task.sleep(for: .seconds(8))
            if deferredDecision?.fingerprint == fingerprint { deferredDecision = nil }
        }
    }

    /// One list of labels per question, in order.
    func answer(_ picks: [[String]], skipUnlock: Bool = false) async {
        guard let request = question else { return }
        if !skipUnlock {
            guard await Self.unlock(reason: String(localized: "Answer Claude on your computer")) else { return }
        }
        guard question?.fingerprint == request.fingerprint else { return }
        client.send(["type": "answer", "fingerprint": request.fingerprint, "picks": picks])
        question = nil
        Notifications.shared.remove(fingerprint: request.fingerprint)
        SoundEngine.shared.play("send")
        show(String(localized: "Answer sent."))
    }

    static func unlock(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = String(localized: "Use passcode")
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            await MainActor.run {
                PhoneStore.shared.show(String(localized: "Set up Face ID or a passcode on this phone to allow commands from it."))
            }
            return false
        }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    // MARK: Diffs

    func openDiff(pillId: String, file: FileChange) {
        diff = DiffState(pillId: pillId, fileId: file.id, name: file.name, added: file.added, removed: file.removed, tooLarge: file.tooLarge)
        client.send(["type": "getDiff", "pillId": pillId, "fileId": file.id])
    }

    func closeDiff() { diff = nil }

    // MARK: Chat

    var canChat: Bool { caps.contains("chat") && !chatModels.isEmpty }

    func sendChat(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, chatRunningId == nil, let model = chatModelId else { return }
        let id = "c" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20).lowercased()
        chat.append(ChatEntry(id: id + "-q", role: .user, text: trimmed))
        chatRunningId = id
        client.send(["type": "chatSend", "id": id, "model": model, "text": String(trimmed.prefix(4000))])
        SoundEngine.shared.play("send")
    }

    func cancelChat() {
        guard let id = chatRunningId else { return }
        client.send(["type": "chatCancel", "id": id])
        chatRunningId = nil
    }

    func newChat() {
        client.send(["type": "chatReset"])
        chat = []
        chatRunningId = nil
    }

    static func chatErrorText(_ reason: String) -> String? {
        switch reason {
        case "busy": return String(localized: "Mochi is still answering the last message.")
        case "rate": return String(localized: "That's a lot of messages. Try again in a few minutes.")
        case "too_long": return String(localized: "That message is too long.")
        case "no_key": return String(localized: "That provider is not set up on your computer.")
        case "unreachable": return String(localized: "Your computer could not reach the provider.")
        case "auth": return String(localized: "The provider refused the key saved on your computer.")
        case "off", "not_allowed": return String(localized: "Chat from the phone is turned off on your computer.")
        default: return nil
        }
    }

    // MARK: Toast

    func show(_ text: String) {
        toastItem?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toast = text }
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil } }
        }
        toastItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: item)
    }
}

// MARK: - A little time after the app leaves the front

@MainActor
enum BackgroundGrace {
    private static var task: UIBackgroundTaskIdentifier = .invalid

    static func begin() {
        guard task == .invalid else { return }
        task = UIApplication.shared.beginBackgroundTask(withName: "Notchy link") {
            end()
        }
    }

    static func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}

// MARK: - Screenshots without a computer (Debug builds only)

#if DEBUG
/// `NOTCHY_DEMO=sessions|approval|question|finished` fills the store with a made-up picture, for
/// looking at the screens in the simulator. Never in a Release build; nothing of it is sent anywhere.
enum DemoSeed {
    @MainActor static func applyIfAsked() {
        let env = ProcessInfo.processInfo.environment
        // `NOTCHY_PAIR_LINK=<notchy://pair…>` pairs at launch, without the confirmation (the simulator's
        // "Open in Notchy?" and the app's own alert both need a tap nobody can script).
        if let link = env["NOTCHY_PAIR_LINK"], PhoneStore.shared.offer(link: link) {
            PhoneStore.shared.confirmPairing()
        }
        guard let mode = env["NOTCHY_DEMO"] else { return }
        PhoneStore.shared.debugSeed(mode)
    }

    /// `NOTCHY_AUTO=deny,answer,chat,diff`: answers what arrives as a tap would, a moment later, so a whole
    /// round trip with a computer can run unattended. Allow is left out on purpose: it needs Face ID.
    @MainActor static func observe(_ message: ServerMessage) {
        let auto = Set((ProcessInfo.processInfo.environment["NOTCHY_AUTO"] ?? "").split(separator: ",").map(String.init))
        guard !auto.isEmpty else { return }
        let store = PhoneStore.shared
        switch message {
        case .approval where auto.contains("deny"):
            after(4) { Task { await store.decide(allow: false) } }
        case .question(let q) where auto.contains("answer"):
            let picks = q.questions.map { [$0.options[0].label] }
            after(4) { Task { await store.answer(picks, skipUnlock: true) } }
        case .welcome where auto.contains("chat"):
            after(3) { store.sendChat("Hello from the phone") }
        case .sessions(let list) where auto.contains("diff") && store.diff == nil:
            if let s = list.first(where: { !$0.files.isEmpty }), let f = s.files.first {
                didOpenDiff = true
                after(2) { if store.diff == nil { store.openDiff(pillId: s.pillId, file: f) } }
            }
        default:
            break
        }
    }

    @MainActor private static var didOpenDiff = false

    @MainActor private static func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            work()
        }
    }
}

extension PhoneStore {
    func debugSeed(_ mode: String) {
        computer = PairedComputer(host: "192.168.1.20", port: 47830, fingerprint: String(repeating: "a", count: 64),
                                  token: String(repeating: "x", count: 32), name: "MacBook Pro")
        status = .connected(desktop: "MacBook Pro", os: "macos")
        caps = ["details", "answers", "diffs", "character", "chat"]
        let now = Date()
        sessions = [
            SessionInfo(pillId: "integration_claude", agent: "Claude Code", state: mode == "finished" ? .finished : .working,
                        statusText: "Running npm test", stepIndex: 3, stepCount: 4, updatedAt: now,
                        steps: ["Reading package.json", "Edited LinkClient.swift +42 −7", "Searching for “fingerprint”", "Running npm test"],
                        finalLine: mode == "finished" ? "All 128 tests pass. The phone link is ready." : nil,
                        project: "windows-atoll-", color: "#F5F6F8",
                        files: [FileChange(id: 1, name: "LinkClient.swift", added: 42, removed: 7, tooLarge: false, isNew: false),
                                FileChange(id: 2, name: "PhoneStore.swift", added: 120, removed: 0, tooLarge: false, isNew: true)],
                        character: MochiCharacter()),
            SessionInfo(pillId: "agent_codex", agent: "Codex", state: .thinking, statusText: "Planning the refactor", stepIndex: 0,
                        stepCount: 1, updatedAt: now, steps: ["Planning the refactor"], finalLine: nil, project: "api-server",
                        color: "#10A37F", files: [], character: MochiCharacter(accessory: .crown, eye: .glossy)),
            SessionInfo(pillId: "agent_cursor", agent: "Cursor", state: .idle, statusText: "", stepIndex: 0, stepCount: 0,
                        updatedAt: now, steps: [], finalLine: nil, project: "website", color: "#7C5CFF", files: [],
                        character: MochiCharacter(accessory: .catEars, shape: .round)),
        ]
        focusedPillId = "integration_claude"
        if mode == "approval" {
            approval = ApprovalRequest(pillId: "integration_claude", fingerprint: String(repeating: "b", count: 64), tool: "Bash",
                                       command: "git push origin claude/notchy-ios-android", createdAt: now, truncated: false)
        }
        if mode == "question" {
            question = QuestionRequest(pillId: "integration_claude", fingerprint: String(repeating: "c", count: 64), createdAt: now, questions: [
                AskedQuestion(question: "Which platform should ship first?", options: [
                    AskedOption(label: "iPhone", description: ""), AskedOption(label: "Android", description: ""),
                    AskedOption(label: "Both together", description: ""),
                ], multiSelect: false),
            ])
        }
        if mode == "chat" {
            chatModels = [ChatModel(id: "anthropic/claude-sonnet-5-5", provider: "anthropic", label: "Anthropic · claude-sonnet-5-5")]
            chatModelId = chatModels.first?.id
            chat = [
                ChatEntry(id: "1-q", role: .user, text: "What is my agent doing right now?"),
                ChatEntry(id: "1", role: .assistant, text: "Claude Code is **running the tests** in `windows-atoll-`. It edited two files so far:\n\n- `LinkClient.swift` +42 −7\n- `PhoneStore.swift`, new"),
            ]
        }
    }
}
#endif
