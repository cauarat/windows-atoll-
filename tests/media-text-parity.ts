// The Now Playing title and artist cleaners on Windows, checked against the Mac.
//
// MediaText.swift and windows/src/core/mediaText.ts are a hand-kept pair. The
// Swift suite dumps what it makes of a fixed list of titles and artists, and
// this runs the same inputs through the TypeScript and compares.
//
// Run by scripts/test-media-text.sh, which supplies MEDIA_TEXT_DUMP.

import { readFileSync } from "node:fs";
import { shortArtist, shortTitle } from "../windows/src/core/mediaText.ts";

let failures = 0;
const rows = readFileSync(process.env.MEDIA_TEXT_DUMP!, "utf8")
  .split("\n").filter((line) => line.length > 0).map((line) => line.split("\t"));

console.log("MediaText parity");
for (const [kind, input, want] of rows) {
  const got = kind === "title" ? shortTitle(input) : shortArtist(input);
  const ok = got === want;
  console.log(`  ${ok ? "✓" : "✗"} ${kind} "${input}" → "${got}"${ok ? "" : ` (Mac: "${want}")`}`);
  if (!ok) failures++;
}
if (rows.length < 20) {
  console.log(`  ✗ only ${rows.length} rows in the dump`);
  failures++;
}

if (failures > 0) {
  console.log(`${failures} failed`);
  process.exit(1);
}
console.log("all passed");
