import AppKit
import SwiftUI

/// What an edge button can be besides a pill.
///
/// Kept apart from `RadialAction` on purpose: the wheel is for what you do
/// often enough to learn a flick for, and the ring is for what you want in
/// sight. The two overlap but they are not the same list, and collapsing them
/// would mean every wedge had to earn a place on the island's border too.
enum IslandEdgeAction: String, CaseIterable, Identifiable {
    // `agents` (the AI Agents panel) went with the coding agents. A stored
    // button for it is dropped on load (`AppState.loadIntegrationTasks`).
    case clipboard, timer, settings, site
    /// Were tabs in the island's header. They hang underneath it now, which is
    /// why a fresh ring deals them onto `.bottom` (`IslandEdgeLayout.defaults`).
    case hydration, agenda

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .timer:     return "Focus timer"
        case .settings:  return "Settings"
        case .site:      return NotchSite.hostLabel
        case .hydration: return "Hydration"
        case .agenda:    return "Agenda"
        }
    }

    var icon: String {
        switch self {
        case .clipboard: return "doc.on.clipboard"
        case .timer:     return "timer"
        case .settings:  return "gearshape"
        case .site:      return "globe"
        case .hydration: return "drop.fill"
        case .agenda:    return "calendar"
        }
    }

    var colorHex: String {
        switch self {
        case .clipboard: return "#8AB4F8"
        case .timer:     return "#F5A524"
        case .settings:  return "#8E939C"
        case .site:      return "#38BDF8"
        // Hydration's colour in Settings; the Agenda card's own accent.
        case .hydration: return "#22D3EE"
        case .agenda:    return "#38BDF8"
        }
    }

    /// Whether it is worth offering. An unavailable one still draws rather than
    /// moving everything after it — except the Agenda, which is not drawn at
    /// all while it is off (`AppState.drawnEdgeButtons`), as its header tab was.
    @MainActor
    var isAvailable: Bool {
        switch self {
        case .agenda:
            // An Actuar tool, and off by default: a disc onto a sign-in prompt
            // is not something everyone should carry.
            #if APPSTORE
            return false
            #else
            return UserDefaults.standard.bool(forKey: AgendaSettings.enabledKey)
            #endif
        default: return true
        }
    }

    @MainActor
    func perform() {
        switch self {
        case .clipboard: ClipboardPanelController.shared.toggle()
        case .timer:
            FocusTimer.shared.isActive ? FocusTimer.shared.stop() : FocusTimer.shared.startFromPicker()
        case .settings:
            NotificationCenter.default.post(name: .openFullSettings, object: "island")
        case .site:
            NotificationCenter.default.post(name: .islandExpand, object: IslandView.web)
        case .hydration:
            // What the header tab did: opening it by hand ends whatever the
            // reminder card had moved on to say.
            HydrationStore.shared.clearPrompt()
            show(.hydration)
        case .agenda:
            show(.agenda)
        }
    }

    /// The ring is only drawn round the open island, so this switches the view
    /// in place, on the spring a header tab switches it with.
    @MainActor
    private func show(_ view: IslandView) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            AppState.shared.view = view
        }
    }
}
