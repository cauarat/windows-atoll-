import Foundation

/// Pure 4-state FSM for island open/close logic.
/// No AppKit / AppState dependencies — communicates via `onTransition`.
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

    /// When non-nil and returns true, timers and mouse-leave never auto-collapse or hide the island.
    var isHeldOpen: (() -> Bool)?

    /// home → petit delay (seconds) for an island the user opened on purpose.
    /// Driven by the Auto-close setting; the countdown bar reads the same value.
    var homeToPetitDelay: TimeInterval = 15
    /// petit → hidden delay (seconds). Override for debug.
    var petitToHiddenDelay: TimeInterval = 60
    /// coucou → petit delay after greeting animation ends (no hover). ~0.6s syncs with canvas collapse.
    var greetAutoCollapseDelay: TimeInterval = 0.6
    /// coucou → petit delay when mouse is hovering over the greeting.
    var greetHoverCollapseDelay: TimeInterval = 10

    /// How long the cursor has to rest before hover opens the island, counted
    /// from where the hover started — SPEC §3, rules 2 and 4.
    ///
    /// From hidden the island is idle in the menu bar, which the cursor crosses on
    /// its way to menus and status items, so opening takes a deliberate pause.
    /// From compact there is live work on screen already and the island is visible
    /// right under the cursor, so it opens almost at once.
    var hoverOpenDelayFromHidden: TimeInterval = 0.65
    var hoverOpenDelayFromPetit: TimeInterval = 0.20

    /// Grace between the cursor leaving and a hover-opened island closing again.
    /// Long enough that clipping a corner, or one jittery frame of the 60 Hz
    /// poll, does not slam it shut; short enough that leaving still reads as
    /// closing straight away.
    var hoverCloseDelay: TimeInterval = 0.25

    /// Where a hover-opened island returns to, and the flag for whether it was
    /// hover-opened at all. A click clears it: clicking is a deliberate open, and
    /// a deliberate open keeps the user's Auto-close interval instead of closing
    /// the instant the cursor wanders off.
    private(set) var hoverOrigin: State?

    private var petitHideWork: DispatchWorkItem?
    private var homeCollapseWork: DispatchWorkItem?
    private var greetCollapseWork: DispatchWorkItem?
    private var hoverOpenWork: DispatchWorkItem?
    private var hoverCloseWork: DispatchWorkItem?

    // MARK: – Inputs

    /// App launched or debug "launch greeting"
    func launch() {
        cancelTimers()
        hoverOrigin = nil
        transition(to: .coucou)
    }

    /// Mouse entered the island notch area
    func mouseEntered() {
        // Coming back cancels a pending close, so crossing out and in again
        // never flickers the island shut behind the cursor.
        hoverCloseWork?.cancel(); hoverCloseWork = nil

        switch state {
        case .hidden:
            if isHeldOpen?() == true {
                // Island already expanded by an external call — sync FSM state without transition
                state = .home
            } else {
                cancelTimers()
                // Peek first, exactly as before: the compact island is the instant
                // acknowledgement that the cursor arrived. Scheduling the open
                // after the transition matters, because `onTransition` runs
                // synchronously and may call back into `mouseLeft()`.
                transition(to: .petit)
                scheduleHoverOpen(from: .hidden)
            }
        case .petit:
            petitHideWork?.cancel()
            petitHideWork = nil
            scheduleHoverOpen(from: .petit)
        case .home:
            homeCollapseWork?.cancel()
            homeCollapseWork = nil
        case .coucou:
            // Mouse hovering during greeting — cancel short auto-collapse, extend to hover delay
            scheduleGreetCollapse(delay: greetHoverCollapseDelay)
        }
    }

    /// Mouse left the island notch area
    func mouseLeft() {
        // A cursor that has already moved on was never dwelling: drop the pending open.
        hoverOpenWork?.cancel(); hoverOpenWork = nil

        switch state {
        case .hidden:
            break
        case .petit:
            schedulePetitHide()
        case .home:
            guard isHeldOpen?() != true else { break }
            if hoverOrigin != nil {
                scheduleHoverClose()
            } else {
                scheduleHomeCollapse()
            }
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
        hoverOrigin = nil
        transition(to: .home)
    }

    /// A click landed inside an already-open island. Hover brought it up, but the
    /// user is working in it now, so it stops being disposable: from here it
    /// follows the Auto-close interval like any island opened on purpose.
    func engaged() {
        hoverOpenWork?.cancel();  hoverOpenWork = nil
        hoverCloseWork?.cancel(); hoverCloseWork = nil
        hoverOrigin = nil
    }

    /// The app hid the island on its own (e.g. `AppState.syncMode()` when the last
    /// task ends). Mirror it without side effects, so the next hover peeks again
    /// instead of being swallowed by a FSM that still thinks the island is `.petit`.
    func hiddenExternally() {
        guard state == .petit else { return }
        cancelTimers()
        hoverOrigin = nil
        state = .hidden
    }

    /// The app expanded the island externally (hookExpand for an alert).
    /// Cancel timers and sync state to `.home` without firing `onTransition`, so the
    /// next hover/mouseLeft behave correctly instead of collapsing the island.
    func openedExternally() {
        cancelTimers()
        hoverOrigin = nil
        guard state != .home && state != .coucou else { return }
        state = .home
    }

    /// The app folded the island itself (Escape, Settings, OK button, auto-close).
    /// Move to `.petit` right away so hover and click keep working; waiting for the
    /// 15 s home timer left the island compact on screen while the FSM still said `.home`.
    func collapse() {
        guard state == .home || state == .coucou else { return }
        cancelTimers()
        hoverOrigin = nil
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
        hoverOrigin = nil
        transition(to: .petit)
        schedulePetitHide()
    }

    // MARK: – Timers

    /// Dwell before hover opens the island. `origin` is where it goes back to
    /// when the cursor leaves, so a hover that started from nothing closes all
    /// the way to nothing instead of parking a compact island on screen.
    private func scheduleHoverOpen(from origin: State) {
        hoverOpenWork?.cancel()
        let delay = origin == .hidden ? hoverOpenDelayFromHidden : hoverOpenDelayFromPetit
        guard delay > 0 else {
            hoverOpenWork = nil
            openByHover(from: origin)
            return
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverOpenWork = nil
            self.openByHover(from: origin)
        }
        hoverOpenWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func openByHover(from origin: State) {
        guard state == .petit || state == .hidden else { return }
        cancelTimers()
        hoverOrigin = origin
        transition(to: .home)
    }

    private func scheduleHoverClose() {
        hoverCloseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverCloseWork = nil
            guard self.state == .home, self.isHeldOpen?() != true else { return }
            let target = self.hoverOrigin ?? .petit
            self.hoverOrigin = nil
            self.transition(to: target)
            // Back at compact, the ordinary 60 s hide timer takes over again.
            if target == .petit { self.schedulePetitHide() }
        }
        hoverCloseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverCloseDelay, execute: item)
    }

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
        homeCollapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .home, !(self.isHeldOpen?() ?? false) else { return }
            self.transition(to: .petit)
        }
        homeCollapseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + homeToPetitDelay, execute: item)
    }

    func cancelTimers() {
        petitHideWork?.cancel();     petitHideWork = nil
        homeCollapseWork?.cancel();  homeCollapseWork = nil
        greetCollapseWork?.cancel(); greetCollapseWork = nil
        hoverOpenWork?.cancel();     hoverOpenWork = nil
        hoverCloseWork?.cancel();    hoverCloseWork = nil
    }

    private func transition(to new: State) {
        guard new != state else { return }
        let old = state
        state = new
        onTransition?(old, new)
    }

}
