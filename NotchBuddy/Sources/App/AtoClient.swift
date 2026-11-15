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
            guard target == "onConversationUpdated" else { return }
            handleConversationUpdate(payload)

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
        guard let update = try? JSONDecoder().decode(AtoConversationUpdate.self, from: data),
              AtoRules.shouldNotify(update, memberships: memberships)
        else { return }

        // The same customer message comes back on every later change to the
        // conversation — a queue set, a tag added. Announced once.
        let stamp = update.lastMessageOnUtc ?? ""
        guard announced[update.conversationId] != stamp else { return }
        announced[update.conversationId] = stamp

        Task { [weak self] in
            guard let self else { return }
            let sender = await self.contactName(update.contactId) ?? "Ato"
            self.ingest(update, sender: sender)
        }
    }

    private func ingest(_ update: AtoConversationUpdate, sender: String) {
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
            body: AtoRules.body(update) ?? L("📎 Sent a file"),
            timestamp: AtoRules.date(update.lastMessageOnUtc) ?? Date(),
            link: AtoEndpoints.conversationLink(update.conversationId)
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
    func sendMessage(conversationID: String, message: String) async throws {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let url = AtoEndpoints.supportService
            .appendingPathComponent("Conversations")
            .appendingPathComponent(conversationID)
            .appendingPathComponent("messages")
        let body: [String: Any] = [
            "ClientMessageId": UUID().uuidString.lowercased(),
            "Body": text,
        ]

        func attempt(token: String) async throws {
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
