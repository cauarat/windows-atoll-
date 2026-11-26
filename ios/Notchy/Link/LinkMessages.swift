import Foundation

// MARK: - What the computer says (docs/PHONE_LINK.md, protocol v1)
//
// Parsed strictly: a field that breaks the limits the computer keeps drops the message or the item,
// never the connection. Unknown message types and unknown fields are ignored, by contract.

struct ChatModel: Equatable, Identifiable, Sendable {
    var id: String
    var provider: String
    var label: String
}

enum ServerMessage: Sendable {
    case welcome(version: Int, desktop: String, os: String, caps: Set<String>)
    case error(code: String, message: String)
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

    private static func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }

    private static func clip(_ s: String, _ max: Int) -> String { PhoneLinkProtocol.clip(s, max) }
}
