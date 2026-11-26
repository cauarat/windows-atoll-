import Foundation

// MARK: - Phone link: who is connected, and what they were offered
//
// The hub keeps the list of phones that have authenticated, each with the
// capabilities it was offered. It knows nothing about sockets or AppState:
// connections subscribe to it, and the service closes them all through it when
// the link is switched off or paired again. That keeps the rules of
// docs/PHONE_LINK.md testable without a window, exactly as the Rust `hub.rs` does.
//
// It used to hold the island's sessions, the permission request and the question
// waiting, and to apply a phone's decision to them. Notchy no longer shows coding
// agents, so the chat is all a phone is offered, and what is left here is the
// list of subscribers.

/// What a connection may have been offered.
///
/// `details`, `diffs`, `answers` and `character` are retired with the agent
/// sessions they described; a phone that still asks for them is simply not
/// offered them, as with any capability this computer does not know.
struct PhoneLinkCaps: Equatable, Sendable {
    var chat = false

    /// The `caps` of the welcome line; empty means the field is left out.
    var offered: [String] {
        chat ? ["chat"] : []
    }
}

/// What reaches a connection's writer.
enum PhoneLinkOut: Equatable, Sendable {
    /// One JSON line, without its newline.
    case line(String)
    /// Tell the phone why, then close.
    case close(code: String, message: String)
}

/// A subscriber's way out: true when the line was taken, false when the phone cannot keep up
/// (it is then dropped and closes, and reconnects).
typealias PhoneLinkSender = @Sendable (PhoneLinkOut) -> Bool

final class PhoneLinkHub: @unchecked Sendable {
    private struct Sub {
        let id: UInt64
        let send: PhoneLinkSender
        let caps: PhoneLinkCaps
    }

    private let lock = NSLock()
    private var subs: [Sub] = []
    private var nextSub: UInt64 = 0

    /// How many phones are connected, told whenever it changes (on the queue that changed it).
    private let onClients: (@Sendable (Int) -> Void)?

    init(onClients: (@Sendable (Int) -> Void)? = nil) {
        self.onClients = onClients
    }

    // MARK: Subscribers

    /// Registers a connection that has authenticated.
    @discardableResult
    func subscribe(caps: PhoneLinkCaps, send: @escaping PhoneLinkSender) -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        let id = nextSub
        nextSub += 1
        subs.append(Sub(id: id, send: send, caps: caps))
        onClients?(subs.count)
        return id
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
}
