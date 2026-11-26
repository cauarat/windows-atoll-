import Foundation

// MARK: - Phone link: what the phone is told, and what it may decide
//
// The hub holds the last list of sessions, the one permission request and the one
// question still waiting, as the island publishes them. It knows nothing about
// sockets or AppState: connections subscribe to it, and a decision from a phone goes
// back to the app through `PhoneLinkHost`. That keeps every rule of
// docs/PHONE_LINK.md testable without a window, exactly as the Rust `hub.rs` does.
//
// The rules that matter:
//   * a phone decision is applied only if its fingerprint is the one of the request that is
//     *still* pending (same session, tool, command and request);
//   * only one decision is ever applied per request;
//   * a request older than 115 s is dismissed, whatever the phone says;
//   * a command cut to 500 characters can be denied from the phone, never allowed;
//   * nothing here can block the agent: the Mac's own card keeps working, and a phone that never
//     answers changes nothing.

// MARK: What the island publishes

struct PhoneSessionIn: Equatable, Sendable {
    var pillId: String
    var agent: String
    var state: String = "idle"
    var statusText: String = ""
    var stepIndex: Int = 0
    var stepCount: Int = 0
    /// Details, sent only to phones that asked for and were offered `details`.
    var steps: [String] = []
    var finalLine: String? = nil
    /// The folder the session runs in; only its last segment is ever kept.
    var project: String? = nil
    var color: String? = nil
    /// The files the session changed, newest last (cap `diffs`).
    var files: [PhoneFileIn] = []
    /// The Mochi this pill wears on the island: `accessory`, `eye`, `shape` and `festive` as their
    /// stored raw values (cap `character`, a Notchy addition). Nothing about the user's work.
    var character: [String: String] = [:]
}

/// One file a session changed, as the island's ticker lists it (cap `diffs`).
struct PhoneFileIn: Equatable, Sendable {
    var id: Int
    var name: String
    var added: Int
    var removed: Int
    var tooLarge: Bool = false
    var isNew: Bool = false
}

/// One line of a file's diff: `+` added, `-` removed, ` ` context, `@` a hunk starts.
struct PhoneDiffLineIn: Equatable, Sendable {
    var kind: String
    var text: String
}

/// A file's diff, read from the island when a phone asks for it.
struct PhoneDiffIn: Equatable, Sendable {
    var name: String
    var added: Int
    var removed: Int
    var tooLarge: Bool
    var lines: [PhoneDiffLineIn]
}

/// The permission request waiting on the island.
struct PhoneApprovalIn: Equatable, Sendable {
    var requestId: String
    var sessionId: String
    var pillId: String
    var tool: String
    var command: String
}

struct PhoneOptionIn: Equatable, Sendable {
    var label: String
    var description: String = ""
}

struct PhoneQuestionItemIn: Equatable, Sendable {
    var question: String
    var options: [PhoneOptionIn]
    var multiSelect: Bool = false
}

/// The question Claude Code is waiting on, as the island has it (cap `answers`).
struct PhoneQuestionIn: Equatable, Sendable {
    var requestId: String
    var sessionId: String
    var pillId: String
    var questions: [PhoneQuestionItemIn]
}

struct PhoneUsageWindowIn: Equatable, Sendable {
    var usedPct: Double
    var resetsAt: UInt64
}

struct PhoneUsagePlanIn: Equatable, Sendable {
    var fiveHour: PhoneUsageWindowIn? = nil
    var sevenDay: PhoneUsageWindowIn? = nil
    var plan: String? = nil
    var resetCredits: Int? = nil
    var updatedAt: UInt64? = nil
}

/// What the island's Claude and Codex pills show (cap `usage`).
struct PhoneUsageIn: Equatable, Sendable {
    var claude: PhoneUsagePlanIn? = nil
    var codex: PhoneUsagePlanIn? = nil
}

/// What a connection may have been offered.
struct PhoneLinkCaps: Equatable, Sendable {
    var details = false
    var answers = false
    var usage = false
    var diffs = false
    /// Notchy's own: each session says which Mochi its pill wears. No switch, like Coucou's `prefs`:
    /// what a character looks like says nothing about the user's work.
    var character = false
    var chat = false

    /// The `caps` of the welcome line, in the Rust order; empty means the field is left out.
    var offered: [String] {
        var list: [String] = []
        if details { list.append("details") }
        if answers { list.append("answers") }
        if usage { list.append("usage") }
        if diffs { list.append("diffs") }
        if character { list.append("character") }
        if chat { list.append("chat") }
        return list
    }

    /// The parts of a `sessions` line that depend on what this phone was offered.
    var sessionsKey: Int { (details ? 1 : 0) | (diffs ? 2 : 0) | (character ? 4 : 0) }
}

/// What reaches a connection's writer.
enum PhoneLinkOut: Equatable, Sendable {
    /// One JSON line, without its newline.
    case line(String)
    /// Tell the phone why, then close.
    case close(code: String, message: String)
}

/// How a decision gets back to the agent. The app's implementation answers the waiting
/// nb-hook exactly as a click on the island would, only for the request still pending.
protocol PhoneLinkHost: AnyObject, Sendable {
    func decide(requestId: String, allow: Bool)
    /// A phone answered a question: one list of labels per question, in order, already checked against
    /// the question's options. Only called for the question still pending; the app builds the agent's
    /// `{question: label}` shape with the island's own `AskQuestion.buildAnswers`.
    func answer(requestId: String, picks: [[String]])
    /// The lines of one file a session changed, read from the island; `reply(nil)` when it no longer has it.
    /// Called from the link's queue; `reply` may be called on any queue.
    func diff(pillId: String, fileId: Int, reply: @escaping @Sendable (PhoneDiffIn?) -> Void)
}

extension PhoneLinkHost {
    func diff(pillId: String, fileId: Int, reply: @escaping @Sendable (PhoneDiffIn?) -> Void) { reply(nil) }
}

/// What became of a decision from a phone.
enum PhoneLinkOutcome: Equatable, Sendable {
    case applied
    /// Not the pending request (another command, or already answered).
    case noMatch
    /// The request was pending but is older than the TTL.
    case late
    /// Neither `allow` nor `deny`, or picks that do not match the question.
    case invalid
    /// `allow` for a request whose command was cut to fit the phone: refused, the request stays pending.
    case tooLong
}

/// A subscriber's way out: true when the line was taken, false when the phone cannot keep up
/// (it is then dropped and closes, and reconnects to a fresh picture).
typealias PhoneLinkSender = @Sendable (PhoneLinkOut) -> Bool

final class PhoneLinkHub: @unchecked Sendable {
    private struct Session: Equatable {
        var pillId: String
        var agent: String
        var state: String
        var statusText: String
        var stepIndex: Int
        var stepCount: Int
        var updatedAt: UInt64
        var steps: [String]
        var finalLine: String?
        var project: String?
        var color: String?
        var files: [PhoneFileIn]
        var character: [String: String]

        func sameContent(as other: Session) -> Bool {
            var a = self, b = other
            a.updatedAt = 0; b.updatedAt = 0
            return a == b
        }
    }

    private struct Approval {
        var requestId: String
        var fingerprint: String
        var pillId: String
        var tool: String
        var command: String
        /// The command was longer than `maxCommandChars` and the phone is shown only the start.
        var truncated: Bool
        var createdAt: UInt64
    }

    private struct Question {
        var requestId: String
        var fingerprint: String
        var pillId: String
        var items: [PhoneQuestionItemIn]
        var createdAt: UInt64
    }

    private struct Sub {
        let id: UInt64
        let send: PhoneLinkSender
        let caps: PhoneLinkCaps
    }

    private let host: PhoneLinkHost
    private let lock = NSLock()
    private var sessions: [Session] = []
    private var approval: Approval?
    private var question: Question?
    /// The last `usage` line (nil: the island has nothing to say).
    private var usage: String?
    private var subs: [Sub] = []
    private var nextSub: UInt64 = 0

    /// How many phones are connected, told whenever it changes (on the queue that changed it).
    private let onClients: (@Sendable (Int) -> Void)?

    init(host: PhoneLinkHost, onClients: (@Sendable (Int) -> Void)? = nil) {
        self.host = host
        self.onClients = onClients
    }

    // MARK: Publishing

    /// The island's current picture. Sends the phones only what changed.
    func publish(sessions incoming: [PhoneSessionIn], approval incomingApproval: PhoneApprovalIn?, now: UInt64) {
        lock.lock(); defer { lock.unlock() }
        let P = PhoneLinkProtocol.self
        var next: [Session] = []
        for s in incoming.filter({ !$0.pillId.isEmpty }).prefix(P.maxSessions) {
            var fresh = Session(
                pillId: s.pillId,
                agent: P.clip(s.agent, 64),
                state: P.states.contains(s.state) ? s.state : "idle",
                statusText: P.clip(s.statusText, P.maxTextChars),
                stepIndex: s.stepIndex,
                stepCount: s.stepCount,
                updatedAt: now,
                steps: P.cleanSteps(s.steps),
                finalLine: s.finalLine.map { P.clip($0, P.maxTextChars) }.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
                project: s.project.flatMap(P.projectName),
                color: s.color.flatMap { P.isColor($0) ? $0 : nil },
                files: Self.cleanFiles(s.files),
                character: P.cleanCharacter(s.character))
            if let old = sessions.first(where: { $0.pillId == fresh.pillId }), old.sameContent(as: fresh) {
                fresh.updatedAt = old.updatedAt
            }
            next.append(fresh)
        }
        if next != sessions {
            sessions = next
            broadcastSessions()
        }

        // The pending request: a new one replaces the old, none retracts it.
        let same: Bool
        switch (approval, incomingApproval) {
        case (let a?, let b?): same = a.requestId == b.requestId
        case (nil, nil): same = true
        default: same = false
        }
        if same { return }
        if let old = approval {
            approval = nil
            broadcast(Self.resolvedLine(old.fingerprint))
        }
        if let a = incomingApproval, !a.requestId.isEmpty {
            let tool = P.clip(a.tool, 64)
            let truncated = P.length(a.command) > P.maxCommandChars
            let command = P.clip(a.command, P.maxCommandChars)
            let fresh = Approval(
                requestId: a.requestId,
                fingerprint: P.fingerprint(pillId: a.pillId, sessionId: a.sessionId, tool: tool, command: command, inputKey: a.requestId),
                pillId: a.pillId, tool: tool, command: command, truncated: truncated, createdAt: now)
            approval = fresh
            broadcast(Self.approvalLine(fresh))
        }
    }

    /// The question the island shows, or nil when none waits. Only phones with `answers` hear of it.
    func publishQuestion(_ incoming: PhoneQuestionIn?, now: UInt64) {
        lock.lock(); defer { lock.unlock() }
        let usable = incoming.flatMap { !$0.requestId.isEmpty && Self.fitsTheLimits($0.questions) ? $0 : nil }
        let same: Bool
        switch (question, usable) {
        case (let a?, let b?): same = a.requestId == b.requestId
        case (nil, nil): same = true
        default: same = false
        }
        if same { return }
        if let old = question {
            question = nil
            broadcast(Self.resolvedLine(old.fingerprint), onlyTo: { $0.answers })
        }
        if let q = usable {
            let texts = q.questions.map(\.question).joined(separator: "\n")
            let fresh = Question(
                requestId: q.requestId,
                fingerprint: PhoneLinkProtocol.fingerprint(pillId: q.pillId, sessionId: q.sessionId, tool: "AskUserQuestion",
                                                             command: texts, inputKey: q.requestId),
                pillId: q.pillId, items: q.questions, createdAt: now)
            question = fresh
            broadcast(Self.questionLine(fresh), onlyTo: { $0.answers })
        }
    }

    /// The plan usage. Only phones with `usage` hear of it; a change with nothing usable left is sent as a
    /// bare `{"type":"usage"}`, which makes the phone remove its panel.
    func publishUsage(_ incoming: PhoneUsageIn?) {
        lock.lock(); defer { lock.unlock() }
        let next = incoming.flatMap(Self.usageLine)
        if next == usage { return }
        usage = next
        broadcast(next ?? PhoneLinkProtocol.json(["type": "usage"]), onlyTo: { $0.usage })
    }

    // MARK: Subscribers

    /// Registers a connection that has authenticated. It is sent what brings it up to date: the
    /// sessions, then the request still waiting, the question (with `answers`) and the usage (with `usage`).
    @discardableResult
    func subscribe(caps: PhoneLinkCaps, now: UInt64, send: @escaping PhoneLinkSender) -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        expire(now: now)
        let id = nextSub
        nextSub += 1
        _ = send(.line(Self.sessionsLine(sessions, caps: caps)))
        if let a = approval { _ = send(.line(Self.approvalLine(a))) }
        if caps.answers, let q = question { _ = send(.line(Self.questionLine(q))) }
        if caps.usage, let u = usage { _ = send(.line(u)) }
        subs.append(Sub(id: id, send: send, caps: caps))
        onClients?(subs.count)
        return id
    }

    /// A phone asked for the lines of a file (cap `diffs`): the island is read for it, nothing is kept here.
    func requestDiff(pillId: String, fileId: Int, reply: @escaping @Sendable (PhoneDiffIn?) -> Void) {
        host.diff(pillId: pillId, fileId: fileId, reply: reply)
    }

    func unsubscribe(_ id: UInt64) {
        lock.lock(); defer { lock.unlock() }
        subs.removeAll { $0.id == id }
        onClients?(subs.count)
    }

    /// Unpaired or switched off: every connection is told and closed.
    func kickAll(code: String, message: String) {
        lock.lock()
        let gone = subs
        subs = []
        lock.unlock()
        onClients?(0)
        for s in gone { _ = s.send(.close(code: code, message: message)) }
    }

    var clients: Int {
        lock.lock(); defer { lock.unlock() }
        return subs.count
    }

    // MARK: Decisions

    /// A phone's answer. Applied only for the request that is still pending.
    func decide(fingerprint: String, decision: String, now: UInt64) -> PhoneLinkOutcome {
        let allow: Bool
        switch decision {
        case "allow": allow = true
        case "deny": allow = false
        default: return .invalid
        }
        lock.lock()
        guard let a = approval, PhoneLinkProtocol.constantEq(a.fingerprint, fingerprint) else {
            lock.unlock()
            return .noMatch
        }
        // A command the phone could not show in full is never allowed from the phone, whatever the phone says.
        if allow && a.truncated {
            lock.unlock()
            return .tooLong
        }
        // Taken in every case: a request is answered once, or dismissed.
        approval = nil
        broadcast(Self.resolvedLine(a.fingerprint))
        let late = Self.age(now, since: a.createdAt) > PhoneLinkProtocol.approvalTTLms
        lock.unlock()
        if late { return .late }
        // Outside the lock: the host answers the agent and touches the island.
        host.decide(requestId: a.requestId, allow: allow)
        return .applied
    }

    /// A phone's answer to the question that is still pending. `picks` has one list of labels per question,
    /// in order. Applied only if every label is exactly one of that question's options, one label for a
    /// single choice and at least one (each at most once) for a multiple choice; anything else changes nothing.
    func answer(fingerprint: String, picks: [[String]], now: UInt64) -> PhoneLinkOutcome {
        lock.lock()
        guard let q = question, PhoneLinkProtocol.constantEq(q.fingerprint, fingerprint) else {
            lock.unlock()
            return .noMatch
        }
        guard Self.picksMatch(q.items, picks: picks) else {
            lock.unlock()
            return .invalid
        }
        question = nil
        broadcast(Self.resolvedLine(q.fingerprint), onlyTo: { $0.answers })
        let late = Self.age(now, since: q.createdAt) > PhoneLinkProtocol.approvalTTLms
        lock.unlock()
        if late { return .late }
        host.answer(requestId: q.requestId, picks: picks)
        return .applied
    }

    // MARK: Rules (pure, for the tests)

    static func fitsTheLimits(_ items: [PhoneQuestionItemIn]) -> Bool {
        let P = PhoneLinkProtocol.self
        guard !items.isEmpty, items.count <= P.maxQuestions else { return false }
        return items.allSatisfy { item in
            let labels = item.options.map(\.label)
            return !item.question.trimmingCharacters(in: .whitespaces).isEmpty
                && P.length(item.question) <= P.maxQuestionChars
                && !labels.isEmpty && labels.count <= P.maxOptions
                && labels.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty && P.length($0) <= P.maxLabelChars }
                && item.options.allSatisfy { P.length($0.description) <= P.maxDescriptionChars }
                // two options with the same label could not be told apart in an answer
                && Set(labels).count == labels.count
        }
    }

    /// One list per question; each label one of that question's (exact, case-sensitive), once; one label for a
    /// single choice, one or more for a multiple choice.
    static func picksMatch(_ items: [PhoneQuestionItemIn], picks: [[String]]) -> Bool {
        guard picks.count == items.count else { return false }
        for (item, chosen) in zip(items, picks) {
            if chosen.isEmpty || chosen.count > item.options.count || (!item.multiSelect && chosen.count != 1) { return false }
            var seen: Set<String> = []
            for label in chosen {
                guard item.options.contains(where: { $0.label == label }), !seen.contains(label) else { return false }
                seen.insert(label)
            }
        }
        return true
    }

    /// Milliseconds since `since`, 0 when the clock went backwards.
    static func age(_ now: UInt64, since: UInt64) -> UInt64 {
        now >= since ? now - since : 0
    }

    // MARK: Lines

    private func broadcast(_ line: String, onlyTo wants: (PhoneLinkCaps) -> Bool = { _ in true }) {
        subs.removeAll { s in wants(s.caps) && !s.send(.line(line)) }
    }

    /// Every phone gets the picture it asked for: the v1 line, or the one with details.
    private func broadcastSessions() {
        var lines: [Int: String] = [:]
        subs.removeAll { s in
            let line: String
            if let known = lines[s.caps.sessionsKey] { line = known } else {
                line = Self.sessionsLine(sessions, caps: s.caps)
                lines[s.caps.sessionsKey] = line
            }
            return !s.send(.line(line))
        }
    }

    private func expire(now: UInt64) {
        if let q = question, Self.age(now, since: q.createdAt) > PhoneLinkProtocol.approvalTTLms {
            question = nil
            broadcast(Self.resolvedLine(q.fingerprint), onlyTo: { $0.answers })
        }
        if let a = approval, Self.age(now, since: a.createdAt) > PhoneLinkProtocol.approvalTTLms {
            approval = nil
            broadcast(Self.resolvedLine(a.fingerprint))
        }
    }

    private static func sessionJSON(_ s: Session) -> [String: Any] {
        ["pillId": s.pillId, "agent": s.agent, "state": s.state, "statusText": s.statusText,
         "stepIndex": s.stepIndex, "stepCount": s.stepCount, "updatedAt": s.updatedAt]
    }

    /// The v1 line, or the one with `steps`, `finalLine`, `project` and `color` where there is something to
    /// say. Steps are dropped from the oldest first (and then from all sessions) until the line fits the budget.
    /// The v1 line, or the one with what this phone was offered: `steps`, `finalLine`, `project` and `color`
    /// (details), `files` (diffs), `character` (character), where there is something to say. Steps go first,
    /// from the oldest (and then from all sessions), then files, until the line fits the budget.
    private static func sessionsLine(_ sessions: [Session], caps: PhoneLinkCaps) -> String {
        let extras = caps.details || caps.diffs || caps.character
        var keep = PhoneLinkProtocol.maxSteps
        var keepFiles = PhoneLinkProtocol.maxFiles
        while true {
            let list: [[String: Any]] = sessions.map { s in
                var v = sessionJSON(s)
                if caps.details {
                    let steps = Array(s.steps.suffix(keep))
                    if !steps.isEmpty { v["steps"] = steps }
                    if let l = s.finalLine { v["finalLine"] = l }
                    if let p = s.project { v["project"] = p }
                    if let c = s.color { v["color"] = c }
                }
                if caps.diffs {
                    let files = s.files.suffix(keepFiles).map(fileJSON)
                    if !files.isEmpty { v["files"] = Array(files) }
                }
                if caps.character, !s.character.isEmpty { v["character"] = s.character }
                return v
            }
            let line = PhoneLinkProtocol.json(["type": "sessions", "sessions": list])
            if !extras || line.utf8.count <= PhoneLinkProtocol.detailsLineBudget || (keep == 0 && keepFiles == 0) { return line }
            if keep > 0 { keep /= 2 } else { keepFiles /= 2 }
        }
    }

    private static func fileJSON(_ f: PhoneFileIn) -> [String: Any] {
        var v: [String: Any] = ["id": f.id, "name": f.name, "added": f.added, "removed": f.removed]
        if f.tooLarge { v["tooLarge"] = true }
        if f.isNew { v["isNew"] = true }
        return v
    }

    // MARK: Diffs (cap `diffs`)

    /// The newest `maxFiles` files with a usable name, names only.
    static func cleanFiles(_ files: [PhoneFileIn]) -> [PhoneFileIn] {
        let kept = files.compactMap { f -> PhoneFileIn? in
            guard f.id >= 0, let name = PhoneLinkProtocol.fileName(f.name) else { return nil }
            var clean = f
            clean.name = name
            clean.added = max(0, f.added)
            clean.removed = max(0, f.removed)
            return clean
        }
        return Array(kept.suffix(PhoneLinkProtocol.maxFiles))
    }


    /// The `diff` lines answering a `getDiff`: at most `maxDiffLines` lines, each cut at `maxDiffLineChars`, in parts of
    /// `diffPartLines`. A diff the island no longer has is one part with `gone: true` and no lines; a change that was
    /// too large to show line by line has no lines either.
    static func diffLines(pillId: String, fileId: Int, diff: PhoneDiffIn?) -> [String] {
        let P = PhoneLinkProtocol.self
        guard let diff else {
            return [P.json(["type": "diff", "pillId": pillId, "fileId": fileId, "name": "", "added": 0, "removed": 0,
                            "tooLarge": false, "gone": true, "truncated": false, "part": 0, "parts": 1, "lines": [Any]()])]
        }
        let rows = diff.tooLarge ? [] : diff.lines.prefix(P.maxDiffLines).map { line -> [String] in
            let kind = ["+", "-", "@"].contains(line.kind) ? line.kind : " "
            return [kind, P.clip(line.text, P.maxDiffLineChars)]
        }
        let truncated = !diff.tooLarge && diff.lines.count > P.maxDiffLines
        var parts: [[[String]]] = stride(from: 0, to: rows.count, by: P.diffPartLines).map {
            Array(rows[$0..<min($0 + P.diffPartLines, rows.count)])
        }
        if parts.isEmpty { parts = [[]] }
        let name = P.fileName(diff.name) ?? ""
        return parts.enumerated().map { index, lines in
            P.json(["type": "diff", "pillId": pillId, "fileId": fileId, "name": name, "added": max(0, diff.added),
                    "removed": max(0, diff.removed), "tooLarge": diff.tooLarge, "gone": false, "truncated": truncated,
                    "part": index, "parts": parts.count, "lines": lines])
        }
    }

    private static func approvalLine(_ a: Approval) -> String {
        PhoneLinkProtocol.json(["type": "approval", "pillId": a.pillId, "fingerprint": a.fingerprint, "tool": a.tool,
                                  "command": a.command, "truncated": a.truncated, "createdAt": a.createdAt])
    }

    private static func resolvedLine(_ fingerprint: String) -> String {
        PhoneLinkProtocol.json(["type": "approvalResolved", "fingerprint": fingerprint])
    }

    private static func questionLine(_ q: Question) -> String {
        let questions: [[String: Any]] = q.items.map { item in
            ["question": item.question, "multiSelect": item.multiSelect,
             "options": item.options.map { ["label": $0.label, "description": $0.description] }]
        }
        return PhoneLinkProtocol.json(["type": "question", "pillId": q.pillId, "fingerprint": q.fingerprint,
                                         "createdAt": q.createdAt, "questions": questions])
    }

    private static func windowJSON(_ w: PhoneUsageWindowIn) -> [String: Any]? {
        guard w.usedPct.isFinite, w.resetsAt > 0 else { return nil }
        return ["pct": Int(min(100, max(0, w.usedPct)).rounded()), "resetsAt": w.resetsAt]
    }

    private static func planJSON(_ p: PhoneUsagePlanIn) -> [String: Any]? {
        var v: [String: Any] = [:]
        if let w = p.fiveHour.flatMap(windowJSON) { v["fiveHour"] = w }
        if let w = p.sevenDay.flatMap(windowJSON) { v["sevenDay"] = w }
        // A plan with no usable window is left out.
        if v.isEmpty { return nil }
        if let c = p.resetCredits { v["resetCredits"] = min(99, max(0, c)) }
        // "plus", "pro", "max 5x": ASCII letters, digits, spaces and dashes only, short.
        if let plan = p.plan {
            let clean = String(plan.filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == " " || $0 == "-" }.prefix(20))
                .trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty { v["plan"] = clean }
        }
        if let t = p.updatedAt, t > 0 { v["updatedAt"] = t }
        return v
    }

    /// nil when neither plan has a usable window (the phone is then told so with a bare line).
    static func usageLine(_ u: PhoneUsageIn) -> String? {
        var v: [String: Any] = ["type": "usage"]
        if let c = u.claude.flatMap(planJSON) { v["claude"] = c }
        if let c = u.codex.flatMap(planJSON) { v["codex"] = c }
        return v.count > 1 ? PhoneLinkProtocol.json(v) : nil
    }
}
