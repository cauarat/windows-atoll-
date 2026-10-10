// The body tables, checked against the Swift ones.
//
// Both sides are written by scripts/generate-mochi-shapes.mjs from one source,
// so in principle they cannot differ. This is what catches the case where
// somebody edits a generated file by hand, or regenerates one platform and
// forgets the other — which is a silent, shipping-quality bug, because each
// platform looks perfectly correct on its own.
//
// Run by scripts/test-mochi-character.sh, which supplies SHAPES_DUMP.

import { readFileSync } from "node:fs";
import {
  MOCHI_SHAPES, MOCHI_SHAPE_LABEL, MOCHI_SHAPE_TABLE, shapeOutline,
  furHash, furSample, anchorRadius,
} from "../windows/src/mochi/shape.ts";
import { SHAPES } from "../windows/src/mochi/character.ts";

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

const f6 = (v: number) => v.toFixed(6);
const nums = (text: string) => text.split(",").map(Number);

// ── The list in character.ts cannot drift from the generated table ───────────
//
// character.ts spells the six out rather than importing them, so that it stays
// free of runtime imports and this file can load it under bare Node.

check(SHAPES.length === MOCHI_SHAPES.length && SHAPES.every((s, i) => s === MOCHI_SHAPES[i]),
  "character.ts lists the same bodies the table defines");

// ── Swift's numbers, value for value ─────────────────────────────────────────

const dump = readFileSync(process.env.SHAPES_DUMP!, "utf8").trimEnd().split("\n");
check(dump.length === MOCHI_SHAPES.length, `Swift knows the same ${MOCHI_SHAPES.length} bodies`);

for (const line of dump) {
  const c = line.split("\t");
  const [id, label, o72, o36, o24, anchor, sockets] = c;
  const g = MOCHI_SHAPE_TABLE[id as keyof typeof MOCHI_SHAPE_TABLE];
  if (!g) { check(false, `TypeScript has a body called ${id}`); continue; }

  check(MOCHI_SHAPE_LABEL[id as keyof typeof MOCHI_SHAPE_LABEL] === label,
    `${label} is called the same thing on both sides`);

  const sameList = (swift: string, ts: number[]) => {
    const a = nums(swift);
    return a.length === ts.length && a.every((v, i) => Math.abs(v - ts[i]) < 1e-6);
  };
  check(sameList(o72, g.outline72) && sameList(o36, g.outline36) && sameList(o24, g.outline24),
    `${label} is the same silhouette at every size`);
  check(sameList(anchor, g.anchor24), `${label} hangs its hat in the same place`);

  const swiftSockets = sockets
    ? sockets.split(";").map((s) => s.split("/").map(Number))
    : [];
  check(swiftSockets.length === g.sockets.length
    && swiftSockets.every(([x, y, r], i) =>
         Math.abs(x - g.sockets[i].x) < 1e-6
      && Math.abs(y - g.sockets[i].y) < 1e-6
      && Math.abs(r - g.sockets[i].r) < 1e-6),
    `${label} has the same sockets`);

  // Everything after the lists, in the order the Swift dump writes it.
  const scalars: [string, number][] = [
    ["rxK", g.rxK], ["ryK", g.ryK], ["top", g.top], ["bottom", g.bottom],
    ["eyeSp", g.eyeSp], ["eyeP", g.eyeP],
    ["earA0", g.earA0], ["earE0", g.earE0], ["crownE0", g.crownE0], ["cheekK", g.cheekK],
    ["handX", g.handX], ["handY", g.handY], ["badgeA0", g.badgeA0], ["badgeE0", g.badgeE0],
    ["eyeScale", g.eyeScale], ["pivotY", g.pivotY], ["squashAnchorY", g.squashAnchorY], ["breathScale", g.breathScale],
  ];
  const wrong = scalars.filter(([, v], i) => f6(v) !== c[7 + i]).map(([n]) => n);
  check(wrong.length === 0,
    wrong.length ? `${label} disagrees about ${wrong.join(", ")}` : `${label} agrees on every measurement`);
}

// ── The things that are computed rather than tabulated ───────────────────────

// The ragged edge and the plush tile both come off this hash, and a float
// `sin` would have drifted between the two platforms in its last bits.
check([0, 1, 7, 1000, 65535].every((i) => {
  const v = furHash(i, 0x5eed1234);
  return v >= 0 && v <= 1 && Number.isFinite(v);
}), "the fur hash stays inside 0…1");
check(furHash(5, 1) !== furHash(5, 2) && furHash(5, 1) === furHash(5, 1),
  "the fur hash is seeded, and stable once seeded");

check([0, 1, 50, 95].every((x) => [0, 1, 50, 95].every((y) => {
  const v = furSample(x, y);
  return Number.isInteger(v) && v >= 150 && v <= 255;
})), "the plush tile stays light enough to texture rather than shade");

// Seamless: the tile is multiplied over a body far wider than 96 px, so a hard
// edge at the wrap would read as a grid drawn on the creature.
const seam = [0, 13, 44, 77].map((y) => Math.abs(furSample(0, y) - furSample(95, y)));
check(Math.max(...seam) < 40, "the plush tile wraps without a seam");

for (const s of MOCHI_SHAPES) {
  const g = MOCHI_SHAPE_TABLE[s];
  const r = anchorRadius(0, g);
  check(Math.abs(r - g.anchor24[0]) < 1e-9, `${MOCHI_SHAPE_LABEL[s]} reads its anchor table straight`);
  check(shapeOutline(g, 72).length === 72 && shapeOutline(g, 36).length === 36
     && shapeOutline(g, 24).length === 24 && shapeOutline(g, 8).length === 24,
    `${MOCHI_SHAPE_LABEL[s]} picks a sensible table at every size`);
}

console.log("");
if (failures > 0) {
  console.log(`${failures} failed.`);
  process.exit(1);
}
console.log("TypeScript body tables agree with Swift.");
