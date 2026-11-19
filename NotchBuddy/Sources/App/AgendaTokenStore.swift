//
//  AgendaTokenStore.swift
//  Notchy
//
//  Keychain storage for the commercial panel's session.
//

import Foundation
import Security

/// The Agenda's own session with the commercial panel.
///
/// The credentials are not here: they are the Actuar account Ato already
/// keeps in ``AtoTokenStore`` — the panel signs in with the same e-mail and
/// the same password digest. Only the token pair is the Agenda's, because the
/// panel asks for it under its own `AppSource`, and two clients refreshing
/// from one `TokenId` would take turns invalidating each other.
final class AgendaTokenStore: @unchecked Sendable {
    static let shared = AgendaTokenStore()

    private static let service = "com.cauarati.Notchy.Agenda"

    private enum Account {
        static let token = "token"
        static let tokenID = "tokenId"
    }

    private let lock = NSLock()
    private var cachedToken: String?
    private var cachedTokenID: String?

    private init() {
        cachedToken = Self.read(account: Account.token)
        cachedTokenID = Self.read(account: Account.tokenID)
    }

    var token: String {
        lock.lock(); defer { lock.unlock() }
        return cachedToken ?? ""
    }

    var tokenID: String {
        lock.lock(); defer { lock.unlock() }
        return cachedTokenID ?? ""
    }

    func setSession(token: String, tokenID: String) {
        lock.lock()
        cachedToken = token.isEmpty ? nil : token
        cachedTokenID = tokenID.isEmpty ? nil : tokenID
        lock.unlock()

        Self.write(token, account: Account.token)
        Self.write(tokenID, account: Account.tokenID)
    }

    func clear() {
        setSession(token: "", tokenID: "")
    }

    // MARK: - Keychain

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    @discardableResult
    private static func write(_ value: String, account: String) -> OSStatus {
        guard !value.isEmpty else { return delete(account: account) }

        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]

        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return status }

        var attributes = baseQuery(account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    @discardableResult
    private static func delete(account: String) -> OSStatus {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }
}
