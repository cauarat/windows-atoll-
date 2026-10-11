// The island's clickable chrome.
//
// These rectangles decide what a transparent panel covering the top of the
// screen lets through. If the chrome is too small the buttons do not click; if
// it is too large the island eats clicks meant for whatever is behind it. Both
// failures are invisible in a screenshot, which is why they are asserted here.
//
// Run with scripts/test-island-edges.sh.

import CoreGraphics
import Foundation

@main
enum IslandEdgeLayoutTests {

    static var failures = 0

    static func check(_ condition: Bool, _ what: String) {
        print("  \(condition ? "\u{2713}" : "\u{2717}") \(what)")
        if !condition { failures += 1 }
    }

    static func main() {
        let d = IslandEdgeLayout.diameter
        let gap = IslandEdgeLayout.gap

        // The real sizes: resting on a notch, compact, expanded, and the big
        // screen this work introduces.
        let sizes: [(String, CGFloat, CGFloat)] = [
            ("resting", 184, 32), ("compact", 344, 32),
            ("expanded", 640, 160), ("large", 1000, 650),
        ]

        // MARK: – Nothing hung off it behaves exactly as today

        for (name, w, h) in sizes {
            let bounds = IslandEdgeLayout.chromeBounds([], islandWidth: w, islandHeight: h)
            check(bounds == CGRect(x: 0, y: 0, width: w, height: h),
                  "\(name): an island with no buttons has the chrome it always had")
        }

        // MARK: – The chrome contains everything it should

        let full = [
            IslandEdgeButton("a", .left), IslandEdgeButton("b", .left),
            IslandEdgeButton("c", .right), IslandEdgeButton("d", .right),
            IslandEdgeButton("e", .bottom),
        ]
        for (name, w, h) in sizes {
            let island = CGRect(x: 0, y: 0, width: w, height: h)
            let bounds = IslandEdgeLayout.chromeBounds(full, islandWidth: w, islandHeight: h)
            let rects = IslandEdgeLayout.rects(full, islandWidth: w, islandHeight: h)

            check(bounds.contains(island), "\(name): the chrome still contains the island")
            check(rects.count == full.count, "\(name): every button got a rect")
            check(rects.allSatisfy { bounds.contains($0) },
                  "\(name): the chrome contains every button")
            check(rects.allSatisfy { $0.width == d && $0.height == d },
                  "\(name): every button is the size it should be")
        }

        // MARK: – Buttons do not sit on the island

        // A button overlapping the island would be unreachable under it, and
        // worse, would make the island's own hover fire when you aim for it.
        for (name, w, h) in sizes {
            let island = CGRect(x: 0, y: 0, width: w, height: h)
            let rects = IslandEdgeLayout.rects(full, islandWidth: w, islandHeight: h)
            check(rects.allSatisfy { !$0.intersects(island.insetBy(dx: 0.01, dy: 0.01)) },
                  "\(name): no button overlaps the island")
        }

        // MARK: – Buttons do not sit on each other

        for (name, w, h) in sizes {
            let rects = IslandEdgeLayout.rects(full, islandWidth: w, islandHeight: h)
            var clash = false
            for i in 0..<rects.count {
                for j in (i + 1)..<rects.count where rects[i].intersects(rects[j].insetBy(dx: 0.01, dy: 0.01)) {
                    clash = true
                }
            }
            check(!clash, "\(name): no two buttons overlap")
        }

        // MARK: – Which side is which

        let w: CGFloat = 640, h: CGFloat = 160
        let left = IslandEdgeLayout.center(side: .left, index: 0, count: 1, islandWidth: w, islandHeight: h)
        let right = IslandEdgeLayout.center(side: .right, index: 0, count: 1, islandWidth: w, islandHeight: h)
        let bottom = IslandEdgeLayout.center(side: .bottom, index: 0, count: 1, islandWidth: w, islandHeight: h)
        check(left.x < 0 && abs(left.y - h / 2) < 0.001, "a lone left button sits left, centred")
        check(right.x > w && abs(right.y - h / 2) < 0.001, "a lone right button sits right, centred")
        check(bottom.y > h && abs(bottom.x - w / 2) < 0.001, "a lone bottom button sits under the middle")
        check(abs(left.x + right.x - w) < 0.001, "the two sides are mirror images")

        // A run is centred on the island, so adding one shifts both.
        let two = (0..<2).map {
            IslandEdgeLayout.center(side: .left, index: $0, count: 2, islandWidth: w, islandHeight: h)
        }
        check(abs((two[0].y + two[1].y) / 2 - h / 2) < 0.001, "a pair stays centred on the island")
        check(abs(two[1].y - two[0].y - (d + IslandEdgeLayout.spacing)) < 0.001,
              "a pair is spaced by exactly one gap")

        // MARK: – Overhang on a resting island

        // Two 34 pt buttons need 76 pt against a 32 pt island, so they must
        // overhang both ways rather than being squeezed or clipped.
        let resting = IslandEdgeLayout.chromeBounds(
            [IslandEdgeButton("a", .left), IslandEdgeButton("b", .left)],
            islandWidth: 184, islandHeight: 32)
        check(resting.minY < 0 && resting.maxY > 32, "two buttons overhang a resting island both ways")

        // MARK: – The flip into panel space

        // The panel's y grows upward. A button *below* the island must end up
        // at a smaller y, not a larger one — getting this backwards puts the
        // clickable area above the island where nothing is drawn.
        let islandFrame = CGRect(x: 40, y: 500, width: 640, height: 160)
        let under = IslandEdgeLayout.chromeFrame(
            islandFrame: islandFrame, buttons: [IslandEdgeButton("e", .bottom)])
        check(under.minY < islandFrame.minY, "a button below the island extends the chrome downward")
        check(abs(under.maxY - islandFrame.maxY) < 0.001, "and leaves the top where it was")
        check(under.contains(islandFrame), "the flipped chrome still contains the island")

        let beside = IslandEdgeLayout.chromeFrame(
            islandFrame: islandFrame, buttons: [IslandEdgeButton("a", .left)])
        check(abs(beside.minX - (islandFrame.minX - gap - d)) < 0.001,
              "a button left of the island extends the chrome left by exactly its reach")
        check(IslandEdgeLayout.chromeFrame(islandFrame: islandFrame, buttons: []) == islandFrame,
              "no buttons, no change to the frame")

        // MARK: – Defaults

        let defaults = IslandEdgeLayout.defaults(pills: ["p1", "p2", "p3", "p4", "p5"])
        check(defaults.count == 5, "every pill becomes a button")
        check(IslandEdgeLayout.buttons(defaults, on: .left).count == 3
              && IslandEdgeLayout.buttons(defaults, on: .right).count == 2,
              "and they are dealt alternately between the sides")
        check(defaults.map(\.action) == ["p1", "p2", "p3", "p4", "p5"],
              "keeping the order the user chose")
        check(Set(defaults.map(\.id)).count == defaults.count, "with ids that stay distinct")

        print("")
        if failures == 0 {
            print("All island edge layout tests passed.")
        } else {
            print("\(failures) failed.")
            exit(1)
        }
    }
}
