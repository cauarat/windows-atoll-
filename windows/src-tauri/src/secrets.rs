// API keys live in the Windows Credential Manager or, on Linux, the Secret
// Service (GNOME Keyring, KWallet) — never on disk and never in the front end — the island can only ask whether a key is present.

use keyring::Entry;

const SERVICE: &str = "fr.louisraille.coucou";

/// Every key Coucou may store. Anything outside this list is refused.
///
/// The message keys are spelled by `messages`, not repeated here. A key the
/// settings window writes but this list does not name is refused by `entry()`
/// below and the save goes nowhere, with nothing shown to say so — which is
/// exactly what happened when these two lists were written separately.
pub const KNOWN_KEYS: &[&str] = &[
    "anthropic-api-key",
    "n8n-url",
    "n8n-api-key",
    "vercel-token",
    "github-token",
    "stripe-api-key",
    "resend-api-key",
    "notion-api-key",
    "calcom-api-key",
    crate::messages::MATTERMOST_URL_KEY,
    crate::messages::MATTERMOST_LOGIN_KEY,
    crate::messages::MATTERMOST_PASSWORD_KEY,
    crate::messages::MATTERMOST_TOKEN_KEY,
    crate::messages::ATO_EMAIL_KEY,
    crate::messages::ATO_PASSWORD_KEY,
    crate::messages::ATO_TOKEN_KEY,
    crate::messages::ATO_TOKEN_ID_KEY,
    crate::messages::AGENDA_TOKEN_KEY,
    crate::messages::AGENDA_TOKEN_ID_KEY,
    // Missing from this list from the day it was added, so `whatsapp.rs` could
    // never record a linked phone: `is_linked()` stayed false and the page
    // went blank a poll after the sign-in window hid.
    crate::messages::WHATSAPP_LINKED_KEY,
];

/// Deletes what ClickMassa left behind. Bypasses `KNOWN_KEYS` on purpose: these
/// may no longer be written, only removed. Idempotent, so it runs every start.
pub fn forget_retired() {
    for key in crate::messages::RETIRED_CLICKMASSA_KEYS {
        if let Ok(entry) = Entry::new(SERVICE, key) {
            let _ = entry.delete_credential();
        }
    }
}

fn entry(key: &str) -> Option<Entry> {
    if !KNOWN_KEYS.contains(&key) {
        return None;
    }
    Entry::new(SERVICE, key).ok()
}

pub fn get(key: &str) -> Option<String> {
    entry(key)?.get_password().ok().filter(|v| !v.is_empty())
}

pub fn set(key: &str, value: &str) -> Result<(), String> {
    let entry = entry(key).ok_or_else(|| format!("unknown key {key}"))?;
    if value.is_empty() {
        let _ = entry.delete_credential();
        return Ok(());
    }
    entry.set_password(value).map_err(|e| e.to_string())
}

pub fn clear(key: &str) -> Result<(), String> {
    let entry = entry(key).ok_or_else(|| format!("unknown key {key}"))?;
    match entry.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(e.to_string()),
    }
}

pub fn present(key: &str) -> bool {
    get(key).is_some()
}

// ── Entries only Rust reads and writes ───────────────────────────────────────
//
// The phone link's certificate, its key and the pairing token (phone_link/pairing.rs).
// Not in KNOWN_KEYS on purpose: the island has `secret_present` / `secret_set` /
// `secret_clear` for those, and none of the three may be reachable from a webview —
// whoever holds the token can pair.

/// Every entry of that kind. Anything outside this list is refused.
pub const INTERNAL_KEYS: &[&str] = &["phone-link-cert", "phone-link-key", "phone-link-token"];

/// Whether the keystore would accept this key through `get_internal` / `set_internal`.
pub fn is_internal(key: &str) -> bool {
    INTERNAL_KEYS.contains(&key)
}

fn internal_entry(key: &str) -> Result<Entry, String> {
    if !is_internal(key) {
        return Err(format!("unknown key {key}"));
    }
    Entry::new(SERVICE, key).map_err(|e| e.to_string())
}

pub fn get_internal(key: &str) -> Option<String> {
    internal_entry(key).ok()?.get_password().ok().filter(|v| !v.is_empty())
}

pub fn set_internal(key: &str, value: &str) -> Result<(), String> {
    let entry = internal_entry(key)?;
    if value.is_empty() {
        return match entry.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(e.to_string()),
        };
    }
    entry.set_password(value).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::{entry, KNOWN_KEYS, INTERNAL_KEYS};

    #[test]
    fn the_phone_links_secrets_cannot_be_reached_from_the_island() {
        // The island's commands go through `get`/`set`/`clear`/`present`, which
        // only know KNOWN_KEYS.
        for key in INTERNAL_KEYS {
            assert!(!KNOWN_KEYS.contains(key), "{key}");
            assert!(entry(key).is_none(), "{key}");
            assert!(super::set(key, "x").is_err(), "{key}");
            assert!(super::clear(key).is_err(), "{key}");
        }
    }

    /// Every key `messages.rs` spells is one this list lets through. Read off
    /// the source rather than listed again here, so a key added there and
    /// forgotten here fails at once instead of saving nowhere.
    #[test]
    fn every_key_messages_spells_is_known() {
        let source = include_str!("messages.rs");
        let mut seen = 0;
        for line in source.lines() {
            let line = line.trim();
            if !(line.starts_with("pub const ") && line.contains("_KEY: &str = \"")) {
                continue;
            }
            let key = line.split('"').nth(1).expect("a quoted key");
            assert!(
                KNOWN_KEYS.contains(&key),
                "{key} is written but not in KNOWN_KEYS"
            );
            seen += 1;
        }
        assert!(seen >= 11, "found only {seen} keys in messages.rs");
    }
}
