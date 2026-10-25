import AppKit
import SwiftUI

/// What an edge button can be besides a pill.
///
/// Kept apart from `RadialAction` on purpose: the wheel is for what you do
/// often enough to learn a flick for, and the ring is for what you want in
/// sight. The two overlap but they are not the same list, and collapsing them
/// would mean every wedge had to earn a place on the island's border too.
enum IslandEdgeAction: String, CaseIterable, Identifiable {
    case agents, clipboard, timer, settings, site, agentsDashboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agents:    return "AI Agents"
        case .clipboard: return "Clipboard"
        case .timer:     return "Focus timer"
        case .settings:  return "Settings"
        case .site:      return NotchSite.hostLabel
        case .agentsDashboard: return "AI dashboard"
        }
    }

    var icon: String {
        switch self {
        case .agents:    return "sparkles"
        case .clipboard: return "doc.on.clipboard"
        case .timer:     return "timer"
        case .settings:  return "gearshape"
        case .site:      return "globe"
        case .agentsDashboard: return "sparkles"
        }
    }

    var colorHex: String {
        switch self {
        case .agents:    return "#E07950"
        case .clipboard: return "#8AB4F8"
        case .timer:     return "#F5A524"
        case .settings:  return "#8E939C"
        case .site:      return "#38BDF8"
        case .agentsDashboard: return "#F5F6F8"
        }
    }

    /// Whether it is worth offering. An unavailable one still draws, dimmed,
    /// rather than moving everything after it.
    @MainActor
    var isAvailable: Bool {
        switch self {
        case .agents:
            #if APPSTORE
            return false
            #else
            return AppState.shared.showAgentsPanel
            #endif
        case .agentsDashboard:
            // The dashboard reads Claude Code's transcripts, which the
            // containerised build cannot reach: it compiles out entirely there.
            #if APPSTORE
            return false
            #else
            return true
            #endif
        default: return true
        }
    }

    @MainActor
    func perform() {
        switch self {
        case .agents:
            #if !APPSTORE
            AgentsPanelController.shared.toggle()
            #endif
        case .clipboard: ClipboardPanelController.shared.toggle()
        case .timer:
            FocusTimer.shared.isActive ? FocusTimer.shared.stop() : FocusTimer.shared.startFromPicker()
        case .settings:
            NotificationCenter.default.post(name: .openFullSettings, object: "island")
        case .site:
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.web)
        case .agentsDashboard:
            // Same notification the sparkles satellite used to post, so the
            // controller still toggles it through the FSM as a deliberate open.
            #if !APPSTORE
            NotificationCenter.default.post(name: .openAgentsDashboard, object: nil)
            #endif
        }
    }
}
