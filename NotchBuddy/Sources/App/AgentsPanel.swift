import AppKit
import SwiftUI

#if !APPSTORE

/// What Claude Code is doing on this Mac, and which account it is doing it as.
///
/// Reads two things Claude Code already keeps for itself: the account summary
/// in `~/.claude.json` and the running sessions in `~/.claude/sessions`. It
/// never touches the login token, which lives in the Keychain, and it never
/// opens a `.key` file, which is a socket secret sitting in that same folder.
/// Nothing it reads is written anywhere.
@MainActor
final class AgentsStore: ObservableObject {
    static let shared = AgentsStore()

    @Published private(set) var account: ClaudeAccount = .none
    @Published private(set) var sessions: [ClaudeSession] = []
    @Published private(set) var lastRead: Date?

    /// `~/.claude.json` is 80 KB here, so it is re-read only when it changes
    /// and never on the main thread — parsing it at 1 Hz where the island
    /// animates would be visible.
    private var accountStamp: Date?

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private var accountURL: URL { home.appendingPathComponent(".claude.json") }
    private var sessionsURL: URL { home.appendingPathComponent(".claude/sessions") }

    private init() {}

    func refresh() async {
        let accountURL = self.accountURL
        let sessionsURL = self.sessionsURL
        let known = accountStamp

        let result = await Task.detached(priority: .utility) { () -> (ClaudeAccount?, Date?, [ClaudeSession]) in
            let fm = FileManager.default

            var account: ClaudeAccount?
            var stamp: Date?
            if let attrs = try? fm.attributesOfItem(atPath: accountURL.path),
               let modified = attrs[.modificationDate] as? Date {
                stamp = modified
                if modified != known, let data = try? Data(contentsOf: accountURL) {
                    account = ClaudeAccount(claudeJSON: data)
                }
            }

            // `.json` only. The `.key` beside each one is the socket secret
            // Claude Code uses to talk to itself, and is none of our business.
            var sessions: [ClaudeSession] = []
            if let names = try? fm.contentsOfDirectory(atPath: sessionsURL.path) {
                for name in names where name.hasSuffix(".json") {
                    guard let data = try? Data(contentsOf: sessionsURL.appendingPathComponent(name)),
                          let s = ClaudeSession(sessionJSON: data), s.isAlive else { continue }
                    sessions.append(s)
                }
            }
            sessions.sort { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
            return (account, stamp, sessions)
        }.value

        if let a = result.0 { account = a }
        accountStamp = result.1
        sessions = result.2
        lastRead = Date()
    }
}

/// The panel.
@MainActor
final class AgentsPanelController {
    static let shared = AgentsPanelController()

    private var panel: NSPanel?
    private var escapeMonitor: Any?
    private var poll: Timer?

    private init() {}

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { isOpen ? close() : open() }

    func open() {
        Task { await AgentsStore.shared.refresh() }

        if let panel { place(panel); panel.makeKeyAndOrderFront(nil); return }

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false

        let host = NSHostingView(rootView: Localizing { AgentsPanelView()
            .environmentObject(AppState.shared) })
        host.frame = NSRect(origin: .zero, size: p.contentRect(forFrameRect: p.frame).size)
        host.autoresizingMask = [.width, .height]
        p.contentView = host

        panel = p
        place(p)
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        watch()
    }

    func close() {
        panel?.orderOut(nil)
        poll?.invalidate(); poll = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    private func place(_ panel: NSPanel) {
        let chosen = IslandDisplays.chosenScreens(NSScreen.screens,
                                                  selection: AppState.shared.displaySelection)
        guard let screen = IslandDisplays.activeScreen(chosen, cursor: NSEvent.mouseLocation)
                ?? NSScreen.main else { return }
        let f = screen.frame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2,
                                     y: f.maxY - IslandConst.topReservation - 10 - size.height))
    }

    private func watch() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.keyCode == 53, self?.isOpen == true else { return e }
            self?.close()
            return nil
        }
        // Only while it is open, so a panel nobody has asked for costs nothing.
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in await AgentsStore.shared.refresh() }
        }
    }
}

#endif
