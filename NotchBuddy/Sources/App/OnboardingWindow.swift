import AppKit
import SwiftUI

/// The welcome's window: dark like the island, hung right under it, and let go
/// the moment it closes, so nothing of it keeps drawing afterwards.
///
/// One welcome at a time. Asking for it while it is up brings it forward
/// instead of opening a second.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: OnboardingModel?
    private var onFinish: (() -> Void)?
    private var persist = true
    private var titleObserver: NSObjectProtocol?

    var isShowing: Bool { window != nil }

    /// - Parameters:
    ///   - start: the screen to open on — the hello, except for a screenshot.
    ///   - persist: false for a preview, which must not mark the welcome done.
    ///   - place: positions the window (the Settings window's rule, under the island).
    ///   - onFinish: runs once the welcome is over, however it ended.
    func show(from start: OnboardingStep = .welcome, persist: Bool = true,
              place: (NSWindow) -> Void, onFinish: @escaping () -> Void) {
        if window != nil {
            bringToFront()
            return
        }
        self.persist = persist
        self.onFinish = onFinish

        let model = OnboardingModel(start: start) { [weak self] in self?.finish() }
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: OnboardingView.size),
                           styleMask: [.titled, .closable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = .black
        win.isReleasedWhenClosed = false
        // The title still names it in Mission Control and the Window menu.
        win.title = L("Welcome to Notchy")
        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
        win.standardWindowButton(.zoomButton)?.isHidden = true
        let host = NSHostingView(rootView: Localizing { OnboardingView(model: model) })
        // The window sets the size, not the view: left to itself the hosting
        // view adds the title bar's height on top of the screens' own.
        host.sizingOptions = []
        win.contentView = host
        // Above other apps' windows while it is up. Notchy has no Dock icon and
        // no place in Command-Tab, so a welcome that opened behind a browser
        // could not be found again; it is short-lived and closes itself.
        win.level = .floating
        // The content runs up under the transparent title bar, so the window's
        // whole frame is the size the screens are laid out in — and placing it
        // under the island may never squeeze it below that.
        win.setFrame(NSRect(origin: win.frame.origin, size: OnboardingView.size), display: false)
        win.minSize = OnboardingView.size
        win.delegate = self
        place(win)

        self.window = win
        self.model = model
        // AppKit text does not follow the language on its own.
        titleObserver = NotificationCenter.default.addObserver(
            forName: .languageChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.window?.title = L("Welcome to Notchy") }
        }

        win.orderFrontRegardless()
        win.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        model.start()
    }

    func bringToFront() {
        window?.orderFrontRegardless()
        window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Open Notchy or Skip.
    private func finish() {
        guard let window else { return }
        // Cleared before `close()`, so `windowWillClose` knows this is not a
        // second ending.
        self.window = nil
        window.delegate = nil
        window.close()
        wrapUp()
    }

    /// The close button: the same as Skip, keeping whatever was already chosen.
    func windowWillClose(_ notification: Notification) {
        guard window != nil else { return }
        model?.leaveStep()
        window = nil
        wrapUp()
    }

    private func wrapUp() {
        if let titleObserver { NotificationCenter.default.removeObserver(titleObserver) }
        titleObserver = nil
        if persist { AppState.shared.onboardingVersion = OnboardingGate.version }
        // The window, its hosting view and Mochi's ticking canvas go with this.
        model = nil
        let done = onFinish
        onFinish = nil
        done?()
    }
}
