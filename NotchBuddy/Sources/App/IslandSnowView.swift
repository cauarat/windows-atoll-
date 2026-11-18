import SwiftUI

// The snow on the island's floor, drawn.
//
// `IslandSnow` is the arithmetic; this is the three things around it: where the
// pointer is, a ticker that runs only while something is moving, and a canvas.
//
// A detail, and it has to stay one. It sits under everything the island shows,
// takes no clicks, keeps inside the 10 pt every view leaves above the floor,
// and gets out of the way of the auto-close hairline, which is drawn on the
// same edge.

/// What the snow needs to know from the rest of the island.
///
/// The controller already reads the pointer sixty times a second to decide
/// when the panel takes the mouse, and the hairline already works out ten
/// times a second whether it is showing. Both hand the answer here rather than
/// the snow asking again — and only a *change* is published, so a pointer
/// crossing the island costs the views nothing until it reaches the snow.
@MainActor
final class IslandSnowInput: ObservableObject {
    static let shared = IslandSnowInput()

    /// The pointer, from the island's left edge and above its floor.
    private(set) var x: CGFloat = 0
    private(set) var above: CGFloat = 0
    /// The pointer is in the snow, or close enough that it is about to be.
    @Published private(set) var near = false
    /// The auto-close hairline is on screen.
    @Published private(set) var counting = false

    func track(x: CGFloat, above: CGFloat, width: CGFloat) {
        self.x = x
        self.above = above
        let now = above >= -2 && above <= CGFloat(IslandSnow.touch) + 4 && x >= -4 && x <= width + 4
        if now != near { near = now }
    }

    func pointerLeft() { if near { near = false } }

    func setCounting(_ on: Bool) { if on != counting { counting = on } }

    /// Nil unless the pointer is where the snow can feel it.
    var pointer: (x: Double, above: Double)? {
        near ? (x: Double(x), above: Double(above)) : nil
    }
}

/// Steps the snow, and only while there is something to step.
///
/// Sixty times a second while the pointer is in it or anything is still
/// moving; twice a second while the island is open and the bank is getting
/// deeper; not at all the rest of the time. A resting bar with settled snow
/// on it has no timer.
@MainActor
final class IslandSnowDriver: ObservableObject {
    private(set) var snow = IslandSnow()

    var width: Double = 0
    var expanded = false

    private var timer: Timer?
    private var interval: TimeInterval = 0
    private var last: Date?

    /// Something changed — the pointer arrived, the island opened or closed.
    func wake() { schedule(every: 1.0 / 60.0) }

    func stop() {
        timer?.invalidate()
        timer = nil
        interval = 0
        last = nil
    }

    private func schedule(every seconds: TimeInterval) {
        guard seconds != interval || timer == nil else { return }
        timer?.invalidate()
        interval = seconds
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard timer != nil else { return }
        let now = Date()
        // A long gap is the ticker having been stopped, not a long frame.
        let elapsed = last.map { now.timeIntervalSince($0) } ?? interval
        let dt = elapsed > 1 || elapsed <= 0 ? 1.0 / 60.0 : elapsed
        last = now

        let input = IslandSnowInput.shared
        snow.step(dt: dt, width: width, expanded: expanded, pointer: input.pointer)
        objectWillChange.send()

        if input.near || !snow.isSettled {
            schedule(every: 1.0 / 60.0)
        } else if expanded && snow.isGrowing {
            schedule(every: 0.5)
        } else {
            stop()
        }
    }
}

/// The layer `IslandContainer` puts just above the island's black.
struct IslandSnowLayer: View {
    @ObservedObject var state: AppState
    let width: CGFloat
    let height: CGFloat

    @ObservedObject private var input = IslandSnowInput.shared
    @StateObject private var driver = IslandSnowDriver()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inSeason = IslandSnowLayer.seasonOpen()

    /// The snow keeps the season the Christmas wardrobe does. Always in a
    /// debug build, so it can be worked on in July.
    static func seasonOpen() -> Bool {
        #if DEBUG
        return true
        #else
        return MochiFestive.isInSeason(Date())
        #endif
    }

    private var showing: Bool { state.islandSnow && inSeason && state.mode != .hidden }

    var body: some View {
        Group {
            if showing {
                // Reduce Motion: the bank as it drifted, and nothing else. No
                // growing, no ploughing, no flakes — and no ticker.
                IslandSnowCanvas(width: width,
                                 snow: reduceMotion ? IslandSnow() : driver.snow)
                    .opacity(input.counting ? 0 : 1)
                    .animation(.easeInOut(duration: 0.25), value: input.counting)
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: height, alignment: .bottomLeading)
        .animation(.easeInOut(duration: 0.2), value: showing)
        .onAppear { sync() }
        .onChange(of: state.mode) { _, _ in
            inSeason = IslandSnowLayer.seasonOpen()
            sync()
        }
        .onChange(of: state.islandSnow) { _, _ in sync() }
        .onChange(of: input.near) { _, _ in sync() }
        .onChange(of: reduceMotion) { _, _ in sync() }
        .onChange(of: width) { _, _ in driver.width = Double(width) }
    }

    /// Tell the ticker what the island is doing, and start it or stop it.
    private func sync() {
        driver.width = Double(width)
        driver.expanded = state.mode == .expanded
        if showing && !reduceMotion { driver.wake() } else { driver.stop() }
    }
}

/// Snow coming down across the whole island.
///
/// The one part of this that is drawn *over* what the island shows, and it is
/// made so that it cannot get in the way: no flake is as much as half
/// opaque, none is wider than 3.4 pt, and the layer is blended as `screen`, which
/// can only lighten. White text under a flake is exactly as white as it was;
/// what the eye gets is snow falling behind the words.
///
/// Thirty frames a second while the island is on screen, and unmounted — no
/// ticker at all — when it is hidden, out of season, switched off or the
/// system asks for less motion.
struct IslandSnowfallLayer: View {
    @ObservedObject var state: AppState
    let width: CGFloat
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showing: Bool {
        state.islandSnow && state.mode != .hidden && !reduceMotion && IslandSnowLayer.seasonOpen()
    }

    var body: some View {
        Group {
            if showing {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, size in
                        IslandSnowfallLayer.draw(&context, size: size, time: time)
                    }
                }
                .blendMode(.screen)
                .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .animation(.easeInOut(duration: 0.3), value: showing)
    }

    /// Every flake that is over the island right now.
    static func draw(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        let mid = Double(size.width) / 2
        let height = Double(size.height)
        // The field repeats down the island, for one taller than a period.
        let repeats = Int((height / IslandSnow.fallPeriod).rounded(.up))
        for i in 0..<IslandSnow.fallCount {
            let flake = IslandSnow.falling(i, time: time)
            guard abs(flake.x) <= mid + 2 else { continue }
            for k in 0..<max(1, repeats) {
                let y = flake.y + Double(k) * IslandSnow.fallPeriod
                let visible = IslandSnow.fallVisibility(y: y, height: height)
                guard visible > 0 else { continue }
                let r = flake.radius
                let dot = Path(ellipseIn: CGRect(x: mid + flake.x - r, y: y - r,
                                                 width: r * 2, height: r * 2))
                context.fill(dot, with: .color(.white.opacity(flake.alpha * visible)))
            }
        }
    }
}

/// The bank and the flakes, in a strip along the floor.
///
/// A `Shape`, like the island it lies in, and animatable in width for the same
/// reason: the snow springs open with the island instead of jumping to where
/// the island is going.
private struct IslandSnowCanvas: View {
    var width: CGFloat
    let snow: IslandSnow

    /// Tall enough for the highest heap and the highest flake above it.
    static let band: CGFloat = 28

    var body: some View {
        IslandSnowShape(width: width, snow: snow)
            .fill(LinearGradient(
                stops: [
                    .init(color: Color(hex: "#FFFFFF"),
                          location: 1 - CGFloat(IslandSnow.capHeight) / IslandSnowCanvas.band),
                    .init(color: Color(hex: "#D3E2F2"), location: 1),
                ],
                startPoint: .top, endPoint: .bottom))
            .frame(width: max(0, width), height: IslandSnowCanvas.band)
    }
}

private struct IslandSnowShape: Shape {
    var width: CGFloat
    let snow: IslandSnow

    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let floor = Double(rect.maxY)
        let mid = Double(width) / 2
        let columns = IslandSnow.visible(width: Double(width))
        func x(_ i: Int) -> Double { mid + Double(i - IslandSnow.columns / 2) * IslandSnow.pitch }

        var path = Path()
        path.move(to: CGPoint(x: x(columns.lowerBound), y: floor))
        for i in columns {
            path.addLine(to: CGPoint(x: x(i), y: floor - snow.height(i)))
        }
        path.addLine(to: CGPoint(x: x(columns.upperBound), y: floor))
        path.closeSubpath()

        // A flake fades by getting smaller: one fill, one colour.
        for flake in snow.flakes {
            let r = flake.size * min(1, flake.life / 0.25)
            path.addEllipse(in: CGRect(x: mid + flake.x - r, y: floor - flake.y - r,
                                       width: r * 2, height: r * 2))
        }
        return path
    }
}
