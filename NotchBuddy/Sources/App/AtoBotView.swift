//
//  AtoBotView.swift
//  NotchBuddy
//
//  Draws Ato's mascot (AtoBot.swift) and keeps it alive: which state it is
//  in, how long it has been in it, where it is looking.
//
//  Ato does not wear a Mochi. Wherever the Ato pill would put a Mochi — its
//  mini bot, the big bot while Ato owns the island — this draws the orb from
//  Actuar's own engine instead, and the mark in the ring and in Settings is a
//  still of the same orb.
//

import SwiftUI

// MARK: - Drawing

enum AtoBotRenderer {
    /// Draws `scene` with the orb's centre at `center`, `unit` points per
    /// orb unit (the orb's radius is 100), then `motion` on top — the blog's
    /// whole-body gesture, in orb units.
    static func draw(_ scene: AtoScene, in context: GraphicsContext, center: CGPoint, unit: CGFloat,
                     motion: AtoScene.Affine = .identity) {
        var root = context
        root.translateBy(x: center.x, y: center.y)
        root.scaleBy(x: unit, y: unit)
        root.concatenate(cg(motion))

        for layer in scene.layers where layer.opacity > 0.001 && layer.s > 0 {
            var path = Path()
            for (i, p) in layer.points.enumerated() {
                let pt = CGPoint(x: p.0, y: p.1)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.closeSubpath()
            var c = root
            c.concatenate(cg(layer.transform))
            c.opacity = layer.opacity
            c.fill(path, with: .color(Color(hex: layer.fill)))
        }

        if scene.eyesOpacity > 0.001 {
            var eyes = root
            eyes.concatenate(cg(scene.eyesTransform))
            for mark in scene.eyes {
                var c = eyes
                switch mark {
                case let .dot(cx, cy, ry, op):
                    c.opacity = scene.eyesOpacity * op
                    c.fill(Path(ellipseIn: CGRect(x: cx - 26, y: cy - ry, width: 52, height: ry * 2)), with: .color(.white))
                case let .arc(x0, y0, qx, qy, x1, y1, w, op):
                    c.opacity = scene.eyesOpacity * op
                    var p = Path()
                    p.move(to: CGPoint(x: x0, y: y0))
                    p.addQuadCurve(to: CGPoint(x: x1, y: y1), control: CGPoint(x: qx, y: qy))
                    c.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: w, lineCap: .round))
                }
            }
        }

        for d in scene.decor {
            var c = root
            c.opacity = min(1, max(0, d.a))
            switch d.kind {
            case .badge:
                let x = d.x * 100, y = d.y * 100, r = d.r * 100
                c.fill(Path(ellipseIn: CGRect(x: x - r - 7, y: y - r - 7, width: (r + 7) * 2, height: (r + 7) * 2)),
                       with: .color(Color(hex: scene.badgeRing)))
                c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                       with: .color(Color(hex: AtoBot.orange)))
            case .text(let txt):
                c.draw(Text(verbatim: txt)
                        .font(.system(size: max(1, d.s * 100), weight: .heavy))
                        .foregroundColor(.white),
                       at: CGPoint(x: d.x * 100, y: d.y * 100), anchor: .center)
            }
        }
    }

    static func cg(_ m: AtoScene.Affine) -> CGAffineTransform {
        CGAffineTransform(a: m.a, b: m.b, c: m.c, d: m.d, tx: m.e, ty: m.f)
    }

    /// The blog's CSS transform on the orb — `translateY(ty%) rotate(rot)
    /// scale(sx, sy)` about a point 62 % of the way down its 320-unit box —
    /// as an affine in orb units, faded in by `weight`.
    static func motion(_ m: (ty: Double, rot: Double, sx: Double, sy: Double), weight w: Double) -> AtoScene.Affine {
        let originY = -160 + 0.62 * 320
        return AtoScene.Affine.identity
            .translated(0, originY)
            .translated(0, m.ty * 3.2 * w)
            .rotated(m.rot * w)
            .scaled(1 + (m.sx - 1) * w, 1 + (m.sy - 1) * w)
            .translated(0, -originY)
    }
}

// MARK: - What it is doing

extension AtoState {
    /// What a pill's state means for Ato. A message waiting is the badge;
    /// a dizzy slap is "I didn't get that".
    init(_ state: BotState) {
        switch state {
        case .idle:                           self = .idle
        case .working, .thinking, .searching: self = .thinking
        case .approval, .question:            self = .notify
        case .finished:                       self = .success
        case .error, .dizzy:                  self = .error
        case .ratelimit:                      self = .offline
        case .sleeping:                       self = .sleep
        }
    }

    /// The pill's state, unless Ato itself is not reachable — then it is
    /// offline, whatever the pill says, and still thinking while it connects.
    @MainActor
    static func current(_ state: BotState) -> AtoState {
        switch AtoClient.shared.state {
        case .connected:              return AtoState(state)
        case .connecting:             return .thinking
        case .disconnected, .failed:  return .offline
        }
    }
}

// MARK: - Keeping time

/// One orb's clock and memory: when it started, which state it is in and
/// since when, where its eyes are. A class, held in `@StateObject`, so it
/// lives as long as the view and costs nothing between frames.
@MainActor
final class AtoBotDriver: ObservableObject {
    /// The big bot plays the blog hero: gestures every 6 s and eyes that
    /// follow the pointer. A mini bot plays the blog's small orb: neither.
    let lively: Bool

    private var startedAt: Double?
    private var lastNow = 0.0
    private var current: AtoState = .idle
    private var previous: AtoState = .idle
    private var enteredAt = 0.0
    private var requested: AtoState?
    /// A state that plays out once whatever is asked for meanwhile — the
    /// welcome — and when it ends.
    private var oneShot: (state: AtoState, until: Double)?
    private var pointer = AtoVec(x: -0.6, y: 0.06)

    init(lively: Bool) { self.lively = lively }

    /// The pose for this frame, and the whole-body move to draw it with.
    func frame(now: Double, state asked: AtoState, pointer target: AtoVec?) -> (scene: AtoScene, motion: AtoScene.Affine) {
        if startedAt == nil {
            startedAt = now
            lastNow = now
        }
        let s = now - startedAt!
        let dt = min(0.25, max(0, now - lastNow))
        lastNow = now
        // The blog starts its big orb 0.6 s into its clock and its small one 3.1.
        let T = (lively ? 0.6 : 3.1) + s

        // Coming back from offline it greets you, the way the widget does when
        // it first opens. The big bot also does it the first time it draws.
        if requested == nil, lively, asked != .offline {
            oneShot = (.welcome, T + AtoState.welcome.spec.dur)
        } else if requested == .offline, asked != .offline {
            oneShot = (.welcome, T + AtoState.welcome.spec.dur)
        }
        requested = asked
        if let shot = oneShot, T >= shot.until || asked == .offline { oneShot = nil }
        let want = oneShot?.state ?? asked

        if s == 0 {
            // First frame: nothing to blend from. A welcome starts from its
            // beginning; anything else as the blog starts it, with tl = T.
            current = want
            previous = want
            enteredAt = want == .welcome ? T : 0
        } else if want != current {
            previous = current
            current = want
            enteredAt = T
        }
        let tl = T - enteredAt

        var X = AtoContext()
        var motion = AtoScene.Affine.identity
        if lively {
            // The blog's driver: the gaze eases toward the pointer (or toward
            // where it looks at rest) and, mid-gesture, straight at you.
            let g = AtoBot.gesture(s).g
            let base = target ?? AtoBot.idleLook(s)
            let goal = AtoVec(x: base.x * (1 - g), y: base.y * (1 - g) + 0.04 * g)
            let k = 1 - pow(1 - 0.16, dt / 0.03)
            pointer = AtoVec(x: pointer.x + (goal.x - pointer.x) * k, y: pointer.y + (goal.y - pointer.y) * k)
            X = AtoContext(expr: AtoBot.restingFace(s), energy: 1, follow: true, pointer: pointer, followW: 1)

            // The gesture moves the whole body, so only at rest: faded in as it
            // settles into idle and out as it leaves.
            let fade = AtoBot.easeInOut(tl / 0.5)
            let weight = current == .idle ? (previous == .idle ? 1 : fade) : (previous == .idle && tl < 0.5 ? 1 - fade : 0)
            if weight > 0 { motion = AtoBotRenderer.motion(AtoBot.bodyMotion(s), weight: weight) }
        }

        let pose = AtoBot.sample(T, state: current, tl: tl, previous: previous,
                                 previousAt: previous.spec.dur, X)
        return (AtoBot.scene(pose), motion)
    }
}

// MARK: - Views

/// The orb, alive, sized like a Mochi in the same frame: radius 0.3 of the
/// width, so it drops into any slot a `MiniBotCanvasView` fills.
struct AtoBotView: View {
    /// The Ato pill's state. Read with the connection every frame, so going
    /// offline shows without anything else having to redraw the view.
    var botState: BotState
    var lively = false
    var paused = false

    @StateObject private var driver: AtoBotDriver

    init(botState: BotState, lively: Bool = false, paused: Bool = false) {
        self.botState = botState
        self.lively = lively
        self.paused = paused
        _driver = StateObject(wrappedValue: AtoBotDriver(lively: lively))
    }

    var body: some View {
        // 30 frames a second, as the blog draws it; stopped when hidden.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
            Canvas { context, size in
                let frame = driver.frame(now: timeline.date.timeIntervalSinceReferenceDate,
                                         state: AtoState.current(botState), pointer: nil)
                AtoBotView.draw(frame, in: context, size: size)
            }
        }
        .accessibilityHidden(true)
    }

    /// Where a Mochi's body would be in a canvas this size.
    static func draw(_ frame: (scene: AtoScene, motion: AtoScene.Affine), in context: GraphicsContext,
                     size: CGSize, overhang: CGFloat = 0) {
        let R = size.width * 0.3
        AtoBotRenderer.draw(frame.scene, in: context,
                            center: CGPoint(x: size.width / 2, y: size.height / 2 + overhang / 2 + R * 0.06),
                            unit: R / 100, motion: frame.motion)
    }
}
