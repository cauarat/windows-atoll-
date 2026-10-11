// Whether both buttons were pressed together.
//
// This runs inside an event tap that can swallow mouse clicks system-wide, so
// the failure mode is not "the menu does not open" — it is "the Mac stops
// responding to the mouse". Everything that could be wrong about the decision
// is asserted here, where no permission, no tap and no mouse are needed.
//
// Run with scripts/test-radial-chord.sh.

import CoreGraphics
import Foundation

@main
enum RadialChordTests {

    static var failures = 0

    static func check(_ condition: Bool, _ what: String) {
        print("  \(condition ? "\u{2713}" : "\u{2717}") \(what)")
        if !condition { failures += 1 }
    }

    static let p = CGPoint(x: 400, y: 300)
    static func near(_ d: CGFloat) -> CGPoint { CGPoint(x: p.x + d, y: p.y) }

    static func main() {
        var m = RadialChordMachine()

        // MARK: – Right then left, together

        m = RadialChordMachine()
        check(m.step(.down(.right, at: p, t: 0)) == [.hold],
              "a right press is held back rather than passed on")
        check(m.isHolding, "and the timer is wanted while it is held")
        check(m.step(.down(.left, at: p, t: 0.02)) == [.swallow, .fire(at: p)],
              "a left press just after it is a chord, and nothing reaches the app")

        // Both buttons belong to the wheel until they are let go.
        check(m.step(.dragged(.left, at: near(40), t: 0.1)) == [.swallow],
              "dragging while the wheel is open does not reach the app")
        check(m.step(.up(.left, at: p, t: 0.3)) == [.swallow], "nor the first release")
        check(m.step(.up(.right, at: p, t: 0.31)) == [.swallow], "nor the second")
        check(m.step(.down(.left, at: p, t: 1)) == [.passThrough],
              "and afterwards the mouse is ordinary again")

        // MARK: – Left then right, together

        m = RadialChordMachine()
        check(m.step(.down(.left, at: p, t: 0)) == [.passThrough],
              "a left press is never delayed")
        let out = m.step(.down(.right, at: p, t: 0.03))
        check(out == [.swallow, .release(.left, at: p), .fire(at: p)],
              "a right press just after it fires, and completes the click already started")

        // MARK: – An ordinary right-click is not a chord

        m = RadialChordMachine()
        _ = m.step(.down(.right, at: p, t: 0))
        check(m.step(.tick(t: 0.01)) == [], "the window has not closed yet")
        check(m.step(.tick(t: 0.2)) == [.flushHeld],
              "once it closes the held press is let go, late but intact")
        check(!m.isHolding, "and the timer is no longer wanted")
        check(m.step(.up(.right, at: p, t: 0.4)) == [.passThrough],
              "its release passes through too")

        // MARK: – Right-click, then clicking the menu it opened

        // The case time alone cannot tell from a chord. The pointer has to
        // travel to the menu, so distance is what separates them.
        m = RadialChordMachine()
        _ = m.step(.down(.right, at: p, t: 0))
        _ = m.step(.tick(t: 0.2))
        _ = m.step(.up(.right, at: p, t: 0.25))
        check(m.step(.down(.left, at: near(120), t: 0.4)) == [.passThrough],
              "clicking a context menu afterwards is an ordinary click")

        // Even inside the window, far apart is not a chord.
        m = RadialChordMachine()
        _ = m.step(.down(.right, at: p, t: 0))
        check(m.step(.down(.left, at: near(60), t: 0.01)) == [.flushHeld, .passThrough],
              "two presses close in time but far apart are not a chord")

        // And close together but too slow is not either.
        m = RadialChordMachine()
        _ = m.step(.down(.right, at: p, t: 0))
        check(m.step(.down(.left, at: p, t: 0.5)) == [.flushHeld, .passThrough],
              "two presses in the same place but far apart in time are not a chord")

        // MARK: – A right-drag must not arrive before its own press

        m = RadialChordMachine()
        _ = m.step(.down(.right, at: p, t: 0))
        check(m.step(.dragged(.right, at: near(30), t: 0.01)) == [.flushHeld, .passThrough],
              "a right drag releases the held press first, so the app sees them in order")

        // MARK: – An ordinary left click is untouched throughout

        m = RadialChordMachine()
        check(m.step(.down(.left, at: p, t: 0)) == [.passThrough], "left down passes")
        check(m.step(.up(.left, at: p, t: 0.1)) == [.passThrough], "left up passes")
        check(m.step(.down(.left, at: p, t: 0.2)) == [.passThrough], "and again")

        // MARK: – Nothing is ever swallowed without the wheel opening

        // The property that matters: if `.swallow` appears, `.fire` is in the
        // same batch or the wheel is already open. Anything else is a click the
        // user made and nobody received.
        m = RadialChordMachine()
        var open = false
        var pressed = Set<String>()
        var lost = 0
        let script: [ChordInput] = [
            .down(.right, at: p, t: 0), .tick(t: 0.2), .up(.right, at: p, t: 0.3),
            .down(.left, at: p, t: 0.4), .up(.left, at: p, t: 0.5),
            .down(.right, at: p, t: 1.0), .down(.left, at: p, t: 1.01),
            .up(.left, at: p, t: 1.2), .up(.right, at: p, t: 1.21),
            .down(.left, at: p, t: 2.0), .down(.right, at: p, t: 2.01),
            .up(.right, at: p, t: 2.2), .up(.left, at: p, t: 2.21),
            .down(.left, at: p, t: 3.0), .up(.left, at: p, t: 3.1),
        ]
        for input in script {
            let o = m.step(input)
            if o.contains(.fire(at: p)) { open = true }
            if o.contains(.swallow) && !open { lost += 1 }
            // The wheel owns both buttons until both are let go, so track what
            // is physically down rather than guessing from the first release.
            switch input {
            case .down(let b, _, _): pressed.insert("\(b)")
            case .up(let b, _, _):   pressed.remove("\(b)")
            default: break
            }
            if pressed.isEmpty { open = false }
        }
        check(lost == 0, "across a long script, nothing is swallowed before the wheel opens")

        // MARK: – Reset

        m = RadialChordMachine()
        _ = m.step(.down(.right, at: p, t: 0))
        m.reset()
        check(m.step(.down(.left, at: p, t: 0.01)) == [.passThrough],
              "after a reset the machine lets everything through")
        check(!m.isHolding, "and holds nothing")

        print("")
        if failures == 0 {
            print("All radial chord tests passed.")
        } else {
            print("\(failures) failed.")
            exit(1)
        }
    }
}
