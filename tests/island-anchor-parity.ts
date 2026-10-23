// The TypeScript anchor rules, checked against the Swift ones.
//
// IslandAnchor.swift and core/anchor.ts are a hand-kept pair, and a third port
// of the same arithmetic lives in Rust (island.rs). Where they disagree, Rust
// puts the window in one place and the page draws the island in another — an
// island that is not where it looks, which is an island nobody can click. The
// Swift suite dumps its table and this compares, so drift is a failing build.
//
// Run by scripts/test-island-anchor.sh, which supplies TABLE.

import { readFileSync } from "node:fs";
import {
  anchorFor, islandX, islandY, positionForDrop, type Metrics,
} from "../windows/src/core/anchor.ts";

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

const rows = readFileSync(process.env.TABLE!, "utf8")
  .trim().split("\n").map((line) => line.split("\t"));

const area = rows.find((r) => r[0] === "area")!;
const [areaW, areaH] = [Number(area[1]), Number(area[2])];

const met = rows.find((r) => r[0] === "metrics")!;
const m: Metrics = {
  restW: Number(met[1]), restH: Number(met[2]),
  panelW: Number(met[3]), panelH: Number(met[4]),
};

console.log("\nThe island lands where Swift says it does");

for (const row of rows.filter((r) => r[0] === "drop")) {
  const [, name, x, y, stored, edge, align, hug, winX, winY, offX, offY, ix, iy] = row;

  const mine = positionForDrop(Number(x), Number(y), areaW, areaH, m);
  check(mine === stored, `${name} → ${stored}${mine === stored ? "" : ` (got ${mine})`}`);

  const a = anchorFor(stored, areaW, areaH, m);
  const same =
    a.edge === edge &&
    a.align === align &&
    (a.hug ?? "-") === hug &&
    num(a.free?.winX) === winX &&
    num(a.free?.winY) === winY &&
    num(a.free?.offX) === offX &&
    num(a.free?.offY) === offY &&
    num(islandX(a, 640, m)) === ix &&
    num(islandY(a, 160, m)) === iy;
  check(same, `${name} — placed the same`);
}

/** Swift prints CGFloats as "580.0"; match that rather than compare strings loosely. */
function num(v: number | undefined): string {
  if (v === undefined) return "-";
  return Number.isInteger(v) ? `${v}.0` : String(v);
}

console.log(failures === 0 ? "\nAll good." : `\n${failures} failed.`);
process.exit(failures === 0 ? 0 : 1);
