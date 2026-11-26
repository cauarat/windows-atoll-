// The Android body tables, checked against the Swift ones.
//
// android/app/src/main/kotlin/com/cauarati/notchy/mochi/MochiShape.kt is
// written by scripts/generate-mochi-shapes.mjs from the same source as
// MochiShape.swift and windows/src/mochi/shape.ts. This reads its literals back
// and compares them, value for value, with the Swift dump — what catches a
// hand-edited Kotlin table, or a regeneration that skipped Android.
//
// The Kotlin functions that are computed rather than tabulated (the fur hash,
// the plush tile, the anchor lookup) are run by the app's own unit test,
// MochiShapeTest.kt, against expected values written there. This file checks
// those expected values are TypeScript's, so the chain is Swift = TypeScript
// (mochi-shape-parity.ts) = Kotlin.
//
// Run by scripts/test-mochi-character.sh, which supplies SHAPES_DUMP.

import { readFileSync } from "node:fs";
import {
  MOCHI_SHAPES, MOCHI_SHAPE_LABEL, furHash, furSample, anchorRadius, MOCHI_SHAPE_TABLE,
} from "../windows/src/mochi/shape.ts";

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

const KT = "android/app/src/main/kotlin/com/cauarati/notchy/mochi/MochiShape.kt";
const TEST = "android/app/src/test/kotlin/com/cauarati/notchy/MochiShapeTest.kt";
const kt = readFileSync(KT, "utf8");
const f6 = (v: number) => v.toFixed(6);
const nums = (text: string) => text.split(",").map((s) => Number(s.trim())).filter((v) => !Number.isNaN(v));

/** The `val NAME = MochiShapeGeometry(...)` block of one body. */
function block(id: string): string | null {
  const start = kt.indexOf(`val ${id.toUpperCase()} = MochiShapeGeometry(`);
  if (start < 0) return null;
  const end = kt.indexOf("\n    )", start);
  return end < 0 ? null : kt.slice(start, end);
}
const list = (b: string, name: string) => {
  const m = b.match(new RegExp(`${name} = doubleArrayOf\\(([^)]*)\\)`));
  return m ? nums(m[1]) : [];
};
const scalar = (b: string, name: string) => {
  const m = b.match(new RegExp(`\\b${name} = (-?[0-9.]+)`));
  return m ? Number(m[1]) : NaN;
};

const enumIds = [...kt.matchAll(/^\s{4}([A-Z]+)\("([a-z]+)", "([^"]+)"\),$/gm)].map((m) => [m[2], m[3]]);
check(enumIds.length === MOCHI_SHAPES.length && enumIds.every(([id], i) => id === MOCHI_SHAPES[i]),
  "Kotlin lists the same bodies, in the same order");

const dump = readFileSync(process.env.SHAPES_DUMP!, "utf8").trimEnd().split("\n");
for (const line of dump) {
  const c = line.split("\t");
  const [id, label, o72, o36, o24, anchor, sockets] = c;
  const b = block(id);
  if (!b) { check(false, `Kotlin has a body called ${id}`); continue; }
  check(enumIds.some(([k, l]) => k === id && l === label), `${label} is called the same thing on Android`);

  const same = (swift: string, k: number[]) => {
    const a = nums(swift);
    return a.length === k.length && a.every((v, i) => Math.abs(v - k[i]) < 1e-6);
  };
  check(same(o72, list(b, "outline72")) && same(o36, list(b, "outline36")) && same(o24, list(b, "outline24")),
    `${label} is the same silhouette on Android at every size`);
  check(same(anchor, list(b, "anchor24")), `${label} hangs its hat in the same place on Android`);

  const ktSockets = [...b.matchAll(/MochiSocket\((-?[0-9.]+), (-?[0-9.]+), (-?[0-9.]+)\)/g)].map((m) => [1, 2, 3].map((i) => Number(m[i])));
  const swiftSockets = sockets ? sockets.split(";").map((s) => s.split("/").map(Number)) : [];
  check(ktSockets.length === swiftSockets.length
    && swiftSockets.every((s, i) => s.every((v, j) => Math.abs(v - ktSockets[i][j]) < 1e-6)),
    `${label} has the same sockets on Android`);

  const names = ["rxK", "ryK", "top", "bottom", "eyeSp", "eyeP", "earA0", "earE0", "crownE0", "cheekK",
    "handX", "handY", "badgeA0", "badgeE0", "eyeScale", "pivotY", "squashAnchorY", "breathScale"];
  const wrong = names.filter((n, i) => f6(scalar(b, n)) !== c[7 + i]);
  check(wrong.length === 0,
    wrong.length ? `${label} disagrees on Android about ${wrong.join(", ")}` : `${label} agrees on every measurement on Android`);
}

// ── The expected values MochiShapeTest.kt runs the Kotlin functions against ──

const test = readFileSync(TEST, "utf8");
const hashes = [...test.matchAll(/hash\((-?\d+), (-?\d+), ([0-9.]+)\)/g)];
check(hashes.length >= 5 && hashes.every((m) => {
  const v = furHash(Number(m[1]), Number(m[2]) >>> 0);
  return Math.abs(v - Number(m[3])) < 1e-9;
}), `the Kotlin test expects TypeScript's fur hash (${hashes.length} values)`);
const samples = [...test.matchAll(/sample\((\d+), (\d+), (\d+)\)/g)];
check(samples.length >= 5 && samples.every((m) => furSample(Number(m[1]), Number(m[2])) === Number(m[3])),
  `the Kotlin test expects TypeScript's plush tile (${samples.length} values)`);
const anchors = [...test.matchAll(/anchor\(MochiShape\.([A-Z]+), (-?[0-9.]+), ([0-9.]+)\)/g)];
check(anchors.length >= 4 && anchors.every((m) => {
  const g = MOCHI_SHAPE_TABLE[m[1].toLowerCase() as keyof typeof MOCHI_SHAPE_TABLE];
  return Math.abs(anchorRadius(Number(m[2]), g) - Number(m[3])) < 1e-9;
}), `the Kotlin test expects TypeScript's anchor lookup (${anchors.length} values)`);
void MOCHI_SHAPE_LABEL;

console.log("");
if (failures > 0) {
  console.log(`${failures} failed.`);
  process.exit(1);
}
console.log("Android body tables agree with Swift.");
