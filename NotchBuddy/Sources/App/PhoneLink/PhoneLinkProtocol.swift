import CryptoKit
import Foundation

// MARK: - Phone link, protocol v1: the wire (docs/PHONE_LINK.md)
//
// The Mac side of the link with Notchy for iPhone and Android. Ported from Coucou's
// Android link (Louis-CFM/coucou, NotchBuddy/Sources/App/AndroidLink, MIT), which
// is also what Coucou's Windows/Linux server speaks, so a phone cannot tell a Mac
// from a PC. Newline-delimited JSON over TLS, a self-signed certificate the phone
// pins, a pairing token that is the shared secret. Notchy's names are its own
// (`notchy://pair`, `_notchy._tcp`, port 47830) so a phone paired with Coucou is
// never offered a Notchy and the other way round; every message is protocol v1.
//
// This file is the pure part: no sockets, no Keychain, no AppState, so every rule
// here is checked by scripts/test-phone-link.sh against the vectors Coucou's Rust
// and Kotlin tests use. The bytes it produces (fingerprints, pairing links, TXT
// records, JSON lines) must stay identical to theirs.

enum PhoneLinkProtocol {
    static let version = 1
    /// The port the pairing link offers; another is taken if it is busy.
    static let defaultPort: UInt16 = 47830
    /// A line over this is a protocol error (the connection closes).
    static let maxLine = 64 * 1024
    /// The DNS-SD service type the phone browses for.
    static let serviceType = "_notchy._tcp"
    /// How many hex characters of the certificate fingerprint go into the TXT record.
    static let fingerprintIdLength = 16
    /// The protocol version in the TXT record.
    static let txtVersion = "1"

    // MARK: Hashing and comparing

    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    /// Constant-time equality, so a token or fingerprint cannot be guessed byte by byte.
    /// The length is not secret (tokens and fingerprints have a fixed size).
    static func constantEq(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var acc: UInt8 = 0
        for i in 0..<x.count { acc |= x[i] ^ y[i] }
        return acc == 0
    }

    // MARK: Pairing

    /// A chat message id made by the phone: 1 to 64 characters of `[A-Za-z0-9_-]`.
    static func isChatId(_ s: String) -> Bool {
        let bytes = Array(s.utf8)
        guard (1...64).contains(bytes.count) else { return false }
        return bytes.allSatisfy { b in
            (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x5F || b == 0x2D
        }
    }

    /// 16 to 128 characters of `[A-Za-z0-9_-]`.
    static func isToken(_ s: String) -> Bool {
        let bytes = Array(s.utf8)
        guard (16...128).contains(bytes.count) else { return false }
        return bytes.allSatisfy { b in
            (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x5F || b == 0x2D
        }
    }

    /// A fresh pairing token: 32 symbols of a 64-symbol alphabet (192 bits) from the system's
    /// cryptographic random source.
    static func randomToken() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var generator = SystemRandomNumberGenerator()
        return String((0..<32).map { _ in alphabet[Int(generator.next() & 63)] })
    }

    /// RFC 3986 unreserved characters and `:` stay; everything else is `%XX` (same as the Rust encoder).
    static func percentEncode(_ s: String) -> String {
        var out = ""
        for b in s.utf8 {
            let keep = (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
                || b == 0x2D || b == 0x5F || b == 0x2E || b == 0x7E || b == 0x3A
            if keep { out.unicodeScalars.append(UnicodeScalar(b)) } else { out += String(format: "%%%02X", b) }
        }
        return out
    }

    /// `notchy://pair?v=1&host=…&port=…&fp=…&token=…&name=…`
    static func pairingLink(host: String, port: UInt16, fingerprint: String, token: String, name: String) -> String {
        "notchy://pair?v=1&host=\(percentEncode(host))&port=\(port)&fp=\(fingerprint)&token=\(token)&name=\(percentEncode(name))"
    }

    // MARK: Discovery (Bonjour)

    /// The short, non-secret id of a certificate fingerprint: its first 16 lowercase hex characters.
    /// nil if the input is not hex.
    static func fingerprintId(_ fingerprint: String) -> String? {
        let f = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bytes = Array(f.utf8)
        guard bytes.count >= fingerprintIdLength,
              bytes.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }) else { return nil }
        return String(f.prefix(fingerprintIdLength))
    }

    /// The TXT record: `v` and `fp`, nothing else. Never the token, never the pairing link, never a path.
    static func txtRecord(fingerprint: String) -> [String: String]? {
        guard let id = fingerprintId(fingerprint) else { return nil }
        return ["v": txtVersion, "fp": id]
    }

    /// The service's instance name: the computer's name, at most 48 characters, "Notchy" if empty.
    static func instanceName(_ name: String) -> String {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Notchy" : trimmed
    }

    /// The name the phone shows for this Mac.
    #if os(macOS)
    static func computerName() -> String {
        let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        return String(name.prefix(48))
    }
    #endif

    // MARK: The local network only

    /// Private (10/8, 172.16/12, 192.168/16), loopback and link-local IPv4 addresses.
    static func isLocal(ipv4 b: [UInt8]) -> Bool {
        guard b.count == 4 else { return false }
        return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168)
            || b[0] == 127 || (b[0] == 169 && b[1] == 254)
    }

    /// Loopback, unique local (fc00::/7), link-local (fe80::/10), and an IPv4-mapped address whose IPv4 is local.
    static func isLocal(ipv6 b: [UInt8]) -> Bool {
        guard b.count == 16 else { return false }
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF {
            return isLocal(ipv4: Array(b[12..<16]))
        }
        if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return true }
        return (b[0] & 0xFE) == 0xFC || (b[0] == 0xFE && (b[1] & 0xC0) == 0x80)
    }

    /// `isLocal` on a textual address, for the tests and the log.
    static func isLocal(address: String) -> Bool {
        var v4 = in_addr()
        if inet_pton(AF_INET, address, &v4) == 1 {
            return isLocal(ipv4: withUnsafeBytes(of: &v4) { Array($0) })
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, address, &v6) == 1 {
            return isLocal(ipv6: withUnsafeBytes(of: &v6) { Array($0) })
        }
        return false
    }

    // MARK: Text

    /// Length in Unicode scalars, as the Rust server counts `chars()`; the limits are the same on both.
    static func length(_ s: String) -> Int { s.unicodeScalars.count }

    /// The first `max` Unicode scalars (the same cut as the Rust `clip`).
    static func clip(_ s: String, _ max: Int) -> String {
        length(s) <= max ? s : String(String.UnicodeScalarView(s.unicodeScalars.prefix(max)))
    }

    // MARK: JSON

    /// One JSON line without its newline. Keys sorted, so the same picture gives the same bytes.
    static func json(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func nowMs() -> UInt64 {
        UInt64(max(0, Date().timeIntervalSince1970 * 1000))
    }
}

// MARK: - What the phone sends

enum PhoneLinkIncoming: Equatable {
    case hello(token: String, version: Int?, device: String, caps: Set<String>)
    case ping
    case bye
    /// Chat (cap `chat`): the allowed models, a message, stop waiting for one, start over.
    case chatModels
    case chatSend(id: String, model: String, text: String)
    case chatCancel(id: String)
    case chatReset
    /// A well-formed message of a type this version ignores (unknown types are ignored, by contract).
    /// `decision`, `answer` and `getDiff` land here now: they answered the agents' permission
    /// requests, questions and diffs, which Notchy no longer shows.
    case other(type: String)

    /// nil when the line is not a JSON object (a protocol error: the connection closes).
    static func parse(_ line: Data) -> PhoneLinkIncoming? {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return nil }
        let type = object["type"] as? String ?? ""
        switch type {
        case "hello":
            let caps = (object["caps"] as? [Any])?.compactMap { $0 as? String } ?? []
            return .hello(token: object["token"] as? String ?? "", version: Self.int(object["v"]),
                          device: object["device"] as? String ?? "", caps: Set(caps))
        case "ping": return .ping
        case "bye": return .bye
        case "chatModels": return .chatModels
        case "chatSend":
            guard let id = object["id"] as? String, PhoneLinkProtocol.isChatId(id) else { return .other(type: type) }
            return .chatSend(id: id, model: object["model"] as? String ?? "", text: object["text"] as? String ?? "")
        case "chatCancel":
            guard let id = object["id"] as? String, PhoneLinkProtocol.isChatId(id) else { return .other(type: type) }
            return .chatCancel(id: id)
        case "chatReset": return .chatReset
        default:
            return .other(type: type)
        }
    }

    private static func int(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }
}

// MARK: - Line framing

/// Newline-delimited lines, none longer than `PhoneLinkProtocol.maxLine`. Bytes are fed as they
/// arrive; complete lines come out. A `\r` before the newline is dropped, empty lines are skipped.
struct PhoneLinkLineReader {
    private var buffer = Data()

    /// The complete lines in what has arrived so far, or nil when a line is over the limit
    /// (the caller closes the connection; nothing more should be fed).
    mutating func feed(_ data: Data) -> [Data]? {
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if line.last == 0x0D { line.removeLast() }
            if line.count > PhoneLinkProtocol.maxLine { return nil }
            if !line.isEmpty { lines.append(line) }
        }
        // No newline within the limit: too long, however much more is sent.
        if buffer.count > PhoneLinkProtocol.maxLine { return nil }
        return lines
    }
}
