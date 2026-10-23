import CoreGraphics
import Foundation

/// Where the island goes when it is dropped, over made-up displays.
///
/// `--dump` writes the same cases as a table for `island-anchor-parity.ts`:
/// three hand-kept ports of this arithmetic — Swift, TypeScript and Rust —
/// drift silently otherwise, and here that means the window ending up in one
/// place and the island drawn in another, which is an island nobody can click.
@main
enum IslandAnchorTests {

    static var failures = 0

    static func check(_ label: String, _ got: Any, _ expected: Any) {
        let g = String(describing: got), e = String(describing: expected)
        if g == e {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            print("    got:      \(g)")
            print("    expected: \(e)")
            failures += 1
        }
    }

    /// The PC metrics, so the table the TypeScript reads needs no conversion.
    static let m = IslandAnchor.Metrics(
        rest: CGSize(width: 288, height: 32),
        panel: CGSize(width: 760, height: 620))

    /// A 1080p screen with a 40 pt taskbar along the bottom.
    static let areaW: CGFloat = 1920
    static let areaH: CGFloat = 1040

    /// Drops worth naming: the corners, the middles, and the open field.
    static let drops: [(String, CGPoint)] = [
        ("top left", CGPoint(x: 150, y: 16)),
        ("top centre", CGPoint(x: 960, y: 16)),
        ("top right", CGPoint(x: 1770, y: 16)),
        ("bottom left", CGPoint(x: 150, y: 1024)),
        ("bottom centre", CGPoint(x: 960, y: 1024)),
        ("bottom right", CGPoint(x: 1770, y: 1024)),
        ("along the top, off to one side", CGPoint(x: 600, y: 16)),
        ("the open middle", CGPoint(x: 700, y: 500)),
        ("low but not on the edge", CGPoint(x: 1200, y: 900)),
        ("hard against the left, halfway down", CGPoint(x: 0, y: 520)),
    ]

    static func main() {
        if CommandLine.arguments.contains("--dump") { dump(); return }

        print("IslandAnchor — reading the preference")

        check("one of the six", IslandAnchor.isFree("bottom-right"), false)
        check("a dropped point", IslandAnchor.isFree("free:0.5,0.5"), true)
        check("both spellings of centre",
              IslandAnchor.align(of: "top-center"), IslandAnchor.Align.centre)
        check("a value from a newer build falls back rather than vanishing",
              IslandAnchor.parseFree("free:banana") == nil, true)
        check("a point out of range is pulled back in",
              IslandAnchor.parseFree("free:2,-1")!, IslandAnchor.FreePoint(fx: 1, fy: 0))
        check("written the way it is read",
              IslandAnchor.formatFree(0.73456, 0.88211), "free:0.7346,0.8821")

        print("\nIslandAnchor — where a drop lands")

        for (name, p) in drops {
            check(name, IslandAnchor.positionForDrop(
                centre: p, areaW: areaW, areaH: areaH, metrics: m), expectedPosition(name))
        }

        // The thing the magnet must not do: an island dropped along an edge but
        // nowhere near a corner is still free, or free placement along that edge
        // would have been quietly taken away.
        check("the edge alone does not snap",
              IslandAnchor.isFree(IslandAnchor.positionForDrop(
                  centre: CGPoint(x: 600, y: 16), areaW: areaW, areaH: areaH, metrics: m)), true)

        print("\nIslandAnchor — placing a dropped island")

        let mid = IslandAnchor.freeGeometry(
            fx: 0.5, fy: 0.25, areaW: areaW, areaH: areaH, metrics: m)
        check("the top half grows downward", mid.grow, IslandAnchor.Edge.top)
        check("the panel is centred on the drop", mid.winX, CGFloat(580))
        check("the island's centre lands on the drop", mid.winX + mid.offX, CGFloat(960))

        let low = IslandAnchor.freeGeometry(
            fx: 0.5, fy: 0.75, areaW: areaW, areaH: areaH, metrics: m)
        check("the bottom half grows upward", low.grow, IslandAnchor.Edge.bottom)
        check("the island's centre still lands on the drop",
              low.winY + low.offY - m.rest.height / 2, 0.75 * areaH)

        // Near an edge the panel stops at the work area, and the island slides
        // in rather than hanging off it.
        let edge = IslandAnchor.freeGeometry(
            fx: 0.02, fy: 0.5, areaW: areaW, areaH: areaH, metrics: m)
        check("the panel never leaves the work area", edge.winX, CGFloat(0))
        let wide = IslandAnchor.islandX(
            IslandAnchor.resolve("free:0.02,0.5", areaW: areaW, areaH: areaH, metrics: m),
            w: 640, metrics: m)
        check("a wide view slides inward instead of off the screen", wide >= 0, true)

        print("\nIslandAnchor — what the island draws")

        let free = IslandAnchor.resolve("free:0.5,0.5", areaW: areaW, areaH: areaH, metrics: m)
        check("out in the open it hugs nothing", free.hug == nil, true)
        let hugged = IslandAnchor.resolve("free:0.4,0.005", areaW: areaW, areaH: areaH, metrics: m)
        check("along the top edge it still hugs the top", hugged.hug == .top, true)
        let preset = IslandAnchor.resolve("bottom-right", areaW: areaW, areaH: areaH, metrics: m)
        check("a name hugs its own edge", preset.hug == .bottom, true)
        check("and is placed the way it always was",
              IslandAnchor.islandY(preset, h: 160, metrics: m), CGFloat(460))

        print(failures == 0 ? "\nAll good." : "\n\(failures) failed.")
        exit(failures == 0 ? 0 : 1)
    }

    /// The six names, then "free" for everything the magnet leaves alone.
    static func expectedPosition(_ name: String) -> String {
        switch name {
        case "top left": return "top-left"
        case "top centre": return "top-centre"
        case "top right": return "top-right"
        case "bottom left": return "bottom-left"
        case "bottom centre": return "bottom-centre"
        case "bottom right": return "bottom-right"
        default:
            let p = drops.first { $0.0 == name }!.1
            return IslandAnchor.formatFree(p.x / areaW, p.y / areaH)
        }
    }

    /// One row per drop: the name, the point, what it is stored as, and where
    /// that puts the panel and the island.
    static func dump() {
        print("area\t\(areaW)\t\(areaH)")
        print("metrics\t\(m.rest.width)\t\(m.rest.height)\t\(m.panel.width)\t\(m.panel.height)")
        for (name, p) in drops {
            let stored = IslandAnchor.positionForDrop(
                centre: p, areaW: areaW, areaH: areaH, metrics: m)
            let a = IslandAnchor.resolve(stored, areaW: areaW, areaH: areaH, metrics: m)
            let g = a.free
            print([
                "drop", name, "\(p.x)", "\(p.y)", stored,
                a.edge.rawValue, a.align.rawValue, a.hug?.rawValue ?? "-",
                g.map { "\($0.winX)" } ?? "-", g.map { "\($0.winY)" } ?? "-",
                g.map { "\($0.offX)" } ?? "-", g.map { "\($0.offY)" } ?? "-",
                "\(IslandAnchor.islandX(a, w: 640, metrics: m))",
                "\(IslandAnchor.islandY(a, h: 160, metrics: m))",
            ].joined(separator: "\t"))
        }
    }
}
