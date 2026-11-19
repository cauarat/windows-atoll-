import SwiftUI

// The hydration cards: the tab with the glass you tap, and the reminder.
//
// Everything they know comes from `HydrationStore.shared`; these only draw it.
// The island builds every view at once and hides the ones that are not up, so
// nothing here runs a clock at rest — the glass animates for a few seconds
// after a change and then stops.

// MARK: - Text

enum HydrationText {
    /// "850 ml", "1,1 L": with the decimal mark of the language the app is in,
    /// not the Mac's region — the sentence around it is in that language.
    static func amount(_ ml: Int) -> String {
        HydrationFormat.amount(ml, decimalSeparator: AppLanguage.current.resolved == .en ? "." : ",")
    }

    /// "45 min", "2 h", "1 h 30".
    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return L("\(m) min") }
        if m == 0 { return L("\(h) h") }
        return L("\(h) h \(m)")
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// The marks a streak is counted toward.
    static func nextMark(after days: Int) -> Int {
        [3, 7, 14, 30, 60, 100, 365].first { $0 > days } ?? (days / 100 + 1) * 100
    }

    static func previousMark(before mark: Int) -> Int {
        [0, 3, 7, 14, 30, 60, 100, 365].last { $0 < mark } ?? 0
    }
}

// MARK: - The glass

/// A tumbler that fills. `level` is 0…1; `pulse` changes when something was
/// poured in, which is what drops the drop — past the goal the level no longer
/// moves, and the drop is then the only sign the tap was heard.
struct HydrationGlass: View {
    var level: Double
    var pulse: Int = 0
    var color: Color = Color(hex: "#22D3EE")
    /// A few points wide, in the compact bar: outline and level, nothing else.
    var mini = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var from: Double = 0
    @State private var changedAt = Date.distantPast
    @State private var dropAt = Date.distantPast
    @State private var live = false
    @State private var wake = 0

    private var still: Bool { reduceMotion || mini }

    var body: some View {
        TimelineView(.animation(paused: !live)) { timeline in
            Canvas { context, size in
                draw(context, size: size, now: timeline.date)
            }
        }
        .aspectRatio(100.0 / 120.0, contentMode: .fit)
        .onAppear { from = level }
        .onChange(of: level) { old, _ in
            from = shownLevel(at: Date(), target: old)
            changedAt = Date()
            stir()
        }
        .onChange(of: pulse) { _, _ in
            dropAt = Date()
            if abs(Date().timeIntervalSince(changedAt)) > 0.2 { changedAt = Date(); from = level }
            stir()
        }
        .task(id: wake) {
            guard wake > 0 else { return }
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled { live = false }
        }
        .accessibilityHidden(true)
    }

    private func stir() {
        guard !still else { return }
        live = true
        wake += 1
    }

    /// The level on screen at `now`: the pour takes 0.9 s and overshoots a
    /// little, the way water does when it arrives.
    private func shownLevel(at now: Date, target: Double) -> Double {
        guard !still else { return target }
        let p = min(1, max(0, now.timeIntervalSince(changedAt) / 0.9))
        let c1 = 1.70158, c3 = c1 + 1
        let eased = 1 + c3 * pow(p - 1, 3) + c1 * pow(p - 1, 2)
        return from + (target - from) * eased
    }

    private func draw(_ context: GraphicsContext, size: CGSize, now: Date) {
        var ctx = context
        let s = size.width / 100
        ctx.scaleBy(x: s, y: s)

        let sinceChange = now.timeIntervalSince(changedAt)
        let sinceDrop = now.timeIntervalSince(dropAt)
        let shown = min(1, max(0, shownLevel(at: now, target: level)))
        let energy: CGFloat = still || shown <= 0 ? 0 : CGFloat(pow(max(0, 1 - sinceChange / 3.0), 2))

        // A small squash when a drop lands, about the foot of the glass.
        if !still, sinceDrop >= 0, sinceDrop < 0.46 {
            let p = sinceDrop / 0.46
            let (kx, ky): (CGFloat, CGFloat) = p < 0.3
                ? (1 + 0.035 * CGFloat(p / 0.3), 1 - 0.045 * CGFloat(p / 0.3))
                : p < 0.62
                    ? (1.035 - 0.05 * CGFloat((p - 0.3) / 0.32), 0.955 + 0.065 * CGFloat((p - 0.3) / 0.32))
                    : (0.985 + 0.015 * CGFloat((p - 0.62) / 0.38), 1.02 - 0.02 * CGFloat((p - 0.62) / 0.38))
            ctx.translateBy(x: 50, y: 120)
            ctx.scaleBy(x: kx, y: ky)
            ctx.translateBy(x: -50, y: -120)
        }

        var cavity = Path()
        cavity.move(to: CGPoint(x: 12.6, y: 8))
        cavity.addLine(to: CGPoint(x: 87.4, y: 8))
        cavity.addLine(to: CGPoint(x: 77.9, y: 104.6))
        cavity.addQuadCurve(to: CGPoint(x: 70, y: 111.6), control: CGPoint(x: 77.2, y: 111.6))
        cavity.addLine(to: CGPoint(x: 30, y: 111.6))
        cavity.addQuadCurve(to: CGPoint(x: 22.1, y: 104.6), control: CGPoint(x: 22.8, y: 111.6))
        cavity.closeSubpath()
        ctx.fill(cavity, with: .color(Color.white.opacity(0.05)))

        let surface = 111.6 - 93.6 * CGFloat(shown)
        if shown > 0.001 {
            var w = ctx
            w.clip(to: cavity)
            let t = CGFloat(now.timeIntervalSinceReferenceDate)
            func water(amp: CGFloat, phase: CGFloat, lift: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: -10, y: 130))
                p.addLine(to: CGPoint(x: -10, y: surface - lift))
                var x: CGFloat = -10
                while x <= 110 {
                    let y = surface - lift + (amp > 0 ? sin(x / 50 * 2 * .pi + phase) * amp : 0)
                    p.addLine(to: CGPoint(x: x, y: y))
                    x += 2
                }
                p.addLine(to: CGPoint(x: 110, y: 130))
                p.closeSubpath()
                return p
            }
            if energy > 0.01 {
                w.fill(water(amp: 3.4 * energy, phase: -t * 1.9, lift: 2.5 * energy), with: .color(color.opacity(0.45)))
            }
            w.fill(water(amp: 3.2 * energy, phase: t * 2.9, lift: 0), with: .linearGradient(
                Gradient(colors: [color.opacity(0.95), color.opacity(0.6)]),
                startPoint: CGPoint(x: 0, y: surface), endPoint: CGPoint(x: 0, y: 112)
            ))
            if energy < 0.05 {
                w.fill(Path(CGRect(x: -10, y: surface, width: 120, height: 1.3)), with: .color(Color.white.opacity(0.3)))
            }
            // Bubbles, while the water is still moving.
            if energy > 0.05 {
                for (i, base) in [(36.0, 1.7), (54.0, 2.1), (66.0, 1.9)].enumerated() {
                    let cycle = (Double(t) + Double(i) * 0.45).truncatingRemainder(dividingBy: base.1) / base.1
                    let y = surface + 44 - CGFloat(cycle) * 40
                    let alpha = Double(energy) * 0.55 * (cycle < 0.2 ? cycle / 0.2 : 1 - cycle)
                    let r: CGFloat = i == 0 ? 2.2 : 1.5
                    w.fill(Path(ellipseIn: CGRect(x: base.0 - r, y: y - r, width: r * 2, height: r * 2)),
                           with: .color(Color.white.opacity(alpha)))
                }
            }
            // The ring the drop leaves on the surface.
            if !still, sinceDrop >= 0.24, sinceDrop < 0.94 {
                let p = CGFloat((sinceDrop - 0.24) / 0.7)
                let k = 0.2 + 1.5 * p
                w.stroke(Path(ellipseIn: CGRect(x: 50 - 15 * k, y: surface - 2.6 * k, width: 30 * k, height: 5.2 * k)),
                         with: .color(Color.white.opacity(0.75 * Double(1 - p))), lineWidth: 1.2)
            }
        }

        let stroke: CGFloat = mini ? 8 : 2.4
        var outline = Path()
        outline.move(to: CGPoint(x: 9, y: 6))
        outline.addLine(to: CGPoint(x: 19.6, y: 105.5))
        outline.addQuadCurve(to: CGPoint(x: 30.5, y: 115), control: CGPoint(x: 20.7, y: 115))
        outline.addLine(to: CGPoint(x: 69.5, y: 115))
        outline.addQuadCurve(to: CGPoint(x: 80.4, y: 105.5), control: CGPoint(x: 79.3, y: 115))
        outline.addLine(to: CGPoint(x: 91, y: 6))
        ctx.stroke(outline, with: .color(Color.white.opacity(mini ? 0.6 : 0.36)),
                   style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
        if !mini {
            var rim = Path()
            rim.move(to: CGPoint(x: 9, y: 6)); rim.addLine(to: CGPoint(x: 91, y: 6))
            ctx.stroke(rim, with: .color(Color.white.opacity(0.16)), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            var shine = Path()
            shine.move(to: CGPoint(x: 19.5, y: 18)); shine.addLine(to: CGPoint(x: 25.8, y: 82))
            ctx.stroke(shine, with: .color(Color.white.opacity(0.24)), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
            var glint = Path()
            glint.move(to: CGPoint(x: 83.2, y: 15)); glint.addLine(to: CGPoint(x: 81.6, y: 31))
            ctx.stroke(glint, with: .color(Color.white.opacity(0.14)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }

        // The drop, falling into the mouth of the glass.
        if !still, sinceDrop >= 0, sinceDrop < 0.42 {
            let p = CGFloat(sinceDrop / 0.42)
            let eased = p * p
            let dy = -26 + 38 * eased
            let alpha = p < 0.2 ? Double(p / 0.2) : (p > 0.8 ? Double((1 - p) / 0.2) : 1)
            var drop = Path()
            drop.move(to: CGPoint(x: 50, y: -7 + dy))
            drop.addCurve(to: CGPoint(x: 56.5, y: 6 + dy), control1: CGPoint(x: 54, y: -1 + dy), control2: CGPoint(x: 56.5, y: 2.5 + dy))
            drop.addArc(center: CGPoint(x: 50, y: 6 + dy), radius: 6.5, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            drop.addCurve(to: CGPoint(x: 50, y: -7 + dy), control1: CGPoint(x: 43.5, y: 2.5 + dy), control2: CGPoint(x: 46, y: -1 + dy))
            ctx.fill(drop, with: .color(color.opacity(alpha)))
        }
    }
}

// MARK: - The snowflake

/// The streak's mark: a day that reached its goal froze.
///
/// Six arms with a diamond tip and two pairs of branches around a hexagonal
/// ring, traced from the reference the design was approved with.
struct HydrationSnowflake: Shape {
    func path(in rect: CGRect) -> Path {
        let half: [CGPoint] = [
            CGPoint(x: 3.0, y: -16), CGPoint(x: 2.25, y: -23.75), CGPoint(x: 11, y: -30), CGPoint(x: 11, y: -36),
            CGPoint(x: 2.5, y: -30.5), CGPoint(x: 2.5, y: -34.5), CGPoint(x: 8.5, y: -38.5), CGPoint(x: 7, y: -43.5),
            CGPoint(x: 2.5, y: -41.5), CGPoint(x: 2.5, y: -44.5), CGPoint(x: 4.3, y: -47), CGPoint(x: 2.7, y: -50.3),
            CGPoint(x: 0, y: -52.5),
        ]
        let arm = half + half.dropLast().reversed().map { CGPoint(x: -$0.x, y: $0.y) }
        var p = Path()
        for k in 0..<6 {
            let a = CGFloat(k) * .pi / 3
            let points = arm.map { CGPoint(x: $0.x * cos(a) - $0.y * sin(a), y: $0.x * sin(a) + $0.y * cos(a)) }
            p.addLines(points)
            p.closeSubpath()
        }
        func hexagon(_ r: CGFloat, reversed: Bool) -> [CGPoint] {
            let pts = (0..<6).map { CGPoint(x: r * cos(CGFloat($0) * .pi / 3), y: r * sin(CGFloat($0) * .pi / 3)) }
            return reversed ? pts.reversed() : pts
        }
        p.addLines(hexagon(18.85, reversed: false)); p.closeSubpath()
        // Wound the other way, so the middle is a hole rather than more ice.
        p.addLines(hexagon(9.75, reversed: true)); p.closeSubpath()

        let scale = min(rect.width, rect.height) / 108
        return p.applying(CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: scale, y: scale))
    }
}

// MARK: - Shared pieces

private enum Ice {
    static let light = Color(hex: "#9EDCFF")
    static let mark = Color(hex: "#7AC4DF")
    static let text = Color(hex: "#BDE8FF")
    static let deep = Color(hex: "#2E8DB8")
}

private struct HydrationWho: View {
    var dot: Color = Color(hex: "#22D3EE")
    var detail: LocalizedStringKey? = "today"

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text("Hydration").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
            if let detail {
                Text(detail).font(.system(size: 12)).foregroundColor(Color(hex: "#9398A1"))
            }
        }
    }
}

private struct StreakPill: View {
    let days: Int
    let lit: Bool

    var body: some View {
        HStack(spacing: 4) {
            HydrationSnowflake().fill(lit ? Color(hex: "#0B0C0E") : Ice.text).frame(width: 12, height: 12)
            (days == 1 ? Text("1 day") : Text("\(days) days"))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .padding(.leading, 6).padding(.trailing, 8)
        .frame(height: 20)
        .foregroundColor(lit ? Color(hex: "#0B0C0E") : Ice.text)
        .background(lit ? Ice.light : Ice.light.opacity(0.16))
        .clipShape(Capsule())
    }
}

/// A burst around Mochi when the goal is reached: one ring and nine flecks,
/// once, and only while the store says it is celebrating.
private struct HydrationConfetti: View {
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(startedAt)
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                if t < 0.9 {
                    let p = CGFloat(t / 0.9)
                    let k = 0.55 + p
                    ctx.stroke(Path(ellipseIn: CGRect(x: centre.x - 34 * k, y: centre.y - 28 * k, width: 68 * k, height: 56 * k)),
                               with: .color(Ice.light.opacity(0.75 * Double(1 - p))), lineWidth: 2)
                }
                let colours: [Color] = [Ice.light, Color(hex: "#34D399"), Color(hex: "#F5F6F8"), Color(hex: "#F472B6"), Color(hex: "#22D3EE")]
                for i in 0..<9 {
                    let delay = Double(i % 4) * 0.04
                    let p = CGFloat((t - delay) / 1.2)
                    guard p > 0, p < 1 else { continue }
                    let eased = 1 - pow(1 - p, 3)
                    let angle = CGFloat(-200 + i * 28) * .pi / 180
                    let d = 22 + 44 * eased
                    let pos = CGPoint(x: centre.x + cos(angle) * d, y: centre.y + sin(angle) * d * 0.9)
                    let alpha = p < 0.22 ? Double(p / 0.22) : Double(1 - p)
                    let r: CGFloat = (i % 3 == 0 ? 3.2 : 2.4) * (0.4 + 0.6 * eased)
                    let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
                    let shape = i % 2 == 0 ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1)
                    ctx.fill(shape, with: .color(colours[i % colours.count].opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - The tab

struct HydrationView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = HydrationStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var streakCard: Bool { store.celebrates && store.settings.streakEnabled }

    var body: some View {
        ZStack {
            CardBackground(wash: !store.enabled || store.isPaused ? nil : (store.celebrates ? .green : .cyan))
            Group {
                if !store.enabled {
                    intro
                } else if streakCard {
                    streak
                } else {
                    main
                }
            }
            .padding(.leading, IslandConst.lead(108, flush: 18, hidden: state.hideCharacters))
            .padding(.trailing, 18)
            .padding(.vertical, 12)
        }
        .overlay(alignment: .leading) {
            // Over Mochi's gutter, which this card pads around but does not own.
            if store.celebrating, !reduceMotion, !state.hideCharacters, state.view == .hydration {
                HydrationConfetti().frame(width: 150, height: 150).offset(x: -23)
            }
        }
        .onChange(of: state.mode) { _, mode in
            if mode == .expanded { store.rollIfNeeded() }
        }
    }

    // MARK: Before it is set up

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            HydrationWho(detail: nil)
            Text("A glass of water, now and then")
                .font(.system(size: 15, weight: .semibold))
            Text("A few quick questions suggest a daily goal to start from. Reminders stay gentle and you can pause them.")
                .font(.system(size: 13)).foregroundColor(Color(hex: "#9398A1"))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 7) {
                PrimaryButton(L("Answer the questions")) { HydrationRoute.shared.open(.questions) }
                SecondaryButton(L("Just remind me")) { store.setEnabled(true) }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The glass

    private func glassButton(width: CGFloat, showsPortion: Bool) -> some View {
        Button(action: { store.log() }) {
            VStack(spacing: 7) {
                HydrationGlass(level: store.level, pulse: store.pulse)
                    .frame(width: width)
                if showsPortion {
                    Text(verbatim: "+" + HydrationText.amount(store.settings.portionML))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundColor(Color(hex: "#F1F2F4"))
                        .padding(.horizontal, 9).frame(height: 20)
                        .background(Color.white.opacity(0.09)).clipShape(Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassButtonStyle())
        .accessibilityLabel(glassLabel)
    }

    private var glassLabel: String {
        let portion = HydrationText.amount(store.settings.portionML)
        let total = HydrationText.amount(store.total)
        if store.goal.ml > 0 {
            return L("Log \(portion). \(total) of \(HydrationText.amount(store.goal.ml)) today.")
        }
        return L("Log \(portion). \(total) today.")
    }

    // MARK: The day

    private var main: some View {
        HStack(alignment: .center, spacing: 20) {
            glassButton(width: 96, showsPortion: true)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    HydrationWho()
                    Spacer(minLength: 4)
                    if store.settings.streakEnabled {
                        weekDots
                        if store.streak.days > 0 { StreakPill(days: store.streak.days, lit: store.streak.isFrozen(store.dayKey)) }
                    }
                    pauseButton
                }

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(verbatim: HydrationText.amount(store.total))
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .snappy(duration: 0.5), value: store.total)
                    if store.goal.ml > 0 {
                        Text("of \(HydrationText.amount(store.goal.ml))")
                            .font(.system(size: 13)).foregroundColor(Color(hex: "#9398A1"))
                    }
                }
                .padding(.top, 4)

                message
                    .font(.system(size: 13)).foregroundColor(Color(hex: "#9398A1"))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)

                HStack(spacing: 6) {
                    Text("Portion").font(.system(size: 11)).foregroundColor(Color(hex: "#9398A1")).padding(.trailing, 2)
                    ForEach(HydrationSettings.portions, id: \.self) { ml in
                        let selected = store.settings.portionML == ml
                        Button(action: { store.update { $0.portionML = ml } }) {
                            Text(verbatim: "\(ml) ml")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .padding(.horizontal, 10).frame(height: 24)
                                .background(selected ? Color(hex: "#F5F6F8") : Color.white.opacity(0.07))
                                .foregroundColor(selected ? Color(hex: "#0B0C0E") : Color(hex: "#B9BDC4"))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.top, 9)

                log.padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var message: Text {
        let g = store.goal
        if store.isPaused { return Text("Reminders paused. You can still log whenever you like.") }
        if g.kind == .limit {
            if store.total >= g.ml { return Text("You have reached today's limit.") }
            return Text("Up to \(HydrationText.amount(g.ml)) today. Reminders stop before you get there.")
        }
        if g.ml > 0, store.total >= g.ml {
            if store.total >= g.ml + store.settings.portionML {
                return Text("Today's goal is already reached. From here on, follow your thirst.")
            }
            if store.settings.streakEnabled, store.streak.days >= 2 {
                return Text("Today's goal reached: \(store.streak.days) days in a row. Reminders rest until tomorrow.")
            }
            return Text("Today's goal reached. Reminders rest until tomorrow.")
        }
        if store.entries.isEmpty { return Text("Your glass is waiting. Tap it when you drink.") }
        return Text("Tap the glass whenever you drink. At your own pace.")
    }

    private var weekDots: some View {
        let dots = store.week
        let frozen = dots.filter { $0 == .frozen }.count
        return HStack(spacing: 4) {
            ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                Circle()
                    .fill(dot == .frozen ? Ice.light : (dot == .rest ? Color(hex: "#94A3B8").opacity(0.5) : Color.clear))
                    .overlay(Circle().strokeBorder(
                        dot == .frozen ? Ice.light : (dot == .today ? Ice.light : Color.white.opacity(dot == .rest ? 0 : 0.22)),
                        lineWidth: 1.5))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("This week: \(frozen) of 7 days frozen"))
    }

    private var pauseButton: some View {
        let status: String = {
            if store.isPaused { return L("Reminders paused") }
            if store.remindersDone { return L("Reminders rest until tomorrow") }
            if let next = store.nextDue { return L("Next reminder at \(HydrationText.clock(next))") }
            return ""
        }()
        let action = store.isPaused ? L("Resume reminders") : L("Pause reminders")
        return Button(action: { store.isPaused ? store.resume() : store.pause(.indefinitely) }) {
            Image(systemName: store.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color(hex: "#F1F2F4"))
                .frame(width: 20, height: 20)
                .background(Color.white.opacity(0.08)).clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(status.isEmpty ? action : status + " — " + action)
        .accessibilityLabel(action)
    }

    private var log: some View {
        let recent = Array(store.entries.suffix(2).reversed())
        let more = store.entries.count - recent.count
        return HStack(spacing: 6) {
            Button(action: { store.undo() }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 9.5, weight: .bold))
                    Text("Undo").font(.system(size: 12.5, weight: .medium))
                }
                .padding(.leading, 9).padding(.trailing, 12).frame(height: 26)
                .background(Color.white.opacity(0.09)).foregroundColor(Color(hex: "#F1F2F4"))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.entries.isEmpty)
            .opacity(store.entries.isEmpty ? 0.4 : 1)

            ForEach(recent) { entry in
                HStack(spacing: 3) {
                    Text(verbatim: HydrationText.clock(entry.at) + " · " + HydrationText.amount(entry.ml))
                        .font(.system(size: 11).monospacedDigit()).foregroundColor(Color(hex: "#B9BDC4"))
                    Button(action: { store.remove(entry.id) }) {
                        Image(systemName: "xmark").font(.system(size: 6.5, weight: .heavy))
                            .foregroundColor(Color(hex: "#B9BDC4"))
                            .frame(width: 16, height: 16)
                            .background(Color.white.opacity(0.08)).clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Remove the \(HydrationText.amount(entry.ml)) logged at \(HydrationText.clock(entry.at))"))
                }
                .padding(.leading, 9).padding(.trailing, 4).frame(height: 24)
                .background(Color.white.opacity(0.07)).clipShape(Capsule())
                .lineLimit(1).fixedSize()
            }
            if more > 0 {
                Text("+\(more) today").font(.system(size: 11)).foregroundColor(Color(hex: "#9398A1")).lineLimit(1).fixedSize()
            }
        }
    }

    // MARK: The goal, reached

    private var streak: some View {
        let days = store.streak.days
        let mark = HydrationText.nextMark(after: days)
        let floor = HydrationText.previousMark(before: mark)
        let progress = CGFloat(days - floor) / CGFloat(max(1, mark - floor))
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HydrationWho(dot: Ice.light, detail: "today's goal reached")

                HStack(spacing: 8) {
                    HydrationSnowflake().fill(Ice.mark).frame(width: 28, height: 28)
                    (days <= 1 ? Text("First day frozen") : Text("\(days) days in a row"))
                        .font(.system(size: 24, weight: .semibold).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.top, 6)

                weekDiscs.padding(.top, 10)

                HStack(spacing: 10) {
                    Text("Next mark: \(mark) days").font(.system(size: 11)).foregroundColor(Color(hex: "#9398A1")).lineLimit(1).fixedSize()
                    Capsule().fill(Color.white.opacity(0.1))
                        .frame(width: 84, height: 6)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Ice.light).frame(width: max(6, 84 * progress), height: 6)
                        }
                    if store.streak.rests > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "moon.fill").font(.system(size: 8))
                            (store.streak.rests == 1 ? Text("1 rest day saved") : Text("\(store.streak.rests) rest days saved"))
                                .font(.system(size: 11))
                        }
                        .foregroundColor(Color(hex: "#B7C2D0"))
                        .padding(.leading, 6).padding(.trailing, 8).frame(height: 20)
                        .background(Color(hex: "#94A3B8").opacity(0.16)).clipShape(Capsule())
                        .lineLimit(1).fixedSize()
                    }
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 5) {
                glassButton(width: 62, showsPortion: false)
                Text(verbatim: HydrationText.amount(store.total))
                    .font(.system(size: 11).monospacedDigit()).foregroundColor(Color(hex: "#9398A1"))
                Button(action: { store.undo() }) {
                    Text("Undo").font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9).frame(height: 20)
                        .background(Color.white.opacity(0.09)).foregroundColor(Color(hex: "#F1F2F4"))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(width: 84)
        }
    }

    private var weekDiscs: some View {
        let dots = store.week
        // In the app's language, not the Mac's: the card around them is.
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLanguage.current.locale
        var symbols = calendar.veryShortStandaloneWeekdaySymbols   // Sunday first
        if symbols.count == 7 { symbols.append(symbols.removeFirst()) }     // Monday first
        let frozen = dots.filter { $0 == .frozen }.count
        return HStack(spacing: 8) {
            ForEach(Array(dots.enumerated()), id: \.offset) { index, dot in
                VStack(spacing: 4) {
                    ZStack {
                        switch dot {
                        case .frozen:
                            Circle().fill(LinearGradient(colors: [.white, Color(hex: "#D9EFF9")], startPoint: .topLeading, endPoint: .bottomTrailing))
                            HydrationSnowflake().fill(Ice.deep).frame(width: 17, height: 17)
                        case .rest:
                            Circle().fill(Color(hex: "#94A3B8").opacity(0.16))
                            Circle().strokeBorder(Color(hex: "#94A3B8").opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                            Image(systemName: "moon.fill").font(.system(size: 10)).foregroundColor(Color(hex: "#B7C2D0"))
                        case .today, .missed, .future:
                            Circle().strokeBorder(Color.white.opacity(dot == .today ? 0.5 : 0.2), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 26, height: 26)
                    Text(verbatim: index < symbols.count ? symbols[index] : "")
                        .font(.system(size: 10)).foregroundColor(Color(hex: "#9398A1"))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("This week: \(frozen) of 7 days frozen"))
    }
}

/// The glass presses like something you can push: down a little, back with a
/// spring. `.plain` alone would make it look painted on.
private struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// MARK: - The reminder

/// "How about some water?" — the notification, and what it says once answered.
struct HydrationSipView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = HydrationStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            CardBackground(wash: store.prompt == .goal ? .green : .cyan)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    HydrationWho(detail: nil)
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 4) {
                    HydrationGlass(level: store.level, pulse: store.pulse).frame(width: 46)
                    Text(verbatim: totalLine)
                        .font(.system(size: 11).monospacedDigit()).foregroundColor(Color(hex: "#9398A1"))
                        .lineLimit(1).fixedSize()
                }
                .frame(minWidth: 84)
            }
            .padding(.leading, IslandConst.lead(108, flush: 18, hidden: state.hideCharacters))
            .padding(.trailing, 18)
        }
        .overlay(alignment: .leading) {
            if store.celebrating, !reduceMotion, !state.hideCharacters, state.view == .sip {
                HydrationConfetti().frame(width: 150, height: 150).offset(x: -23)
            }
        }
        .onChange(of: state.view) { old, new in
            // Leaving the card ends what it was saying.
            if old == .sip, new != .sip { store.clearPrompt() }
        }
        .onChange(of: state.mode) { _, mode in
            if mode != .expanded, state.view == .sip { store.clearPrompt() }
        }
    }

    private var totalLine: String {
        let total = HydrationText.amount(store.total)
        return store.goal.ml > 0 ? total + " " + L("of \(HydrationText.amount(store.goal.ml))") : total
    }

    @ViewBuilder private var content: some View {
        let portion = HydrationText.amount(store.settings.portionML)
        switch store.prompt {
        case .logged:
            lines(title: Text("Logged: +\(portion)"),
                  sub: store.goal.ml > 0
                    ? Text("\(HydrationText.amount(store.total)) of \(HydrationText.amount(store.goal.ml)) today. Nice sip.")
                    : Text("\(HydrationText.amount(store.total)) today. Nice sip."))
            HStack(spacing: 7) {
                PrimaryButton(L("I drank \(portion) more")) { store.log() }
                SecondaryButton(L("Undo")) { store.undo() }
            }
            .padding(.top, 8)
        case .goal:
            lines(title: Text("Congratulations, today's goal is reached!"),
                  sub: Text("Glass full, mascot full. Reminders rest until tomorrow."))
            HStack(spacing: 7) {
                SecondaryButton(L("Undo")) { store.undo() }
            }
            .padding(.top, 8)
        case .snoozed:
            lines(title: Text("Deal, I'll be back in 30 min."),
                  sub: Text("If you drink before that, just tap the glass."))
            HStack(spacing: 7) {
                SecondaryButton(L("Undo")) { store.unsnooze() }
            }
            .padding(.top, 8)
        case .reminder, .none:
            lines(title: store.name.isEmpty ? Text("How about some water?") : Text("\(store.name)! How about some water?"),
                  sub: lastLog)
            HStack(spacing: 7) {
                PrimaryButton(L("I drank \(portion)")) { store.log() }
                SecondaryButton(L("Later")) { store.snooze() }
            }
            .padding(.top, 8)
        }
    }

    private var lastLog: Text {
        guard let last = store.entries.last?.at else { return Text("Nothing logged yet today.") }
        let minutes = max(1, Int(Date().timeIntervalSince(last) / 60))
        return Text("Your last log was \(HydrationText.duration(minutes: minutes)) ago.")
    }

    @ViewBuilder private func lines(title: Text, sub: Text) -> some View {
        title.font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8).padding(.top, 4)
        sub.font(.system(size: 13)).foregroundColor(Color(hex: "#9398A1")).lineLimit(1).minimumScaleFactor(0.85).padding(.top, 1)
    }
}

// MARK: - The compact bar

/// The closed notch, while a reminder waits for an answer: a small glass at
/// today's level and a slow ring around it.
struct CompactHydrationCue: View {
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var out = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color(hex: "#22D3EE"), lineWidth: 1.5)
                .frame(width: 18, height: 18)
                .scaleEffect(out ? 1.5 : 0.9)
                .opacity(out ? 0 : 0.8)
            HydrationGlass(level: level, mini: true).frame(width: 11)
        }
        .frame(width: 28, height: 28)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { out = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Going to Settings

/// Where in the Hydration pane a button on the island wants Settings to open.
@MainActor
final class HydrationRoute: ObservableObject {
    static let shared = HydrationRoute()

    enum Screen: Equatable {
        case main, questions, estimate, manual, sources
    }

    @Published var screen: Screen = .main

    private init() {}

    func open(_ target: Screen) {
        screen = target
        UserDefaults.standard.set("hydration", forKey: "settingsSection")
        NotificationCenter.default.post(name: .openFullSettings, object: nil)
    }
}
