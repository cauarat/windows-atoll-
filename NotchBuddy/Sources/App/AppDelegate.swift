import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The live delegate.
    ///
    /// `NSApp.delegate as? AppDelegate` does **not** work in this app and never
    /// did: `@NSApplicationDelegateAdaptor` installs SwiftUI's own shim as the
    /// application delegate and forwards to ours, so `NSApp.delegate` is some
    /// `NSApplicationDelegate` that is not this class, and every such cast
    /// silently returns nil. That is why the settings window could not reach the
    /// island — and why the master switch there never did anything either.
    static private(set) weak var shared: AppDelegate?

    var statusItem: NSStatusItem?
    private(set) var islandController: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        // Ignore SIGPIPE — prevents crash when nb-hook closes socket before we write response
        signal(SIGPIPE, SIG_IGN)
        // Warm up Keychain cache on main thread BEFORE any poller or view touches it
        _ = KeychainStore.shared
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarItem()
        setupIsland()
    }

    // MARK: - Menu bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Notchy")
        button.image?.size = NSSize(width: 24, height: 18)
        button.image?.accessibilityDescription = "Notchy"
        button.image?.isTemplate = true

        let menu = NSMenu()
        // AppKit would re-enable "Open Coucou" from target/action validation,
        // undoing the greying that says it cannot do anything while off.
        menu.autoenablesItems = false
        openItem = menu.addItem(withTitle: "Open Notchy", action: #selector(openIsland), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        #if !APPSTORE
        // Permanent rather than appearing only when something is waiting, which
        // is the Mac convention and the one place people look for it. Sparkle
        // answers either way: it says you are up to date as readily as it
        // offers a new version.
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        #endif
        toggleItem = menu.addItem(withTitle: "", action: #selector(toggleEnabled), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem?.menu = menu
        refreshMenuBarState()
    }

    // MARK: - Master switch

    private var openItem: NSMenuItem?
    private var toggleItem: NSMenuItem?

    @objc private func toggleEnabled() {
        applyEnabled(!AppState.shared.isEnabled)
    }

    /// The one way the switch moves, whichever control was used.
    func applyEnabled(_ on: Bool) {
        AppState.shared.isEnabled = on      // didSet persists it and feeds the gate
        islandController?.setRunning(on)
        // Off means off everywhere: a banner left in Notification Center would
        // still be sitting there with a Reply box an hour later.
        #if !APPSTORE
        if !on { MessageNotifier.shared.withdrawAll() }
        #endif
        refreshMenuBarState()
    }

    private func refreshMenuBarState() {
        let on = AppState.shared.isEnabled
        toggleItem?.title = on ? "Turn Notchy off" : "Turn Notchy on"
        openItem?.isEnabled = on
        // With the island gone the menu bar icon is all that is left on screen;
        // dimming it is what answers "is it even running?" without a click.
        statusItem?.button?.alphaValue = on ? 1.0 : 0.4
        statusItem?.button?.toolTip = on ? "Notchy" : "Notchy — off"
    }

    // MARK: - Actions

    #if !APPSTORE
    @objc private func checkForUpdates() {
        Updater.shared.check()
    }
    #endif

    @objc private func openIsland() {
        islandController?.expand(to: .overview)
    }

    /// Clicking the app icon in Finder, Launchpad, Spotlight or the Dock while
    /// Coucou is already running.
    ///
    /// Without this the app looks broken from the outside: an LSUIElement app
    /// has no window to bring forward, so a second launch does nothing at all
    /// and the icon you just clicked appears dead. Opening is the one thing
    /// somebody clicking it can mean.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if AppState.shared.isEnabled {
            openIsland()
        } else {
            // Nothing to expand while it is off, and silently switching it back
            // on would undo a deliberate choice. Show the window with the
            // switch in it instead.
            openSettings()
        }
        return true
    }

    private var settingsWindow: NSWindow?

    @objc private func openSettingsFromNotification(_ notification: Notification) {
        if let section = notification.object as? String {
            UserDefaults.standard.set(section, forKey: "settingsSection")
        }
        openSettings()
    }

    @objc private func openSettings() {
        // The island floats above every window; fold it away so it can't cover
        // Settings. A screen refuses `collapse()` — it is held open on purpose —
        // so it gets the call that is allowed to put it away.
        if AppState.shared.viewHoldsIslandOpen { islandController?.closeScreen() }
        if AppState.shared.mode == .expanded { islandController?.collapse() }

        if let w = settingsWindow, w.isVisible {
            placeBelowIsland(w)
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Settings — Notchy"
        let host = NSHostingView(rootView: SettingsView())
        host.sizingOptions = [.minSize]
        win.contentView = host
        win.contentMinSize = NSSize(width: 640, height: 420)
        win.isReleasedWhenClosed = false
        placeBelowIsland(win)
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Centres the window horizontally and keeps its title bar clear of the room
    /// the island reserves at the top of the screen, shrinking it to fit if needed.
    private func placeBelowIsland(_ win: NSWindow) {
        let chosen = IslandDisplays.chosenScreens(NSScreen.screens,
                                                  selection: AppState.shared.displaySelection)
        let screen = IslandDisplays.activeScreen(chosen, cursor: NSEvent.mouseLocation)
            ?? NSScreen.main ?? win.screen
        guard let screen else { win.center(); return }
        let visible = screen.visibleFrame
        // Under the island itself, wherever it got to. The reservation at the
        // top of the screen is still the answer for an island in the notch, and
        // the fallback for before the panel exists.
        let islandBottom = islandController?.islandScreenFrame()
            .map { $0.minY - 12 }
            ?? (screen.frame.maxY - IslandConst.topReservation - 12)
        let top = min(visible.maxY, islandBottom)
        var frame = win.frame
        frame.size.height = min(frame.height, max(top - visible.minY - 12, win.minSize.height))
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = max(visible.minY + 12, top - frame.height)
        win.setFrame(frame, display: true)
    }

    // MARK: - Island setup

    /// Puts the one island on the display the cursor is on, among those Mochi is
    /// allowed on.
    ///
    /// There is deliberately only ever one. The other displays used to get a
    /// decorative copy that took no mouse and could not expand, which is exactly
    /// what "it appears but never opens" was: a thing shaped like the island
    /// that was never able to answer.
    ///
    /// Called on launch, whenever displays are plugged in, unplugged or
    /// rearranged, when the preference changes, and when the cursor crosses to
    /// another allowed display.
    func refreshIslands(rebuild: Bool = false) {
        let selection = AppState.shared.displaySelection
        let chosen = IslandDisplays.chosenScreens(NSScreen.screens, selection: selection)
        guard let active = IslandDisplays.activeScreen(chosen, cursor: NSEvent.mouseLocation) else {
            return
        }
        guard let controller = islandController else { return }
        // `rebuild` re-measures even when the screen has not changed, for when
        // the thing that moved is a chosen height rather than the display.
        if rebuild || !controller.isOn(active) {
            controller.move(to: active)
        }
    }

    private func setupIsland() {
        let selection = AppState.shared.displaySelection
        let chosen = IslandDisplays.chosenScreens(NSScreen.screens, selection: selection)
        let start = IslandDisplays.activeScreen(chosen, cursor: NSEvent.mouseLocation)
            ?? IslandWindowController.notchScreen() ?? NSScreen.main!
        islandController = IslandWindowController(screen: start)

        // Displays coming and going. Nothing watched for this before, which is
        // why unplugging a monitor used to strand the island on it.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIslands() }
        }

        refreshIslands()
        if AppState.shared.isEnabled {
            islandController?.showWindow(nil)
            islandController?.fsm.launch()
        } else {
            // Launched into a switched-off state: no island, no greeting. The
            // menu bar icon is the way back on.
            islandController?.setRunning(false)
        }
        // The hook server starts either way. handleClient answers immediately
        // while off, which is faster for Claude Code than nothing listening.
        HookServer.shared.start()
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsFromNotification(_:)),
                                               name: .openFullSettings, object: nil)
        #if !APPSTORE
        _ = MusicController.shared
        MessagingCoordinator.shared.start()
        #endif
    }
}
