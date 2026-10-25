import SwiftUI
// The AI Agents dashboard reads Claude Code's transcripts under
// ~/.claude/projects. The App Store build is containerised and cannot
// reach them, so the whole feature compiles out there rather than
// shipping a permanently empty panel.
#if !APPSTORE

// MARK: - Sparkles glyph
//
// Three four-pointed stars with concave waists, matching the supplied icon.
// Drawn rather than shipped as an asset, per the project's no-images rule.
//
// The centres and radii below were measured off the reference bitmap and then
// checked by rasterising this exact path back down to the reference's 45x37
// grid and diffing the two. Coordinates are normalised to the glyph's own
// bounding box, which is taller than it is wide.

struct SparklesShape: Shape {
    /// Width / height of the glyph's natural bounding box.
    static let aspect: CGFloat = 0.818

    /// cx, cy, rx, ry — all fractions of the bounding box.
    private static let sparks: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0.579, 0.636, 0.421, 0.364),   // large, lower right
        (0.208, 0.332, 0.208, 0.174),   // medium, mid left
        (0.470, 0.097, 0.109, 0.097),   // small, top
    ]

    /// How far the curve's control point sits from the centre toward the
    /// corner between two tips. Smaller pinches the waist and sharpens the
    /// spikes; 0.20 is what reproduces the reference.
    private static let waist: CGFloat = 0.20

    func path(in rect: CGRect) -> Path {
        // Fit the glyph inside rect without distorting it.
        let boxH = min(rect.height, rect.width / Self.aspect)
        let boxW = boxH * Self.aspect
        let originX = rect.midX - boxW / 2
        let originY = rect.midY - boxH / 2

        var path = Path()
        for (fx, fy, frx, fry) in Self.sparks {
            let cx = originX + fx * boxW
            let cy = originY + fy * boxH
            let rx = frx * boxW
            let ry = fry * boxH

            let tips = [
                CGPoint(x: cx,      y: cy - ry),
                CGPoint(x: cx + rx, y: cy),
                CGPoint(x: cx,      y: cy + ry),
                CGPoint(x: cx - rx, y: cy),
            ]
            path.move(to: tips[0])
            for i in 0..<4 {
                let a = tips[i]
                let b = tips[(i + 1) % 4]
                let control = CGPoint(
                    x: cx + (a.x - cx + b.x - cx) * Self.waist * 0.5,
                    y: cy + (a.y - cy + b.y - cy) * Self.waist * 0.5)
                path.addQuadCurve(to: b, control: control)
            }
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Satellite button

/// The sparkles mark the ring draws for `IslandEdgeAction.agentsDashboard`,
/// circled by how much of the Claude Code plan has been spent.
///
/// A mark and not a button: the ring supplies the disc, the border, the hover
/// and the click, exactly as it does for every other button on the island's
/// edge. The circle reads the same `PlanUsage` the dashboard card does, so it
/// inherits that type's clamping, its "reset time has passed" rule and its
/// colour thresholds rather than restating them.
///
/// The shape is Claude Code's own usage ring, measured off a screenshot rather
/// than guessed at: a full dim track with the spent arc over it, starting at
/// twelve o'clock and running clockwise with round caps. Claude Code draws it
/// at 18.5 pt across with a 3 pt stroke — a ratio of about 0.16, which is what
/// `Self.stroke` keeps against this larger disc. The arc alone, with no track
/// under it, reads as a stray mark rather than a gauge, which is why the track
/// is drawn even when there is no reading at all.
///
/// It follows the **worst** window rather than the session, which is also what
/// Claude Code does: measuring its arc gave 53.6 % against a session at 21 %
/// and a week at 55 %. A ring that ignored the week would sit green while the
/// account was nearly out.
struct AgentsDashboardGlyph: View {
    @ObservedObject var state: AppState
    /// The disc the ring already drew, so the arc lands on its edge.
    var disc: CGFloat

    /// Stroke against the mark's full width. Claude Code's own is 6 px on 37 at
    /// 2×, a ratio of 0.16; this is pulled back because the island's chrome is
    /// 1 pt lines throughout and the measured weight sat on the button like a
    /// collar.
    private static let strokeRatio: CGFloat = 0.11
    /// The track's grey, as Claude Code draws it.
    private static let trackColor = Color(hex: "#676767")

    private var stroke: CGFloat { (disc * Self.strokeRatio).rounded() }
    /// The path the stroke is centred on, inset by half the stroke at each
    /// side so the ring's outer edge lands exactly on the disc. Framing the
    /// circle at the full width instead pushes half the stroke outside the
    /// button, which a render measured at 36 pt on a 34 pt disc.
    private var ring: CGFloat { disc - stroke }

    private var percent: Double? {
        guard let usage = state.claudePlanUsage else { return nil }
        return ClaudePlanGauge.dominantPct(usage)
    }

    private var ringColor: Color {
        Color(hex: ClaudePlanGauge.color(for: percent))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Self.trackColor, lineWidth: stroke)
                .frame(width: ring, height: ring)

            if let pct = percent, pct > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(min(100, pct) / 100))
                    .stroke(ringColor,
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: ring, height: ring)
                    .animation(.spring(response: 0.5, dampingFraction: 0.9), value: pct)
            }

            SparklesShape()
                .fill(Color(hex: "#F5F6F8"))
                .frame(width: disc * 0.42, height: disc * 0.52)
        }
        .frame(width: disc, height: disc)
        // The ring is only ever on screen while the island is open, so this is
        // also the whole lifetime of the network polling behind it.
        .onAppear { ClaudePlanAPIPoller.shared.retain() }
        .onDisappear { ClaudePlanAPIPoller.shared.release() }
    }
}

#endif
