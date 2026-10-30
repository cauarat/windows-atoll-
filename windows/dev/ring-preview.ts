// Dev harness: the ring around the island, at every anchor, in a plain browser.
// Not part of the app bundle.
//
// The red outline is the rect the island pushes to Rust for click-through. A
// disc outside it would be drawn over a window that lets clicks through, so
// that outline has to contain every one of them.

import "../src/style.css";
import { PANEL_H, PANEL_W } from "../src/core/layout";
import { anchorFor, islandX, type IslandPosition } from "../src/core/anchor";
import {
  DIAMETER, chromeBounds, defaults as ringDefaults, layout, type EdgeButton,
} from "../src/core/edgeRing";
import { ICONS } from "../src/views/icons";
import { PILL_LOGOS } from "../src/views/logos";
import { h, svg } from "../src/views/dom";

/** Exactly what a fresh install deals, from the real function. */
const DEFAULT: EdgeButton[] = ringDefaults([
  "integration_music", "integration_mattermost",
  "integration_clickmassa", "integration_notifications",
]);

const ROW: EdgeButton[] = [
  { action: "integration_claude", side: "bottom" },
  { action: "integration_music", side: "bottom" },
  { action: "integration_notifications", side: "bottom" },
  { action: "timer", side: "bottom" },
  { action: "site", side: "bottom" },
];

const SIDES: EdgeButton[] = [
  { action: "integration_music", side: "left" },
  { action: "integration_mattermost", side: "left" },
  { action: "settings", side: "right" },
  { action: "clipboard", side: "right" },
];

const MARKS: Record<string, string> = {
  integration_claude: ICONS.code,
  integration_music: ICONS.musicNote,
  integration_notifications: ICONS.bell,
  clipboard: ICONS.clipboard,
  timer: ICONS.timer,
  settings: ICONS.gear,
  site: ICONS.globe,
};

const TINTS: Record<string, string> = {
  integration_claude: "#F5F6F8",
  integration_music: "#FA2D48",
  integration_notifications: "#FFFFFF",
  integration_mattermost: "#1B6FF3",
  integration_clickmassa: "#41BFEF",
  clipboard: "#8AB4F8",
  timer: "#F5A524",
  settings: "#8E939C",
  site: "#38BDF8",
};

/** One window, with the island where that position puts it and its ring on it. */
function stage(title: string, position: IslandPosition, buttons: EdgeButton[],
               islandW: number, islandH: number) {
  const anchor = anchorFor(position, PANEL_W, PANEL_H);
  const x = islandX(anchor, islandW);

  const panel = h("div", { class: "panel" });
  // The preview panel is 200 tall, not the window's real height: the island is
  // placed against the same edge, so what the ring has to clear is the same.
  const top = anchor.edge === "top" ? 0 : 200 - islandH;
  const island = h("div", { class: "island" });
  island.style.left = `${x}px`;
  island.style.top = `${top}px`;
  island.style.width = `${islandW}px`;
  island.style.height = `${islandH}px`;
  panel.append(island);

  const chrome = chromeBounds(buttons, anchor, islandW, islandH);
  const hit = h("div", { class: "hit" });
  hit.style.left = `${x + chrome.x}px`;
  hit.style.top = `${top + chrome.y}px`;
  hit.style.width = `${chrome.w}px`;
  hit.style.height = `${chrome.h}px`;
  panel.append(hit);

  for (const placed of layout(buttons, anchor, islandW, islandH)) {
    const logo = PILL_LOGOS[placed.button.action];
    const btn = h("button", { class: "ring-btn on", title: placed.button.action },
                  logo ? logo(16) : svg(MARKS[placed.button.action] ?? ICONS.ellipsis, 15));
    btn.style.setProperty("--tint", TINTS[placed.button.action] ?? "#8E939C");
    btn.style.width = `${DIAMETER}px`;
    btn.style.height = `${DIAMETER}px`;
    btn.style.left = `${x + placed.x - DIAMETER / 2}px`;
    btn.style.top = `${top + placed.y - DIAMETER / 2}px`;
    panel.append(btn);
  }

  const note = `${title} — window ${PANEL_W}×${PANEL_H}, island ${islandW}×${islandH}`;
  return h("div", {}, h("div", { class: "label", text: note }), panel);
}

const stages = document.getElementById("stages")!;
stages.append(
  stage("Bottom right, what a fresh install deals", "bottom-right", DEFAULT, 640, 160),
  stage("Top left, the same default — the column mirrors", "top-left", DEFAULT, 640, 160),
  stage("Bottom right, an all-bottom row", "bottom-right", ROW, 640, 160),
  stage("Top centre, the same row", "top-centre", ROW, 640, 160),
  stage("Bottom centre, columns either side", "bottom-centre", SIDES, 640, 160),
  stage("Bottom right, columns — both mirror inward", "bottom-right", SIDES, 640, 160),
  stage("Top left, columns — both mirror inward", "top-left", SIDES, 640, 160),
  stage("Compact island, a row that overhangs it", "bottom-right", ROW, 288, 32),
);
