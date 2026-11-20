import Foundation

/// The Mac's corner of tests/fixtures/settings-defaults.json.
///
/// The fixture writes down where a fresh install starts and what the Settings
/// fields accept, once, for both platforms; this holds the Mac to it, and
/// tests/settings-defaults.ts and settings_defaults_test.rs hold Windows. The
/// Mac is the source of truth, so a number changed here fails until the
/// fixture says the same — and then Windows fails until it follows.
///
/// Run by scripts/test-settings-defaults.sh, with the fixture's path.
@main
enum SettingsDefaultsTests {

    /// A fixture value, compared by kind: JSON has one number type, and the
    /// Mac keeps the same number as a TimeInterval in one place and an Int in
    /// the next.
    enum Value: Equatable, CustomStringConvertible {
        case bool(Bool)
        case number(Double)
        case text(String)

        init?(json: Any) {
            if let n = json as? NSNumber {
                // JSONSerialization hands back true and false as NSNumbers;
                // only the CFBoolean ones are booleans.
                self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
            } else if let s = json as? String {
                self = .text(s)
            } else {
                return nil
            }
        }

        var description: String {
            switch self {
            case .bool(let b):   return "\(b)"
            case .number(let d): return d == d.rounded() ? String(Int(d)) : "\(d)"
            case .text(let s):   return "\"\(s)\""
            }
        }
    }

    /// Every key of the fixture's `defaults`, and what the Mac starts with.
    static let macDefaults: [String: Value] = [
        "soundEnabled":         .bool(SettingsDefaults.soundEnabled),
        "soundVolume":          .number(SettingsDefaults.soundVolume),
        "autoCloseInterval":    .number(SettingsDefaults.autoClose),
        "absenceInterval":      .number(SettingsDefaults.absence),
        "closeShortcutEnabled": .bool(SettingsDefaults.closeShortcutEnabled),
        "skipBackSeconds":      .number(Double(SettingsDefaults.skipSeconds)),
        "skipForwardSeconds":   .number(Double(SettingsDefaults.skipSeconds)),
        "islandSnow":           .bool(SettingsDefaults.islandSnow),
        "christmasMusic":       .bool(SettingsDefaults.christmasMusic),
        "homeContent":          .text(HomeContent.defaultChoice.rawValue),
    ]

    /// Fixture keys with no stored default on the Mac to compare, and why.
    static let notStoredOnTheMac: [String: String] = [
        // SettingsView reads SMAppService's own state, and a fresh install has
        // never registered: off, which is what the fixture says Windows does.
        "autostart": "Launch at Mac startup is SMAppService's state, and a new install is unregistered",
    ]

    /// Every key of the fixture's `ranges`, and what the Mac's field accepts.
    static let macRanges: [String: ClosedRange<Double>] = [
        "soundVolume":        SettingsDefaults.soundVolumeRange,
        "autoCloseInterval":  SettingsDefaults.autoCloseRange,
        "absenceInterval":    SettingsDefaults.absenceRange,
        "skipBackSeconds":    Double(SettingsDefaults.skipSecondsRange.lowerBound)...Double(SettingsDefaults.skipSecondsRange.upperBound),
        "skipForwardSeconds": Double(SettingsDefaults.skipSecondsRange.lowerBound)...Double(SettingsDefaults.skipSecondsRange.upperBound),
    ]

    /// The `mac` side of every key in the fixture's `platformForced`.
    static let macForced: [String: Value] = [
        "alwaysVisible": .bool(SettingsDefaults.alwaysVisible),
        "position":      .text(IslandAnchor.defaultPosition),
    ]

    static var failures = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { print("  ✓ \(label)") }
        else {
            print("  ✗ \(label)\(detail.isEmpty ? "" : " — \(detail)")")
            failures += 1
        }
    }

    static func main() {
        guard let path = CommandLine.arguments.dropFirst().first,
              let data = FileManager.default.contents(atPath: path),
              let fixture = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            print("usage: settings-defaults-tests <tests/fixtures/settings-defaults.json>")
            exit(2)
        }
        let defaults = fixture["defaults"] as? [String: Any] ?? [:]
        let ranges = fixture["ranges"] as? [String: Any] ?? [:]
        let window = fixture["settingsWindow"] as? [String: Any] ?? [:]
        let forced = fixture["platformForced"] as? [String: [String: Any]] ?? [:]

        print("Settings defaults — a fresh Mac install starts where the fixture says")

        for key in defaults.keys.sorted() {
            if let why = notStoredOnTheMac[key] {
                print("  – \(key): not checked here (\(why))")
                continue
            }
            guard let mac = macDefaults[key] else {
                check(key, false, "the fixture names it and this check does not know it")
                continue
            }
            let want = defaults[key].flatMap(Value.init(json:))
            check("\(key) is \(mac)", want == mac, "the fixture says \(want.map(String.init(describing:)) ?? "something unreadable")")
        }
        for key in macDefaults.keys.sorted() where defaults[key] == nil {
            check(key, false, "the Mac checks it and the fixture does not list it")
        }

        print("Settings defaults — the fields accept the same numbers")

        for key in ranges.keys.sorted() {
            guard let mac = macRanges[key] else {
                check(key, false, "the fixture names it and this check does not know it")
                continue
            }
            let bounds = (ranges[key] as? [Any] ?? []).compactMap(Value.init(json:))
            let ok = bounds == [.number(mac.lowerBound), .number(mac.upperBound)]
            check("\(key) takes \(Value.number(mac.lowerBound))…\(Value.number(mac.upperBound))", ok,
                  "the fixture says \(bounds.map(\.description).joined(separator: "…"))")
        }
        for key in macRanges.keys.sorted() where ranges[key] == nil {
            check(key, false, "the Mac checks its range and the fixture does not list it")
        }
        // Every default sits inside its own range, or a fresh install would be
        // clamped the first time anybody opened Settings.
        for key in macRanges.keys.sorted() {
            if case .number(let d) = macDefaults[key], let range = macRanges[key] {
                check("\(key)'s default is one the field accepts", range.contains(d), "\(d) is outside \(range)")
            }
        }

        print("Settings defaults — the window")

        let size = SettingsDefaults.settingsWindowSize
        let minimum = SettingsDefaults.settingsWindowMinSize
        let sizes: [(String, Double)] = [
            ("width", size.width), ("height", size.height),
            ("minWidth", minimum.width), ("minHeight", minimum.height),
        ]
        for (key, mac) in sizes {
            let want = window[key].flatMap(Value.init(json:))
            check("\(key) \(Value.number(mac))", want == .number(mac),
                  "the fixture says \(want.map(String.init(describing:)) ?? "nothing")")
        }
        check("the window opens no smaller than it may shrink to",
              size.width >= minimum.width && size.height >= minimum.height)

        print("Settings defaults — where Windows differs on purpose")

        for key in forced.keys.sorted() {
            let entry = forced[key] ?? [:]
            guard let mac = macForced[key] else {
                check(key, false, "the fixture names it and this check does not know it")
                continue
            }
            let want = entry["mac"].flatMap(Value.init(json:))
            check("\(key) is \(mac) on the Mac", want == mac,
                  "the fixture says \(want.map(String.init(describing:)) ?? "nothing")")
            let windows = entry["windows"].flatMap(Value.init(json:))
            check("\(key) really differs on Windows", windows != nil && windows != want,
                  "a value both sides share belongs under defaults")
            check("\(key) says why", !((entry["why"] as? String) ?? "").isEmpty)
            check("\(key) is not also a shared default", defaults[key] == nil)
        }
        for key in macForced.keys.sorted() where forced[key] == nil {
            check(key, false, "the Mac checks it and the fixture does not list it")
        }

        print("")
        if failures == 0 { print("All settings defaults tests passed.") }
        else { print("\(failures) failure(s)."); exit(1) }
    }
}
