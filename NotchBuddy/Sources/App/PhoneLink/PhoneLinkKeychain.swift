import CryptoKit
import Foundation
import Security

// MARK: Keychain

/// The Mac's Keychain, through the app's own `Keychain` helper (generic passwords, this device only,
/// never synced).
final class PhoneLinkKeychainStore: PhoneLinkSecretStore {
    func get(_ key: String) -> String? { Keychain.load(key: key) }

    func set(_ key: String, _ value: String) -> Bool {
        Keychain.save(key: key, value: value)
        return Keychain.load(key: key) == value
    }
}

/// The Mac's TLS identity, as Network.framework needs it: a `SecIdentity`, which on macOS means a private
/// key in a keychain and the certificate that goes with it.
///
/// Coucou imports a raw key into the Keychain at each start. That needs the keychain-access entitlement a
/// team-signed app has, and Notchy is ad-hoc signed: the import fails with errSecMissingEntitlement and the
/// link could never start. So the key is generated *inside* the login keychain instead
/// (`SecKeyCreateRandomKey`, permanent, file-based keychain), which needs no entitlement, and it never
/// leaves it: the certificate is signed by the Keychain, and nothing of the key is ever read back out.
/// The certificate (public) is kept in the secret store so its fingerprint, which phones pin, stays the same.
struct PhoneLinkMacIdentity {
    let certificateDER: Data
    let fingerprint: String
    let secIdentity: SecIdentity

    static let tag = Data("com.cauarati.Notchy.phonelink".utf8)
    static let label = "Notchy phone link"

    /// The identity already made, else a new one. nil when the Keychain refuses.
    /// `tag` names the key; tests and tools pass their own so they never touch the app's.
    static func loadOrCreate(store: PhoneLinkSecretStore, tag: Data = Self.tag) -> PhoneLinkMacIdentity? {
        guard let key = existingKey(tag) ?? newKey(tag),
              let publicKey = SecKeyCopyPublicKey(key),
              let publicData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { return nil }
        // The stored certificate, if it is the one for this key; otherwise a new one (phones pair again).
        var der: Data?
        if let hex = store.get(PhoneLinkIdentity.certKey), let stored = PhoneLinkIdentity.unhex(hex),
           let cert = SecCertificateCreateWithData(nil, stored as CFData),
           let certKey = SecCertificateCopyKey(cert), let certData = SecKeyCopyExternalRepresentation(certKey, nil) as Data?,
           certData == publicData {
            der = stored
        }
        if der == nil {
            guard let made = PhoneLinkDER.selfSignedCertificate(
                publicKey: Array(publicData), commonName: label, serial: PhoneLinkDER.randomSerial(), sign: { tbs in
                    (SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, Data(tbs) as CFData, nil) as Data?).map(Array.init)
                }) else { return nil }
            guard store.set(PhoneLinkIdentity.certKey, PhoneLinkProtocol.hex(made)) else { return nil }
            der = Data(made)
        }
        guard let der, let cert = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
        guard let identity = identity(for: cert) else { return nil }
        return PhoneLinkMacIdentity(certificateDER: der, fingerprint: PhoneLinkProtocol.sha256Hex(der), secIdentity: identity)
    }

    /// Forgets the key (and so the certificate): the next start makes a new identity, and every phone pairs again.
    static func reset(store: PhoneLinkSecretStore, tag: Data = Self.tag) {
        let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: tag,
                                    kSecUseDataProtectionKeychain as String: false]
        SecItemDelete(query as CFDictionary)
        _ = store.set(PhoneLinkIdentity.certKey, "")
    }

    private static func existingKey(_ tag: Data) -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecUseDataProtectionKeychain as String: false,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let item,
              CFGetTypeID(item) == SecKeyGetTypeID() else { return nil }
        return (item as! SecKey)
    }

    private static func newKey(_ tag: Data) -> SecKey? {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: tag,
            kSecAttrLabel as String: label,
            kSecUseDataProtectionKeychain as String: false,
        ]
        return SecKeyCreateRandomKey(attributes as CFDictionary, nil)
    }

    /// The certificate and its key in the keychain, as one identity. The certificate is added to the keychain
    /// beside the key when the system will not pair them otherwise (it is public; only the key is secret).
    private static func identity(for cert: SecCertificate) -> SecIdentity? {
        var found: SecIdentity?
        if SecIdentityCreateWithCertificate(nil, cert, &found) == errSecSuccess, let found { return found }
        let add: [String: Any] = [kSecClass as String: kSecClassCertificate, kSecValueRef as String: cert,
                                  kSecAttrLabel as String: label, kSecUseDataProtectionKeychain as String: false]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { return nil }
        if SecIdentityCreateWithCertificate(nil, cert, &found) == errSecSuccess, let found { return found }
        return nil
    }
}
