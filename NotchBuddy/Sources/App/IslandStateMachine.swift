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

    /// Blocks only the pointer-leave collapse, never an explicit one.
    ///
    /// Deliberately separate from `isHeldOpen`: `collapse()` guards on that one, so a view
    /// that merely wants to stay open while it is being read would also disable Escape and
    /// every deliberate way out.
    var holdsHomeOpen: (() -> Bool)?

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
    /// coucou → petit delay after the greeting animation ends. ~0.6s syncs with canvas collapse.
    var greetAutoCollapseDelay: TimeInterval = 0.6
    /// How long a notification stays fully open before it folds itself away
    /// (seconds). Driven by the user's auto-close preference: the controller
    /// assigns it from `AppState.autoCloseInterval`. Nothing assigned it for a
    /// long time, and the literal below was what every Mac really used while
    /// the settings field and the countdown hairline both showed something else.
    var notificationHoldDelay: TimeInterval = 5
    /// Time the open animation needs to land (seconds) — the hold above is
    /// counted from the end of it, so a notification is readable for its full
    /// duration. Matches `IslandMotion.openResponse`.
    var openAnimationDelay: TimeInterval = IslandMotion.openResponse

    /// Open animation plus hold — what the countdown hairline draws.
    var holdDuration: TimeInterval { openAnimationDelay + notificationHoldDelay }

    /// How a delayed transition reaches the future.
    ///
    /// The default below is the only thing the app ever uses; nothing assigns
    /// this outside the tests. It is a property so they can hand the machine a
    /// clock they advance by hand, because the alternative does not work: an
    /// assertion that a transition has *not* fired yet is a bet on how long
    /// `RunLoop.run(until:)` really takes, and on a loaded runner that bet
    /// loses. Scaling every delay to widen the margin was tried first, and the
    /// flake came back three days later — the margin scales, the jitter does
    /// not.
    ///
    /// Whatever is here is called on the main actor and must put the item
    /// somewhere that runs it there too: the work items below are closures
    /// written inside a `@MainActor` type, so in Swift 6 they inherit that
    /// isolation and running one anywhere else traps at runtime.
    var schedule: @MainActor (TimeInterval, DispatchWorkItem) -> Void = { delay, item in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

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
            // Back before the grace elapsed: the pointer wins, and the panel
            // stays until it goes.
            //
            // The notification hold is deliberately left running. Cancelling it
            // here let the pointer *shorten* a card, and this enter is as often
            // the poll's doing as the user's: expanding swaps the hover rect
            // from the island to the chrome, so a cursor that never moved can
            // cross into it.
            homeCollapseWork?.cancel(); homeCollapseWork = nil
        case .coucou:
            // The greeting plays to the end whatever the pointer does, so there
            // is no auto-collapse left to postpone.
            break
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
            // The greeting is never cut short, by the pointer or anything else.
            // It used to end here the instant the pointer left — and the pointer
            // "left" on its own: expanding swaps the hover rect from the island
            // to the chrome and widens the margin, so a cursor that never moved
            // falls outside it and the 60 Hz poll reports a leave. The animation
            // died in well under a second on practically every launch.
            break
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

    /// A notification, or any other request to open the panel from outside:
    /// open straight to expanded and hold it there.
    ///
    /// The hold is armed *before* the state changes, because `onTransition` runs
    /// synchronously inside it and reads the machine. Arming afterwards let the
    /// handler schedule a leave-collapse that nothing cleared, and the island
    /// folded away in a tenth of a second instead of holding.
    ///
    /// Re-entrant on purpose: every arming cancels the one before it, so a burst
    /// of notifications leaves exactly one timer running and the last to arrive
    /// is the one whose hold counts.
    func openedExternally() {
        cancelTimers()
        openedByHover = false
        scheduleNotificationHold()
        // `.coucou` is not excepted any more. It was, and the machine then sat
        // in `.coucou` with its greeting timer already cancelled above while the
        // hold's `guard state == .home` could never pass — an island left
        // expanded with nothing running to close it. The controller now holds a
        // card back until the greeting ends, so this is only ever reached from a
        // state the hold can actually fire in.
        if state != .home { state = .home }
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
    func greetComplete() {
        guard state == .coucou else { return }
        scheduleGreetCollapse(delay: greetAutoCollapseDelay)
    }

    private func scheduleGreetCollapse(delay: TimeInterval) {
        greetCollapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .coucou else { return }
            self.transition(to: .petit)
        }
        greetCollapseWork = item
        schedule(delay, item)
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
        schedule(petitToHiddenDelay, item)
    }

    private func scheduleHomeCollapse(delay: TimeInterval? = nil) {
        homeCollapseWork?.cancel(); homeCollapseWork = nil
        // A notification owns its own deadline. This used to cancel the hold and
        // put the 0.12 s leave grace in its place, which is how a card the user
        // had set to ten seconds folded away in a tenth of one.
        guard notificationHoldWork == nil else { return }
        guard !(isHeldOpen?() ?? false) else { return }
        let back: State = openedByHover ? .hidden : .petit
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .home else { return }
            // Re-arm instead of giving up, so the collapse lands the moment the view stops
            // holding. On its own cadence: leaveGraceDelay is 0.12s, and re-checking a held
            // view eight times a second would be pure waste.
            if self.holdsHomeOpen?() == true { self.scheduleHomeCollapse(delay: 1.0); return }
            self.openedByHover = false
            self.transition(to: back)
        }
        homeCollapseWork = item
        schedule(delay ?? leaveGraceDelay, item)
    }

    private func scheduleNotificationHold() {
        notificationHoldWork?.cancel(); notificationHoldWork = nil
        // An alert waiting for an answer is deliberately not exempt: it folds
        // away with everything else once its time is up, and Claude Code falls
        // back to asking in the terminal. Only an unfinished reply overrides it.
        // `pointerInside` is no longer a reason to skip the hold. It was, and a
        // card arriving under a resting cursor then had no timer at all: it sat
        // there until the next leave edge closed it on the 0.12 s grace.
        guard !(isHeldOpen?() ?? false) else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .home else { return }
            self.notificationHoldWork = nil
            // Its time is up, and the hold is a floor on how long the card stays
            // readable rather than a ceiling: with someone on the island, or
            // mid-reply, it stays until they leave and the ordinary leave grace
            // takes it from there.
            if self.pointerInside || (self.isHeldOpen?() ?? false) { return }
            self.transition(to: .petit)
        }
        notificationHoldWork = item
        schedule(holdDuration, item)
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
