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

        print("")
        if failures == 0 {
            print("All island state machine tests passed.")
        } else {
            print("\(failures) failure(s).")
            exit(1)
        }
    }
}
