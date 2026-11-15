//
//  AtoTokenStore.swift
//  Notchy
//
//  Keychain storage for the Ato (Actuar) credentials and session.
//

import CryptoKit
import Foundation
import Security

/// The Ato credentials, kept in the Keychain rather than in `Defaults`.
///
/// Same shape as ``MattermostTokenStore``, with one difference worth having:
/// the password itself is never stored. Actuar's sign-in does not take the
/// password, it takes `md5(lowercased email + password)` — computed in the
/// browser before anything is sent — so that digest is all a fresh sign-in
/// needs, and it is all that is kept.
///
/// The session is two strings: the bearer `Token`, good for two hours, and the
/// `TokenId` that `/Auth/Refresh` trades for the next one. Refreshing is what
/// keeps this working through a day without signing in from the digest again.
final class AtoTokenStore: @unchecked Sendable {
    static let shared = AtoTokenStore()

    private static let service = "com.cauarati.Notchy.Ato"

    private enum Account {
        static let email = "email"
        static let passwordDigest = "passwordDigest"
        static let token = "token"
        static let tokenID = "tokenId"
    }

    private let lock = NSLock()
    private var cachedEmail: String?
    private var cachedDigest: String?
    private var cachedToken: String?
    private var cachedTokenID: String?

    private init() {
        cachedEmail = Self.read(account: Account.email)
        cachedDigest = Self.read(account: Account.passwordDigest)
        cachedToken = Self.read(account: Account.token)
        cachedTokenID = Self.read(account: Account.tokenID)
    }

    // MARK: - Credentials

    var email: String {
        lock.lock(); defer { lock.unlock() }
        return cachedEmail ?? ""
    }

    /// What `/Auth/Login` takes as `Password`.
    var passwordDigest: String {
        lock.lock(); defer { lock.unlock() }
        return cachedDigest ?? ""
    }

    var hasCredentials: Bool {
        !email.isEmpty && !passwordDigest.isEmpty
    }

    /// Stores the email and the digest of the password; the password is
    /// dropped here.
    func setCredentials(email: String, password: String) {
        let normalized = Self.normalizedEmail(email)
        let digest = (normalized.isEmpty || password.isEmpty)
            ? "" : Self.passwordDigest(email: normalized, password: password)

        lock.lock()
        cachedEmail = normalized.isEmpty ? nil : normalized
        cachedDigest = digest.isEmpty ? nil : digest
        lock.unlock()

        Self.write(normalized, account: Account.email)
        Self.write(digest, account: Account.passwordDigest)
    }

    /// Lowercased and trimmed, as the panel sends it.
    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// `md5(email + password)`, hex, lowercase — the panel's `encryptMd5`.
    /// Not a security measure on our side, only the format the server expects.
    static func passwordDigest(email: String, password: String) -> String {
        let digest = Insecure.MD5.hash(data: Data((normalizedEmail(email) + password).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Session

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

    func clearSession() {
        setSession(token: "", tokenID: "")
    }

    func clear() {
        lock.lock()
        cachedEmail = nil
        cachedDigest = nil
        cachedToken = nil
        cachedTokenID = nil
        lock.unlock()

        for account in [Account.email, Account.passwordDigest, Account.token, Account.tokenID] {
            Self.delete(account: account)
        }
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
