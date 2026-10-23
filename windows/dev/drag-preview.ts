// Dev harness: where a dropped island ends up, in a plain browser.
// Not part of the app bundle.
//
// The gesture itself cannot be driven here — there is no window to move and no
// cursor to read — so this draws the thing the gesture produces: for a set of
// drops, what gets stored, where Rust puts the window, and where the page then
// draws the island inside it. If those three disagree the island is not where
// it looks, which is an island nobody can click.
//
// The red dot is where the island was dropped. The dashed box is the window.
// The black shape is the island at rest, with the open card drawn behind it in
// outline so the growth direction is visible.

import "../src/style.css";
import {
  anchorFor, islandX, islandY, positionForDrop, radiusCss,
} from "../src/core/anchor";
import { COMPACT_W, EXPANDED_W, NOTCH_H, PANEL_H, PANEL_W } from "../src/core/layout";
import { h } from "../src/views/dom";

/** A 1080p screen with a 40 px taskbar along the bottom, drawn at a third. */
const AREA_W = 1920;
const AREA_H = 1040;
const SCALE = 0.32;

const DROPS: Array<[string, number, number]> = [
  ["the six corners still snap — bottom right", 1770, 1024],
  ["…and top left", 150, 16],
  ["along the top, off to one side", 600, 16],
  ["the open middle", 700, 500],
  ["low, but not on the edge", 1200, 900],
  ["hard against the left, halfway down", 0, 520],
  ["bottom right-ish, but not close enough to snap", 1500, 820],
];

const px = (n: number) => `${n * SCALE}px`;

function stage(title: string, dx: number, dy: number): HTMLElement {
  const stored = positionForDrop(dx, dy, AREA_W, AREA_H);
  const a = anchorFor(stored, AREA_W, AREA_H);

  const area = h("div", { class: "area" });
  area.style.width = px(AREA_W);
  area.style.height = px(AREA_H);

  // The window, where Rust puts it.
  const win = h("div", { class: "win" });
  win.style.left = px(a.free?.winX ?? windowLeftForPreset(stored));
  win.style.top = px(a.free?.winY ?? (a.edge === "top" ? 0 : AREA_H - PANEL_H));
  win.style.width = px(PANEL_W);
  win.style.height = px(PANEL_H);

  // The island at rest, where the page draws it inside that window.
  const rest = h("div", { class: "island" });
  rest.style.left = px(islandX(a, COMPACT_W));
  rest.style.top = px(islandY(a, NOTCH_H));
  rest.style.width = px(COMPACT_W);
  rest.style.height = px(NOTCH_H);
  rest.style.borderRadius = radiusCss(a, 14 * SCALE);

  // The open card, so which way it grows is visible.
  const open = h("div", { class: "island" });
  open.style.left = px(islandX(a, EXPANDED_W));
  open.style.top = px(islandY(a, 300));
  open.style.width = px(EXPANDED_W);
  open.style.height = px(300);
  open.style.background = "transparent";
  open.style.outline = "1px solid rgba(255,255,255,.22)";
  open.style.borderRadius = radiusCss(a, 22 * SCALE);

  win.append(open, rest);

  const dot = h("div", { class: "drop" });
  dot.style.left = px(dx);
  dot.style.top = px(dy);
  area.append(win, dot);

  return h("div", {},
    h("h2", { text: title }),
    area,
    h("div", {
      class: "cap",
      text: `${stored}   edge=${a.edge} align=${a.align} hug=${a.hug ?? "free"}`,
    }));
}

/** Where apply_geometry puts the window for one of the six names. */
function windowLeftForPreset(p: string): number {
  if (p.endsWith("-left")) return 0;
  if (p.endsWith("-centre") || p.endsWith("-center")) return (AREA_W - PANEL_W) / 2;
  return AREA_W - PANEL_W;
}

const stages = document.getElementById("stages")!;
stages.append(h("p", {
  class: "note",
  text: "Red dot: where it was dropped. Dashed box: the window Rust places. "
      + "Black: the island at rest. Outline: the open card, so the growth "
      + "direction shows. Work area 1920×1040, drawn at a third.",
}));
for (const [title, x, y] of DROPS) stages.append(stage(title, x, y));
