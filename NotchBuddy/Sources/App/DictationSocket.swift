import Foundation

/// One dictation's connection to the transcription service.
///
/// Not bound to the main thread: audio frames come from the microphone's
/// thread and go straight out, through one serial queue so they leave in the
/// order they were heard, with `start` first and `stop` last. What the service
/// answers is handed to `deliver` on URLSession's own queue; the controller
/// brings it to the main thread.
final class DictationSocket: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    enum Closed: Equatable, Sendable {
        /// Nothing answered at the address: the service is not running there.
        case refused
        /// It answered, then the connection went.
        case lost
    }

    enum Event: Sendable {
        case message(DictationServerMessage)
        case closed(Closed)
    }

    private let url: URL
    private let deliver: @Sendable (Event) -> Void
    private let sendQueue = DispatchQueue(label: "fr.notchy.dictation.socket")
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var opened = false
    private var ended = false

    init(url: URL, deliver: @escaping @Sendable (Event) -> Void) {
        self.url = url
        self.deliver = deliver
    }

    func open(start: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        lock.lock()
        self.session = session
        self.task = task
        lock.unlock()
        task.resume()
        send(.string(start))
        receive()
    }

    func send(audio: Data) {
        send(.data(audio))
    }

    /// All the audio has been sent: the service answers with the final.
    func stop() {
        send(.string(DictationProtocol.stopMessage))
    }

    /// Drop the dictation. Nothing more is delivered.
    func cancel() {
        send(.string(DictationProtocol.cancelMessage))
        sendQueue.async { [weak self] in self?.close(code: .goingAway) }
    }

    func close(code: URLSessionWebSocketTask.CloseCode = .normalClosure) {
        lock.lock()
        ended = true
        let task = self.task
        let session = self.session
        lock.unlock()
        task?.cancel(with: code, reason: nil)
        session?.invalidateAndCancel()
    }

    private func send(_ message: URLSessionWebSocketTask.Message) {
        sendQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let task = self.ended ? nil : self.task
            self.lock.unlock()
            task?.send(message) { [weak self] error in
                if error != nil { self?.end() }
            }
        }
    }

    private func receive() {
        lock.lock()
        let task = ended ? nil : self.task
        lock.unlock()
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)):
                if let message = DictationServerMessage.decode(text) { self.deliver(.message(message)) }
                self.receive()
            case .success:
                self.receive()
            case .failure:
                self.end()
            }
        }
    }

    /// The first ending is the one reported; the rest are its echoes.
    private func end() {
        lock.lock()
        let first = !ended
        ended = true
        let wasOpen = opened
        let session = self.session
        lock.unlock()
        guard first else { return }
        deliver(.closed(wasOpen ? .lost : .refused))
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        lock.lock()
        opened = true
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        end()
    }
}

/// `GET /health`: whether the service is there, what it runs, and whether the
/// model is ready. Asked when Settings or the card wants to know, never on a
/// timer — nothing here runs while the island is hidden.
enum DictationServiceProbe {
    enum Failure: Error, Equatable, Sendable {
        case invalidAddress
        case offline
        /// Something answered, but not this service.
        case notTheService
    }

    static func health(service: String) async -> Result<DictationHealth, Failure> {
        guard let url = DictationProtocol.healthURL(service: service) else { return .failure(.invalidAddress) }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let health = DictationHealth.decode(data) else {
                return .failure(.notTheService)
            }
            return .success(health)
        } catch {
            return .failure(.offline)
        }
    }
}
