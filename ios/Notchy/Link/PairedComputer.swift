import Foundation
import Security

// MARK: - The computer this phone is paired with
//
// Everything the pairing link said: where the computer was, the SHA-256 of its certificate (the only
// certificate this phone will ever accept from it) and the token, which is the shared secret. Kept in
// the Keychain, this device only, never in a file or in UserDefaults, and never synced.

struct PairedComputer: Codable, Equatable, Sendable {
    var host: String
    var port: UInt16
    /// Lowercase hex SHA-256 of the computer's certificate (64 characters).
    var fingerprint: String
    var token: String
    var name: String
}

enum PairingLink {
    /// `notchy://pair?v=1&host=…&port=…&fp=…&token=…&name=…`, or nil when it is not one this app can use:
    /// another version, a malformed field, or an address that is not on a local network.
    static func parse(_ text: String) -> PairedComputer? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed), comps.scheme?.lowercased() == "notchy",
              comps.host?.lowercased() == "pair" else { return nil }
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] where q[item.name] == nil { q[item.name] = item.value ?? "" }
        guard q["v"] == "1",
              let host = q["host"], !host.isEmpty, PhoneLinkProtocol.isLocal(address: host),
              let portText = q["port"], let port = UInt16(portText), port > 0,
              let fp = q["fp"]?.lowercased(), fp.utf8.count == 64,
              fp.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) }),
              let token = q["token"], PhoneLinkProtocol.isToken(token) else { return nil }
        let rawName = (q["name"] ?? "").unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let name = String(String(String.UnicodeScalarView(rawName)).prefix(48)).trimmingCharacters(in: .whitespaces)
        return PairedComputer(host: host, port: port, fingerprint: fp, token: token, name: name.isEmpty ? host : name)
    }
}

enum PairingStore {
    private static let service = "com.cauarati.NotchyPhone"
    private static let account = "paired-computer"

    static func load() -> PairedComputer? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(PairedComputer.self, from: data)
    }

    @discardableResult
    static func save(_ computer: PairedComputer) -> Bool {
        guard let data = try? JSONEncoder().encode(computer) else { return false }
        clear()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Readable once the phone has been unlocked after a restart; this device only, never synced.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
        ]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
