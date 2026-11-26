import CoreGraphics
import SwiftUI

// MARK: - What the Mac's Mochi files expect from the Mac app
//
// The iPhone compiles Mochi from the Mac's own sources (BotEngine, MochiShape, MochiCharacter…), so
// the character on the phone is the character on the island, line for line. Those files lean on a
// few things the Mac app defines elsewhere, in files that are all AppKit. This is the iOS side of
// each, kept to exactly what the Mochi files call.

extension CGColor {
    // macOS has these as class properties; iOS does not.
    static var white: CGColor { CGColor(gray: 1, alpha: 1) }
    static var black: CGColor { CGColor(gray: 0, alpha: 1) }
    static var clear: CGColor { CGColor(gray: 0, alpha: 0) }
}

extension Color {
    /// The island's `Color(hex:)` (IslandRootView.swift).
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let val = UInt64(h, radix: 16) ?? 0
        let r = Double((val >> 16) & 0xFF) / 255
        let g = Double((val >> 8)  & 0xFF) / 255
        let b = Double( val        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension Notification.Name {
    /// Posted by the engine when Mochi has been poked too often; the island listens, the phone does not need to.
    static let botDizzy = Notification.Name("notchy.phone.botDizzy")
}
