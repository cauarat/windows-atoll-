// The TypeScript message-card heights, checked against the Swift ones.
//
// `IslandView.messageHeight` and `core/layout.ts`'s `messageCardHeight` are a
// hand-kept pair, and the cap is worse than hand-kept: ChatGPT is a window of
// its own on Windows rather than a view in the island, so there is no local
// number for `MESSAGE_EXPANDED_CAP` to be derived from. It is the Mac's 650,
// copied. A copy that drifts is a card that stops growing at the wrong place
// on one platform, or grows past the window it is drawn in.
//
// Run by scripts/test-island-owner.sh, which supplies TABLE.

import { readFileSync } from "node:fs";
import { messageCardHeight } from "../windows/src/core/layout.ts";

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

const rows = readFileSync(process.env.TABLE!, "utf8")
  .trim().split("\n").map((line) => line.split("\t"));

console.log("\nThe message card is as tall here as Swift says it is");

for (const [attachments, notice, overflow, height] of rows) {
  const mine = messageCardHeight(Number(attachments), notice === "true", Number(overflow));
  const want = Number(height);
  check(
    mine === want,
    `${attachments} file(s), notice ${notice}, overflow ${overflow} → ${want}`
      + (mine === want ? "" : ` (got ${mine})`),
  );
}

console.log("");
if (failures === 0) console.log("All good.");
else { console.log(`${failures} failed.`); process.exit(1); }
