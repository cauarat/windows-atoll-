// Hydration: today's glasses, the goal, the streak and the one deadline for the
// next reminder — the twin of NotchBuddy/Sources/App/HydrationStore.swift.
//
// The rules are in core/hydration.ts, pure and compared against the Swift ones;
// this is the part that has a clock, a disk and an island to open. A module
// singleton for the reason `FocusTimer` is one: every view is built once and
// kept, so state owned by a view would outlive nothing.
//
// Nothing here leaves the computer. Everything is one JSON value in
// localStorage, and not in settings.json, because two windows read it — the
// island and Settings are the same origin — and `storage` events are what keep
// them in step without a round trip through Rust.
//
// Only the island keeps the deadline. The settings window loads the same store
// to read and write it, but a reminder armed in both would open the island
// twice.

import {
  HYDRATION, HYDRATION_GOAL_UNSET,
  defaultHydrationSettings, goalCelebrates, goalCountsForStreak, goalLevel, goalRemindersDone,
  hydrationDayKey, hydrationDayStart, hydrationKeyOffset, hydrationNext,
  newHydrationSchedule, newHydrationStreak, streakFreeze, streakSettle, streakUnfreeze, streakWeek,
  type HydrationAnswers, type HydrationDot, type HydrationEntry, type HydrationGoal,
  type HydrationSchedule, type HydrationSettings, type HydrationStreak,
} from "./hydration";
import { Sound } from "./sound";
import { State } from "./state";
import { FocusTimer } from "./timer";

/** What the reminder card is saying. Not persisted: a card that was on screen
 *  when the app quit is not on screen when it starts. */
export type HydrationPrompt = "reminder" | "logged" | "snoozed" | "goal";
export type HydrationPauseChoice = "hour" | "tomorrow" | "indefinitely";
/** The scenes `seedForPreview` knows, for dev/hydration-preview. */
export type HydrationScene = "intro" | "empty" | "mid" | "goal" | "paused" | "limit";

interface Persisted {
  v: 1;
  enabled: boolean;
  settings: HydrationSettings;
  goal: HydrationGoal;
  answers: HydrationAnswers | null;
  name: string;
  day: { key: string; entries: HydrationEntry[] };
  streak: HydrationStreak;
  schedule: HydrationSchedule;
  awaiting: boolean;
}

const KEY = "hydration";
/** Written by the island's "Answer the questions"; heard by the settings window. */
const SETUP_KEY = "hydrationSetup";
/** The longest a single timer is trusted across a possible sleep. */
const SLICE_MS = 5 * 60_000;
const MINUTE_MS = 60_000;
const CELEBRATION_MS = 2600;
/** A reminder held back by a focus timer asks again this often. */
const FOCUS_RETRY_MS = 5 * MINUTE_MS;
/** Something is waiting on an answer: water can wait two minutes. */
const BUSY_RETRY_MS = 2 * MINUTE_MS;

const newId = (now: number): string => `${now.toString(36)}-${Math.random().toString(36).slice(2, 8)}`;

class HydrationStore {
  // ── Persisted ───────────────────────────────────────────────────────────────

  enabled = false;
  settings: HydrationSettings = { ...defaultHydrationSettings(), enabled: false };
  goal: HydrationGoal = { ...HYDRATION_GOAL_UNSET };
  answers: HydrationAnswers | null = null;
  name = "";
  day: { key: string; entries: HydrationEntry[] } = { key: "", entries: [] };
  streak: HydrationStreak = newHydrationStreak();
  schedule: HydrationSchedule = newHydrationSchedule();
  /** A reminder was shown and nobody has answered it yet. */
  awaiting = false;

  // ── Transient ───────────────────────────────────────────────────────────────

  prompt: HydrationPrompt | null = null;
  /** True for a couple of seconds after the goal is first reached. */
  celebrating = false;
  /** Counts logs, so the glass knows a drop fell even when the level did not move. */
  pulse = 0;

  /** Set by main.ts: open the island on the reminder. */
  onDue: (() => void) | null = null;
  /** Set by the settings window: the island asked for the questions. */
  onSetupAsked: (() => void) | null = null;

  private nextAt: number | null = null;
  private timer: number | undefined;
  private celebration: number | undefined;
  private listeners = new Set<() => void>();
  /** The JSON last read or written, to tell a real change from an echo. */
  private raw: string | null = null;
  private loaded = false;
  /** Only the island's copy arms the deadline. */
  private scheduling = false;
  /** A preview scene: nothing is read, written or armed. */
  private seeded = false;

  subscribe(fn: () => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private emit() {
    for (const fn of this.listeners) fn();
  }

  // ── Derived ─────────────────────────────────────────────────────────────────

  get total(): number {
    return this.day.entries.reduce((sum, e) => sum + e.ml, 0);
  }
  /** 0…1 for the glass, and for Mochi while he is one. */
  get level(): number {
    return goalLevel(this.goal, this.total);
  }
  /** Reminders are over for the day. */
  get done(): boolean {
    return goalRemindersDone(this.goal, this.total, this.settings.portionML);
  }
  get celebrates(): boolean {
    return goalCelebrates(this.goal, this.total);
  }
  /** When the next reminder is due, in epoch ms, or null when none is. */
  get next(): number | null {
    return this.nextAt;
  }
  get todayKey(): string {
    return this.day.key;
  }
  /** "Today is hot or I moved more" is on, for today. */
  get hot(): boolean {
    return this.day.key !== "" && this.schedule.hotDay === this.day.key;
  }
  get paused(): boolean {
    const p = this.schedule.pause;
    return p.kind === "indefinitely" || (p.kind === "until" && p.at > Date.now());
  }
  /** Which of the three pauses is in force — Settings marks that button. */
  get pauseChoice(): HydrationPauseChoice | null {
    const p = this.schedule.pause;
    if (p.kind === "indefinitely") return "indefinitely";
    if (p.kind !== "until" || p.at <= Date.now()) return null;
    return p.at === this.tomorrowStart(Date.now()) ? "tomorrow" : "hour";
  }
  /** Monday…Sunday of this week. */
  get week(): HydrationDot[] {
    return streakWeek(this.streak, this.day.key);
  }
  /**
   * The settings the deadline is worked out from.
   *
   * "A light nudge every 3 h" is for a goal that was reached. Beside a limit
   * it would be a nudge past the number somebody's doctor gave them, which is
   * the one thing a limit exists to prevent — so a limit always stops.
   */
  private get plan(): HydrationSettings {
    return this.goal.kind === "limit" ? { ...this.settings, afterGoal: "stop" } : this.settings;
  }

  // ── Disk ────────────────────────────────────────────────────────────────────

  private adopt(raw: string | null) {
    let p: Partial<Persisted> = {};
    try {
      const parsed: unknown = raw ? JSON.parse(raw) : null;
      if (parsed && typeof parsed === "object") p = parsed as Partial<Persisted>;
    } catch {
      // Not JSON: start over rather than half-read it.
    }
    const sameDay = (p.day?.key ?? "") === this.day.key;
    this.enabled = p.enabled === true;
    // Field by field over the defaults, so a value written by an older build
    // gains whatever has been added since.
    this.settings = { ...defaultHydrationSettings(), ...(p.settings ?? {}), enabled: this.enabled };
    this.goal = p.goal && typeof p.goal.ml === "number"
      ? { kind: p.goal.kind, ml: p.goal.ml }
      : { ...HYDRATION_GOAL_UNSET };
    this.answers = p.answers ?? null;
    this.name = typeof p.name === "string" ? p.name : "";
    this.day = {
      key: typeof p.day?.key === "string" ? p.day.key : "",
      entries: Array.isArray(p.day?.entries) ? p.day.entries : [],
    };
    const streak = { ...newHydrationStreak(), ...(p.streak ?? {}) };
    this.streak = { ...streak, marks: { ...(streak.marks ?? {}) } };
    this.schedule = { ...newHydrationSchedule(), ...(p.schedule ?? {}) };
    this.awaiting = p.awaiting === true && this.enabled;
    // What the card was saying belonged to the day and the switch it was said
    // under; the other window just changed one of them.
    if (!this.enabled || !sameDay) this.dropPrompt();
  }

  /** Reads what is stored, if it is not what this window last saw. */
  private pull(): boolean {
    if (this.seeded) return false;
    let raw: string | null = null;
    try {
      raw = localStorage.getItem(KEY);
    } catch {
      return false;
    }
    if (raw === this.raw) return false;
    this.raw = raw;
    this.adopt(raw);
    return true;
  }

  private save() {
    if (this.seeded) return;
    const value: Persisted = {
      v: 1, enabled: this.enabled, settings: this.settings, goal: this.goal, answers: this.answers,
      name: this.name, day: this.day, streak: this.streak, schedule: this.schedule, awaiting: this.awaiting,
    };
    this.raw = JSON.stringify(value);
    try {
      localStorage.setItem(KEY, this.raw);
    } catch {
      // Private storage refused: today's glasses last until the window closes.
    }
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /** Once, at boot. The settings window passes "settings" and arms nothing. */
  load(role: "island" | "settings" = "island") {
    if (this.loaded || this.seeded) return;
    this.loaded = true;
    this.scheduling = role === "island";
    this.pull();
    const stored = this.raw !== null;
    let changed = this.roll();
    // The app may have been closed for days: settle what was missed, even on a
    // day that had already been opened once.
    if (!changed && this.settings.streakEnabled && this.day.key !== "") {
      const before = JSON.stringify(this.streak);
      streakSettle(this.streak, this.day.key);
      changed = before !== JSON.stringify(this.streak);
    }
    // Nothing is written for someone who never turned this on.
    if (changed && (stored || this.enabled)) this.save();
    // A reminder that was still waiting when the app closed is still the
    // question: the island opens on it, and the answer has to move it on.
    if (this.awaiting) this.prompt = "reminder";

    window.addEventListener("storage", (e) => this.onStorage(e));
    // A deadline armed before the lid closed is not to be trusted after it
    // opens, and the day may have turned while the machine slept.
    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) this.wake();
    });
    window.addEventListener("focus", () => this.wake());
    this.arm();
  }

  private onStorage(e: StorageEvent) {
    if (this.seeded) return;
    if (e.key === SETUP_KEY) {
      if (e.newValue) this.onSetupAsked?.();
      return;
    }
    // `key` is null when the whole store was cleared.
    if (e.key !== null && e.key !== KEY) return;
    if (!this.pull()) return;
    if (this.roll()) this.save();
    this.arm();
    this.emit();
  }

  /** Reads the clock and the disk again: after a sleep, a focus, a settings
   *  change — and whenever a slice of the deadline runs out. */
  wake() {
    if (!this.loaded || this.seeded) return;
    const pulled = this.pull();
    const rolled = this.roll();
    if (rolled) this.save();
    // With nothing changed and the deadline still ahead, only the timer is
    // renewed. Working the deadline out again would move it: one that is
    // already late is always "a minute from now", so a window that takes
    // focus every half minute would never be reminded at all.
    const standing = !pulled && !rolled && this.nextAt !== null && this.nextAt > Date.now();
    this.arm(standing);
    if (pulled || rolled) this.emit();
  }

  /** Before every action: what the other window wrote, then the day. */
  private begin(): number {
    this.pull();
    const now = Date.now();
    // Saved here, not left to `commit`: an action that finds nothing to do
    // returns without one, and the new day must not be lost with it.
    if (this.roll(now)) this.save();
    return now;
  }

  private commit() {
    this.save();
    this.arm();
    this.emit();
  }

  private dropPrompt() {
    this.prompt = null;
    this.celebrating = false;
    window.clearTimeout(this.celebration);
    this.celebration = undefined;
  }

  /** The start of the hydration day after the one `now` is in. */
  private tomorrowStart(now: number): number {
    const d = new Date(hydrationDayStart(now, this.settings.windowStart));
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1, d.getHours(), d.getMinutes()).getTime();
  }

  /**
   * A new hydration day starts when the online window does. Yesterday's
   * glasses go, the streak settles what was missed, and anything that only
   * made sense "today" — a snooze, an unanswered card — goes too.
   *
   * Entries are kept when they still belong to the day now in force, which is
   * only ever the case when it was the window's start that moved, not the
   * clock: dragging "I'm online" an hour later must not empty the glass.
   */
  private roll(now = Date.now()): boolean {
    const start = this.settings.windowStart;
    const key = hydrationDayKey(now, start);
    if (key === this.day.key) return false;
    this.day = { key, entries: this.day.entries.filter((e) => hydrationDayKey(e.at, start) === key) };
    this.schedule.ignored = 0;
    this.schedule.snoozedUntil = null;
    this.awaiting = false;
    this.dropPrompt();
    if (this.settings.streakEnabled) streakSettle(this.streak, key);
    return true;
  }

  /** Today counts for the streak, or it stopped counting. */
  private settleToday() {
    if (!this.settings.streakEnabled || this.day.key === "") return;
    if (goalCountsForStreak(this.goal, this.total, this.day.entries.length)) streakFreeze(this.streak, this.day.key);
    else streakUnfreeze(this.streak, this.day.key);
  }

  // ── Logging ─────────────────────────────────────────────────────────────────

  log(ml: number = this.settings.portionML) {
    const now = this.begin();
    const before = this.celebrates;
    this.day.entries.push({ id: newId(now), ml, at: now });
    this.schedule.lastLogAt = now;
    this.schedule.ignored = 0;
    this.schedule.snoozedUntil = null;
    this.awaiting = false;
    this.pulse += 1;
    if (this.settings.streakEnabled
        && goalCountsForStreak(this.goal, this.total, this.day.entries.length)) {
      streakFreeze(this.streak, this.day.key);
    }

    if (this.celebrates && !before) {
      // The glass that reached the goal, and only that one: past it the level
      // stays full and nothing celebrates twice.
      this.celebrating = true;
      window.clearTimeout(this.celebration);
      this.celebration = window.setTimeout(() => {
        this.celebration = undefined;
        this.celebrating = false;
        this.emit();
      }, CELEBRATION_MS);
      if (this.prompt !== null) this.prompt = "goal";
      Sound.play("proud");
    } else {
      Sound.play("gulp");
      if (this.prompt === "reminder") this.prompt = "logged";
    }
    this.commit();
  }

  /** Takes back today's last glass. */
  undo() {
    const last = this.day.entries[this.day.entries.length - 1];
    if (last) this.remove(last.id);
  }

  remove(id: string) {
    this.begin();
    const index = this.day.entries.findIndex((e) => e.id === id);
    if (index < 0) return;
    this.day.entries.splice(index, 1);
    const last = this.day.entries[this.day.entries.length - 1];
    this.schedule.lastLogAt = last ? last.at : null;
    if (!goalCountsForStreak(this.goal, this.total, this.day.entries.length)) {
      streakUnfreeze(this.streak, this.day.key);
    }
    // The card goes back to asking, whatever it had moved on to say.
    const asking = this.prompt !== null;
    this.dropPrompt();
    if (asking) this.prompt = "reminder";
    this.commit();
  }

  // ── The reminder card ───────────────────────────────────────────────────────

  /** "Later": back in half an hour. */
  snooze() {
    const now = this.begin();
    this.schedule.snoozedUntil = now + HYDRATION.snoozeMinutes * MINUTE_MS;
    this.schedule.lastReminderAt = now;
    this.awaiting = false;
    this.prompt = "snoozed";
    this.commit();
  }

  unsnooze() {
    this.begin();
    this.schedule.snoozedUntil = null;
    this.awaiting = true;
    this.prompt = "reminder";
    this.commit();
  }

  /** Leaving the card ends what it was saying. A reminder nobody answered
   *  stays a reminder, so the question is still there when the island opens. */
  clearPrompt() {
    if (this.prompt === null || this.prompt === "reminder") return;
    this.dropPrompt();
    this.emit();
  }

  // ── Settings ────────────────────────────────────────────────────────────────

  setEnabled(on: boolean) {
    this.begin();
    if (on === this.enabled) return;
    this.enabled = on;
    this.settings = { ...this.settings, enabled: on };
    if (!on) {
      this.awaiting = false;
      this.dropPrompt();
    }
    this.commit();
  }

  setSettings(patch: Partial<HydrationSettings>) {
    this.begin();
    // `enabled` has one home, the switch: a patch cannot move it.
    this.settings = { ...this.settings, ...patch, enabled: this.enabled };
    // The window's start may be what changed, and it is what a day is cut by.
    this.roll();
    if (patch.streakEnabled === true && this.day.key !== "") {
      streakSettle(this.streak, this.day.key);
      this.settleToday();
    }
    this.commit();
  }

  setGoal(goal: HydrationGoal) {
    this.begin();
    this.goal = { kind: goal.kind, ml: goal.ml };
    // "Today is hot" has no place beside a number that may be a limit.
    if (goal.kind === "limit") this.schedule.hotDay = null;
    this.settleToday();
    this.commit();
  }

  setAnswers(answers: HydrationAnswers | null) {
    this.begin();
    this.answers = answers ? { ...answers } : null;
    this.commit();
  }

  setName(name: string) {
    this.begin();
    this.name = name.trim();
    this.commit();
  }

  setHot(on: boolean) {
    this.begin();
    this.schedule.hotDay = on && this.goal.kind !== "limit" ? this.day.key : null;
    this.commit();
  }

  pause(choice: HydrationPauseChoice) {
    const now = this.begin();
    if (choice === "hour") this.schedule.pause = { kind: "until", at: now + 60 * MINUTE_MS };
    else if (choice === "tomorrow") this.schedule.pause = { kind: "until", at: this.tomorrowStart(now) };
    else this.schedule.pause = { kind: "indefinitely" };
    this.awaiting = false;
    this.commit();
  }

  resume() {
    this.begin();
    this.schedule.pause = { kind: "none" };
    this.commit();
  }

  // ── Setting it up, from the island ──────────────────────────────────────────

  /** Asks the settings window to open the questions. It is created hidden at
   *  launch and never reloaded, so a `storage` event is the only way to reach it. */
  askForSetup() {
    try {
      localStorage.setItem(SETUP_KEY, String(Date.now()));
    } catch {
      // Refused: Settings opens on whatever it was showing.
    }
  }

  // ── The deadline ────────────────────────────────────────────────────────────

  /**
   * Arms the one deadline, replacing any other: the next reminder, or the start
   * of tomorrow when that comes first, so the glass empties on time with
   * nobody watching. A deadline, not a ticker — with the island hidden this
   * costs nothing until a slice runs out.
   *
   * `keep` is for a wake that changed nothing — see `wake`.
   */
  private arm(keep = false) {
    window.clearTimeout(this.timer);
    this.timer = undefined;
    const now = Date.now();
    const pause = this.schedule.pause;
    if (pause.kind === "until" && pause.at <= now) this.schedule.pause = { kind: "none" };
    // `keep`: the deadline stands and only the timer under it is new.
    if (!keep) this.nextAt = this.enabled ? hydrationNext(now, this.plan, this.schedule, this.done) : null;
    if (!this.scheduling || this.seeded || !this.enabled) return;
    const dayTurns = this.tomorrowStart(now) + 1_000;
    if (this.nextAt !== null && this.nextAt <= dayTurns) this.waitUntil(this.nextAt, () => this.due());
    else this.waitUntil(dayTurns, () => this.wake());
  }

  private waitUntil(at: number, then: () => void) {
    const delay = Math.max(0, at - Date.now());
    this.timer = window.setTimeout(() => {
      this.timer = undefined;
      // A slice, not the whole wait: past a sleep the clock is read again.
      if (Date.now() < at) this.wake();
      else then();
    }, Math.min(delay, SLICE_MS));
  }

  private retryIn(ms: number) {
    window.clearTimeout(this.timer);
    this.nextAt = Date.now() + ms;
    this.waitUntil(this.nextAt, () => this.due());
    this.emit();
  }

  private due() {
    const now = this.begin();
    if (!this.enabled) {
      this.arm();
      return;
    }
    // Not in the middle of a focus block, if the person asked for that.
    if (this.settings.holdDuringFocus && FocusTimer.isActive) {
      this.retryIn(FOCUS_RETRY_MS);
      return;
    }
    // Never over a reply half-written, or anything else holding the island.
    if (State.isPinned) {
      this.retryIn(BUSY_RETRY_MS);
      return;
    }
    // The moment may have passed while this waited: the goal reached, a pause
    // set, the window over.
    const planned = hydrationNext(now - 1_000, this.plan, this.schedule, this.done);
    if (planned === null || planned > now + HYDRATION.lateGraceMs + 1_000) {
      this.arm();
      this.emit();
      return;
    }

    if (this.awaiting) this.schedule.ignored += 1;
    this.schedule.lastReminderAt = now;
    this.schedule.snoozedUntil = null;
    this.awaiting = true;
    this.dropPrompt();
    this.prompt = "reminder";
    this.save();
    this.onDue?.();
    this.arm();
    this.emit();
  }

  // ── Preview ─────────────────────────────────────────────────────────────────

  /**
   * Fills the store for looking at the cards without living a day first, and
   * cuts it off from the disk: the dev server is the same origin `tauri dev`
   * runs the real app on, and a preview must not rewrite somebody's real day.
   */
  seedForPreview(scene: HydrationScene, prompt: HydrationPrompt | null = null, nowMs = Date.now()) {
    this.seeded = true;
    window.clearTimeout(this.timer);
    this.timer = undefined;
    this.dropPrompt();
    this.enabled = scene !== "intro";
    this.settings = { ...defaultHydrationSettings(), enabled: this.enabled };
    this.answers = null;
    this.name = "Cauã";
    const key = hydrationDayKey(nowMs, this.settings.windowStart);
    const entry = (ml: number, minutesAgo: number): HydrationEntry =>
      ({ id: newId(nowMs - minutesAgo * MINUTE_MS), ml, at: nowMs - minutesAgo * MINUTE_MS });

    // Five days running, one of them a rest day, and one rest day in hand.
    this.streak = newHydrationStreak();
    for (const offset of [-3, -1]) {
      const day = hydrationKeyOffset(key, offset);
      if (day) this.streak.marks[day] = "frozen";
    }
    const rested = hydrationKeyOffset(key, -2);
    if (rested) this.streak.marks[rested] = "rest";
    this.streak.days = 5;
    this.streak.rests = 1;
    this.streak.lastDay = hydrationKeyOffset(key, -1);

    this.goal = { kind: "estimated", ml: 2200 };
    let entries: HydrationEntry[] = [entry(250, 330), entry(250, 235), entry(350, 100)];
    this.schedule = newHydrationSchedule();
    switch (scene) {
      case "intro":
        this.goal = { ...HYDRATION_GOAL_UNSET };
        this.streak = newHydrationStreak();
        entries = [];
        break;
      case "empty":
        entries = [];
        break;
      case "goal":
        entries = [entry(500, 400), entry(500, 300), entry(500, 200), entry(350, 120), entry(350, 30)];
        streakFreeze(this.streak, key);
        break;
      case "paused":
        this.schedule.pause = { kind: "indefinitely" };
        break;
      case "limit":
        this.goal = { kind: "limit", ml: 1500 };
        entries = [entry(250, 200), entry(250, 90)];
        break;
      case "mid":
        break;
    }
    this.day = { key, entries };
    const last = entries[entries.length - 1];
    this.schedule.lastLogAt = last ? last.at : null;
    this.prompt = prompt;
    this.awaiting = prompt === "reminder";
    this.arm();
    this.emit();
  }
}

export const Hydration = new HydrationStore();
