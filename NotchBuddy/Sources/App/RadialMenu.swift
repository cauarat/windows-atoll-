import AppKit
import SwiftUI

/// The wheel: a panel at the pointer, open while the chord is held.
///
/// It reads the pointer and the buttons rather than waiting for events, because
/// the tap that opened it is swallowing exactly those events — that is what
/// stops a context menu appearing behind the wheel. One 60 Hz timer, running
/// only while it is open.
@MainActor
final class RadialMenuController: NSObject {

    static let shared = RadialMenuController()

    private var panel: NSPanel?
    private var poll: Timer?
    private var escapeMonitor: Any?
    /// Set once the pointer leaves the dead zone. Until it does, letting go
    /// commits nothing and the wheel stays up for a deliberate click instead.
    private var committed = false
    private let model = RadialMenuModel()

    var isOpen: Bool { panel != nil }

    func open() {
        guard AppState.shared.radialEnabled, !isOpen else { return }
        let actions = AppState.shared.radialActions
        guard actions.count >= RadialGeometry.minWedges else { return }

        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let screen else { return }

        let centre = RadialGeometry.center(for: pointer, on: screen.visibleFrame)
        let side = RadialGeometry.panelSide
        model.actions = actions
        model.hovered = nil
        model.centre = centre
        committed = false

        let p = NSPanel(contentRect: NSRect(x: centre.x - side / 2, y: centre.y - side / 2,
                                            width: side, height: side),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        // Above the clipboard panel, below the island: the wheel is a passing
        // thing and the island is where it sends you.
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.ignoresMouseEvents = true
        p.contentView = NSHostingView(rootView: RadialMenuView(model: model))
        p.orderFrontRegardless()
        panel = p

        SoundEngine.shared.play("peek")
        poll = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { Task { @MainActor in self?.close(commit: false) } }
        }
    }

    private func tick() {
        guard isOpen else { return }
        let p = NSEvent.mouseLocation
        let w = RadialGeometry.wedge(dx: p.x - model.centre.x, dy: p.y - model.centre.y,
                                     count: model.actions.count)
        if w != nil { committed = true }
        if model.hovered != w {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { model.hovered = w }
        }

        let left = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let right = CGEventSource.buttonState(.combinedSessionState, button: .right)
        if !left && !right {
            // Let go having aimed: run it. Let go without aiming: stay up, so
            // the wheel can also be used by clicking rather than flicking.
            if committed { close(commit: true) }
        }
    }

    func close(commit: Bool) {
        guard let p = panel else { return }
        let chosen = commit ? model.hovered.map { model.actions[$0] } : nil
        poll?.invalidate(); poll = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        p.orderOut(nil)
        panel = nil
        if let chosen, chosen.isAvailable {
            SoundEngine.shared.play("blip")
            // After the panel is gone, so an action that activates another app
            // does not race the teardown.
            DispatchQueue.main.async { chosen.perform() }
        }
    }
}

@MainActor
final class RadialMenuModel: ObservableObject {
    @Published var actions: [RadialAction] = []
    @Published var hovered: Int?
    var centre: CGPoint = .zero
}

/// The wedges.
struct RadialMenuView: View {
    @ObservedObject var model: RadialMenuModel

    var body: some View {
        let side = RadialGeometry.panelSide
        ZStack {
            ForEach(Array(model.actions.enumerated()), id: \.offset) { i, action in
                let on = model.hovered == i
                let a = RadialGeometry.angle(of: i, count: model.actions.count)
                // The panel is a SwiftUI view, where y grows down; the angles
                // are in the screen's y-up convention, so the sign flips here
                // and nowhere else.
                let r = (RadialGeometry.outerRadius + RadialGeometry.innerRadius) / 2
                ZStack {
                    Circle()
                        .fill(on ? Color(hex: "#2A2D33") : Color(hex: "#15171B"))
                        .frame(width: 52, height: 52)
                    Circle()
                        .strokeBorder(on ? Color(hex: "#3B9EFF").opacity(0.8)
                                         : Color.white.opacity(0.08), lineWidth: 1)
                        .frame(width: 52, height: 52)
                    Image(systemName: action.icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(action.isAvailable
                                         ? (on ? Color(hex: "#F5F6F8") : Color(hex: "#B0B5BE"))
                                         : Color(hex: "#5A5F68"))
                }
                .scaleEffect(on ? 1.12 : 1)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                .position(x: side / 2 + cos(a) * r, y: side / 2 - sin(a) * r)
            }

            // The dead zone, named. Letting go here does nothing.
            Circle()
                .fill(Color(hex: "#0E0F11").opacity(0.92))
                .frame(width: RadialGeometry.innerRadius * 1.5,
                       height: RadialGeometry.innerRadius * 1.5)
                .overlay(
                    Text(model.hovered.map { model.actions[$0].title } ?? "")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .multilineTextAlignment(.center)
                        .frame(width: 70)
                )
        }
        .frame(width: side, height: side)
    }
}
