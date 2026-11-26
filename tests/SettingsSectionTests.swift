import Foundation

/// The Settings sidebar's table, on its own.
///
/// `--dump` writes it as tab-separated rows for tests/settings-sections-parity.ts,
/// which holds windows/src/settings/sections.ts to it: same ids in the same
/// order, the same English titles, SF Symbols and tile colours.
@main
enum SettingsSectionTests {

    static var failures = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { print("  ✓ \(label)") }
        else {
            print("  ✗ \(label)\(detail.isEmpty ? "" : " — \(detail)")")
            failures += 1
        }
    }

    static func dump() {
        for s in SettingsSection.all {
            print(["section", s.id, s.title, s.symbol, s.color, s.hiddenInAppStore ? "1" : "0"]
                .joined(separator: "\t"))
        }
        print(["default", SettingsSection.defaultID].joined(separator: "\t"))
    }

    static func main() {
        if CommandLine.arguments.contains("--dump") { dump(); return }

        let all = SettingsSection.all
        let ids = all.map(\.id)

        print("SettingsSection — the table")

        check("ten rows, as the Mac sidebar has", all.count == 10, "\(all.count)")
        check("every id is used once", Set(ids).count == ids.count, ids.joined(separator: ","))
        check("no blank id, title or symbol",
              all.allSatisfy { !$0.id.isEmpty && !$0.title.isEmpty && !$0.symbol.isEmpty })
        // Lower case and nothing else: the id is what `settingsSection` stores
        // and what a deep link names, on both platforms.
        check("ids are plain lower-case words",
              ids.allSatisfy { $0.range(of: "^[a-z]+$", options: .regularExpression) != nil },
              ids.joined(separator: ","))
        let badColours = all.filter {
            $0.color.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) == nil
        }
        check("every tile colour is #RRGGBB", badColours.isEmpty,
              badColours.map(\.color).joined(separator: ","))

        print("SettingsSection — what opens, and what the App Store build leaves out")

        check("Settings opens on General", SettingsSection.defaultID == "general")
        check("the default is a row every build shows",
              SettingsSection.named(SettingsSection.defaultID).map { !$0.hiddenInAppStore } ?? false)
        check("only AI Agents is left out of the App Store build",
              all.filter(\.hiddenInAppStore).map(\.id) == ["aiagents"],
              all.filter(\.hiddenInAppStore).map(\.id).joined(separator: ","))
        // The deep links: the ring's gear and the radial open "island", the
        // island's integration links "integrations", the hydration card
        // "hydration". A renamed row would open General instead, silently.
        for id in ["island", "integrations", "hydration"] {
            check("a deep link to \(id) finds its row", SettingsSection.named(id) != nil)
        }
        // AppState migrates the removed Agents tab's id to General on launch.
        check("the removed Agents tab is not a row again", SettingsSection.named("agents") == nil)
        check("an unknown id finds nothing", SettingsSection.named("nope") == nil)

        print("")
        if failures == 0 { print("All settings section tests passed.") }
        else { print("\(failures) failure(s)."); exit(1) }
    }
}
