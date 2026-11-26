import Foundation

// MARK: - What the computer says (docs/PHONE_LINK.md, protocol v1)
//
// Parsed strictly: a field that breaks the limits the computer keeps drops the message or the item,
// never the connection. Unknown message types and unknown fields are ignored, by contract.

struct FileChange: Equatable, Identifiable, Sendable {
    var id: Int
    var name: String
    var added: Int
    var removed: Int
    var tooLarge: Bool
    var isNew: Bool
}

struct SessionInfo: Equatable, Identifiable, Sendable {
    var pillId: String
    var agent: String
    var state: BotState
    var statusText: String
    var stepIndex: Int
    var stepCount: Int
    var updatedAt: Date
    var steps: [String]
    var finalLine: String?
    var project: String?
    var color: String?
    var files: [FileChange]
    var character: MochiCharacter

    var id: String { pillId }
}

struct ApprovalRequest: Equatable, Sendable {
    var pillId: String
    var fingerprint: String
    var tool: String
    var command: String
    var createdAt: Date
    /// The command was longer than the computer sends: the phone may only deny it.
    var truncated: Bool
}

struct AskedOption: Equatable, Sendable {
    var label: String
    var description: String
}

struct AskedQuestion: Equatable, Sendable {
    var question: String
    var options: [AskedOption]
    var multiSelect: Bool
}

struct QuestionRequest: Equatable, Sendable {
    var pillId: String
    var fingerprint: String
    var createdAt: Date
    var questions: [AskedQuestion]
}

struct DiffRow: Equatable, Sendable {
    /// `+`, `-`, `@` or ` `.
    var kind: Character
    var text: String
}

struct DiffPart: Equatable, Sendable {
    var pillId: String
    var fileId: Int
    var name: String
    var added: Int
    var removed: Int
    var tooLarge: Bool
    var gone: Bool
    var truncated: Bool
    var part: Int
    var parts: Int
    var lines: [DiffRow]
}

struct ChatModel: Equatable, Identifiable, Sendable {
    var id: String
    var provider: String
    var label: String
}

enum ServerMessage: Sendable {
    case welcome(version: Int, desktop: String, os: String, caps: Set<String>)
    case error(code: String, message: String)
    case sessions([SessionInfo])
    case approval(ApprovalRequest)
    case approvalResolved(fingerprint: String)
    case question(QuestionRequest)
    case diff(DiffPart)
    case chatModels([ChatModel])
    case chatDelta(id: String, text: String)
    case chatDone(id: String, text: String?)
    case chatError(id: String, reason: String, message: String)
    case pong
    case other

    /// nil when the line is not a JSON object with a `type`.
    static func parse(_ line: Data) -> ServerMessage? {
        guard let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let type = o["type"] as? String else { return nil }
        switch type {
        case "welcome":
            guard let v = int(o["v"]) else { return nil }
            return .welcome(version: v, desktop: clip(o["desktop"] as? String ?? "", 48), os: o["os"] as? String ?? "",
                            caps: Set((o["caps"] as? [Any])?.compactMap { $0 as? String } ?? []))
        case "error":
            return .error(code: o["code"] as? String ?? "", message: clip(o["message"] as? String ?? "", 200))
        case "sessions":
            let list = (o["sessions"] as? [Any])?.compactMap { ($0 as? [String: Any]).flatMap(session) } ?? []
            return .sessions(Array(list.prefix(PhoneLinkProtocol.maxSessions)))
        case "approval":
            guard let fp = o["fingerprint"] as? String, isFingerprint(fp), let pill = o["pillId"] as? String else { return .other }
            return .approval(ApprovalRequest(pillId: pill, fingerprint: fp, tool: clip(o["tool"] as? String ?? "Tool", 64),
                                             command: clip(o["command"] as? String ?? "", PhoneLinkProtocol.maxCommandChars),
                                             createdAt: date(o["createdAt"]), truncated: o["truncated"] as? Bool ?? false))
        case "approvalResolved":
            guard let fp = o["fingerprint"] as? String else { return .other }
            return .approvalResolved(fingerprint: fp)
        case "question":
            guard let fp = o["fingerprint"] as? String, isFingerprint(fp), let pill = o["pillId"] as? String,
                  let raw = o["questions"] as? [Any] else { return .other }
            let items = raw.compactMap { $0 as? [String: Any] }.map { q in
                AskedQuestion(question: q["question"] as? String ?? "",
                              options: (q["options"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map {
                                  AskedOption(label: $0["label"] as? String ?? "", description: $0["description"] as? String ?? "")
                              },
                              multiSelect: q["multiSelect"] as? Bool ?? false)
            }
            // The computer never sends one that breaks these; a phone that got one would answer it wrong.
            guard (1...PhoneLinkProtocol.maxQuestions).contains(items.count),
                  items.allSatisfy({ !$0.question.isEmpty && (1...PhoneLinkProtocol.maxOptions).contains($0.options.count)
                      && Set($0.options.map(\.label)).count == $0.options.count && !$0.options.contains { $0.label.isEmpty } })
            else { return .other }
            return .question(QuestionRequest(pillId: pill, fingerprint: fp, createdAt: date(o["createdAt"]), questions: items))
        case "diff":
            guard let pill = o["pillId"] as? String, let fileId = int(o["fileId"]), let part = int(o["part"]), let parts = int(o["parts"]),
                  (1...2).contains(parts), (0..<parts).contains(part) else { return .other }
            let rows = (o["lines"] as? [Any] ?? []).prefix(PhoneLinkProtocol.diffPartLines).compactMap { r -> DiffRow? in
                guard let pair = r as? [Any], pair.count == 2, let k = pair[0] as? String, let t = pair[1] as? String else { return nil }
                let kind: Character = (k.count == 1 && "+-@".contains(k)) ? Character(k) : " "
                return DiffRow(kind: kind, text: clip(t, PhoneLinkProtocol.maxDiffLineChars))
            }
            return .diff(DiffPart(pillId: pill, fileId: fileId, name: PhoneLinkProtocol.fileName(o["name"] as? String ?? "") ?? "",
                                  added: max(0, int(o["added"]) ?? 0), removed: max(0, int(o["removed"]) ?? 0),
                                  tooLarge: o["tooLarge"] as? Bool ?? false, gone: o["gone"] as? Bool ?? false,
                                  truncated: o["truncated"] as? Bool ?? false, part: part, parts: parts, lines: rows))
        case "chatModels":
            let models = (o["models"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.compactMap { m -> ChatModel? in
                guard let id = m["id"] as? String, !id.isEmpty else { return nil }
                return ChatModel(id: id, provider: m["provider"] as? String ?? "", label: clip(m["label"] as? String ?? id, 80))
            }
            return .chatModels(models)
        case "chatDelta":
            guard let id = o["id"] as? String else { return .other }
            return .chatDelta(id: id, text: o["text"] as? String ?? "")
        case "chatDone":
            guard let id = o["id"] as? String else { return .other }
            return .chatDone(id: id, text: o["text"] as? String)
        case "chatError":
            guard let id = o["id"] as? String else { return .other }
            return .chatError(id: id, reason: o["reason"] as? String ?? "internal", message: clip(o["message"] as? String ?? "", 200))
        case "pong":
            return .pong
        default:
            return .other
        }
    }

    private static func session(_ o: [String: Any]) -> SessionInfo? {
        guard let pill = o["pillId"] as? String, !pill.isEmpty else { return nil }
        let P = PhoneLinkProtocol.self
        let files = (o["files"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.compactMap { f -> FileChange? in
            guard let id = int(f["id"]), id >= 0, let name = P.fileName(f["name"] as? String ?? "") else { return nil }
            return FileChange(id: id, name: name, added: max(0, int(f["added"]) ?? 0), removed: max(0, int(f["removed"]) ?? 0),
                              tooLarge: f["tooLarge"] as? Bool ?? false, isNew: f["isNew"] as? Bool ?? false)
        }
        let color = (o["color"] as? String).flatMap { P.isColor($0) ? $0 : nil }
        return SessionInfo(
            pillId: pill,
            agent: clip(o["agent"] as? String ?? "", 64),
            state: BotState(rawValue: o["state"] as? String ?? "") ?? .idle,
            statusText: clip(o["statusText"] as? String ?? "", P.maxTextChars),
            stepIndex: max(0, int(o["stepIndex"]) ?? 0),
            stepCount: max(0, int(o["stepCount"]) ?? 0),
            updatedAt: date(o["updatedAt"]),
            steps: ((o["steps"] as? [Any]) ?? []).compactMap { $0 as? String }.suffix(P.maxSteps).map { clip($0, P.maxTextChars) },
            finalLine: (o["finalLine"] as? String).map { clip($0, P.maxTextChars) }.flatMap { $0.isEmpty ? nil : $0 },
            project: (o["project"] as? String).flatMap(P.projectName),
            color: color,
            files: Array(files.suffix(P.maxFiles)),
            character: character(o["character"] as? [String: Any]))
    }

    /// The Mochi a pill wears on the computer; anything this app does not know is left off.
    static func character(_ o: [String: Any]?) -> MochiCharacter {
        guard let o else { return MochiCharacter() }
        let festive = (o["festive"] as? String).map { MochiFestive(storage: $0) }?.orNil
        return MochiCharacter(accessory: (o["accessory"] as? String).flatMap(MochiAccessory.init(rawValue:)),
                              eye: (o["eye"] as? String).flatMap(MochiEye.init(rawValue:)),
                              shape: (o["shape"] as? String).flatMap(MochiShape.init(rawValue:)),
                              festive: festive)
    }

    static func isFingerprint(_ s: String) -> Bool {
        s.utf8.count == 64 && s.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdef").contains($0) }
    }

    private static func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }

    private static func date(_ v: Any?) -> Date {
        guard let ms = (v as? NSNumber)?.doubleValue, ms > 0 else { return Date() }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    private static func clip(_ s: String, _ max: Int) -> String { PhoneLinkProtocol.clip(s, max) }
}
