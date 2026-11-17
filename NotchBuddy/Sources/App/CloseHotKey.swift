import AppKit
import Carbon.HIToolbox

/// The shortcut that closes the island, registered with the system.
///
/// Carbon's `RegisterEventHotKey` rather than the `NSEvent` global monitor the
/// "show island" shortcut uses, for three reasons that all bite this one in
/// particular. A global monitor needs Accessibility permission, and without it
/// the shortcut silently does nothing. It never sees keys delivered to Notchy
/// itself, so it would go dead exactly while the reply box has the keyboard —
/// the moment a message is most likely on screen. And it cannot swallow the
/// keystroke, so ⌃⌥X would close the island and type into the app behind it.
/// A registered hot key has none of those problems and is fine in the sandbox.
///
/// One registration for the app, so a singleton: the island controller hands it
/// the preference whenever the preference changes, and listens for
/// `.closeHotKeyPressed`.
@MainActor
final class CloseHotKey {
    static let shared = CloseHotKey()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Registers the shortcut, replaces the one registered before, or drops it.
    /// False when the system refused it: another app holds the same keys, or
    /// it is a combination macOS no longer lets an app take (see `isAllowed`).
    @discardableResult
    func update(enabled: Bool, flags: UInt, code: UInt16) -> Bool {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        guard enabled else { return true }
        guard Self.isAllowed(flags: flags) else { return false }
        guard installHandler() else { return false }

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: closeHotKeySignature, id: 1)
        let status = RegisterEventHotKey(UInt32(code), Self.carbonModifiers(from: flags), id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    /// Installed once and left: a handler with no hot key behind it costs
    /// nothing, and the island can be rebuilt any number of times.
    private func installHandler() -> Bool {
        if handlerRef != nil { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), closeHotKeyHandler,
                                         1, &spec, nil, &handlerRef)
        return status == noErr
    }

    // MARK: - Rules (pure, tested by tests/CloseHotKeyTests.swift)

    /// Whether a shortcut is one worth registering.
    ///
    /// It has to hold ⌘ or ⌃. Shift alone would take a capital letter from
    /// every app on the Mac, and since macOS 15 the system refuses hot keys
    /// whose only modifiers are ⌥ or ⌥⇧ — refuses them by never firing, which
    /// would look like a broken setting rather than a rejected one.
    nonisolated static func isAllowed(flags: UInt) -> Bool {
        let mods = NSEvent.ModifierFlags(rawValue: flags)
        return mods.contains(.command) || mods.contains(.control)
    }

    /// `NSEvent` modifier flags, as Settings records them, in Carbon's terms.
    /// The key code needs no such step: both speak the same virtual key codes.
    nonisolated static func carbonModifiers(from flags: UInt) -> UInt32 {
        let mods = NSEvent.ModifierFlags(rawValue: flags)
        var carbon: UInt32 = 0
        if mods.contains(.command) { carbon |= UInt32(cmdKey) }
        if mods.contains(.option)  { carbon |= UInt32(optionKey) }
        if mods.contains(.control) { carbon |= UInt32(controlKey) }
        if mods.contains(.shift)   { carbon |= UInt32(shiftKey) }
        return carbon
    }
}

extension Notification.Name {
    /// The close shortcut was pressed. Posted from the Carbon handler; the
    /// island controller observes it on the main queue.
    static let closeHotKeyPressed = Notification.Name("notchBuddy.closeHotKeyPressed")
}

/// 'NBXC' — tells our hot key apart from any other in the same event stream.
private let closeHotKeySignature: OSType = 0x4E42_5843

/// A plain function, not a closure in the class above: a closure written inside
/// a `@MainActor` type inherits its isolation, and a C callback is no place for
/// the runtime to start asserting one. This touches nothing isolated — posting
/// a notification is fine from anywhere, and the observer names its own queue.
private func closeHotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var id = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr, id.signature == closeHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }
    NotificationCenter.default.post(name: .closeHotKeyPressed, object: nil)
    return noErr
}
