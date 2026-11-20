import Foundation

/// The defaults and limits the Settings window shares with the Windows and
/// Linux app, out of AppState so that a test can compile them on their own.
///
/// tests/fixtures/settings-defaults.json writes the same numbers down once, and
/// three checks hold a platform each to that file: this one
/// (scripts/test-settings-defaults.sh), `DEFAULT_SETTINGS` in
/// windows/src/core/state.ts, and `Settings::default()` in settings.rs. Change a
/// value here and the fixture fails until it changes too, and then Windows
/// fails until it follows. Without that, Windows quietly starts somewhere else.
///
/// Values only. What reads them, and when, is where it always was.
enum SettingsDefaults {
    // MARK: Sound

    static let soundEnabled = true
    static let soundVolume: Double = 0.12
    /// The Volume slider's range. Its top is also 100 % in the readout beside it.
    static let soundVolumeRange: ClosedRange<Double> = 0...0.2

    // MARK: Behavior

    /// Seconds a notification stays open ("Close after").
    static let autoClose: TimeInterval = 5
    /// What "Close after" accepts — `AppState.autoCloseRange` says why.
    static let autoCloseRange: ClosedRange<TimeInterval> = 2...120
    /// Seconds the compact island waits, with nothing happening, before it
    /// folds back into the notch ("Hide after").
    static let absence: TimeInterval = 3 * 60
    /// What "Hide after" accepts.
    static let absenceRange: ClosedRange<TimeInterval> = 5...3600
    /// "Never" — the island never folds away. Off on a Mac, where the fold is
    /// into a notch that is already black; Windows starts with it on, having no
    /// notch to fold into (the fixture lists it under "platformForced").
    static let alwaysVisible = false

    // MARK: Hotkey

    /// "Close island with shortcut". Off until asked for: a registered shortcut
    /// takes its keys away from every other app.
    static let closeShortcutEnabled = false

    // MARK: Now Playing

    /// How far each of the player's round buttons jumps, in seconds.
    static let skipSeconds = 10
    static let skipSecondsRange = 1...120

    // MARK: Christmas

    /// Snow on the island and Christmas music at start, in season. On: it is
    /// a season, and nobody should have to go looking for it.
    static let islandSnow = true
    static let christmasMusic = true

    // MARK: The Settings window

    static let settingsWindowSize = CGSize(width: 720, height: 560)
    static let settingsWindowMinSize = CGSize(width: 640, height: 420)
}
