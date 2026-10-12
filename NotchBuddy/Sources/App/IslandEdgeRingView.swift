import SwiftUI

/// The buttons around the island's border.
///
/// Drawn as a sibling of the island rather than inside it, because the island
/// clips its own content and these sit outside it. It takes the island's
/// animated size and positions everything from that, so one spring moves the
/// shape and the ring together — which is what makes them read as one object
/// instead of two that happen to agree.
struct IslandEdgeRingView: View {
    @ObservedObject var state: AppState
    let islandSize: CGSize

    var body: some View {
        let buttons = IslandEdgeLayout.visible(state.edgeButtons,
                                               expanded: state.mode == .expanded)
        ZStack(alignment: .topLeading) {
            ForEach(IslandEdgeSide.allCases, id: \.self) { side in
                let onSide = IslandEdgeLayout.buttons(buttons, on: side)
                ForEach(Array(onSide.enumerated()), id: \.element.id) { index, button in
                    let c = IslandEdgeLayout.center(side: side, index: index, count: onSide.count,
                                                    islandWidth: islandSize.width,
                                                    islandHeight: islandSize.height)
                    IslandEdgeButtonView(action: button.action, state: state)
                        .position(x: c.x, y: c.y)
                        // Just behind the shape, so the ring unfurls from the
                        // island rather than arriving with it.
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
        }
        .frame(width: islandSize.width, height: islandSize.height, alignment: .topLeading)
        .allowsHitTesting(state.isEnabled)
        .animation(IslandMotion.open, value: state.mode)
    }
}

/// One button. A pill's colour and its symbol on the island's own black.
private struct IslandEdgeButtonView: View {
    let action: String
    @ObservedObject var state: AppState
    @State private var hovering = false

    private var pill: PillDefinition? { PillCatalog.definition(for: action) }
    private var builtIn: IslandEdgeAction? { IslandEdgeAction(rawValue: action) }

    private var tintHex: String { pill?.color ?? builtIn?.colorHex ?? "#8E939C" }
    private var symbol: String { pill?.icon ?? builtIn?.icon ?? "circle.fill" }
    private var label: String { pill?.name ?? builtIn?.title ?? action }

    var body: some View {
        let tint = Color(hex: tintHex)
        Button {
            if let builtIn { builtIn.perform() } else { openPill(action) }
        } label: {
            ZStack {
                Circle().fill(Color(hex: "#0E0F11"))
                Circle().strokeBorder(tint.opacity(hovering ? 0.75 : 0.22), lineWidth: 1)
                glyph(tint)
            }
            .frame(width: IslandEdgeLayout.diameter, height: IslandEdgeLayout.diameter)
            .scaleEffect(hovering ? 1.08 : 1)
            .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .help(label)
        .onHover { h in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { hovering = h }
        }
    }

    private var initial: String { String(label.prefix(1)).uppercased() }

    /// How large a drawn mark sits on the disc.
    ///
    /// Larger than the 13 pt symbols beside it on purpose: a symbol carries its
    /// own optical padding and a path fills its box edge to edge, so matching
    /// the numbers would not match the sizes.
    private static let logoSide: CGFloat = 16

    @ViewBuilder
    private func glyph(_ tint: Color) -> some View {
        if let logo = pill?.logo {
            // No initial underneath: that is a net for a symbol name macOS
            // might not know, and a path always draws. The mark keeps its own
            // colours rather than taking the pill's — it is artwork, not a
            // symbol, and tinting it would be drawing someone else's logo
            // wrong. The disc's border is still the pill's colour, so the
            // button stays in family with its neighbours.
            //
            // Simplified at this size: the bubble behind would cost the front
            // one a quarter of its width to make room, and the smile with it.
            // Two competing blobs is not the mark; the bubble and its smile is.
            logo.view(side: Self.logoSide, detail: .simplified)
                // This disc is near-black whatever the system appearance is, so
                // a mark that inverts for dark surfaces has to be told; one
                // with fixed colours ignores it.
                .environment(\.colorScheme, .dark)
        } else if builtIn == .agentsDashboard {
            // Keeps the mark it had as a satellite, and the circle of session
            // spend around it: that reading is the reason to glance at it, and
            // a plain `sparkles` symbol would throw it away.
            #if !APPSTORE
            AgentsDashboardGlyph(state: state, disc: IslandEdgeLayout.diameter)
            #endif
        } else if builtIn == .site {
            // The site has a mark of its own, so it draws that instead of a
            // symbol. No initial underneath, for the same reason the pill
            // marks go without one: a path always draws.
            NotchSiteGlyph(side: 17, ink: tint)
                .background(Circle().fill(Color(hex: "#0E0F11")).frame(width: 22, height: 22))
        } else {
            // A symbol macOS does not know draws nothing at all, so the
            // initial sits underneath it rather than instead of it: the
            // button is never blank, whatever happens to the symbol name.
            ZStack {
                Text(initial)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(tint.opacity(0.9))
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(tint)
                    .background(Circle().fill(Color(hex: "#0E0F11")).frame(width: 22, height: 22))
            }
        }
    }
}
