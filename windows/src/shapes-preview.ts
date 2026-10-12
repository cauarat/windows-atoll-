// A dev page for looking at the bodies. Not shipped; `vite` serves it in dev.
import { characterPreview } from "./mochi/preview";
import { MOCHI_SHAPES, MOCHI_SHAPE_LABEL } from "./mochi/shape";
import { ACCESSORIES, EYES, type MochiCharacter, type MochiShape } from "./mochi/character";

const out = document.getElementById("out")!;
const COLORS = ["#1e88ff", "#8be22e", "#ffc21a", "#ff2fc4", "#9d6bff", "#ff7a2f", "#16c6ae"];
const bodies: (MochiShape | null)[] = [null, ...MOCHI_SHAPES];

function section(title: string, make: (i: number) => [MochiCharacter, string, number, string]) {
  const h = document.createElement("h2"); h.textContent = title; out.append(h);
  const row = document.createElement("div"); row.className = "row"; out.append(row);
  for (let i = 0; i < bodies.length; i++) {
    const [ch, color, size, label] = make(i);
    const t = document.createElement("div"); t.className = "tile";
    t.append(characterPreview(ch, color, size));
    const s = document.createElement("span"); s.textContent = label; t.append(s);
    row.append(t);
  }
}

section("Bodies, bare — 64 px", (i) =>
  [{ shape: bodies[i] }, COLORS[i], 64, bodies[i] ? MOCHI_SHAPE_LABEL[bodies[i]!] : "Classic"]);

section("Wearing something, each body a different hat — 64 px", (i) =>
  [{ shape: bodies[i], accessory: ACCESSORIES[i % ACCESSORIES.length], eye: EYES[i % EYES.length] },
   COLORS[i], 64,
   `${ACCESSORIES[i % ACCESSORIES.length]} / ${EYES[i % EYES.length]}`]);

section("Visor and shades, the eyes that are worn — 64 px", (i) =>
  [{ shape: bodies[i], accessory: "crown", eye: i % 2 ? "shades" : "visor" }, COLORS[i], 64,
   i % 2 ? "shades" : "visor"]);

section("Pill size — 22 px", (i) =>
  [{ shape: bodies[i], accessory: "catEars", eye: "dot" }, COLORS[i], 22, ""]);

section("Column size — 16 px", (i) =>
  [{ shape: bodies[i], accessory: "crown", eye: "dot" }, COLORS[i], 16, ""]);
