import Foundation

// MARK: - Phone link: chat with the Mac's AI providers (cap `chat`, docs/PHONE_LINK.md)
//
// The phone sends text and gets text back. The provider is called from the Mac with the key in
// the Mac's Keychain, which never leaves it, and the phone can only name a model this list offers:
// the one chosen in Settings → Chat for each provider that is set up there. A conversation of its
// own, in memory only and per phone: the island's chat is not touched, and nothing is written to
// disk. A provider's own error text is never forwarded (some echo part of a key), only a reason.
//
// One answer at a time per phone, at most 12 messages in 10 minutes, at most 4000 characters a
// message. Cloud and local providers both answer all at once here.

#if !APPSTORE

final class PhoneLinkChatService: PhoneLinkChat, @unchecked Sendable {
    static let shared = PhoneLinkChatService()

    static let maxText = 4000
    static let maxSends = 12
    static let sendWindow: TimeInterval = 600
    /// Turns kept per phone (user + assistant), oldest dropped first.
    static let maxTurns = 20

    private struct Conversation {
        var messages: [[String: String]] = []
        var sends: [Date] = []
        var running: (id: String, task: Task<Void, Never>)?
    }

    private let lock = NSLock()
    private var conversations: [ObjectIdentifier: Conversation] = [:]

    // MARK: PhoneLinkChat

    func handle(_ message: PhoneLinkIncoming, from peer: PhoneLinkChatPeer) {
        switch message {
        case .chatModels:
            Task { @MainActor in
                let models = Self.models().map { ["id": $0.id, "provider": $0.provider.rawValue, "label": $0.label] }
                peer.send(PhoneLinkProtocol.json(["type": "chatModels", "models": models]))
            }
        case .chatSend(let id, let model, let text):
            send(id: id, model: model, text: text, peer: peer)
        case .chatCancel(let id):
            lock.lock()
            let running = conversations[peer.id]?.running
            if running?.id == id { conversations[peer.id]?.running = nil }
            lock.unlock()
            if let running, running.id == id {
                running.task.cancel()
                peer.send(Self.error(id, "canceled", "Stopped."))
            }
        case .chatReset:
            lock.lock()
            let running = conversations[peer.id]?.running
            conversations[peer.id] = Conversation(sends: conversations[peer.id]?.sends ?? [])
            lock.unlock()
            running?.task.cancel()
        default:
            break
        }
    }

    func ended(_ peer: ObjectIdentifier) {
        lock.lock()
        let running = conversations.removeValue(forKey: peer)?.running
        lock.unlock()
        running?.task.cancel()
    }

    /// The switch went off or the phone was unpaired: every answer stops, every conversation is forgotten.
    func reset() {
        lock.lock()
        let running = conversations.values.compactMap { $0.running?.task }
        conversations = [:]
        lock.unlock()
        running.forEach { $0.cancel() }
    }

    // MARK: Sending

    private func send(id: String, model: String, text raw: String, peer: PhoneLinkChatPeer) {
        let text = String(raw.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) && $0 != "\n" ? " " : Character($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { peer.send(Self.error(id, "empty", "Write something first.")); return }
        if text.unicodeScalars.count > Self.maxText { peer.send(Self.error(id, "too_long", "That message is too long.")); return }

        lock.lock()
        var conversation = conversations[peer.id] ?? Conversation()
        if conversation.running != nil {
            lock.unlock()
            peer.send(Self.error(id, "busy", "Mochi is still answering the last message."))
            return
        }
        let now = Date()
        conversation.sends.removeAll { now.timeIntervalSince($0) > Self.sendWindow }
        if conversation.sends.count >= Self.maxSends {
            conversations[peer.id] = conversation
            lock.unlock()
            peer.send(Self.error(id, "rate", "That's a lot of messages. Try again in a few minutes."))
            return
        }
        conversation.sends.append(now)
        conversation.messages.append(["role": "user", "content": text])
        conversation.messages = Array(conversation.messages.suffix(Self.maxTurns))
        let history = conversation.messages
        let task = Task { [weak self] in
            let result = await Self.answer(model: model, history: history)
            self?.finish(id: id, result: result, peer: peer)
        }
        conversation.running = (id, task)
        conversations[peer.id] = conversation
        lock.unlock()
    }

    private func finish(id: String, result: Result<String, ChatFailure>, peer: PhoneLinkChatPeer) {
        lock.lock()
        guard var conversation = conversations[peer.id], conversation.running?.id == id else {
            lock.unlock()   // canceled, reset or gone: nothing more is said about it
            return
        }
        conversation.running = nil
        switch result {
        case .success(let answer):
            conversation.messages.append(["role": "assistant", "content": answer])
        case .failure:
            // The question goes too, so the next one is not asked twice.
            if conversation.messages.last?["role"] == "user" { conversation.messages.removeLast() }
        }
        conversations[peer.id] = conversation
        lock.unlock()
        switch result {
        case .success(let answer):
            // In pieces of at most 8 KiB, then done: the phone appends them.
            var rest = Substring(answer)
            while !rest.isEmpty {
                var piece = rest.prefix(2000)
                while piece.utf8.count > 8 * 1024 { piece = piece.dropLast(100) }
                peer.send(PhoneLinkProtocol.json(["type": "chatDelta", "id": id, "text": String(piece)]))
                rest = rest.dropFirst(piece.count)
            }
            peer.send(PhoneLinkProtocol.json(["type": "chatDone", "id": id]))
        case .failure(let failure):
            peer.send(Self.error(id, failure.reason, failure.message))
        }
    }

    private static func error(_ id: String, _ reason: String, _ message: String) -> String {
        PhoneLinkProtocol.json(["type": "chatError", "id": id, "reason": reason, "message": message])
    }

    // MARK: Models

    struct Model: Sendable {
        let id: String
        let provider: ChatProvider
        let model: String
        let label: String
    }

    /// The model chosen in Settings → Chat for each provider that is set up: a key for the cloud ones,
    /// a server address for the local ones. The island's current provider first.
    @MainActor
    static func models() -> [Model] {
        let s = AppState.shared
        var list: [Model] = []
        for provider in ChatProvider.allCases {
            let model: String
            switch provider {
            case .anthropic: model = s.claudeModel.isEmpty ? AppState.defaultClaudeModel : s.claudeModel
            case .google:    model = s.googleChatModel
            case .openai:    model = s.openAIChatModel
            case .ollama:    model = s.ollamaChatModel
            case .lmstudio:  model = s.lmstudioChatModel
            }
            let ready: Bool
            switch provider {
            case .ollama:   ready = !s.ollamaServerURL.trimmingCharacters(in: .whitespaces).isEmpty
            case .lmstudio: ready = !s.lmstudioServerURL.trimmingCharacters(in: .whitespaces).isEmpty
            default:        ready = !(KeychainStore.shared.get(provider.keychainKey) ?? "").isEmpty
            }
            guard ready, !model.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            list.append(Model(id: "\(provider.rawValue)/\(model)", provider: provider, model: model,
                              label: "\(provider.displayName) · \(model)"))
        }
        if let current = list.firstIndex(where: { $0.provider == s.chatProvider }) {
            list.insert(list.remove(at: current), at: 0)
        }
        return list
    }

    // MARK: Providers

    struct ChatFailure: Error {
        let reason: String
        let message: String
        static let noKey = ChatFailure(reason: "no_key", message: "That provider is not set up on your Mac.")
        static let notAllowed = ChatFailure(reason: "not_allowed", message: "That model is not offered to the phone.")
        static let unreachable = ChatFailure(reason: "unreachable", message: "Your Mac could not reach the provider.")
        static let auth = ChatFailure(reason: "auth", message: "The provider refused the key saved on your Mac.")
        static let provider = ChatFailure(reason: "provider", message: "The provider could not answer.")
        static let canceled = ChatFailure(reason: "canceled", message: "Stopped.")
    }

    private struct Request: Sendable {
        let provider: ChatProvider
        let model: String
        let key: String?
        let baseURL: String
        let system: String
    }

    private static func answer(model id: String, history: [[String: String]]) async -> Result<String, ChatFailure> {
        guard let request = await MainActor.run(body: { prepare(id) }) else { return .failure(.notAllowed) }
        do {
            let text = try await call(request, history: history)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .failure(.provider) : .success(trimmed)
        } catch let failure as ChatFailure {
            return .failure(failure)
        } catch is CancellationError {
            return .failure(.canceled)
        } catch {
            return .failure(Task.isCancelled ? .canceled : .unreachable)
        }
    }

    /// The request for a model of the list, read on the main actor; nil for anything else.
    @MainActor
    private static func prepare(_ id: String) -> Request? {
        guard let m = models().first(where: { $0.id == id }) else { return nil }
        let s = AppState.shared
        let name = userGreetingName(typed: s.userName, system: systemUserFirstName)
        let opening = name.map { "You are Mochi, \($0)'s personal AI assistant, answering on their phone through Notchy." }
            ?? "You are Mochi, a personal AI assistant, answering on the user's phone through Notchy."
        let system = opening + " Respond in the user's language. Be helpful and concise: the screen is small. "
            + "Use light Markdown when it helps: short paragraphs, bullet lists, **bold**, `inline code`. Avoid tables and big headings."
        let base: String
        switch m.provider {
        case .anthropic: base = "https://api.anthropic.com/v1"
        case .google:    base = "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openai:    base = "https://api.openai.com/v1"
        case .ollama:    base = LocalChat.normaliseURL(s.ollamaServerURL)
        case .lmstudio:  base = LocalChat.normaliseURL(s.lmstudioServerURL)
        }
        let key = m.provider.isLocal ? nil : KeychainStore.shared.get(m.provider.keychainKey)
        return Request(provider: m.provider, model: m.model, key: key, baseURL: base, system: system)
    }

    private static func call(_ r: Request, history: [[String: String]]) async throws -> String {
        if r.provider == .anthropic {
            guard let key = r.key, !key.isEmpty, let url = URL(string: r.baseURL + "/messages") else { throw ChatFailure.noKey }
            var req = URLRequest(url: url, timeoutInterval: 60)
            req.httpMethod = "POST"
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("web-search-2025-03-05", forHTTPHeaderField: "anthropic-beta")
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            let body: [String: Any] = [
                "model": r.model, "max_tokens": 2048, "system": r.system, "messages": history,
                "tools": [["type": "web_search_20250305", "name": "web_search", "max_uses": 3]],
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: req)
            try check(response)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]] else { throw ChatFailure.provider }
            // Every text block, in order: with web search the answer comes in several, between the searches.
            return content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        }
        guard !r.baseURL.isEmpty, let url = URL(string: r.baseURL + "/chat/completions") else { throw ChatFailure.noKey }
        if !r.provider.isLocal && (r.key ?? "").isEmpty { throw ChatFailure.noKey }
        var req = URLRequest(url: url, timeoutInterval: r.provider.isLocal ? 120 : 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(r.key ?? "local")", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": r.model, "max_tokens": 2048, "stream": false,
            "messages": [["role": "system", "content": r.system]] + history,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try check(response)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else { throw ChatFailure.provider }
        return text
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ChatFailure.unreachable }
        switch http.statusCode {
        case 200: return
        case 401, 403: throw ChatFailure.auth
        default: throw ChatFailure.provider
        }
    }
}

#endif
