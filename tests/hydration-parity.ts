// The TypeScript hydration rules, checked against the Swift ones.
//
// Hydration.swift and core/hydration.ts are a hand-kept pair: the same
// estimate, the same streak, the same next reminder. The Swift suite runs a
// script and dumps what it saw; this runs the same script and compares, so a
// number changed on one side is a failing build rather than a different goal
// on Windows.
//
// Run by scripts/test-hydration.sh, which supplies HYDRATION_DUMP and TZ=UTC.

import { readFileSync } from "node:fs";
import {
  HYDRATION_GOAL_UNSET, defaultHydrationSettings, goalCelebrates, goalCountsForStreak, goalLevel,
  goalRemindersDone, hydrationAmount, hydrationBlock, hydrationClock, hydrationDayKey, hydrationEstimate,
  hydrationNext, hydrationTimeline, hydrationWeekKey, newHydrationSchedule, newHydrationStreak,
  streakFreeze, streakSettle, streakUnfreeze, streakWeek,
  type HydrationAnswers, type HydrationGoal, type HydrationSchedule, type HydrationSettings,
} from "../windows/src/core/hydration.ts";

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

/** A moment in November 2026 (the process runs in UTC). */
const nov = (day: number, hour: number, minute = 0): number => new Date(2026, 10, day, hour, minute).getTime();
const stamp = (at: number | null): string => (at === null ? "nil" : String(Math.round(at / 1000)));

// The script. tests/HydrationTests.swift has the same steps, in the same
// order: change one and change the other.
function script(): string[] {
  const lines: string[] = [];
  const add = (name: string, values: string[]) => lines.push([name, ...values].join("\t"));

  const answers: [string, HydrationAnswers][] = [
    ["empty", {}],
    ["female-moderate-hot", { reference: "female", activity: "moderate", climate: "hot" }],
    ["male-everything", { reference: "male", weight: "over85", activity: "intense", sweat: "lots", climate: "intenseHeat" }],
    ["female-light-still", { reference: "female", weight: "under55", activity: "still" }],
    ["over65", { age: "over65", reference: "skipped", sweat: "some" }],
  ];
  for (const [name, a] of answers) {
    const e = hydrationEstimate(a);
    add(`estimate-${name}`, [String(e.totalML), String(e.lines.length), ...e.lines.map((l) => String(l.ml))]);
  }

  const blocked: [string, HydrationAnswers][] = [
    ["none", { age: "from18to39", pregnancy: "no", health: "none" }],
    ["minor", { age: "under18" }],
    ["pregnant", { pregnancy: "pregnant" }],
    ["breastfeeding", { pregnancy: "breastfeeding" }],
    ["pregnancy-skipped", { pregnancy: "skipped" }],
    ["organs", { health: "organs" }],
    ["medication", { health: "medication" }],
    ["guidance", { health: "guidance" }],
    ["other", { health: "other" }],
    ["health-skipped", { health: "skipped" }],
  ];
  for (const [name, a] of blocked) add(`block-${name}`, [hydrationBlock(a) ?? "nil"]);

  const goals: [string, HydrationGoal][] = [
    ["estimated", { kind: "estimated", ml: 2200 }],
    ["target", { kind: "target", ml: 1500 }],
    ["limit", { kind: "limit", ml: 1500 }],
    ["none", HYDRATION_GOAL_UNSET],
  ];
  for (const [name, g] of goals) {
    for (const total of [0, 1300, 1500, 2200, 2450]) {
      add(`goal-${name}-${total}`, [
        goalRemindersDone(g, total, 250) ? "1" : "0",
        goalCelebrates(g, total) ? "1" : "0",
        goalCountsForStreak(g, total, total > 0 ? 1 : 0) ? "1" : "0",
        goalLevel(g, total).toFixed(6),
      ]);
    }
  }

  const moments: [string, number][] = [
    ["morning", nov(19, 9)], ["before-window", nov(19, 6)], ["after-midnight", nov(20, 0, 30)], ["at-start", nov(19, 8)],
  ];
  for (const [name, moment] of moments) add(`day-${name}`, [hydrationDayKey(moment, 8 * 60)]);
  add("week", [hydrationWeekKey("2026-11-19") ?? "nil", hydrationWeekKey("2026-11-23") ?? "nil"]);

  const streak = newHydrationStreak();
  const streakLine = (name: string, today: string) =>
    add(`streak-${name}`, [String(streak.days), streak.lastDay ?? "nil", String(streak.rests), ...streakWeek(streak, today)]);
  streakSettle(streak, "2026-11-16"); streakFreeze(streak, "2026-11-16");
  streakLine("monday", "2026-11-16");
  streakSettle(streak, "2026-11-17"); streakFreeze(streak, "2026-11-17");
  streakSettle(streak, "2026-11-19");
  streakLine("rested", "2026-11-19");
  streakFreeze(streak, "2026-11-19"); streakFreeze(streak, "2026-11-19");
  streakLine("thursday", "2026-11-19");
  streakUnfreeze(streak, "2026-11-19");
  streakLine("undone", "2026-11-19");
  streakFreeze(streak, "2026-11-19");
  streakSettle(streak, "2026-11-21");
  streakLine("reset", "2026-11-21");
  streakFreeze(streak, "2026-11-21");
  streakSettle(streak, "2026-11-23");
  streakSettle(streak, "2026-11-23");
  streakLine("new-week", "2026-11-23");

  const next = (now: number, settings: HydrationSettings = defaultHydrationSettings(),
    schedule: HydrationSchedule = newHydrationSchedule(), done = false) =>
    stamp(hydrationNext(now, settings, schedule, done));

  let s = defaultHydrationSettings();
  let sch = newHydrationSchedule();
  add("next-first", [next(nov(19, 9))]);
  sch.lastLogAt = nov(19, 10, 15);
  add("next-after-log", [next(nov(19, 10, 20), s, sch)]);
  sch.hotDay = "2026-11-19";
  add("next-hot", [next(nov(19, 10, 20), s, sch)]);
  sch.hotDay = "2026-11-18";
  add("next-hot-expired", [next(nov(19, 10, 20), s, sch)]);
  sch.hotDay = null; sch.ignored = 3;
  add("next-ignored", [next(nov(19, 10, 20), s, sch)]);

  sch = newHydrationSchedule(); sch.lastLogAt = nov(19, 10, 45);
  s.quietEnabled = true;
  add("next-quiet", [next(nov(19, 10, 50), s, sch)]);
  s.quietEnabled = false;
  sch.pause = { kind: "until", at: nov(19, 15) };
  add("next-paused-until", [next(nov(19, 10, 50), s, sch)]);
  sch.pause = { kind: "indefinitely" };
  add("next-paused", [next(nov(19, 10, 50), s, sch)]);

  sch = newHydrationSchedule(); sch.lastReminderAt = nov(19, 12); sch.snoozedUntil = nov(19, 12, 30);
  add("next-snoozed", [next(nov(19, 12, 1), defaultHydrationSettings(), sch)]);
  sch = newHydrationSchedule(); sch.lastLogAt = nov(19, 9);
  add("next-late", [next(nov(19, 14), defaultHydrationSettings(), sch)]);
  sch.lastLogAt = nov(19, 14);
  add("next-done-stop", [next(nov(19, 15), defaultHydrationSettings(), sch, true)]);
  s.afterGoal = "light"; sch.lastLogAt = nov(19, 15);
  add("next-done-light", [next(nov(19, 15, 5), s, sch, true)]);
  s.afterGoal = "stop"; sch.lastLogAt = nov(19, 20, 30);
  add("next-tail", [next(nov(19, 20, 31), s, sch)]);
  add("next-before-window", [next(nov(19, 6))]);

  s = defaultHydrationSettings(); s.windowStart = 20 * 60; s.windowEnd = 4 * 60;
  sch = newHydrationSchedule(); sch.lastLogAt = nov(19, 22, 30);
  add("next-night-window", [next(nov(19, 23), s, sch)]);
  s = defaultHydrationSettings(); s.windowEnd = 2 * 60; s.quietEnabled = true; s.quietStart = 23 * 60; s.quietEnd = 30;
  sch = newHydrationSchedule(); sch.lastLogAt = nov(19, 21, 45);
  add("next-night-quiet", [next(nov(19, 21, 50), s, sch)]);
  s = defaultHydrationSettings(); s.enabled = false;
  add("next-off", [next(nov(19, 9), s)]);

  s = defaultHydrationSettings();
  add("timeline", hydrationTimeline(s, false).map(String));
  add("timeline-hot", hydrationTimeline(s, true).map(String));
  s.quietEnabled = true;
  add("timeline-quiet", hydrationTimeline(s, false).map(String));
  s.intervalMinutes = 45;
  add("timeline-45", hydrationTimeline(s, false).map(String));

  add("amounts", [0, 850, 1000, 1100, 1250, 2050, 2200, 3400].map((ml) => hydrationAmount(ml, ",")));
  add("clock", [0, 480, 810, 1320, 1470].map(hydrationClock));
  return lines;
}

console.log("Hydration parity");
const swift = readFileSync(process.env.HYDRATION_DUMP!, "utf8").trim().split("\n");
const mine = script();
check(swift.length === mine.length, `both sides ran ${mine.length} steps (Swift ran ${swift.length})`);
let differing = 0;
for (let i = 0; i < Math.max(swift.length, mine.length); i++) {
  if (swift[i] === mine[i]) continue;
  differing++;
  console.log(`  ✗ ${(mine[i] ?? swift[i] ?? "").split("\t")[0]}\n      swift: ${swift[i] ?? "(missing)"}\n      ts:    ${mine[i] ?? "(missing)"}`);
}
check(differing === 0, "every step gives the same answer on both platforms");
check(mine.some((l) => l.startsWith("next-night-quiet\t") && !l.endsWith("nil")), "the script reached the scheduler's edge cases");

console.log("");
if (failures > 0) {
  console.log(`${failures} failed`);
  process.exit(1);
}
console.log("Hydration parity passed");
