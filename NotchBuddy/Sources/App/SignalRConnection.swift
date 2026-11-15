//
//  SignalRConnection.swift
//  Notchy
//
//  Just enough ASP.NET Core SignalR to listen to Ato.
//

import Foundation

/// A minimal SignalR client — JSON protocol, WebSocket transport, no
/// negotiation — over `URLSessionWebSocketTask`.
///
/// Only what Ato needs: open, shake hands, receive invocations, keep the
/// connection alive. No invoking, no streams, no MessagePack. Ato's own web
/// console connects the same way (`skipNegotiation`, WebSockets only), so the
/// server is known to accept exactly this.
///
/// The wire format, for whoever reads this next. Every message is JSON ending
/// in the record separator `0x1E`, and one frame can carry several:
///
/// ```
/// {"protocol":"json","version":1}␞            handshake, client → server
/// {}␞                                         handshake accepted
/// {"type":1,"target":"onX","arguments":[…]}␞  invocation (the one that matters)
/// {"type":6}␞                                 ping, either way
/// {"type":7,"error":"…","allowReconnect":true}␞  close
/// ```
///
/// The client has to ping too: the server drops a connection it has not
/// heard from in 30 seconds, and a listener that never invokes anything is
/// silent unless it pings.
// Main-actor isolated for the reason `SocketIOConnection` gives: its owner is,
// and the receive loop is a Task capturing self.
@MainActor
final class SignalRConnection {
    enum ConnectionEvent {
        /// The handshake was accepted; invocations will follow.
        case connected
        /// A server-to-client invocation: the method name, and its first
        /// argument as raw JSON.
        case invocation(target: String, payload: Data)
        /// The handshake was refused. The server's reason, as it gave it.
        case rejected(String)
        /// The transport failed. Says nothing about the credentials.
        case failed(String)
        /// The server closed the connection, with its reason if it gave one.
        case closed(String?)
    }

    private nonisolated static let recordSeparator: Character = "\u{1E}"

    private let url: URL
    private let session: URLSession
    private let onEvent: (ConnectionEvent) -> Void

    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var isStopping = false
    private var handshakeDone = false

    /// - Parameter url: the hub, already carrying `access_token`. A browser
    ///   cannot set headers on a WebSocket, so SignalR servers read the token
    ///   from the query — this is the route the web console itself uses.
    init(url: URL, session: URLSession = .shared, onEvent: @escaping (ConnectionEvent) -> Void) {
        self.url = url
        self.session = session
        self.onEvent = onEvent
    }

    // MARK: - Lifecycle

    func connect() {
        isStopping = false
        handshakeDone = false
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        send(#"{"protocol":"json","version":1}"#)

        receiveLoop = Task { [weak self] in
            await self?.listen(task)
        }
    }

    func disconnect() {
        isStopping = true
        receiveLoop?.cancel()
        receiveLoop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    /// The protocol-level ping the server counts, plus a transport ping: a
    /// dropped Wi-Fi can leave `receive()` hanging rather than throwing.
    func ping() {
        guard handshakeDone else { return }
        send(#"{"type":6}"#)
        task?.sendPing { _ in }
    }

    // MARK: - Receiving

    private func listen(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text): handle(text)
                case .data(let data): handle(String(decoding: data, as: UTF8.self))
                @unknown default: break
                }
            } catch {
                guard !Task.isCancelled, !isStopping else { return }
                onEvent(.failed(error.localizedDescription))
                return
            }
        }
    }

    private func handle(_ frame: String) {
        for record in Self.records(in: frame) {
            handleRecord(record)
        }
    }

    /// Splits a frame into its JSON records. Pure, for the tests.
    nonisolated static func records(in frame: String) -> [String] {
        frame.split(separator: recordSeparator, omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func handleRecord(_ record: String) {
        guard let data = record.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        guard handshakeDone else {
            // The first record is the handshake answer: `{}` or `{"error":…}`.
            if let error = object["error"] as? String {
                onEvent(.rejected(error))
            } else {
                handshakeDone = true
                onEvent(.connected)
            }
            return
        }

        switch object["type"] as? Int {
        case 1:
            guard let target = object["target"] as? String else { return }
            let arguments = object["arguments"] as? [Any] ?? []
            let first: Any = arguments.first ?? [String: Any]()
            guard JSONSerialization.isValidJSONObject(first),
                  let payload = try? JSONSerialization.data(withJSONObject: first)
            else { return }
            onEvent(.invocation(target: target, payload: payload))

        case 7:
            onEvent(.closed(object["error"] as? String))

        default:
            // 6 is a ping and needs no answer beyond our own; completions and
            // stream items belong to invocations this client never makes.
            break
        }
    }

    // MARK: - Sending

    private func send(_ json: String) {
        task?.send(.string(json + String(Self.recordSeparator))) { _ in }
    }
}
