import Foundation

// The snow on the island's floor: what it promises, and a script both
// platforms run.
//
// `--dump` prints the script's samples for tests/island-snow-parity.ts, which
// runs the same steps through windows/src/island/snow.ts and compares.

@main
enum IslandSnowTests {
    static var failures = 0

    static func check(_ ok: Bool, _ what: String) {
        print("  \(ok ? "✓" : "✗") \(what)")
        if !ok { failures += 1 }
    }

    /// One line of the dump: a name, then numbers.
    static func sample(_ name: String, _ snow: IslandSnow, width: Double) -> String {
        var values: [Double] = [snow.depth, snow.openFor, snow.isSettled ? 1 : 0, Double(snow.flakes.count)]
        let visible = IslandSnow.visible(width: width)
        for i in stride(from: visible.lowerBound, through: visible.upperBound, by: 4) {
            values.append(snow.height(i))
        }
        for flake in snow.flakes {
            values += [flake.x, flake.y, flake.vx, flake.vy, flake.life, flake.size]
        }
        return ([name] + values.map { String(format: "%.9f", $0) }).joined(separator: "\t")
    }

    /// The script. tests/island-snow-parity.ts has the same steps, in the same
    /// order: change one and change the other.
    static func script() -> [String] {
        var lines: [String] = []
        var snow = IslandSnow()
        let frame = 1.0 / 60.0

        // Open for twenty seconds, at the slow tick.
        for _ in 0..<40 { snow.step(dt: 0.5, width: 640, expanded: true, pointer: nil) }
        lines.append(sample("grown", snow, width: 640))

        // Swept to the right, 600 points a second.
        var x = 120.0
        while x <= 520 {
            snow.step(dt: frame, width: 640, expanded: true, pointer: (x: x, above: 3))
            x += 10
        }
        lines.append(sample("swept", snow, width: 640))

        // Held still in the snow for half a second.
        for _ in 0..<30 { snow.step(dt: frame, width: 640, expanded: true, pointer: (x: 300, above: 2)) }
        lines.append(sample("parted", snow, width: 640))

        // Swept back, faster.
        x = 500
        while x >= 100 {
            snow.step(dt: frame, width: 640, expanded: true, pointer: (x: x, above: 5))
            x -= 16
        }
        lines.append(sample("swept-back", snow, width: 640))

        // Left alone for three seconds.
        for _ in 0..<180 { snow.step(dt: frame, width: 640, expanded: true, pointer: nil) }
        lines.append(sample("refilling", snow, width: 640))

        // Closed.
        for _ in 0..<30 { snow.step(dt: frame, width: 288, expanded: false, pointer: nil) }
        lines.append(sample("closed", snow, width: 288))
        return lines
    }

    static func main() {
        if CommandLine.arguments.contains("--dump") {
            print(script().joined(separator: "\n"))
            return
        }
        let frame = 1.0 / 60.0

        print("\nThe bank")
        check(IslandSnow.depth(openFor: 0) == IslandSnow.restDepth, "opens at the resting depth")
        var last = IslandSnow.restDepth
        var monotone = true
        for second in 1...300 {
            let d = IslandSnow.depth(openFor: Double(second))
            if d < last || d > IslandSnow.maxDepth { monotone = false }
            last = d
        }
        check(monotone, "only gets deeper, and never past the maximum")
        check(IslandSnow.maxDepth - IslandSnow.depth(openFor: IslandSnow.grownAfter) < 0.03,
              "has finished growing by the time the clock stops")
        check(IslandSnow.shape.allSatisfy { $0 >= 0.44 - 1e-9 && $0 <= 1 + 1e-9 },
              "has a surface between 0.44 and 1 of its depth")
        check(IslandSnow.capHeight < 10, "stays inside the 10 pt every view leaves above the floor")

        print("\nLeft alone")
        var snow = IslandSnow()
        check(snow.isSettled && !snow.isGrowing, "starts settled")
        for _ in 0..<120 { snow.step(dt: 0.5, width: 640, expanded: true, pointer: nil) }
        check(abs(snow.depth - IslandSnow.depth(openFor: 60)) < 1e-9, "is as deep as a minute open makes it")
        check(snow.isSettled && snow.isGrowing, "is settled while it grows: a slow tick is enough")
        for _ in 0..<240 { snow.step(dt: 0.5, width: 640, expanded: true, pointer: nil) }
        check(!snow.isGrowing, "stops growing, so the ticker can stop")
        snow.step(dt: frame, width: 640, expanded: true, pointer: (x: 300, above: 40))
        check(snow.isSettled, "ignores a pointer that is above it")
        snow.step(dt: frame, width: 640, expanded: true, pointer: (x: 700, above: 3))
        check(snow.isSettled, "ignores a pointer that is beside the island")

        print("\nSwept")
        let centre = IslandSnow.column(at: 0)
        let before = snow.height(centre)
        var x = 200.0
        var thrown = 0
        var overCap = false
        while x <= 440 {
            snow.step(dt: frame, width: 640, expanded: true, pointer: (x: x, above: 3))
            thrown = max(thrown, snow.flakes.count)
            for i in 0..<IslandSnow.columns where snow.height(i) > IslandSnow.capHeight || snow.height(i) < 0 {
                overCap = true
            }
            x += 8
        }
        check(snow.height(centre) < before * 0.5, "leaves a gap where the pointer went")
        check(snow.height(centre) >= IslandSnow.dusting * 0.9, "but never sweeps the floor bare")
        check(thrown > 0 && thrown <= IslandSnow.maxFlakes, "throws flakes, and not more than the limit")
        check(snow.flakes.allSatisfy { $0.vx > 0 }, "throws them the way the pointer was going")
        check(!overCap, "never heaps past the cap")
        check(!snow.isSettled, "is moving, so the ticker runs")

        for _ in 0..<(60 * 40) { snow.step(dt: frame, width: 640, expanded: true, pointer: nil) }
        check(snow.isSettled && snow.flakes.isEmpty, "comes to rest once it is left alone")
        check(abs(snow.height(centre) - before) < 0.05, "and the gap has filled back in")

        print("\nA pointer resting in it")
        var still = IslandSnow()
        let resting = still.height(centre)
        for _ in 0..<60 { still.step(dt: frame, width: 640, expanded: false, pointer: (x: 320, above: 2)) }
        check(still.height(centre) < resting * 0.5, "parts the snow")
        check(still.flakes.isEmpty, "and throws nothing")
        let side = IslandSnow.column(at: IslandSnow.radius + 4)
        let other = IslandSnow.column(at: -IslandSnow.radius - 4)
        check(still.offsets[side] > 0 && still.offsets[other] > 0, "to both sides")

        print("\nClosing")
        var closing = IslandSnow()
        for _ in 0..<120 { closing.step(dt: 0.5, width: 640, expanded: true, pointer: nil) }
        for _ in 0..<60 { closing.step(dt: frame, width: 288, expanded: false, pointer: nil) }
        check(closing.depth == IslandSnow.restDepth && closing.isSettled,
              "thins back to the resting depth within a second, and settles")

        print("")
        if failures > 0 {
            print("\(failures) failed")
            exit(1)
        }
        print("All island snow tests passed")
    }
}
