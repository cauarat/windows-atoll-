import AppKit
import SwiftUI

/// The Clipboard Manager, in a window of its own.
///
/// Not a tab in the island: a list you search and scroll wants more room than
/// the island's 640 × 240, and it wants the keyboard, which the island's panel
/// refuses by design so it never steals focus from what you are typing in.
///
/// Borderless and rounded, like the reference. It can become key — the search
/// field is the whole point — but the app stays an accessory, so opening it
/// does not pull you out of whatever is in front.
@MainActor
final class ClipboardPanelController {
    static let shared = ClipboardPanelController()

    private var panel: NSPanel?
    private var escapeMonitor: Any?
    private var outsideMonitor: Any?

    private init() {}

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { isOpen ? close() : open() }

    func open() {
        // Watching starts when the manager is first opened: having asked to see
        // the clipboard is the clearest statement that you want it kept.
        ClipboardStore.shared.start()

        if let panel {
            place(panel)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: ClipboardPanelView())
        host.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        self.panel = panel
        place(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        watchForDismissal()
    }

    func close() {
        panel?.orderOut(nil)
        stopWatching()
    }

    /// Under the island, on the display it is on, so it opens where you were
    /// already looking.
    private func place(_ panel: NSPanel) {
        let chosen = IslandDisplays.chosenScreens(NSScreen.screens,
                                                  selection: AppState.shared.displaySelection)
        guard let screen = IslandDisplays.activeScreen(chosen, cursor: NSEvent.mouseLocation)
                ?? NSScreen.main else { return }
        let f = screen.frame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: f.midX - size.width / 2,
            // Clear of the island's own 320 pt, with a little air.
            y: f.maxY - 330 - size.height
        ))
    }

    // MARK: – Dismissal

    private func watchForDismissal() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 53 is Escape. Returning nil swallows it so nothing else reacts.
            guard event.keyCode == 53, self?.isOpen == true else { return event }
            self?.close()
            return nil
        }
        // Clicking anywhere else puts it away, the way a popover behaves.
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func stopWatching() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        escapeMonitor = nil
        outsideMonitor = nil
    }
}

// MARK: - The view

struct ClipboardPanelView: View {
    @ObservedObject private var store = ClipboardStore.shared

    @State private var query = ""
    @State private var showingFavourites = false
    /// The row that was just put back on the clipboard, so it can say so.
    @State private var justCopied: UUID?

    private var shown: [ClipEntry] {
        (showingFavourites ? store.favourites : store.entries).filter { $0.matches(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            search
            Divider().overlay(Color.white.opacity(0.08))
            list
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#1C1C1E"))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: – Header

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: { ClipboardPanelController.shared.close() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#FF5F57"))
            }
            .buttonStyle(.plain)

            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#E8E9EC"))

            Text("Clipboard Manager")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))

            Spacer(minLength: 0)

            Button(action: { store.clear() }) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "#FF453A"))
            }
            .buttonStyle(.plain)
            .help("Forget everything")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var tabs: some View {
        HStack(spacing: 10) {
            tab("History", system: "clock", count: store.entries.count, on: !showingFavourites) {
                showingFavourites = false
            }
            tab("Favorites", system: "heart.fill", count: nil, on: showingFavourites) {
                showingFavourites = true
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func tab(_ title: String, system: String, count: Int?,
                     on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: system).font(.system(size: 11))
                Text(title).font(.system(size: 13, weight: .medium))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(on ? 0.25 : 0.0))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(on ? .white : Color(hex: "#9398A1"))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(on ? Color(hex: "#0A84FF") : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private var search: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#8E939C"))
            TextField("Search clipboard…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#F5F6F8"))
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // MARK: – List

    @ViewBuilder private var list: some View {
        if !store.watching {
            message("Coucou is not watching the clipboard yet.")
        } else if shown.isEmpty {
            message(query.isEmpty
                    ? (showingFavourites ? "Nothing kept yet." : "Copy something and it shows up here.")
                    : "Nothing matches.")
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { entry in
                        ClipPanelRow(entry: entry, justCopied: $justCopied)
                    }
                }
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Color(hex: "#6B7079"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One row. Clicking it puts the entry back on the clipboard and says so.
private struct ClipPanelRow: View {
    let entry: ClipEntry
    @Binding var justCopied: UUID?
    @State private var isHovered = false

    private var copied: Bool { justCopied == entry.id }

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: copied ? "#34D399" : "#F5F6F8"))
                    .lineLimit(1).truncationMode(.tail)
                Text(copied ? "Copied" : entry.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: copied ? "#34D399" : "#8E939C"))
            }
            Spacer(minLength: 6)
            if isHovered && !copied {
                actions
            } else {
                Text(copied ? "" : ClipEntry.ago(entry.copiedAt))
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            copied ? Color(hex: "#34D399").opacity(0.14)
                   : (isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { copy() }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.18), value: copied)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: { ClipboardStore.shared.toggleFavourite(entry) }) {
                Image(systemName: entry.favourite ? "heart.fill" : "heart")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: entry.favourite ? "#FF375F" : "#9398A1"))
            }
            .buttonStyle(.plain)
            Button(action: { copy() }) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#30D158"))
            }
            .buttonStyle(.plain)
            Button(action: { ClipboardStore.shared.remove(entry) }) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#FF453A"))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var icon: some View {
        switch entry.kind {
        case .image(let image, _):
            Image(nsImage: image)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .text:
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(hex: "#0A84FF"))
                Image(systemName: entry.subtitle == "Link" ? "link" : "text.alignleft")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }
            .frame(width: 26, height: 26)
        }
    }

    /// Puts it back, then says so on the row itself for a moment — the feedback
    /// belongs where the eye already is, not in a corner of the window.
    private func copy() {
        ClipboardStore.shared.copy(entry)
        justCopied = entry.id
        let id = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            if justCopied == id { justCopied = nil }
        }
    }
}
