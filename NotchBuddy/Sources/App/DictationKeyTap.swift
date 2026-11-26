import AppKit
import CoreGraphics
import Foundation

/// Listens for the dictation key being held, anywhere.
///
/// A listen-only event tap: it never holds back or changes a keystroke, so
/// every app still gets fn, ⌥ and the rest exactly as before. It needs
/// Accessibility, which dictation asks for anyway to paste the text.
///
/// It reports only what the hold-to-talk gesture needs — the key went down,
/// came up, or something else was pressed while it was down — and nothing at
/// all while the key is up: what is typed never leaves the callback.
///
/// On its own thread, like the radial menu's tap, so a busy main run loop can
/// never starve it into `tapDisabledByTimeout`.
final class DictationKeyTap: @unchecked Sendable {

    static let shared = DictationKeyTap()

    private let lock = NSLock()
    private var key: DictationHoldKey = .default
    private var keyIsDown = false
    private var lastFlags: UInt64 = 0

    private var thread: Thread?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var loop: CFRunLoop?

    private(set) var isRunning = false

    /// Device-independent modifier bits: a change in any of them, other than
    /// the dictation key's own, is "another key".
    private static let modifierBits: UInt64 =
        CGEventFlags.maskShift.rawValue | CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue |
        CGEventFlags.maskSecondaryFn.rawValue

    private static let escapeKeyCode: Int64 = 53

    // MARK: – Lifetime

    func start(key: DictationHoldKey) {
        lock.lock()
        self.key = key
        keyIsDown = false
        lock.unlock()
        guard !isRunning, key != .off else { return }
        let t = Thread { [weak self] in self?.run() }
        t.name = "fr.notchy.dictation-key"
        t.qualityOfService = .userInteractive
        thread = t
        isRunning = true
        t.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let loop { CFRunLoopStop(loop) }
        lock.lock()
        keyIsDown = false
        lock.unlock()
    }

    private func run() {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask,
            callback: { _, type, event, info -> Unmanaged<CGEvent>? in
                if let info {
                    Unmanaged<DictationKeyTap>.fromOpaque(info).takeUnretainedValue().handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isRunning = false
            appendAppLog("dictation.log", "tapCreate returned nil — not trusted")
            DispatchQueue.main.async { MainActor.assumeIsolated { AppState.shared.dictationTapFailed = true } }
            return
        }

        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        loop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        appendAppLog("dictation.log", "key tap running")
        DispatchQueue.main.async { MainActor.assumeIsolated { AppState.shared.dictationTapFailed = false } }

        CFRunLoopRun()

        if let source { CFRunLoopRemoveSource(loop, source, .commonModes) }
        CFMachPortInvalidate(port)
        tap = nil; source = nil; loop = nil
        appendAppLog("dictation.log", "key tap stopped")
    }

    // MARK: – The callback

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            appendAppLog("dictation.log", "key tap re-enabled after \(type.rawValue)")
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let code = event.getIntegerValueField(.keyboardEventKeycode)

        lock.lock()
        var input: DictationHoldGesture.Input?
        switch type {
        case .flagsChanged:
            let flags = event.flags.rawValue
            if code == key.keyCode {
                let down = flags & key.downMask != 0
                if down != keyIsDown {
                    keyIsDown = down
                    input = down ? .down : .up
                }
            } else if keyIsDown {
                // A modifier pressed while holding: ⌥⇧, fn⌃… a shortcut, not a dictation.
                let pressed = flags & ~lastFlags & Self.modifierBits
                if pressed != 0 { input = .other }
            }
            lastFlags = flags
        case .keyDown:
            if keyIsDown {
                input = code == Self.escapeKeyCode ? .escape : .other
            }
        default:
            break
        }
        lock.unlock()

        guard let input else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { DictationController.shared.handleKey(input, at: now) }
        }
    }
}
