// Dev harness: Ato's mascot (src/ato) in a plain browser — every state alive,
// each on its own Mochi engine so it reacts as a Mochi does, buttons for every
// reaction the island can send, and the still mark at the sizes it ships at.
// Not part of the app bundle.

import { ATO_STATES, type AtoState } from "../src/ato/bot";
import { AtoDriver, drawAtoInBotFrame, reactionFrom } from "../src/ato/view";
import { BotEngine } from "../src/mochi/engine";
import type { BotEmoteName, BotStateName } from "../src/core/layout";
import { atoMark } from "../src/views/logos";

const stages = document.getElementById("stages")!;
const label = (t: string) => Object.assign(document.createElement("div"), { className: "label", textContent: t });
const row = () => Object.assign(document.createElement("div"), { className: "row" });

interface Live { canvas: HTMLCanvasElement; driver: AtoDriver; engine: BotEngine; state: AtoState; size: number; big: boolean }
const lives: Live[] = [];

/** The pill state that makes the island show each Ato state. */
const PILL: Record<AtoState, BotStateName> = {
  idle: "idle", thinking: "thinking", notify: "question", success: "finished",
  error: "error", offline: "ratelimit", sleep: "sleeping", welcome: "idle",
};

function orb(state: AtoState, size: number, big: boolean, parent: HTMLElement, caption: string) {
  const cell = Object.assign(document.createElement("div"), { className: "cell" });
  const canvas = document.createElement("canvas");
  const dpr = Math.min(2, devicePixelRatio || 1);
  canvas.width = size * dpr; canvas.height = size * dpr;
  canvas.style.width = `${size}px`; canvas.style.height = `${size}px`;
  cell.append(canvas, caption);
  parent.append(cell);
  const engine = new BotEngine();
  engine.isMini = !big;
  engine.setState(PILL[state], true);
  // As the island does: the third slap in 1.7 s makes it dizzy for 3.3 s.
  engine.onDizzy = () => {
    engine.setState("dizzy");
    setTimeout(() => { engine.setState(PILL[state]); engine.triggerEmote("happy"); }, 3300);
  };
  lives.push({ canvas, driver: new AtoDriver(big), engine, state, size, big });
}

stages.append(label("Big bot — every state. Move the pointer: the eyes follow it in every state."));
const big = row(); stages.append(big);
for (const s of ATO_STATES) orb(s, 110, true, big, s);

stages.append(label("Reactions — sent to every big bot, as the island sends them"));
const buttons = row(); stages.append(buttons);
const act = (name: string, f: (e: BotEngine) => void) => {
  const b = Object.assign(document.createElement("button"), { textContent: name });
  b.onclick = () => lives.filter((l) => l.big).forEach((l) => f(l.engine));
  buttons.append(b);
};
act("hover", (e) => { e.blink(); e.tgEs = 1.08; setTimeout(() => (e.tgEs = 1), 1500); });
for (const emote of ["love", "happy", "proud", "surprised", "wink", "yawn", "annoyed"] as BotEmoteName[]) {
  act(emote, (e) => e.triggerEmote(emote));
}
act("slap", (e) => e.slap());
act("music on/off (dance)", (e) => e.setDancing(!e.isDancing));
act("slap ×3 (dizzy)", (e) => { e.slap(); setTimeout(() => e.slap(), 200); setTimeout(() => e.slap(), 400); });

stages.append(label("Mini bot — looks around on its own, like the other minis"));
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

let mouse = { x: 0, y: 0 };
addEventListener("pointermove", (e) => { mouse = { x: e.clientX, y: e.clientY }; });

let last = performance.now();
function tick() {
  const nowMs = performance.now(), dt = Math.min(0.05, (nowMs - last) / 1000), dpr = Math.min(2, devicePixelRatio || 1);
  last = nowMs;
  for (const l of lives) {
    if (l.big) {
      // The island's own gaze math, against this canvas.
      const r = l.canvas.getBoundingClientRect();
      l.engine.lookX = Math.tanh((mouse.x - (r.left + r.width / 2)) / 260);
      l.engine.lookY = -Math.tanh((mouse.y - (r.top + r.height / 2)) / 200);
    }
    l.engine.update(dt);
    const x = l.canvas.getContext("2d")!;
    x.setTransform(dpr, 0, 0, dpr, 0, 0);
    x.clearRect(0, 0, l.size, l.size);
    l.engine.applyDance(x, l.size, l.size);
    drawAtoInBotFrame(x, l.driver.frame(nowMs / 1000, l.state, reactionFrom(l.engine)), l.size, l.size);
    l.engine.drawParticlesOnly(x, l.size, l.size);
  }
  requestAnimationFrame(tick);
}
requestAnimationFrame(tick);
