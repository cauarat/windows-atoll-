// Where the island sits on screen, and what that means inside the window.
//
// Rust places the 720×320 window against the chosen edge of the display (see
// island.rs); this decides where the island is drawn inside it, which way it
// grows, and which corners are square. The two halves have to agree: the rect
// pushed back to Rust is what decides click-through.

import { PANEL_H, PANEL_W } from "./layout";

export type IslandPosition =
  | "top-left"
  | "top-centre"
  | "top-right"
  | "bottom-left"
  | "bottom-centre"
  | "bottom-right";

/** Next to the clock, where the notifications already are. */
export const DEFAULT_POSITION: IslandPosition = "bottom-right";

export const POSITIONS: ReadonlyArray<readonly [IslandPosition, string]> = [
  ["top-left", "Top left"],
  ["top-centre", "Top centre"],
  ["top-right", "Top right"],
  ["bottom-left", "Bottom left"],
  ["bottom-centre", "Bottom centre"],
  ["bottom-right", "Bottom right"],
];

export type Edge = "top" | "bottom";
export type Align = "left" | "centre" | "right";

/** Mirrors `island::parse_position`: anything unknown falls back to the default. */
export function edgeOf(p: string): Edge {
  return p.startsWith("top-") ? "top" : "bottom";
}

export function alignOf(p: string): Align {
  if (p.endsWith("-left")) return "left";
  // Both spellings, so a hand-edited settings.json still works.
  if (p.endsWith("-centre") || p.endsWith("-center")) return "centre";
  return "right";
}

/** Island x inside the window, for an island `w` wide. */
export function islandX(p: string, w: number): number {
  switch (alignOf(p)) {
    case "left":
      return 0;
    case "centre":
      return (PANEL_W - w) / 2;
    case "right":
      return PANEL_W - w;
  }
}

/**
 * Island y inside the window, for an island `h` tall.
 *
 * At the bottom this is rewritten on every animation frame as `h` changes, which
 * is what makes the island grow upward out of the edge and retract back into it.
 */
export function islandY(p: string, h: number): number {
  return edgeOf(p) === "top" ? 0 : PANEL_H - h;
}

/** Square against the edge it retracts into, rounded on the other side. */
export function radiusCss(p: string, r: number): string {
  return edgeOf(p) === "top" ? `0 0 ${r}px ${r}px` : `${r}px ${r}px 0 0`;
}
