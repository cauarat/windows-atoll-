// Island open/close FSM — port of IslandStateMachine.swift.
// No DOM, no Tauri: it only reports transitions.
//
// Hover drives the island directly: the pointer reaching the island opens the
// full panel, and leaving closes it again after a grace short enough to feel
// instant but long enough that a cursor skimming the boundary does not flicker.
// A notification opens the same panel and holds it for `notificationHoldDelay`
// once the open animation has landed.
//
// Where it folds back to is the `alwaysVisible` preference: on, the compact bar
// stays in its corner for as long as Coucou runs and `hidden` is reached only
// by the master switch; off, the bar gives up after `petitToHiddenDelay` and
// retracts into the screen edge, leaving the wake strip behind.

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
  /**
   * petit → hidden delay, seconds. A work event keeps the compact island up.
   * Never runs at all while `alwaysVisible` is on, which is the default.
   */
  petitToHiddenDelay = 60;
  /** coucou → petit once the greeting animation ends. */
  greetAutoCollapseDelay = 0.6;
  /**
   * How long a notification stays fully open before it folds itself away,
   * seconds. Driven by the user's auto-close preference.
   */
  notificationHoldDelay = 5;
  /**
   * Time the open animation needs to land, seconds — the hold above is counted
   * from the end of it, so a notification is readable for its full duration.
   * Matches the open spring's response on both platforms (see core/anim.ts and
   * IslandMotion.openResponse). It claimed to match while being half a second
   * against the Mac's 0.34, which put the two countdowns a frame-and-a-half
   * apart for anyone comparing them side by side.
   */
  openAnimationDelay = 0.34;
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

  private alwaysVisibleFlag = false;
  /** True once `launch()` has run, so the boot state is not mistaken for a fold. */
  private launched = false;

  /**
   * The island never folds away: with nothing left to say it rests as the
   * compact bar in its corner instead of retracting into the screen edge.
   *
   * A setter rather than a field because flipping it has to settle the island
   * that is already on screen — on cancels the fold that was counting down and
   * brings back one that has already gone, off starts that countdown again.
   * Nothing is brought back before `launch()`: at boot the machine is in
   * `hidden` because it has not started yet, and waking it there would put a
   * compact bar on screen for one frame before the greeting opened over it.
   */
  get alwaysVisible(): boolean {
    return this.alwaysVisibleFlag;
  }

  set alwaysVisible(on: boolean) {
    if (on === this.alwaysVisibleFlag) return;
    // Set before anything else: `transition` runs its handler synchronously,
    // and that handler schedules the very timer this flag turns into a no-op.
    this.alwaysVisibleFlag = on;
    if (on) {
      this.clear("petitHide");
      if (this.launched && this.state === "hidden") this.transition("petit");
    } else if (this.state === "petit" && !this.pointerInside) {
      this.schedulePetitHide();
    }
  }

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
    this.launched = true;
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
        // Back before the grace elapsed: the pointer wins, and the panel stays
        // until it leaves.
        //
        // The notification hold is deliberately left running. Clearing it here
        // let the pointer *shorten* a card, and this enter is as often the
        // poll's doing as the user's: expanding moves the hover rect out from
        // under a cursor that never went anywhere.
        this.clear("homeCollapse");
        break;
      case "coucou":
        // The greeting plays to the end whatever the pointer does, so there is
        // no auto-collapse left to postpone.
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
        // The greeting is never cut short. It used to end here the instant the
        // pointer left, and the pointer "left" on its own: expanding swaps the
        // hover rect from the island to the chrome, so a cursor that never
        // moved falls outside it and the poll reports a leave.
        break;
    }
  }

  click() {
    if (this.state !== "petit") return;
    this.cancelTimers();
    this.openedByHover = false;
    this.transition("home");
  }

  /** Greeting animation finished (T.end). */
  greetComplete() {
    if (this.state !== "coucou") return;
    this.scheduleGreetCollapse(this.greetAutoCollapseDelay);
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

  /**
   * Off screen entirely — the master switch, and nothing else. Not governed by
   * `alwaysVisible`: switching Coucou off has to take the island with it.
   */
  forceHidden() {
    this.cancelTimers();
    this.openedByHover = false;
    this.transition("hidden");
  }

  // ── Timers ──────────────────────────────────────────────────────────────────

  private schedulePetitHide() {
    this.clear("petitHide");
    // The one timer `alwaysVisible` switches off. Everything else still runs:
    // a notification still folds back to the compact bar on its own, it just
    // has somewhere to fold back to that stays on screen.
    if (this.alwaysVisibleFlag) return;
    this.petitHide = window.setTimeout(() => {
      this.petitHide = null;
      if (this.state === "petit") this.transition("hidden");
    }, this.petitToHiddenDelay * 1000);
  }

  private scheduleHomeCollapse() {
    this.clear("homeCollapse");
    // A notification owns its own deadline. This used to clear the hold and put
    // the 0.12 s leave grace in its place, which is how a card the user had set
    // to ten seconds folded away in a tenth of one.
    if (this.notificationHold != null) return;
    if (this.pinned || this.heldOpen) return;
    // Opened by nothing but the pointer, the island goes back to nothing when
    // it leaves — unless it is meant to stay, in which case the compact bar is
    // the nothing it goes back to.
    const back: FsmState =
      this.openedByHover && !this.alwaysVisibleFlag ? "hidden" : "petit";
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
    // `pointerInside` is no longer a reason to skip the hold. It was, and a
    // card arriving under a resting cursor then had no timer at all: it sat
    // there until the next leave edge closed it on the 0.12 s grace.
    if (this.heldOpen) return;
    const delay = this.openAnimationDelay + this.notificationHoldDelay;
    this.notificationHold = window.setTimeout(() => {
      this.notificationHold = null;
      if (this.state !== "home") return;
      // Its time is up, and the hold is a floor on how long the card stays
      // readable rather than a ceiling: with someone on the island, or
      // mid-reply, it stays until they leave and the leave grace takes over.
      if (this.pointerInside || this.heldOpen) return;
      this.transition("petit");
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
