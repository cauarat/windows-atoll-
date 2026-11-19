// Dev harness: the Hydration tab in each of its states, the reminder card in
// each thing it can say, and the closed island's little glass — every one
// seeded through `Hydration.seedForPreview`, which also cuts the store off from
// localStorage so looking at this page cannot rewrite a real day.
//
// Mochi is the real engine, drawn where `botPosition` puts him and filled the
// way the island fills him, so the glass body can be checked here too.
//
// The store is one singleton and the page shows a dozen states of it, so each
// card is a picture of the moment it was seeded. Click inside a card and it
// becomes the live one: it is seeded again and follows the store from then on,
// which is how the wave, the drop and the celebration are looked at.
//
// `npx vite`, then /dev/hydration-preview.html — `?lang=pt-BR` or `?lang=es`
// for the other two languages.

import "../src/style.css";
import { buildCompactSip, buildHydration, buildSip } from "../src/views/hydration";
import type { ViewActions, ViewHost } from "../src/views/views";
import { Hydration, type HydrationPrompt, type HydrationScene } from "../src/core/hydrationStore";
import { setLanguage, type Language } from "../src/core/i18n";
import { botPosition, islandSize, type IslandViewName } from "../src/core/layout";
import { BotEngine, hexToRGB } from "../src/mochi/engine";

const noop = () => {};
const actions: ViewActions = {
  setView: noop, collapse: noop, setFocus: noop, openTerminal: noop,
  openTarget: noop, openUrl: noop, decide: noop, toggleSound: noop,
  setVolume: noop, setAutoClose: noop, openSettingsWindow: noop,
  setPinned: noop, focusField: noop, blip: noop,
};

const asked = new URLSearchParams(location.search).get("lang");
if (asked) setLanguage(asked as Language);

interface Case {
  label: string;
  view: "hydration" | "sip";
  seed(): void;
}

const scene = (s: HydrationScene, prompt: HydrationPrompt | null = null) => () => Hydration.seedForPreview(s, prompt);

const CASES: Case[] = [
  { label: "not set up yet", view: "hydration", seed: scene("intro") },
  { label: "the start of the day", view: "hydration", seed: scene("empty") },
  { label: "mid-day, 850 ml of 2.2 L", view: "hydration", seed: scene("mid") },
  {
    label: "one glass from the goal — click the glass for the celebration", view: "hydration",
    seed: () => { Hydration.seedForPreview("mid"); Hydration.log(1200); },
  },
  { label: "goal reached, streak on — the week of frozen days", view: "hydration", seed: scene("goal") },
  {
    label: "goal reached, streak off", view: "hydration",
    seed: () => { Hydration.seedForPreview("goal"); Hydration.setSettings({ streakEnabled: false }); },
  },
  { label: "reminders paused", view: "hydration", seed: scene("paused") },
  { label: "a limit of 1.5 L", view: "hydration", seed: scene("limit") },
  {
    label: "no goal, just logging", view: "hydration",
    seed: () => { Hydration.seedForPreview("mid"); Hydration.setGoal({ kind: "none", ml: 0 }); },
  },
  { label: "the reminder", view: "sip", seed: scene("mid", "reminder") },
  { label: "the reminder, answered", view: "sip", seed: scene("mid", "logged") },
  { label: "the reminder, and that was the goal", view: "sip", seed: scene("goal", "goal") },
  { label: "the reminder, put off", view: "sip", seed: scene("mid", "snoozed") },
];

interface Stage {
  seed(): void;
  view: ViewHost;
  canvas: HTMLCanvasElement;
  engine: BotEngine;
  width: number;
  /** What the engine is told, as the island would tell it. */
  level: number | null;
  paused: boolean;
}

const OVERHANG = 40;
const CYAN = hexToRGB("#22D3EE");
const GREY = hexToRGB("#94A3B8");
const dpr = Math.min(2, window.devicePixelRatio || 1);
const stages: Stage[] = [];
let live: Stage | null = null;

/** What the island pushes into the engine each frame, read off the store now. */
function read(stage: Stage) {
  stage.level = Hydration.enabled ? Hydration.level : null;
  stage.paused = Hydration.paused;
}

function draw(stage: Stage, dt: number) {
  const ctx = stage.canvas.getContext("2d");
  if (!ctx) return;
  const h = stage.width + OVERHANG;
  stage.engine.particleOverhang = OVERHANG;
  stage.engine.waterLevel = stage.level;
  stage.engine.waterColor = stage.paused ? GREY : CYAN;
  stage.engine.update(dt);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, stage.width, h);
  stage.engine.draw(ctx, stage.width, h);
}

const cols = document.getElementById("cols")!;

for (const c of CASES) {
  const view: IslandViewName = c.view;
  const { h } = islandSize("expanded", view, 0, "automatic", 0, false, false, 0);
  const bot = botPosition("expanded", view, h);

  const col = document.createElement("div");
  col.className = "col";
  const label = Object.assign(document.createElement("div"), { className: "label", textContent: `${c.label} — ${h}px` });
  const stageEl = document.createElement("div");
  stageEl.className = "stage";
  stageEl.style.height = `${h}px`;
  const inner = document.createElement("div");
  inner.className = "inner";
  const host = c.view === "hydration" ? buildHydration(actions) : buildSip(actions);
  host.el.classList.add("on");
  inner.append(host.el);

  // The island's own arithmetic (`drawBot`): the canvas is the body's diameter
  // over 0.6, with 40 px of headroom for whatever flies out of him.
  const width = Math.round(bot.diameter / 0.6);
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(width * dpr);
  canvas.height = Math.round((width + OVERHANG) * dpr);
  canvas.style.width = `${width}px`;
  canvas.style.height = `${width + OVERHANG}px`;
  canvas.style.left = `${bot.cx - width / 2}px`;
  canvas.style.top = `${bot.cy - OVERHANG / 2 - (width + OVERHANG) / 2}px`;

  stageEl.append(inner, canvas);
  col.append(label, stageEl);
  cols.append(col);

  const stage: Stage = { seed: c.seed, view: host, canvas, engine: new BotEngine(), width, level: null, paused: false };
  stages.push(stage);

  c.seed();
  host.sync();
  read(stage);
  // Twice: the first frame is where the engine meets its level, and it draws
  // from the second. Synchronously, so a pane that gives no animation frames
  // still shows him.
  draw(stage, 0.016);
  draw(stage, 0.016);

  // The first press inside a card makes it the live one, before the press
  // reaches whatever was under it.
  stageEl.addEventListener("pointerdown", () => {
    if (live === stage) return;
    live = stage;
    for (const el of document.querySelectorAll(".label b")) el.remove();
    label.append(" ", Object.assign(document.createElement("b"), { textContent: "live" }));
    stage.seed();
    stage.view.sync();
    read(stage);
  }, true);
}

// The closed island: Mochi on the left, the waiting glass on the right.
{
  Hydration.seedForPreview("mid", "reminder");
  const col = document.createElement("div");
  col.className = "col";
  const label = Object.assign(document.createElement("div"), {
    className: "label", textContent: "closed, a reminder waiting — 288 × 32",
  });
  const bar = document.createElement("div");
  bar.className = "bar";
  const sip = buildCompactSip();
  // Where `applyGeometry` puts it: its centre 40 px in from the right.
  sip.el.style.left = `${288 - 40 - 6}px`;
  sip.el.style.top = `${32 / 2 - 7.2}px`;
  sip.sync(true);
  bar.append(sip.el);
  col.append(label, bar);
  cols.append(col);
}

let pulse = Hydration.pulse;
let celebrating = false;
Hydration.subscribe(() => {
  if (!live) return;
  live.view.sync();
  read(live);
  // The island's own two reactions to a glass.
  if (Hydration.celebrating && !celebrating) live.engine.triggerEmote("proud", 2.6);
  else if (Hydration.pulse !== pulse && !Hydration.celebrating) live.engine.triggerEmote("happy");
  pulse = Hydration.pulse;
  celebrating = Hydration.celebrating;
});

let last = performance.now();
function loop(nowMs: number) {
  const dt = Math.min(0.05, (nowMs - last) / 1000);
  last = nowMs;
  for (const stage of stages) draw(stage, dt);
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
