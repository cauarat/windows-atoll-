// What Copy copies, on Windows, checked against the Mac.
//
// `MessageCopy.content` and `core/messageCopy.ts`'s `copyKind` are a
// hand-kept pair. A pair that drifts is a card that offers Copy on one
// platform and not the other, or copies "📎 Sent a file" where the other
// copies nothing.
//
// Run by scripts/test-message-copy.sh, which supplies TABLE.

import { readFileSync } from "node:fs";
import { copyKind } from "../windows/src/core/messageCopy.ts";

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

const rows = readFileSync(process.env.TABLE!, "utf8").trim().split("\n").map((line) => line.split("\t"));

console.log("\nA card copies here what Swift says it copies");

for (const [encoded, hasPhoto, hasAudio, expected] of rows) {
  const text = encoded === "<nil>" ? null : encoded.replace(/\\n/g, "\n");
  const message = {
    text,
    photo: hasPhoto === "true" ? { fileId: "abc" } : null,
    audio: hasAudio === "true" ? { storageFileId: "s1" } : null,
  };
  const mine = copyKind(message) ?? "none";
  check(mine === expected,
        `text ${JSON.stringify(text)}, photo ${hasPhoto}, audio ${hasAudio} → ${expected}`
        + (mine === expected ? "" : ` (got ${mine})`));
}

console.log("");
if (failures === 0) console.log("All good.");
else { console.log(`${failures} failed.`); process.exit(1); }
