//
//  AgendaClient.swift
//  Notchy
//
//  Today's meetings from Actuar's commercial panel, and the heads-up before
//  each one.
//

import AppKit
import Combine
import Foundation

// MARK: - Settings

/// The Agenda's switches. `@AppStorage` in Settings writes the same keys, and
/// tells ``AgendaClient`` when one changed.
enum AgendaSettings {
    static let enabledKey = "agendaEnabled"
    static let leadKey = "agendaLeadMinutes"
    static let notifyOnboardingKey = "agendaNotifyOnboarding"
    static let notifyBackofficeKey = "agendaNotifyBackoffice"
    private static let notifiedDayKey = "agendaNotifiedDay"
    private static let notifiedKeysKey = "agendaNotifiedKeys"

    /// Off until someone turns it on: it is an Actuar tool, and most people
    /// running Notchy have no panel to read.
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var leadMinutes: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: leadKey)
            return AgendaRules.leadChoices.contains(stored) ? stored : AgendaRules.defaultLeadMinutes
        }
        set { UserDefaults.standard.set(newValue, forKey: leadKey) }
    }

    static var notifyOnboarding: Bool {
        get { UserDefaults.standard.object(forKey: notifyOnboardingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: notifyOnboardingKey) }
    }

    static var notifyBackoffice: Bool {
        get { UserDefaults.standard.object(forKey: notifyBackofficeKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: notifyBackofficeKey) }
    }

    static var notifyDepartments: Set<AgendaDepartment> {
        var set = Set<AgendaDepartment>()
        if notifyOnboarding { set.insert(.onboarding) }
        if notifyBackoffice { set.insert(.backoffice) }
        return set
    }

    /// The heads-ups already given today. Kept so that a relaunch at 08:50
    /// does not announce the 09:00 meeting a second time; filed under the day
    /// so that tomorrow starts clean.
    static func notified(today: String) -> Set<String> {
        guard UserDefaults.standard.string(forKey: notifiedDayKey) == today else { return [] }
        return Set(UserDefaults.standard.stringArray(forKey: notifiedKeysKey) ?? [])
    }

    static func remember(_ keys: [String], today: String) {
        var set = notified(today: today)
        set.formUnion(keys)
        UserDefaults.standard.set(today, forKey: notifiedDayKey)
        UserDefaults.standard.set(Array(set), forKey: notifiedKeysKey)
    }
}

extension Notification.Name {
    /// A meeting is about to start. Object is the meeting's `attemptID`.
    static let agendaMeetingDue = Notification.Name("agendaMeetingDue")
}

// MARK: - Client

/// Reads your meetings for today off the commercial panel, the way its own
/// Agenda does, and says when one is coming.
///
/// - **Sign-in** is the Actuar account Ato keeps, with the panel's
///   `AppSource`, into a token pair of the Agenda's own
///   (``AgendaTokenStore``). It keeps Ato's manners: one full sign-in a
///   minute at most, a refresh before the token runs out, and no retrying a
///   wrong password until the password changes.
/// - **Reading** is the panel's two case lists narrowed to you — the "Eu"
///   filter — every ten minutes, on wake, at midnight and when the tab opens.
///   The panel itself re-reads every minute, so this is the lighter of the two.
/// - **The heads-up** is one deadline on the wall clock, armed for the next
///   meeting. Between deadlines nothing runs.
@MainActor
final class AgendaClient: ObservableObject {
    static let shared = AgendaClient()

    enum Status: Equatable {
        case off
        case signedOut
        case loading
        case ready
        case noPanelAccess
        case failed(String)
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var meetings: [AgendaMeeting] = []
    @Published private(set) var lastUpdated: Date?

    // MARK: Timings

    private static let refreshInterval: TimeInterval = 10 * 60
    /// A tab opened within this of the last read shows that read.
    private static let tabFreshness: TimeInterval = 60
    /// A heads-up is given from a read at most this old; older, it reads first,
    /// so a meeting cancelled or moved in the meantime is not announced.
    private static let reminderFreshness: TimeInterval = 2 * 60
    private static let minimumLoginInterval: TimeInterval = 60
    private static let refreshLead: TimeInterval = 10 * 60

    /// The panel is a web app; its gateway expects a browser.
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    // MARK: State

    private var personID: String?
    private var loopTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var reminderWork: DispatchWorkItem?
    private var generation = 0
    private var observersInstalled = false
    private var cancellables = Set<AnyCancellable>()
    private var lastLoginAttempt: Date?
    /// The credentials a wrong-password answer was given for. Nothing signs
    /// in again with those; new ones clear it.
    private var refusedFingerprint: String?
    /// Fake meetings for looking at the tab without an account. Nothing reads
    /// the network while they are in.
    private var seeded = false

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    private init() {}

    private var credentialsFingerprint: String {
        AtoTokenStore.shared.email + ":" + AtoTokenStore.shared.passwordDigest
    }

    // MARK: - Lifecycle

    /// At launch: reads now if the Agenda is on, and keeps reading.
    func start() {
        installSystemObserversIfNeeded()
        settingsChanged()
    }

    /// Something in Settings moved: on/off, the lead time, which processes ring.
    func settingsChanged() {
        guard AgendaSettings.enabled else {
            stop()
            status = .off
            return
        }
        if loopTask == nil { startLoop() }
        if meetings.isEmpty && fetchTask == nil {
            refresh(force: true)
        } else {
            armReminder()
        }
    }

    /// The Actuar e-mail or password changed: the old session and person are
    /// somebody else's.
    func credentialsChanged() {
        generation += 1
        fetchTask?.cancel(); fetchTask = nil
        AgendaTokenStore.shared.clear()
        personID = nil
        refusedFingerprint = nil
        meetings = []
        lastUpdated = nil
        reminderWork?.cancel(); reminderWork = nil
        guard AgendaSettings.enabled else { return }
        refresh(force: true)
    }

    /// The Agenda tab came up. Reads unless the last read is a minute old or less.
    func tabOpened() {
        refresh(force: false)
    }

    func refresh(force: Bool = true) {
        guard AgendaSettings.enabled, !seeded, fetchTask == nil else { return }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < Self.tabFreshness { return }
        generation += 1
        let gen = generation
        fetchTask = Task { [weak self] in
            await self?.fetch(generation: gen)
            // Only its own: a read started after this one was cancelled owns
            // the slot now.
            if self?.generation == gen { self?.fetchTask = nil }
        }
    }

    private func stop() {
        generation += 1
        loopTask?.cancel(); loopTask = nil
        fetchTask?.cancel(); fetchTask = nil
        personID = nil
        reminderWork?.cancel(); reminderWork = nil
        meetings = []
        lastUpdated = nil
        seeded = false
    }

    /// Every ten minutes, and just after midnight so the new day is read
    /// before anyone looks at it.
    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date()
                let midnight = AgendaRules.day(containing: now).end
                let wait = min(Self.refreshInterval, midnight.timeIntervalSince(now) + 5)
                try? await Task.sleep(for: .seconds(max(30, wait)))
                guard !Task.isCancelled, let self else { return }
                self.refresh(force: true)
            }
        }
    }

    private func installSystemObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true

        // A deadline armed before the lid closed is not to be trusted after it
        // opens; neither is a read from before.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, AgendaSettings.enabled else { return }
                self.refresh(force: true)
                self.armReminder()
            }
            .store(in: &cancellables)
    }

    // MARK: - Reading

    private func fetch(generation gen: Int) async {
        guard AtoTokenStore.shared.hasCredentials else {
            status = .signedOut
            meetings = []
            reminderWork?.cancel()
            return
        }
        if refusedFingerprint == credentialsFingerprint {
            status = .failed(L("Wrong email or password"))
            return
        }
        if meetings.isEmpty { status = .loading }

        do {
            if personID == nil {
                let data = try await rpc(AgendaRules.organizationContextRPC, body: [:])
                personID = AgendaRules.personID(fromOrganizationContext: data)
            }
            guard gen == generation else { return }
            guard let personID else {
                status = .noPanelAccess
                meetings = []
                return
            }

            let day = AgendaRules.day(containing: Date())
            var lists: [[AgendaMeeting]] = []
            for department in AgendaDepartment.allCases {
                lists.append(try await cases(department, personID: personID, day: day))
            }
            guard gen == generation, !Task.isCancelled else { return }

            meetings = AgendaRules.merged(lists)
            lastUpdated = Date()
            status = .ready
            logMessages("agenda: \(meetings.count) meeting(s) today")
            armReminder()
        } catch let error as AgendaError {
            guard gen == generation else { return }
            if error.isNoAccess {
                personID = nil
                status = .noPanelAccess
                meetings = []
            } else {
                status = .failed(error.text)
            }
            logMessages("agenda: \(error.text)")
        } catch is CancellationError {
            return
        } catch {
            guard gen == generation else { return }
            status = .failed(L("Server unreachable"))
        }
    }

    /// Every page of one process's cases, read down to your meetings today.
    ///
    /// A process this account may not read is an empty one rather than a
    /// failure: an Onboarding person has no Backoffice list to be refused.
    private func cases(_ department: AgendaDepartment, personID: String,
                       day: DateInterval) async throws -> [AgendaMeeting] {
        var page = 1
        var found: [AgendaMeeting] = []
        while true {
            try Task.checkCancellation()
            let request = AgendaRules.casesRequest(department, personID: personID, day: day, page: page)
            let data: Data
            do {
                data = try await rpc(request.rpc, body: request.body)
            } catch let error as AgendaError where error.isNoAccess {
                return found
            }
            found += AgendaRules.meetings(fromCases: data, personID: personID, day: day)
            guard let next = AgendaRules.nextPage(after: data, page: page) else { return found }
            page = next
        }
    }

    /// One gateway call, signing in again once if the token is refused.
    private func rpc(_ name: String, body: [String: Any]) async throws -> Data {
        var token = try await validToken()
        for attempt in 0..<2 {
            var request = URLRequest(url: AgendaRules.rpcURL(name))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("public", forHTTPHeaderField: "Content-Profile")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(AgendaRules.panel.absoluteString, forHTTPHeaderField: "Origin")
            request.setValue(AgendaRules.panel.absoluteString + "/", forHTTPHeaderField: "Referer")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AgendaError(L("Unexpected response from server"))
            }
            switch http.statusCode {
            case 200...299:
                return data
            case 401 where attempt == 0:
                // Two hours run out; the next token is one refresh away.
                AgendaTokenStore.shared.setSession(token: "", tokenID: AgendaTokenStore.shared.tokenID)
                token = try await validToken()
            case 401:
                AgendaTokenStore.shared.clear()
                throw AgendaError(L("Session expired"))
            case 403:
                throw AgendaError(L("This Actuar account has no access to the commercial panel"), isNoAccess: true)
            default:
                throw AgendaError(L("Server returned \(http.statusCode)"))
            }
        }
        throw AgendaError(L("Session expired"))
    }

    // MARK: - Tokens

    private func validToken() async throws -> String {
        let store = AgendaTokenStore.shared
        if !store.token.isEmpty,
           let expiry = Self.expiry(ofJWT: store.token),
           expiry.timeIntervalSinceNow > Self.refreshLead {
            return store.token
        }
        if !store.tokenID.isEmpty, let refreshed = try? await refreshSession() {
            return refreshed
        }
        return try await signIn()
    }

    private func signIn() async throws -> String {
        if let lastLoginAttempt {
            let waited = Date().timeIntervalSince(lastLoginAttempt)
            if waited < Self.minimumLoginInterval {
                try await Task.sleep(for: .seconds(Self.minimumLoginInterval - waited))
            }
        }
        let ato = AtoTokenStore.shared
        let fingerprint = credentialsFingerprint
        lastLoginAttempt = Date()
        let (data, http) = try await post(
            AgendaRules.userService.appendingPathComponent("Auth/Login"),
            json: AgendaRules.loginBody(email: ato.email, passwordDigest: ato.passwordDigest)
        )
        switch http.statusCode {
        case 200, 201:
            return try storeSession(from: data)
        case 400, 401:
            refusedFingerprint = fingerprint
            throw AgendaError(L("Wrong email or password"))
        case 403:
            throw AgendaError(L("This account cannot sign in"))
        case 429:
            throw AgendaError(L("Too many sign-in attempts — not a password problem. Try again in a minute."))
        default:
            throw AgendaError(L("Server returned \(http.statusCode)"))
        }
    }

    private func refreshSession() async throws -> String {
        let store = AgendaTokenStore.shared
        let (data, http) = try await post(
            AgendaRules.userService.appendingPathComponent("Auth/Refresh"),
            json: AgendaRules.refreshBody(tokenID: store.tokenID)
        )
        guard http.statusCode == 200 || http.statusCode == 201 else {
            store.clear()
            throw AgendaError(L("Session expired"))
        }
        return try storeSession(from: data)
    }

    private func storeSession(from data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["Token"] as? String, !token.isEmpty
        else { throw AgendaError(L("Signed in, but could not read the account")) }
        AgendaTokenStore.shared.setSession(token: token, tokenID: (object["TokenId"] as? String) ?? "")
        return token
    }

    private func post(_ url: URL, json: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(AgendaRules.panel.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(AgendaRules.panel.absoluteString + "/", forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgendaError(L("Unexpected response from server"))
        }
        return (data, http)
    }

    private static func expiry(ofJWT token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = claims["exp"] as? Double
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    // MARK: - Heads-up

    /// Arms the one deadline for the next heads-up, replacing any other.
    private func armReminder() {
        reminderWork?.cancel()
        reminderWork = nil
        guard AgendaSettings.enabled else { return }
        let now = Date()
        guard let next = AgendaRules.nextReminder(
            meetings, now: now,
            lead: TimeInterval(AgendaSettings.leadMinutes * 60),
            notified: AgendaSettings.notified(today: AgendaRules.dayStamp(now)),
            departments: AgendaSettings.notifyDepartments
        ) else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reminderWork = nil
            Task { await self.reminderDue() }
        }
        reminderWork = work
        // The wall clock, not uptime: an uptime deadline stands still while
        // the Mac sleeps and would ring late by however long the lid was shut.
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(0, next.fireAt.timeIntervalSince(now)),
                                      execute: work)
    }

    /// The deadline came. Read again if the last read is old, then announce
    /// what is still due — all of it at once when two share a time.
    private func reminderDue() async {
        if !seeded, (lastUpdated.map { Date().timeIntervalSince($0) } ?? .infinity) > Self.reminderFreshness {
            if fetchTask == nil { refresh(force: true) }
            await fetchTask?.value
        }
        let now = Date()
        let today = AgendaRules.dayStamp(now)
        let lead = TimeInterval(AgendaSettings.leadMinutes * 60)
        var due: [AgendaMeeting] = []
        var notified = AgendaSettings.notified(today: today)
        while let next = AgendaRules.nextReminder(meetings, now: now, lead: lead, notified: notified,
                                                  departments: AgendaSettings.notifyDepartments),
              next.fireAt <= now.addingTimeInterval(1) {
            due.append(next.meeting)
            notified.insert(next.meeting.reminderKey)
        }
        if let first = due.first {
            AgendaSettings.remember(due.map(\.reminderKey), today: today)
            logMessages("agenda: heads-up for \(due.count) meeting(s)")
            NotificationCenter.default.post(name: .agendaMeetingDue, object: first.attemptID)
        }
        armReminder()
    }

    // MARK: - Preview

    /// Four meetings around now, for looking at the tab and the heads-up
    /// without an Actuar account: `NOTCHY_SEED_AGENDA=1`. The first is due a
    /// minute after launch at the default lead.
    func seedForPreview() {
        seeded = true
        let now = Date()
        func meeting(_ id: String, _ minutes: Double, _ length: Double, _ title: String, _ code: String?,
                     _ stage: String, attempt: Int = 1, state: String = "open") -> AgendaMeeting {
            AgendaMeeting(attemptID: id, meetingID: "m-\(id)", caseID: "c-\(id)",
                          department: AgendaDepartment(stageKey: stage), stageKey: stage,
                          start: now.addingTimeInterval(minutes * 60),
                          end: now.addingTimeInterval((minutes + length) * 60),
                          title: title, publicID: code, attemptSequence: attempt,
                          attemptState: "confirmed", meetingState: state)
        }
        meetings = AgendaRules.merged([[
            meeting("seed-1", -150, 60, "Studio Movimento / actuar", "GB5940", "connection", state: "attended"),
            meeting("seed-2", -20, 90, "Academia Forja", nil, "contact"),
            meeting("seed-3", Double(AgendaSettings.leadMinutes) + 1, 90,
                    "welber vieira freire santos - Toletus GK7045 - Actuar", "GM3941", "connection", attempt: 2),
            meeting("seed-4", 240, 60, "L.A. Esportes", nil, "connection_2"),
        ]])
        lastUpdated = now
        status = .ready
        AgendaSettings.enabled = true
        armReminder()
    }

    // MARK: - Errors

    struct AgendaError: Error, LocalizedError {
        let text: String
        let isNoAccess: Bool

        init(_ text: String, isNoAccess: Bool = false) {
            self.text = text
            self.isNoAccess = isNoAccess
        }

        var errorDescription: String? { text }
    }
}
