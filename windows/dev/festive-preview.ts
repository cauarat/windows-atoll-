// Dev harness: everything a Mochi — and Ato — can wear at Christmas, drawn by
// the real engines (src/mochi/engine.ts, src/ato/view.ts) from the generated
// artwork, alive: the lights run, the eyes blink and follow the pointer, and
// the buttons send every state and reaction the island can, which is the only
// way to watch the "Christmas eyes step aside for an expression" rule happen.
// Not part of the app bundle.
//
// `?size=120` draws the 64 px sheets bigger, to look at one closely;
// `?only=ato` (or classic, round, …, parts, eyes, over, flake, mini, tiles)
// keeps one sheet. Neither changes what the engines do.

import { BotEngine, hexToRGB } from "../src/mochi/engine";
import {
  FESTIVE_EXTRAS, FESTIVE_EYES, FESTIVE_HEADS, FESTIVE_TEXTURES, SHAPES,
  characterFromStorage, characterToStorage,
  type MochiCharacter, type MochiFestive, type MochiShape,
} from "../src/mochi/character";
import { MOCHI_SHAPE_LABEL } from "../src/mochi/shape";
import { festiveData, isFestiveSeason } from "../src/mochi/festive";
import { atoPreview, characterPreview } from "../src/mochi/preview";
import { AtoDriver, atoFestiveFrom, drawAtoInBotFrame, reactionFrom } from "../src/ato/view";
import type { BotEmoteName, BotStateName } from "../src/core/layout";

const query = new URLSearchParams(location.search);
const BIG = Number(query.get("size")) || 64;
const only = query.get("only");
const sheet = (name: string) => !only || only === name;

const stages = document.getElementById("stages")!;
const el = <K extends keyof HTMLElementTagNameMap>(tag: K, className = "", text = "") =>
  Object.assign(document.createElement(tag), { className, textContent: text });
const label = (t: string) => stages.appendChild(el("div", "label", t));
const row = () => stages.appendChild(el("div", "row"));

const { catalog } = festiveData();
const bodies: (MochiShape | null)[] = [null, ...SHAPES];
const bodyName = (s: MochiShape | null) => (s ? MOCHI_SHAPE_LABEL[s] : "Classic");
// One colour per body, and null — the big bot's own pale gradient — for classic.
const COLORS: (string | null)[] = [null, "#1e88ff", "#8be22e", "#ffc21a", "#ff2fc4", "#9d6bff", "#16c6ae"];
const ATO_BLUE = "#1B2FEB";

const festiveOf = (p: { head: string | null; eyes: string | null; texture: string | null; extra: string | null }): MochiFestive => ({
  ...(p.head ? { head: p.head } : {}), ...(p.eyes ? { eyes: p.eyes } : {}),
  ...(p.texture ? { texture: p.texture } : {}), ...(p.extra ? { extra: p.extra } : {}),
});

// ── The hand-kept id lists against the generated catalogue ────────────────────

const drift: string[] = [];
const same = (mine: readonly string[], theirs: [string, string][], what: string) => {
  if (JSON.stringify(mine) !== JSON.stringify(theirs.map((x) => x[0]))) drift.push(what);
};
same(FESTIVE_HEADS, catalog.heads, "FESTIVE_HEADS");
same(FESTIVE_EYES, catalog.eyes, "FESTIVE_EYES");
same(FESTIVE_TEXTURES, catalog.textures, "FESTIVE_TEXTURES");
same(FESTIVE_EXTRAS, catalog.extras, "FESTIVE_EXTRAS");
// And the storage string, there and back, for every preset on every body.
for (const preset of catalog.presets) {
  for (const shape of bodies) {
    const c: MochiCharacter = { accessory: "crown", eye: "dot", shape, festive: festiveOf(preset) };
    const back = characterFromStorage(characterToStorage(c));
    if (JSON.stringify(back) !== JSON.stringify(c)) drift.push(`storage round trip: ${preset.id} on ${bodyName(shape)}`);
  }
}
if (characterToStorage({ accessory: "catEars", eye: "dot", shape: "pointy", festive: {} }) !== "catEars:dot:pointy") {
  drift.push("an empty festive changed the stored string");
}
if (drift.length) {
  stages.append(el("div", "drift",
    `character.ts and festive.generated.ts disagree — ${drift.join("; ")}. Update the lists in src/mochi/character.ts.`));
}

// ── Live bots ────────────────────────────────────────────────────────────────

interface Live { canvas: HTMLCanvasElement; engine: BotEngine; size: number; ato: AtoDriver | null }
const lives: Live[] = [];

/** `body` is the body's size in CSS px; the canvas is body / 0.6, as everywhere. */
function bot(parent: HTMLElement, character: MochiCharacter, color: string | null, body: number, caption: string,
  opts: { mini?: boolean; ato?: boolean; black?: boolean } = {}) {
  const cell = parent.appendChild(el("div", opts.black ? "cell black" : "cell"));
  const size = body / 0.6;
  const dpr = Math.min(2, devicePixelRatio || 1);
  const canvas = cell.appendChild(document.createElement("canvas"));
  canvas.width = Math.round(size * dpr); canvas.height = Math.round(size * dpr);
  canvas.style.width = `${size}px`; canvas.style.height = `${size}px`;
  if (caption) cell.append(el("span", "", caption));
  const engine = new BotEngine();
  engine.isMini = !!opts.mini;
  engine.bodyColor = color ? hexToRGB(color) : null;
  engine.character = character;
  engine.setState("idle", true);
  engine.onDizzy = () => {
    engine.setState("dizzy");
    setTimeout(() => { engine.setState("idle"); engine.triggerEmote("happy"); }, 3300);
  };
  lives.push({ canvas, engine, size, ato: opts.ato ? new AtoDriver(!opts.mini) : null });
}

// ── Controls ─────────────────────────────────────────────────────────────────

const bar = stages.appendChild(el("div", "bar"));
const act = (name: string, f: (e: BotEngine) => void) => {
  const b = bar.appendChild(el("button", "", name));
  b.onclick = () => lives.forEach((l) => f(l.engine));
};
bar.append(`season today: ${isFestiveSeason() ? "yes" : "no"} · `);
for (const s of ["idle", "working", "approval", "question", "error", "finished", "ratelimit", "sleeping", "dizzy"] as BotStateName[]) {
  act(s, (e) => e.setState(s, true));
}
bar.append(" · ");
for (const emote of ["love", "happy", "proud", "surprised", "wink", "yawn", "annoyed"] as BotEmoteName[]) {
  act(emote, (e) => e.triggerEmote(emote));
}
act("blink", (e) => e.blink());
act("slap", (e) => e.slap());
act("mailbox", (e) => e.animateMorph(e.morph > 0.5 ? 0 : 1));
act("dance", (e) => e.setDancing(!e.isDancing));
let frozen = false;
const freeze = bar.appendChild(el("button", "", "freeze"));
freeze.onclick = () => { frozen = !frozen; freeze.classList.toggle("on", frozen); };

// ── The sheets ───────────────────────────────────────────────────────────────

for (const [i, shape] of bodies.entries()) {
  if (!sheet(shape ?? "classic")) continue;
  label(`${bodyName(shape)} — the 12 ready-made, ${BIG} px`);
  const r = row();
  for (const preset of catalog.presets) {
    bot(r, { shape, festive: festiveOf(preset) }, COLORS[i], BIG, preset.name);
  }
}

if (sheet("ato")) {
  label(`Ato — the 12 ready-made, ${BIG} px`);
  const r = row();
  bot(r, {}, ATO_BLUE, BIG, "bare", { ato: true });
  for (const preset of catalog.presets) {
    bot(r, { festive: festiveOf(preset) }, ATO_BLUE, BIG, preset.name, { ato: true });
  }
}

const PARTS: [string, keyof MochiFestive, [string, string][]][] = [
  ["Head", "head", catalog.heads], ["Eyes", "eyes", catalog.eyes],
  ["Texture", "texture", catalog.textures], ["Extra", "extra", catalog.extras],
];
for (const [name, slot, list] of PARTS) {
  if (!sheet("parts")) break;
  label(`${name} — each part alone, classic body, ${BIG} px (Mochi's own pale body, then a pill colour)`);
  const r = row();
  for (const [id, partName] of list) bot(r, { festive: { [slot]: id } }, null, BIG, partName);
  const r2 = row();
  for (const [id, partName] of list) bot(r2, { festive: { [slot]: id } }, "#1e88ff", BIG, partName);
}

for (const [name, slot, list] of PARTS) {
  if (!sheet("ato")) break;
  label(`${name} — each part alone, on Ato, ${BIG} px`);
  const r = row();
  for (const [id, partName] of list) bot(r, { festive: { [slot]: id } }, ATO_BLUE, BIG, partName, { ato: true });
}

if (sheet("eyes")) {
  label("Every eye on every body (the frog's sit in its sockets)");
  for (const [i, shape] of bodies.entries()) {
    const r = row();
    for (const [id] of catalog.eyes) {
      bot(r, { shape, festive: { eyes: id } }, COLORS[i] ?? "#F5F6F8", only ? BIG : 48, i === 0 ? id : "");
    }
  }
}

if (sheet("over")) {
  label("Christmas over an existing character — the hat replaces the crown, the eyes the glossy ones; the body stays");
  const r = row();
  bot(r, { accessory: "crown", eye: "glossy", shape: "round" }, "#ffc21a", BIG, "Royal, bare");
  bot(r, { accessory: "crown", eye: "glossy", shape: "round", festive: { head: "santaHat" } }, "#ffc21a", BIG, "+ Santa hat");
  bot(r, { accessory: "crown", eye: "glossy", shape: "round", festive: { eyes: "starEye" } }, "#ffc21a", BIG, "+ star eyes");
  bot(r, { accessory: "crown", eye: "shades", shape: "round", festive: { texture: "sweater" } }, "#ffc21a", BIG, "shades + sweater");
  bot(r, { accessory: "catEars", eye: "visor", festive: { extra: "scarf" } }, "#9d6bff", BIG, "visor + scarf");
}

if (sheet("flake")) {
  label("Snowflake eyes and frost: pale body, dark body");
  const r = row();
  for (const color of ["#F5F6F8", "#FFFFFF", "#ffc21a", "#1e88ff", "#22252b"]) {
    bot(r, { festive: { eyes: "snowflake" } }, color, BIG, `${color} flake`);
    bot(r, { festive: { eyes: "snowflake", texture: "frost" } }, color, BIG, "+ frost");
    bot(r, { festive: { eyes: "snowflake", texture: "gingerbread", head: "elfEars" } }, color, BIG, "+ ginger, ears");
  }
}

if (sheet("mini")) {
  label("Pill size — 22 px minis on black, as in a pill: the 12 ready-made, classic then each body, then Ato");
  for (const [i, shape] of bodies.entries()) {
    const r = row();
    for (const preset of catalog.presets) {
      bot(r, { shape, festive: festiveOf(preset) }, COLORS[i] ?? "#F5F6F8", 22, "", { mini: true, black: true });
    }
  }
  const r = row();
  for (const preset of catalog.presets) {
    bot(r, { festive: festiveOf(preset) }, ATO_BLUE, 22, "", { mini: true, ato: true, black: true });
  }

  label("Column size — 16 px minis");
  const r2 = row();
  for (const preset of catalog.presets) {
    bot(r2, { festive: festiveOf(preset) }, "#ff7a2f", 16, "", { mini: true, black: true });
  }
}

if (sheet("tiles")) {
  label("The Settings tiles — still, drawn once by characterPreview / atoPreview at 54 px");
  const r = row();
  for (const preset of catalog.presets) {
    const cell = r.appendChild(el("div", "cell"));
    cell.append(characterPreview({ shape: "frog", festive: festiveOf(preset) }, "#16c6ae", 54), el("span", "", preset.name));
  }
  const r2 = row();
  for (const preset of catalog.presets) {
    const cell = r2.appendChild(el("div", "cell"));
    cell.append(atoPreview(festiveOf(preset), 54), el("span", "", preset.name));
  }
}

// ── The loop ─────────────────────────────────────────────────────────────────

let mouse = { x: innerWidth / 2, y: innerHeight / 2 };
addEventListener("pointermove", (e) => { mouse = { x: e.clientX, y: e.clientY }; });

let last = performance.now();
function tick() {
  const nowMs = performance.now(), dt = Math.min(0.05, (nowMs - last) / 1000), dpr = Math.min(2, devicePixelRatio || 1);
  last = nowMs;
  if (!frozen) {
    for (const l of lives) {
      const e = l.engine;
      if (!e.isMini) {
        const r = l.canvas.getBoundingClientRect();
        e.lookX = Math.tanh((mouse.x - (r.left + r.width / 2)) / 260);
        e.lookY = -Math.tanh((mouse.y - (r.top + r.height / 2)) / 200);
      }
      e.update(dt);
      const x = l.canvas.getContext("2d")!;
      x.setTransform(dpr, 0, 0, dpr, 0, 0);
      x.clearRect(0, 0, l.size, l.size);
      e.applyDance(x, l.size, l.size);
      if (l.ato && e.morph < 0.05) {
        const nowS = nowMs / 1000;
        drawAtoInBotFrame(x, l.ato.frame(nowS, "idle", reactionFrom(e)), l.size, l.size, 0, atoFestiveFrom(e, nowS));
        e.drawParticlesOnly(x, l.size, l.size);
      } else {
        e.draw(x, l.size, l.size);
      }
    }
  }
  requestAnimationFrame(tick);
}
requestAnimationFrame(tick);
