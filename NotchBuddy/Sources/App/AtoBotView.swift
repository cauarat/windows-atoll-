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
//  The one thing of a Mochi's it can put on is Christmas (`MochiFestive`): the
//  parts are generated for the orb as they are for every Mochi body, and drawn
//  here round an orb that is itself untouched.
//

import SwiftUI

// MARK: - Drawing

enum AtoBotRenderer {
    /// Draws `scene` with the orb's centre at `center`, `unit` points per
    /// orb unit (the orb's radius is 100), then `motion` on top — the blog's
    /// whole-body gesture, in orb units.
    ///
    /// `festive` is what Ato has on for Christmas, if anything, and `time` the
    /// clock its lights blink by — nil for a still.
    @MainActor
    static func draw(_ scene: AtoScene, in context: GraphicsContext, center: CGPoint, unit: CGFloat,
                     motion: AtoScene.Affine = .identity,
                     festive: MochiFestive? = nil, time: Double? = nil) {
        var root = context
        root.translateBy(x: center.x, y: center.y)
        root.scaleBy(x: unit, y: unit)
        root.concatenate(cg(motion))

        let dress = Dress(festive, scene: scene, root: root, time: time)
        dress?.draw(\.headBehind)

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

        dress?.draw(\.texture)

        if scene.eyesOpacity > 0.001 {
            var eyes = root
            eyes.concatenate(cg(scene.eyesTransform))
            if scene.blush > 0.01 {
                // The original's cheeks: an ellipse 52 × 42 at (±118, 46), its
                // radial gradient stretched to the ellipse as SVG stretches
                // one to its bounding box.
                let pink = Color(hex: "#FFB4C4"), b = scene.blush
                let gradient = Gradient(stops: [
                    .init(color: pink.opacity(b), location: 0),
                    .init(color: pink.opacity(b * 0.92), location: 0.62),
                    .init(color: pink.opacity(0), location: 1),
                ])
                for sd in [-1.0, 1.0] {
                    var c = eyes
                    c.opacity = scene.eyesOpacity
                    c.translateBy(x: sd * 118, y: 46)
                    c.scaleBy(x: 1, y: 21.0 / 26.0)
                    c.fill(Path(ellipseIn: CGRect(x: -26, y: -26, width: 52, height: 52)),
                           with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: 26))
                }
            }
            for mark in scene.eyes {
                var c = eyes
                switch mark {
                case .dot where dress?.outfit.hasEyes == true:
                    break   // Christmas eyes, below
                case let .dot(cx, cy, ry, op):
                    c.opacity = scene.eyesOpacity * op
                    c.fill(Path(ellipseIn: CGRect(x: cx - 26, y: cy - ry, width: 52, height: ry * 2)), with: .color(.white))
                case let .arc(x0, y0, qx, qy, x1, y1, w, op):
                    c.opacity = scene.eyesOpacity * op
                    var p = Path()
                    p.move(to: CGPoint(x: x0, y: y0))
                    p.addQuadCurve(to: CGPoint(x: x1, y: y1), control: CGPoint(x: qx, y: qy))
                    c.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: w, lineCap: .round))
                case let .glyph(_, pts, w, op):
                    c.opacity = scene.eyesOpacity * op
                    var p = Path()
                    for (i, v) in pts.enumerated() {
                        let pt = CGPoint(x: v.x, y: v.y)
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    if w == 0 {
                        p.closeSubpath()
                        c.fill(p, with: .color(.white))
                    } else {
                        c.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            dress?.drawEyes()
        }

        dress?.draw(\.extraFace)
        dress?.draw(\.headFront)
        dress?.draw(\.extraTop)

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

    /// Ato's Christmas parts for one frame.
    ///
    /// The data is drawn against the orb at radius 100, centred where the orb
    /// is — the scene's own space once `AtoBot.K` has brought its 196 down. So
    /// the parts go inside the scene's `body` transform, the one the three
    /// layers are in, and a hat rides every bounce, squash and tumble the orb
    /// makes. There is no silhouette to ask the engine for — the orb is three
    /// discs turning under each other — so what is clipped is clipped to the
    /// outline the generator fitted the parts to.
    @MainActor
    private struct Dress {
        let outfit: MochiFestiveArt.Outfit
        let scene: AtoScene
        let palette: MochiFestiveArt.Palette
        let time: Double?
        /// In the data's units, inside `body`: unclipped, and clipped to the orb.
        let plain: GraphicsContext
        let clipped: GraphicsContext

        init?(_ festive: MochiFestive?, scene: AtoScene, root: GraphicsContext, time: Double?) {
            guard let outfit = MochiFestiveArt.outfit(festive, body: "ato") else { return nil }
            self.outfit = outfit
            self.scene = scene
            self.time = time
            // The front disc's colour this frame: Ato's blue, or the grey it
            // goes when it is offline — elf ears go grey with it.
            palette = .ato(skinHex: scene.layers.last?.fill ?? AtoBot.blue)
            var c = root
            c.concatenate(AtoBotRenderer.cg(scene.body))
            c.scaleBy(x: 1 / AtoBot.K, y: 1 / AtoBot.K)
            plain = c
            if let outline = MochiFestiveArt.clip(body: "ato") { c.clip(to: outline) }
            clipped = c
        }

        func draw(_ part: KeyPath<MochiFestiveArt.Outfit, [MochiFestiveArt.Prim]>) {
            MochiFestiveArt.draw(outfit[keyPath: part], plain: plain, clipped: clipped,
                                 palette: palette, time: time)
        }

        /// The eyes, in place of the white dots.
        ///
        /// Only the dots. A happy arc, a shut one or a borrowed Mochi glyph is
        /// Ato expressing something and is drawn by the caller as ever, which
        /// is the rule a Mochi's Christmas eyes follow too. Each dot says where
        /// its eye is and how far shut, so the part is moved to it and squashed
        /// to match; what lies over both moves by the mean and does not blink.
        func drawEyes() {
            guard outfit.hasEyes else { return }
            let k = AtoBot.K
            // From `body` to where the face is this frame — the caller's own
            // `eyesTransform`, less the `body` these contexts already carry.
            func face(_ base: GraphicsContext) -> GraphicsContext {
                var c = base
                c.scaleBy(x: k, y: k)
                c.translateBy(x: scene.fx, y: scene.fy + AtoBot.EY)
                c.scaleBy(x: scene.eyeS, y: scene.eyeS)
                c.translateBy(x: 0, y: -AtoBot.EY)
                return c
            }
            let plainFace = face(plain), clippedFace = face(clipped)

            var shiftX = 0.0, shiftY = 0.0, seen = 0.0, shown = 0.0
            for mark in scene.eyes {
                guard case let .dot(cx, cy, ry, op) = mark else { continue }
                let sd: Double = cx < 0 ? -1 : 1
                shiftX += cx - sd * AtoBot.EYX
                shiftY += cy - AtoBot.EY
                seen += 1
                shown = max(shown, op)
                func placed(_ base: GraphicsContext) -> GraphicsContext {
                    var c = base
                    c.translateBy(x: cx, y: cy)
                    c.scaleBy(x: 1 / k, y: ry / 26 / k)
                    c.translateBy(x: -sd * outfit.eyeRest.x, y: -outfit.eyeRest.y)
                    return c
                }
                MochiFestiveArt.draw(sd < 0 ? outfit.eyeLeft : outfit.eyeRight,
                                     plain: placed(plainFace), clipped: placed(clippedFace),
                                     palette: palette, time: time, alpha: scene.eyesOpacity * op)
            }

            // Frames stay on through an expression; cheeks go with the eyes.
            guard seen > 0 || outfit.eyesAreWorn else { return }
            func over(_ base: GraphicsContext) -> GraphicsContext {
                var c = base
                if seen > 0 { c.translateBy(x: shiftX / seen, y: shiftY / seen) }
                c.scaleBy(x: 1 / k, y: 1 / k)
                return c
            }
            MochiFestiveArt.draw(outfit.eyeOver, plain: over(plainFace), clipped: over(clippedFace),
                                 palette: palette, time: time,
                                 alpha: scene.eyesOpacity * (outfit.eyesAreWorn ? 1 : shown))
        }
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
    /// What a pill's state means for Ato. A message waiting is the badge.
    /// Dizzy is not here as an error: a dizzy Ato is itself, with a Mochi's
    /// spiral eyes and its tumble (`AtoReaction`).
    init(_ state: BotState) {
        switch state {
        case .idle, .dizzy:                   self = .idle
        case .working, .thinking, .searching: self = .thinking
        case .approval, .question:            self = .notify
        case .finished:                       self = .success
        case .error:                          self = .error
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

// MARK: - Reacting like a Mochi

/// What a Mochi would be doing right now, read off its engine, for Ato to do
/// in its own body.
///
/// Ato is not given its own copy of the hover, the love, the slap, the dizzy
/// spell or the dance. The engine behind it gets every one of them already —
/// the island sends them to whoever is drawn — and runs them on the same
/// timers, with the same sounds. Ato reads where that engine is looking, what
/// its eyes are, how pink its cheeks are and how its body is squashed, tilted
/// and thrown, and wears it. A reaction added to Mochi reaches Ato for free.
struct AtoReaction {
    /// Where the eyes point, in Ato's look units (+y is down).
    var look: AtoVec
    /// Eyelids: 1 open, 0 shut — the engine's blinks in place of Ato's own.
    var lid: Double
    /// A Mochi eye shape being shown, if Ato has to show one too.
    var eye: EyeShape?
    var blush: Double
    var eyeScale: Double
    /// The body, in orb radii and radians: offset, squash, tilt and tumble.
    var ox, oy, sx, sy, tilt, roll: Double

    /// Nothing happening: what `frame` uses when no engine is given.
    var isQuiet: Bool { eye == nil && blush < 0.05 }

    @MainActor
    static func from(_ e: BotEngine) -> AtoReaction {
        var eye = e.eyeOverride
        if e.state == .dizzy { eye = .spiral }
        // A dancing Mochi is a happy one, in the calm states.
        if eye == nil, e.isDancing, e.dancingLevel > 0.15, !e.isMini, e.state == .idle || e.state == .finished {
            eye = .happy
        }
        // The engine turns its look into a head turn of 0.62 and a nod of
        // 0.5, eyes up for a positive nod; Ato's look is ±1, +y down.
        return AtoReaction(look: AtoVec(x: Double(e.yaw) / 0.62, y: -Double(e.pitch) / 0.5),
                           lid: Double(e.open), eye: eye, blush: Double(e.blush), eyeScale: Double(e.es),
                           ox: Double(e.ox), oy: Double(e.oy), sx: Double(e.sx), sy: Double(e.sy),
                           tilt: Double(e.tilt), roll: Double(e.roll))
    }

    /// The face the reaction asks for, put on a pose that has been sampled.
    func dress(_ P: inout AtoPose) {
        AtoBot.react(&P, eye: eye, blush: blush, eyeScale: eyeScale)
    }

    /// The body move, in orb units, about the orb's centre — as the engine
    /// moves a Mochi about its own.
    var motion: AtoScene.Affine {
        AtoScene.Affine.identity
            .translated(ox * 100, oy * 100)
            .rotated((tilt + roll) * 180 / Double.pi)
            .scaled(sx, sy)
    }
}

// MARK: - Keeping time

/// One orb's clock and memory: when it started, which state it is in and
/// since when, where its eyes are. A class, held in `@StateObject`, so it
/// lives as long as the view and costs nothing between frames.
@MainActor
final class AtoBotDriver: ObservableObject {
    /// The big bot plays the blog hero: gestures every 6 s. A mini bot plays
    /// the blog's small orb, without them.
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
    /// `reaction` is the Mochi engine behind this orb: given, Ato looks where
    /// it looks, blinks when it blinks and reacts as it reacts.
    func frame(now: Double, state asked: AtoState, reaction: AtoReaction?) -> (scene: AtoScene, motion: AtoScene.Affine) {
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

        // The blog's gesture every 6 s, unless the engine has Ato in the
        // middle of a reaction of its own.
        let quiet = reaction?.isQuiet ?? true
        var X = AtoContext()
        if let reaction {
            // A Mochi's eyes follow it in every state, and blink when it blinks.
            X.follow = true
            X.gazeAlways = true
            X.pointer = reaction.look
            X.lid = max(0.06, reaction.lid)
            if lively, quiet { X.expr = AtoBot.restingFace(s) }
        } else if lively {
            // The blog's driver: the gaze eases toward where it looks at rest.
            let g = AtoBot.gesture(s).g
            let base = AtoBot.idleLook(s)
            let goal = AtoVec(x: base.x * (1 - g), y: base.y * (1 - g) + 0.04 * g)
            let k = 1 - pow(1 - 0.16, dt / 0.03)
            pointer = AtoVec(x: pointer.x + (goal.x - pointer.x) * k, y: pointer.y + (goal.y - pointer.y) * k)
            X = AtoContext(expr: AtoBot.restingFace(s), energy: 1, follow: true, pointer: pointer, followW: 1)
        }

        var motion = AtoScene.Affine.identity
        if lively, quiet {
            // The gesture moves the whole body, so only at rest: faded in as it
            // settles into idle and out as it leaves.
            let fade = AtoBot.easeInOut(tl / 0.5)
            let weight = current == .idle ? (previous == .idle ? 1 : fade) : (previous == .idle && tl < 0.5 ? 1 - fade : 0)
            if weight > 0 { motion = AtoBotRenderer.motion(AtoBot.bodyMotion(s), weight: weight) }
        }

        var pose = AtoBot.sample(T, state: current, tl: tl, previous: previous,
                                 previousAt: previous.spec.dur, X)
        if let reaction {
            reaction.dress(&pose)
            motion = reaction.motion.concat(motion)
        }
        return (AtoBot.scene(pose), motion)
    }
}

// MARK: - Drawing in a Mochi's frame

enum AtoBotView {
    /// Where a Mochi's body would be in a canvas this size: radius 0.3 of the
    /// width, so the orb drops into any slot a `BotCanvasView` or
    /// `MiniBotCanvasView` fills.
    ///
    /// `festive` is what the Ato pill's character has on for Christmas — the
    /// only part of a `MochiCharacter` that means anything to an orb.
    @MainActor
    static func draw(_ frame: (scene: AtoScene, motion: AtoScene.Affine), in context: GraphicsContext,
                     size: CGSize, overhang: CGFloat = 0,
                     festive: MochiFestive? = nil, time: Double? = nil) {
        let R = size.width * 0.3
        AtoBotRenderer.draw(frame.scene, in: context,
                            center: CGPoint(x: size.width / 2, y: size.height / 2 + overhang / 2 + R * 0.06),
                            unit: R / 100, motion: frame.motion, festive: festive, time: time)
    }
}
