// The TypeScript welcome and name rules, checked against the Swift ones.
//
// UserIdentity.swift / Onboarding.swift and core/greetingName.ts /
// core/onboarding.ts are a hand-kept pair. The Swift suite dumps every input it
// knows with its answer; this runs the same inputs through the TypeScript and
// compares, so a rule changed on one side is a failing build rather than a
// Windows Mochi that calls you something else.
//
// Run by scripts/test-welcome.sh, which supplies WELCOME_DUMP.

import { readFileSync } from "node:fs";
import {
  cleanUserName, dayPeriod, firstNameFromFullName, greetingName, MAX_TYPED_NAME,
} from "../windows/src/core/greetingName.ts";
import {
  ONBOARDING_STEPS, ONBOARDING_VERSION, onboardingProgress, shouldShowOnboarding,
} from "../windows/src/core/onboarding.ts";

interface Dump {
  periods: { hour: number; period: string }[];
  typed: { input: string; output: string | null }[];
  accounts: { input: string; output: string | null }[];
  names: { typed: string; account: string; output: string | null }[];
  steps: string[];
  progress: { step: string; current: number | null; total: number | null }[];
  gate: { seen: number; enabled: boolean; show: boolean }[];
  version: number;
  maxTyped: number;
}

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};
const show = (s: string | null) => (s === null ? "nil" : JSON.stringify(s));

const path = process.env.WELCOME_DUMP;
if (!path) {
  console.error("WELCOME_DUMP is not set — run scripts/test-welcome.sh");
  process.exit(1);
}
const swift: Dump = JSON.parse(readFileSync(path, "utf8"));

console.log("Parity with Swift");
for (const { hour, period } of swift.periods) {
  const ts = dayPeriod(hour);
  if (ts !== period) check(false, `hour ${hour}: Swift ${period}, TypeScript ${ts}`);
}
check(swift.periods.every(({ hour, period }) => dayPeriod(hour) === period), "the same part of the day for all 24 hours");

for (const { input, output } of swift.typed) {
  const ts = cleanUserName(input);
  check(ts === output, `typed ${JSON.stringify(input)} → ${show(output)}${ts === output ? "" : `, TypeScript ${show(ts)}`}`);
}
for (const { input, output } of swift.accounts) {
  const ts = firstNameFromFullName(input);
  check(ts === output, `account ${JSON.stringify(input)} → ${show(output)}${ts === output ? "" : `, TypeScript ${show(ts)}`}`);
}
check(
  swift.names.every(({ typed, account, output }) => greetingName(typed, account) === output),
  "the typed name and the account's fall back the same way",
);

check(JSON.stringify([...ONBOARDING_STEPS]) === JSON.stringify(swift.steps), `the same seven screens: ${swift.steps.join(", ")}`);
check(
  swift.progress.every(({ step, current, total }) => {
    const ts = onboardingProgress(ONBOARDING_STEPS.indexOf(step as (typeof ONBOARDING_STEPS)[number]));
    return ts === null ? current === null && total === null : ts.current === current && ts.total === total;
  }),
  "the same \"N of 5\" on every screen",
);
check(
  swift.gate.every(({ seen, enabled, show }) => shouldShowOnboarding(seen, enabled) === show),
  "the welcome shows on the same launches",
);
check(ONBOARDING_VERSION === swift.version, `the same welcome version (${swift.version})`);
check(MAX_TYPED_NAME === swift.maxTyped, `the same cap on a typed name (${swift.maxTyped})`);

console.log("");
if (failures > 0) {
  console.log(`${failures} failed.`);
  process.exit(1);
}
console.log("Swift and TypeScript agree.");
