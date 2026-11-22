// Rust's corner of tests/fixtures/settings-defaults.json.
//
// The fixture writes down where a fresh install starts, once, for both
// platforms; tests/SettingsDefaultsTests.swift holds the Mac to it and
// tests/settings-defaults.ts holds DEFAULT_SETTINGS. This holds
// `Settings::default()`, which is what a new settings.json is written from and
// what every field missing from an old one falls back to, and the settings
// window's size. Declared from settings.rs, under #[cfg(test)].

use crate::settings::Settings;
use serde_json::{Map, Value};

const FIXTURE: &str = include_str!("../../../tests/fixtures/settings-defaults.json");

fn fixture() -> Value {
    serde_json::from_str(FIXTURE).expect("tests/fixtures/settings-defaults.json parses")
}

/// `Settings::default()` as settings.json spells it — the fixture's keys.
fn fresh_install() -> Map<String, Value> {
    match serde_json::to_value(Settings::default()).expect("Settings serialises") {
        Value::Object(fields) => fields,
        other => panic!("Settings serialised as {other}"),
    }
}

/// Numbers as numbers: Rust writes the f64 five as 5.0 where the fixture says
/// 5, and serde_json does not call those equal.
fn same(a: &Value, b: &Value) -> bool {
    match (a.as_f64(), b.as_f64()) {
        (Some(x), Some(y)) => x == y,
        _ => a == b,
    }
}

#[test]
fn a_fresh_install_starts_where_the_mac_does() {
    let fixture = fixture();
    let ours = fresh_install();
    let mut wrong = Vec::new();
    for (key, want) in fixture["defaults"]
        .as_object()
        .expect("the fixture has defaults")
    {
        match ours.get(key) {
            None => wrong.push(format!("{key}: not a Settings field")),
            Some(got) if !same(got, want) => {
                wrong.push(format!("{key}: {got} here, {want} on the Mac"))
            }
            Some(_) => {}
        }
    }
    assert!(
        wrong.is_empty(),
        "Settings::default() disagrees with tests/fixtures/settings-defaults.json:\n  {}",
        wrong.join("\n  ")
    );
}

#[test]
fn where_windows_differs_it_differs_on_purpose() {
    let fixture = fixture();
    let ours = fresh_install();
    let mut wrong = Vec::new();
    for (key, forced) in fixture["platformForced"]
        .as_object()
        .expect("the fixture has platformForced")
    {
        let want = &forced["windows"];
        match ours.get(key) {
            None => wrong.push(format!("{key}: not a Settings field")),
            Some(got) if !same(got, want) => {
                wrong.push(format!("{key}: {got} here, {want} wanted on Windows"))
            }
            Some(_) => {}
        }
    }
    assert!(
        wrong.is_empty(),
        "platformForced:\n  {}",
        wrong.join("\n  ")
    );
}

#[test]
fn the_settings_window_is_the_size_of_the_macs() {
    let fixture = fixture();
    let window = &fixture["settingsWindow"];
    let size = |key: &str| {
        window[key]
            .as_f64()
            .unwrap_or_else(|| panic!("settingsWindow.{key}"))
    };
    assert_eq!(crate::SETTINGS_W, size("width"), "width");
    assert_eq!(crate::SETTINGS_H, size("height"), "height");
    assert_eq!(crate::SETTINGS_MIN_W, size("minWidth"), "minWidth");
    assert_eq!(crate::SETTINGS_MIN_H, size("minHeight"), "minHeight");
}
