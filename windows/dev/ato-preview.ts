// Dev harness: Ato's mascot (src/ato) in a plain browser — every state alive,
// the big bot following the pointer, the mini bot, and the still mark at the
// sizes it ships at. Not part of the app bundle.

import { ATO_STATES, type AtoState } from "../src/ato/bot";
import { AtoDriver, drawAtoInBotFrame } from "../src/ato/view";
import { atoMark } from "../src/views/logos";

const stages = document.getElementById("stages")!;
const label = (t: string) => Object.assign(document.createElement("div"), { className: "label", textContent: t });
const row = () => Object.assign(document.createElement("div"), { className: "row" });

interface Live { canvas: HTMLCanvasElement; driver: AtoDriver; state: AtoState; size: number; follow: boolean }
const lives: Live[] = [];
const pointer = { x: 0, y: 0 };

function orb(state: AtoState, size: number, lively: boolean, parent: HTMLElement, caption: string) {
  const cell = Object.assign(document.createElement("div"), { className: "cell" });
  const canvas = document.createElement("canvas");
  const dpr = Math.min(2, devicePixelRatio || 1);
  canvas.width = size * dpr; canvas.height = size * dpr;
  canvas.style.width = `${size}px`; canvas.style.height = `${size}px`;
  cell.append(canvas, caption);
  parent.append(cell);
  lives.push({ canvas, driver: new AtoDriver(lively), state, size, follow: lively });
}

stages.append(label("Big bot — every state (the hero driver: gestures every 6 s, gaze follows the pointer)"));
const big = row(); stages.append(big);
for (const s of ATO_STATES) orb(s, 110, true, big, s);

stages.append(label("Mini bot — the blog's small orb (no gestures, no pointer)"));
const mini = row(); stages.append(mini);
for (const s of ATO_STATES) orb(s, 22 / 0.6, false, mini, s);

stages.append(label("The still mark (ring disc, Settings)"));
const marks = row(); stages.append(marks);
for (const side of [13, 16, 32, 64]) {
  const disc = Object.assign(document.createElement("div"), { className: "disc" });
  if (side > 20) { disc.style.width = disc.style.height = `${side + 18}px`; }
  disc.append(atoMark(side));
  marks.append(disc);
}

addEventListener("pointermove", (e) => {
  pointer.x = Math.tanh((e.clientX - innerWidth / 2) / 260);
  pointer.y = Math.tanh((e.clientY - 120) / 200);
});

function tick() {
  const now = performance.now() / 1000, dpr = Math.min(2, devicePixelRatio || 1);
  for (const l of lives) {
    const x = l.canvas.getContext("2d")!;
    x.setTransform(dpr, 0, 0, dpr, 0, 0);
    x.clearRect(0, 0, l.size, l.size);
    drawAtoInBotFrame(x, l.driver.frame(now, l.state, l.follow ? pointer : null), l.size, l.size);
  }
  requestAnimationFrame(tick);
}
requestAnimationFrame(tick);
