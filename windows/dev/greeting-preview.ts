// Dev harness: the launch greeting frozen at one instant — `?t=2.9`, seconds
// in — with the line under Mochi — `?label=Boa tarde, Ana!` — on the island's
// 640×150 canvas, drawn twice as large so the line can be checked against
// Mochi's chin and the snow margin under the card. Not in the bundle.
//
// `?collapse=4.9` starts the fold at that second, to watch the line go with
// the card; `?guides` draws Mochi's chin at rest (119), at the bottom of the
// settle (126) and in the dip (130), and the card's end (140); `?play` runs it
// live, from the top every six seconds. For a pane that gets no animation
// frames, `drawAt(1.7)` redraws at another second and `greeting` is the object.

import { Greeting } from "../src/mochi/greeting";

const query = new URLSearchParams(location.search);
const at = Number(query.get("t") ?? "2.9");
const label = query.get("label") ?? "Good afternoon, Ana!";
const collapse = query.get("collapse");

const SCALE = 2;
const canvas = document.getElementById("greeting") as HTMLCanvasElement;
canvas.width = 640 * SCALE;
canvas.height = 150 * SCALE;
canvas.style.width = `${640 * SCALE}px`;
canvas.style.height = `${150 * SCALE}px`;
const ctx = canvas.getContext("2d")!;

const greeting = new Greeting();
greeting.start(label);
// The fold, at a second of the preview's choosing — the island sets this when
// the pointer leaves, which a frozen frame cannot do.
if (collapse !== null) (greeting as unknown as { tc: number }).tc = Number(collapse);

function guides() {
  ctx.save();
  ctx.lineWidth = 1 / SCALE;
  for (const [y, colour] of [[119, "#3b9eff"], [126, "#22c55e"], [130, "#f5a524"], [140, "#f4505e"]] as const) {
    ctx.strokeStyle = colour;
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(640, y);
    ctx.stroke();
  }
  ctx.restore();
}

/** One frame, `seconds` into the greeting. */
function drawAt(seconds: number) {
  ctx.setTransform(SCALE, 0, 0, SCALE, 0, 0);
  greeting.draw(ctx, seconds);
  if (query.has("guides")) guides();
  document.getElementById("label")!.textContent = `t = ${seconds.toFixed(2)} s — “${label}”`;
}

Object.assign(window, { greeting, drawAt });

if (query.has("play")) {
  const loop = () => {
    if (greeting.elapsed > 6) greeting.start(label);
    drawAt(greeting.elapsed);
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
} else {
  drawAt(at);
}
