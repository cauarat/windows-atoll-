import AppKit
import Combine
import Foundation

// MARK: - Phone link: the bridge to the island (GitHub build)
//
// Lets Notchy for iPhone and Notchy for Android pair with this Mac (docs/PHONE_LINK.md,
// protocol v1). Off by default and opt-in in Settings → General → Phone. While it is off nothing
// listens, nothing is announced on the network and no timer runs. While it is on, the work is
// event driven: AppState changes (debounced) are published to the hub, and phones' lines are
// handled as they arrive. No polling anywhere.
//
// The island keeps owning the sessions, the pending request and the question. A phone's decision
// goes through `PhoneLinkHub.decide`, which applies it only if its fingerprint is the request still
// pending, and then `PhoneLinkAppHost` answers the waiting nb-hook through
// `HookServer.sendApprovalDecision`, the very path a click on the island's own card takes, so that
// card keeps working all along.
//
// Compiled out of the App Store build: the sandbox has no server entitlement.

#if !APPSTORE

// MARK: Switches

/// The switches in Settings → General → Phone, read again for every connection.
final class PhoneLinkDefaultsFeatures: PhoneLinkFeatures, @unchecked Sendable {
    static let detailsKey = "phoneLinkDetails"
    static let answersKey = "phoneLinkAnswers"
    static let diffsKey = "phoneLinkDiffs"
    static let chatKey = "phoneLinkChat"

    func details() -> Bool { UserDefaults.standard.bool(forKey: Self.detailsKey) }
    func answers() -> Bool { UserDefaults.standard.bool(forKey: Self.answersKey) }
    func usage() -> Bool { false }
    func diffs() -> Bool { UserDefaults.standard.bool(forKey: Self.diffsKey) }
    func chat() -> Bool { UserDefaults.standard.bool(forKey: Self.chatKey) }
}

// MARK: Host

/// Applies a phone's decision as a click on the island's own card would.
final class PhoneLinkAppHost: PhoneLinkHost, @unchecked Sendable {
    func decide(requestId: String, allow: Bool) {
        Task { @MainActor in
            // Checked again on the main actor, right before answering the hook: the request must
            // still be the one on the card.
            guard let pending = AppState.shared.pendingApproval, pending.requestId == requestId else {
                PhoneLinkService.log("decision arrived after the request was resolved, ignored")
                return
            }
            PhoneLinkService.log("\(allow ? "allowed" : "denied") from the phone: \(pending.tool)")
            HookServer.shared.sendApprovalDecision(allow ? "allow" : "deny")
        }
    }

    func answer(requestId: String, picks: [[String]]) {
        Task { @MainActor in
            guard let question = AppState.shared.pendingQuestion, question.requestId == requestId else {
                PhoneLinkService.log("answer for a question no longer waiting, ignored")
                return
            }
            // Never what was picked.
            PhoneLinkService.log("answered a question from the phone")
            HookServer.shared.sendQuestionAnswers(AskQuestion.buildAnswers(questions: question.questions, selections: picks))
        }
    }

    func diff(pillId: String, fileId: Int, reply: @escaping @Sendable (PhoneDiffIn?) -> Void) {
        Task { @MainActor in
            let diff = AppState.shared.sessionDiffs[pillId]?.first { $0.id == fileId }
            reply(diff.map(PhoneLinkService.diff(from:)))
        }
    }
}

// MARK: Service

@MainActor
final class PhoneLinkService: ObservableObject {
    static let shared = PhoneLinkService()
    static let enabledKey = "phoneLinkEnabled"

    @Published private(set) var running = false
    @Published private(set) var port: UInt16 = 0
    @Published private(set) var error: String?
    /// Phones connected right now.
    @Published private(set) var phones = 0

    private var hub: PhoneLinkHub?
    private var server: PhoneLinkServer?
    private var identity: PhoneLinkIdentity?
    private var cancellable: AnyCancellable?
    private let store = PhoneLinkKeychainStore()

    nonisolated static func log(_ message: String) {
        appendAppLog("PhoneLink.log", message)
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// At launch: starts only if the user turned it on.
    func startIfEnabled() {
        if Self.isEnabled { start() }
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on { start() } else { stop() }
    }

    // MARK: Start and stop

    private func start() {
        guard server == nil else { return }
        guard let identity = PhoneLinkIdentity.loadOrCreate(store: store),
              let token = PhoneLinkIdentity.token(store: store) else {
            fail("no secure storage for the certificate or the pairing code")
            return
        }
        guard let secIdentity = PhoneLinkSecIdentity.make(for: identity) else {
            fail("the certificate could not be loaded")
            return
        }
        let hub = PhoneLinkHub(host: PhoneLinkAppHost()) { [weak self] count in
            Task { @MainActor in self?.phones = count }
        }
        let server = PhoneLinkServer(hub: hub, features: PhoneLinkDefaultsFeatures(), chat: PhoneLinkChatService.shared,
                                     name: PhoneLinkProtocol.computerName(), token: token)
        server.onState = { [weak self] state in
            Task { @MainActor in self?.serverState(state) }
        }
        self.hub = hub
        self.server = server
        self.identity = identity
        error = nil
        server.start(identity: secIdentity, txt: PhoneLinkProtocol.txtRecord(fingerprint: identity.fingerprint) ?? [:])
        observe()
        Self.log("starting")
    }

    private func stop() {
        cancellable = nil
        server?.stop()
        server = nil
        hub = nil
        identity = nil
        PhoneLinkChatService.shared.reset()
        PhoneLinkSecIdentity.remove()
        running = false
        port = 0
        phones = 0
        error = nil
        Self.log("stopped")
    }

    private func fail(_ message: String) {
        error = message
        running = false
        Self.log("could not start: \(message)")
    }

    private func serverState(_ state: PhoneLinkServer.State) {
        guard server != nil else { return }
        switch state {
        case .ready(let p):
            port = p
            running = true
            error = nil
            Self.log("listening on port \(p)")
            publish()
        case .failed(let message):
            // Nothing is left half running: the listener is gone, so is everything else.
            stop()
            fail(message)
        }
    }

    // MARK: Pairing

    /// The pairing link for this Mac, or nil while the link is not running.
    func pairingLink() -> String? {
        guard running, let identity, let server, let host = PhoneLinkNetwork.lanAddress() else { return nil }
        return PhoneLinkProtocol.pairingLink(host: host, port: port, fingerprint: identity.fingerprint,
                                             token: server.currentToken, name: PhoneLinkProtocol.computerName())
    }

    /// A new pairing code: the phone that held the old one is locked out and disconnected.
    func pairAgain() {
        guard let server, let hub, let token = PhoneLinkIdentity.newToken(store: store) else { return }
        server.replaceToken(token)
        hub.kickAll(code: "auth", message: "unpaired")
        PhoneLinkChatService.shared.reset()
        Self.log("paired again")
    }

    /// A switch changed: phones reconnect once, to be told what is offered now.
    func switchesChanged() {
        hub?.kickAll(code: "closed", message: "settings changed")
        if !PhoneLinkDefaultsFeatures().chat() { PhoneLinkChatService.shared.reset() }
    }

    // MARK: From the island to the phones

    /// Event driven: the island's state changes, debounced, are published. Nothing else wakes this up.
    private func observe() {
        let s = AppState.shared
        let sources: [AnyPublisher<Void, Never>] = [
            s.$tasks.map { _ in () }.eraseToAnyPublisher(),
            s.$pendingApproval.map { _ in () }.eraseToAnyPublisher(),
            s.$pendingQuestion.map { _ in () }.eraseToAnyPublisher(),
            s.$pillCharacters.map { _ in () }.eraseToAnyPublisher(),
        ]
        // @Published sends before the property changes: the debounce lets the value settle, and it is read back.
        cancellable = Publishers.MergeMany(sources)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.publish() }
            }
    }

    private func publish() {
        guard let hub else { return }
        let state = AppState.shared
        let now = PhoneLinkProtocol.nowMs()
        hub.publish(sessions: Self.sessions(from: state.tasks, state: state), approval: state.pendingApproval.flatMap(Self.approval(from:)), now: now)
        hub.publishQuestion(state.pendingQuestion.flatMap(Self.question(from:)), now: now)
    }

    // MARK: Mapping (AppState → the phone's picture)

    /// One session per agent pill, as the island shows them: services (Mattermost, Ato, Now Playing…) are not sessions.
    static func sessions(from tasks: [AgentTask], state: AppState) -> [PhoneSessionIn] {
        tasks.filter { $0.source != .n8n }
            .map { task in
                let current = task.steps.indices.contains(task.stepIndex) ? task.steps[task.stepIndex] : (task.steps.last ?? "")
                let files = (state.sessionDiffs[task.id] ?? []).map {
                    PhoneFileIn(id: $0.id, name: $0.name, added: $0.added, removed: $0.removed, tooLarge: $0.tooLarge, isNew: $0.isNewFile)
                }
                return PhoneSessionIn(
                    pillId: task.id, agent: task.name, state: task.state.rawValue, statusText: current,
                    stepIndex: task.stepIndex, stepCount: task.steps.count,
                    steps: task.steps, finalLine: task.finalLine, project: task.sessionCwd, color: task.color,
                    files: files, character: character(state.character(for: task.id)))
            }
    }

    /// A character as the wire carries it: the raw values the Mac stores, and nothing for classic.
    static func character(_ c: MochiCharacter) -> [String: String] {
        var v: [String: String] = [:]
        if let a = c.accessory { v["accessory"] = a.rawValue }
        if let e = c.eye { v["eye"] = e.rawValue }
        if let s = c.shape { v["shape"] = s.rawValue }
        if let f = c.festive?.orNil { v["festive"] = f.storageString }
        return v
    }

    /// The request on the card. Its request id goes into the fingerprint, so asking for the same command
    /// twice gives two different fingerprints, and a late decision for the first can never answer the second.
    static func approval(from info: ApprovalInfo) -> PhoneApprovalIn? {
        PhoneApprovalIn(requestId: info.requestId, sessionId: info.sessionId, pillId: info.pillId,
                        tool: info.tool, command: info.command)
    }

    /// The question on the card, if it fits what a phone can show whole; otherwise it stays on the Mac.
    static func question(from q: AskQuestion) -> PhoneQuestionIn? {
        let items = q.questions.map { item in
            PhoneQuestionItemIn(question: item.question,
                                options: item.options.map { PhoneOptionIn(label: $0.label, description: $0.description) },
                                multiSelect: item.multiSelect)
        }
        guard PhoneLinkHub.fitsTheLimits(items) else { return nil }
        return PhoneQuestionIn(requestId: q.requestId, sessionId: q.sessionId, pillId: q.pillId.isEmpty ? "integration_claude" : q.pillId,
                               questions: items)
    }

    /// The island's diff as the phone's lines: a hunk header, then its lines.
    nonisolated static func diff(from d: FileDiff) -> PhoneDiffIn {
        var lines: [PhoneDiffLineIn] = []
        for hunk in d.hunks {
            lines.append(PhoneDiffLineIn(kind: "@", text: "@@ -\(hunk.origStart) +\(hunk.newStart)"))
            for line in hunk.lines {
                let kind: String
                switch line.kind {
                case .added: kind = "+"
                case .removed: kind = "-"
                case .context: kind = " "
                }
                lines.append(PhoneDiffLineIn(kind: kind, text: line.text))
            }
        }
        return PhoneDiffIn(name: d.name, added: d.added, removed: d.removed, tooLarge: d.tooLarge, lines: lines)
    }
}

// MARK: Network

enum PhoneLinkNetwork {
    /// This Mac's address on the local network: the one the system would use to reach the outside.
    /// Connecting a UDP socket sends nothing; it only makes the system pick the interface.
    static func lanAddress() -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var remote = sockaddr_in()
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = UInt16(9).bigEndian
        guard inet_pton(AF_INET, "192.0.2.1", &remote.sin_addr) == 1 else { return nil }
        let connected = withUnsafePointer(to: &remote) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }
        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var address = local.sin_addr
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        let text = String(cString: buffer)
        return text == "0.0.0.0" ? nil : text
    }
}

#endif
