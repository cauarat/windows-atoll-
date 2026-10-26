// What the island's window is at any moment — and nothing about what is drawn
// inside it.
//
// There are three sizes. The panel is the window the open island is drawn in:
// large, transparent, click-through everywhere the island is not. The wake
// strip is the six invisible pixels left behind when the island has retracted
// into the screen edge. The bar is the resting island itself, window and all.
//
// The bar is how an island that never folds away still costs nothing. The
// window shrinks to exactly the compact bar, so Rust parks the 60 Hz cursor
// poll on the same condvar a folded island parks it on; what is left on screen
// is Mochi in its corner rather than six invisible pixels. Hovering it is then
// the DOM's job, because the poll is asleep — `wakeFromDom` in island/island.ts.
//
// Free placement got here first, by another road: dropped out in the open there
// is no edge to retract into, so a floating island has always rested as the bar
// where it was put. `alwaysVisible` makes that the rule everywhere rather than
// the exception out in the middle of the screen.
//
// Mirrored by `island::fold_of` in src-tauri/src/island.rs, which sizes the
// window. The two have to agree: this decides where the page draws the island
// inside the window, that decides how big the window is.

import type { Edge } from "./anchor";
import type { IslandMode } from "./layout";

export type Fold = "panel" | "strip" | "bar";

/**
 * Which of the three the window should be.
 *
 * `hug` and `free` describe the placement — the screen edge the island is
 * pressed against, if any, and whether it was dropped rather than named.
 */
export function foldFor(
  mode: IslandMode,
  alwaysVisible: boolean,
  hug: Edge | null,
  free: boolean,
): Fold {
  // Open, or on its way: the island needs the whole panel to unfold into.
  if (mode === "expanded") return "panel";
  // Never folds away, so the window is the bar it rests as — whichever of the
  // six spots it sits in, and whether or not the master switch has it hidden.
  if (alwaysVisible) return "bar";
  // The compact bar is drawn inside the panel while the fold is still coming:
  // shrinking here would park the poll a minute before the island goes.
  if (mode === "compact") return "panel";
  // Hidden. Against an edge it retracts into it and leaves the wake strip; out
  // in the open there is no edge to retract into, so the bar stays where it was
  // dropped — small enough to park the poll, visible enough to pick up again.
  return free && hug == null ? "bar" : "strip";
}

/**
 * The mode the island *draws* as, which is not always the mode it is in.
 *
 * Hiding means retracting into the screen edge, and out in the open there is no
 * edge to retract into: a free island would fold to nothing in the middle of
 * the screen and leave nobody anything to hover, or to pick up again. So it
 * rests as the compact bar instead, where it was put — in a window `foldFor`
 * has already sized to exactly that bar.
 *
 * `alwaysVisible` needs nothing here: it keeps the machine at `compact`, so
 * what is drawn is the compact bar by the ordinary route.
 */
export function drawModeFor(mode: IslandMode, hug: Edge | null): IslandMode {
  return mode === "hidden" && hug == null ? "compact" : mode;
}
