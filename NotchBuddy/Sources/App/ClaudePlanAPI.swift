import Foundation
import Security
// Reads Claude Code's own login token, which the App Store build is
// containerised away from — and the whole AI Agents feature compiles out there
// anyway. Fenced for the same reason as the rest of it.
#if !APPSTORE

/// Asks Anthropic for the session and week figures that Claude Code's `/usage`
/// shows, using the token Claude Code itself signed in with.
///
/// The reason this exists at all: the statusline relay can only fire from
/// Claude Code's terminal UI. Someone using the desktop app has no status line,
/// so the relay never runs and the gauges stay empty forever. This is the only
/// other way to the numbers.
///
/// What it will not do, deliberately:
///
/// * **Never touch `refreshToken`.** Refreshing rotates the token server-side,
///   which invalidates the copy Claude Code holds — Notchy would silently sign
///   the user out of their own CLI. An expired token here means "stale, Claude
///   Code has not run lately", and the answer to that is to wait, not to act.
/// * **Never keep the token.** Not in a property, not in `AppState`, not in
///   `UserDefaults`, not as a payload on an error. Claude Code rotates it in
///   place, so a cached copy is wrong within hours anyway; reading it fresh
///   costs one silent Keychain call once the user has allowed it.
/// * **Never pretend to be Claude Code.** No forged `User-Agent`. If the
///   endpoint starts refusing other callers, that is an answer, not an obstacle.
///
/// This is an undocumented endpoint reached with a token issued to another
/// application, which is why it is off until the user switches it on.
actor ClaudePlanAPI {
    static let shared = ClaudePlanAPI()

    /// Why a reading did not happen.
    ///
    /// Carries no payload on purpose. An error holding the token, or the
    /// response body, is an error that reaches a log line or a crash report one
    /// `localizedDescription` later.
    enum Failure: Error {
        /// Nobody signed in here, or the copy on disk has expired. Transient:
        /// the next run of Claude Code fixes it.
        case noCredentials
        /// The user refused the Keychain dialog. The poller must stop asking.
        case denied
        /// The Keychain is locked. Transient.
        case locked
        /// The token was rejected.
        case unauthorized
        /// Told to slow down, with the server's own interval when it gave one.
        case rateLimited(TimeInterval?)
        case transport
        /// A 200 that did not contain a window worth showing.
        case unreadable
        /// The account has no session or weekly limits to report — Claude Code
        /// signed in with an API key rather than a Pro or Max subscription.
        /// Nothing to retry: this is a property of the account, not a hiccup.
        case notApplicable
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let service = "Claude Code-credentials"

    /// Ephemeral, and then some. Ephemeral already means no credential store and
    /// no on-disk cache; the two lines after it say so outright, because the one
    /// thing this session must never do is write any part of this exchange down.
    ///
    /// `waitsForConnectivity` is off: a tick that cannot go now should fail and
    /// let the next one try, not hold a request open across a network change.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Fetching

    /// One reading, or why there isn't one.
    ///
    /// Retries exactly once on a 401, re-reading the token first: the usual
    /// cause is Claude Code having rotated it between the read and the request.
    /// A second 401 is a real refusal and latches the caller.
    func fetch() async -> Result<PlanUsage, Failure> {
        let first = await attempt()
        if case .failure(.unauthorized) = first {
            return await attempt()
        }
        return first
    }

    private func attempt() async -> Result<PlanUsage, Failure> {
        let token: String
        switch Self.token() {
        case .success(let t): token = t
        case .failure(let why): return .failure(why)
        }

        var request = URLRequest(url: Self.endpoint)
        // The token goes in a header and nowhere else. `URLError` carries
        // `failingURL` but never headers, so a logged transport failure cannot
        // take the token with it.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failure(.transport)
        }

        guard let http = response as? HTTPURLResponse else { return .failure(.transport) }
        switch http.statusCode {
        case 200:
            // A 200 with no windows is what a plan without limits looks like.
            // Not an error worth shouting about, and not a reason to blank
            // whatever is already on screen.
            guard let usage = ClaudePlanGauge.parse(usageJSON: data) else {
                return .failure(.unreadable)
            }
            return .success(usage)
        case 400:
            // What an API-billed organisation gets: "Usage limits are not
            // applicable to API organizations". A real answer, not a fault, so
            // it must not be retried or reported as a network problem.
            return .failure(.notApplicable)
        case 401, 403:
            return .failure(.unauthorized)
        case 429:
            let retry = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            return .failure(.rateLimited(retry))
        default:
            return .failure(.transport)
        }
    }

    // MARK: - The token

    /// Finds the access token without keeping it.
    ///
    /// Environment first because it costs nothing and raises no dialog. Worth
    /// knowing that an app launched from Finder inherits no shell environment,
    /// so this only ever fires for someone who set it with `launchctl setenv`
    /// or started Notchy from a terminal.
    private static func token() -> Result<String, Failure> {
        if let fromEnv = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
           !fromEnv.isEmpty {
            return .success(fromEnv)
        }

        var query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: NSUserName(),
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)

        // The account convention is Claude Code's own and undocumented. If it
        // ever stops being the unix name, ask again without that constraint
        // rather than reporting a signed-in Mac as signed out.
        if status == errSecItemNotFound {
            query.removeValue(forKey: kSecAttrAccount as String)
            status = SecItemCopyMatching(query as CFDictionary, &result)
        }

        switch status {
        case errSecSuccess:
            break
        case errSecUserCanceled, errSecAuthFailed:
            return .failure(.denied)
        case errSecInteractionNotAllowed, errSecInteractionRequired:
            return .failure(.locked)
        default:
            return .failure(.noCredentials)
        }

        guard let data = result as? Data else { return .failure(.noCredentials) }
        return parse(credentials: data)
    }

    /// Pulls the access token out of Claude Code's stored JSON.
    ///
    /// Every key is named, in the spirit of `ClaudeAccount.init?(claudeJSON:)`:
    /// a decoder that took the whole object would quietly start carrying
    /// whatever Claude Code adds to it next — including the refresh token this
    /// must never hold.
    private static func parse(credentials data: Data) -> Result<String, Failure> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return .failure(.noCredentials)
        }
        // An expiry in the past is not a dead account — it is a token Claude
        // Code has not refreshed yet because it has not run. Sending it would
        // spend a 401 and a retry to learn nothing.
        if let expiry = ClaudeAccount.date(oauth["expiresAt"]), expiry <= Date() {
            return .failure(.noCredentials)
        }
        return .success(token)
    }

    /// Whether Claude Code has credentials on this Mac at all.
    ///
    /// Asks for the item's attributes and **not** its data, which is a query
    /// macOS answers without putting up the access dialog. That is what lets
    /// Settings say what it can see without spending the one prompt the user
    /// gets.
    nonisolated static func credentialsPresent() -> Bool {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }
}

extension ClaudePlanAPI.Failure {
    /// What to say in the log and in Settings. Outcomes only — never a body,
    /// never a header, never the token.
    var plainLine: String {
        switch self {
        case .noCredentials: return "no Claude Code login found on this Mac"
        case .denied:        return "keychain access refused"
        case .locked:        return "keychain locked"
        case .unauthorized:  return "the token was rejected"
        case .rateLimited:   return "asked to slow down"
        case .transport:     return "could not reach Anthropic"
        case .unreadable:    return "no session or weekly limit came back"
        case .notApplicable: return "this Claude Code login is an API key, which has no session or weekly limit"
        }
    }
}

#endif
