// Island open/close FSM — port of IslandStateMachine.swift.
// No DOM, no Tauri: it only reports transitions.
//
// Hover drives the island directly: the pointer reaching the island opens the
// full panel, and leaving closes it again after a grace short enough to feel
// instant but long enough that a cursor skimming the boundary does not flicker.
// A notification opens the same panel and holds it for `notificationHoldDelay`
// once the open animation has landed.

export type FsmState = "hidden" | "petit" | "home" | "coucou";

export class IslandStateMachine {
  state: FsmState = "hidden";

  onTransition: ((from: FsmState, to: FsmState) => void) | null = null;

  /**
   * home → petit/hidden once the pointer leaves, seconds.
   *
   * Not zero on purpose: the hit test has a margin, and a cursor travelling
   * along the edge crosses in and out of it within a frame or two. This is the
   * only debounce in the FSM and it exists to stop that flicker — short enough
   * that the collapse still reads as a direct answer to the pointer leaving.
   */
  leaveGraceDelay = 0.12;
  /** petit → hidden delay, seconds. A work event keeps the compact island up. */
  petitToHiddenDelay = 60;
  /** coucou → petit once the greeting animation ends (no hover). */
  greetAutoCollapseDelay = 0.6;
  /** coucou → petit while the mouse hovers the greeting. */
  greetHoverCollapseDelay = 10;
  /**
   * How long a notification stays fully open before it folds itself away,
   * seconds. Driven by the user's auto-close preference.
   */
  notificationHoldDelay = 5;
  /**
   * Time the open animation needs to land, seconds — the hold above is counted
   * from the end of it, so a notification is readable for its full duration.
   * Matches the open spring's response on both platforms (see core/anim.ts and
   * IslandRootView.openSpring).
   */
  openAnimationDelay = 0.5;
  /** An alert waiting for an answer stays open, even when the mouse leaves. */
  pinned = false;
  /**
   * Someone is mid-sentence in the reply field.
   *
   * Stronger than `pinned`, and the only thing that stops the hold above: a
   * notification folding itself away is wanted, a half-written reply vanishing
   * on a timer is not. Mirrors `AppState.isReplying` feeding `fsm.isHeldOpen`.
   */
  heldOpen = false;

  private petitHide: number | null = null;
  private homeCollapse: number | null = null;
  private greetCollapse: number | null = null;
  private notificationHold: number | null = null;

  /**
   * True while the panel is open only because the pointer is on it, having
   * opened from nothing. Leaving then returns to nothing rather than parking a
   * compact island on screen for a minute — that bar belongs to a work event,
   * not to having brushed past the corner.
   */
  private openedByHover = false;

  /**
   * Whether the pointer is on the island right now.
   *
   * The machine tracks this itself so a notification arriving under a cursor
   * that is already there does not start a hold: nothing would cancel it, and
   * the card would fold away while it was being read.
   */
  pointerInside = false;

  /** For the countdown hairline, which may only draw a hold that is running. */
  get holdRunning(): boolean {
    return this.notificationHold != null;
  }

  /** Open animation plus hold, in ms — what the countdown hairline draws. */
  get holdDurationMs(): number {
    return (this.openAnimationDelay + this.notificationHoldDelay) * 1000;
  }

  // ── Inputs ──────────────────────────────────────────────────────────────────

  launch() {
    this.cancelTimers();
    this.transition("coucou");
  }

  mouseEntered() {
    this.pointerInside = true;
    switch (this.state) {
      case "hidden":
      case "petit":
        // Hover opens the panel itself. One spring from whatever is on screen
        // to the full size, so it reads as the island physically expanding.
        this.openedByHover = this.state === "hidden";
        this.cancelTimers();
        this.transition("home");
        break;
      case "home":
        // Back before the grace elapsed, or in while a notification was
        // counting down: the pointer wins, and the panel stays until it leaves.
        this.clear("homeCollapse");
        this.clear("notificationHold");
        break;
      case "coucou":
        this.scheduleGreetCollapse(this.greetHoverCollapseDelay);
        break;
    }
  }

  mouseLeft() {
    this.pointerInside = false;
    switch (this.state) {
      case "hidden":
        break;
      case "petit":
        this.schedulePetitHide();
        break;
      case "home":
        this.scheduleHomeCollapse();
        break;
      case "coucou":
        this.clear("greetCollapse");
        this.transition("petit");
        break;
    }
  }

  click() {
    if (this.state !== "petit") return;
    this.cancelTimers();
    this.openedByHover = false;
    this.transition("home");
  }

  /** Greeting animation finished (T.end). Doesn't override a running hover timer. */
  greetComplete() {
    if (this.state !== "coucou") return;
    if (this.greetCollapse == null) this.scheduleGreetCollapse(this.greetAutoCollapseDelay);
  }

  /** Non-alert work event: show compact from hidden. */
  reveal() {
    if (this.state !== "hidden") return;
    this.cancelTimers();
    this.transition("petit");
    this.schedulePetitHide();
  }

  /**
   * A notification, or any other request to open the panel from outside: open
   * straight to expanded and hold it there.
   *
   * The hold is armed *before* the transition, because `onTransition` runs
   * synchronously inside it and reads the machine's state. Arming afterwards
   * let the handler schedule a leave-collapse that nothing cleared, and the
   * island folded away in a tenth of a second instead of holding.
   *
   * Re-entrant on purpose. Every arming cancels the one before it, so a burst
   * of notifications leaves exactly one timer running and the last one to
   * arrive is the one whose hold counts.
   */
  forceHome() {
    this.cancelTimers();
    this.openedByHover = false;
    this.scheduleNotificationHold();
    this.transition("home");
  }

  /// Explicit close (OK button, Escape, an alert being answered).
  forcePetit() {
    this.cancelTimers();
    this.openedByHover = false;
    this.transition("petit");
  }

  forceHidden() {
    this.cancelTimers();
    this.openedByHover = false;
    this.transition("hidden");
  }

  // ── Timers ──────────────────────────────────────────────────────────────────

  private schedulePetitHide() {
    this.clear("petitHide");
    this.petitHide = window.setTimeout(() => {
      this.petitHide = null;
      if (this.state === "petit") this.transition("hidden");
    }, this.petitToHiddenDelay * 1000);
  }

  private scheduleHomeCollapse() {
    this.clear("homeCollapse");
    this.clear("notificationHold");
    if (this.pinned || this.heldOpen) return;
    const back: FsmState = this.openedByHover ? "hidden" : "petit";
    this.homeCollapse = window.setTimeout(() => {
      this.homeCollapse = null;
      if (this.state !== "home") return;
      this.openedByHover = false;
      this.transition(back);
    }, this.leaveGraceDelay * 1000);
  }

  private scheduleNotificationHold() {
    this.clear("notificationHold");
    // `pinned` is deliberately not checked: an alert waiting for an answer folds
    // away with everything else once its time is up, and Claude Code falls back
    // to asking in the terminal. Only an unfinished reply overrides it.
    if (this.heldOpen || this.pointerInside) return;
    const delay = this.openAnimationDelay + this.notificationHoldDelay;
    this.notificationHold = window.setTimeout(() => {
      this.notificationHold = null;
      // The pointer arriving cancels this timer, so reaching here means nobody
      // is on the island and it is safe to fold away.
      if (this.state === "home") this.transition("petit");
    }, delay * 1000);
  }

  private scheduleGreetCollapse(delay: number) {
    this.clear("greetCollapse");
    this.greetCollapse = window.setTimeout(() => {
      this.greetCollapse = null;
      if (this.state === "coucou") this.transition("petit");
    }, delay * 1000);
  }

  private clear(which: "petitHide" | "homeCollapse" | "greetCollapse" | "notificationHold") {
    const id = this[which];
    if (id != null) window.clearTimeout(id);
    this[which] = null;
  }

  cancelTimers() {
    this.clear("petitHide");
    this.clear("homeCollapse");
    this.clear("greetCollapse");
    this.clear("notificationHold");
  }

  private transition(next: FsmState) {
    if (next === this.state) return;
    const from = this.state;
    this.state = next;
    this.onTransition?.(from, next);
  }
}
