// The close-the-island shortcut: which combinations it takes, and how they are
// handed to Carbon.
//
// A registered hot key swallows its keys system-wide, so a rule that let Shift
// alone through would take a capital letter away from every app on the Mac.
// And macOS 15 quietly ignores hot keys whose only modifiers are ⌥ or ⌥⇧, so a
// rule that let those through would ship a setting that does nothing. Both are
// asserted here, where no registration, permission or keyboard is needed.
//
// Run with scripts/test-close-hotkey.sh.

import AppKit
import Carbon.HIToolbox

@main @MainActor
enum CloseHotKeyTests {

    static var failures = 0

    static func check(_ condition: Bool, _ what: String) {
        print("  \(condition ? "\u{2713}" : "\u{2717}") \(what)")
        if !condition { failures += 1 }
    }

    static func flags(_ f: NSEvent.ModifierFlags) -> UInt { f.rawValue }

    static func main() {
        // MARK: – Which shortcuts are accepted

        check(CloseHotKey.isAllowed(flags: flags([.control, .option])), "⌃⌥, the default, is accepted")
        check(CloseHotKey.isAllowed(flags: flags([.command, .shift])), "⌘⇧ is accepted")
        check(CloseHotKey.isAllowed(flags: flags([.control])), "⌃ alone is accepted")
        check(CloseHotKey.isAllowed(flags: flags([.command])), "⌘ alone is accepted")
        check(!CloseHotKey.isAllowed(flags: flags([.shift])), "⇧ alone is refused: it would take capitals")
        check(!CloseHotKey.isAllowed(flags: flags([.option])), "⌥ alone is refused: macOS 15 ignores it")
        check(!CloseHotKey.isAllowed(flags: flags([.option, .shift])), "⌥⇧ is refused for the same reason")
        check(!CloseHotKey.isAllowed(flags: 0), "no modifier at all is refused")
        // Settings records the flags already masked to these four, but a stray
        // device-dependent bit must not make an otherwise bad set acceptable.
        check(!CloseHotKey.isAllowed(flags: flags([.shift, .capsLock])), "Caps Lock does not count as a modifier")

        // MARK: – Carbon's modifier bits

        check(CloseHotKey.carbonModifiers(from: flags([.control, .option])) == UInt32(controlKey | optionKey),
              "⌃⌥ becomes controlKey | optionKey")
        check(CloseHotKey.carbonModifiers(from: flags([.command, .shift])) == UInt32(cmdKey | shiftKey),
              "⌘⇧ becomes cmdKey | shiftKey")
        check(CloseHotKey.carbonModifiers(from: flags([.command, .control, .option, .shift]))
              == UInt32(cmdKey | controlKey | optionKey | shiftKey),
              "all four map, none lost")
        check(CloseHotKey.carbonModifiers(from: flags([.capsLock, .function])) == 0,
              "keys that are not shortcut modifiers carry nothing across")

        print(failures == 0 ? "\nAll close-hotkey checks passed." : "\n\(failures) check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
