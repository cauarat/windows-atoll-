// The TypeScript snow, checked against the Swift one.
//
// IslandSnow.swift and island/snow.ts are a hand-kept pair: the same bank, the
// same plough, the same sequence of thrown flakes. The Swift suite runs a
// script and dumps what it saw; this runs the same script and compares, so a
// constant changed on one side is a failing build rather than snow that
// behaves differently on Windows.
//
// Run by scripts/test-island-snow.sh, which supplies SNOW_DUMP.

import { readFileSync } from "node:fs";
import { SnowField, snowVisible, SNOW, snowDepth } from "../windows/src/island/snow.ts";

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

function sample(name: string, snow: SnowField, width: number): [string, number[]] {
  const values = [snow.depth, snow.openFor, snow.isSettled ? 1 : 0, snow.flakes.length];
  const [first, last] = snowVisible(width);
  for (let i = first; i <= last; i += 4) values.push(snow.height(i));
  for (const f of snow.flakes) values.push(f.x, f.y, f.vx, f.vy, f.life, f.size);
  return [name, values];
}

// The script. tests/IslandSnowTests.swift has the same steps, in the same
// order: change one and change the other.
function script(): [string, number[]][] {
  const lines: [string, number[]][] = [];
  const snow = new SnowField();
  const frame = 1 / 60;

  for (let i = 0; i < 40; i++) snow.step(0.5, 640, true, null);
  lines.push(sample("grown", snow, 640));

  for (let x = 120; x <= 520; x += 10) snow.step(frame, 640, true, { x, above: 3 });
  lines.push(sample("swept", snow, 640));

  for (let i = 0; i < 30; i++) snow.step(frame, 640, true, { x: 300, above: 2 });
  lines.push(sample("parted", snow, 640));

  for (let x = 500; x >= 100; x -= 16) snow.step(frame, 640, true, { x, above: 5 });
  lines.push(sample("swept-back", snow, 640));

  for (let i = 0; i < 180; i++) snow.step(frame, 640, true, null);
  lines.push(sample("refilling", snow, 640));

  for (let i = 0; i < 30; i++) snow.step(frame, 288, false, null);
  lines.push(sample("closed", snow, 288));
  return lines;
}

console.log("\nThe snow matches Swift");

const swift = readFileSync(process.env.SNOW_DUMP!, "utf8").trim().split("\n")
  .map((line) => line.split("\t"));
const mine = script();

check(swift.length === mine.length, `${mine.length} samples on both sides`);

for (const [i, [name, ...numbers]] of swift.entries()) {
  const [myName, values] = mine[i] ?? ["(missing)", []];
  if (name !== myName || numbers.length !== values.length) {
    check(false, `${name}: ${numbers.length} values in Swift, ${values.length} here (${myName})`);
    continue;
  }
  let worst = 0;
  numbers.forEach((n, k) => { worst = Math.max(worst, Math.abs(Number(n) - values[k])); });
  check(worst < 1e-6, `${name}: ${values.length} values agree (off by at most ${worst.toExponential(1)})`);
}

// The script has to have thrown something, or the comparison above proves
// nothing about the flakes.
const swept = mine.find(([name]) => name === "swept")!;
check(swept[1][3] > 0, `the sweep threw flakes (${swept[1][3]} in the air)`);
check(Math.abs(snowDepth(0) - SNOW.restDepth) < 1e-12, "the bank opens at the resting depth");

console.log("");
if (failures > 0) {
  console.log(`${failures} failed`);
  process.exit(1);
}
console.log("Island snow parity passed");
