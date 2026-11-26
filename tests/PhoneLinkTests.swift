import CryptoKit
import Foundation
import Security

// Checks the Mac side of the phone link against the vectors of the Windows/Linux server
// (windows/src-tauri/src/phone_link/: pairing.rs, discovery.rs, admission.rs, hub.rs, server.rs) and
// the Android client (ProtocolTest.kt): the bytes the Mac produces must be the bytes the phone expects.
// Compiled by scripts/test-phone-link.sh with the pure files of NotchBuddy/Sources/App/PhoneLink/.

nonisolated(unsafe) var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ what: String, line: Int = #line) {
    if !condition() { failures += 1; print("FAIL line \(line): \(what)") }
}

final class MemStore: PhoneLinkSecretStore, @unchecked Sendable {
    var values: [String: String] = [:]
    var refuse = false
    func get(_ key: String) -> String? { values[key] }
    func set(_ key: String, _ value: String) -> Bool {
        if refuse { return false }
        values[key] = value
        return true
    }
}

/// A fake phone: collects the lines the hub sends it.
final class Phone: @unchecked Sendable {
    var lines: [String] = []
    var closed: (String, String)?
    var full = false
    func send(_ out: PhoneLinkOut) -> Bool {
        if full { return false }
        switch out {
        case .line(let l): lines.append(l)
        case .close(let c, let m): closed = (c, m)
        }
        return true
    }
    func types() -> [String] {
        lines.compactMap { l in
            ((try? JSONSerialization.jsonObject(with: Data(l.utf8))) as? [String: Any])?["type"] as? String
        }
    }
    func last(_ type: String) -> [String: Any]? {
        for l in lines.reversed() {
            if let o = (try? JSONSerialization.jsonObject(with: Data(l.utf8))) as? [String: Any], o["type"] as? String == type { return o }
        }
        return nil
    }
}

@main
enum PhoneLinkTests {
    static func main() {
        let P = PhoneLinkProtocol.self
        fingerprints(P); pairing(P); discovery(P); local(P); text(P)
        framing(); incoming(); admission(); identity(); hub(); caps()
        if failures > 0 { print("\(failures) FAILED"); exit(1) }
        print("PhoneLink tests: all passed")
    }

    // MARK: Vectors shared with Rust and Kotlin

    static func fingerprints(_ P: PhoneLinkProtocol.Type) {
        // The certificate's fingerprint, which the phone pins.
        check(P.sha256Hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256 of nothing")
        check(P.sha256Hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256 of abc")
    }

    static func pairing(_ P: PhoneLinkProtocol.Type) {
        let link = P.pairingLink(host: "192.168.1.20", port: 47830, fingerprint: String(repeating: "ab", count: 32),
                                 token: "tok_en-1234567890abcd", name: "Léa's PC & co")
        check(link == "notchy://pair?v=1&host=192.168.1.20&port=47830&fp=\(String(repeating: "ab", count: 32))&token=tok_en-1234567890abcd&name=L%C3%A9a%27s%20PC%20%26%20co",
              "pairing link vector (pairing.rs)")
        check(P.isToken(String(repeating: "a", count: 16)), "16 chars")
        check(P.isToken(String(repeating: "A-_9", count: 32)), "128 chars of the alphabet")
        check(!P.isToken(String(repeating: "a", count: 15)), "15 chars")
        check(!P.isToken(String(repeating: "a", count: 129)), "129 chars")
        check(!P.isToken("aaaaaaaaaaaaaaa!"), "bad char")
        check(!P.isToken("aaaaaaaaaaaaaaa "), "space")
        check(!P.isToken(""), "empty")
        let a = P.randomToken(), b = P.randomToken()
        check(P.isToken(a) && P.isToken(b) && a != b && a.count == 32, "random tokens are valid and differ")
        // The longest realistic link stays under what the phone accepts (2 048 characters).
        let long = P.pairingLink(host: "2001:db8:aaaa:bbbb:cccc:dddd:eeee:ffff", port: 47830, fingerprint: String(repeating: "ab", count: 32),
                                 token: String(repeating: "t", count: 128), name: String(repeating: "é", count: 48))
        check(long.count < 2048, "long link \(long.count)")
    }

    static func discovery(_ P: PhoneLinkProtocol.Type) {
        let fp = "AB12CD34EF56AB78901234567890ABCDEF1234567890ABCDEF1234567890ABCD"
        check(P.fingerprintId(fp) == "ab12cd34ef56ab78", "id is 16 lowercase hex")
        check(P.fingerprintId(fp.lowercased()) == "ab12cd34ef56ab78", "lowercase input")
        check(P.fingerprintId("zz12cd34ef56ab78901234") == nil, "not hex")
        check(P.fingerprintId("abcd") == nil && P.fingerprintId("") == nil, "too short")
        check(P.txtRecord(fingerprint: fp) == ["v": "1", "fp": "ab12cd34ef56ab78"], "TXT: v and fp, nothing else")
        check(P.txtRecord(fingerprint: "not a fingerprint") == nil, "no TXT without a fingerprint")
        check(P.serviceType == "_notchy._tcp", "service type")
        check(P.instanceName("Rhytam's Mac") == "Rhytam's Mac", "instance is the name")
        check(P.instanceName("   ") == "Notchy", "empty name")
        check(P.instanceName(String(repeating: "x", count: 100)).count == 48, "name cut at 48")
    }

    static func local(_ P: PhoneLinkProtocol.Type) {
        for ok in ["192.168.1.20", "10.0.0.5", "172.16.3.4", "172.31.255.255", "127.0.0.1", "169.254.7.7", "::1", "fd12:3456::1", "fe80::1", "::ffff:192.168.0.9"] {
            check(P.isLocal(address: ok), "\(ok) is local")
        }
        for no in ["8.8.8.8", "172.32.0.1", "100.64.0.1", "2001:db8::1", "::ffff:8.8.8.8", "0.0.0.0", "nonsense"] {
            check(!P.isLocal(address: no), "\(no) is not local")
        }
    }

    static func text(_ P: PhoneLinkProtocol.Type) {
        check(P.clip("héllo", 2) == "hé", "clip on a character")
        check(P.isChatId("a-Z_9") && !P.isChatId("") && !P.isChatId(String(repeating: "a", count: 65)) && !P.isChatId("a b"), "chat ids")
        check(P.constantEq("abc", "abc") && !P.constantEq("abc", "abd") && !P.constantEq("abc", "ab"), "constant-time equality")
    }

    // MARK: Framing

    static func framing() {
        var r = PhoneLinkLineReader()
        check(r.feed(Data("{\"a\":1}\n{\"b\"".utf8))?.count == 1, "one complete line")
        check(r.feed(Data(":2}\r\n\n".utf8))?.count == 1, "the rest, CRLF dropped, empty line skipped")
        // A line of exactly 64 KiB is accepted, one byte more is a protocol error.
        var exact = PhoneLinkLineReader()
        let ok = exact.feed(Data(String(repeating: "a", count: PhoneLinkProtocol.maxLine).utf8 + [0x0A]))
        check(ok?.count == 1, "64 KiB line accepted")
        var over = PhoneLinkLineReader()
        check(over.feed(Data(String(repeating: "a", count: PhoneLinkProtocol.maxLine + 1).utf8 + [0x0A])) == nil, "64 KiB + 1 refused")
        var endless = PhoneLinkLineReader()
        check(endless.feed(Data(String(repeating: "a", count: PhoneLinkProtocol.maxLine + 10).utf8)) == nil, "no newline within the limit")
        var split = PhoneLinkLineReader()
        check(split.feed(Data(String(repeating: "a", count: 40_000).utf8))?.isEmpty == true, "half a big line waits")
        check(split.feed(Data((String(repeating: "a", count: 20_000) + "\n").utf8))?.count == 1, "and completes")
    }

    static func incoming() {
        func parse(_ s: String) -> PhoneLinkIncoming? { PhoneLinkIncoming.parse(Data(s.utf8)) }
        check(parse("{\"type\":\"hello\",\"v\":1,\"token\":\"tok\",\"device\":\"Pixel\",\"caps\":[\"details\",\"chat\"]}")
              == .hello(token: "tok", version: 1, device: "Pixel", caps: ["details", "chat"]), "hello")
        check(parse("{\"type\":\"hello\"}") == .hello(token: "", version: nil, device: "", caps: []), "bare hello")
        check(parse("{\"type\":\"ping\"}") == .ping && parse("{\"type\":\"bye\"}") == .bye, "ping, bye")
        // What answered the agents is an unknown type now, ignored like any other.
        check(parse("{\"type\":\"decision\",\"fingerprint\":\"f\",\"decision\":\"allow\"}") == .other(type: "decision"), "decision is ignored")
        check(parse("{\"type\":\"answer\",\"fingerprint\":\"f\",\"picks\":[[\"a\"]]}") == .other(type: "answer"), "answer is ignored")
        check(parse("{\"type\":\"getDiff\",\"pillId\":\"p\",\"fileId\":1}") == .other(type: "getDiff"), "getDiff is ignored")
        check(parse("{\"type\":\"chatSend\",\"id\":\"c1\",\"model\":\"anthropic/x\",\"text\":\"hi\"}")
              == .chatSend(id: "c1", model: "anthropic/x", text: "hi"), "chatSend")
        check(parse("{\"type\":\"chatModels\"}") == .chatModels && parse("{\"type\":\"chatReset\"}") == .chatReset, "chatModels, chatReset")
        check(parse("{\"type\":\"chatSend\"}") == .other(type: "chatSend"), "unknown types are ignored, not errors")
        check(parse("not json") == nil && parse("[1]") == nil, "not an object")
    }

    // MARK: Admission (admission.rs)

    static func admission() {
        typealias A = PhoneLinkAdmission
        let a = A()
        let t1 = a.admit("192.168.1.50")
        let t2 = a.admit("192.168.1.50")
        check(t1 != nil && t2 != nil, "two silent connections from one address")
        check(a.admit("192.168.1.50") == nil, "the third from one address")
        check(a.admit("192.168.1.51") != nil, "another address is not affected")
        t1?.release()
        check(a.admit("192.168.1.50") != nil, "a closed connection frees its place")

        // Strangers share a pool smaller than the whole.
        let b = A()
        var held: [A.Ticket] = []
        for n in 0..<(A.maxUnauthStrangers / A.maxUnauthPerAddress) {
            for _ in 0..<A.maxUnauthPerAddress { if let t = b.admit("10.0.0.\(n + 1)") { held.append(t) } }
        }
        check(held.count == A.maxUnauthStrangers, "stranger pool is \(A.maxUnauthStrangers)")
        check(b.admit("10.0.0.99") == nil, "the stranger pool is full")
        check(held.count < A.maxConnections, "slots are left for known phones")

        // A flood from many addresses cannot lock out the paired phone.
        let c = A()
        c.admit("192.168.1.20")?.authenticated()
        check(c.knows("192.168.1.20"), "authenticated address remembered")
        var flood: [A.Ticket] = []
        for n in 0..<50 { if let t = c.admit("192.168.1.\(100 + n)") { flood.append(t) } }
        check(flood.count == A.maxUnauthStrangers, "the flood is capped")
        let phone = c.admit("192.168.1.20")
        check(phone != nil, "the paired phone still gets in")
        phone?.authenticated()
        let again = c.admit("192.168.1.20")
        check(again != nil, "and can reconnect during the flood")
        again?.authenticated()
        check(c.counts.1 == A.maxUnauthStrangers && c.counts.0 <= A.maxConnections, "counts")

        // A flood from one address leaves every other address alone.
        let d = A()
        var one: [A.Ticket] = []
        for _ in 0..<20 { if let t = d.admit("192.168.1.66") { one.append(t) } }
        check(d.admit("192.168.1.20") != nil, "a newcomer still connects")

        // Authenticating is counted once and frees the unauthenticated place.
        let e = A()
        let t = e.admit("192.168.1.20")!
        t.authenticated(); t.authenticated()
        check(e.counts.0 == 1 && e.counts.1 == 0, "authenticated once")
        let u1 = e.admit("192.168.1.20"), u2 = e.admit("192.168.1.20")
        check(u1 != nil && u2 != nil, "authenticated connection no longer counts against the per-address limit")

        // The total never goes over eight, even for known phones.
        let f = A()
        var all: [A.Ticket] = []
        for n in 0..<A.maxConnections { let x = f.admit("192.168.1.\(10 + n)")!; x.authenticated(); all.append(x) }
        check(f.admit("192.168.1.10") == nil, "no ninth connection")

        // Places come back when tickets are released or dropped, whatever their state.
        let g = A()
        do {
            let x = g.admit("192.168.1.20")!
            _ = g.admit("192.168.1.21")
            x.authenticated()
        }
        check(g.counts.0 == 0 && g.counts.1 == 0, "dropped tickets give their places back")

        // The wait is shorter when the pool is filling up.
        let h = A()
        check(h.admit("192.168.1.1")!.wait == A.patient, "an empty server is patient")
        var more: [A.Ticket] = []
        for n in 0..<2 { more.append(h.admit("192.168.2.\(n)")!) }
        check(h.admit("192.168.3.1")!.wait == A.hurried, "hurried when strangers fill up")

        // At most eight addresses are remembered.
        let i = A()
        for n in 0..<(A.knownAddresses + 3) { i.admit("192.168.5.\(n)")?.authenticated() }
        check(!i.knows("192.168.5.0") && i.knows("192.168.5.\(A.knownAddresses + 2)"), "the oldest is forgotten")
    }

    // MARK: Identity (pairing.rs)

    static func identity() {
        let store = MemStore()
        guard let first = PhoneLinkIdentity.loadOrCreate(store: store) else { check(false, "identity created"); return }
        let again = PhoneLinkIdentity.loadOrCreate(store: store)
        check(again?.certificateDER == first.certificateDER && again?.fingerprint == first.fingerprint, "the certificate is made once and kept")
        check(first.fingerprint.count == 64 && first.fingerprint == PhoneLinkProtocol.sha256Hex(first.certificateDER), "fingerprint is the SHA-256 of the DER")
        // The system's own parser accepts it, and it carries the key we signed with.
        if let cert = SecCertificateCreateWithData(nil, first.certificateDER as CFData) {
            check((SecCertificateCopySubjectSummary(cert) as String?) == "Notchy phone link", "subject")
            var trust: SecTrust?
            check(SecTrustCreateWithCertificates(cert, SecPolicyCreateBasicX509(), &trust) == errSecSuccess, "usable as a trust object")
        } else {
            check(false, "Security parses the certificate")
        }
        // The signature verifies with the certificate's own public key.
        let parsed = parseCertificate(Array(first.certificateDER))
        check(parsed != nil, "DER structure")
        if let (tbs, signature) = parsed,
           let sig = try? P256.Signing.ECDSASignature(derRepresentation: Data(signature)) {
            check(first.privateKey.publicKey.isValidSignature(sig, for: Data(tbs)), "self-signature verifies")
        } else {
            check(false, "signature parsed")
        }
        // A damaged key means a new identity, not a crash; the new one is what is kept.
        store.values[PhoneLinkIdentity.privateKeyKey] = "zz-not-hex"
        let next = PhoneLinkIdentity.loadOrCreate(store: store)
        check(next != nil && next?.fingerprint != first.fingerprint, "damaged key: new identity")
        check(PhoneLinkIdentity.loadOrCreate(store: store)?.fingerprint == next?.fingerprint, "and kept")
        // A store that refuses writes: no identity, nothing half-saved.
        let locked = MemStore(); locked.refuse = true
        check(PhoneLinkIdentity.loadOrCreate(store: locked) == nil, "no identity without secure storage")
        check(locked.values.isEmpty, "nothing kept")
        // Tokens.
        let t = PhoneLinkIdentity.token(store: store)!
        check(PhoneLinkProtocol.isToken(t) && PhoneLinkIdentity.token(store: store) == t, "token kept")
        let n = PhoneLinkIdentity.newToken(store: store)!
        check(n != t && PhoneLinkIdentity.token(store: store) == n, "new token replaces it")
        store.values[PhoneLinkIdentity.tokenKey] = "short"
        check(PhoneLinkProtocol.isToken(PhoneLinkIdentity.token(store: store)!), "a damaged token is replaced")
        // Nothing but the store is written: the secrets are exactly what the store holds.
        check(store.values[PhoneLinkIdentity.privateKeyKey]?.count == 64, "raw key kept in the store only")
    }

    /// (to-be-signed bytes, signature DER) of a certificate, or nil if it is not Certificate ::= SEQUENCE { tbs, alg, sig }.
    static func parseCertificate(_ der: [UInt8]) -> ([UInt8], [UInt8])? {
        func read(_ b: [UInt8], _ at: Int) -> (tag: UInt8, start: Int, end: Int)? {
            guard at + 2 <= b.count else { return nil }
            var len = Int(b[at + 1]); var start = at + 2
            if len & 0x80 != 0 {
                let n = len & 0x7F
                guard n > 0, n <= 4, at + 2 + n <= b.count else { return nil }
                len = 0
                for k in 0..<n { len = len << 8 | Int(b[at + 2 + k]) }
                start = at + 2 + n
            }
            guard start + len <= b.count else { return nil }
            return (b[at], start, start + len)
        }
        guard let outer = read(der, 0), outer.tag == 0x30, outer.end == der.count,
              let tbs = read(der, outer.start), tbs.tag == 0x30,
              let alg = read(der, tbs.end), alg.tag == 0x30,
              let sig = read(der, alg.end), sig.tag == 0x03, sig.end == outer.end else { return nil }
        return (Array(der[outer.start..<tbs.end]), Array(der[(sig.start + 1)..<sig.end]))
    }

    // MARK: Hub (hub.rs)

    static func hub() {
        nonisolated(unsafe) var counts: [Int] = []
        let hub = PhoneLinkHub { counts.append($0) }
        let a = Phone(), b = Phone()
        let first = hub.subscribe(caps: PhoneLinkCaps(chat: true), send: a.send)
        hub.subscribe(caps: PhoneLinkCaps(), send: b.send)
        check(hub.clients == 2 && counts == [1, 2], "two phones, each counted")
        check(a.lines.isEmpty && b.lines.isEmpty, "nothing is pushed to a phone that just arrived: no sessions any more")
        hub.unsubscribe(first)
        check(hub.clients == 1 && counts.last == 1, "one left")
        hub.kickAll(code: "auth", message: "unpaired")
        check(hub.clients == 0 && counts.last == 0, "all gone")
        check(b.closed?.0 == "auth" && a.closed == nil, "the phone still connected is told why")
    }

    // MARK: Capabilities

    static func caps() {
        check(PhoneLinkCaps(chat: true).offered == ["chat"], "chat is the one capability left")
        check(PhoneLinkCaps().offered.isEmpty, "no caps, no field")
    }
}
