import AppKit
import SwiftUI

/// Mochi at rest on a display that is not the one you are using.
///
/// There is exactly one *interactive* island — it follows the cursor between
/// displays and owns every view, the drop zone, the event monitors and the
/// sounds. These are the others: the resting bar and Mochi, and nothing else.
/// They take no mouse, subscribe to nothing and never expand, so several of them
/// cost no more than the drawing.
///
/// That split is what makes "Mochi on every display" affordable. Fully
/// independent islands would mean lifting `mode`, `view`, `isPinned` and the
/// upload flow off `AppState.shared`, giving every `NotificationCenter`
/// broadcast a target, and registering the `NSEvent` monitors once rather than
/// once per island — otherwise one Claude Code hook opens two cards and every
/// sound plays twice.
@MainActor
final class PassiveIslandController {

    let screenID: String
    private let panel: NSPanel

    init(screen: NSScreen, screenID: String) {
        self.screenID = screenID

        let geometry = IslandWindowController.screenGeometry(for: screen)
        let sf = screen.frame
        // Only as tall as the resting bar: nothing here ever expands, so there
        // is no reason to hold a 320 pt panel over someone's menu bar.
        let height = max(geometry.height, 1)
        panel = NSPanel(
            contentRect: NSRect(x: sf.midX - geometry.width / 2, y: sf.maxY - height,
                                width: geometry.width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Always: this island is scenery. Every click goes to whatever is under it.
        panel.ignoresMouseEvents = true

        let hosting = NSHostingView(
            rootView: PassiveIslandView(geometry: geometry).environmentObject(AppState.shared)
        )
        hosting.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    func show() { panel.orderFrontRegardless() }

    /// Always called before the controller is dropped, by `refreshIslands()` and
    /// by the master switch. Deliberately not a `deinit`: `deinit` on a
    /// `@MainActor` class is not guaranteed to run on the main actor, so taking
    /// the panel away there would mean either a hop or a trap during teardown.
    func hide() { panel.orderOut(nil) }
}

/// The resting island: the black bar that melts into the screen edge, with Mochi
/// in it. The expanded views live on the interactive island and never come here.
struct PassiveIslandView: View {
    /// Injected, not read from `AppState`: a notched laptop and an external
    /// monitor measure differently, and the global copy describes whichever
    /// screen the interactive island is on.
    let geometry: IslandScreenGeometry

    @EnvironmentObject var state: AppState

    private var layout: IslandRestingLayout {
        IslandRestingLayout(width: geometry.width, height: geometry.height)
    }

    /// Off, or with nothing to say, the bar is not drawn at all — which is also
    /// what stops Mochi animating here. CLAUDE.md asks for 0 % CPU when the
    /// island is hidden, and that has to hold on every display, not just one.
    private var visible: Bool {
        state.isEnabled && state.mode != .hidden
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if visible {
                ZStack(alignment: .topLeading) {
                    // Square at the top so it flows into the screen edge,
                    // rounded below — the resting shape the island already has.
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: IslandConst.roundedCorner,
                        bottomTrailingRadius: IslandConst.roundedCorner
                    )
                    .fill(Color.black)
                    .frame(width: layout.width, height: layout.height)

                    BotCanvasView(state: state)
                        .frame(width: layout.botDiameter, height: layout.botDiameter)
                        .offset(x: 12, y: layout.botCenterY - layout.botDiameter / 2)
                        .allowsHitTesting(false)
                }
                .frame(width: layout.width, height: layout.height)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(IslandMotion.forGrowing(visible), value: visible)
    }
}
