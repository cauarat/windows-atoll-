// The Windows island's "Always visible" preference, checked against the clock.
//
// The island state machine is the one place that decides whether Mochi is on
// screen at all, and the preference is a single flag threaded through three of
// its timers. What it must not do is as important as what it must: the master
// switch has to go on clearing the screen, and with the preference off the
// one-minute fold has to survive untouched.
//
// Run by scripts/test-island-always-visible.sh. The Swift machine has no such
// preference — there is a notch to retract into on a Mac — so this one has no
// parity half.

import { IslandStateMachine, type FsmState } from "../windows/src/island/fsm.ts";

// ── A clock we own ────────────────────────────────────────────────────────────
//
// The machine reaches for `window.setTimeout`, so the test supplies a window
// whose timers fire when it says. Waiting out a real minute sixty times over is
// not a suite anybody runs.

let now = 0;
let seq = 0;
const timers = new Map<number, { at: number; fn: () => void }>();

(globalThis as unknown as { window: unknown }).window = {
  setTimeout(fn: () => void, ms: number) {
    const id = ++seq;
    timers.set(id, { at: now + ms, fn });
    return id;
  },
  clearTimeout(id: number) {
    timers.delete(id);
  },
};

/** Runs the clock forward, firing every timer that falls due, in order. */
function advance(ms: number) {
  const end = now + ms;
  for (;;) {
    let next: number | null = null;
    for (const [id, t] of timers) {
      if (t.at <= end && (next === null || t.at < timers.get(next)!.at)) next = id;
    }
    if (next === null) break;
    const t = timers.get(next)!;
    timers.delete(next);
    now = t.at;
    t.fn();
  }
  now = end;
}

/**
 * A machine wired the way island.ts wires it.
 *
 * The handler matters: entering `petit` with nobody on the island is what arms
 * the fold, and it is the page that says so. A bare machine never folds at all,
 * and a test on one would pass whatever this preference did.
 */
function machine(): IslandStateMachine {
  const m = new IslandStateMachine();
  m.onTransition = (_from, to) => {
    if (to === "petit" && !m.pointerInside) m.mouseLeft();
  };
  return m;
}

/** Launched, greeted and settled — where the island spends its life. */
function resting(alwaysVisible: boolean): IslandStateMachine {
  const m = machine();
  m.alwaysVisible = alwaysVisible;
  m.launch();
  m.greetComplete();
  advance(1_000);
  return m;
}

const A_MINUTE = 61 * 1_000;
const A_LONG_WHILE = 10 * 60 * 1_000;

let failures = 0;
function is(m: IslandStateMachine, want: FsmState, what: string) {
  const ok = m.state === want;
  console.log(`  ${ok ? "✓" : "✗"} ${what}${ok ? "" : ` — got ${m.state}, wanted ${want}`}`);
  if (!ok) failures++;
}

// ── On ────────────────────────────────────────────────────────────────────────

console.log("\nAlways visible: the compact bar stays in its corner");
{
  const m = resting(true);
  is(m, "petit", "the greeting settles on the compact bar");
  advance(A_MINUTE);
  is(m, "petit", "the minute that used to fold it away passes");
  advance(A_LONG_WHILE);
  is(m, "petit", "and ten more");
}
{
  const m = resting(true);
  m.forceHome();
  is(m, "home", "a notification opens the panel");
  advance(20 * 1_000);
  is(m, "petit", "it folds back to the bar on its own");
  advance(A_LONG_WHILE);
  is(m, "petit", "and the bar stays");
}
{
  const m = resting(true);
  m.mouseEntered();
  is(m, "home", "hovering the bar opens the panel");
  m.mouseLeft();
  advance(500);
  is(m, "petit", "leaving it returns to the bar, not to nothing");
  advance(A_LONG_WHILE);
  is(m, "petit", "which stays");
}

console.log("\nThe master switch still clears the screen");
{
  const m = resting(true);
  m.forceHidden();
  is(m, "hidden", "switching Coucou off hides the island");
  advance(A_LONG_WHILE);
  is(m, "hidden", "and nothing brings it back on its own");
  m.reveal();
  is(m, "petit", "switching it back on returns the bar");
  advance(A_LONG_WHILE);
  is(m, "petit", "for good");
}

// ── Off ───────────────────────────────────────────────────────────────────────

console.log("\nOff, the fold is exactly what it was");
{
  const m = resting(false);
  is(m, "petit", "the greeting settles on the compact bar");
  advance(A_MINUTE);
  is(m, "hidden", "and the minute folds it into the edge");
}
{
  const m = resting(false);
  advance(A_MINUTE);
  m.mouseEntered();
  is(m, "home", "hovering the wake strip opens the panel");
  m.mouseLeft();
  advance(500);
  is(m, "hidden", "and a hover that opened from nothing returns to nothing");
}

// ── Flipping it ───────────────────────────────────────────────────────────────

console.log("\nFlipping the preference settles whatever is on screen");
{
  const m = resting(false);
  advance(A_MINUTE);
  is(m, "hidden", "folded away with the preference off");
  m.alwaysVisible = true;
  is(m, "petit", "turning it on brings the bar straight back");
  advance(A_LONG_WHILE);
  is(m, "petit", "and leaves it there");
  m.alwaysVisible = false;
  advance(A_MINUTE);
  is(m, "hidden", "turning it off lets the minute run again");
}
{
  // The reason `launched` exists: at boot the machine sits in `hidden` because
  // it has not started, not because it folded. Waking it there put a compact
  // bar on screen for the frame before the greeting opened over it.
  const m = machine();
  m.alwaysVisible = true;
  is(m, "hidden", "before launch the preference moves nothing");
  m.launch();
  is(m, "coucou", "and launch still opens on the greeting");
}

console.log(failures === 0 ? "\nAll good.\n" : `\n${failures} failing.\n`);
process.exit(failures === 0 ? 0 : 1);
