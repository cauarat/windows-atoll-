import AppKit
import Foundation

// MARK: - Phone link: the service (GitHub build)
//
// Lets Notchy for iPhone and Notchy for Android pair with this Mac (docs/PHONE_LINK.md,
// protocol v1). Off by default and opt-in in Settings → General → Phone. While it is off nothing
// listens, nothing is announced on the network and no timer runs. While it is on, phones' lines
// are handled as they arrive. No polling anywhere.
//
// A paired phone can chat with the providers set up in Settings → Chat. It used to be sent the
// agents' sessions, permission requests and questions too; Notchy no longer shows coding agents,
// so that half of the link is gone.
//
// Compiled out of the App Store build: the sandbox has no server entitlement.

#if !APPSTORE

// MARK: Switches

/// The switches in Settings → General → Phone, read again for every connection.
final class PhoneLinkDefaultsFeatures: PhoneLinkFeatures, @unchecked Sendable {
    static let chatKey = "phoneLinkChat"
    /// The switches for session details, diffs and answering Claude Code's questions, retired with
    /// the agents. Removed from the preferences once, at launch.
    static let retiredKeys = ["phoneLinkDetails", "phoneLinkDiffs", "phoneLinkAnswers"]

    func chat() -> Bool { UserDefaults.standard.bool(forKey: Self.chatKey) }
}

// MARK: Service

@MainActor
final class PhoneLinkService: ObservableObject {
    static let shared = PhoneLinkService()
    static let enabledKey = "phoneLinkEnabled"

    @Published private(set) var running = false
    @Published private(set) var port: UInt16 = 0
    @Published private(set) var error: String?
    /// Phones connected right now.
    @Published private(set) var phones = 0

    private var hub: PhoneLinkHub?
    private var server: PhoneLinkServer?
    private var identity: PhoneLinkMacIdentity?
    private let store = PhoneLinkKeychainStore()

    nonisolated static func log(_ message: String) {
        appendAppLog("PhoneLink.log", message)
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// At launch: starts only if the user turned it on.
    func startIfEnabled() {
        for key in PhoneLinkDefaultsFeatures.retiredKeys { UserDefaults.standard.removeObject(forKey: key) }
        if Self.isEnabled { start() }
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on { start() } else { stop() }
    }

    // MARK: Start and stop

    private func start() {
        guard server == nil else { return }
        guard let token = PhoneLinkIdentity.token(store: store) else {
            fail("no secure storage for the pairing code")
            return
        }
        guard let identity = PhoneLinkMacIdentity.loadOrCreate(store: store) else {
            fail("the Keychain refused the link's certificate")
            return
        }
        let secIdentity = identity.secIdentity
        let hub = PhoneLinkHub { [weak self] count in
            Task { @MainActor in self?.phones = count }
        }
        let server = PhoneLinkServer(hub: hub, features: PhoneLinkDefaultsFeatures(), chat: PhoneLinkChatService.shared,
                                     name: PhoneLinkProtocol.computerName(), token: token)
        server.onState = { [weak self] state in
            Task { @MainActor in self?.serverState(state) }
        }
        self.hub = hub
        self.server = server
        self.identity = identity
        error = nil
        server.start(identity: secIdentity, txt: PhoneLinkProtocol.txtRecord(fingerprint: identity.fingerprint) ?? [:])
        Self.log("starting")
    }

    private func stop() {
        server?.stop()
        server = nil
        hub = nil
        identity = nil
        PhoneLinkChatService.shared.reset()
        running = false
        port = 0
        phones = 0
        error = nil
        Self.log("stopped")
    }

    private func fail(_ message: String) {
        error = message
        running = false
        Self.log("could not start: \(message)")
    }

    private func serverState(_ state: PhoneLinkServer.State) {
        guard server != nil else { return }
        switch state {
        case .ready(let p):
            port = p
            running = true
            error = nil
            Self.log("listening on port \(p)")
        case .failed(let message):
            // Nothing is left half running: the listener is gone, so is everything else.
            stop()
            fail(message)
        }
    }

    // MARK: Pairing

    /// The pairing link for this Mac, or nil while the link is not running.
    func pairingLink() -> String? {
        guard running, let identity, let server, let host = PhoneLinkNetwork.lanAddress() else { return nil }
        return PhoneLinkProtocol.pairingLink(host: host, port: port, fingerprint: identity.fingerprint,
                                             token: server.currentToken, name: PhoneLinkProtocol.computerName())
    }

    /// A new pairing code: the phone that held the old one is locked out and disconnected.
    func pairAgain() {
        guard let server, let hub, let token = PhoneLinkIdentity.newToken(store: store) else { return }
        server.replaceToken(token)
        hub.kickAll(code: "auth", message: "unpaired")
        PhoneLinkChatService.shared.reset()
        Self.log("paired again")
    }

    /// A switch changed: phones reconnect once, to be told what is offered now.
    func switchesChanged() {
        hub?.kickAll(code: "closed", message: "settings changed")
        if !PhoneLinkDefaultsFeatures().chat() { PhoneLinkChatService.shared.reset() }
    }
}

// MARK: Network

enum PhoneLinkNetwork {
    /// This Mac's address on the local network: the one the system would use to reach the outside.
    /// Connecting a UDP socket sends nothing; it only makes the system pick the interface.
    static func lanAddress() -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var remote = sockaddr_in()
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = UInt16(9).bigEndian
        guard inet_pton(AF_INET, "192.0.2.1", &remote.sin_addr) == 1 else { return nil }
        let connected = withUnsafePointer(to: &remote) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }
        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var address = local.sin_addr
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        let text = String(cString: buffer)
        return text == "0.0.0.0" ? nil : text
    }
}

#endif
