import CoreGraphics
import Foundation

/// Where the island sits on screen, and what that means inside the panel.
///
/// Two kinds of position. Six names put the island against an edge of the
/// display; a dropped point puts it anywhere at all — see `FreePoint` below.
/// `IslandAnchor.resolve` turns either into the one shape the window controller
/// draws from, so nothing downstream has to know which it was given.
///
/// A port of `windows/src/core/anchor.ts`, value for value, and kept that way by
/// `scripts/test-island-anchor.sh` — which runs the cases here and then checks
/// the TypeScript answers the same. Free of AppKit on purpose, like
/// `IslandScreenGeometry` and `IslandDisplays`, so it can be compiled and
/// asserted with no display attached.
enum IslandAnchor {

    // MARK: – The two kinds of position

    /// The screen edge the island hugs and retracts into.
    enum Edge: String, Sendable {
        case top, bottom
    }

    /// Where along that edge it sits.
    enum Align: String, Sendable {
        case left, centre, right
    }

    /// Prefix of a dropped point, as written into the preference.
    static let freePrefix = "free:"

    /// The notch, which is where Mochi lives.
    ///
    /// Deliberately not the same default as the PC, where `anchor.ts` and
    /// `settings.rs` say bottom-right: there is no notch on a PC, so the island
    /// goes next to the clock where the notifications already are. Here the
    /// notch is the whole idea, and an island that starts anywhere else reads
    /// as a broken app rather than as a setting nobody chose.
    static let defaultPosition = "top-centre"

    /// The six names and what to call them, in the order Settings shows them.
    /// The same list as `POSITIONS` in windows/src/core/anchor.ts.
    static let presets: [(String, String)] = [
        ("top-left", "Top left"),
        ("top-centre", "Top centre"),
        ("top-right", "Top right"),
        ("bottom-left", "Bottom left"),
        ("bottom-centre", "Bottom centre"),
        ("bottom-right", "Bottom right"),
    ]

    /// How near an edge a drop still counts as *on* that edge, in points.
    ///
    /// Inside it the island hugs the edge the way it always has — square corners
    /// bleeding into the bezel, growing out of it. That look is most of what the
    /// island is, so it is worth a band this wide to land on.
    static let magnet: CGFloat = 48

    /// The two sizes the free arithmetic needs.
    ///
    /// `rest` is the island's resting footprint, which is what a drop is aiming
    /// with — on a Mac that is the notch, which every display measures for
    /// itself, so it is passed in rather than written down.
    struct Metrics: Equatable, Sendable {
        var rest: CGSize
        var panel: CGSize
    }

    /// Where a dropped island rests: its centre, as a fraction of the work area.
    ///
    /// Fractions, because of what they do across displays: the same pair on a
    /// screen of another size or another scale is the same place, so the island
    /// reappears where it was put on whichever display the cursor is on. Points
    /// would need one position per monitor and would land somewhere else the
    /// moment one is resized.
    struct FreePoint: Equatable, Sendable {
        var fx: CGFloat
        var fy: CGFloat
    }

    // MARK: – Reading and writing the preference

    /// Mirrors `edgeOf` in anchor.ts: anything unknown falls back to the default.
    static func edge(of p: String) -> Edge {
        p.hasPrefix("top-") ? .top : .bottom
    }

    static func align(of p: String) -> Align {
        if p.hasSuffix("-left") { return .left }
        // Both spellings, so a hand-edited preference still works.
        if p.hasSuffix("-centre") || p.hasSuffix("-center") { return .centre }
        return .right
    }

    static func isFree(_ p: String) -> Bool { p.hasPrefix(freePrefix) }

    /// `free:0.734,0.882` → the point. Anything malformed reads as not-free.
    static func parseFree(_ p: String) -> FreePoint? {
        guard p.hasPrefix(freePrefix) else { return nil }
        let parts = p.dropFirst(freePrefix.count).split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let fx = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let fy = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              fx.isFinite, fy.isFinite
        else { return nil }
        return FreePoint(fx: CGFloat(min(max(fx, 0), 1)), fy: CGFloat(min(max(fy, 0), 1)))
    }

    /// Four decimals: a point on an 8K display, and short enough to read in a file.
    static func formatFree(_ fx: CGFloat, _ fy: CGFloat) -> String {
        func r(_ n: CGFloat) -> String {
            let v = (min(max(n, 0), 1) * 10_000).rounded() / 10_000
            // Trailing zeros dropped, so the three ports write the same string.
            return v == v.rounded() ? String(Int(v)) : String(Double(v))
        }
        return "\(freePrefix)\(r(fx)),\(r(fy))"
    }

    // MARK: – Where a drop lands

    /// The screen edge a dropped point is near enough to hug, or nil out in the open.
    ///
    /// Kept apart from `nearestPreset` on purpose: an island dropped along the
    /// top edge but nowhere near left, centre or right is still a free island —
    /// it just hugs the edge while it is there.
    static func hug(fy: CGFloat, areaH: CGFloat, metrics: Metrics) -> Edge? {
        let y = fy * areaH
        if y - metrics.rest.height / 2 <= magnet { return .top }
        if areaH - (y + metrics.rest.height / 2) <= magnet { return .bottom }
        return nil
    }

    /// The preset a drop lands on, or nil to keep it free.
    ///
    /// Both axes have to agree. Snapping on the edge alone would quietly take
    /// away free placement along that edge, which is the thing being added.
    static func nearestPreset(
        fx: CGFloat, fy: CGFloat, areaW: CGFloat, areaH: CGFloat, metrics: Metrics,
    ) -> String? {
        guard let edge = hug(fy: fy, areaH: areaH, metrics: metrics) else { return nil }
        let x = fx * areaW
        let half = metrics.rest.width / 2
        let align: Align
        if x - half <= magnet {
            align = .left
        } else if areaW - (x + half) <= magnet {
            align = .right
        } else if abs(x - areaW / 2) <= magnet {
            align = .centre
        } else {
            return nil
        }
        return "\(edge.rawValue)-\(align.rawValue)"
    }

    /// What a drop at `centre` — the resting island's centre, in work-area
    /// points — is stored as: one of the six names when it lands on one, else
    /// the point itself.
    static func positionForDrop(
        centre: CGPoint, areaW: CGFloat, areaH: CGFloat, metrics: Metrics,
    ) -> String {
        let fx = areaW > 0 ? centre.x / areaW : 0.5
        let fy = areaH > 0 ? centre.y / areaH : 0.5
        return nearestPreset(fx: fx, fy: fy, areaW: areaW, areaH: areaH, metrics: metrics)
            ?? formatFree(fx, fy)
    }

    // MARK: – Placing a dropped island

    /// Panel origin and island offsets for a dropped point, in work-area points.
    ///
    /// Everything here is y-down from the work area's top-left, like the web and
    /// unlike AppKit — the three ports have to agree pixel for pixel, and the
    /// one flip at the call site is cheaper than three sets of arithmetic.
    struct FreeGeometry: Equatable, Sendable {
        /// Panel origin inside the work area.
        var winX: CGFloat
        var winY: CGFloat
        /// The island's resting centre x, inside the panel.
        var offX: CGFloat
        /// The island's pinned edge y, inside the panel.
        var offY: CGFloat
        /// Which of the island's own edges is pinned: `.top` grows down, `.bottom` up.
        var grow: Edge
    }

    /// The whole of free placement, as one function.
    ///
    /// The island grows away from the half it was dropped in, so a point near
    /// the bottom unfolds upward into the room that is there rather than off the
    /// screen. The panel is clamped to the work area; the island is then clamped
    /// inside the panel by `islandX`/`islandY`, which is what makes a wide view
    /// slide inward near an edge instead of hanging off it.
    static func freeGeometry(
        fx: CGFloat, fy: CGFloat, areaW: CGFloat, areaH: CGFloat, metrics: Metrics,
    ) -> FreeGeometry {
        let halfW = metrics.rest.width / 2
        let halfH = metrics.rest.height / 2
        let cx = min(max(fx * areaW, halfW), max(halfW, areaW - halfW))
        let cy = min(max(fy * areaH, halfH), max(halfH, areaH - halfH))
        let grow: Edge = cy < areaH / 2 ? .top : .bottom
        let edgeY = grow == .top ? cy - halfH : cy + halfH
        let winX = fit(cx - metrics.panel.width / 2, area: areaW, size: metrics.panel.width)
        let rawY = grow == .top ? edgeY : edgeY - metrics.panel.height
        let winY = fit(rawY, area: areaH, size: metrics.panel.height)
        return FreeGeometry(winX: winX, winY: winY, offX: cx - winX, offY: edgeY - winY, grow: grow)
    }

    /// A panel larger than the display pins to the near corner rather than drifting.
    private static func fit(_ v: CGFloat, area: CGFloat, size: CGFloat) -> CGFloat {
        size >= area ? 0 : min(max(v, 0), area - size)
    }

    // MARK: – What the island reads

    /// A position resolved against a display: the one shape the island draws from.
    struct Resolved: Equatable, Sendable {
        /// The island's own pinned edge. `.top` grows down, `.bottom` grows up.
        var edge: Edge
        var align: Align
        /// The screen edge it is pressed against, or nil when it floats free.
        var hug: Edge?
        /// Set for a dropped point; nil for one of the six names.
        var free: FreeGeometry?
    }

    /// Resolves a stored position against the work area it will be placed in.
    ///
    /// The area is only read for a dropped point, so the six names still answer
    /// before any display has been measured.
    static func resolve(
        _ p: String, areaW: CGFloat, areaH: CGFloat, metrics: Metrics,
    ) -> Resolved {
        guard let pt = parseFree(p) else {
            let e = edge(of: p)
            return Resolved(edge: e, align: align(of: p), hug: e, free: nil)
        }
        let free = freeGeometry(fx: pt.fx, fy: pt.fy, areaW: areaW, areaH: areaH, metrics: metrics)
        return Resolved(
            edge: free.grow,
            align: .centre,
            hug: hug(fy: pt.fy, areaH: areaH, metrics: metrics),
            free: free)
    }

    /// Island x inside the panel, for an island `w` wide.
    static func islandX(_ a: Resolved, w: CGFloat, metrics: Metrics) -> CGFloat {
        if let free = a.free {
            return min(max(free.offX - w / 2, 0), max(0, metrics.panel.width - w))
        }
        switch a.align {
        case .left:   return 0
        case .centre: return (metrics.panel.width - w) / 2
        case .right:  return metrics.panel.width - w
        }
    }

    /// Island y inside the panel, y-down, for an island `h` tall.
    ///
    /// At the bottom this is rewritten as `h` changes, which is what makes the
    /// island grow upward out of the edge and retract back into it.
    static func islandY(_ a: Resolved, h: CGFloat, metrics: Metrics) -> CGFloat {
        if let free = a.free {
            let y = a.edge == .top ? free.offY : free.offY - h
            return min(max(y, 0), max(0, metrics.panel.height - h))
        }
        return a.edge == .top ? 0 : metrics.panel.height - h
    }
}
