import AppKit
import CoreGraphics

/// Which displays Mochi is allowed on, and which one she is on right now.
///
/// The screen-picking rules are kept as free functions over plain values —
/// `DisplayInfo`, not `NSScreen` — so they can be tested with no display
/// attached, the same way `IslandScreenGeometry` is.
enum IslandDisplays {

    /// A display reduced to what the rules actually need.
    struct DisplayInfo: Equatable {
        /// Stable across reconnects and reboots; nil when macOS will not give one.
        let id: String?
        let frame: CGRect
    }

    // MARK: – Identity

    /// A key for this display that survives unplugging it.
    ///
    /// `NSScreenNumber` is a `CGDirectDisplayID`, which macOS hands out afresh
    /// on every reconnect and reboot — fine to act on now, useless to write
    /// down. The ColorSync UUID is the physical display, so that is what gets
    /// persisted.
    ///
    /// The `CFUUID` is turned into a `String` here and never stored: it is an
    /// unmanaged CoreFoundation object, which has no place in a preference or
    /// anywhere the strict-concurrency build has to reason about it.
    static func identifier(for screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    /// What to call this display in the settings window.
    static func localizedName(for screen: NSScreen) -> String {
        let name = screen.localizedName
        return name.isEmpty ? "Display" : name
    }

    static func info(for screen: NSScreen) -> DisplayInfo {
        DisplayInfo(id: identifier(for: screen), frame: screen.frame)
    }

    // MARK: – The rules

    /// The displays Mochi may appear on.
    ///
    /// An empty selection means every display — the same "empty = all"
    /// convention `vercelProjectFilter` and `n8nWorkflowFilter` use.
    ///
    /// A selection that matches nothing attached also means every display.
    /// Unplugging the one display somebody picked must not leave Mochi with
    /// nowhere to be: an app that silently vanishes reads as broken, and the
    /// preference is still on disk for when that display comes back.
    static func chosen(from displays: [DisplayInfo], selection: Set<String>) -> [DisplayInfo] {
        if selection.isEmpty { return displays }
        let picked = displays.filter { info in
            guard let id = info.id else { return false }
            return selection.contains(id)
        }
        return picked.isEmpty ? displays : picked
    }

    /// The display the interactive island belongs on: the one under the cursor
    /// when that is a display Mochi is allowed on, and otherwise the first
    /// allowed one, so there is always exactly one answer.
    static func active(in chosen: [DisplayInfo], cursor: CGPoint) -> DisplayInfo? {
        chosen.first { $0.frame.contains(cursor) } ?? chosen.first
    }

    // MARK: – NSScreen convenience

    /// `chosen(from:selection:)` over the attached screens, keeping the screens.
    ///
    /// Matched by position rather than by id, so a screen macOS gives no UUID
    /// for still comes through on the "everything" paths instead of silently
    /// dropping out.
    static func chosenScreens(_ screens: [NSScreen], selection: Set<String>) -> [NSScreen] {
        let infos = screens.map(info(for:))
        let keep = chosen(from: infos, selection: selection)
        return zip(screens, infos)
            .filter { _, info in keep.contains(info) }
            .map { screen, _ in screen }
    }

    /// The screen the interactive island belongs on.
    static func activeScreen(_ chosen: [NSScreen], cursor: CGPoint) -> NSScreen? {
        chosen.first { $0.frame.contains(cursor) } ?? chosen.first
    }
}
