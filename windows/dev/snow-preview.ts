// Dev harness: the snow on the island's floor, on every shape the island takes
// — the resting bar, an open card, against the bottom of the screen, and
// dropped in the open — so the bank, the corners and the plough can be looked
// at without Windows. Move the pointer through the snow. Not in the bundle.
//
// `?zoom=3` magnifies the lot: the bank is three pixels deep at rest, which is
// the point of it and no way to judge a curve.
// `?open=90` starts the open ones as if they had been open that many seconds.

import "../src/style.css";
import { SnowLayer } from "../src/island/snowLayer";

const params = new URLSearchParams(location.search);
const zoom = Number(params.get("zoom")) || 1;
const openFor = Number(params.get("open")) || 0;

const stages = document.getElementById("stages")!;
stages.style.transform = `scale(${zoom})`;

interface Stage { label: string; w: number; h: number; radius: string; expanded: boolean; card?: boolean }

const STAGES: Stage[] = [
  { label: "Resting bar — hugging the top", w: 288, h: 32, radius: "0 0 14px 14px", expanded: false },
  { label: "Open — hugging the top", w: 640, h: 150, radius: "0 0 22px 22px", expanded: true, card: true },
  { label: "Open — against the bottom of the screen", w: 640, h: 150, radius: "22px 22px 0 0",
    expanded: true, card: true },
  { label: "Resting bar — dropped in the open", w: 288, h: 32, radius: "14px", expanded: false },
];

// For driving it by hand from the console — `snowLayers[1].tick(t)` — where
// the page is in the background and gets no animation frames of its own.
const layers: SnowLayer[] = [];
(window as unknown as { snowLayers: SnowLayer[] }).snowLayers = layers;

for (const s of STAGES) {
  const label = document.createElement("div");
  label.className = "label";
  label.textContent = s.label;

  const stage = document.createElement("div");
  stage.className = "stage";
  stage.style.cssText = `width:${s.w}px;height:${s.h}px;border-radius:${s.radius}`;

  const clip = document.createElement("div");
  clip.className = "clip";
  const snow = new SnowLayer();
  clip.append(snow.el);
  layers.push(snow);
  if (s.card) {
    const card = document.createElement("div");
    card.className = "fake-card";
    card.innerHTML = `<b>Mattermost</b> <span>Messages</span><br><i>Connected</i><br>
      <b>Abrir o Mattermost</b>`;
    clip.append(card);
  }
  clip.append(snow.fall);
  stage.append(clip);
  stages.append(label, stage);

  snow.resize(s.w, s.h);
  snow.setEnabled(true);
  snow.setExpanded(s.expanded);
  // The clock cannot be wound forward from outside, and waiting a minute and a
  // half to see a deep bank is no way to work: reach in, here only.
  if (s.expanded && openFor > 0) {
    (snow as unknown as { field: { openFor: number } }).field.openFor = openFor;
  }

  stage.addEventListener("mousemove", (e) => {
    const r = stage.getBoundingClientRect();
    snow.setPointer({ x: (e.clientX - r.left) / zoom, above: (r.bottom - e.clientY) / zoom });
  });
  stage.addEventListener("mouseleave", () => snow.setPointer(null));
}
