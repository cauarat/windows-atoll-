import Foundation

/// Covers the island's open/close rules: hover drives the panel directly, and a
/// notification holds it open for a fixed time and then folds itself away.
///
/// The delays are set to a few milliseconds per case so the suite runs in well
/// under a second; what is being checked is the ordering and the bookkeeping,
/// not the wall-clock constants.
///
/// `windows/src/island/fsm.ts` is a direct port of the machine under test. When
/// a rule changes here it changes there too.
@MainActor
@main
enum IslandStateMachineTests {

    static var failures = 0

    static func check(_ label: String, _ got: Any, _ expected: Any) {
        let g = String(describing: got), e = String(describing: expected)
        if g == e {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            print("    got:      \(g)")
            print("    expected: \(e)")
            failures += 1
        }
    }

    static func checkTrue(_ label: String, _ value: Bool) {
        if value { print("  ✓ \(label)") }
        else      { print("  ✗ \(label)"); failures += 1 }
    }

    /// Lets the main queue deliver whatever `asyncAfter` has pending.
    static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// A machine whose timers fire fast enough to test.
    static func makeFSM() -> IslandStateMachine {
        let fsm = IslandStateMachine()
        fsm.leaveGraceDelay = 0.02
        fsm.petitToHiddenDelay = 0.08
        fsm.notificationHoldDelay = 0.05
        fsm.openAnimationDelay = 0
        return fsm
    }

    static func main() {
        print("IslandStateMachine — hover")

        // The pointer arriving opens the panel itself, not just a peek.
        let a = makeFSM()
        a.mouseEntered()
        check("hidden + hover → home", a.state, IslandStateMachine.State.home)

        // And it opens just the same from the compact bar a work event left up.
        let b = makeFSM()
        b.reveal()
        check("reveal → petit", b.state, IslandStateMachine.State.petit)
        b.mouseEntered()
        check("petit + hover → home", b.state, IslandStateMachine.State.home)

        // Opened by hovering from nothing, it goes back to nothing: brushing the
        // corner must not park a compact island on screen for a minute.
        let c = makeFSM()
        c.mouseEntered()
        c.mouseLeft()
        check("leave is not instant (grace)", c.state, IslandStateMachine.State.home)
        pump(0.06)
        check("hover-opened → hidden after grace", c.state, IslandStateMachine.State.hidden)

        // Opened from a compact bar, it returns to that bar.
        let d = makeFSM()
        d.reveal()
        d.mouseEntered()
        d.mouseLeft()
        pump(0.06)
        check("petit-opened → petit after grace", d.state, IslandStateMachine.State.petit)

        // Skimming the boundary must not flicker: coming back inside the grace
        // cancels the collapse outright.
        let e = makeFSM()
        e.mouseEntered()
        var eTransitions = 0
        e.onTransition = { _, _ in eTransitions += 1 }
        e.mouseLeft()
        e.mouseEntered()
        e.mouseLeft()
        e.mouseEntered()
        pump(0.06)
        check("in/out/in/out/in stays home", e.state, IslandStateMachine.State.home)
        check("…and never transitions", eTransitions, 0)

        print("IslandStateMachine — notifications")

        // A notification opens the panel and then folds it away on its own.
        let f = makeFSM()
        f.openedExternally()
        check("notification → home", f.state, IslandStateMachine.State.home)
        pump(0.03)
        check("…still open before the hold is up", f.state, IslandStateMachine.State.home)
        pump(0.05)
        check("…folds away after the hold", f.state, IslandStateMachine.State.petit)

        // A burst leaves one timer, not one per notification, and the last one
        // to arrive is the one whose hold counts.
        let g = makeFSM()
        g.openedExternally()
        pump(0.04)
        g.openedExternally()       // re-arms: the hold starts again from here
        pump(0.03)
        check("second notification extends the hold", g.state, IslandStateMachine.State.home)
        pump(0.04)
        check("…and then folds away once", g.state, IslandStateMachine.State.petit)

        // Reading it with the cursor on the island stops the clock.
        let h = makeFSM()
        h.openedExternally()
        h.mouseEntered()
        pump(0.09)
        check("pointer on the island cancels the hold", h.state, IslandStateMachine.State.home)
        h.mouseLeft()
        pump(0.06)
        check("…and leaving then closes it", h.state, IslandStateMachine.State.petit)

        // Arriving under a cursor that is already on the island: no mouseEntered
        // fires to cancel a hold, so none may be started in the first place.
        let hh = makeFSM()
        hh.mouseEntered()
        hh.openedExternally()
        checkTrue("no hold starts under a resting pointer", !hh.holdRunning)
        pump(0.09)
        check("…and the card stays up", hh.state, IslandStateMachine.State.home)
        hh.mouseLeft()
        pump(0.06)
        check("…until the pointer leaves", hh.state, IslandStateMachine.State.petit)

        // A half-written reply is the one thing a timer may not take away.
        let i = makeFSM()
        var replying = true
        i.isHeldOpen = { replying }
        i.openedExternally()
        pump(0.09)
        check("a reply in progress holds it open", i.state, IslandStateMachine.State.home)
        replying = false
        i.mouseLeft()
        pump(0.06)
        check("…and it closes once the reply is done", i.state, IslandStateMachine.State.petit)

        print("IslandStateMachine — click and collapse")

        let j = makeFSM()
        j.reveal()
        j.click()
        check("click on the compact island → home", j.state, IslandStateMachine.State.home)
        j.mouseLeft()
        pump(0.06)
        check("…clicked open returns to petit, not hidden", j.state, IslandStateMachine.State.petit)

        let k = makeFSM()
        k.openedExternally()
        k.collapse()
        check("explicit collapse → petit", k.state, IslandStateMachine.State.petit)
        pump(0.09)
        check("…and the hold does not fire afterwards", k.state, IslandStateMachine.State.petit)

        // The compact bar still times out on its own after a work event.
        let l = makeFSM()
        l.reveal()
        pump(0.12)
        check("petit → hidden on its own timer", l.state, IslandStateMachine.State.hidden)

        // ── Wired up to a transition handler ────────────────────────────────
        //
        // Everything above drives the machine on its own. The bug that shipped
        // lived in the seam: `onTransition` runs synchronously inside a
        // transition, the controller's handler consulted its own copy of "is the
        // pointer on the island", and that copy is only refreshed at the end of
        // the poll tick. During a hover-open it still read false, so the handler
        // scheduled a collapse under a pointer that had just arrived — the
        // island opened and shut several times a second.
        //
        // These attach a handler shaped like the real one, so the seam is covered
        // too.
        print("IslandStateMachine — wired to a transition handler")

        func wire(_ fsm: IslandStateMachine) {
            fsm.onTransition = { _, to in
                switch to {
                case .petit:
                    // The compact bar still times itself out when nobody is on it.
                    if !fsm.pointerInside { fsm.mouseLeft() }
                case .home, .hidden, .coucou:
                    // Nothing. An island opened with nobody on it folds away on
                    // its hold, not on the leave grace.
                    break
                }
            }
        }

        // The contract the controller leans on, and the one the shipped bug
        // broke: by the time `onTransition` fires, `pointerInside` already tells
        // the truth. The controller used to read its own mirror instead, which
        // the poll only refreshes at the end of the tick — so it saw `false`
        // here and collapsed the island it had just opened.
        //
        // Proved against the mirror, not just asserted: `stale` is updated after
        // the dispatch exactly as `wasInIsland` is, and the two disagree.
        let probe = makeFSM()
        var stale = false
        var seenPointerInside: Bool?
        var seenStale: Bool?
        probe.onTransition = { _, to in
            if to == .home { seenPointerInside = probe.pointerInside; seenStale = stale }
        }
        probe.mouseEntered()
        stale = true                       // what the poll does, a beat too late
        checkTrue("pointerInside is true inside the transition", seenPointerInside == true)
        checkTrue("…while the mirror still reads false", seenStale == false)

        let m = makeFSM(); wire(m)
        m.mouseEntered()
        check("hover opens", m.state, IslandStateMachine.State.home)
        pump(0.15)
        checkTrue("…and nothing scheduled a collapse behind it", m.state == .home)
        pump(0.25)
        check("…still open with the pointer parked on it", m.state, IslandStateMachine.State.home)
        m.mouseLeft()
        pump(0.06)
        check("…and it closes once the pointer goes", m.state, IslandStateMachine.State.hidden)

        // A notification must get its whole hold, not the leave grace.
        let n = makeFSM(); wire(n)
        n.openedExternally()
        pump(0.03)
        check("notification survives the grace", n.state, IslandStateMachine.State.home)
        pump(0.05)
        check("…and folds on its hold", n.state, IslandStateMachine.State.petit)

        // Sweeping across the edge with a handler attached still settles once.
        let o = makeFSM(); wire(o)
        var oStates: [IslandStateMachine.State] = []
        o.mouseEntered()
        o.onTransition = { _, to in oStates.append(to) }
        for _ in 0..<5 { o.mouseLeft(); o.mouseEntered() }
        pump(0.15)
        check("sweeping the edge never transitions", oStates.count, 0)
        check("…and leaves it open", o.state, IslandStateMachine.State.home)

        print("")
        if failures == 0 {
            print("All island state machine tests passed.")
        } else {
            print("\(failures) failure(s).")
            exit(1)
        }
    }
}
