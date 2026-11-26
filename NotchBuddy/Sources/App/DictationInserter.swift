import AppKit
import Carbon.HIToolbox

/// What to do with the text once it is ready, stored in `dictationInsertMode`.
/// The raw values are the Windows and Linux app's too.
enum DictationInsertMode: String, CaseIterable, Identifiable, Sendable {
    /// Typed where the cursor is, in the app in front.
    case paste
    /// Only put on the clipboard.
    case copy

    var id: String { rawValue }

    /// English — the catalogue key.
    var title: String {
        switch self {
        case .paste: return "Paste where the cursor is"
        case .copy:  return "Only copy to the clipboard"
        }
    }

    static let `default`: DictationInsertMode = .paste
}

/// Puts a dictation where the cursor is.
///
/// The way dictation apps do it on a Mac: the text goes on the clipboard for a
/// moment, ⌘V is pressed for the person, and what the clipboard held before is
/// put back. ⌘V works in every app that takes text, which no per-app trick does.
/// The text is marked transient (nspasteboard.org's convention), so clipboard
/// histories — this app's included — leave it out.
///
/// Pressing ⌘V needs Accessibility. Without it, or in a password field (secure
/// input is on, and nothing can type into it), the text is only copied, and
/// the card says so.
@MainActor
enum DictationInserter {
    enum Outcome: Equatable, Sendable {
        case pasted
        case copied
        /// Wanted to paste, could not: a password field had the keyboard.
        case copiedSecureInput
        /// Wanted to paste, could not: Accessibility is not granted.
        case copiedNoAccessibility
    }

    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// How long the pasted text stays on the clipboard before what was there
    /// comes back. Some apps (Electron ones) read a paste a beat late.
    private static let restoreDelay: TimeInterval = 0.8

    static func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    /// Into the app in front, which is still the one being typed in: the hold
    /// key never takes the focus.
    static func paste(_ text: String) -> Outcome {
        guard AXIsProcessTrusted() else {
            copy(text)
            return .copiedNoAccessibility
        }
        guard !IsSecureEventInputEnabled() else {
            copy(text)
            return .copiedSecureInput
        }
        let board = NSPasteboard.general
        let saved = snapshot(board)
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: transientType)
        board.writeObjects([item])
        let ours = board.changeCount
        pressCommandV()
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            // Copied something else meanwhile: theirs wins.
            guard board.changeCount == ours else { return }
            restore(saved, to: board)
        }
        return .pasted
    }

    /// From the card's button: the card had the keyboard, so the app that was
    /// in front before it comes back first.
    static func paste(_ text: String, into app: NSRunningApplication?) async -> Outcome {
        guard let app, !app.isTerminated else { return paste(text) }
        app.activate()
        try? await Task.sleep(for: .milliseconds(250))
        return paste(text)
    }

    private static func snapshot(_ board: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (board.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copy[type] = data }
            }
            return copy
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to board: NSPasteboard) {
        board.clearContents()
        guard !items.isEmpty else { return }
        board.writeObjects(items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        })
    }

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = keyCodeTypingV()
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// The key that types "v" with ⌘ held, in the keyboard layout in use: on
    /// Dvorak it is not the key QWERTY puts V on, and ⌘ shortcuts follow the
    /// letter. QWERTY's when the layout cannot be read.
    private static func keyCodeTypingV() -> CGKeyCode {
        let fallback = CGKeyCode(kVK_ANSI_V)
        guard let layoutSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(layoutSource, kTISPropertyUnicodeKeyLayoutData) else {
            return fallback
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        let commandState = UInt32((cmdKey >> 8) & 0xFF)
        let keyboardType = UInt32(LMGetKbdType())
        return layoutData.withUnsafeBytes { raw -> CGKeyCode in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return fallback }
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), commandState, keyboardType,
                                            OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, chars.count,
                                            &length, &chars)
                if status == noErr, length == 1, chars[0] == 0x76 { return CGKeyCode(code) }  // "v"
            }
            return fallback
        }
    }
}
