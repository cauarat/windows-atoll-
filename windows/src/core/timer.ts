// A focus or break countdown — port of FocusTimer.swift.
//
// A module-level singleton rather than state inside the view, for the same
// reason as on the Mac: every view is built once and kept, so a clock owned by
// the timer tab would be rebuilt and a ticker living there would run while you
// were looking at Home. The view reads this; this owns the clock.

import { Sound } from "./sound";

export type TimerKind = "focus" | "rest" | "deep";

/** The three named lengths, in minutes. */
export const TIMER_PRESETS: ReadonlyArray<{ kind: TimerKind; minutes: number }> = [
  { kind: "focus", minutes: 25 },
  { kind: "rest", minutes: 5 },
  { kind: "deep", minutes: 45 },
];

export const TIMER_LABEL: Record<TimerKind, string> =
  { focus: "Focus", rest: "Break", deep: "Deep Work" };
/** Focus is the app's working colour, a break is calmer, deep work is the one
 *  you are not meant to interrupt. */
export const TIMER_COLOR: Record<TimerKind, string> =
  { focus: "#FF9F0A", rest: "#30D158", deep: "#D946EF" };

type Listener = () => void;

class FocusTimerStore {
  kind: TimerKind = "focus";
  /** null when nothing is running. */
  private endsAt: number | null = null;
  /** Set while paused, so resuming does not lose the time left. */
  private pausedRemaining: number | null = null;
  /** How long the current run was asked for, for the progress bar. */
  private total = 0;

  /** What the picker is set to, before anything has started. Kept as three
   *  numbers rather than one total so each tile can be typed into without the
   *  other two drifting. */
  pickerHours = 0;
  pickerMinutes = 25;
  pickerSeconds = 0;
  /** Which preset the picker holds, for Reset and for the colour. */
  pickerKind: TimerKind = "focus";

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

  get pickerTotal(): number {
    return this.pickerHours * 3600 + this.pickerMinutes * 60 + this.pickerSeconds;
  }

  /** Loads a preset into the picker without starting it, so the tiles show what
   *  Start is about to do. */
  load(kind: TimerKind, minutes: number) {
    this.pickerKind = kind;
    this.pickerHours = Math.floor(minutes / 60);
    this.pickerMinutes = minutes % 60;
    this.pickerSeconds = 0;
    this.notify();
  }

  /** Start, from whatever the tiles say. */
  startFromPicker() {
    this.startSeconds(this.pickerKind, this.pickerTotal);
  }

  /** Back to the preset the picker was last loaded with. */
  reset() {
    this.stop();
    const preset = TIMER_PRESETS.find((p) => p.kind === this.pickerKind);
    this.load(this.pickerKind, preset?.minutes ?? 25);
  }

  /** Each tile, clamped to what it can mean. */
  setPicker(part: "hours" | "minutes" | "seconds", value: number) {
    const n = Number.isFinite(value) ? Math.round(value) : 0;
    if (part === "hours") this.pickerHours = Math.min(Math.max(n, 0), 23);
    else if (part === "minutes") this.pickerMinutes = Math.min(Math.max(n, 0), 59);
    else this.pickerSeconds = Math.min(Math.max(n, 0), 59);
    this.notify();
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
