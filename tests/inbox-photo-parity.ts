// The TypeScript photo sizes, checked against the Swift ones.
//
// `InboxPhoto.displaySize` and `core/layout.ts`'s `photoDisplaySize` are a
// hand-kept pair, and the card grows by what they answer. A pair that drifts
// is a photo drawn taller than the card made room for on one platform, with
// the reply bar pushed off the island.
//
// Run by scripts/test-inbox-photo.sh, which supplies TABLE.

import { readFileSync } from "node:fs";
import { photoDisplaySize } from "../windows/src/core/layout.ts";

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

const rows = readFileSync(process.env.TABLE!, "utf8")
  .trim().split("\n").map((line) => line.split("\t").map(Number));

console.log("\nA photo is drawn the size here that Swift says it is");

for (const [pw, ph, maxWidth, w, h] of rows) {
  const mine = photoDisplaySize(pw, ph, maxWidth);
  const ok = mine.w === w && mine.h === h;
  check(ok, `${pw}×${ph} in ${maxWidth} → ${w}×${h}` + (ok ? "" : ` (got ${mine.w}×${mine.h})`));
}

console.log("");
if (failures === 0) console.log("All good.");
else { console.log(`${failures} failed.`); process.exit(1); }
