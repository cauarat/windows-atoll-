//! Translating the strings Rust owns: the tray menu, and the errors the island
//! shows when a service will not answer.
//!
//! The table itself is generated into `i18n_generated.rs` from i18n/catalog.json
//! by scripts/generate-i18n.mjs, the same catalogue the Mac app and the frontend
//! read. Nothing here holds a translation.

use crate::i18n_generated;

/// Resolves the stored preference -- "system", "en", "es", "pt-BR" -- against
/// what the OS was asked for.
///
/// Portuguese from Portugal lands on the Brazilian strings rather than on
/// English: the two are close enough that the wrong Portuguese beats no
/// Portuguese. The same rule as `AppLanguage.resolved` on the Mac.
///
/// The environment is all this reads, which answers on Linux and usually not on
/// Windows. That is deliberate: a crate for one call is a dependency the Mac
/// half does not need, and the frontend knows the answer anyway -- it reports
/// `navigator.language` through `set_language`, which is what the tray is
/// rebuilt from. Until then "en" is shown, and every string is keyed by it.
pub fn resolve(preference: &str) -> String {
    if preference != "system" {
        return preference.to_string();
    }
    let tag = ["LC_ALL", "LC_MESSAGES", "LANG", "LANGUAGE"]
        .iter()
        .find_map(|k| std::env::var(k).ok())
        .unwrap_or_default()
        .to_lowercase();
    from_tag(&tag)
}

/// The language a BCP-47 tag resolves to, e.g. "pt-pt" -> "pt-BR".
pub fn from_tag(tag: &str) -> String {
    let tag = tag.to_lowercase();
    if tag.starts_with("pt") {
        "pt-BR".into()
    } else if tag.starts_with("es") {
        "es".into()
    } else {
        "en".into()
    }
}

/// The translation of `key`, or `key` itself.
///
/// English is what every string is keyed by, so a missing translation shows an
/// English sentence rather than an identifier.
pub fn t(lang: &str, key: &str) -> String {
    i18n_generated::lookup(lang, key).unwrap_or(key).to_string()
}

/// `t` with the first placeholder replaced, for the strings that carry a value.
///
/// `%@` and `%lld` are the spellings a Swift literal compiles to, and the
/// catalogue holds one key per sentence for all three platforms, so this reads
/// the same spelling rather than inventing its own.
pub fn t1(lang: &str, key: &str, value: &str) -> String {
    let text = t(lang, key);
    for ph in ["%@", "%lld", "%lf", "%u"] {
        if text.contains(ph) {
            return text.replacen(ph, value, 1);
        }
    }
    text
}

/// What the frontend said the system language resolves to.
///
/// `navigator.language` is the one answer that is right on both platforms, and
/// the webview is the only part of the app that can read it. It arrives through
/// the `set_language` command and is kept here for the tray, which is built in
/// Rust and cannot ask.
static REPORTED: std::sync::RwLock<Option<String>> = std::sync::RwLock::new(None);

pub fn reported() -> Option<String> {
    REPORTED.read().ok().and_then(|g| g.clone())
}

pub fn set_reported(language: Option<String>) {
    if let Ok(mut g) = REPORTED.write() {
        *g = language;
    }
}
