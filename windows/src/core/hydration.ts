// Hydration: the rules, with no UI and no clock of their own.
//
// The twin of NotchBuddy/Sources/App/Hydration.swift, kept by hand:
// scripts/test-hydration.sh runs one script through both and compares. The
// numbers are a product heuristic anchored on public reference intakes (EFSA,
// the US National Academies, NHMRC) — a starting estimate for a healthy adult,
// never a prescription. `hydrationBlock` lists who gets no number.
//
// Moments are epoch milliseconds; days are read in the machine's own time zone.

// ── Answers ─────────────────────────────────────────────────────────────────

export type HydrationAge = "under18" | "from18to39" | "from40to64" | "over65" | "skipped";
export type HydrationReference = "female" | "male" | "skipped";
export type HydrationWeight = "under55" | "from55to85" | "over85" | "skipped";
export type HydrationActivity = "still" | "light" | "moderate" | "intense";
export type HydrationSweat = "little" | "some" | "lots";
export type HydrationClimate = "mild" | "hot" | "intenseHeat";
export type HydrationPregnancy = "no" | "pregnant" | "breastfeeding" | "skipped";
export type HydrationHealth = "none" | "organs" | "medication" | "guidance" | "other" | "skipped";

export interface HydrationAnswers {
  age?: HydrationAge;
  reference?: HydrationReference;
  weight?: HydrationWeight;
  activity?: HydrationActivity;
  sweat?: HydrationSweat;
  climate?: HydrationClimate;
  pregnancy?: HydrationPregnancy;
  health?: HydrationHealth;
}

// ── Estimate ────────────────────────────────────────────────────────────────

/** Why the app gives no automatic number. */
export type HydrationBlock =
  | "minor"
  | "pregnant" | "breastfeeding" | "pregnancySkipped"
  | "organs" | "medication" | "guidance" | "otherCondition" | "healthSkipped";

export type HydrationPart =
  | { kind: "base"; value: HydrationReference }
  | { kind: "weight"; value: HydrationWeight }
  | { kind: "activity"; value: HydrationActivity }
  | { kind: "sweat"; value: HydrationSweat }
  | { kind: "climate"; value: HydrationClimate }
  /** Activity, sweat and climate together never add more than the cap. */
  | { kind: "cap" }
  /** Shown so the person sees age was considered: it changes nothing. */
  | { kind: "over65" };

export interface HydrationLine { part: HydrationPart; ml: number }
export interface HydrationEstimate { totalML: number; lines: HydrationLine[] }

export const HYDRATION = {
  extrasCap: 800,
  minimumML: 1600,
  maximumML: 3400,
  intervals: [45, 60, 90, 120],
  portions: [150, 250, 350, 500],
  /** No reminder in the last hour of the window. */
  tailMinutes: 60,
  lightIntervalMinutes: 180,
  minimumIntervalMinutes: 30,
  snoozeMinutes: 30,
  /** A reminder that came due during sleep shows once, a little after wake. */
  lateGraceMs: 60_000,
  maxRests: 2,
  keptMarks: 28,
} as const;

export function hydrationBlock(a: HydrationAnswers): HydrationBlock | null {
  if (a.age === "under18") return "minor";
  if (a.pregnancy === "pregnant") return "pregnant";
  if (a.pregnancy === "breastfeeding") return "breastfeeding";
  if (a.pregnancy === "skipped") return "pregnancySkipped";
  if (a.health === "organs") return "organs";
  if (a.health === "medication") return "medication";
  if (a.health === "guidance") return "guidance";
  if (a.health === "other") return "otherCondition";
  if (a.health === "skipped") return "healthSkipped";
  return null;
}

export const hydrationBaseML = (r: HydrationReference): number =>
  r === "female" ? 1800 : r === "male" ? 2300 : 2000;
export const hydrationWeightML = (w: HydrationWeight): number =>
  w === "under55" ? -200 : w === "over85" ? 200 : 0;
export const hydrationActivityML = (a: HydrationActivity): number =>
  ({ still: 0, light: 100, moderate: 300, intense: 400 })[a];
export const hydrationSweatML = (s: HydrationSweat): number =>
  ({ little: 0, some: 100, lots: 200 })[s];
export const hydrationClimateML = (c: HydrationClimate): number =>
  ({ mild: 0, hot: 100, intenseHeat: 200 })[c];

/** The estimate for answers that are not blocked. An unanswered question
 *  counts as "no adjustment", so a half-filled form still gives a number. */
export function hydrationEstimate(a: HydrationAnswers): HydrationEstimate {
  const reference = a.reference ?? "skipped";
  const lines: HydrationLine[] = [{ part: { kind: "base", value: reference }, ml: hydrationBaseML(reference) }];
  let total = hydrationBaseML(reference);

  if (a.weight && hydrationWeightML(a.weight) !== 0) {
    lines.push({ part: { kind: "weight", value: a.weight }, ml: hydrationWeightML(a.weight) });
    total += hydrationWeightML(a.weight);
  }

  let extras = 0;
  if (a.activity && hydrationActivityML(a.activity) !== 0) {
    lines.push({ part: { kind: "activity", value: a.activity }, ml: hydrationActivityML(a.activity) });
    extras += hydrationActivityML(a.activity);
  }
  if (a.sweat && hydrationSweatML(a.sweat) !== 0) {
    lines.push({ part: { kind: "sweat", value: a.sweat }, ml: hydrationSweatML(a.sweat) });
    extras += hydrationSweatML(a.sweat);
  }
  if (a.climate && hydrationClimateML(a.climate) !== 0) {
    lines.push({ part: { kind: "climate", value: a.climate }, ml: hydrationClimateML(a.climate) });
    extras += hydrationClimateML(a.climate);
  }
  if (extras > HYDRATION.extrasCap) {
    lines.push({ part: { kind: "cap" }, ml: HYDRATION.extrasCap - extras });
    extras = HYDRATION.extrasCap;
  }
  total += extras;

  if (a.age === "over65") lines.push({ part: { kind: "over65" }, ml: 0 });

  const rounded = Math.round(total / 100) * 100;
  return { totalML: Math.min(HYDRATION.maximumML, Math.max(HYDRATION.minimumML, rounded)), lines };
}

// ── Goal ────────────────────────────────────────────────────────────────────

/** estimated: from the questions, celebrated when reached. target / limit:
 *  typed by the person, to reach or not to pass. none: log only. */
export type HydrationGoalKind = "estimated" | "target" | "limit" | "none";
export interface HydrationGoal { kind: HydrationGoalKind; ml: number }
export const HYDRATION_GOAL_UNSET: HydrationGoal = { kind: "none", ml: 0 };

/** Reminders stop for the day. A limit stops them one serving early, so the app
 *  never nudges someone past the number their doctor gave them. */
export function goalRemindersDone(goal: HydrationGoal, totalML: number, portionML: number): boolean {
  if (goal.kind === "estimated" || goal.kind === "target") return goal.ml > 0 && totalML >= goal.ml;
  if (goal.kind === "limit") return goal.ml > 0 && totalML + portionML > goal.ml;
  return false;
}

/** The glass is full and Mochi celebrates. Only an estimate is celebrated. */
export function goalCelebrates(goal: HydrationGoal, totalML: number): boolean {
  return goal.kind === "estimated" && goal.ml > 0 && totalML >= goal.ml;
}

/** The day counts for the streak. With a manual goal, logging is enough. */
export function goalCountsForStreak(goal: HydrationGoal, totalML: number, entries: number): boolean {
  if (goal.kind === "estimated") return goal.ml > 0 && totalML >= goal.ml;
  return entries > 0;
}

/** 0…1 for the glass. */
export function goalLevel(goal: HydrationGoal, totalML: number): number {
  if (goal.ml <= 0) return totalML > 0 ? 0.5 : 0;
  return Math.min(1, Math.max(0, totalML / goal.ml));
}

// ── Day and log ─────────────────────────────────────────────────────────────

export interface HydrationEntry { id: string; ml: number; at: number }

const MINUTE = 60_000;
const startOfDay = (ms: number): Date => {
  const d = new Date(ms);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
};
const pad = (n: number, width = 2): string => String(n).padStart(width, "0");

/** The hydration day a moment belongs to starts when the person's online
 *  window starts, not at midnight: a glass at 00:30 belongs to "yesterday". */
export function hydrationDayStart(at: number, windowStart: number): number {
  const midnight = startOfDay(at);
  const todayStart = midnight.getTime() + windowStart * MINUTE;
  if (at >= todayStart) return todayStart;
  const yesterday = new Date(midnight.getFullYear(), midnight.getMonth(), midnight.getDate() - 1);
  return yesterday.getTime() + windowStart * MINUTE;
}

export function hydrationDayKeyOf(dayStart: number): string {
  const d = new Date(dayStart);
  return `${pad(d.getFullYear(), 4)}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export const hydrationDayKey = (at: number, windowStart: number): string =>
  hydrationDayKeyOf(hydrationDayStart(at, windowStart));

export function hydrationKeyDate(key: string): Date | null {
  const parts = key.split("-").map(Number);
  if (parts.length !== 3 || parts.some((n) => !Number.isFinite(n))) return null;
  return new Date(parts[0], parts[1] - 1, parts[2]);
}

export function hydrationKeyOffset(key: string, days: number): string | null {
  const d = hydrationKeyDate(key);
  if (!d) return null;
  return hydrationDayKeyOf(new Date(d.getFullYear(), d.getMonth(), d.getDate() + days).getTime());
}

/** "2026-W47": the ISO week a rest day is granted for. */
export function hydrationWeekKey(key: string): string | null {
  const d = hydrationKeyDate(key);
  if (!d) return null;
  const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const weekday = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - weekday);
  const yearStart = Date.UTC(t.getUTCFullYear(), 0, 1);
  const week = Math.ceil(((t.getTime() - yearStart) / 86_400_000 + 1) / 7);
  return `${pad(t.getUTCFullYear(), 4)}-W${pad(week)}`;
}

// ── Streak ──────────────────────────────────────────────────────────────────

/** frozen: the day counted. rest: it was missed and a rest day covered it. */
export type HydrationMark = "frozen" | "rest";
export type HydrationDot = "frozen" | "rest" | "missed" | "today" | "future";

export interface HydrationStreak {
  days: number;
  lastDay: string | null;
  rests: number;
  lastGrantWeek: string | null;
  marks: Record<string, HydrationMark>;
}

export const newHydrationStreak = (): HydrationStreak =>
  ({ days: 0, lastDay: null, rests: 0, lastGrantWeek: null, marks: {} });

/** Run at the start of a day (and at launch): grants the week's rest day and
 *  settles the days missed since the streak last moved. A missed day spends a
 *  rest day; with none left the count starts over — quietly. */
export function streakSettle(s: HydrationStreak, today: string): void {
  const week = hydrationWeekKey(today);
  if (week && week !== s.lastGrantWeek) {
    s.lastGrantWeek = week;
    s.rests = Math.min(HYDRATION.maxRests, s.rests + 1);
  }
  if (s.lastDay && s.lastDay < today) {
    let day = hydrationKeyOffset(s.lastDay, 1);
    let guard = 0;
    while (day && day < today && guard < 400) {
      guard++;
      if (!s.marks[day]) {
        if (s.rests > 0) {
          s.rests--;
          s.marks[day] = "rest";
        } else {
          s.days = 0;
          s.lastDay = null;
          break;
        }
      }
      day = hydrationKeyOffset(day, 1);
    }
  }
  const oldest = hydrationKeyOffset(today, -HYDRATION.keptMarks);
  if (oldest) {
    for (const key of Object.keys(s.marks)) if (key < oldest) delete s.marks[key];
  }
}

/** The day counted. Safe to call again for the same day. */
export function streakFreeze(s: HydrationStreak, today: string): void {
  if (s.marks[today] === "frozen") return;
  s.marks[today] = "frozen";
  s.days++;
  s.lastDay = today;
}

/** Undo took the day back under the goal. */
export function streakUnfreeze(s: HydrationStreak, today: string): void {
  if (s.marks[today] !== "frozen") return;
  delete s.marks[today];
  s.days = Math.max(0, s.days - 1);
  const earlier = Object.keys(s.marks).filter((k) => s.marks[k] === "frozen" && k < today).sort();
  s.lastDay = earlier.length ? earlier[earlier.length - 1] : null;
}

/** Monday…Sunday of the week `today` is in. */
export function streakWeek(s: HydrationStreak, today: string): HydrationDot[] {
  const date = hydrationKeyDate(today);
  if (!date) return [];
  const fromMonday = (date.getDay() + 6) % 7;
  const dots: HydrationDot[] = [];
  for (let i = 0; i < 7; i++) {
    const offset = i - fromMonday;
    const key = hydrationKeyOffset(today, offset);
    const mark = key ? s.marks[key] : undefined;
    if (mark) dots.push(mark === "frozen" ? "frozen" : "rest");
    else if (offset === 0) dots.push("today");
    else dots.push(offset > 0 ? "future" : "missed");
  }
  return dots;
}

// ── Reminders ───────────────────────────────────────────────────────────────

export type HydrationAfterGoal = "stop" | "light";

export interface HydrationSettings {
  enabled: boolean;
  /** "I'm online from … to …", minutes since midnight. */
  windowStart: number;
  windowEnd: number;
  intervalMinutes: number;
  quietEnabled: boolean;
  quietStart: number;
  quietEnd: number;
  holdDuringFocus: boolean;
  afterGoal: HydrationAfterGoal;
  streakEnabled: boolean;
  portionML: number;
}

export const defaultHydrationSettings = (): HydrationSettings => ({
  enabled: true,
  windowStart: 8 * 60,
  windowEnd: 22 * 60,
  intervalMinutes: 90,
  quietEnabled: false,
  quietStart: 12 * 60,
  quietEnd: 13 * 60 + 30,
  holdDuringFocus: true,
  afterGoal: "stop",
  streakEnabled: true,
  portionML: 250,
});

export function hydrationWindowLength(s: HydrationSettings): number {
  const length = s.windowEnd - s.windowStart;
  return length > 0 ? length : length + 24 * 60;
}

export type HydrationPause = { kind: "none" } | { kind: "until"; at: number } | { kind: "indefinitely" };

export interface HydrationSchedule {
  pause: HydrationPause;
  /** The day key "today is hot / I moved more" applies to. */
  hotDay: string | null;
  lastLogAt: number | null;
  lastReminderAt: number | null;
  snoozedUntil: number | null;
  /** Reminders shown since the last log or answer. */
  ignored: number;
}

export const newHydrationSchedule = (): HydrationSchedule =>
  ({ pause: { kind: "none" }, hotDay: null, lastLogAt: null, lastReminderAt: null, snoozedUntil: null, ignored: 0 });

/** Minutes between reminders, or null when the day's reminders are over. */
export function hydrationInterval(s: HydrationSettings, hot: boolean, ignored: number, goalDone: boolean): number | null {
  if (goalDone) return s.afterGoal === "light" ? HYDRATION.lightIntervalMinutes : null;
  let minutes = s.intervalMinutes;
  if (hot) minutes *= 0.75;
  if (ignored >= 3) minutes *= 1.5;
  const rounded = Math.round(minutes / 5) * 5;
  return Math.max(HYDRATION.minimumIntervalMinutes, rounded);
}

const minuteOfDay = (at: number): number => {
  const d = new Date(at);
  return d.getHours() * 60 + d.getMinutes();
};

/** The end of the quiet hours `at` falls in, or null when it is outside them. */
export function hydrationQuietEnd(at: number, s: HydrationSettings): number | null {
  if (!s.quietEnabled || s.quietStart === s.quietEnd) return null;
  const m = minuteOfDay(at);
  const midnight = startOfDay(at);
  if (s.quietStart < s.quietEnd) {
    if (m < s.quietStart || m >= s.quietEnd) return null;
    return midnight.getTime() + s.quietEnd * MINUTE;
  }
  // Quiet hours cross midnight.
  if (m >= s.quietStart) {
    const tomorrow = new Date(midnight.getFullYear(), midnight.getMonth(), midnight.getDate() + 1);
    return tomorrow.getTime() + s.quietEnd * MINUTE;
  }
  if (m < s.quietEnd) return midnight.getTime() + s.quietEnd * MINUTE;
  return null;
}

/** When the next reminder is due, on the wall clock. One deadline, not a
 *  ticker: the caller arms a single timer for it and recomputes on wake, on
 *  every log and on every settings change. */
export function hydrationNext(
  now: number,
  settings: HydrationSettings,
  schedule: HydrationSchedule,
  goalDoneToday: boolean,
): number | null {
  if (!settings.enabled) return null;
  if (schedule.pause.kind === "indefinitely") return null;

  const today = hydrationDayStart(now, settings.windowStart);
  let dayStart = today;
  for (let i = 0; i < 3; i++) {
    const isToday = dayStart === today;
    const key = hydrationDayKeyOf(dayStart);
    const minutes = hydrationInterval(
      settings,
      schedule.hotDay === key,
      isToday ? schedule.ignored : 0,
      isToday && goalDoneToday,
    );
    if (minutes !== null) {
      const end = dayStart + hydrationWindowLength(settings) * MINUTE;
      const last = end - HYDRATION.tailMinutes * MINUTE;

      let anchor = dayStart;
      for (const moment of [schedule.lastLogAt, schedule.lastReminderAt]) {
        if (moment !== null && moment > anchor && moment <= now) anchor = moment;
      }
      let due = anchor + minutes * MINUTE;
      if (isToday && schedule.snoozedUntil !== null && schedule.snoozedUntil > now) due = schedule.snoozedUntil;
      if (due < now) due = now + HYDRATION.lateGraceMs;
      if (schedule.pause.kind === "until" && schedule.pause.at > due) due = schedule.pause.at;
      const quietEnd = hydrationQuietEnd(due, settings);
      if (quietEnd !== null) due = quietEnd;
      if (due <= last) return due;
    }
    const d = new Date(dayStart);
    dayStart = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1, d.getHours(), d.getMinutes()).getTime();
  }
  return null;
}

/** Where a day's reminders would fall if nothing were logged: the row of dots
 *  in Settings. Minutes since midnight, past 1440 when the window crosses it. */
export function hydrationTimeline(s: HydrationSettings, hot: boolean): number[] {
  const step = hydrationInterval(s, hot, 0, false);
  if (step === null) return [];
  const start = s.windowStart;
  const last = start + hydrationWindowLength(s) - HYDRATION.tailMinutes;
  let quietStart = s.quietStart;
  let quietEnd = s.quietEnd;
  if (quietEnd <= quietStart) quietEnd += 24 * 60;
  if (quietEnd <= start) { quietStart += 24 * 60; quietEnd += 24 * 60; }

  const result: number[] = [];
  let t = start + step;
  while (t <= last && result.length < 64) {
    let due = t;
    if (s.quietEnabled && s.quietStart !== s.quietEnd && due >= quietStart && due < quietEnd) due = quietEnd;
    if (due <= last) result.push(due);
    t = due + step;
  }
  return result;
}

// ── Amounts as text ─────────────────────────────────────────────────────────

/** "850 ml", "1.1 L", "2.25 L": the unit switches at a litre so the counter
 *  never reads "1100 ml"; the separator follows the person's locale. */
export function hydrationAmount(ml: number, decimalSeparator = "."): string {
  if (ml < 1000) return `${ml} ml`;
  const hundredths = Math.round(ml / 10);
  const whole = Math.floor(hundredths / 100);
  const fraction = hundredths % 100;
  if (fraction === 0) return `${whole} L`;
  const digits = fraction % 10 === 0 ? String(fraction / 10) : pad(fraction);
  return `${whole}${decimalSeparator}${digits} L`;
}

/** "08:00" from minutes since midnight. */
export function hydrationClock(minute: number): string {
  const m = ((minute % 1440) + 1440) % 1440;
  return `${pad(Math.floor(m / 60))}:${pad(m % 60)}`;
}
