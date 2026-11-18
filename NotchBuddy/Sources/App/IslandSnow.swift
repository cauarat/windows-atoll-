import Foundation

/// The snow lying on the island's floor, as arithmetic.
///
/// A bank of snow along the bottom edge: thin on the resting bar, slowly deeper
/// while the island stays open, and soft — a pointer passing through it ploughs
/// a gap, heaps what it moved in front of itself and throws the rest up as a
/// few flakes, and the gap fills back in over the next seconds.
///
/// Foundation only, and no clock or pointer of its own: the view hands in the
/// time step and where the pointer is, so `scripts/test-island-snow.sh` can
/// compile this file alone and run the same script through
/// `windows/src/island/snow.ts`, its hand-kept twin. A number changed here and
/// not there is a failing build.
///
/// Heights are in points above the floor. Columns are counted from the island's
/// centre, so the humps stay where they are while the island springs wider.
struct IslandSnow {

    // MARK: The numbers both platforms share

    /// How deep the bank is on the resting bar, and the moment the island opens.
    static let restDepth = 6.0
    /// How deep it gets if the island is left open.
    static let maxDepth = 8.5
    /// Time constant of that growth, seconds: most of it in the first minute.
    static let growTime = 30.0
    /// After this long open there is nothing left to grow, and the clock stops.
    static let grownAfter = 150.0
    /// No heap rises past this. Every view leaves 10 pt clear above the floor,
    /// and the snow stays inside that — it never reaches a card.
    static let capHeight = 9.8

    /// Column pitch, points.
    static let pitch = 2.0
    /// Enough columns for an island 4096 pt wide. Fixed, so nothing reallocates
    /// while the island animates.
    static let columns = 2048

    /// How far above the floor the pointer still touches the snow.
    static let touch = 12.0
    /// Half the width of what it ploughs.
    static let radius = 11.0
    /// What it leaves behind: a floor is never swept quite clean.
    static let dusting = 0.5
    /// How wide the heap in front of it is.
    static let heapSpan = 14.0
    /// Slower than this, points a second, and the pointer is resting in the
    /// snow rather than sweeping it: it parts to both sides and nothing flies.
    static let sweepSpeed = 30.0
    /// How fast the pointer clears what is under it, per second.
    static let scoopRate = 22.0
    /// How much of a column goes when the pointer passes right across it.
    static let sweepTake = 0.85
    /// Seconds for a heap to slump, and for a gap to fill back in.
    static let slumpTime = 2.5
    static let refillTime = 5.0
    /// Seconds for the bank to thin back down when the island closes.
    static let closeTime = 0.12
    /// An offset smaller than this is nothing, and is dropped — which is what
    /// lets the bank come to rest and the ticker stop.
    static let epsilon = 0.02

    /// Snow moved, in column-points, for one flake to fly.
    static let flakeCost = 1.2
    static let maxFlakes = 40
    static let gravity = 560.0

    /// One thrown flake. `y` is height above the floor.
    struct Flake {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var life: Double
        var size: Double
    }

    // MARK: The bank at rest

    /// How deep the bank is `seconds` after the island opened.
    static func depth(openFor seconds: Double) -> Double {
        restDepth + (maxDepth - restDepth) * (1 - exp(-max(0, seconds) / growTime))
    }

    /// The surface `x` points from the centre, as a fraction of the depth:
    /// three sines that never line up, so it reads as drifted, not drawn.
    /// Always between 0.44 and 1.
    static func unit(x: Double) -> Double {
        let wave = sin(x * 0.071 + 1.3) * 0.5 + sin(x * 0.183 + 0.4) * 0.3 + sin(x * 0.41 + 2.1) * 0.2
        return 0.72 + 0.28 * wave
    }

    /// `unit` for every column, worked out once.
    static let shape: [Double] = (0..<columns).map { unit(x: Double($0 - columns / 2) * pitch) }

    // MARK: Falling

    // The snow coming down across the whole island, faint, in front of the
    // cards but blended so it can only ever lighten what is under it: white
    // text stays exactly as white, and nothing is ever hidden.
    //
    // No state at all. Every flake is a function of the clock, so there is
    // nothing to step, nothing to keep in time between two platforms, and a
    // ticker that stops and starts again picks up where the snow would have
    // been anyway.

    /// How many flakes there are in the whole field, most of them out of sight.
    static let fallCount = 220
    /// The field they are scattered over: as wide as the columns reach, and
    /// this tall before it repeats. One flake to about 3000 square points —
    /// twenty over an open card, three or four over the resting bar.
    static let fallField = 4096.0
    static let fallPeriod = 160.0
    /// A flake fades in over this far from the top, and out over this far from
    /// the floor, so it settles into the bank instead of stopping at the edge.
    static let fallFade = 8.0

    /// One flake, somewhere in its fall. `x` from the island's centre, `y`
    /// down from its top edge — before the island's height is taken into
    /// account, so `y` runs over the whole period.
    struct Falling {
        var x: Double
        var y: Double
        var radius: Double
        var alpha: Double
    }

    /// Four numbers a flake keeps for life: where across, where in the fall,
    /// how near, and how it sways. From the same fixed sequence as the thrown
    /// flakes, drawn once.
    static let fallSeeds: [Double] = {
        var seed: UInt32 = 0x1234_5678
        return (0..<fallCount * 4).map { _ in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed) / 4_294_967_296
        }
    }()

    /// Where flake `i` is at `time`, seconds.
    ///
    /// The near ones are bigger, quicker and a little brighter, which is all
    /// the depth there is. None is ever as much as half opaque.
    static func falling(_ i: Int, time: Double) -> Falling {
        let across = fallSeeds[i * 4], start = fallSeeds[i * 4 + 1]
        let near = fallSeeds[i * 4 + 2], sway = fallSeeds[i * 4 + 3]
        let speed = 10 + 16 * near
        let y = (time * speed + start * fallPeriod).truncatingRemainder(dividingBy: fallPeriod)
        let x = (across - 0.5) * fallField
            + sin(time * (0.4 + 0.6 * sway) + sway * 6.283) * (2 + 4 * near)
        return Falling(x: x, y: y, radius: 0.7 + 1.0 * near, alpha: 0.2 + 0.25 * near)
    }

    /// How much of a flake at `y` shows in an island `height` tall: nothing
    /// below the floor, and fading at both ends.
    static func fallVisibility(y: Double, height: Double) -> Double {
        guard y >= 0, y <= height else { return 0 }
        return max(0, min(1, y / fallFade, (height - y) / fallFade))
    }

    // MARK: State

    /// What the pointer has done to each column: negative where it ploughed,
    /// positive where it heaped. Zero is the bank as it drifted.
    private(set) var offsets = [Double](repeating: 0, count: IslandSnow.columns)
    private(set) var flakes: [Flake] = []
    /// The depth being drawn. Follows `depth(openFor:)` up, and eases down.
    private(set) var depth = IslandSnow.restDepth
    private(set) var openFor = 0.0
    /// Nothing is moving: no flake in the air, no column out of place, the
    /// depth where it should be.
    private(set) var isSettled = true

    private var lastX: Double?
    private var budget = 0.0
    private var seed: UInt32 = 0x9E37_79B9

    /// Still getting deeper, so worth a slow tick even with nothing else going on.
    var isGrowing: Bool { openFor > 0 && openFor < IslandSnow.grownAfter }

    /// The snow's height at column `i`.
    func height(_ i: Int) -> Double {
        min(IslandSnow.capHeight, max(0, depth * IslandSnow.shape[i] + offsets[i]))
    }

    /// The column under `x`, measured from the centre.
    static func column(at x: Double) -> Int {
        Int((x / pitch).rounded()) + columns / 2
    }

    /// The columns an island `width` wide shows.
    static func visible(width: Double) -> ClosedRange<Int> {
        let half = Int((width / 2 / pitch).rounded(.up)) + 1
        return max(0, columns / 2 - half)...min(columns - 1, columns / 2 + half)
    }

    // MARK: One step

    /// Advance by `dt` seconds.
    ///
    /// `pointer` is where the pointer is, if it is over the island: `x` from the
    /// island's left edge, `above` the floor. Nil when it is somewhere else.
    mutating func step(dt: Double, width: Double, expanded: Bool,
                       pointer: (x: Double, above: Double)?) {
        // Depth: up with the clock, down on a curve.
        openFor = expanded ? openFor + dt : 0
        let goal = expanded ? IslandSnow.depth(openFor: openFor) : IslandSnow.restDepth
        if goal < depth {
            depth += (goal - depth) * (1 - exp(-dt / IslandSnow.closeTime))
            if depth - goal < IslandSnow.epsilon { depth = goal }
        } else {
            depth = goal
        }

        // Heaps slump and gaps fill.
        let slump = exp(-dt / IslandSnow.slumpTime)
        let refill = exp(-dt / IslandSnow.refillTime)
        var moving = false
        for i in 0..<IslandSnow.columns where offsets[i] != 0 {
            offsets[i] *= offsets[i] > 0 ? slump : refill
            if abs(offsets[i]) < IslandSnow.epsilon { offsets[i] = 0 } else { moving = true }
        }

        if let pointer, pointer.above >= -2, pointer.above <= IslandSnow.touch,
           pointer.x >= 0, pointer.x <= width {
            plough(at: pointer.x - width / 2, dt: dt)
            moving = true
        } else {
            lastX = nil
        }

        // Flakes fly, fall and are gone: thrown snow does not come back, the
        // bank refills on its own.
        if !flakes.isEmpty {
            let drag = exp(-1.5 * dt)
            for i in flakes.indices {
                flakes[i].vy -= IslandSnow.gravity * dt
                flakes[i].vx *= drag
                flakes[i].x += flakes[i].vx * dt
                flakes[i].y += flakes[i].vy * dt
                flakes[i].life -= dt
            }
            flakes.removeAll { $0.life <= 0 || $0.y < 0 }
        }

        isSettled = !moving && flakes.isEmpty && depth == goal
    }

    /// The pointer is in the snow at `cx`, measured from the centre.
    private mutating func plough(at cx: Double, dt: Double) {
        let from = lastX ?? cx
        let velocity = (cx - from) / max(dt, 1e-4)
        lastX = cx
        let direction = abs(velocity) > IslandSnow.sweepSpeed ? (velocity > 0 ? 1.0 : -1.0) : 0.0

        // Scoop what is under it — and everything it crossed since the last
        // step. A pointer covers ten or twenty points between two frames, and
        // clearing only where it happens to be seen would leave a dotted line
        // instead of a furrow.
        let take = 1 - exp(-dt * IslandSnow.scoopRate)
        let lo = min(from, cx), hi = max(from, cx)
        let first = max(0, IslandSnow.column(at: lo - IslandSnow.radius))
        let last = min(IslandSnow.columns - 1, IslandSnow.column(at: hi + IslandSnow.radius))
        var moved = 0.0
        if first <= last {
            for i in first...last {
                let x = Double(i - IslandSnow.columns / 2) * IslandSnow.pitch
                let crossed = hi > lo && x >= lo && x <= hi
                let weight = max(0, 1 - abs(x - cx) / IslandSnow.radius)
                let part = crossed ? max(IslandSnow.sweepTake, weight * take) : weight * take
                let scoop = max(0, height(i) - IslandSnow.dusting) * part
                offsets[i] -= scoop
                moved += scoop
            }
        }
        guard moved > 0 else { return }

        // Half goes in a heap ahead of a moving pointer and half into the air;
        // a resting one just parts it, to both sides.
        if direction == 0 {
            // What would not fit is simply packed down: nothing flies from a
            // pointer that is not moving.
            _ = heap(moved / 2, from: cx, toward: -1)
            _ = heap(moved / 2, from: cx, toward: 1)
            return
        }
        budget += moved / 2 + heap(moved / 2, from: cx, toward: direction)
        let top = height(max(0, min(IslandSnow.columns - 1, IslandSnow.column(at: cx))))
        while budget >= IslandSnow.flakeCost, flakes.count < IslandSnow.maxFlakes {
            budget -= IslandSnow.flakeCost
            let speed = 60 + min(abs(velocity), 900) * 0.25
            flakes.append(Flake(
                x: cx + direction * IslandSnow.radius * random(),
                y: top + 1,
                vx: direction * speed * (0.5 + random()) + (random() - 0.5) * 30,
                vy: 45 + 75 * random(),
                life: 0.5 + 0.4 * random(),
                size: 0.6 + 0.8 * random()))
        }
        // The air is full: the rest is lost rather than saved up for a burst.
        budget = min(budget, IslandSnow.flakeCost)
    }

    /// Spread `amount` over the heap on one side of `cx`. Returns what the cap
    /// would not take.
    private mutating func heap(_ amount: Double, from cx: Double, toward side: Double) -> Double {
        let near = IslandSnow.column(at: cx + side * IslandSnow.radius)
        let far = IslandSnow.column(at: cx + side * (IslandSnow.radius + IslandSnow.heapSpan))
        let first = max(0, min(near, far))
        let last = min(IslandSnow.columns - 1, max(near, far))
        guard first <= last else { return amount }
        // A mound, not a box: most of it lands in the middle, and the middle
        // is allowed to stand tallest, so a heap that is full still has a
        // rounded top rather than a flat one at the cap.
        let count = Double(last - first + 1)
        func hump(_ i: Int) -> Double { sin(Double.pi * (Double(i - first) + 0.5) / count) }
        var total = 0.0
        for i in first...last { total += hump(i) }
        var spilled = 0.0
        for i in first...last {
            let share = amount * hump(i) / total
            let limit = IslandSnow.capHeight * (0.55 + 0.45 * hump(i))
            let put = min(share, max(0, limit - height(i)))
            offsets[i] += put
            spilled += share - put
        }
        return spilled
    }

    /// A fixed sequence rather than the system's: the two platforms have to
    /// throw the same flakes for the parity test to mean anything.
    private mutating func random() -> Double {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Double(seed) / 4_294_967_296
    }
}
