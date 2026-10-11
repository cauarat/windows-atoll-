// Island open/close FSM — port of IslandStateMachine.swift.
// No DOM, no Tauri: it only reports transitions.

export type FsmState = "hidden" | "petit" | "home" | "coucou";

export class IslandStateMachine {
  state: FsmState = "hidden";

  onTransition: ((from: FsmState, to: FsmState) => void) | null = null;

  /** home → petit delay, seconds, for an island the user opened on purpose. */
  homeToPetitDelay = 15;
  /** petit → hidden delay, seconds. */
  petitToHiddenDelay = 60;
  /** coucou → petit once the greeting animation ends (no hover). */
  greetAutoCollapseDelay = 0.6;
  /** coucou → petit while the mouse hovers the greeting. */
  greetHoverCollapseDelay = 10;
  /** An alert waiting for an answer stays open, even when the mouse leaves. */
  pinned = false;

  /**
   * How long the cursor has to rest before hover opens the island, counted from
   * where the hover started — SPEC §3, rules 2 and 4.
   *
   * From hidden the island is idle at the top of the screen, which the cursor
   * crosses on its way to window controls and the tray, so opening takes a
   * deliberate pause. From compact there is live work on screen already and the
   * island is visible right under the cursor, so it opens almost at once.
   */
  hoverOpenDelayFromHidden = 0.65;
  hoverOpenDelayFromPetit = 0.2;

  /**
   * Grace between the cursor leaving and a hover-opened island closing again.
   * Long enough that clipping a corner, or one jittery frame of the 60 Hz poll,
   * does not slam it shut; short enough that leaving still reads as closing
   * straight away.
   */
  hoverCloseDelay = 0.25;

  /**
   * Where a hover-opened island returns to, and the flag for whether it was
   * hover-opened at all. A click clears it: clicking is a deliberate open, and a
   * deliberate open keeps the user's Auto-close interval instead of closing the
   * instant the cursor wanders off.
   */
  hoverOrigin: FsmState | null = null;

  private petitHide: number | null = null;
  private homeCollapse: number | null = null;
  private greetCollapse: number | null = null;
  private hoverOpen: number | null = null;
  private hoverClose: number | null = null;

  // ── Inputs ──────────────────────────────────────────────────────────────────

  launch() {
    this.cancelTimers();
    this.hoverOrigin = null;
    this.transition("coucou");
  }

  mouseEntered() {
    // Coming back cancels a pending close, so crossing out and in again never
    // flickers the island shut behind the cursor.
    this.clear("hoverClose");

    switch (this.state) {
      case "hidden":
        this.cancelTimers();
        // Peek first, exactly as before: the compact island is the instant
        // acknowledgement that the cursor arrived. Scheduling the open after the
        // transition matters, because `onTransition` runs synchronously and may
        // call back into `mouseLeft()`.
        this.transition("petit");
        this.scheduleHoverOpen("hidden");
        break;
      case "petit":
        this.clear("petitHide");
        this.scheduleHoverOpen("petit");
        break;
      case "home":
        this.clear("homeCollapse");
        break;
      case "coucou":
        this.scheduleGreetCollapse(this.greetHoverCollapseDelay);
        break;
    }
  }

  mouseLeft() {
    // A cursor that has already moved on was never dwelling: drop the pending open.
    this.clear("hoverOpen");

    switch (this.state) {
      case "hidden":
        break;
      case "petit":
        this.schedulePetitHide();
        break;
      case "home":
        if (this.pinned) break;
        if (this.hoverOrigin !== null) this.scheduleHoverClose();
        else this.scheduleHomeCollapse();
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
    this.hoverOrigin = null;
    this.transition("home");
  }

  /**
   * A click landed inside an already-open island. Hover brought it up, but the
   * user is working in it now, so it stops being disposable: from here it
   * follows the Auto-close interval like any island opened on purpose.
   */
  engaged() {
    this.clear("hoverOpen");
    this.clear("hoverClose");
    this.hoverOrigin = null;
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
    this.hoverOrigin = null;
    this.transition("petit");
    this.schedulePetitHide();
  }

  /** Alert or explicit request: open straight to expanded. */
  forceHome() {
    this.cancelTimers();
    this.hoverOrigin = null;
    this.transition("home");
  }

  /// Explicit close (OK button, Escape, an alert being answered).
  forcePetit() {
    this.cancelTimers();
    this.hoverOrigin = null;
    this.transition("petit");
  }

  forceHidden() {
    this.cancelTimers();
    this.hoverOrigin = null;
    this.transition("hidden");
  }

  // ── Timers ──────────────────────────────────────────────────────────────────

  /**
   * Dwell before hover opens the island. `origin` is where it goes back to when
   * the cursor leaves, so a hover that started from nothing closes all the way
   * to nothing instead of parking a compact island on screen.
   */
  private scheduleHoverOpen(origin: FsmState) {
    this.clear("hoverOpen");
    const delay = origin === "hidden" ? this.hoverOpenDelayFromHidden : this.hoverOpenDelayFromPetit;
    if (delay <= 0) {
      this.openByHover(origin);
      return;
    }
    this.hoverOpen = window.setTimeout(() => {
      this.hoverOpen = null;
      this.openByHover(origin);
    }, delay * 1000);
  }

  private openByHover(origin: FsmState) {
    if (this.state !== "petit" && this.state !== "hidden") return;
    this.cancelTimers();
    this.hoverOrigin = origin;
    this.transition("home");
  }

  private scheduleHoverClose() {
    this.clear("hoverClose");
    this.hoverClose = window.setTimeout(() => {
      this.hoverClose = null;
      if (this.state !== "home" || this.pinned) return;
      const target = this.hoverOrigin ?? "petit";
      this.hoverOrigin = null;
      this.transition(target);
      // Back at compact, the ordinary hide timer takes over again.
      if (target === "petit") this.schedulePetitHide();
    }, this.hoverCloseDelay * 1000);
  }

  private schedulePetitHide() {
    this.clear("petitHide");
    this.petitHide = window.setTimeout(() => {
      this.petitHide = null;
      if (this.state === "petit") this.transition("hidden");
    }, this.petitToHiddenDelay * 1000);
  }

  private scheduleHomeCollapse() {
    this.clear("homeCollapse");
    if (this.pinned) return;
    this.homeCollapse = window.setTimeout(() => {
      this.homeCollapse = null;
      if (this.state === "home") this.transition("petit");
    }, this.homeToPetitDelay * 1000);
  }

  private scheduleGreetCollapse(delay: number) {
    this.clear("greetCollapse");
    this.greetCollapse = window.setTimeout(() => {
      this.greetCollapse = null;
      if (this.state === "coucou") this.transition("petit");
    }, delay * 1000);
  }

  private clear(which: "petitHide" | "homeCollapse" | "greetCollapse" | "hoverOpen" | "hoverClose") {
    const id = this[which];
    if (id != null) window.clearTimeout(id);
    this[which] = null;
  }

  cancelTimers() {
    this.clear("petitHide");
    this.clear("homeCollapse");
    this.clear("greetCollapse");
    this.clear("hoverOpen");
    this.clear("hoverClose");
  }

  private transition(next: FsmState) {
    if (next === this.state) return;
    const from = this.state;
    this.state = next;
    this.onTransition?.(from, next);
  }
}
