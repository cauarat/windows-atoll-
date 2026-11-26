import Foundation

/// The key that is held to dictate. The raw values are what `dictationHoldKey`
/// stores, the same spellings the Windows and Linux app use for the keys both
/// have (rightAlt is the Mac's right Option).
enum DictationHoldKey: String, CaseIterable, Identifiable, Sendable {
    case fn
    case rightAlt
    case rightCtrl
    case rightCmd
    case off

    var id: String { rawValue }

    /// English — the catalogue key, translated where it is drawn.
    var title: String {
        switch self {
        case .fn:        return "fn (🌐)"
        case .rightAlt:  return "Right Option (⌥)"
        case .rightCtrl: return "Right Control (⌃)"
        case .rightCmd:  return "Right Command (⌘)"
        case .off:       return "No key — only the button"
        }
    }

    /// The virtual key code a `flagsChanged` event carries for it.
    var keyCode: Int64? {
        switch self {
        case .fn:        return 63   // kVK_Function
        case .rightAlt:  return 61   // kVK_RightOption
        case .rightCtrl: return 62   // kVK_RightControl
        case .rightCmd:  return 54   // kVK_RightCommand
        case .off:       return nil
        }
    }

    /// The bit of CGEventFlags that is set while that very key is down: the
    /// secondary-fn mask for fn, the device-dependent right-hand bits
    /// (NX_DEVICER*KEYMASK) for the others, so the left key never counts.
    var downMask: UInt64 {
        switch self {
        case .fn:        return 0x80_0000  // CGEventFlags.maskSecondaryFn
        case .rightAlt:  return 0x40       // NX_DEVICERALTKEYMASK
        case .rightCtrl: return 0x2000     // NX_DEVICERCTLKEYMASK
        case .rightCmd:  return 0x10       // NX_DEVICERCMDKEYMASK
        case .off:       return 0
        }
    }

    static let `default`: DictationHoldKey = .fn
}

/// Hold-to-talk, as a state machine with no clock and no keyboard of its own:
/// the key tap feeds it what happened and when, a timer feeds it `tick`, and it
/// answers with what to do. tests/fixtures/dictation.json is its specification,
/// and windows/src-tauri/src/dictation_keys.rs is the same machine for Windows
/// and Linux.
///
/// - `arm` on the press: start the microphone and the connection at once, so
///   the first syllable is not lost.
/// - `show` once the key has been held `minimumHold`: open the card. Shorter is
///   a tap, and a tap never opens anything.
/// - `commit` on release after that: stop and transcribe. Also at
///   `maximumHold`, after which the release is ignored.
/// - `cancel` for a tap, for any other key or modifier pressed while holding
///   (that was a shortcut — ⌥E is an accent, not a dictation), and for Escape.
struct DictationHoldGesture {
    enum Input: String, Sendable {
        case down, up, other, escape, tick
    }

    enum Action: String, Sendable {
        case arm, show, commit, cancel
    }

    static let minimumHold: TimeInterval = 0.3
    static let maximumHold: TimeInterval = 300

    private enum State: Equatable {
        case idle
        case armed(since: TimeInterval)
        case shown(since: TimeInterval)
        /// Committed at the cap or cancelled: the key is still down, and its
        /// release must not start anything.
        case waitingForRelease
    }

    private var state: State = .idle

    /// Whether the key is being held for a dictation right now.
    var isHolding: Bool {
        switch state {
        case .armed, .shown: return true
        case .idle, .waitingForRelease: return false
        }
    }

    mutating func reset() { state = .idle }

    mutating func handle(_ input: Input, at time: TimeInterval) -> [Action] {
        switch (state, input) {
        case (.idle, .down):
            state = .armed(since: time)
            return [.arm]
        case (.idle, _):
            return []

        case (.armed(let since), .tick):
            guard time - since >= Self.minimumHold else { return [] }
            state = .shown(since: since)
            return [.show] + capReached(since: since, at: time)
        case (.armed(let since), .up):
            state = .idle
            return time - since >= Self.minimumHold ? [.show, .commit] : [.cancel]
        case (.armed, .other), (.armed, .escape):
            state = .waitingForRelease
            return [.cancel]
        case (.armed, .down):
            return []  // key repeat

        case (.shown(let since), .tick):
            return capReached(since: since, at: time)
        case (.shown, .up):
            state = .idle
            return [.commit]
        case (.shown, .other), (.shown, .escape):
            state = .waitingForRelease
            return [.cancel]
        case (.shown, .down):
            return []

        case (.waitingForRelease, .up):
            state = .idle
            return []
        case (.waitingForRelease, _):
            return []
        }
    }

    private mutating func capReached(since: TimeInterval, at time: TimeInterval) -> [Action] {
        guard time - since >= Self.maximumHold else { return [] }
        state = .waitingForRelease
        return [.commit]
    }
}
