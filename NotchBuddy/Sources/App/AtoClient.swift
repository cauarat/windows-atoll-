//
//  AtoClient.swift
//  Notchy
//
//  Listens to Ato, Actuar's support inbox, and turns customer messages into
//  notifications. It replaced ClickMassa, which worked the same way.
//

import AppKit
import Combine
import Foundation

// MARK: - Settings

/// The non-secret half of the Ato configuration. There is no server to type:
/// Ato is one Actuar product, see ``AtoEndpoints``.
enum AtoSettings {
    /// What a second click on the pill opens: `PillOpen.websiteSetting`, or an
    /// application's bundle identifier. Defaults to the website — Ato lives
    /// inside novo.actuar.com.
    static var openTarget: String {
        get {
            let stored = UserDefaults.standard.string(forKey: "atoOpenTarget") ?? ""
            return stored.isEmpty ? PillOpen.websiteSetting : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: "atoOpenTarget") }
    }
}

/// Connects to Ato and forwards the customer messages that are actually yours.
///
/// The shape is ``MattermostClient``'s — backoff, an open deadline, a
/// generation counter, sleep/wake, a floor between sign-ins — because those
/// were learned the hard way twice already. What differs:
///
/// - **Sign-in is Actuar's**, not Ato's: `userservice/Auth/Login` with the
///   password as the panel digests it, answering a two-hour bearer token and
///   a `TokenId` that `/Auth/Refresh` trades for the next one. The client
///   refreshes ahead of expiry, so a day goes by on one sign-in.
/// - **The socket is SignalR** (`/SupportHub`), and the event that carries a
///   customer's words is `onConversationUpdated`; see ``AtoConversationUpdate``.
/// - **The socket carries the whole workspace**, as ClickMassa's carried the
///   whole tenant before it. ``AtoRules/shouldNotify(_:memberships:)`` is the part that
///   matters.
///
/// Listening never changes your presence: the console's `Heartbeat` is what
/// marks an agent online, and this client never invokes it.
@MainActor
final class AtoClient: ObservableObject {
    static let shared = AtoClient()

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(username: String)
        case failed(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    @Published private(set) var state: ConnectionState = .disconnected

    // MARK: - Timings

    /// SignalR's server drops a client it has not heard from in 30 seconds.
    private static let pingInterval: TimeInterval = 15
    private static let openDeadline: TimeInterval = 20
    private static let backoffFloor: TimeInterval = 1
    private static let backoffCeiling: TimeInterval = 30
    /// The floor ClickMassa had to learn to keep: a flapping socket must not
    /// turn into a stream of sign-ins.
    private static let minimumLoginInterval: TimeInterval = 60
    /// How long before a token's `exp` to trade it for the next one.
    private static let refreshLead: TimeInterval = 10 * 60
    private static let maximumUnattendedRetry: TimeInterval = 15 * 60

    /// The panel is a web app, so the API expects a browser.
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    // MARK: - Private state

    private var socket: SignalRConnection?
    private var sessionTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var openDeadlineTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private var attempt = 0
    private var isStopping = false
    private var observersInstalled = false
    private var generation = 0

    /// Who we are, per workspace. Without it the filter cannot run, which is
    /// why nothing is ingested before `/Agents/me` has answered.
    private var memberships: [AtoMembership] = []
    private var queueNames: [String: String] = [:]
    /// Contact names by id. A conversation's update names the contact by id
    /// only, and the same few people write again and again.
    private var contactNames: [String: String] = [:]
    /// The last customer message already announced, per conversation — the
    /// hub repeats an update for every change to a conversation.
    private var announced: [String: String] = [:]

    private var lastLoginAttempt: Date?
    private var bypassLoginFloorOnce = false
    private var lastAttemptedFingerprint: Int?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Lifecycle

    var hasCredentials: Bool { AtoTokenStore.shared.hasCredentials }

    func connectIfConfigured() {
        guard AtoTokenStore.shared.hasCredentials else { return }
        guard !state.isConnected, state != .connecting else { return }
        connect()
    }

    /// - Parameter userInitiated: true when a person pressed Sign In. Changed
    ///   credentials skip the sign-in floor; the same ones pressed again do not.
    func connect(userInitiated: Bool = false) {
        isStopping = false
        attempt = 0
        if userInitiated {
            var hasher = Hasher()
            hasher.combine(AtoTokenStore.shared.email)
            hasher.combine(AtoTokenStore.shared.passwordDigest)
            let fingerprint = hasher.finalize()
            if fingerprint != lastAttemptedFingerprint {
                lastAttemptedFingerprint = fingerprint
                bypassLoginFloorOnce = true
            }
        }
        installSystemObserversIfNeeded()
        startAttempt()
    }

    func signOut() {
        disconnect()
        AtoTokenStore.shared.clear()
        memberships = []
        queueNames = [:]
        contactNames = [:]
        announced = [:]
        engaged = [:]
        answererChecked = []
        UserDefaults.standard.removeObject(forKey: Self.engagedKey)
    }

    func disconnect() {
        isStopping = true
        generation += 1
        teardown()
        state = .disconnected
    }

    private func startAttempt() {
        teardown()

        guard AtoTokenStore.shared.hasCredentials else {
            state = .failed(L("Enter your email and password"))
            return
        }

        state = .connecting
        generation += 1
        let gen = generation
        sessionTask = Task { [weak self] in
            await self?.runSession(generation: gen)
        }
    }

    private func teardown() {
        reconnectTask?.cancel(); reconnectTask = nil
        pingTask?.cancel(); pingTask = nil
        openDeadlineTask?.cancel(); openDeadlineTask = nil
        refreshTask?.cancel(); refreshTask = nil
        sessionTask?.cancel(); sessionTask = nil
        socket?.disconnect(); socket = nil
    }

    private func installSystemObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.isStopping else { return }
                self.generation += 1
                self.teardown()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.isStopping else { return }
                self.attempt = 0
                self.connectIfConfigured()
            }
            .store(in: &cancellables)
    }

    // MARK: - Session

    private func runSession(generation gen: Int) async {
        let token: String
        do {
            token = try await validToken()
            try Task.checkCancellation()
            memberships = try await fetchMemberships(token: token)
        } catch let error as AtoError {
            guard gen == generation else { return }
            if error.isUnauthorized {
                // The token was refused outright: forget it, and the next
                // attempt signs in from the stored digest.
                AtoTokenStore.shared.clearSession()
                scheduleReconnect(reason: error.text)
            } else {
                handleFatal(error.text, retryAfter: error.retryAfter)
            }
            return
        } catch is CancellationError {
            return
        } catch {
            guard gen == generation, !Task.isCancelled else { return }
            scheduleReconnect(reason: L("Server unreachable"))
            return
        }

        guard gen == generation, !Task.isCancelled else { return }
        guard !memberships.isEmpty else {
            handleFatal(L("This account is not an agent in any Ato workspace"))
            return
        }

        await loadQueueNames(token: token)
        guard gen == generation, !Task.isCancelled else { return }

        guard let url = AtoEndpoints.hubURL(token: token) else {
            handleFatal(L("Could not build a socket URL for this server"))
            return
        }

        let connection = SignalRConnection(url: url, session: session) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event, generation: gen)
            }
        }
        socket = connection
        connection.connect()

        startOpenDeadline(generation: gen)
        scheduleRefresh(token: token, generation: gen)
    }

    private var username: String {
        memberships.first?.DisplayName?.nilIfBlankAto ?? AtoTokenStore.shared.email
    }

    private func handle(_ event: SignalRConnection.ConnectionEvent, generation gen: Int) {
        guard gen == generation, !isStopping else { return }

        switch event {
        case .connected:
            openDeadlineTask?.cancel(); openDeadlineTask = nil
            attempt = 0
            state = .connected(username: username)
            startPinging(generation: gen)
            logMessages("ato: connected, \(memberships.count) workspace(s)")

        case .invocation(let target, let payload):
            switch target {
            case "onConversationUpdated": handleConversationUpdate(payload)
            // Reaches a connection only for conversations it has joined, which
            // this one never does — taken when it comes, polled for when not.
            case "onMessageTranscribed":  handleMessageTranscribed(payload)
            default: break
            }

        case .rejected(let reason):
            // The handshake is where an expired or refused token shows up.
            AtoTokenStore.shared.clearSession()
            scheduleReconnect(reason: reason)

        case .failed(let reason):
            scheduleReconnect(reason: reason)

        case .closed(let reason):
            scheduleReconnect(reason: reason ?? L("Connection closed"))
        }
    }

    private func startOpenDeadline(generation gen: Int) {
        openDeadlineTask?.cancel()
        openDeadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.openDeadline))
            guard !Task.isCancelled, let self, !self.isStopping, gen == self.generation else { return }
            guard !self.state.isConnected else { return }
            self.scheduleReconnect(reason: L("Server did not answer"))
        }
    }

    private func startPinging(generation gen: Int) {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pingInterval))
                guard !Task.isCancelled else { return }
                guard let self, gen == self.generation else { return }
                self.socket?.ping()
            }
        }
    }

    /// Trades the token for the next one before it runs out.
    ///
    /// The open socket is left alone: it was authorised when it opened, and
    /// reconnecting just to carry a fresher token would open a gap in which a
    /// message could slip past. The new token serves REST calls and whatever
    /// connection comes next.
    private func scheduleRefresh(token: String, generation gen: Int) {
        refreshTask?.cancel()
        let expiry = AtoRules.expiry(ofJWT: token) ?? Date().addingTimeInterval(2 * 3600)
        let delay = max(60, expiry.timeIntervalSinceNow - Self.refreshLead)

        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, gen == self.generation, !self.isStopping else { return }
            do {
                let next = try await self.refreshSession()
                guard gen == self.generation else { return }
                self.scheduleRefresh(token: next, generation: gen)
            } catch {
                guard gen == self.generation else { return }
                // A refresh refused is a session over: start again from the
                // digest, behind the sign-in floor.
                logMessages("ato: refresh failed, signing in again")
                AtoTokenStore.shared.clearSession()
                self.startAttempt()
            }
        }
    }

    // MARK: - Reconnect

    private func handleFatal(_ reason: String, retryAfter: TimeInterval? = nil) {
        generation += 1
        teardown()
        state = .failed(reason)
        logMessages("ato: stopped — \(reason)")

        guard !isStopping, let retryAfter, retryAfter > 0,
              retryAfter <= Self.maximumUnattendedRetry
        else { return }

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(retryAfter + 1))
            guard !Task.isCancelled, let self, !self.isStopping else { return }
            self.startAttempt()
        }
    }

    private func scheduleReconnect(reason: String) {
        guard !isStopping else { return }

        socket?.disconnect(); socket = nil
        pingTask?.cancel(); pingTask = nil
        openDeadlineTask?.cancel(); openDeadlineTask = nil
        refreshTask?.cancel(); refreshTask = nil

        state = .failed(reason)

        let backoff = min(Self.backoffFloor * pow(2.0, Double(attempt)), Self.backoffCeiling)
        let delay = backoff * Double.random(in: 1.0...1.3)
        attempt += 1

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !self.isStopping else { return }
            self.startAttempt()
        }
    }

    // MARK: - Events

    private func handleConversationUpdate(_ data: Data) {
        guard let update = try? JSONDecoder().decode(AtoConversationUpdate.self, from: data)
        else { return }

        // Before the rule: your own reply is what makes the customer's next
        // message yours, and it arrives on this same stream.
        let key = update.conversationId.lowercased()
        switch AtoRules.engagement(after: update, memberships: memberships) {
        case .engage:  setEngaged(key, true)
        case .release: setEngaged(key, false)
        case .keep:    break
        }

        // Any agent speaking settles it on the stream from here on, so an
        // earlier "not yours" answer for this conversation is stale.
        if update.lastMessageSenderType == AtoSenderType.agent.rawValue {
            answererChecked.remove(key)
        }

        guard AtoRules.shouldNotify(update, memberships: memberships,
                                    engaged: Set(engaged.keys))
        else {
            if AtoRules.needsAnswererLookup(update, memberships: memberships,
                                            engaged: Set(engaged.keys),
                                            checked: answererChecked) {
                answererChecked.insert(key)
                Task { [weak self] in await self?.lookUpAnswerer(for: update, data: data) }
            }
            return
        }

        // The same customer message comes back on every later change to the
        // conversation — a queue set, a tag added. Announced once.
        let stamp = update.lastMessageOnUtc ?? ""
        guard announced[update.conversationId] != stamp else { return }
        announced[update.conversationId] = stamp

        Task { [weak self] in
            guard let self else { return }
            let sender = await self.contactName(update.contactId) ?? "Ato"
            // `[anexo]` says a file came and nothing about which. Asking costs
            // one request and is the difference between a card that reads
            // "[anexo]" and one you can listen to.
            let audio = AtoRules.isAttachmentPreview(update.lastMessagePreview)
                ? await self.latestVoiceNote(in: update.conversationId)
                : nil
            self.ingest(update, sender: sender, audio: audio)
            if audio?.transcript.isPending == true {
                self.followTranscript(messageID: AtoRules.messageID(update),
                                      conversationID: update.conversationId)
            }
        }
    }

    // MARK: - Voice messages

    /// The voice note on the customer's newest message, or nil when that
    /// message carries no audio or Ato could not be asked.
    private func latestVoiceNote(in conversationID: String) async -> InboxAudio? {
        var components = URLComponents(
            url: AtoEndpoints.supportService.appendingPathComponent("OData/Messages"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = AtoRules.latestCustomerMessageQuery(conversationID: conversationID)
        guard let url = components.url,
              let data = await fetchOK(url, token: AtoTokenStore.shared.token),
              let row = AtoRules.firstMessage(inPage: data)
        else { return nil }
        return AtoRules.voiceNote(in: row)
    }

    /// Asks again while Ato is still transcribing: it does that after the
    /// message has arrived, and the event that says it is done only reaches
    /// connections that have joined the conversation. Backs off, and gives up
    /// after about two minutes — the audio is there to listen to regardless.
    private func followTranscript(messageID: String, conversationID: String) {
        guard transcriptFollows.insert(messageID).inserted else { return }
        Task { [weak self] in
            for delay in [4.0, 8, 15, 30, 60] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self else { return }
                guard let current = MessageInbox.shared.messages.first(where: { $0.id == messageID })?.audio,
                      current.transcript.isPending
                else { break }
                guard let fresh = await self.latestVoiceNote(in: conversationID),
                      fresh.attachmentID == current.attachmentID
                else { continue }
                self.applyVoiceNote(fresh, to: messageID)
                if !fresh.transcript.isPending { break }
            }
            self?.transcriptFollows.remove(messageID)
        }
    }

    private var transcriptFollows: Set<String> = []

    private func handleMessageTranscribed(_ data: Data) {
        guard let event = try? JSONDecoder().decode(AtoMessageTranscribed.self, from: data) else { return }
        for message in MessageInbox.shared.messages where message.source == .ato {
            guard let audio = message.audio,
                  let updated = AtoRules.applying(event, to: audio)
            else { continue }
            applyVoiceNote(updated, to: message.id)
        }
    }

    private func applyVoiceNote(_ audio: InboxAudio, to messageID: String) {
        MessageInbox.shared.update(messageID) { message in
            message.audio = audio
            message.body = Self.cardBody(for: audio)
        }
    }

    /// What the list, the pill and the banner say for a voice message: what
    /// was said once Ato has it, and that it is a voice message until then.
    static func cardBody(for audio: InboxAudio) -> String {
        audio.transcript.text ?? "🎤 " + L("Voice message")
    }

    /// The audio itself, for the card to play. Kept for the few most recent,
    /// so a second press does not download it again.
    ///
    /// The storage service answers a short-lived address for the file rather
    /// than the file: the console puts that address straight into an `<audio>`
    /// tag, so it is fetched here with no credentials of ours on it.
    func voiceNoteData(_ audio: InboxAudio) async throws -> Data {
        if let cached = voiceNoteCache.first(where: { $0.id == audio.storageFileID }) {
            return cached.data
        }
        var components = URLComponents(
            url: AtoEndpoints.storageService.appendingPathComponent("StorageObject/GetObject"),
            resolvingAgainstBaseURL: false
        )!
        // Both are required: without the tenant it answers 400.
        guard let tenant = await tenantID() else { throw AtoError(L("Couldn't load the audio")) }
        components.queryItems = [URLQueryItem(name: "id", value: audio.storageFileID),
                                 URLQueryItem(name: "tenantId", value: tenant)]
        guard let url = components.url else { throw AtoError(L("Couldn't load the audio")) }

        let (answer, http) = try await send(url: url, method: "GET", token: AtoTokenStore.shared.token)
        if http.statusCode == 401 { throw AtoError(L("Session expired"), isUnauthorized: true) }
        guard http.statusCode == 200, let fileURL = AtoRules.objectURL(fromStorageObject: answer)
        else { throw AtoError(L("Couldn't load the audio")) }

        let (data, response) = try await session.data(from: fileURL)
        guard (response as? HTTPURLResponse)?.statusCode ?? 0 < 300, !data.isEmpty,
              data.count <= AtoEndpoints.maxUploadBytes
        else { throw AtoError(L("Couldn't load the audio")) }

        voiceNoteCache.insert((audio.storageFileID, data), at: 0)
        if voiceNoteCache.count > 6 { voiceNoteCache.removeLast() }
        return data
    }

    private var voiceNoteCache: [(id: String, data: Data)] = []

    /// The tenant the signed-in person belongs to, which the storage service
    /// wants beside a file's id. Sign-in answers it, and it is kept — an id,
    /// not a secret. The token does not carry it, so a session restored from
    /// the Keychain asks the profile the console itself reads it from.
    private static let tenantKey = "atoTenantID"

    private func tenantID() async -> String? {
        if let stored = UserDefaults.standard.string(forKey: Self.tenantKey), !stored.isEmpty {
            return stored
        }
        if let claimed = AtoRules.tenantID(ofJWT: AtoTokenStore.shared.token) { return claimed }
        let url = AtoEndpoints.userService.appendingPathComponent("UserProfile/GetByAuthPersonAsync")
        guard let data = await fetchOK(url, token: AtoTokenStore.shared.token),
              let tenant = AtoRules.tenantID(fromProfile: data)
        else { return nil }
        UserDefaults.standard.set(tenant, forKey: Self.tenantKey)
        return tenant
    }

    // MARK: - Conversations you are answering

    /// Conversations you replied to, and when. In `UserDefaults` rather than
    /// memory: a restart between your reply and the customer's answer must not
    /// make the answer someone else's. Ids only — nothing anyone said.
    private static let engagedKey = "atoEngagedConversations"

    private lazy var engaged: [String: Date] = {
        let stored = UserDefaults.standard.dictionary(forKey: Self.engagedKey) as? [String: Double] ?? [:]
        return AtoRules.pruned(stored.mapValues { Date(timeIntervalSince1970: $0) })
    }()

    /// Conversations already asked about this session, so a busy one costs
    /// one request rather than one per message.
    private var answererChecked: Set<String> = []

    /// Asks Ato who answered this conversation last; if it was you, it is
    /// yours, and the update that prompted the question is handled again.
    private func lookUpAnswerer(for update: AtoConversationUpdate, data: Data) async {
        guard let membership = memberships.first(where: {
            $0.WorkspaceId.lowercased() == update.workspaceId?.lowercased()
        }) else { return }
        var components = URLComponents(
            url: AtoEndpoints.supportService.appendingPathComponent("OData/Messages"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "$filter",
                         value: "ConversationId eq \(update.conversationId) and SenderType eq 'Agent'"),
            URLQueryItem(name: "$orderby", value: "AddedOnUtc desc"),
            URLQueryItem(name: "$top", value: "1"),
            URLQueryItem(name: "$select", value: "SenderId"),
        ]
        guard let url = components.url,
              let body = await fetchOK(url, token: AtoTokenStore.shared.token),
              let row = (try? JSONDecoder().decode(ODataPage<SenderRow>.self, from: body))?.value.first,
              row.SenderId?.lowercased() == membership.AgentId.lowercased()
        else { return }

        setEngaged(update.conversationId, true)
        handleConversationUpdate(data)
    }

    private struct SenderRow: Decodable { let SenderId: String? }

    private func setEngaged(_ conversationID: String, _ on: Bool) {
        let key = conversationID.lowercased()
        if on {
            engaged[key] = Date()
        } else {
            guard engaged.removeValue(forKey: key) != nil else { return }
        }
        engaged = AtoRules.pruned(engaged)
        UserDefaults.standard.set(engaged.mapValues { $0.timeIntervalSince1970 }, forKey: Self.engagedKey)
    }

    private func ingest(_ update: AtoConversationUpdate, sender: String, audio: InboxAudio? = nil) {
        let membership = memberships.first {
            $0.WorkspaceId.lowercased() == update.workspaceId?.lowercased()
        }
        let isMine = update.assignedToAgentId != nil
            && update.assignedToAgentId?.lowercased() == membership?.AgentId.lowercased()
        // The queue is only worth showing when it is why you are being told.
        let queueName = isMine ? nil : update.queueId.flatMap { queueNames[$0.lowercased()] }

        let message = InboxMessage(
            id: AtoRules.messageID(update),
            source: .ato,
            kind: .directMessage,
            sender: sender,
            channel: queueName,
            conversationID: update.conversationId,
            body: audio.map(Self.cardBody(for:)) ?? AtoRules.body(update) ?? L("📎 Sent a file"),
            timestamp: AtoRules.date(update.lastMessageOnUtc) ?? Date(),
            link: AtoEndpoints.conversationLink(update.conversationId),
            audio: audio,
            // `[anexo]` is Ato saying a file came, not the customer saying it.
            text: AtoRules.isAttachmentPreview(update.lastMessagePreview) ? nil : AtoRules.body(update)
        )
        MessageInbox.shared.ingest(message)
    }

    // MARK: - Who we are

    private func fetchMemberships(token: String) async throws -> [AtoMembership] {
        let url = AtoEndpoints.supportService.appendingPathComponent("Agents/me")
        let (data, http) = try await send(url: url, method: "GET", token: token)
        switch http.statusCode {
        case 200:
            guard let rows = try? JSONDecoder().decode([AtoMembership].self, from: data) else {
                throw AtoError(L("Unexpected response from server"))
            }
            return rows
        case 401, 403:
            throw AtoError(L("Session expired"), isUnauthorized: true)
        default:
            throw AtoError(L("Server returned \(http.statusCode)"))
        }
    }

    /// Names for the queues you belong to, for the line under the sender.
    /// Best effort: a card without a queue name is still a card.
    private func loadQueueNames(token: String) async {
        var names: [String: String] = [:]
        for membership in memberships {
            var components = URLComponents(
                url: AtoEndpoints.supportService.appendingPathComponent("OData/Queues"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "$filter", value: "WorkspaceId eq \(membership.WorkspaceId)"),
                URLQueryItem(name: "$select", value: "QueueId,Name"),
            ]
            guard let url = components.url,
                  let data = await fetchOK(url, token: token),
                  let page = try? JSONDecoder().decode(ODataPage<QueueRow>.self, from: data)
            else { continue }
            for row in page.value { names[row.QueueId.lowercased()] = row.Name }
        }
        queueNames = names
    }

    private func contactName(_ contactID: String?) async -> String? {
        guard let contactID, !contactID.isEmpty else { return nil }
        if let known = contactNames[contactID] { return known }

        var components = URLComponents(
            url: AtoEndpoints.supportService.appendingPathComponent("OData/Contacts"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "$filter", value: "ContactId eq \(contactID)"),
            URLQueryItem(name: "$select", value: "ContactId,DisplayName,PhoneE164"),
        ]
        guard let url = components.url,
              let data = await fetchOK(url, token: AtoTokenStore.shared.token),
              let row = (try? JSONDecoder().decode(ODataPage<ContactRow>.self, from: data))?.value.first
        else { return nil }

        let name = AtoRules.displayName(row.DisplayName) ?? row.PhoneE164.map { "+\($0)" }
        if let name { contactNames[contactID] = name }
        return name
    }

    /// A GET whose body is only worth having on a 200; anything else is nil.
    private func fetchOK(_ url: URL, token: String) async -> Data? {
        guard let result = try? await send(url: url, method: "GET", token: token) else { return nil }
        return result.1.statusCode == 200 ? result.0 : nil
    }

    private struct ODataPage<Row: Decodable>: Decodable { let value: [Row] }
    private struct QueueRow: Decodable { let QueueId: String; let Name: String }
    private struct ContactRow: Decodable { let DisplayName: String?; let PhoneE164: String? }

    // MARK: - Tokens

    /// A token good for at least a few more minutes: the stored one, a
    /// refreshed one, or a fresh sign-in, in that order of preference.
    private func validToken() async throws -> String {
        let store = AtoTokenStore.shared
        if !store.token.isEmpty,
           let expiry = AtoRules.expiry(ofJWT: store.token),
           expiry.timeIntervalSinceNow > 5 * 60 {
            return store.token
        }
        if !store.tokenID.isEmpty, let refreshed = try? await refreshSession() {
            return refreshed
        }
        return try await signIn()
    }

    private func signIn() async throws -> String {
        await waitForLoginWindow()
        try Task.checkCancellation()

        let store = AtoTokenStore.shared
        let url = AtoEndpoints.userService.appendingPathComponent("Auth/Login")
        let body: [String: Any] = [
            "Email": store.email,
            "Password": store.passwordDigest,
            "Origin": "actuar",
        ]

        lastLoginAttempt = Date()
        let (data, http) = try await send(url: url, method: "POST", json: body,
                                          origin: AtoEndpoints.accounts)
        switch http.statusCode {
        case 200, 201:
            return try storeSession(from: data)
        case 400, 401:
            throw AtoError(L("Wrong email or password"))
        case 403:
            throw AtoError(L("This account cannot sign in"))
        case 429:
            throw AtoError(L("Too many sign-in attempts — not a password problem. Try again in a minute."),
                           retryAfter: Self.minimumLoginInterval)
        case 500...599:
            throw AtoError(L("Server returned \(http.statusCode)"), retryAfter: Self.minimumLoginInterval)
        default:
            throw AtoError(L("Server returned \(http.statusCode)"))
        }
    }

    /// `/Auth/Refresh`: the `TokenId` for a new two-hour token.
    private func refreshSession() async throws -> String {
        let store = AtoTokenStore.shared
        guard !store.tokenID.isEmpty else { throw AtoError(L("Session expired"), isUnauthorized: true) }

        let url = AtoEndpoints.userService.appendingPathComponent("Auth/Refresh")
        let (data, http) = try await send(url: url, method: "POST",
                                          json: ["TokenId": store.tokenID, "AppSource": "Actuar"],
                                          token: store.token.isEmpty ? nil : store.token,
                                          origin: AtoEndpoints.app)
        guard http.statusCode == 200 || http.statusCode == 201 else {
            throw AtoError(L("Session expired"), isUnauthorized: true)
        }
        return try storeSession(from: data)
    }

    private func storeSession(from data: Data) throws -> String {
        guard let auth = try? JSONDecoder().decode(AtoAuthorization.self, from: data),
              let token = auth.Token, !token.isEmpty
        else {
            // Signed in but handed no token: an account linked to several
            // people asks the browser which one to be, and that choice is not
            // something to make on someone's behalf.
            throw AtoError(L("Signed in, but could not read the account"))
        }
        AtoTokenStore.shared.setSession(token: token, tokenID: auth.TokenId ?? "")
        if let tenant = auth.TenantId, !tenant.isEmpty {
            UserDefaults.standard.set(tenant, forKey: Self.tenantKey)
        }
        return token
    }

    private func waitForLoginWindow() async {
        if bypassLoginFloorOnce {
            bypassLoginFloorOnce = false
            return
        }
        guard let lastLoginAttempt else { return }
        let waited = Date().timeIntervalSince(lastLoginAttempt)
        guard waited < Self.minimumLoginInterval else { return }
        try? await Task.sleep(for: .seconds(Self.minimumLoginInterval - waited))
    }

    // MARK: - Sending

    /// Replies to a conversation from the notification card.
    ///
    /// The route and body are the console's own (`POST
    /// /Conversations/{id}/messages` with a `ClientMessageId` it can match its
    /// echo against). Nothing comes back as a notification: the reply returns
    /// as an update whose last sender is an agent, which the filter drops.
    ///
    /// Files go the console's way too: each is uploaded to the storage
    /// service's chat folder first, which answers a `StorageObjectId`, and the
    /// one message then carries the text and every file as `Attachments`. A
    /// voice message is simply an audio file among them, as it is there.
    func sendMessage(conversationID: String, message: String, attachments: [URL] = []) async throws {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }

        // Read up front: a file that cannot be read or is too large is said
        // before anything has gone out.
        var files: [(name: String, mime: String, data: Data)] = []
        for url in attachments {
            guard let data = try? Data(contentsOf: url) else {
                throw AtoError(L("Could not read \(url.lastPathComponent)"))
            }
            guard data.count <= AtoEndpoints.maxUploadBytes else {
                throw AtoError(L("\(url.lastPathComponent) is larger than Ato takes (25 MB)"))
            }
            files.append((url.lastPathComponent,
                          AttachmentKind.mimeType(forExtension: url.pathExtension),
                          data))
        }

        let url = AtoEndpoints.supportService
            .appendingPathComponent("Conversations")
            .appendingPathComponent(conversationID)
            .appendingPathComponent("messages")
        let clientMessageID = UUID().uuidString.lowercased()

        // What has been uploaded survives a token running out halfway, so a
        // retry carries on from there rather than uploading everything twice.
        var uploaded: [[String: Any]] = []

        func attempt(token: String) async throws {
            while uploaded.count < files.count {
                let file = files[uploaded.count]
                let id = try await upload(file.data, name: file.name, mime: file.mime, token: token)
                uploaded.append(AtoRules.attachment(storageFileID: id, fileName: file.name,
                                                    contentType: file.mime, sizeBytes: file.data.count))
            }
            var body: [String: Any] = ["ClientMessageId": clientMessageID]
            if !text.isEmpty { body["Body"] = text }
            if !uploaded.isEmpty { body["Attachments"] = uploaded }

            let (_, http) = try await send(url: url, method: "POST", json: body, token: token)
            switch http.statusCode {
            case 200, 201, 204: return
            case 401: throw AtoError(L("Session expired"), isUnauthorized: true)
            case 403: throw AtoError(L("Ato did not let this account reply to that conversation"))
            case 404: throw AtoError(L("That conversation no longer exists in Ato"))
            case 422: throw AtoError(L("Ato refused the reply — the conversation may be closed or assigned to someone else"))
            default:  throw AtoError(L("Server returned \(http.statusCode)"))
            }
        }

        do {
            try await attempt(token: AtoTokenStore.shared.token)
        } catch let error as AtoError where error.isUnauthorized {
            // Two hours is short enough to run out between a notification
            // arriving and the reply being typed.
            bypassLoginFloorOnce = true
            AtoTokenStore.shared.setSession(token: "", tokenID: AtoTokenStore.shared.tokenID)
            try await attempt(token: try await validToken())
        }
        // Answered from the card: the customer's next word is yours, without
        // waiting for the echo on the hub to say so.
        setEngaged(conversationID, true)
    }

    /// `POST /FileUpload/Upload?folder=19`: the file and its content type as
    /// form fields, answering the `StorageObjectId` a message attaches.
    private func upload(_ data: Data, name: String, mime: String, token: String) async throws -> String {
        var components = URLComponents(
            url: AtoEndpoints.storageService.appendingPathComponent("FileUpload/Upload"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "folder", value: AtoEndpoints.chatUploadFolder)]
        guard let url = components.url else { throw AtoError(L("Unexpected response from server")) }

        var form = MultipartBody()
        form.addFile(name: "file", filename: name, mimeType: mime, contents: data)
        form.addField(name: "contentType", value: mime)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(AtoEndpoints.app.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(AtoEndpoints.app.absoluteString + "/", forHTTPHeaderField: "Referer")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finished()

        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AtoError(L("Unexpected response from server"))
        }
        switch http.statusCode {
        case 200, 201:
            guard let id = AtoRules.storageObjectID(fromUpload: body) else {
                throw AtoError(L("Ato did not accept \(name)"))
            }
            return id
        case 401: throw AtoError(L("Session expired"), isUnauthorized: true)
        case 413: throw AtoError(L("\(name) is larger than Ato takes (25 MB)"))
        default:  throw AtoError(L("Ato did not accept \(name)"))
        }
    }

    // MARK: - HTTP

    private func send(url: URL,
                      method: String,
                      json: [String: Any]? = nil,
                      token: String? = nil,
                      origin: URL = AtoEndpoints.app) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(origin.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(origin.absoluteString + "/", forHTTPHeaderField: "Referer")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AtoError(L("Unexpected response from server"))
        }
        return (data, http)
    }

    // MARK: - Errors

    struct AtoError: Error, LocalizedError {
        let text: String
        let retryAfter: TimeInterval?
        let isUnauthorized: Bool

        init(_ text: String, retryAfter: TimeInterval? = nil, isUnauthorized: Bool = false) {
            self.text = text
            self.retryAfter = retryAfter
            self.isUnauthorized = isUnauthorized
        }

        var errorDescription: String? { text }
    }
}

private extension String {
    var nilIfBlankAto: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
