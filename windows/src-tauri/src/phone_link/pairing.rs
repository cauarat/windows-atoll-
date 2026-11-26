// The phone link's identity: a TLS certificate made once, and the pairing token.
//
// Both live in the OS keystore (Credential Manager, Secret Service), never in a
// file and never in settings.json. If the keystore is not there the link simply
// does not start — there is no fallback to disk.
//
// The certificate is self-signed and has no name: the phone does not check a
// host name or an authority, it accepts exactly the certificate whose SHA-256 it
// was given in the pairing link (certificate pinning). So it only has to be
// generated once and kept; if it is lost, phones pair again.
//
// ECDSA P-256 on the named curve prime256v1, as rcgen writes it: Android's TLS
// refuses a certificate that spells the curve out as explicit parameters
// (`a_certificate_on_a_named_curve_is_what_android_accepts` below holds it to that).

use ring::digest;
use ring::rand::{SecureRandom, SystemRandom};

use super::hub::hex;

pub(super) const CERT_KEY: &str = "phone-link-cert";
pub(super) const PRIVATE_KEY: &str = "phone-link-key";
pub(super) const TOKEN_KEY: &str = "phone-link-token";

/// Where the secrets are kept. The app's implementation is the OS keystore
/// (secrets.rs); tests use memory.
pub trait SecretStore: Send + Sync {
    fn get(&self, key: &str) -> Option<String>;
    fn set(&self, key: &str, value: &str) -> Result<(), String>;
}

/// The certificate and its key, as the TLS server needs them.
#[derive(Clone)]
pub struct Identity {
    pub cert_der: Vec<u8>,
    pub key_der: Vec<u8>,
    /// Lowercase hex SHA-256 of the certificate: the `fp` of the pairing link.
    pub fingerprint: String,
}

/// The certificate already made, else a new one — stored before it is used.
pub fn load_or_create_identity(store: &dyn SecretStore) -> Result<Identity, String> {
    if let (Some(cert), Some(key)) = (store.get(CERT_KEY), store.get(PRIVATE_KEY)) {
        if let (Some(cert_der), Some(key_der)) = (unhex(&cert), unhex(&key)) {
            // A key that no longer parses means a damaged entry: start over.
            if rcgen::KeyPair::try_from(key_der.as_slice()).is_ok() {
                let fingerprint = hex(digest::digest(&digest::SHA256, &cert_der).as_ref());
                return Ok(Identity { cert_der, key_der, fingerprint });
            }
        }
    }
    let key_pair = rcgen::KeyPair::generate_for(&rcgen::PKCS_ECDSA_P256_SHA256).map_err(|e| e.to_string())?;
    let mut params = rcgen::CertificateParams::new(Vec::<String>::new()).map_err(|e| e.to_string())?;
    // The Mac's common name (PhoneLinkKeychain.swift); the phone reads nothing in it.
    params.distinguished_name.push(rcgen::DnType::CommonName, "Notchy phone link");
    params.not_before = rcgen::date_time_ymd(2024, 1, 1);
    params.not_after = rcgen::date_time_ymd(2124, 1, 1);
    let cert = params.self_signed(&key_pair).map_err(|e| e.to_string())?;
    let cert_der = cert.der().to_vec();
    let key_der = key_pair.serialize_der();
    // Key first: a certificate without its key is useless, the reverse is harmless.
    store.set(PRIVATE_KEY, &hex(&key_der))?;
    store.set(CERT_KEY, &hex(&cert_der))?;
    let fingerprint = hex(digest::digest(&digest::SHA256, &cert_der).as_ref());
    Ok(Identity { cert_der, key_der, fingerprint })
}

/// The pairing token: the stored one, else a new one.
pub fn token(store: &dyn SecretStore) -> Result<String, String> {
    if let Some(t) = store.get(TOKEN_KEY).filter(|t| is_token(t)) {
        return Ok(t);
    }
    new_token(store)
}

/// A fresh token. Whatever phone held the old one is locked out.
pub fn new_token(store: &dyn SecretStore) -> Result<String, String> {
    let token = random_token()?;
    store.set(TOKEN_KEY, &token)?;
    Ok(token)
}

/// 16 to 128 characters of `[A-Za-z0-9_-]` (docs/PHONE_LINK.md).
pub fn is_token(s: &str) -> bool {
    (16..=128).contains(&s.len()) && s.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

fn random_token() -> Result<String, String> {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut bytes = [0u8; 32];
    SystemRandom::new().fill(&mut bytes).map_err(|_| "no secure random source".to_string())?;
    // 64 symbols, so a byte's low six bits are uniform: 32 symbols = 192 bits.
    Ok(bytes.iter().map(|b| ALPHABET[(b & 63) as usize] as char).collect())
}

/// `notchy://pair?v=1&host=…&port=…&fp=…&token=…&name=…` — byte for byte the Mac's
/// `PhoneLinkProtocol.pairingLink`.
pub fn pairing_link(host: &str, port: u16, fingerprint: &str, token: &str, name: &str) -> String {
    format!(
        "notchy://pair?v=1&host={}&port={port}&fp={fingerprint}&token={token}&name={}",
        percent_encode(host),
        percent_encode(name)
    )
}

/// RFC 3986 unreserved characters and `:` stay; everything else is `%XX`.
fn percent_encode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~' | b':') {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// The link as a QR code, an SVG the settings window shows: black on white,
/// error correction M, whole modules no larger than 180 px across — the Mac's
/// `PhoneLinkQR`. The quiet zone is the 12 px white margin the window draws
/// around it, as the Mac composites one.
pub fn qr_svg(link: &str) -> Option<String> {
    let code = qrcode::QrCode::with_error_correction_level(link.as_bytes(), qrcode::EcLevel::M).ok()?;
    Some(
        code.render::<qrcode::render::svg::Color>()
            // First: the size is worked out from the modules, quiet zone included if it is still on.
            .quiet_zone(false)
            .max_dimensions(180, 180)
            .dark_color(qrcode::render::svg::Color("#000000"))
            .light_color(qrcode::render::svg::Color("#ffffff"))
            .build(),
    )
}

fn unhex(s: &str) -> Option<Vec<u8>> {
    if s.len() % 2 == 1 || s.is_empty() || !s.is_ascii() {
        return None;
    }
    (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).ok()).collect()
}

/// This computer's address on the local network: the one the OS would use to
/// reach the outside. Connecting a UDP socket sends nothing; it only makes the
/// OS pick the interface.
pub fn lan_address() -> Option<std::net::IpAddr> {
    let socket = std::net::UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("192.0.2.1:9").ok()?;
    let ip = socket.local_addr().ok()?.ip();
    (!ip.is_unspecified() && !ip.is_loopback()).then_some(ip)
}

/// The name the phone shows for this computer, at most 48 characters.
pub fn computer_name() -> String {
    let name = std::env::var("COMPUTERNAME")
        .or_else(|_| std::env::var("HOSTNAME"))
        .ok()
        .filter(|n| !n.trim().is_empty())
        .or_else(|| std::fs::read_to_string("/etc/hostname").ok().map(|n| n.trim().to_string()))
        .filter(|n| !n.is_empty())
        .unwrap_or_else(|| "Notchy".to_string());
    name.chars().take(48).collect()
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::Mutex;

    #[derive(Default)]
    pub struct MemStore(pub Mutex<HashMap<String, String>>);
    impl SecretStore for MemStore {
        fn get(&self, key: &str) -> Option<String> {
            self.0.lock().unwrap().get(key).cloned()
        }
        fn set(&self, key: &str, value: &str) -> Result<(), String> {
            self.0.lock().unwrap().insert(key.into(), value.into());
            Ok(())
        }
    }

    /// A store that accepts only what the real keystore accepts (`secrets::INTERNAL_KEYS`), and can be told to refuse every write.
    #[derive(Default)]
    pub struct StrictStore {
        pub inner: MemStore,
        pub refuse_writes: std::sync::atomic::AtomicBool,
    }
    impl SecretStore for StrictStore {
        fn get(&self, key: &str) -> Option<String> {
            if !crate::secrets::is_internal(key) {
                return None;
            }
            self.inner.get(key)
        }
        fn set(&self, key: &str, value: &str) -> Result<(), String> {
            if !crate::secrets::is_internal(key) {
                return Err(format!("unknown key {key}"));
            }
            if self.refuse_writes.load(std::sync::atomic::Ordering::SeqCst) {
                return Err("the keystore is locked".into());
            }
            self.inner.set(key, value)
        }
    }

    #[test]
    fn the_certificate_is_made_once_and_then_kept() {
        let store = MemStore::default();
        let first = load_or_create_identity(&store).unwrap();
        let again = load_or_create_identity(&store).unwrap();
        assert_eq!(first.cert_der, again.cert_der);
        assert_eq!(first.fingerprint, again.fingerprint);
        assert_eq!(first.fingerprint.len(), 64);
        // It is the SHA-256 of the DER, which is what the phone pins.
        assert_eq!(first.fingerprint, hex(digest::digest(&digest::SHA256, &first.cert_der).as_ref()));
    }

    /// The SubjectPublicKeyInfo's algorithm: id-ecPublicKey with the curve NAMED (prime256v1). A certificate that spells
    /// the curve out as explicit parameters is refused by Android's TLS, so the phone could never connect.
    #[test]
    fn a_certificate_on_a_named_curve_is_what_android_accepts() {
        let id = load_or_create_identity(&MemStore::default()).unwrap();
        // SEQUENCE { OID 1.2.840.10045.2.1 (id-ecPublicKey), OID 1.2.840.10045.3.1.7 (prime256v1) }
        let named: [u8; 21] = [
            0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03,
            0x01, 0x07,
        ];
        assert!(id.cert_der.windows(named.len()).any(|w| w == named), "the public key names the curve");
        // id-ecPublicKey followed by a SEQUENCE (explicit ECParameters) instead of the curve's OID is what Android refuses.
        let explicit = [0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x30];
        assert!(!id.cert_der.windows(explicit.len()).any(|w| w == explicit), "no explicit curve parameters");
        // Signed with ECDSA-SHA256 (OID 1.2.840.10045.4.3.2), which every phone's TLS verifies.
        let ecdsa_sha256 = [0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02];
        assert!(id.cert_der.windows(ecdsa_sha256.len()).any(|w| w == ecdsa_sha256));
    }

    #[test]
    fn a_damaged_key_means_a_new_identity_not_a_crash() {
        let store = MemStore::default();
        let first = load_or_create_identity(&store).unwrap();
        store.set(PRIVATE_KEY, "zz-not-hex").unwrap();
        let next = load_or_create_identity(&store).unwrap();
        assert_ne!(first.fingerprint, next.fingerprint);
        // And the new one is what is kept from now on.
        assert_eq!(load_or_create_identity(&store).unwrap().fingerprint, next.fingerprint);
    }

    #[test]
    fn nothing_secret_is_written_anywhere_but_the_store() {
        let store = MemStore::default();
        let id = load_or_create_identity(&store).unwrap();
        let t = token(&store).unwrap();
        let kept = store.0.lock().unwrap();
        assert_eq!(kept.get(PRIVATE_KEY).unwrap(), &hex(&id.key_der));
        assert_eq!(kept.get(TOKEN_KEY).unwrap(), &t);
    }

    #[test]
    fn tokens_are_valid_random_and_replaced_on_demand() {
        let store = MemStore::default();
        let a = token(&store).unwrap();
        assert!(is_token(&a), "{a}");
        assert_eq!(a.len(), 32);
        assert_eq!(token(&store).unwrap(), a, "the token is kept");
        let b = new_token(&store).unwrap();
        assert!(is_token(&b));
        assert_ne!(a, b);
        assert_eq!(token(&store).unwrap(), b);
        // A damaged stored token is replaced rather than used.
        store.set(TOKEN_KEY, "short").unwrap();
        assert!(is_token(&token(&store).unwrap()));
    }

    #[test]
    fn the_token_alphabet_matches_the_protocol() {
        assert!(is_token(&"a".repeat(16)));
        assert!(is_token(&"A-_9".repeat(32)));
        assert!(!is_token(&"a".repeat(15)));
        assert!(!is_token(&"a".repeat(129)));
        assert!(!is_token("aaaaaaaaaaaaaaa!"));
        assert!(!is_token("aaaaaaaaaaaaaaa "));
        assert!(!is_token(""));
    }

    /// The Mac's vector (tests/PhoneLinkTests.swift): both computers write the same link for the same pairing.
    #[test]
    fn the_link_has_every_field_and_encodes_the_name() {
        let link = pairing_link("192.168.1.20", 47830, &"ab".repeat(32), "tok_en-1234567890abcd", "Léa's PC & co");
        assert_eq!(
            link,
            format!(
                "notchy://pair?v=1&host=192.168.1.20&port=47830&fp={}&token=tok_en-1234567890abcd&name=L%C3%A9a%27s%20PC%20%26%20co",
                "ab".repeat(32)
            )
        );
        assert_eq!(super::super::DEFAULT_PORT, 47830, "the port the Mac offers too");
    }

    #[test]
    fn the_longest_realistic_link_still_fits_what_the_phone_accepts_and_a_qr_code() {
        // 48 accented characters in the name (9 characters each once percent-encoded) and an IPv6 host.
        let link = pairing_link("2001:db8:aaaa:bbbb:cccc:dddd:eeee:ffff", 47830, &"ab".repeat(32), &"t".repeat(128), &"é".repeat(48));
        assert!(link.len() < 2048, "the phone refuses a link of 2,048 characters or more: {}", link.len());
        assert!(qr_svg(&link).is_some(), "and the QR code can hold it");
        // The ordinary case is far shorter, so the code stays easy to scan.
        let usual = pairing_link("192.168.1.20", 47830, &"ab".repeat(32), &"t".repeat(32), "My PC");
        assert!(usual.len() < 250, "{}", usual.len());
    }

    #[test]
    fn the_qr_is_an_svg_of_the_link() {
        let svg = qr_svg(&pairing_link("192.168.1.20", 47830, &"ab".repeat(32), &"t".repeat(32), "PC")).unwrap();
        assert!(svg.starts_with("<?xml") || svg.contains("<svg"));
        assert!(!svg.contains("script"));
        // The Mac's size: whole modules, as large as fits in 180 px (a usual link is 53 modules: 3 px each).
        let width: u32 = svg.split("width=\"").nth(1).and_then(|w| w.split('"').next()).and_then(|w| w.parse().ok()).unwrap();
        assert!(width <= 180 && width > 120, "{width}");
    }

    #[test]
    fn the_computer_has_a_short_name_for_the_phone() {
        let name = computer_name();
        assert!(!name.is_empty() && name.chars().count() <= 48, "{name:?}");
    }
}
