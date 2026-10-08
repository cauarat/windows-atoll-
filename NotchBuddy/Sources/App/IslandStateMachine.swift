import Foundation

/// Pure 4-state FSM for island open/close logic.
/// No AppKit / AppState dependencies — communicates via `onTransition`.
///
/// Hover drives the island directly: the pointer reaching it opens the full
/// panel, and leaving closes it again after a grace short enough to feel instant
/// but long enough that a cursor skimming the boundary does not flicker. A
/// notification opens the same panel and holds it for `notificationHoldDelay`
/// once the open animation has landed.
///
/// Kept in step with `windows/src/island/fsm.ts`, which is a direct port: the
/// states, the delays and the transitions are the same on both platforms.
@MainActor
final class IslandStateMachine {

    enum State: Equatable {
        case hidden   // island invisible (notch size)
        case petit    // compact island (notch + ears)
        case home     // expanded, overview
        case coucou   // expanded, greeting animation
    }

    private(set) var state: State = .hidden

    /// Fired on every transition: (from, to)
    var onTransition: ((State, State) -> Void)?

    /// When non-nil and returns true, nothing auto-collapses the island.
    ///
    /// Means "someone is mid-sentence in the reply field", not "an alert is
    /// waiting for an answer": a notification folding itself away is wanted, a
    /// half-written reply vanishing on a timer is not.
    var isHeldOpen: (() -> Bool)?

    /// home → petit/hidden once the pointer leaves (seconds).
    ///
    /// Not zero on purpose: the hit test has a margin, and a cursor travelling
    /// along the edge crosses in and out of it within a frame or two. This is
    /// the only debounce in the FSM and it exists to stop that flicker — short
    /// enough that the collapse still reads as a direct answer to the pointer
    /// leaving.
    var leaveGraceDelay: TimeInterval = 0.12
    /// petit → hidden delay (seconds). A work event keeps the compact island up.
    var petitToHiddenDelay: TimeInterval = 60
    /// coucou → petit delay after greeting animation ends (no hover). ~0.6s syncs with canvas collapse.
    var greetAutoCollapseDelay: TimeInterval = 0.6
    /// coucou → petit delay when mouse is hovering over the greeting.
    var greetHoverCollapseDelay: TimeInterval = 10
    /// How long a notification stays fully open before it folds itself away
    /// (seconds). Driven by the user's auto-close preference.
    var notificationHoldDelay: TimeInterval = 5
    /// Time the open animation needs to land (seconds) — the hold above is
    /// counted from the end of it, so a notification is readable for its full
    /// duration. Matches `IslandMotion.openResponse`.
    var openAnimationDelay: TimeInterval = IslandMotion.openResponse

    /// Open animation plus hold — what the countdown hairline draws.
    var holdDuration: TimeInterval { openAnimationDelay + notificationHoldDelay }

    private var petitHideWork: DispatchWorkItem?
    private var homeCollapseWork: DispatchWorkItem?
    private var greetCollapseWork: DispatchWorkItem?
    private var notificationHoldWork: DispatchWorkItem?

    /// True while the panel is open only because the pointer is on it, having
    /// opened from nothing. Leaving then returns to nothing rather than parking
    /// a compact island on screen for a minute — that bar belongs to a work
    /// event, not to having brushed past the corner.
    private var openedByHover = false

    /// Whether the pointer is on the island right now.
    ///
    /// The machine tracks this itself so a notification arriving under a cursor
    /// that is already there does not start a hold: nothing would cancel it, and
    /// the card would fold away while it was being read.
    private(set) var pointerInside = false

    /// For the countdown hairline, which may only draw a hold that is running.
    var holdRunning: Bool { notificationHoldWork != nil }

    // MARK: – Inputs

    /// App launched or debug "launch greeting"
    func launch() {
        cancelTimers()
        transition(to: .coucou)
    }

    /// Mouse entered the island notch area
    func mouseEntered() {
        pointerInside = true
        switch state {
        case .hidden, .petit:
            // Hover opens the panel itself. One spring from whatever is on
            // screen to the full size, so it reads as the island expanding.
            openedByHover = (state == .hidden)
            cancelTimers()
            transition(to: .home)
        case .home:
            // Back before the grace elapsed, or in while a notification was
            // counting down: the pointer wins, and the panel stays until it goes.
            homeCollapseWork?.cancel(); homeCollapseWork = nil
            notificationHoldWork?.cancel(); notificationHoldWork = nil
        case .coucou:
            // Mouse hovering during greeting — cancel short auto-collapse, extend to hover delay
            scheduleGreetCollapse(delay: greetHoverCollapseDelay)
        }
    }

    /// Mouse left the island notch area
    func mouseLeft() {
        pointerInside = false
        switch state {
        case .hidden:
            break
        case .petit:
            schedulePetitHide()
        case .home:
            scheduleHomeCollapse()
        case .coucou:
            if isHeldOpen?() != true {
                // Interrupt greeting immediately → compact (overrides 10s auto-collapse)
                greetCollapseWork?.cancel(); greetCollapseWork = nil
                transition(to: .petit)
            }
        }
    }

    /// Compact island clicked.
    /// Also accepts `.hidden`: after an alert the island can be on screen while the
    /// FSM never saw the mouse enter (it was already there), and the click must still open it.
    func click() {
        guard state == .petit || state == .hidden else { return }
        cancelTimers()
        openedByHover = false
        transition(to: .home)
    }

    /// The app hid the island on its own (e.g. `AppState.syncMode()` when the last
    /// task ends). Mirror it without side effects, so the next hover peeks again
    /// instead of being swallowed by a FSM that still thinks the island is `.petit`.
    func hiddenExternally() {
        guard state == .petit else { return }
        cancelTimers()
        openedByHover = false
        state = .hidden
    }

    /// The app expanded the island externally (hookExpand for an alert).
    ///
    /// Syncs state to `.home` without firing `onTransition`, and arms the hold
    /// so the notification folds itself away instead of staying up until the
    /// user happens to touch it.
    ///
    /// Re-entrant on purpose: every arming cancels the one before it, so a burst
    /// of notifications leaves exactly one timer running and the last to arrive
    /// is the one whose hold counts.
    func openedExternally() {
        cancelTimers()
        openedByHover = false
        if state != .home && state != .coucou { state = .home }
        scheduleNotificationHold()
    }

    /// The app folded the island itself (Escape, Settings, OK button, auto-close).
    /// Move to `.petit` right away so hover and click keep working; waiting for the
    /// 15 s home timer left the island compact on screen while the FSM still said `.home`.
    func collapse() {
        guard state == .home || state == .coucou else { return }
        cancelTimers()
        openedByHover = false
        transition(to: .petit)
    }

    /// Greeting animation finished (called at T.end ≈ 4.60 s).
    /// Schedules auto-collapse. Does not override a longer hover timer already running.
    func greetComplete() {
        guard state == .coucou else { return }
        // If mouse entered before this fires (hover timer already running), don't override it
        if greetCollapseWork == nil {
            scheduleGreetCollapse(delay: greetAutoCollapseDelay)
        }
    }

    private func scheduleGreetCollapse(delay: TimeInterval) {
        greetCollapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .coucou else { return }
            self.transition(to: .petit)
        }
        greetCollapseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Non-alert work event: show compact from hidden (HookServer reveal)
    func reveal() {
        guard state == .hidden else { return }
        cancelTimers()
        transition(to: .petit)
        schedulePetitHide()
    }

    // MARK: – Timers

    private func schedulePetitHide() {
        petitHideWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .petit, !(self.isHeldOpen?() ?? false) else { return }
            self.transition(to: .hidden)
        }
        petitHideWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + petitToHiddenDelay, execute: item)
    }

    private func scheduleHomeCollapse() {
        homeCollapseWork?.cancel(); homeCollapseWork = nil
        notificationHoldWork?.cancel(); notificationHoldWork = nil
        guard !(isHeldOpen?() ?? false) else { return }
        let back: State = openedByHover ? .hidden : .petit
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .home else { return }
            self.openedByHover = false
            self.transition(to: back)
        }
        homeCollapseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + leaveGraceDelay, execute: item)
    }

    private func scheduleNotificationHold() {
        notificationHoldWork?.cancel(); notificationHoldWork = nil
        // An alert waiting for an answer is deliberately not exempt: it folds
        // away with everything else once its time is up, and Claude Code falls
        // back to asking in the terminal. Only an unfinished reply overrides it.
        guard !(isHeldOpen?() ?? false), !pointerInside else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .home else { return }
            // The pointer arriving cancels this timer, so reaching here means
            // nobody is on the island and it is safe to fold away.
            self.transition(to: .petit)
        }
        notificationHoldWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration, execute: item)
    }

    func cancelTimers() {
        petitHideWork?.cancel();    petitHideWork = nil
        homeCollapseWork?.cancel(); homeCollapseWork = nil
        greetCollapseWork?.cancel(); greetCollapseWork = nil
        notificationHoldWork?.cancel(); notificationHoldWork = nil
    }

    private func transition(to new: State) {
        guard new != state else { return }
        let old = state
        state = new
        onTransition?(old, new)
    }

}
