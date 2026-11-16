// Whose face the island wears, Windows against the Mac.
//
// `IslandOwner.swift` and `windows/src/core/owner.ts` are a hand-kept pair. On
// the Mac an Ato card wears Ato whichever pill was clicked last; the Windows
// island used to take the face from focus alone, so the same card wore the
// focused pill's Mochi. Every combination the Swift side prints is asked again
// here and has to come back the same.
//
// Run by scripts/test-island-owner.sh, which supplies OWNERS.

import { readFileSync } from "node:fs";
import { islandOwner } from "../windows/src/core/owner.ts";
import type { IslandViewName } from "../windows/src/core/layout.ts";

const lines = readFileSync(process.env.OWNERS!, "utf8").trimEnd().split("\n");
const wrong: string[] = [];
const opt = (s: string) => (s === "-" ? null : s);
for (const line of lines) {
  const [view, list, all, active, focus, want] = line.split("\t");
  const o = islandOwner(view as IslandViewName, opt(list), all === "1", opt(active), opt(focus));
  const got = o.kind === "pill" ? o.id : o.kind === "everyService" ? "*" : "-";
  if (got !== want) wrong.push(`${line} → ${got}`);
}
const ok = wrong.length === 0 && lines.length > 100;
console.log(`  ${ok ? "✓" : "✗"} Windows picks the same owner as the Mac in all ${lines.length} cases`);
for (const w of wrong.slice(0, 5)) console.log(`      ${w}`);
process.exit(ok ? 0 : 1);
