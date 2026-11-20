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
        openItem = menu.addItem(withTitle: "", action: #selector(openIsland), keyEquivalent: "")
        menu.addItem(.separator())
        settingsItem = menu.addItem(withTitle: "", action: #selector(openSettings), keyEquivalent: ",")
        #if !APPSTORE
        // Permanent rather than appearing only when something is waiting, which
        // is the Mac convention and the one place people look for it. Sparkle
        // answers either way: it says you are up to date as readily as it
        // offers a new version.
        updatesItem = menu.addItem(withTitle: "", action: #selector(checkForUpdates), keyEquivalent: "")
        #endif
        toggleItem = menu.addItem(withTitle: "", action: #selector(toggleEnabled), keyEquivalent: "")
        menu.addItem(.separator())
        quitItem = menu.addItem(withTitle: "", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem?.menu = menu

        // Every title above is set by refreshMenuBarState, in the chosen
        // language. SwiftUI rebuilds itself from the environment when the
        // language changes; a menu is AppKit and has to be told.
        NotificationCenter.default.addObserver(
            forName: .languageChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMenuBarState() }
        }
        refreshMenuBarState()
    }

    // MARK: - Master switch

    private var openItem: NSMenuItem?
    private var toggleItem: NSMenuItem?
    private var settingsItem: NSMenuItem?
    private var updatesItem: NSMenuItem?
    private var quitItem: NSMenuItem?

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
        openItem?.title = L("Open Notchy")
        settingsItem?.title = L("Settings…")
        updatesItem?.title = L("Check for Updates…")
        quitItem?.title = L("Quit")
        toggleItem?.title = on ? L("Turn Notchy off") : L("Turn Notchy on")
        settingsWindow?.title = L("Settings — Notchy")
        openItem?.isEnabled = on
        // With the island gone the menu bar icon is all that is left on screen;
        // dimming it is what answers "is it even running?" without a click.
        statusItem?.button?.alphaValue = on ? 1.0 : 0.4
        statusItem?.button?.toolTip = on ? "Notchy" : L("Notchy — off")
    }

    // MARK: - Actions

    #if !APPSTORE
    @objc private func checkForUpdates() {
        Updater.shared.check()
    }
    #endif

    @objc private func openIsland() {
        // While the welcome is up the island waits for it, so the welcome is
        // what "Open Notchy" — or clicking the app's icon again — brings back.
        if welcome.isShowing { welcome.bringToFront(); return }
        islandController?.expand(to: .overview)
    }

    // MARK: - Welcome

    /// The first-run welcome, and Settings' "Show the welcome again…".
    private let welcome = OnboardingWindowController()

    /// `NOTCHY_ONBOARDING=<screen>` opens the welcome on that screen
    /// (`welcome`, `name`, `language`, `look`, `tools`, `startup`, `ready`)
    /// whatever has been seen, and never marks it done — for screenshots, since
    /// nothing here can press Continue.
    private var welcomePreviewStep: OnboardingStep? {
        guard let raw = ProcessInfo.processInfo.environment["NOTCHY_ONBOARDING"] else { return nil }
        return OnboardingStep(rawValue: raw) ?? .welcome
    }

    /// Settings' "Show the welcome again…". The island is running, so it only
    /// folds out of the way, as it does for Settings, and replays its greeting
    /// once the welcome is over — with whatever name was just given.
    func showOnboarding() {
        if AppState.shared.viewHoldsIslandOpen { islandController?.closeScreen() }
        if AppState.shared.mode == .expanded { islandController?.collapse() }
        welcome.show(place: placeBelowIsland) { [weak self] in
            guard AppState.shared.isEnabled else { return }
            self?.islandController?.fsm.launch()
        }
    }

    /// The first-run welcome is over: what it held back starts now.
    private func startAfterWelcome() {
        #if !APPSTORE
        MessagingCoordinator.shared.start()
        #endif
        // Switched off from the menu bar while the welcome was up: stays off.
        guard AppState.shared.isEnabled else { return }
        islandController?.startAfterWelcome()
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
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsDefaults.settingsWindowSize),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = L("Settings — Notchy")
        let host = NSHostingView(rootView: Localizing { SettingsView() })
        host.sizingOptions = [.minSize]
        win.contentView = host
        win.contentMinSize = SettingsDefaults.settingsWindowMinSize
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
        let preview = welcomePreviewStep
        let welcomeFirst = AppState.shared.isEnabled
            && (preview != nil
                || OnboardingGate.shouldShow(seen: AppState.shared.onboardingVersion, enabled: true))
        if welcomeFirst {
            // The welcome comes before Notchy opens. The island waits parked, as
            // it does when launched off: no polling, so no hover opening it and
            // no sounds behind the welcome, and no panel taking the keyboard
            // from the name field. Its end starts the island on the greeting.
            islandController?.setRunning(false)
            welcome.show(from: preview ?? .welcome, persist: preview == nil,
                         place: placeBelowIsland) { [weak self] in
                self?.startAfterWelcome()
            }
        } else if AppState.shared.isEnabled {
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
        // `NOTCHY_SEED_HYDRATION=mid|goal|empty|limit` fills today's glass for
        // looking at the hydration cards without living a day first, and
        // `NOTCHY_OPEN_HYDRATION=hydration|sip` opens the island on one of them
        // — nothing here can click a tab. Seeded state is never saved.
        let env = ProcessInfo.processInfo.environment
        if let scene = env["NOTCHY_SEED_HYDRATION"] {
            HydrationStore.shared.seedForPreview(scene)
            let screens: [String: HydrationRoute.Screen] = [
                "settings": .main, "questions": .questions, "estimate": .estimate, "manual": .manual, "sources": .sources,
            ]
            if let open = env["NOTCHY_OPEN_HYDRATION"], let screen = screens[open] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { HydrationRoute.shared.open(screen) }
            } else if let open = env["NOTCHY_OPEN_HYDRATION"] {
                if open == "sip" { HydrationStore.shared.previewPrompt(env["NOTCHY_SIP_PROMPT"] == "goal" ? .goal : .reminder) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    NotificationCenter.default.post(name: .hydrationReminderDue, object: open)
                }
            }
        } else {
            HydrationStore.shared.start()
        }
        #if !APPSTORE
        _ = MusicController.shared
        // Not under the welcome: a fresh install's message pills would put the
        // notification-permission prompt on top of it. It starts as it ends.
        if !welcomeFirst { MessagingCoordinator.shared.start() }
        // `NOTCHY_SEED_AGENDA=1` fills the Agenda with four meetings around
        // now, the next one a minute from its heads-up, for looking at the tab
        // without an Actuar account.
        if ProcessInfo.processInfo.environment["NOTCHY_SEED_AGENDA"] == "1" {
            AgendaClient.shared.seedForPreview()
        } else {
            AgendaClient.shared.start()
        }
        #endif
        #if DEBUG
        applyReferenceCaptureOverrides(env)
        #endif
    }

    #if DEBUG
    /// Debug builds only, for `scripts/capture-mac-reference.sh`, which takes the
    /// Mac references the Windows port is compared against (`docs/parity/`).
    /// Nothing here can click a sidebar row or flip the system appearance, so the
    /// script asks through the environment:
    /// - `NOTCHY_APPEARANCE=light|dark` sets this app's appearance only; the
    ///   system setting is never touched.
    /// - `NOTCHY_ISLAND_TAB=layout|content|activity|behavior` picks the Dynamic
    ///   Island tab.
    /// - `NOTCHY_SETTINGS_SECTION=<sidebar id>` opens Settings on that pane once
    ///   the island has settled.
    private func applyReferenceCaptureOverrides(_ env: [String: String]) {
        switch env["NOTCHY_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        if let tab = env["NOTCHY_ISLAND_TAB"] {
            UserDefaults.standard.set(tab, forKey: "islandTab")
        }
        if let section = env["NOTCHY_SETTINGS_SECTION"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                NotificationCenter.default.post(name: .openFullSettings, object: section)
            }
        }
    }
    #endif
}
