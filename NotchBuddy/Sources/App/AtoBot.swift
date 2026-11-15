//
//  AtoBot.swift
//  NotchBuddy
//
//  Ato's own mascot, ported from Actuar's engine rather than imitated.
//
//  The source is design/ato/actuar-bot-v3.js — "Actuar Bot v3", the script
//  behind the orb on blog.actuar.com and the support launcher on
//  novo.actuar.com. Everything here is a line-for-line port of the parts of it
//  Notchy uses: the three-layer orb, the dot eyes, the blink, and eight of its
//  states. scripts/test-ato-bot.sh runs the original under Node and holds this
//  file to it, pose for pose and shape for shape, so a change that is not in
//  the original is a failing test, not a judgement call.
//
//  Pure: Foundation only, no SwiftUI, so the test can compile it alone.
//  AtoBotView.swift draws what `AtoBot.scene` describes.
//

import Foundation

// MARK: - Pose

/// One eye, as far as dot eyes care. The official eye has a dozen more
/// numbers — iris, lids, brows — that only its other eye styles draw; Ato
/// itself only ever wears "pontinhos", which reads these five.
struct AtoEye: Equatable {
    var sy = 1.0, pdx = 1.0, pdy = -1.0, arc = 0.0, shut = 0.0
}

struct AtoVec: Equatable {
    var x = 0.0, y = 0.0
}

/// One of the three layers. `rot` is optional because the original's is: a
/// pose that does not name it leaves it out, and a blend drops it rather than
/// easing it (see `mixLayer`).
struct AtoLayer: Equatable {
    var x = 0.0, y = 0.0, s = 1.0, a = 1.0
    var rot: Double? = nil
}

/// What a state says about a layer; nil keeps the base value.
struct AtoLayerPatch {
    var x: Double? = nil, y: Double? = nil, s: Double? = nil, a: Double? = nil, rot: Double? = nil
}

/// Things drawn around the orb rather than on it.
struct AtoDecor: Equatable {
    enum Kind: Equatable { case badge, text(String) }
    var kind: Kind
    var x = 0.0, y = 0.0
    /// Badge radius, in orb radii.
    var r = 0.0
    /// Text size, in orb radii.
    var s = 0.0
    var a = 1.0
}

struct AtoPose: Equatable {
    var r = 1.0, sx = 1.0, sy = 1.0, x = 0.0, y = 0.0, roll = 0.0, anchor = 0.0, gray = 0.0
    var look = AtoVec()
    var eyes = [AtoEye(), AtoEye()]
    var eyeA = 1.0
    var twist = 0.0, wob = 1.0, spread = 0.0
    var lay = [AtoLayer(), AtoLayer(), AtoLayer()]
    var fo = AtoVec()
    var eyeS = 1.0
    var decor: [AtoDecor] = []
    var drift = 1.0, breathe = 1.0
    var blinkOK = 1.0, gazeFree = 0.0
    /// Set by `post`: the clock the layers turn by, and how lively it is.
    var T = 0.0, energy = 1.0
}

/// What a state's pose function returns: only what it changes.
struct AtoPatch {
    var r: Double? = nil, sx: Double? = nil, sy: Double? = nil, x: Double? = nil, y: Double? = nil
    var roll: Double? = nil, anchor: Double? = nil, gray: Double? = nil
    var look: AtoVec? = nil
    var eyes: [AtoEye]? = nil
    var eyeA: Double? = nil
    var twist: Double? = nil, wob: Double? = nil, spread: Double? = nil
    var lay: [AtoLayerPatch]? = nil
    var eyeS: Double? = nil
    var decor: [AtoDecor]? = nil
    var drift: Double? = nil, breathe: Double? = nil
    var blinkOK: Double? = nil, gazeFree: Double? = nil
}

/// The inputs a pose depends on besides time — the original's `X`.
struct AtoContext {
    /// The resting face (the original's `expr`): the eyes a state shows when
    /// it does not choose its own.
    var expr: [AtoEye] = AtoBot.face(.neutro)
    var energy = 1.0
    var follow = false
    var pointer: AtoVec? = nil
    var followW = 1.0
}

// MARK: - States

/// The states Notchy plays. The original has more — searching, speaking,
/// handoff, goodbye — that nothing here would trigger.
enum AtoState: String, CaseIterable {
    case idle, thinking, notify, success, error, offline, sleep, welcome

    /// Seconds it lasts in the original's timeline, and the spring it settles
    /// into: frequency, damping. `blinkIn` blinks once on the way in.
    var spec: (dur: Double, f: Double, z: Double, blinkIn: Bool) {
        switch self {
        case .idle:     return (3.2, 2.2, 0.5, true)
        case .thinking: return (3.2, 2.0, 0.45, false)
        case .notify:   return (2.6, 2.6, 0.4, true)
        case .success:  return (2.6, 2.2, 0.5, false)
        case .error:    return (2.6, 2.4, 0.45, true)
        case .offline:  return (3.0, 1.6, 0.7, true)
        case .sleep:    return (3.4, 1.4, 0.7, false)
        case .welcome:  return (3.0, 2.0, 0.45, false)
        }
    }
}

enum AtoExpression {
    case neutro, atento, curioso, surpreso, animado, sonolento
}

// MARK: - Engine

enum AtoBot {
    static let TAU = Double.pi * 2
    /// The orb is drawn at radius 196; this brings it to 100.
    static let K = 100.0 / 196.0
    /// Eye centres, in orb units before K.
    static let EYX = 68.0, EY = -14.0

    /// The three layers, back to front: orange chevron, cyan wave, blue.
    /// Radius, wobble, lobes, phase, resting turn and direction of travel.
    struct Layer { let key: String; let R, A, n, ph, base, dir: Double }
    static let ORB: [Layer] = [
        Layer(key: "ch", R: 196, A: 14, n: 5, ph: 0, base: 0, dir: 1),
        Layer(key: "wv", R: 192, A: 12, n: 6, ph: 1.2, base: 20, dir: -1),
        Layer(key: "bl", R: 196, A: 13, n: 7, ph: 2.4, base: 40, dir: 0.7),
    ]

    /// The "oficial" palette.
    static let palette: [String: String] = [
        "ch": "#FB5423", "bl": "#1B2FEB", "wv": "#1FEFFF", "sc": "#FFFFFF", "pu": "#0A1130", "br": "#FFFFFF",
    ]
    static let orange = "#FB5423", blue = "#1B2FEB", cyan = "#1FEFFF", ink = "#0A1130"

    // MARK: Easing — the original's helpers, unchanged

    static func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(b, max(a, x)) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    static func easeOut(_ t: Double) -> Double { 1 - pow(1 - clamp(t), 3) }
    static func easeInOut(_ t: Double) -> Double {
        let t = clamp(t)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    static func bump(_ t: Double, _ a: Double, _ b: Double) -> Double {
        (t <= a || t >= b) ? 0 : sin(Double.pi * (t - a) / (b - a))
    }
    static func hash(_ n: Double) -> Double {
        let x = sin(n * 127.1 + 0.3) * 43758.5453
        return x - floor(x)
    }
    static func spring(_ t: Double, _ f: Double = 2.2, _ z: Double = 0.5) -> Double {
        if t <= 0 { return 0 }
        let w = TAU * f, wd = w * (1 - z * z).squareRoot()
        return 1 - exp(-z * w * t) * (cos(wd * t) + (z * w / wd) * sin(wd * t))
    }
    static func kick(_ t: Double, _ f: Double = 2.2, _ d: Double = 4) -> Double {
        t <= 0 ? 0 : exp(-d * t) * sin(TAU * f * t)
    }
    /// smoothstep, clamped — the driver's `sm`.
    static func sm(_ x: Double) -> Double { x <= 0 ? 0 : (x >= 1 ? 1 : x * x * (3 - 2 * x)) }

    // MARK: Faces

    /// Both eyes alike — the original's `pair` without its second argument,
    /// which only the states Notchy does not play use.
    static func pair(_ o: AtoEye = AtoEye()) -> [AtoEye] { [o, o] }

    static func face(_ e: AtoExpression) -> [AtoEye] {
        switch e {
        case .neutro:    return pair()
        case .atento:    return pair(AtoEye(pdx: -3, pdy: 4))
        case .curioso:   return pair(AtoEye(pdx: 11, pdy: -6))
        case .surpreso:  return pair(AtoEye(pdx: 0, pdy: -8))
        case .animado:   return pair(AtoEye(arc: 1))
        case .sonolento: return pair(AtoEye(pdy: 8))
        }
    }

    static func L3(_ f: (Int) -> AtoLayerPatch) -> [AtoLayerPatch] { [f(0), f(1), f(2)] }

    // MARK: Poses — each state's pose with its overlay (the original's OV) applied

    static func pose(_ s: AtoState, _ t: Double) -> AtoPatch {
        switch s {
        case .idle:
            return AtoPatch(gazeFree: 1)

        case .thinking:
            // Base: shrinks, looks up, layers spin. Overlay: the blue layer
            // stays as the head and the other two orbit it.
            let a = t * 2.4
            func sat(_ k: Double) -> AtoLayerPatch {
                let q = a + k * Double.pi, z = sin(q)
                return AtoLayerPatch(x: cos(q) * 285, y: -30 + z * 70, s: 0.34 + 0.1 * z)
            }
            let fx = cos(a), fz = sin(a), front = fz > 0 ? fx : -fx
            return AtoPatch(r: 0.95, roll: 8, look: AtoVec(x: front * 1.1, y: -0.9), eyes: face(.curioso),
                            twist: t * 90, wob: 1.25, spread: 0.04 + 0.03 * sin(t * 5),
                            lay: [sat(0), sat(1), AtoLayerPatch(s: 0.7 + 0.02 * sin(t * 3))],
                            eyeS: 0.74, drift: 0)

        case .notify:
            // Jumps on a spring, the badge pops in with overshoot, the eyes
            // go to it and come back; the layers hop in cascade.
            let m = easeInOut((t - 1.3) / 0.45)
            return AtoPatch(r: 1 + 0.12 * kick(t, 2.2, 4),
                            look: AtoVec(x: lerp(1, 0, m), y: lerp(-1, 0, m)),
                            eyes: face(.surpreso),
                            twist: 60 * easeOut(t / 0.6) - 60 * m,
                            lay: L3 { i in AtoLayerPatch(y: -70 * max(0, kick(t - Double(i) * 0.09, 2.2, 4))) },
                            decor: [AtoDecor(kind: .badge, x: 0.74, y: -0.74,
                                             r: max(0, 0.21 * spring(t - 0.12, 2.4, 0.35)), a: 1)],
                            drift: m)

        case .success:
            // Crouches, jumps with squash and stretch while the layers turn a
            // full circle, lands on a spring; on landing they open like a flower.
            let ant = bump(t, 0, 0.22)
            let air = (t > 0.2 && t < 0.78) ? sin(Double.pi * (t - 0.2) / 0.58) : 0
            var sy = 1 - 0.07 * ant
            if air > 0 { sy = 1 + 0.04 * (1 - air) * (t < 0.49 ? 1 : 0) + 0.015 * air }
            if t >= 0.78 { sy = 1 - 0.07 * exp(-6 * (t - 0.78)) * cos(TAU * 2.4 * (t - 0.78)) }
            let e = sin(Double.pi * clamp((t - 0.75) / 1.1))
            let T3 = TAU / 3
            return AtoPatch(sx: 1 + (1 - sy) * 0.6, sy: sy, y: -0.2 * air, anchor: 1,
                            eyes: face(.animado),
                            twist: 360 * easeInOut((t - 0.15) / 0.9), wob: 1 + 0.3 * air, spread: 0.1 * air,
                            lay: L3 { i in
                                let ang = Double(i) * T3 - Double.pi / 2
                                return AtoLayerPatch(x: cos(ang) * 150 * e, y: sin(ang) * 150 * e, s: 1 - 0.3 * e)
                            },
                            drift: 0)

        case .error:
            // Shakes its head with damping, each layer out of phase, and a
            // "?" springs up.
            let d = t - 0.1
            let sh = t > 0.1 ? sin(TAU * 3.6 * d) * exp(-2.6 * d) : 0
            return AtoPatch(x: 0.12 * sh, roll: 9 * sh,
                            eyes: pair(AtoEye(pdx: 4, pdy: -5)),
                            twist: 25 * sh,
                            lay: L3 { i in
                                AtoLayerPatch(x: 60 * (t > 0.1 ? sin(TAU * 3.6 * d - Double(i) * 0.7) * exp(-2.6 * d) : 0))
                            },
                            decor: [AtoDecor(kind: .text("?"), x: 0.9, y: -0.78,
                                             s: 0.62 * max(0, spring(t - 0.3, 2.2, 0.35)),
                                             a: clamp((t - 0.3) / 0.15))],
                            drift: 0.4)

        case .offline:
            // Loses its colour, sinks, lids low; the layers slip apart and
            // fade, only the front one keeps its colour.
            return AtoPatch(r: 0.92, y: 0.05, gray: 1, look: AtoVec(x: 0, y: 0.6),
                            eyes: face(.sonolento), wob: 0.5,
                            lay: L3 { i in
                                AtoLayerPatch(y: 40 * Double(i - 1), s: 0.92 - 0.06 * Double(i), a: i == 2 ? 1 : 0.5)
                            },
                            drift: 0.3, breathe: 1.6)

        case .sleep:
            // Eyes shut, slow deep breath, "z"s drifting up.
            let b = sin(t * TAU / 2.6)
            return AtoPatch(sx: 1 - 0.038 * b, sy: 1 + 0.05 * b, anchor: 1,
                            eyes: pair(AtoEye(shut: 1)), wob: 1 + 0.08 * b,
                            decor: (0..<3).map { i in
                                let p = ((t / 2.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1) + 1)
                                    .truncatingRemainder(dividingBy: 1)
                                return AtoDecor(kind: .text("z"), x: 0.6 + 0.3 * p, y: -0.62 - 0.56 * p,
                                                s: 0.22 + 0.2 * p, a: sin(Double.pi * p) * 0.85)
                            },
                            drift: 0.55, blinkOK: 0)

        case .welcome:
            // Born from a point, layers spiralling in one after another; the
            // eyes open last and it winks.
            let g = spring(t - 0.1, 1.5, 0.36), eo = clamp((t - 0.55) / 0.2)
            let wk = clamp((t - 1.5) / 0.1) * (1 - clamp((t - 2.05) / 0.15))
            func k(_ i: Int) -> Double { clamp((t - 0.05 - Double(i) * 0.12) / 0.75) }
            func e(_ i: Int) -> Double {
                let x = k(i), c1 = 1.4
                return 1 + (c1 + 1) * pow(x - 1, 3) + c1 * pow(x - 1, 2)
            }
            return AtoPatch(r: max(0.06, 0.08 + 0.92 * g),
                            eyes: [AtoEye(sy: max(0.06, eo)), AtoEye(sy: max(0.06, eo), arc: wk)],
                            twist: -540 * (1 - easeOut(t / 1.5)), wob: 1.4,
                            lay: L3 { i in AtoLayerPatch(s: max(0.001, e(i)), rot: (1 - k(i)) * Double(i - 1) * 80) },
                            drift: 0, blinkOK: 0)
        }
    }

    // MARK: Assembly

    static func base(_ X: AtoContext) -> AtoPose {
        var P = AtoPose()
        P.eyes = X.expr
        return P
    }

    static func full(_ s: AtoState, _ t: Double, _ X: AtoContext) -> AtoPose {
        var P = base(X)
        let o = pose(s, t)
        if let v = o.r { P.r = v }
        if let v = o.sx { P.sx = v }
        if let v = o.sy { P.sy = v }
        if let v = o.x { P.x = v }
        if let v = o.y { P.y = v }
        if let v = o.roll { P.roll = v }
        if let v = o.anchor { P.anchor = v }
        if let v = o.gray { P.gray = v }
        if let v = o.look { P.look = v }
        if let v = o.eyes { P.eyes = v }
        if let v = o.eyeA { P.eyeA = v }
        if let v = o.twist { P.twist = v }
        if let v = o.wob { P.wob = v }
        if let v = o.spread { P.spread = v }
        if let v = o.eyeS { P.eyeS = v }
        if let v = o.decor { P.decor = v }
        if let v = o.drift { P.drift = v }
        if let v = o.breathe { P.breathe = v }
        if let v = o.blinkOK { P.blinkOK = v }
        if let v = o.gazeFree { P.gazeFree = v }
        if let lay = o.lay {
            for i in 0..<3 where i < lay.count {
                let p = lay[i]
                if let v = p.x { P.lay[i].x = v }
                if let v = p.y { P.lay[i].y = v }
                if let v = p.s { P.lay[i].s = v }
                if let v = p.a { P.lay[i].a = v }
                if let v = p.rot { P.lay[i].rot = v }
            }
        }
        return P
    }

    static func mixEye(_ a: AtoEye, _ b: AtoEye, _ k: Double) -> AtoEye {
        AtoEye(sy: lerp(a.sy, b.sy, k), pdx: lerp(a.pdx, b.pdx, k), pdy: lerp(a.pdy, b.pdy, k),
               arc: lerp(a.arc, b.arc, k), shut: lerp(a.shut, b.shut, k))
    }

    /// The original's `mixObj` over a layer: it walks *b*'s keys, so a `rot`
    /// that only *a* has is dropped, and one only *b* has arrives at once.
    static func mixLayer(_ a: AtoLayer, _ b: AtoLayer, _ k: Double) -> AtoLayer {
        AtoLayer(x: lerp(a.x, b.x, k), y: lerp(a.y, b.y, k), s: lerp(a.s, b.s, k), a: lerp(a.a, b.a, k),
                 rot: b.rot.map { lerp(a.rot ?? $0, $0, k) })
    }

    /// Blend between two poses: `k` (a spring, may overshoot) for motion,
    /// `kc` (an ease) for everything that should not.
    static func mixPose(_ a: AtoPose, _ b: AtoPose, _ k: Double, _ kc: Double) -> AtoPose {
        var P = AtoPose()
        P.r = lerp(a.r, b.r, k); P.sx = lerp(a.sx, b.sx, k); P.sy = lerp(a.sy, b.sy, k)
        P.x = lerp(a.x, b.x, k); P.y = lerp(a.y, b.y, k); P.roll = lerp(a.roll, b.roll, k)
        P.anchor = lerp(a.anchor, b.anchor, kc); P.gray = lerp(a.gray, b.gray, kc)
        P.look = AtoVec(x: lerp(a.look.x, b.look.x, k), y: lerp(a.look.y, b.look.y, k))
        P.eyes = [mixEye(a.eyes[0], b.eyes[0], k), mixEye(a.eyes[1], b.eyes[1], k)]
        P.eyeA = lerp(a.eyeA, b.eyeA, kc)
        P.twist = lerp(a.twist, b.twist, kc)
        P.wob = lerp(a.wob, b.wob, k); P.spread = lerp(a.spread, b.spread, k)
        P.lay = (0..<3).map { mixLayer(a.lay[$0], b.lay[$0], k) }
        P.fo = AtoVec(x: lerp(a.fo.x, b.fo.x, k), y: lerp(a.fo.y, b.fo.y, k))
        P.eyeS = lerp(a.eyeS, b.eyeS, k)
        P.decor = a.decor.map { var d = $0; d.a *= (1 - kc); return d }
            + b.decor.map { var d = $0; d.a *= kc; return d }
        P.drift = lerp(a.drift, b.drift, kc); P.breathe = lerp(a.breathe, b.breathe, kc)
        P.blinkOK = b.blinkOK; P.gazeFree = b.gazeFree
        return P
    }

    /// Eyelid openness at time T: a blink about every 4.1 s, jittered, and
    /// one in three of them a double.
    static func blink(_ T: Double) -> Double {
        let P = 4.1, k = floor(T / P)
        for kk in [k - 1, k] {
            let t0 = kk * P + hash(kk) * 2.2, d = T - t0
            if d >= 0 && d < 0.2 { return 1 - sin(Double.pi * d / 0.2) * 0.94 }
            if hash(kk + 99) > 0.68 {
                let d2 = d - 0.32
                if d2 >= 0 && d2 < 0.18 { return 1 - sin(Double.pi * d2 / 0.18) * 0.94 }
            }
        }
        return 1
    }

    /// What every pose goes through last: blinks, the wandering gaze, the
    /// pointer, breathing.
    static func post(_ Pin: AtoPose, _ T: Double, _ tl: Double, _ S: AtoState?, _ X: AtoContext,
                     noBlink: Bool = false) -> AtoPose {
        var P = Pin
        let enter = (S.map { $0.spec.blinkIn } ?? false) && tl < 0.22 ? 1 - sin(Double.pi * tl / 0.22) * 0.94 : 1
        let bl = noBlink ? 1 : (P.blinkOK != 0 ? blink(T) : 1) * enter
        P.eyes = P.eyes.map { var e = $0; e.sy *= bl; return e }
        let d = P.drift
        P.look = AtoVec(x: P.look.x + d * (0.35 * sin(T * 0.71) + 0.2 * sin(T * 1.93 + 1)),
                        y: P.look.y + d * (0.25 * sin(T * 0.93 + 2) + 0.1 * sin(T * 2.3)))
        if X.follow, let ptr = X.pointer, P.gazeFree != 0 {
            let w = 0.85 * X.followW
            P.look = AtoVec(x: lerp(P.look.x, ptr.x, w), y: lerp(P.look.y, ptr.y, w))
        }
        let en = X.energy, br = sin(T * TAU / (3.4 * (P.breathe == 0 ? 1 : P.breathe)))
        P.sx = 1 + (P.sx * (1 - 0.01 * br) - 1) * en
        P.sy = 1 + (P.sy * (1 + 0.016 * br) - 1) * en
        P.y *= en; P.twist *= en; P.wob = 1 + (P.wob - 1) * en
        P.T = T; P.energy = en
        return P
    }

    /// The pose at clock `T`, `tl` seconds into `state`, having come from
    /// `previous` — which is held as it stood at `previousAt` while the two
    /// blend for the first 1.1 s. The original's `sample`, with the timeline
    /// lookup taken out so a live state can drive it.
    static func sample(_ T: Double, state: AtoState, tl: Double, previous: AtoState, previousAt: Double,
                       _ X: AtoContext) -> AtoPose {
        let S = state.spec
        var P = full(state, tl, X)
        if tl < 1.1 {
            P = mixPose(full(previous, previousAt, X), P, spring(tl, S.f, S.z), easeInOut(tl / 0.5))
        }
        // Every change of state twists the layers.
        P.twist += 38 * kick(tl, 1.3, 3.2)
        return post(P, T, tl, state, X)
    }

    /// The original's `sample` over a looping timeline of blocks.
    static func sample(_ T: Double, blocks: [(state: AtoState, dur: Double)], _ X: AtoContext) -> AtoPose {
        let tot = blocks.reduce(0) { $0 + $1.dur }
        let w = (T.truncatingRemainder(dividingBy: tot) + tot).truncatingRemainder(dividingBy: tot)
        var acc = 0.0, i = 0
        while i < blocks.count {
            if w < acc + blocks[i].dur { break }
            acc += blocks[i].dur
            i += 1
        }
        i = min(i, blocks.count - 1)
        let pb = blocks[(i - 1 + blocks.count) % blocks.count]
        return sample(T, state: blocks[i].state, tl: w - acc, previous: pb.state, previousAt: pb.dur, X)
    }

    /// A still: the state at `t`, without blinks.
    static func poseAt(_ s: AtoState, _ t: Double, _ X: AtoContext = AtoContext(), noBlink: Bool = true) -> AtoPose {
        post(full(s, t, X), noBlink ? 1.3 : t, 1, s, X, noBlink: noBlink)
    }

    // MARK: The blog's driver — Ato at rest

    /// Every 6 s it makes a gesture, alternating: (0) tilts its head and
    /// winks, (1) smiles with both eyes and hops.
    static let gestureCycle = 6.0

    static func env(_ c: Double, _ a: Double, _ b: Double, _ i: Double = 0.3, _ o: Double = 0.35) -> Double {
        sm((c - a) / i) * (1 - sm((c - (b - o)) / o))
    }

    static func gesture(_ s: Double) -> (k: Int, c: Double, g: Double) {
        let c = s.truncatingRemainder(dividingBy: gestureCycle)
        let k = Int(floor(s / gestureCycle)) % 2
        return (k, c, env(c, 3.4, 5.1))
    }

    /// The resting face mid-gesture.
    static func restingFace(_ s: Double) -> [AtoEye] {
        let (k, _, g) = gesture(s)
        var E = face(.neutro)
        let w = sm(g * 1.3)
        if k == 0 { E[1].arc = w; E[0].sy = 1 - 0.1 * w } else { E[0].arc = w; E[1].arc = w }
        return E
    }

    /// Where it looks with nobody pointing: at the title, then at you, then
    /// back — the blog's layout, kept because it is what "at rest" looks like.
    static func idleLook(_ s: Double) -> AtoVec {
        let c = s.truncatingRemainder(dividingBy: gestureCycle)
        let y = sm((c - 1.3) / 0.45) * (1 - sm((c - 2.7) / 0.45))
        return AtoVec(x: -0.6 * (1 - y), y: 0.06)
    }

    /// The gesture's whole-body move: translateY in percent of the box, a
    /// turn in degrees, a scale — the CSS transform the blog puts on the orb,
    /// about a point 62 % of the way down.
    static func bodyMotion(_ s: Double) -> (ty: Double, rot: Double, sx: Double, sy: Double) {
        let (k, c, g) = gesture(s)
        let sway = sin(s * 1.05) * 1.4, bob = sin(s * 2.1) * 0.5
        if k == 0 { return (bob - 1.5 * g, sway - 10 * g, 1, 1) }
        let hop = sin(sm((c - 3.5) / 0.55) * Double.pi) * 3.4
        let squash = sin(sm((c - 3.35) / 0.2) * Double.pi) * 0.04
        return (bob - hop, sway + 2.5 * g, 1 + squash, 1 - squash)
    }

    // MARK: Colour

    /// The original's `hexMix`: per channel, rounded.
    static func hexMix(_ a: String, _ b: String, _ t: Double) -> String {
        func parse(_ h: String) -> Int { Int(h.dropFirst(), radix: 16) ?? 0 }
        let pa = parse(a), pb = parse(b)
        func ch(_ sh: Int) -> Int {
            Int(floor(lerp(Double((pa >> sh) & 255), Double((pb >> sh) & 255), clamp(t)) + 0.5))
        }
        return String(format: "#%02x%02x%02x", ch(16), ch(8), ch(0))
    }
}

// MARK: - Scene

/// Everything there is to draw for one pose, in the original's coordinates:
/// a 320-unit box centred on the orb, whose radius is 100. AtoBotView draws
/// it; the parity test serialises it the way the original writes its SVG.
struct AtoScene: Equatable {
    /// An affine transform, as SVG's matrix(a b c d e f).
    struct Affine: Equatable {
        var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0
        static let identity = Affine()
        func concat(_ m: Affine) -> Affine {
            Affine(a: a * m.a + c * m.b, b: b * m.a + d * m.b,
                   c: a * m.c + c * m.d, d: b * m.c + d * m.d,
                   e: a * m.e + c * m.f + e, f: b * m.e + d * m.f + f)
        }
        func translated(_ x: Double, _ y: Double) -> Affine { concat(Affine(e: x, f: y)) }
        func scaled(_ x: Double, _ y: Double) -> Affine { concat(Affine(a: x, d: y)) }
        func rotated(_ deg: Double) -> Affine {
            let r = deg * Double.pi / 180
            return concat(Affine(a: cos(r), b: sin(r), c: -sin(r), d: cos(r)))
        }
        func apply(_ x: Double, _ y: Double) -> (Double, Double) { (a * x + c * y + e, b * x + d * y + f) }
    }

    struct Layer: Equatable {
        /// The original's wav() arguments, kept for the test.
        var R, A, n, ph: Double
        var points: [(Double, Double)]
        var fill: String
        var opacity: Double
        /// translate, scale, rotate — inside `body`.
        var tx, ty, s, rot: Double
        var transform: Affine

        static func == (l: Layer, r: Layer) -> Bool {
            l.R == r.R && l.A == r.A && l.n == r.n && l.ph == r.ph && l.fill == r.fill
                && l.opacity == r.opacity && l.transform == r.transform
        }
    }

    enum EyeMark: Equatable {
        /// A white dot: centre, vertical radius (horizontal is always 26).
        case dot(cx: Double, cy: Double, ry: Double, opacity: Double)
        /// The happy ∩ (stroke 17) or the shut ∪ (stroke 14): a quadratic
        /// from (x0, y0) through control (qx, qy) to (x1, y1).
        case arc(x0: Double, y0: Double, qx: Double, qy: Double, x1: Double, y1: Double, width: Double, opacity: Double)
    }

    /// The outer group's parts, in the order the original writes them.
    var px, py, roll, anchorY, sx, sy, s: Double
    var body: Affine
    var layers: [Layer]
    var eyesOpacity: Double
    var fx, fy, eyeS: Double
    var eyesTransform: Affine
    var eyes: [EyeMark]
    var decor: [AtoDecor]
    var badgeRing: String
    var textInk: String
}

extension AtoBot {
    /// The original's wav(): a wobbly circle, 121 points.
    static func wav(_ R: Double, _ A: Double, _ n: Double, _ ph: Double) -> [(Double, Double)] {
        (0...120).map { i in
            let t = Double(i) / 120 * TAU, r = R + A * sin(n * t + ph)
            return (r * cos(t), r * sin(t))
        }
    }

    /// What `render` draws for `P`, on a dark background (the island's), with
    /// the official palette. `paper` is what the badge is cut out of.
    static func scene(_ P: AtoPose, paper: String = "#1D1E1F") -> AtoScene {
        let g = "#6B7079"
        func gm(_ c: String) -> String { hexMix(c, g, P.gray) }
        let pal: [String: String] = ["ch": gm(orange), "bl": gm(blue), "wv": gm(cyan)]
        let T = P.T
        let s = K * P.r, A = P.anchor * 100 * P.r
        let body = AtoScene.Affine.identity
            .translated(P.x * 100, P.y * 100).rotated(P.roll)
            .translated(0, A).scaled(P.sx, P.sy).translated(0, -A).scaled(s, s)

        let layers: [AtoScene.Layer] = ORB.enumerated().map { i, L in
            let fi = Double(i)
            let rot = L.base + L.dir * (P.twist + T * 7 * P.energy) + (P.lay[i].rot ?? 0)
            let sc = 1 + P.spread * (fi - 1) * 0.6
            let R = L.R * sc, amp = L.A * P.wob * (1 + 0.12 * sin(T * 1.4 + fi * 2)), ph = L.ph + T * 0.35 * L.dir
            let ly = P.lay[i]
            let px = ly.x + P.look.x * (fi - 1) * 9, py = ly.y + P.look.y * (fi - 1) * 6
            let ls = max(0, ly.s)
            return AtoScene.Layer(R: R, A: amp, n: L.n, ph: ph, points: wav(R, amp, L.n, ph),
                                  fill: pal[L.key]!, opacity: 0.88 * clamp(ly.a),
                                  tx: px, ty: py, s: ls, rot: rot,
                                  transform: body.translated(px, py).scaled(ls, ls).rotated(rot))
        }

        let fx = P.look.x * 7, fy = P.look.y * 5
        let eyesT = body.translated(fx + P.fo.x, fy + P.fo.y).translated(0, EY)
            .scaled(P.eyeS, P.eyeS).translated(0, -EY)
        var eyes: [AtoScene.EyeMark] = []
        for (i, e) in P.eyes.enumerated() {
            let sd: Double = i == 0 ? -1 : 1, x = sd * EYX, y = EY
            let open = clamp(1 - e.arc) * clamp(1 - e.shut)
            let lx = x + e.pdx + clamp(P.look.x, -1.3, 1.3) * 10
            let lyy = y + e.pdy + clamp(P.look.y, -1.3, 1.3) * 8
            if open > 0.02 {
                eyes.append(.dot(cx: lx, cy: y + (lyy - y) * 0.6,
                                 ry: max(0.5, 26 * e.sy * (1 - 0.75 * clamp(e.arc + e.shut))), opacity: open))
            }
            if e.arc > 0.02 {
                eyes.append(.arc(x0: x - 32, y0: y + 12, qx: x, qy: y - 36, x1: x + 32, y1: y + 12,
                                 width: 17, opacity: clamp(e.arc)))
            }
            if e.shut > 0.02 {
                eyes.append(.arc(x0: x - 28, y0: y, qx: x, qy: y + 24, x1: x + 28, y1: y,
                                 width: 14, opacity: clamp(e.shut)))
            }
        }
        return AtoScene(px: P.x * 100, py: P.y * 100, roll: P.roll, anchorY: A, sx: P.sx, sy: P.sy, s: s,
                        body: body, layers: layers,
                        eyesOpacity: clamp(P.eyeA), fx: fx + P.fo.x, fy: fy + P.fo.y, eyeS: P.eyeS,
                        eyesTransform: eyesT, eyes: eyes,
                        decor: P.decor.filter { $0.a >= 0.01 }, badgeRing: paper, textInk: "#FFFFFF")
    }

    // MARK: SVG, the original's way — for the parity test

    /// The original's f1: one decimal, JavaScript's rounding and printing.
    static func f1(_ n: Double) -> String { js(floor(n * 10 + 0.5) / 10) }
    static func fixed(_ n: Double, _ d: Int) -> String { String(format: "%.\(d)f", n) }
    static func js(_ v: Double) -> String {
        if v == 0 { return "0" }
        if v == v.rounded() && abs(v) < 1e15 { return String(Int(v)) }
        var s = String(format: "%.10f", v)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    /// `render(P, {size, body:'orbe', pal: oficial, bg:'escuro', noPaper: true})`.
    static func svg(_ P: AtoPose, size: Double = 160, uid: String = "ab") -> String {
        let sc = scene(P)
        let px = size * 1.6
        var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"-160 -160 320 320\" width=\"\(f1(px))\" height=\"\(f1(px))\" style=\"display:block;overflow:visible\">"
        out += "<g transform=\"translate(\(f1(sc.px)) \(f1(sc.py))) rotate(\(f1(sc.roll))) translate(0 \(f1(sc.anchorY))) scale(\(fixed(sc.sx, 3)) \(fixed(sc.sy, 3))) translate(0 \(f1(-sc.anchorY))) scale(\(fixed(sc.s, 4)))\">"
        out += "<g style=\"isolation:isolate\">"
        for L in sc.layers {
            let d = L.points.enumerated().map { i, p in (i == 0 ? "M" : "L") + f1(p.0) + " " + f1(p.1) }.joined() + "Z"
            out += "<path d=\"\(d)\" fill=\"\(L.fill)\" opacity=\"\(fixed(L.opacity, 2))\" transform=\"translate(\(f1(L.tx)) \(f1(L.ty))) scale(\(fixed(L.s, 3))) rotate(\(f1(L.rot)))\"/>"
        }
        out += "</g>"
        out += "<g opacity=\"\(fixed(sc.eyesOpacity, 2))\" transform=\"translate(\(f1(sc.fx)) \(f1(sc.fy))) translate(0 \(js(EY))) scale(\(fixed(sc.eyeS, 3))) translate(0 \(js(-EY)))\">"
        for m in sc.eyes {
            switch m {
            case let .dot(cx, cy, ry, op):
                out += "<ellipse cx=\"\(f1(cx))\" cy=\"\(f1(cy))\" rx=\"26\" ry=\"\(f1(ry))\" fill=\"#FFFFFF\" opacity=\"\(fixed(op, 2))\"/>"
            case let .arc(x0, y0, qx, qy, x1, y1, w, op):
                out += "<path d=\"M\(js(x0)) \(js(y0))Q\(js(qx)) \(js(qy)) \(js(x1)) \(js(y1))\" stroke=\"#FFFFFF\" stroke-width=\"\(js(w))\" stroke-linecap=\"round\" fill=\"none\" opacity=\"\(fixed(op, 2))\"/>"
            }
        }
        out += "</g></g>"
        for d in sc.decor {
            let op = fixed(clamp(d.a), 2)
            switch d.kind {
            case .badge:
                out += "<circle cx=\"\(f1(d.x * 100))\" cy=\"\(f1(d.y * 100))\" r=\"\(f1(d.r * 100 + 7))\" fill=\"\(sc.badgeRing)\" opacity=\"\(op)\"/><circle cx=\"\(f1(d.x * 100))\" cy=\"\(f1(d.y * 100))\" r=\"\(f1(d.r * 100))\" fill=\"#FB5423\" opacity=\"\(op)\"/>"
            case let .text(txt):
                out += "<text x=\"\(f1(d.x * 100))\" y=\"\(f1(d.y * 100))\" font-family=\"Open Sans, Arial, sans-serif\" font-weight=\"800\" font-size=\"\(f1(d.s * 100))\" text-anchor=\"middle\" dominant-baseline=\"central\" fill=\"\(sc.textInk)\" opacity=\"\(op)\">\(txt)</text>"
            }
        }
        return out + "</svg>"
    }
}
