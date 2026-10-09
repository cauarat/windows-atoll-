// A focus or break countdown — port of FocusTimer.swift.
//
// A module-level singleton rather than state inside the view, for the same
// reason as on the Mac: every view is built once and kept, so a clock owned by
// the timer tab would be rebuilt and a ticker living there would run while you
// were looking at Home. The view reads this; this owns the clock.

import { Sound } from "./sound";

export type TimerKind = "focus" | "rest";

/** What the buttons offer. A Pomodoro and its short break, plus a long break
 *  and a short sprint for when 25 is too much to commit to. */
export const TIMER_PRESETS: ReadonlyArray<{ kind: TimerKind; minutes: number }> = [
  { kind: "focus", minutes: 25 },
  { kind: "focus", minutes: 50 },
  { kind: "rest", minutes: 5 },
  { kind: "rest", minutes: 15 },
];

export const TIMER_LABEL: Record<TimerKind, string> = { focus: "Focus", rest: "Break" };
/** Focus is the app's working colour; a break is deliberately calmer. */
export const TIMER_COLOR: Record<TimerKind, string> = { focus: "#F5A524", rest: "#34D399" };

type Listener = () => void;

class FocusTimerStore {
  kind: TimerKind = "focus";
  /** null when nothing is running. */
  private endsAt: number | null = null;
  /** Set while paused, so resuming does not lose the time left. */
  private pausedRemaining: number | null = null;
  /** How long the current run was asked for, for the progress bar. */
  private total = 0;

  private finish: number | null = null;
  private listeners = new Set<Listener>();

  /** Fired when a run ends on its own, so the island can come back. */
  onFinished: ((kind: TimerKind) => void) | null = null;

  subscribe(fn: Listener): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private notify() {
    for (const fn of this.listeners) fn();
  }

  get isRunning(): boolean {
    return this.endsAt != null;
  }
  get isPaused(): boolean {
    return this.pausedRemaining != null;
  }
  get isActive(): boolean {
    return this.isRunning || this.isPaused;
  }

  /** Seconds left, never negative. Safe to call every frame. */
  get remaining(): number {
    if (this.pausedRemaining != null) return this.pausedRemaining;
    if (this.endsAt == null) return 0;
    return Math.max(0, (this.endsAt - performance.now()) / 1000);
  }

  /** 0 at the start, 1 when it is done. */
  get progress(): number {
    if (this.total <= 0) return 0;
    return Math.min(Math.max(1 - this.remaining / this.total, 0), 1);
  }

  /** `m:ss`, or `h:mm:ss` once there is an hour to show. */
  get clock(): string {
    const t = Math.ceil(this.remaining);
    const h = Math.floor(t / 3600);
    const m = Math.floor((t % 3600) / 60);
    const s = t % 60;
    const pad = (n: number) => String(n).padStart(2, "0");
    return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
  }

  start(kind: TimerKind, minutes: number) {
    this.startSeconds(kind, minutes * 60);
  }

  startSeconds(kind: TimerKind, seconds: number) {
    if (seconds <= 0) return;
    this.kind = kind;
    this.total = seconds;
    this.pausedRemaining = null;
    this.endsAt = performance.now() + seconds * 1000;
    this.arm(seconds);
    Sound.play("blip");
    this.notify();
  }

  pause() {
    if (this.endsAt == null) return;
    this.pausedRemaining = Math.max(0, (this.endsAt - performance.now()) / 1000);
    this.endsAt = null;
    this.cancel();
    this.notify();
  }

  resume() {
    const left = this.pausedRemaining;
    if (left == null || left <= 0) return;
    this.pausedRemaining = null;
    this.endsAt = performance.now() + left * 1000;
    this.arm(left);
    this.notify();
  }

  stop() {
    this.cancel();
    this.endsAt = null;
    this.pausedRemaining = null;
    this.total = 0;
    this.notify();
  }

  /** Adds a minute to whatever is running — the "just a bit more" button. */
  extend(seconds = 60) {
    if (!this.isActive) return;
    this.total += seconds;
    if (this.pausedRemaining != null) {
      this.pausedRemaining += seconds;
    } else if (this.endsAt != null) {
      this.endsAt += seconds * 1000;
      this.arm(Math.max(0, (this.endsAt - performance.now()) / 1000));
    }
    this.notify();
  }

  private arm(seconds: number) {
    this.cancel();
    this.finish = window.setTimeout(() => {
      this.finish = null;
      const ended = this.kind;
      this.endsAt = null;
      this.pausedRemaining = null;
      this.total = 0;
      Sound.play("finish");
      this.notify();
      this.onFinished?.(ended);
    }, seconds * 1000);
  }

  private cancel() {
    if (this.finish != null) window.clearTimeout(this.finish);
    this.finish = null;
  }
}

export const FocusTimer = new FocusTimerStore();
