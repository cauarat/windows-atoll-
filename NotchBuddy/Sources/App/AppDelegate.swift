import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private(set) var islandController: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Coucou")
        button.image?.size = NSSize(width: 24, height: 18)
        button.image?.accessibilityDescription = "Coucou"
        button.image?.isTemplate = true

        let menu = NSMenu()
        // AppKit would re-enable "Open Coucou" from target/action validation,
        // undoing the greying that says it cannot do anything while off.
        menu.autoenablesItems = false
        openItem = menu.addItem(withTitle: "Open Coucou", action: #selector(openIsland), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
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
        applyEnabledToPassiveIslands(on)
        refreshMenuBarState()
    }

    private func refreshMenuBarState() {
        let on = AppState.shared.isEnabled
        toggleItem?.title = on ? "Turn Coucou off" : "Turn Coucou on"
        openItem?.isEnabled = on
        // With the island gone the menu bar icon is all that is left on screen;
        // dimming it is what answers "is it even running?" without a click.
        statusItem?.button?.alphaValue = on ? 1.0 : 0.4
        statusItem?.button?.toolTip = on ? "Coucou" : "Coucou — off"
    }

    // MARK: - Actions

    @objc private func openIsland() {
        islandController?.expand(to: .overview)
    }

    private var settingsWindow: NSWindow?

    @objc private func openSettingsFromNotification(_ notification: Notification) {
        if let section = notification.object as? String {
            UserDefaults.standard.set(section, forKey: "settingsSection")
        }
        openSettings()
    }

    @objc private func openSettings() {
        // The island floats above every window; fold it away so it can't cover Settings.
        if AppState.shared.mode == .expanded { islandController?.collapse() }

        if let w = settingsWindow, w.isVisible {
            placeBelowIsland(w)
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Settings — Coucou"
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

    /// Centres the window horizontally and keeps its title bar clear of the island panel
    /// (320 pt tall at the top of the notch screen), shrinking it to fit if needed.
    private func placeBelowIsland(_ win: NSWindow) {
        let chosen = IslandDisplays.chosenScreens(NSScreen.screens,
                                                  selection: AppState.shared.displaySelection)
        let screen = IslandDisplays.activeScreen(chosen, cursor: NSEvent.mouseLocation)
            ?? NSScreen.main ?? win.screen
        guard let screen else { win.center(); return }
        let visible = screen.visibleFrame
        let islandBottom = screen.frame.maxY - 320 - 12   // island panel height + margin
        let top = min(visible.maxY, islandBottom)
        var frame = win.frame
        frame.size.height = min(frame.height, max(top - visible.minY - 12, win.minSize.height))
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = max(visible.minY + 12, top - frame.height)
        win.setFrame(frame, display: true)
    }

    // MARK: - Island setup

    /// Mochi at rest on every chosen display except the one she is actually on.
    private var passiveIslands: [String: PassiveIslandController] = [:]

    /// Rebuilds the set of islands: one interactive, on the display the cursor
    /// is on, and a resting one on each of the other chosen displays.
    ///
    /// Called on launch, whenever displays are plugged in, unplugged or
    /// rearranged, when the preference changes, and when the cursor crosses to
    /// another chosen display.
    /// `rebuild` tears the resting islands down and makes them again, for when
    /// the thing that changed is baked into their frames — a chosen height. The
    /// cheap path, for the cursor crossing displays, leaves them alone.
    func refreshIslands(rebuild: Bool = false) {
        if rebuild {
            for controller in passiveIslands.values { controller.hide() }
            passiveIslands.removeAll()
        }
        let selection = AppState.shared.displaySelection
        let chosen = IslandDisplays.chosenScreens(NSScreen.screens, selection: selection)
        guard let active = IslandDisplays.activeScreen(chosen, cursor: NSEvent.mouseLocation) else {
            // No display at all: nothing to draw on, and nothing to tidy up that
            // the window server has not already taken away.
            return
        }

        if let controller = islandController, rebuild || !controller.isOn(active) {
            // On a rebuild, re-measure even when the screen has not changed:
            // the height it should be drawn at just did.
            controller.move(to: active)
        }

        let activeID = IslandDisplays.identifier(for: active)
        var wanted: [String: NSScreen] = [:]
        for screen in chosen {
            guard let id = IslandDisplays.identifier(for: screen), id != activeID else { continue }
            wanted[id] = screen
        }

        for (id, controller) in passiveIslands where wanted[id] == nil {
            controller.hide()
            passiveIslands[id] = nil
        }
        for (id, screen) in wanted where passiveIslands[id] == nil {
            let controller = PassiveIslandController(screen: screen, screenID: id)
            passiveIslands[id] = controller
            if AppState.shared.isEnabled { controller.show() }
        }
    }

    /// Off, the resting islands go with the real one.
    func applyEnabledToPassiveIslands(_ on: Bool) {
        for controller in passiveIslands.values {
            if on { controller.show() } else { controller.hide() }
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
        N8nPoller.shared.start()
        VercelPoller.shared.start()
        ResendPoller.shared.start()
        GithubPoller.shared.start()
        StripePoller.shared.start()
        CalcomPoller.shared.start()
        NotionPoller.shared.start()
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsFromNotification(_:)),
                                               name: .openFullSettings, object: nil)
        #if !APPSTORE
        _ = MusicController.shared
        MessagingCoordinator.shared.start()
        #endif
    }
}
