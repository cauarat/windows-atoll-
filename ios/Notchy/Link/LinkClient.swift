import CryptoKit
import Foundation
import Network

// MARK: - The connection to the computer (docs/PHONE_LINK.md)
//
// TLS 1.2+ over TCP, newline-delimited JSON. No certificate authority and no host name: the phone
// accepts exactly one certificate, the one whose SHA-256 the pairing link carried, and nothing else
// (certificate pinning). The token is sent only inside that pinned connection.
//
// Everything runs on one private serial queue. A connection that fails is retried with a growing
// pause (1 s, 2 s, 5 s, 10 s, 30 s); a new network, or the app coming back to the front, retries at
// once. When the saved address stops answering, the computer is looked for on the local network by
// its Bonjour announcement (`_notchy._tcp`, the certificate's short id in the TXT record), and a
// candidate is only ever accepted by the full pinned fingerprint of its certificate.

final class LinkClient: @unchecked Sendable {
    enum Status: Equatable, Sendable {
        case idle
        case connecting
        case connected(desktop: String, os: String)
        /// The computer refused the token: unpaired there, or paired again.
        case unauthorized
        case waiting(reason: String)
    }

    /// The optional features this app understands; the computer offers the ones its user switched on.
    static let caps = ["details", "answers", "diffs", "character", "chat"]

    var onMessage: (@Sendable (ServerMessage) -> Void)?
    var onStatus: (@Sendable (Status) -> Void)?
    /// The computer was found at a new address: the caller saves it.
    var onMoved: (@Sendable (PairedComputer) -> Void)?

    private let queue = DispatchQueue(label: "com.cauarati.NotchyPhone.link")
    private var computer: PairedComputer?
    private var connection: NWConnection?
    private var generation = 0
    private var reader = PhoneLinkLineReader()
    private var authenticated = false
    private var pingTimer: DispatchSourceTimer?
    private var retryItem: DispatchWorkItem?
    private var connectTimeout: DispatchWorkItem?
    private var failures = 0
    private var browser: NWBrowser?
    private var pathMonitor: NWPathMonitor?
    private var running = false
    private var deviceName: String
    /// An address Bonjour pointed at, not saved until its certificate has passed the pin and the computer welcomed us.
    private var candidate: PairedComputer?
    /// The network's last status, so the first report (at start) is not taken for a change.
    private var lastPath: NWPath.Status?

    init(deviceName: String) {
        self.deviceName = String(deviceName.prefix(48))
    }

    // MARK: Control

    func start(_ computer: PairedComputer) {
        queue.async { [self] in
            self.computer = computer
            running = true
            failures = 0
            watchNetwork()
            connect(to: computer.host, port: computer.port)
        }
    }

    func stop() {
        queue.async { [self] in
            running = false
            computer = nil
            retryItem?.cancel()
            stopBrowsing()
            pathMonitor?.cancel()
            pathMonitor = nil
            sendNow(["type": "bye"])
            teardown()
            onStatus?(.idle)
        }
    }

    /// The app came to the front, or the user pulled to refresh: if not connected, try now.
    func retryNow() {
        queue.async { [self] in
            guard running, let computer, connection == nil || !authenticated else { return }
            retryItem?.cancel()
            failures = 0
            teardown()
            connect(to: computer.host, port: computer.port)
        }
    }

    var isConnected: Bool { queue.sync { authenticated } }

    func send(_ object: [String: Any]) {
        queue.async { [self] in sendNow(object) }
    }

    // MARK: Connecting

    private func connect(to host: String, port: UInt16) {
        guard running, let computer, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        generation += 1
        let gen = generation
        authenticated = false
        reader = PhoneLinkLineReader()
        onStatus?(.connecting)

        let parameters = NWParameters(tls: Self.pinnedTLS(fingerprint: computer.fingerprint, queue: queue), tcp: {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            tcp.connectionTimeout = 4
            return tcp
        }())
        let nw = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        connection = nw
        nw.stateUpdateHandler = { [weak self] state in
            guard let self, gen == self.generation else { return }
            switch state {
            case .ready:
                self.connectTimeout?.cancel()
                self.hello()
                self.receive(nw, gen: gen)
            case .waiting(let error):
                self.failed("waiting: \(error)", gen: gen)
            case .failed(let error):
                self.failed("failed: \(error)", gen: gen)
            case .cancelled:
                break
            default:
                break
            }
        }
        // A saved address on another network never answers: give it a few seconds, then look for the computer.
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, gen == self.generation, !self.authenticated else { return }
            self.failed("timed out", gen: gen)
        }
        connectTimeout = timeout
        queue.asyncAfter(deadline: .now() + 6, execute: timeout)
        nw.start(queue: queue)
    }

    private static func pinnedTLS(fingerprint: String, queue: DispatchQueue) -> NWProtocolTLS.Options {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_verify_block(options, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate], let leaf = chain.first else {
                complete(false)
                return
            }
            let der = SecCertificateCopyData(leaf) as Data
            // The one certificate the pairing link named, compared in constant time; nothing else is trusted.
            complete(PhoneLinkProtocol.constantEq(PhoneLinkProtocol.sha256Hex(der), fingerprint))
        }, queue)
        return tls
    }

    private func hello() {
        guard let computer else { return }
        sendNow(["type": "hello", "v": PhoneLinkProtocol.version, "token": computer.token, "device": deviceName, "caps": Self.caps])
    }

    private func receive(_ nw: NWConnection, gen: Int) {
        nw.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self, gen == self.generation else { return }
            if let data, !data.isEmpty {
                guard let lines = self.reader.feed(data) else {
                    self.failed("line too long", gen: gen)
                    return
                }
                for line in lines {
                    guard gen == self.generation else { return }
                    self.handle(line, gen: gen)
                }
            }
            if complete || error != nil {
                self.failed("closed", gen: gen)
                return
            }
            self.receive(nw, gen: gen)
        }
    }

    private func handle(_ line: Data, gen: Int) {
        guard let message = ServerMessage.parse(line) else { return }
        switch message {
        case .welcome(let v, let desktop, let os, _):
            guard v == PhoneLinkProtocol.version else {
                teardown()
                onStatus?(.waiting(reason: "version"))
                return
            }
            authenticated = true
            failures = 0
            stopBrowsing()
            if let moved = candidate {
                candidate = nil
                computer = moved
                onMoved?(moved)
            }
            startPing()
            onStatus?(.connected(desktop: desktop, os: os))
        case .error(let code, _):
            if code == "auth" {
                // Unpaired on the computer, or paired again with another phone: stop knocking.
                running = false
                teardown()
                onStatus?(.unauthorized)
                return
            }
        default:
            break
        }
        onMessage?(message)
    }

    private func failed(_ reason: String, gen: Int) {
        guard gen == generation else { return }
        let wasUp = authenticated
        candidate = nil
        teardown()
        guard running else { return }
        onStatus?(.waiting(reason: reason))
        failures += 1
        // The saved address did not answer twice in a row: look for the computer on this network.
        if !wasUp && failures >= 2 { browse() }
        let delays: [TimeInterval] = [1, 2, 5, 10, 30]
        let delay = wasUp ? 0.5 : delays[min(failures - 1, delays.count - 1)]
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.running, let computer = self.computer, self.connection == nil else { return }
            self.connect(to: computer.host, port: computer.port)
        }
        retryItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func teardown() {
        generation += 1
        connectTimeout?.cancel()
        pingTimer?.cancel()
        pingTimer = nil
        connection?.cancel()
        connection = nil
        authenticated = false
    }

    private func sendNow(_ object: [String: Any]) {
        guard let connection, JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func startPing() {
        pingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 20, repeating: 20, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in self?.sendNow(["type": "ping"]) }
        timer.resume()
        pingTimer = timer
    }

    // MARK: Finding the computer again

    private func watchNetwork() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self, self.running else { return }
            let first = self.lastPath == nil
            self.lastPath = path.status
            // A network came up (or changed): whatever was waiting, try now.
            if path.status == .satisfied, !first, !self.authenticated, let computer = self.computer {
                self.retryItem?.cancel()
                self.failures = 0
                self.teardown()
                self.connect(to: computer.host, port: computer.port)
            }
        }
        monitor.start(queue: queue)
        pathMonitor = monitor
    }

    private func browse() {
        guard browser == nil, let computer, let shortId = PhoneLinkProtocol.fingerprintId(computer.fingerprint) else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: PhoneLinkProtocol.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            for result in results {
                guard case .bonjour(let txt) = result.metadata, txt["fp"] == shortId, (txt["v"] ?? "1") == "1" else { continue }
                self.resolve(result.endpoint)
                return
            }
        }
        browser.start(queue: queue)
        self.browser = browser
        // Fifteen seconds of looking at most; the next failure looks again.
        queue.asyncAfter(deadline: .now() + 15) { [weak self, weak browser] in
            guard let self, let browser, self.browser === browser else { return }
            self.stopBrowsing()
        }
    }

    /// Turns a Bonjour result into an address, through a plain TCP connection that sends nothing; the TLS
    /// connection that follows is what proves it is the paired computer (the pinned fingerprint).
    private func resolve(_ endpoint: NWEndpoint) {
        let probe = NWConnection(to: endpoint, using: .tcp)
        probe.stateUpdateHandler = { [weak self, weak probe] state in
            guard let self, let probe else { return }
            switch state {
            case .ready:
                if case .hostPort(let host, let port)? = probe.currentPath?.remoteEndpoint,
                   var moved = self.computer, self.candidate == nil {
                    let address: String
                    switch host {
                    case .ipv4(let a): address = "\(a)"
                    case .ipv6(let a): address = "\(a)"
                    case .name(let n, _): address = n
                    @unknown default: address = ""
                    }
                    probe.cancel()
                    let clean = address.split(separator: "%").first.map(String.init) ?? address
                    guard !clean.isEmpty, PhoneLinkProtocol.isLocal(address: clean) else { return }
                    guard clean != moved.host || port.rawValue != moved.port else { return }
                    moved.host = clean
                    moved.port = port.rawValue
                    self.stopBrowsing()
                    self.retryItem?.cancel()
                    self.teardown()
                    // Tried, not trusted: saved only once the pinned certificate has answered (see `.welcome`).
                    self.candidate = moved
                    self.connect(to: moved.host, port: moved.port)
                }
            case .failed, .cancelled:
                probe.cancel()
            default:
                break
            }
        }
        probe.start(queue: queue)
    }

    private func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }
}
