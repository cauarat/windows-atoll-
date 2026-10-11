import Foundation

/// What can honestly be said about the Claude account on this Mac.
///
/// Claude Code keeps a summary of the signed-in account in `~/.claude.json`,
/// and that is all this reads. The login token is not in there — it is in the
/// Keychain, where Claude Code put it — and Notchy never goes looking for it.
/// Nothing here is written to disk, sent anywhere, or kept after the panel
/// closes.
///
/// The limit worth being plain about: **a file saying somebody signed in is not
/// the same as being signed in now.** A revoked token looks identical from
/// outside. So this reports what it saw and when, and never claims a session is
/// good.
struct ClaudeAccount: Equatable, Sendable {
    /// Who, as Claude Code recorded them. Display name if there is one, since
    /// it is the least sensitive thing that still identifies the account.
    var name: String?
    var email: String?
    /// Only the organisation's name. Its role, seat tier and uuids are its own
    /// business and say nothing a person reading this wants to know.
    var organization: String?
    /// Whether the last profile fetch saw a subscription. Not whether it is
    /// still valid.
    var hasSubscription: Bool
    /// When Claude Code last refreshed the summary above.
    var profileFetched: Date?
    var trialEnds: Date?

    /// Nothing recorded on this Mac.
    static let none = ClaudeAccount(hasSubscription: false)

    var isSignedIn: Bool { name != nil || email != nil }

    /// What to call the account in one line.
    var label: String { name ?? email ?? "Signed in" }

    /// Read the summary out of `~/.claude.json`'s bytes.
    ///
    /// Every key is named here on purpose. The file holds a great deal besides
    /// — project histories, caches, onboarding flags — and a parser that
    /// decoded the whole thing would quietly start carrying whatever Claude
    /// Code adds to it next.
    init?(claudeJSON data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let account = root["oauthAccount"] as? [String: Any]
        name = (account?["displayName"] as? String)?.nonEmpty
            ?? (account?["fullName"] as? String)?.nonEmpty
        email = (account?["emailAddress"] as? String)?.nonEmpty
        organization = (account?["organizationName"] as? String)?.nonEmpty
        hasSubscription = root["hasAvailableSubscription"] as? Bool ?? false
        profileFetched = Self.date(account?["profileFetchedAt"])
        trialEnds = Self.date(account?["claudeCodeTrialEndsAt"])
    }

    init(name: String? = nil, email: String? = nil, organization: String? = nil,
         hasSubscription: Bool = false, profileFetched: Date? = nil, trialEnds: Date? = nil) {
        self.name = name
        self.email = email
        self.organization = organization
        self.hasSubscription = hasSubscription
        self.profileFetched = profileFetched
        self.trialEnds = trialEnds
    }

    /// Claude Code writes these as milliseconds, or as ISO 8601. Take either,
    /// and nothing if it is neither — a date this cannot read is not worth
    /// guessing at.
    static func date(_ raw: Any?) -> Date? {
        // JSONSerialization hands back NSNumber, which bridges to either —
        // but a plain Swift Int does not bridge to Double, so take both rather
        // than depend on which side the value came from.
        let number = (raw as? Double) ?? (raw as? Int).map(Double.init)
        if let ms = number, ms > 0 {
            return Date(timeIntervalSince1970: ms > 1e11 ? ms / 1000 : ms)
        }
        if let s = raw as? String, !s.isEmpty {
            return ISO8601DateFormatter().date(from: s)
        }
        return nil
    }
}

/// One Claude Code session running on this Mac.
///
/// From `~/.claude/sessions/<pid>.json`, which Claude Code writes for its own
/// use. An undocumented private format, so everything is optional and an
/// unreadable file is simply a session that is not listed — never an error.
struct ClaudeSession: Equatable, Identifiable, Sendable {
    var id: String
    var pid: Int32
    var cwd: String
    var status: String
    var startedAt: Date?
    var name: String?

    /// The folder name, which is what a person recognises a session by.
    var project: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    init?(sessionJSON data: Data) {
        guard let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sid = (d["sessionId"] as? String)?.nonEmpty else { return nil }
        id = sid
        pid = Int32(d["pid"] as? Int ?? 0)
        cwd = (d["cwd"] as? String) ?? ""
        status = (d["status"] as? String) ?? "unknown"
        startedAt = ClaudeAccount.date(d["startedAt"])
        name = (d["name"] as? String)?.nonEmpty
    }

    init(id: String, pid: Int32, cwd: String, status: String,
         startedAt: Date? = nil, name: String? = nil) {
        self.id = id; self.pid = pid; self.cwd = cwd
        self.status = status; self.startedAt = startedAt; self.name = name
    }

    /// Whether the process is still there.
    ///
    /// The file outlives a session that was killed, so without this the list
    /// fills up with things that finished days ago.
    var isAlive: Bool { pid > 0 && kill(pid, 0) == 0 }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
