import Foundation

/// One row of the Settings sidebar: the id `settingsSection` stores, the title,
/// the SF Symbol on its tile and the tile's colour.
///
/// Plain data in a file of its own, so that scripts/test-settings-sections.sh
/// can compile it alone and hold windows/src/settings/sections.ts to it row for
/// row. The Windows sidebar is this same table, and a row added, moved or
/// recoloured on one side only is a failing build there, rather than a window
/// that looks almost right.
///
/// The title stays in English: it is the catalogue key, translated where the
/// row is drawn (`SettingsSidebarRow`), and scripts/test-i18n.sh fails if this
/// file starts translating in place.
struct SettingsSection: Equatable, Sendable {
    /// What `settingsSection` stores and the deep links name (the ring's gear
    /// opens "island", the hydration card "hydration"). Stable: a renamed id is
    /// a Settings window that opens on nothing for whoever was last on it.
    let id: String
    /// English — the catalogue key.
    let title: String
    /// The SF Symbol drawn white on the tile.
    let symbol: String
    /// The tile's colour, `#RRGGBB`.
    let color: String
    /// Left out of the App Store build, which has no AI Agents panel. The row
    /// stays in the table so the Windows twin can still be held to it; the
    /// sidebar decides with `#if APPSTORE` where it is drawn.
    let hiddenInAppStore: Bool

    init(_ id: String, _ title: String, symbol: String, color: String,
         hiddenInAppStore: Bool = false) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.color = color
        self.hiddenInAppStore = hiddenInAppStore
    }

    /// In sidebar order.
    static let all: [SettingsSection] = [
        SettingsSection("general",      "General",        symbol: "gearshape.fill",                    color: "#8E939C"),
        SettingsSection("activepills",  "Active pills",   symbol: "square.grid.2x2.fill",              color: "#F5A524"),
        SettingsSection("island",       "Dynamic Island", symbol: "capsule.fill",                      color: "#EC4899"),
        SettingsSection("radial",       "Radial menu",    symbol: "circle.grid.cross.fill",            color: "#F472B6"),
        SettingsSection("aiagents",     "AI Agents",      symbol: "sparkles",                          color: "#E07950",
                        hiddenInAppStore: true),
        SettingsSection("chat",         "Chat",           symbol: "bubble.left.and.bubble.right.fill", color: "#E07950"),
        SettingsSection("integrations", "Integrations",   symbol: "puzzlepiece.extension.fill",        color: "#7C5CFF"),
        SettingsSection("characters",   "Characters",     symbol: "face.smiling.inverse",              color: "#2DD4BF"),
        SettingsSection("hydration",    "Hydration",      symbol: "drop.fill",                         color: "#22D3EE"),
    ]

    /// Where Settings opens when nothing else was asked for.
    static let defaultID = "general"

    /// The row `id` names, if there is one.
    static func named(_ id: String) -> SettingsSection? {
        all.first { $0.id == id }
    }
}
