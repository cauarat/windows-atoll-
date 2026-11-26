import AppKit
import Foundation

/// Dictation, start to end: the key or the button, the microphone, the
/// service, and where the text goes.
///
/// Two ways in, one session:
/// - **Hold the key** (fn by default), anywhere. The microphone starts on the
///   press so the first syllable is kept; the card opens if the key is still
///   held after 0.3 s; on release the text is pasted where the cursor is, and
///   the card shows it for as long as a notification stays. The island never
///   takes the keyboard, so the app being typed in keeps it.
/// - **The button** on the card (opened from the menu bar's Dictation): click
///   to record, click to stop, then edit, copy or paste.
///
/// The speech model is not here: it runs in dictation-service/, at the address
/// set in Settings. When it is not running, the card says so and says how to
/// start it, rather than pretending.
@MainActor
final class DictationController: ObservableObject {
    static let shared = DictationController()

    enum Phase: Equatable {
        case idle
        /// Asking for the microphone, opening the connection.
        case starting
        case recording
        /// Stopped; waiting for the final.
        case finishing
        case done
        case failed
    }

    enum Trigger: Equatable {
        case button
        case holdKey
    }

    enum Failure: Equatable {
        case microphoneDenied
        case microphoneUnavailable
        case invalidAddress
        case serviceOffline
        case service(code: String, message: String)
        case connectionLost
        case timedOut
    }

    enum ServiceStatus: Equatable {
        case unknown
        case checking
        case ready(DictationHealth)
        case loading(DictationHealth)
        case broken(DictationHealth)
        case offline
        case invalidAddress
        case notTheService
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = DictationTranscript()
    @Published private(set) var failure: Failure?
    @Published private(set) var level: Float = 0
    @Published private(set) var recordingSince: Date?
    @Published private(set) var outcome: DictationInserter.Outcome?
    @Published private(set) var serviceStatus: ServiceStatus = .unknown
    /// The final text, as the person edits it on the card.
    @Published var draft = ""
    private(set) var trigger: Trigger = .button

    private var gesture = DictationHoldGesture()
    private var source: DictationAudioSource?
    private var socket: DictationSocket?
    /// Bumped by every dictation and every cancel: events from a connection or
    /// a microphone that belong to an older one are dropped.
    private var session = 0
    private var holdTicks: [Task<Void, Never>] = []
    private var deadline: Task<Void, Never>?

    /// Held open by the island while this is true (IslandWindowController's
    /// `isHeldOpen`): a dictation is a click or a held key, not a focus.
    var isBusy: Bool { phase == .starting || phase == .recording || phase == .finishing }

    /// How long the service may take to answer once the audio is all sent.
    private static let finalTimeout: Duration = .seconds(90)

    private init() {}

    // MARK: – Settings

    /// At launch and whenever a dictation setting changes. Deferred a turn:
    /// AppState calls this from its own `didSet`, and must not be read back
    /// while it is still setting itself.
    func settingsDidChange() {
        Task { self.applySettings() }
    }

    func applySettings() {
        let state = AppState.shared
        let key = DictationHoldKey(rawValue: state.dictationHoldKey) ?? .default
        if state.dictationEnabled && key != .off {
            DictationKeyTap.shared.stop()
            DictationKeyTap.shared.start(key: key)
        } else {
            DictationKeyTap.shared.stop()
            gesture.reset()
        }
        if !state.dictationEnabled, isBusy { cancel() }
        NotificationCenter.default.post(name: .dictationSettingsChanged, object: nil)
    }

    // MARK: – The key

    func handleKey(_ input: DictationHoldGesture.Input, at time: TimeInterval) {
        let state = AppState.shared
        guard state.dictationEnabled, state.isEnabled else {
            gesture.reset()
            return
        }
        // Recording from the button: the key is not what stops it.
        if trigger == .button, isBusy { return }
        for action in gesture.handle(input, at: time) { perform(action) }
    }

    private func perform(_ action: DictationHoldGesture.Action) {
        switch action {
        case .arm:
            begin(.holdKey)
            scheduleTick(after: DictationHoldGesture.minimumHold)
            scheduleTick(after: DictationHoldGesture.maximumHold)
        case .show:
            showCard(asNotification: true)
        case .commit:
            clearTicks()
            stop()
        case .cancel:
            clearTicks()
            cancel()
        }
    }

    private func scheduleTick(after seconds: TimeInterval) {
        holdTicks.append(Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.handleKey(.tick, at: ProcessInfo.processInfo.systemUptime)
        })
    }

    private func clearTicks() {
        holdTicks.forEach { $0.cancel() }
        holdTicks = []
    }

    // MARK: – The card's button

    func toggleRecording() {
        switch phase {
        case .starting, .recording: stop()
        case .finishing: break
        case .idle, .done, .failed: begin(.button)
        }
    }

    /// From the menu bar: the card, opened like a tab rather than a notification.
    func openCard() {
        showCard(asNotification: false)
        Task { await refreshService() }
    }

    func copyDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        DictationInserter.copy(text)
        outcome = .copied
    }

    func pasteDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            outcome = await DictationInserter.paste(text, into: AppState.shared.lastExternalApp)
        }
    }

    /// Throws the result away and goes back to "Record".
    func discard() {
        cancel(hideCard: false)
    }

    // MARK: – The service

    func refreshService() async {
        serviceStatus = .checking
        switch await DictationServiceProbe.health(service: AppState.shared.dictationServiceURL) {
        case .success(let health):
            if health.ready { serviceStatus = .ready(health) }
            else if health.status == "error" { serviceStatus = .broken(health) }
            else { serviceStatus = .loading(health) }
        case .failure(.invalidAddress): serviceStatus = .invalidAddress
        case .failure(.offline): serviceStatus = .offline
        case .failure(.notTheService): serviceStatus = .notTheService
        }
    }

    // MARK: – A dictation

    func begin(_ trigger: Trigger) {
        guard !isBusy else { return }
        clearState()
        self.trigger = trigger
        phase = .starting
        session += 1
        let session = self.session
        Task {
            let allowed = await VoiceRecorder.hasMicrophonePermission()
            guard self.session == session, self.phase == .starting else { return }  // let go meanwhile
            guard allowed else { return self.fail(.microphoneDenied) }
            self.startStreaming(session)
        }
    }

    private func startStreaming(_ session: Int) {
        guard let url = DictationProtocol.socketURL(service: AppState.shared.dictationServiceURL) else {
            return fail(.invalidAddress)
        }
        let socket = DictationSocket(url: url, deliver: Self.deliverer(session))
        self.socket = socket
        socket.open(start: DictationProtocol.startMessage())
        let source = makeSource()
        do {
            try source.start(onFrame: Self.sender(socket),
                             onLevel: Self.levelSink(session),
                             onInterrupted: Self.interruptionSink(session))
        } catch {
            return fail(.microphoneUnavailable)
        }
        self.source = source
        phase = .recording
        recordingSince = .now
        SoundEngine.shared.play("blip")
    }

    /// The key let go, or Stop: a little more audio, then the final.
    func stop() {
        switch phase {
        case .starting:
            cancel()  // nothing heard yet
        case .recording:
            phase = .finishing
            level = 0
            let session = self.session
            Task {
                try? await Task.sleep(for: .milliseconds(DictationProtocol.tailMilliseconds))
                guard self.session == session, self.phase == .finishing else { return }
                self.source?.stop()  // sends the last, shorter frame
                self.source = nil
                self.socket?.stop()
                self.deadline = Task {
                    try? await Task.sleep(for: Self.finalTimeout)
                    guard !Task.isCancelled, self.session == session, self.phase == .finishing else { return }
                    self.fail(.timedOut)
                }
            }
        default:
            break
        }
    }

    func cancel(hideCard: Bool = true) {
        let wasHeld = trigger == .holdKey
        session += 1
        clearTicks()
        teardown(cancelSocket: true)
        clearState()
        phase = .idle
        if hideCard, wasHeld { NotificationCenter.default.post(name: .dictationHideCard, object: nil) }
    }

    private func finished() {
        teardown(cancelSocket: false)
        phase = .done
        draft = transcript.text
        if trigger == .holdKey { deliver() }
        // The result is a notification, whichever way the dictation started:
        // on screen for as long as one stays, from now, then folded — unless
        // the pointer is on it or the text is being edited.
        showCard(asNotification: true)
    }

    private func deliver() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if AppState.shared.dictationInsertMode == DictationInsertMode.copy.rawValue {
            DictationInserter.copy(text)
            outcome = .copied
        } else {
            outcome = DictationInserter.paste(text)
        }
    }

    private func fail(_ failure: Failure) {
        teardown(cancelSocket: true)
        self.failure = failure
        phase = .failed
        // What was heard before it broke is still the person's.
        draft = transcript.text
        showCard(asNotification: true)
    }

    private func teardown(cancelSocket: Bool) {
        deadline?.cancel()
        deadline = nil
        source?.stop()
        source = nil
        if cancelSocket { socket?.cancel() } else { socket?.close() }
        socket = nil
        level = 0
        recordingSince = nil
    }

    private func clearState() {
        transcript = DictationTranscript()
        failure = nil
        outcome = nil
        draft = ""
        level = 0
        recordingSince = nil
    }

    private func showCard(asNotification: Bool) {
        NotificationCenter.default.post(name: .dictationShowCard, object: asNotification ? "notify" : "expand")
    }

    private func makeSource() -> DictationAudioSource {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["NOTCHY_DICTATION_FILE"] {
            return DictationFileSource(url: URL(fileURLWithPath: path))
        }
        #endif
        return DictationAudioCapture()
    }

    // MARK: – Back to the main thread
    //
    // Built in nonisolated functions on purpose: these closures run on the
    // audio thread and URLSession's queue, and one written inside this
    // main-actor class would inherit its isolation and trap there.

    nonisolated private static func sender(_ socket: DictationSocket) -> @Sendable (Data) -> Void {
        { data in socket.send(audio: data) }
    }

    nonisolated private static func levelSink(_ session: Int) -> @Sendable (Float) -> Void {
        { level in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { DictationController.shared.levelArrived(level, session) }
            }
        }
    }

    nonisolated private static func interruptionSink(_ session: Int) -> @Sendable () -> Void {
        {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { DictationController.shared.sourceInterrupted(session) }
            }
        }
    }

    nonisolated private static func deliverer(_ session: Int) -> @Sendable (DictationSocket.Event) -> Void {
        { event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { DictationController.shared.socketEvent(event, session) }
            }
        }
    }

    private func levelArrived(_ level: Float, _ session: Int) {
        guard session == self.session, phase == .recording else { return }
        self.level = level
    }

    /// The microphone changed under it, or (Debug) the file ran out: what was
    /// heard is transcribed.
    private func sourceInterrupted(_ session: Int) {
        guard session == self.session, phase == .recording else { return }
        stop()
    }

    private func socketEvent(_ event: DictationSocket.Event, _ session: Int) {
        guard session == self.session else { return }
        switch event {
        case .message(let message):
            transcript.apply(message)
            switch message {
            case .final:
                finished()
            case .error(let code, let text):
                fail(.service(code: code, message: text))
            case .ready, .partial:
                break
            }
        case .closed(let why):
            guard isBusy else { return }
            fail(why == .refused ? .serviceOffline : .connectionLost)
        }
    }
}

extension Notification.Name {
    /// Open the dictation card. Object "notify" for the hold key (a
    /// notification, folded by its timer), "expand" for the menu (a tab).
    static let dictationShowCard = Notification.Name("notchy.dictationShowCard")
    /// A held dictation was dropped: fold its card if it is the one showing.
    static let dictationHideCard = Notification.Name("notchy.dictationHideCard")
    /// Dictation was turned on or off, or its key changed: the menu follows.
    static let dictationSettingsChanged = Notification.Name("notchy.dictationSettingsChanged")
}
