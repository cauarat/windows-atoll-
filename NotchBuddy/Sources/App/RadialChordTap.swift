import AppKit
import CoreGraphics
import Foundation

/// Watches the mouse for both buttons at once, and opens the wheel.
///
/// An event tap rather than a global monitor, because a monitor cannot consume
/// what it sees: the chord would fire the wheel *and* drop a context menu into
/// whatever was underneath. Consuming needs Accessibility, which the app
/// already declares a use for — `WindowContextCapture` reads window titles
/// through it — but has never actually asked for.
///
/// On its own thread, blocked in a run loop. The 60 Hz island poll already
/// shares the main run loop with every SwiftUI layout pass, and a tap starved
/// behind those collects `tapDisabledByTimeout` and quietly stops working.
final class RadialChordTap: @unchecked Sendable {

    static let shared = RadialChordTap()

    /// Stamped on events this tap re-posts, so they are passed straight back
    /// out instead of being judged a second time.
    private static let reposted: Int64 = 0x4E4F_5443  // "NOTC"

    private let lock = NSLock()
    private var machine = RadialChordMachine()
    private var heldRightDown: CGEvent?

    private var thread: Thread?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var loop: CFRunLoop?
    private var holdTimer: CFRunLoopTimer?

    private(set) var isRunning = false

    // MARK: – Permission

    /// Whether the tap could run. Never prompts.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks, once. Only ever from the user turning the feature on: macOS shows
    /// this prompt once per app identity, so spending it at launch would burn
    /// it on somebody who never wanted the wheel.
    @discardableResult
    static func requestTrust() -> Bool {
        // The constant itself is a global `var`, which Swift 6 will not let a
        // nonisolated context touch. Its value is fixed and documented.
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    // MARK: – Lifetime

    func start() {
        guard !isRunning else { return }
        let t = Thread { [weak self] in self?.run() }
        t.name = "fr.notchy.radial-chord"
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
        lock.lock(); machine.reset(); heldRightDown = nil; lock.unlock()
    }

    private func run() {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue)

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, info -> Unmanaged<CGEvent>? in
                guard let info else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<RadialChordTap>.fromOpaque(info).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Authoritative, whatever `AXIsProcessTrusted` claims: the two
            // disagree for a while after the permission is revoked.
            isRunning = false
            appendAppLog("radial.log", "tapCreate returned nil — not trusted")
            Task { @MainActor in AppState.shared.radialTapFailed = true }
            return
        }

        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        loop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        appendAppLog("radial.log", "tap running")
        Task { @MainActor in AppState.shared.radialTapFailed = false }

        CFRunLoopRun()

        // Unwound by stop().
        if let source { CFRunLoopRemoveSource(loop, source, .commonModes) }
        CFMachPortInvalidate(port)
        tap = nil; source = nil; loop = nil
        appendAppLog("radial.log", "tap stopped")
    }

    // MARK: – The callback

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system turns a tap off if it ever takes too long. Turning it back
        // on is the difference between a wheel that works and one that stops
        // working after a while with nothing to show why.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            appendAppLog("radial.log", "tap re-enabled after \(type.rawValue)")
            lock.lock(); machine.reset(); heldRightDown = nil; lock.unlock()
            return nil
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.reposted {
            return Unmanaged.passUnretained(event)
        }

        let p = event.location
        let t = Date.timeIntervalSinceReferenceDate
        let input: ChordInput
        switch type {
        case .leftMouseDown:     input = .down(.left, at: p, t: t)
        case .rightMouseDown:    input = .down(.right, at: p, t: t)
        case .leftMouseUp:       input = .up(.left, at: p, t: t)
        case .rightMouseUp:      input = .up(.right, at: p, t: t)
        case .leftMouseDragged:  input = .dragged(.left, at: p, t: t)
        case .rightMouseDragged: input = .dragged(.right, at: p, t: t)
        default:                 return Unmanaged.passUnretained(event)
        }

        lock.lock()
        // If the machine's idea of what is pressed ever parts company with the
        // system's, let everything through. A machine that believes a button is
        // held would swallow every click after it, and there would be nothing
        // left to click to put it right.
        if machine.isHolding,
           !CGEventSource.buttonState(.combinedSessionState, button: .right) {
            machine.reset(); heldRightDown = nil
        }
        let outputs = machine.step(input)
        var held = heldRightDown
        var swallow = false
        var fireAt: CGPoint?
        var releaseLeft: CGPoint?
        var flush = false
        var hold = false
        for o in outputs {
            switch o {
            case .passThrough: break
            case .hold:        hold = true; swallow = true
            case .swallow:     swallow = true
            case .flushHeld:   flush = true
            case .fire(let at): fireAt = at; swallow = true
            case .release(_, let at): releaseLeft = at
            }
        }
        if hold { heldRightDown = event.copy() }
        if flush { heldRightDown = nil }
        held = flush ? held : nil
        lock.unlock()

        if flush, let e = held {
            e.setIntegerValueField(.eventSourceUserData, value: Self.reposted)
            e.post(tap: .cgSessionEventTap)
        }
        if let at = releaseLeft {
            let src = CGEventSource(stateID: .combinedSessionState)
            if let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                                mouseCursorPosition: at, mouseButton: .left) {
                up.setIntegerValueField(.eventSourceUserData, value: Self.reposted)
                up.post(tap: .cgSessionEventTap)
            }
        }
        if hold { scheduleHoldTimer() }
        if let at = fireAt {
            // `event.location` is top-left origin; the menu works in
            // NSEvent.mouseLocation's bottom-left space, so it reads the
            // pointer itself rather than being handed one from here.
            _ = at
            Task { @MainActor in RadialMenuController.shared.open() }
        }
        return swallow ? nil : Unmanaged.passUnretained(event)
    }

    /// Fires once the hold window has passed, so a plain right-click is let go.
    private func scheduleHoldTimer() {
        guard let loop else { return }
        if let holdTimer { CFRunLoopTimerInvalidate(holdTimer) }
        let fire = CFAbsoluteTimeGetCurrent() + machine.window + 0.005
        holdTimer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, fire, 0, 0, 0) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            let outs = self.machine.step(.tick(t: Date.timeIntervalSinceReferenceDate))
            let held = outs.contains(.flushHeld) ? self.heldRightDown : nil
            if outs.contains(.flushHeld) { self.heldRightDown = nil }
            self.lock.unlock()
            if let e = held {
                e.setIntegerValueField(.eventSourceUserData, value: Self.reposted)
                e.post(tap: .cgSessionEventTap)
            }
        }
        CFRunLoopAddTimer(loop, holdTimer, .commonModes)
    }
}
