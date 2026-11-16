// Ato's mascot: the Swift port held to Actuar's own engine.
//
// Compiled against AtoBot.swift alone. Run with scripts/test-ato-bot.sh, which
// also feeds `--dump` to tests/ato-bot-parity.ts: that runs the original
// (design/ato/actuar-bot-v3.js) on the very inputs printed here and compares
// pose numbers and the SVG the original would draw, shape for shape.

import Foundation

@main
enum AtoBotTests {

    static var failures = 0

    static func check(_ condition: Bool, _ what: String) {
        if condition {
            print("  \u{2713} \(what)")
        } else {
            print("  \u{2717} \(what)")
            failures += 1
        }
    }

    static func main() {
        if CommandLine.arguments.contains("--dump") {
            dump()
            return
        }

        print("Ato bot")
        check(AtoBot.hexMix("#FB5423", "#6B7079", 0) == "#fb5423", "hexMix at 0 is the colour itself, lower-cased like the original")
        check(AtoBot.hexMix("#000000", "#ffffff", 0.5) == "#808080", "hexMix rounds half up per channel")
        check(AtoBot.f1(-0.04) == "0" && AtoBot.f1(2.25) == "2.3" && AtoBot.f1(-2.25) == "-2.2" && AtoBot.f1(196) == "196",
              "f1 rounds and prints the way JavaScript does")
        check(AtoBot.wav(196, 14, 5, 0).count == 121, "an orb layer is 121 points")

        let rest = AtoBot.poseAt(.idle, 0)
        let scene = AtoBot.scene(rest)
        check(scene.layers.map(\.fill) == ["#fb5423", "#1fefff", "#1b2feb"],
              "layers go orange, cyan, blue — back to front")
        check(scene.layers.allSatisfy { abs($0.opacity - 0.88) < 1e-12 }, "every layer is 88 % opaque")
        check(scene.eyes.count == 2 && scene.eyes.allSatisfy { if case .dot = $0 { return true }; return false },
              "at rest it has two dot eyes")

        let asleep = AtoBot.scene(AtoBot.poseAt(.sleep, 1))
        check(asleep.eyes.allSatisfy { if case .arc(_, _, _, _, _, _, 14, _) = $0 { return true }; return false },
              "asleep its eyes are closed arcs")
        check(asleep.decor.contains { $0.kind == .text("z") }, "asleep a z floats up")

        let offline = AtoBot.scene(AtoBot.poseAt(.offline, 2))
        check(!offline.layers.contains { $0.fill == "#fb5423" }, "offline the colour drains")

        let pinged = AtoBot.poseAt(.notify, 2)
        check(pinged.decor.contains { $0.kind == .badge && $0.r > 0.2 }, "a new message raises the badge and keeps it up")

        // Blinks: never two closed frames 4 s apart in a row, always open between.
        var closed = 0
        for i in 0..<4000 where AtoBot.blink(Double(i) * 0.01) < 0.5 { closed += 1 }
        check(closed > 20 && closed < 300, "it blinks every few seconds, briefly (\(closed) closed frames in 40 s)")

        // Reacting like a Mochi.
        func looking(_ x: Double) -> AtoPose {
            AtoBot.sample(5, state: .notify, tl: 2, previous: .idle, previousAt: 3.2,
                          AtoContext(follow: true, pointer: AtoVec(x: x, y: 0), gazeAlways: true))
        }
        check(looking(1).look.x - looking(-1).look.x > 1.5,
              "with a message waiting, its eyes still follow the pointer, as a Mochi's do")
        check(AtoBot.poseAt(.notify, 2).look == AtoBot.poseAt(.notify, 2, AtoContext(pointer: AtoVec(x: 1, y: 0))).look,
              "without gazeAlways the original's numbers are untouched")
        var loved = AtoBot.poseAt(.idle, 0)
        AtoBot.react(&loved, eye: .heart, blush: 1, eyeScale: 1.08)
        let lovedScene = AtoBot.scene(loved)
        check(lovedScene.blush == 1 && lovedScene.eyes.allSatisfy { if case .glyph(.heart, _, 0, _) = $0 { return true }; return false },
              "love gives it heart eyes and the original's cheeks")
        var dizzy = AtoBot.poseAt(.idle, 0)
        AtoBot.react(&dizzy, eye: .spiral, blush: 0, eyeScale: 1)
        check(AtoBot.scene(dizzy).eyes.allSatisfy { if case .glyph(.spiral, _, 7, _) = $0 { return true }; return false },
              "dizzy gives it a Mochi's spiral eyes")
        var winked = AtoBot.poseAt(.idle, 0)
        AtoBot.react(&winked, eye: .wink, blush: 0, eyeScale: 1)
        check(winked.eyes[0].arc == 0 && winked.eyes[1].arc == 1, "a wink closes one eye, in the original's own arc")

        print(failures == 0 ? "\nAll Ato bot tests passed." : "\n\(failures) Ato bot test(s) FAILED.")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Dump for the parity test

    static func n(_ v: Double) -> String { v.isNaN ? "nan" : String(describing: v) }

    static func poseNumbers(_ P: AtoPose) -> String {
        var v: [Double] = [P.r, P.sx, P.sy, P.x, P.y, P.roll, P.anchor, P.gray, P.look.x, P.look.y]
        for e in P.eyes { v += [e.sy, e.pdx, e.pdy, e.arc, e.shut] }
        v += [P.eyeA, P.twist, P.wob, P.spread]
        for l in P.lay { v += [l.x, l.y, l.s, l.a, l.rot ?? .nan] }
        v += [P.fo.x, P.fo.y, P.eyeS, P.drift, P.breathe, P.blinkOK, P.gazeFree, P.T, P.energy]
        v.append(Double(P.decor.count))
        for d in P.decor { v += [d.x, d.y, d.r, d.s, d.a] }
        v.append(P.blush)
        return v.map(n).joined(separator: ",")
    }

    static func line(_ head: [String], _ P: AtoPose) {
        print((head + [poseNumbers(P), AtoBot.svg(P)]).joined(separator: "\t"))
    }

    static func dump() {
        let ts: [Double] = [0, 0.1, 0.25, 0.5, 0.8, 1.2, 1.7, 2.4, 3.3]
        for s in AtoState.allCases {
            for t in ts { line(["still", s.rawValue, n(t)], AtoBot.poseAt(s, t)) }
        }

        // State changes, the way the island makes them: from rest into each
        // state and back, and one state straight into another.
        var pairs: [(AtoState, AtoState)] = []
        for s in AtoState.allCases where s != .idle { pairs += [(.idle, s), (s, .idle)] }
        pairs += [(.notify, .success), (.thinking, .error), (.welcome, .notify)]
        let pointer = AtoVec(x: 0.3, y: -0.2)
        for (prev, cur) in pairs {
            // Not 0: the original's timeline lookup, `(T % tot + tot) % tot`,
            // can land a hair before the boundary and pick the block before.
            for tl in [0.001, 0.05, 0.2, 0.45, 0.8, 1.05, 1.5, 2.2] {
                let T = prev.spec.dur + tl
                let X = AtoContext(expr: AtoBot.restingFace(T), energy: 1, follow: true, pointer: pointer, followW: 1)
                line(["live", prev.rawValue, cur.rawValue, n(tl)],
                     AtoBot.sample(T, state: cur, tl: tl, previous: prev, previousAt: prev.spec.dur, X))
            }
        }

        // Thirteen seconds at rest, as the blog plays it: two gestures and
        // a few blinks, with the pointer moving.
        var T = 0.6
        while T < 13.6 {
            let ptr = AtoVec(x: 0.8 * sin(T * 0.7), y: 0.5 * cos(T * 1.1))
            let X = AtoContext(expr: AtoBot.restingFace(T - 0.6), energy: 1, follow: true, pointer: ptr, followW: 1)
            line(["loop", n(T), n(ptr.x), n(ptr.y)], AtoBot.sample(T, blocks: [(.idle, 1e9)], X))
            T += 0.13
        }

        // The original's cheeks ("bochechas"), on still and changing states.
        for s in [AtoState.idle, .notify, .success, .sleep] {
            for t in [0.3, 1.2] { line(["cheeks", s.rawValue, n(t)], AtoBot.poseAt(s, t, AtoContext(blush: 1))) }
        }

        // Notchy's own: Ato reacting as a Mochi — not in the original, so held
        // to the TypeScript twin instead. The gaze in every state, the Mochi's
        // eyelid, and each eye a Mochi can show.
        let eyes: [EyeShape?] = [nil, .happy, .closed, .wink, .tired, .heart, .star, .line, .spiral, .dot]
        for s in [AtoState.idle, .notify] {
            for (k, eye) in eyes.enumerated() {
                let T = 3.0 + Double(k) * 0.37
                let X = AtoContext(expr: AtoBot.face(.neutro), energy: 1, follow: true,
                                   pointer: AtoVec(x: 0.7, y: -0.4), followW: 1, gazeAlways: true, lid: 0.5)
                var P = AtoBot.sample(T, state: s, tl: 2, previous: .idle, previousAt: 3.2, X)
                AtoBot.react(&P, eye: eye, blush: 0.6, eyeScale: 1.08)
                line(["react", s.rawValue, eye?.rawValue ?? "none", n(T)], P)
            }
        }

        // The driver itself.
        var s = 0.0
        while s < 12.5 {
            let e = AtoBot.restingFace(s), l = AtoBot.idleLook(s), m = AtoBot.bodyMotion(s)
            let v = [e[0].sy, e[0].arc, e[1].sy, e[1].arc, l.x, l.y, m.ty, m.rot, m.sx, m.sy]
            print("drive\t\(n(s))\t\(v.map(n).joined(separator: ","))")
            s += 0.1
        }
    }
}
