import Foundation

/// Lets the main-queue timers the FSM schedules actually fire.
@MainActor
private func pump(_ seconds: Double) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
private func fresh() -> IslandStateMachine {
    let fsm = IslandStateMachine()
    // Short enough to keep the suite quick, far enough apart to tell the hover
    // grace and the deliberate-open interval from one another.
    fsm.hoverOpenDelayFromHidden = 0.05
    fsm.hoverOpenDelayFromPetit = 0.05
    fsm.hoverCloseDelay = 0.05
    fsm.homeToPetitDelay = 10
    fsm.petitToHiddenDelay = 10
    return fsm
}

@main
@MainActor
enum IslandStateMachineTests {
    static func main() {
        // Hover peeks at once, then opens on its own once the cursor has dwelt.
        do {
            let fsm = fresh()
            fsm.mouseEntered()
            precondition(fsm.state == .petit, "hover should peek before it opens")
            pump(0.15)
            precondition(fsm.state == .home, "dwelling on the island should open it")
        }

        // A cursor crossing the menu bar must not drag the panel open behind it.
        do {
            let fsm = fresh()
            fsm.mouseEntered()
            fsm.mouseLeft()
            pump(0.15)
            precondition(fsm.state != .home, "a sweep past the notch must never open the island")
        }

        // Leaving closes it again — all the way back to hidden, since that is
        // where the hover started. Anything less parks a bar on screen.
        do {
            let fsm = fresh()
            fsm.mouseEntered()
            pump(0.15)
            precondition(fsm.state == .home)
            fsm.mouseLeft()
            pump(0.15)
            precondition(fsm.state == .hidden, "a hover that started from hidden should close to hidden")
        }

        // Hovering a compact island opens it, and leaving returns it to compact:
        // there is live work behind it, so it must not vanish.
        do {
            let fsm = fresh()
            fsm.reveal()
            precondition(fsm.state == .petit)
            fsm.mouseEntered()
            pump(0.15)
            precondition(fsm.state == .home, "hovering the compact island should open it")
            fsm.mouseLeft()
            pump(0.15)
            precondition(fsm.state == .petit, "a hover that started from compact should close to compact")
        }

        // Coming back during the grace cancels the close, so brushing an edge
        // does not flicker the island shut.
        do {
            let fsm = fresh()
            fsm.mouseEntered()
            pump(0.15)
            fsm.mouseLeft()
            fsm.mouseEntered()
            pump(0.15)
            precondition(fsm.state == .home, "returning during the grace should keep it open")
        }

        // A pending approval outranks the cursor: answering it must not be
        // snatched away by walking the mouse off the island.
        do {
            let fsm = fresh()
            fsm.mouseEntered()
            pump(0.15)
            precondition(fsm.state == .home)
            fsm.isHeldOpen = { true }
            fsm.mouseLeft()
            pump(0.15)
            precondition(fsm.state == .home, "a held-open island must survive the cursor leaving")
        }

        // Clicking inside promotes it: from then on it follows Auto-close, not
        // the hover grace, so reading something you clicked into is not a race.
        do {
            let fsm = fresh()
            fsm.mouseEntered()
            pump(0.15)
            precondition(fsm.state == .home)
            fsm.engaged()
            fsm.mouseLeft()
            pump(0.15)
            precondition(fsm.state == .home, "a clicked-into island should keep the Auto-close interval")
        }

        // Clicking the compact island opens it deliberately, and that open also
        // outlives the cursor leaving.
        do {
            let fsm = fresh()
            fsm.reveal()
            fsm.click()
            precondition(fsm.state == .home)
            fsm.mouseLeft()
            pump(0.15)
            precondition(fsm.state == .home, "a click-opened island should not close on the hover grace")
        }

        // The greeting still wins over hover: it opens on launch and the cursor
        // leaving interrupts it to compact, exactly as before.
        do {
            let fsm = fresh()
            fsm.launch()
            precondition(fsm.state == .coucou)
            fsm.mouseEntered()
            precondition(fsm.state == .coucou, "hover must not reopen the greeting as home")
            fsm.mouseLeft()
            precondition(fsm.state == .petit, "leaving the greeting should interrupt it to compact")
        }

        // The two dwells are independent, and the menu-bar one is the slower:
        // crossing the notch should cost more patience than brushing a compact
        // island that is already on screen.
        do {
            let fsm = fresh()
            fsm.hoverOpenDelayFromHidden = 0.30
            fsm.hoverOpenDelayFromPetit = 0.05
            fsm.mouseEntered()
            pump(0.15)
            precondition(fsm.state == .petit, "the hidden dwell should still be running")
            pump(0.30)
            precondition(fsm.state == .home, "the hidden dwell should have opened it by now")
        }
        do {
            let fsm = fresh()
            fsm.hoverOpenDelayFromHidden = 0.30
            fsm.hoverOpenDelayFromPetit = 0.05
            fsm.reveal()
            fsm.mouseEntered()
            pump(0.15)
            precondition(fsm.state == .home, "the compact dwell is the short one")
        }

        print("IslandStateMachine: all checks passed")
    }
}
