// The window an always-visible island rests in.
//
// "Always visible" (tests/island-always-visible.ts) keeps Mochi on screen; this
// is the half that keeps it cheap. A resting island used to fold into the
// screen edge, and the 240x6 window it left behind is what parked Rust's 60 Hz
// cursor poll. Leave the window at the full 760x620 panel and the poll never
// parks: a visible Mochi would cost, for as long as Coucou runs, what the whole
// feature was built to avoid.
//
// So the window shrinks to the compact bar itself — small, and the island fills
// it. `foldFor` is the decision, and it answers for Rust's `island::fold_of`
// too, which sizes the window from the same two flags.
//
// What is checked here is the three-cornered agreement that makes that work:
// the machine's state, the window the page asks for, and the island the page
// draws inside it. Any two of them agreeing is not enough — a bar-sized window
// with a hidden island in it is an empty black rectangle in the corner, which
// is exactly what free placement shipped.
//
// Run by scripts/test-island-resting-bar.sh. No parity half: the Mac island
// rests in the notch, where there is nothing to shrink.

import { IslandStateMachine } from "../windows/src/island/fsm.ts";
import { asleepFor, drawModeFor, foldFor, type Fold } from "../windows/src/core/fold.ts";
import { METRICS, anchorFor, islandOrigin } from "../windows/src/core/anchor.ts";
import { botPosition, islandSize, type IslandMode } from "../windows/src/core/layout.ts";
import type { Edge } from "../windows/src/core/anchor.ts";

// ── A clock we own ────────────────────────────────────────────────────────────

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

let failures = 0;
function ok(cond: boolean, what: string, got?: string) {
  console.log(`  ${cond ? "✓" : "✗"} ${what}${cond || got == null ? "" : ` — got ${got}`}`);
  if (!cond) failures++;
}
function eq<T>(got: T, want: T, what: string) {
  ok(got === want, what, `${String(got)}, wanted ${String(want)}`);
}

// ── The island as the page sees it ────────────────────────────────────────────
//
// The machine wired the way island.ts wires it, plus the two questions the page
// asks of every frame: which window, and which island inside it.

interface Place {
  /** The screen edge the island is pressed against, null out in the open. */
  hug: Edge | null;
  /** Dropped rather than named. */
  free: boolean;
}

const CORNER: Place = { hug: "bottom", free: false };
const OPEN_FIELD: Place = { hug: null, free: true };

class Page {
  readonly fsm = new IslandStateMachine();
  readonly place: Place;

  constructor(place: Place, alwaysVisible: boolean) {
    this.place = place;
    this.fsm.onTransition = (_from, to) => {
      if (to === "petit" && !this.fsm.pointerInside) this.fsm.mouseLeft();
    };
    this.fsm.alwaysVisible = alwaysVisible;
    this.fsm.launch();
    this.fsm.greetComplete();
    advance(1_000);
  }

  get mode(): IslandMode {
    switch (this.fsm.state) {
      case "hidden":
        return "hidden";
      case "petit":
        return "compact";
      default:
        return "expanded";
    }
  }

  /** The window Rust is asked for. */
  get fold(): Fold {
    return foldFor(this.mode, this.fsm.alwaysVisible, this.place.hug, this.place.free);
  }

  /** The island drawn inside it. */
  get draws(): IslandMode {
    return drawModeFor(this.mode, this.place.hug);
  }

  /** Is Mochi on screen, and how big? */
  get mochi(): { shown: boolean; diameter: number } {
    const { h } = islandSize(this.draws, "overview");
    const p = botPosition(this.draws, "overview", h);
    return { shown: p.opacity > 0, diameter: p.diameter };
  }
}

// ── Resting ───────────────────────────────────────────────────────────────────

console.log("\nAlways visible: the window is the bar, not the panel");
{
  const p = new Page(CORNER, true);
  eq(p.mode, "compact", "the greeting settles on the compact bar");
  eq(p.fold, "bar", "and the window shrinks to that bar");
  eq(p.draws, "compact", "which is what the island draws");
  ok(p.mochi.shown, "with Mochi on it");
  eq(p.mochi.diameter, 20, "at the compact size");
  advance(10 * 60 * 1_000);
  eq(p.fold, "bar", "ten minutes later, still the bar");
}
{
  // The point of shrinking at all: Rust parks the cursor poll on anything that
  // is not the panel, so the bar costs what the wake strip cost.
  const resting = new Page(CORNER, true);
  const folded = new Page(CORNER, false);
  advance(61 * 1_000);
  ok(resting.fold !== "panel", "a resting island has parked the poll");
  ok(folded.fold !== "panel", "and so has a folded one");
  eq(folded.fold, "strip", "which is the wake strip, as it always was");
}
{
  const { w, h } = islandSize("compact", "overview");
  eq(w, METRICS.restW, "the bar the island draws is the width Rust sizes to");
  eq(h, METRICS.restH, "and the height");
}

console.log("\nHovering the bar opens the island, and leaving it puts it back");
{
  const p = new Page(CORNER, true);
  eq(p.fold, "bar", "resting");
  // The window is collapsed, so the cursor poll is parked and this hover came
  // from the DOM — `wakeFromDom` in island.ts, which is the only ear it has.
  p.fsm.mouseEntered();
  eq(p.mode, "expanded", "a hover opens the panel");
  eq(p.fold, "panel", "and the window grows back to hold it");
  eq(p.draws, "expanded", "with the open island in it");
  p.fsm.mouseLeft();
  advance(500);
  eq(p.fold, "bar", "leaving it shrinks back to the bar");
  ok(p.mochi.shown, "Mochi still in the corner");
}
{
  // Growing has to be the same decision from every direction, or the island
  // unfolds inside a window too small to hold it.
  const p = new Page(CORNER, true);
  p.fsm.forceHome();
  eq(p.fold, "panel", "a notification grows the window too");
  advance(20 * 1_000);
  eq(p.fold, "bar", "and it shrinks again when the card has had its minute");
}

// ── The preference off ────────────────────────────────────────────────────────

console.log("\nOff, the window does exactly what it did");
{
  const p = new Page(CORNER, false);
  eq(p.fold, "panel", "a compact bar waiting out its minute sits in the panel");
  advance(61 * 1_000);
  eq(p.mode, "hidden", "the minute folds it into the edge");
  eq(p.fold, "strip", "leaving the wake strip");
  eq(p.draws, "hidden", "and nothing drawn");
  ok(!p.mochi.shown, "no Mochi to see");
}
{
  const p = new Page(CORNER, false);
  advance(61 * 1_000);
  p.fsm.mouseEntered();
  eq(p.fold, "panel", "hovering the strip grows the window");
  p.fsm.mouseLeft();
  advance(500);
  eq(p.fold, "strip", "and a hover that opened from nothing goes back to nothing");
}

// ── Flipping it ───────────────────────────────────────────────────────────────

console.log("\nFlipping the preference resizes the window");
{
  const p = new Page(CORNER, false);
  advance(61 * 1_000);
  eq(p.fold, "strip", "folded away");
  p.fsm.alwaysVisible = true;
  eq(p.fold, "bar", "turning it on brings the bar back — and the window with it");
  ok(p.mochi.shown, "with Mochi on it");
  p.fsm.alwaysVisible = false;
  eq(p.fold, "panel", "turning it off grows the window back to wait out the minute");
  advance(61 * 1_000);
  eq(p.fold, "strip", "which it then does");
}

// ── Dropped out in the open ───────────────────────────────────────────────────
//
// Free placement got to the resting bar first: with no edge to retract into it
// has always stayed as the pill where it was dropped. What it never did was put
// Mochi on that pill — `botPosition` was asked the machine's mode, which says
// hidden, and answered opacity 0. A black bar with nothing in it.

console.log("\nDropped out in the open, the bar is not empty");
{
  const p = new Page(OPEN_FIELD, false);
  advance(61 * 1_000);
  eq(p.mode, "hidden", "the minute still runs with the preference off");
  eq(p.fold, "bar", "but there is no edge to fold into, so the bar stays");
  eq(p.draws, "compact", "drawn as the compact bar");
  ok(p.mochi.shown, "and Mochi is on it");
}
{
  const p = new Page(OPEN_FIELD, true);
  eq(p.fold, "bar", "always visible changes nothing out here");
  ok(p.mochi.shown, "Mochi either way");
}
{
  // Dropped along an edge is a hug, and a hug retracts like any corner does.
  const p = new Page({ hug: "top", free: true }, false);
  advance(61 * 1_000);
  eq(p.fold, "strip", "a drop along an edge still retracts into it");
  ok(!p.mochi.shown, "and takes Mochi with it");
}

// ── The master switch ─────────────────────────────────────────────────────────
//
// Off is off. The window is hidden outright by Rust (`apply_enabled`), so what
// the fold says is moot — but the machine still has to leave `petit`, or
// turning Coucou back on would find it already where it rests and draw nothing.

console.log("\nThe master switch still clears the screen");
{
  const p = new Page(CORNER, true);
  p.fsm.forceHidden();
  eq(p.fsm.state, "hidden", "switching Coucou off hides the island");
  advance(10 * 60 * 1_000);
  eq(p.fsm.state, "hidden", "and nothing brings it back on its own");
  p.fsm.reveal();
  eq(p.fold, "bar", "switching it back on restores the bar");
  ok(p.mochi.shown, "Mochi with it");
}

// ── Where the island sits inside the window ───────────────────────────────────
//
// The bar's 0,0 and the panel's offsets name the same screen pixel, which is
// what lets the window fold without the island appearing to move — and what
// makes using the wrong one of the two a teleport rather than a wobble.
//
// The window origins below are what `island::preset_origin` places, on the
// 1920x1040 work area its own suite uses. Mirrored here on purpose: Rust puts
// the window somewhere and this decides where the island goes inside it, so if
// the pair ever disagrees the island is not where it looks.

console.log("\nThe island does not move on screen when the window folds");
{
  const { restW, restH } = METRICS;
  const { panelW, panelH } = METRICS;
  const AREA_W = 1920;
  const AREA_H = 1040;
  const GAP = 2; // island::BOTTOM_GAP

  // [position, panel window origin, bar window origin]
  const spots: [string, [number, number], [number, number]][] = [
    ["bottom-right", [AREA_W - panelW, AREA_H - panelH - GAP], [AREA_W - restW, AREA_H - restH - GAP]],
    ["bottom-left", [0, AREA_H - panelH - GAP], [0, AREA_H - restH - GAP]],
    ["bottom-centre",
      [(AREA_W - panelW) / 2, AREA_H - panelH - GAP],
      [(AREA_W - restW) / 2, AREA_H - restH - GAP]],
    ["top-right", [AREA_W - panelW, 0], [AREA_W - restW, 0]],
    ["top-left", [0, 0], [0, 0]],
    ["top-centre", [(AREA_W - panelW) / 2, 0], [(AREA_W - restW) / 2, 0]],
  ];

  for (const [position, panelWin, barWin] of spots) {
    const a = anchorFor(position, AREA_W, AREA_H);
    const inPanel = islandOrigin(a, false, restW, restH);
    const inBar = islandOrigin(a, true, restW, restH);
    const sameX = panelWin[0] + inPanel.x === barWin[0] + inBar.x;
    const sameY = panelWin[1] + inPanel.y === barWin[1] + inBar.y;
    ok(sameX && sameY, `${position}: the same screen pixel folded and open`,
       `${panelWin[0] + inPanel.x},${panelWin[1] + inPanel.y} vs ${barWin[0] + inBar.x},${barWin[1] + inBar.y}`);
  }
  ok(islandOrigin(anchorFor("bottom-right", AREA_W, AREA_H), true, restW, restH).x === 0,
     "the bar window is the island, so the island is at its origin");
}

console.log("\nPicking the resting island up grabs it by its own centre");
{
  // `liftOff` hands Rust the resting island's centre in window coordinates, and
  // Rust turns it into a screen point with the window's origin. Measured
  // against the panel from inside a bar-sized window it is out by most of the
  // island's width, and the island jumps that far the moment it comes unstuck
  // — with nothing downstream to catch it, because a drag has no second source
  // of truth about where the island was.
  const { restW, restH } = METRICS;
  const a = anchorFor("bottom-right", 1920, 1040);
  const centre = (windowIsBar: boolean) => {
    const o = islandOrigin(a, windowIsBar, restW, restH);
    return { x: o.x + restW / 2, y: o.y + restH / 2 };
  };
  const bar = centre(true);
  eq(bar.x, restW / 2, "resting as the bar, the centre is the bar's own middle");
  eq(bar.y, restH / 2, "in both axes");
  const panel = centre(false);
  eq(panel.x, METRICS.panelW - restW / 2, "inside the panel it is the anchored corner's middle");
  eq(panel.y, METRICS.panelH - restH / 2, "in both axes");
  ok(panel.x - bar.x === METRICS.panelW - restW,
     "the two differ by a panel less a bar — the jump this is here to stop");
}

// ── Standby and always visible, both on ───────────────────────────────────────
//
// The settings window does not allow it; a hand-edited settings.json does. One
// answer, and the state machine already gave it: always visible keeps the
// island out of `hidden`, so it is never folded away and standby has no fold to
// hold. `PollGate::asleep` says the same on the Rust side.

console.log("\nStandby does not half-deafen an island that never folds");
{
  // `asleepFor` is what `wakeFromDom` and `PollGate::asleep` both read, after
  // the three of them — Rust's input region, the hover and the click — each
  // gave a different answer to a settings.json with both switches on.
  ok(asleepFor(true, false), "folded away with standby on is deaf, as always");
  ok(!asleepFor(true, true), "resting in its corner is not folded, so not deaf");
  ok(!asleepFor(false, true), "and plainly not with standby off");
  ok(!asleepFor(false, false), "nor with neither");
  // The reason it is not: always visible leaves no fold for standby to hold.
  const p = new Page(CORNER, true);
  advance(61 * 1_000);
  eq(p.fold, "bar", "the bar never reaches the fold standby waits for");
  const folded = new Page(CORNER, false);
  advance(61 * 1_000);
  eq(folded.fold, "strip", "which off it does, and standby applies there");
}

// ── The master switch beats the preference ────────────────────────────────────

console.log("\nSwitched off, the window is the smallest one there is");
{
  const p = new Page(CORNER, true);
  p.fsm.forceHidden();
  eq(p.fold, "strip", "not a 288x32 still taking the mouse over the desktop");
  ok(!p.mochi.shown, "and nothing drawn in it");
}

console.log(failures === 0 ? "\nAll good.\n" : `\n${failures} failing.\n`);
process.exit(failures === 0 ? 0 : 1);
