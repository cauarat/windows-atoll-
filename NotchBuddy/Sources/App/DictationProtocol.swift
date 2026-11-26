import Foundation

/// The app's side of the dictation service's protocol.
///
/// The service is dictation-service/ (Python, Qwen3-ASR on open weights by
/// default). The app streams 16 kHz mono PCM16 to `WS /v1/dictation` and reads
/// back `ready`, `partial`, `final` and `error`. The other side is
/// dictation-service/src/notchy_dictation/protocol.py, and
/// tests/fixtures/dictation.json holds both — and the Windows card — to the same
/// messages.
///
/// Foundation only, so scripts/test-dictation.sh can compile it alone.
enum DictationProtocol {
    static let version = 1
    static let path = "/v1/dictation"
    static let healthPath = "/health"
    /// Where the service listens when nobody changed anything.
    static let defaultServiceURL = "http://127.0.0.1:8765"
    static let sampleRate: Double = 16_000
    static let encoding = "pcm_s16le"
    /// How much audio each binary frame carries.
    static let frameMilliseconds = 100
    /// Kept recording after the key is let go: people let go on the last
    /// syllable, not after it.
    static let tailMilliseconds = 250
    /// The only recognition language for now. Shown with its label, never
    /// translated: it names what the model was asked for.
    static let language = "pt-BR"
    static let languageLabel = "Português (Brasil)"

    static let errorCodes = [
        "bad_request", "unsupported_audio", "unsupported_language", "model_loading",
        "model_failed", "provider_unavailable", "forbidden_origin", "internal",
    ]

    static func startMessage(language: String = language) -> String {
        json(["type": "start", "language": language, "sample_rate": Int(sampleRate),
              "encoding": encoding, "channels": 1])
    }

    static let stopMessage = #"{"type":"stop"}"#
    static let cancelMessage = #"{"type":"cancel"}"#

    /// The socket for a service address as typed in Settings:
    /// `http://host:port` → `ws://host:port/v1/dictation` (https → wss). A bare
    /// `host:port` is taken as http. Nil for anything that is not an address.
    static func socketURL(service: String) -> URL? {
        endpoint(service: service, path: path, websocket: true)
    }

    static func healthURL(service: String) -> URL? {
        endpoint(service: service, path: healthPath, websocket: false)
    }

    private static func endpoint(service: String, path: String, websocket: Bool) -> URL? {
        var text = service.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard var parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              let host = parts.host, !host.isEmpty else { return nil }
        switch scheme {
        case "http", "ws": parts.scheme = websocket ? "ws" : "http"
        case "https", "wss": parts.scheme = websocket ? "wss" : "https"
        default: return nil
        }
        parts.path = path
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }

    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

/// What the service says it runs, from `ready` and `/health`.
struct DictationServiceInfo: Equatable, Sendable {
    let provider: String
    let model: String
    let backend: String
    /// Whether partials will come while the person speaks. False for the
    /// offline backend: the text arrives once, at the end.
    let streaming: Bool
    let device: String

    init(provider: String, model: String, backend: String, streaming: Bool, device: String) {
        self.provider = provider
        self.model = model
        self.backend = backend
        self.streaming = streaming
        self.device = device
    }

    init?(json: [String: Any]) {
        guard let provider = json["provider"] as? String, let model = json["model"] as? String else { return nil }
        self.init(provider: provider, model: model,
                  backend: json["backend"] as? String ?? "",
                  streaming: json["streaming"] as? Bool ?? false,
                  device: json["device"] as? String ?? "")
    }

    /// "Qwen3-ASR-1.7B" out of "Qwen/Qwen3-ASR-1.7B", or a folder path's last part.
    var modelName: String {
        model.split(separator: "/").last.map(String.init) ?? model
    }
}

enum DictationServerMessage: Equatable, Sendable {
    case ready(DictationServiceInfo)
    /// The whole hypothesis so far; it replaces the previous one.
    case partial(text: String, seq: Int)
    case final(text: String, audioMs: Int, processingMs: Int, truncated: Bool)
    case error(code: String, message: String)

    static func decode(_ text: String) -> DictationServerMessage? {
        guard let data = text.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = json["type"] as? String else { return nil }
        switch type {
        case "ready":
            return DictationServiceInfo(json: json).map(DictationServerMessage.ready)
        case "partial":
            guard let text = json["text"] as? String else { return nil }
            return .partial(text: text, seq: json["seq"] as? Int ?? 0)
        case "final":
            guard let text = json["text"] as? String else { return nil }
            return .final(text: text, audioMs: json["audio_ms"] as? Int ?? 0,
                          processingMs: json["processing_ms"] as? Int ?? 0,
                          truncated: json["truncated"] as? Bool ?? false)
        case "error":
            return .error(code: json["code"] as? String ?? "internal", message: json["message"] as? String ?? "")
        default:
            return nil
        }
    }
}

/// What the card shows, built from the messages as they arrive.
///
/// A partial replaces the text, never adds to it, so nothing is shown twice;
/// the final replaces everything; an error keeps what was already heard, so a
/// dropped connection does not take the words with it.
struct DictationTranscript: Equatable, Sendable {
    enum Phase: String, Sendable {
        case waiting, listening, done, error
    }

    private(set) var phase: Phase = .waiting
    private(set) var text = ""
    private(set) var service: DictationServiceInfo?
    private(set) var errorCode: String?
    private(set) var errorMessage: String?
    private(set) var audioMs = 0
    private(set) var processingMs = 0
    private(set) var truncated = false

    var streaming: Bool { service?.streaming ?? false }
    var isFinished: Bool { phase == .done || phase == .error }

    mutating func apply(_ message: DictationServerMessage) {
        switch message {
        case .ready(let info):
            guard !isFinished else { return }
            service = info
            phase = .listening
        case .partial(let text, _):
            guard !isFinished else { return }
            self.text = text
        case .final(let text, let audioMs, let processingMs, let truncated):
            guard phase != .done else { return }
            self.text = text
            self.audioMs = audioMs
            self.processingMs = processingMs
            self.truncated = truncated
            phase = .done
        case .error(let code, let message):
            guard !isFinished else { return }
            errorCode = code
            errorMessage = message
            phase = .error
        }
    }
}

/// The service's `/health` answer.
struct DictationHealth: Equatable, Sendable {
    /// "ready", "loading" or "error".
    let status: String
    let ready: Bool
    let protocolVersion: Int
    let info: DictationServiceInfo
    let language: String
    let languageLabel: String
    /// Why the model cannot run, in the service's words, when `status` is "error".
    let error: String?

    static func decode(_ data: Data) -> DictationHealth? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let status = json["status"] as? String,
              let info = DictationServiceInfo(json: json) else { return nil }
        return DictationHealth(
            status: status,
            ready: json["ready"] as? Bool ?? false,
            protocolVersion: json["protocol"] as? Int ?? 0,
            info: info,
            language: json["language"] as? String ?? DictationProtocol.language,
            languageLabel: json["language_label"] as? String ?? DictationProtocol.languageLabel,
            error: json["error"] as? String
        )
    }
}
