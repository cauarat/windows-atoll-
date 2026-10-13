// The buttons around the island's border — port of IslandEdgeLayout.swift and
// IslandEdgeAction.swift.
//
// Kept free of the DOM so the geometry can be read, and reasoned about, on its
// own. That matters more here than anywhere else in this app: these circles
// decide what the pointer can click on a transparent window covering part of
// the screen, and getting them wrong makes that part of the display unclickable
// — the island pushes their bounds to Rust as its own.
//
// One thing is not the Mac's. There the island hangs off the notch with the
// panel around it on every side, so a button can sit left, right or below it.
// Here the island is docked against a screen edge and aligned to a corner, so a
// side that points off the screen has nowhere to be: `bottom` is read as "the
// side away from the edge the island rests on", and a left or right button is
// mirrored inward when the island is flush against that side of the window.
// The stored side keeps its name either way — it is a contract value.

import type { Align, Edge } from "./anchor";

export type EdgeSide = "left" | "right" | "bottom";

/** One button on the island's border. `action` is a pill id or a built-in. */
export interface EdgeButton {
  action: string;
  side: EdgeSide;
}

export const DIAMETER = 34;
/** Clear air between the island's edge and a button. */
export const GAP = 10;
/** Between two buttons on the same side. */
export const SPACING = 8;

/** How far a run of `count` buttons reaches along its side. */
export function span(count: number): number {
  return count <= 0 ? 0 : count * DIAMETER + (count - 1) * SPACING;
}

/** Where the island sits, which is what decides where a side can be. */
export interface Anchor {
  edge: Edge;
  align: Align;
}

/**
 * The side a button is actually drawn on.
 *
 * A column that would fall outside the window is mirrored to the other side,
 * and both columns merge into one when that happens — two runs at the same x,
 * each numbering itself from zero, would draw every button on top of another.
 */
function effectiveSide(side: EdgeSide, align: Align): EdgeSide {
  if (side === "bottom") return "bottom";
  if (align === "right") return "left";
  if (align === "left") return "right";
  return side;
}

export interface PlacedButton {
  button: EdgeButton;
  /** Centre, in island-local coordinates: origin at the island's top-left. */
  x: number;
  y: number;
}

/**
 * Every button's centre, island-local.
 *
 * Side buttons stack down the island's middle; the row spreads across it. A run
 * longer than the island simply overhangs, which is the normal case rather than
 * an edge case: the island is 32 px tall when it rests and two buttons are 76.
 */
export function layout(
  all: readonly EdgeButton[],
  anchor: Anchor,
  islandW: number,
  islandH: number,
): PlacedButton[] {
  const groups = new Map<EdgeSide, EdgeButton[]>();
  for (const button of all) {
    const side = effectiveSide(button.side, anchor.align);
    const list = groups.get(side);
    if (list) list.push(button);
    else groups.set(side, [button]);
  }

  const out: PlacedButton[] = [];
  const step = DIAMETER + SPACING;
  const reach = GAP + DIAMETER / 2;
  for (const [side, list] of groups) {
    list.forEach((button, index) => {
      const offset = (index - (list.length - 1) / 2) * step;
      if (side === "bottom") {
        // Away from the edge the island rests on, so it is always on screen.
        const y = anchor.edge === "top" ? islandH + reach : -reach;
        out.push({ button, x: islandW / 2 + offset, y });
      } else {
        const x = side === "left" ? -reach : islandW + reach;
        out.push({ button, x, y: islandH / 2 + offset });
      }
    });
  }
  return out;
}

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/**
 * The island plus its buttons, island-local. `(0, 0, w, h)` when there are
 * none, so an island with no ring behaves exactly as it did before there was
 * one.
 */
export function chromeBounds(
  all: readonly EdgeButton[],
  anchor: Anchor,
  islandW: number,
  islandH: number,
): Rect {
  let minX = 0;
  let minY = 0;
  let maxX = islandW;
  let maxY = islandH;
  for (const placed of layout(all, anchor, islandW, islandH)) {
    minX = Math.min(minX, placed.x - DIAMETER / 2);
    minY = Math.min(minY, placed.y - DIAMETER / 2);
    maxX = Math.max(maxX, placed.x + DIAMETER / 2);
    maxY = Math.max(maxY, placed.y + DIAMETER / 2);
  }
  return { x: minX, y: minY, w: maxX - minX, h: maxY - minY };
}

/**
 * The buttons that are actually on screen.
 *
 * They belong to the open island, not to the bar it rests as: around a resting
 * bar they would float against the screen edge with nothing to be attached to.
 * One function rather than a check in each place, because the drawing and the
 * click-through have to agree exactly — a button drawn with no clickable area
 * does nothing, and a clickable area with no button steals clicks from whatever
 * is behind it.
 */
export function visible(all: readonly EdgeButton[], expanded: boolean): readonly EdgeButton[] {
  return expanded ? all : [];
}

/** The one pill that joins the dashboard in the row instead of the column. */
const ROW_PILL = "integration_music";

/**
 * What a fresh install starts with: the message services down the near side,
 * and what you glance at rather than answer — the player and the dashboard —
 * in the row along the island's inner edge.
 *
 * The Mac deals its pills alternately left and right and leaves the dashboard
 * alone underneath. This is the arrangement of the Mac that was being copied
 * from rather than that default, which is also the safer of the two here: the
 * row is the one side that can never be against a screen edge, and a column
 * that can be is mirrored inward by `effectiveSide` anyway.
 *
 * The dashboard is dealt rather than migrated in. The Mac has a migration
 * because a free-standing satellite preceded the ring there; no release of this
 * build has ever carried a ring, and a stored arrangement only exists once
 * somebody edits one, so there is nothing yet to migrate.
 */
export function defaults(pills: readonly string[]): EdgeButton[] {
  const out: EdgeButton[] = [];
  for (const action of pills) if (action !== ROW_PILL) out.push({ action, side: "left" });
  if (pills.includes(ROW_PILL)) out.push({ action: ROW_PILL, side: "bottom" });
  out.push({ action: "agentsDashboard", side: "bottom" });
  return out;
}

// ── What a button can be besides a pill ──────────────────────────────────────
//
// Kept apart from the header tabs on purpose: the header is for the views the
// island holds, and the ring is for what you want in sight. The two overlap,
// and collapsing them would mean every tab had to earn a place on the border
// too.

export interface EdgeActionDef {
  id: string;
  title: string;
  color: string;
}

export const EDGE_ACTIONS: readonly EdgeActionDef[] = [
  { id: "agentsDashboard", title: "AI dashboard", color: "#F5F6F8" },
  { id: "clipboard", title: "Clipboard", color: "#8AB4F8" },
  { id: "timer", title: "Focus timer", color: "#F5A524" },
  { id: "settings", title: "Settings", color: "#8E939C" },
  { id: "site", title: "Site", color: "#38BDF8" },
];

export function edgeAction(id: string): EdgeActionDef | null {
  return EDGE_ACTIONS.find((a) => a.id === id) ?? null;
}
