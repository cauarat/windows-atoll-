import AppKit
import SwiftUI

/// What a wedge of the radial menu does.
///
/// Only things Notchy can already do. A wheel that offered screenshots or a
/// volume slider would be promising capabilities the app does not have, and the
/// point of putting it on the mouse is reaching what is here in one gesture.
enum RadialAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case openIsland, clipboard, timer, playPause, nextTrack, previousTrack
    case muteSounds, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openIsland:    return "Open Notchy"
        case .clipboard:     return "Clipboard"
        case .timer:         return "Focus timer"
        case .playPause:     return "Play / Pause"
        case .nextTrack:     return "Next"
        case .previousTrack: return "Previous"
        case .muteSounds:    return "Sounds"
        case .settings:      return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .openIsland:    return "capsule.fill"
        case .clipboard:     return "doc.on.clipboard"
        case .timer:         return "timer"
        case .playPause:     return "playpause.fill"
        case .nextTrack:     return "forward.fill"
        case .previousTrack: return "backward.fill"
        case .muteSounds:    return "speaker.wave.2"
        case .settings:      return "gearshape"
        }
    }

    /// Whether this is worth offering right now.
    ///
    /// An unavailable wedge greys out rather than disappearing: dropping it
    /// would move every wedge after it, and a radial menu is only quick
    /// because the same flick always means the same thing.
    @MainActor
    var isAvailable: Bool {
        switch self {
        case .playPause, .nextTrack, .previousTrack:
            #if APPSTORE
            return false
            #else
            return AppState.shared.activeIntegrations.contains("integration_music")
            #endif
        default:
            return true
        }
    }

    @MainActor
    func perform() {
        switch self {
        case .openIsland:
            AppDelegate.shared?.islandController?.expand(to: .overview)
        case .clipboard:
            ClipboardPanelController.shared.toggle()
        case .timer:
            FocusTimer.shared.isActive ? FocusTimer.shared.stop() : FocusTimer.shared.startFromPicker()
        case .muteSounds:
            AppState.shared.soundEnabled.toggle()
        case .settings:
            NotificationCenter.default.post(name: .openFullSettings, object: "island")
        case .playPause, .nextTrack, .previousTrack:
            #if !APPSTORE
            switch self {
            case .playPause:     NowPlayingController.shared.togglePlay()
            case .nextTrack:     NowPlayingController.shared.nextTrack()
            case .previousTrack: NowPlayingController.shared.previousTrack()
            default: break
            }
            #endif
        }
    }

    /// The wheel a first run gets. Six wedges, so each is a comfortable 60°.
    static let defaults: [RadialAction] =
        [.openIsland, .clipboard, .playPause, .nextTrack, .timer, .settings]
}
