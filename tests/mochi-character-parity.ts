// The TypeScript character rules, checked against the Swift ones.
//
// MochiCharacter.swift and mochi/character.ts are a hand-kept pair, and the
// preset grid is exactly the kind of table where one side gains an entry and
// nobody notices for a release. The Swift suite dumps its catalogue and this
// compares, so drift is a failing build rather than a bug report.
//
// Run by scripts/test-mochi-character.sh, which supplies CATALOG.

import { readFileSync } from "node:fs";
import {
  CHARACTER_PRESETS, ACCESSORIES, EYES, resolveEye, isSpanning, isNeutral,
  characterToStorage, characterFromStorage, sameCharacter, presetMatching,
  type MochiEye,
} from "../windows/src/mochi/character.ts";
import type { EyeShape } from "../windows/src/mochi/engine.ts";

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

const EXPRESSIVE: EyeShape[] =
  ["dot", "line", "flat", "happy", "closed", "spiral", "heart", "star", "tired", "wink", "cup"];
const ALL: EyeShape[] = [...EXPRESSIVE, "pill", "wide"];

// ── The same eighteen, in the same order ─────────────────────────────────────

console.log("\nThe grid matches Swift");

const swift = readFileSync(process.env.CATALOG!, "utf8")
  .trim().split("\n").map((line) => line.split("\t"));

check(swift.length === CHARACTER_PRESETS.length,
      `${CHARACTER_PRESETS.length} presets on both sides`);

for (const [i, [id, name, storage]] of swift.entries()) {
  const mine = CHARACTER_PRESETS[i];
  check(mine?.id === id && mine?.name === name && characterToStorage(mine.character) === storage,
        `#${i + 1} ${name} — ${storage}`);
}

// ── The rules behave the same ────────────────────────────────────────────────

console.log("\nThe eye rule");

check(ACCESSORIES.length === 8 && EYES.length === 6, "eight accessories and six eye styles");
check(ALL.every((s) => resolveEye({}, s).kind === "plain"),
      "classic Mochi passes every shape straight through");
check(isNeutral("pill") && isNeutral("wide") && EXPRESSIVE.every((s) => !isNeutral(s)),
      "only pill and wide count as neutral");

for (const eye of EYES.filter((e) => !isSpanning(e))) {
  const c = { eye };
  check(resolveEye(c, "pill").kind === "character", `${eye} replaces the neutral pill`);
  const wide = resolveEye(c, "wide");
  check(wide.kind === "character" && wide.wide, `${eye} keeps approval's enlargement`);
  check(EXPRESSIVE.every((s) => resolveEye(c, s).kind === "plain"),
        `${eye} leaves every expression alone`);
}

for (const eye of EYES.filter(isSpanning)) {
  check(ALL.every((s) => {
    const r = resolveEye({ eye }, s);
    return r.kind === "behindLens" && r.shape === s;
  }), `${eye} stays on through all thirteen shapes, with each drawn as the glint`);
}

const shades: MochiEye = "shades";
check(resolveEye({ eye: shades }, "closed").kind === "behindLens",
      "a bot in sunglasses does not take them off to fall asleep");
check(resolveEye({ eye: shades }, "spiral").kind === "behindLens",
      "a bot in sunglasses does not take them off when it gets dizzy");

// ── Storage ──────────────────────────────────────────────────────────────────

console.log("\nStorage");

for (const p of CHARACTER_PRESETS) {
  check(sameCharacter(characterFromStorage(characterToStorage(p.character)), p.character),
        `${p.name} survives a round trip`);
  check(presetMatching(p.character)?.id === p.id, `${p.name} is found again from its character`);
}
check(presetMatching({ accessory: "crown", eye: "sleepy" }) === null,
      "a combination nobody named matches no preset");

for (const junk of ["", "-", ":", "wizardHat:lasers", "crown", "crown:", ":glossy", "::", "a:b:c"]) {
  const c = characterFromStorage(junk);
  const ok = (c.accessory === null || ACCESSORIES.includes(c.accessory!))
          && (c.eye === null || EYES.includes(c.eye!));
  check(ok, `"${junk}" parses to something drawable`);
}

console.log("");
if (failures) {
  console.log(`${failures} failure(s).`);
  process.exit(1);
}
console.log("TypeScript character rules agree with Swift.");
