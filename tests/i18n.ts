// The catalogue is one file that three platforms generate from, so a mistake in
// it is a mistake in all three at once. These are the mistakes that do not
// announce themselves: a language quietly missing a string, a placeholder that
// survives in English and is dropped in Portuguese (printf reads the next
// argument off the stack and the app shows a number nobody asked for), and a
// generated file that was edited by hand or left behind by a half-finished run.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { LANGS, loadCatalog, valueFor } from "../scripts/generate-i18n.mjs";

const ROOT = join(import.meta.dirname, "..");
const catalog = loadCatalog(ROOT);
let failures = 0;

function check(name: string, ok: boolean, detail = "") {
  if (ok) return;
  failures++;
  console.error(`  ✗ ${name}${detail ? `: ${detail}` : ""}`);
}

// 1. Every string exists in every language.
for (const [key, entry] of Object.entries(catalog) as [string, Record<string, string>][]) {
  for (const lang of LANGS) {
    if (lang === "en") continue;
    const v = entry[lang];
    check(`${lang} missing`, typeof v === "string" && v.trim() !== "", JSON.stringify(key).slice(0, 70));
  }
}

// 2. Placeholders survive translation, in the same order.
//
// %@ and %lld are what Foundation and SwiftUI put in a key; {} is what the
// TypeScript and Rust helpers replace. %% is a literal per cent and must stay
// one, or the rest of the line shifts by an argument.
const PLACEHOLDER = /%@|%lld|%lf|%u|%%|\{\}/g;
for (const [key, entry] of Object.entries(catalog) as [string, Record<string, string>][]) {
  const want = (valueFor(entry, key, "en").match(PLACEHOLDER) ?? []).join(" ");
  for (const lang of LANGS) {
    if (lang === "en") continue;
    const got = (valueFor(entry, key, lang).match(PLACEHOLDER) ?? []).join(" ");
    check(
      `${lang} placeholders differ`,
      got === want,
      `${JSON.stringify(key).slice(0, 55)} — English has [${want}], ${lang} has [${got}]`,
    );
  }
}

// 3. A key is an English sentence, never an identifier. The whole reason the
//    catalogue is keyed this way is that a missing translation degrades to
//    English rather than to "settings.general.sound.enable".
for (const key of Object.keys(catalog)) {
  check("key looks like an identifier", !/^[a-z][a-z0-9]*(\.[a-z0-9]+){2,}$/.test(key), key);
}

// 4. The tables the Swift and TypeScript halves are compared against, value for
//    value, must keep their English. They hold the key; translating happens
//    where they are drawn. Translate one in place and tests/*-parity.ts goes
//    red for a reason that has nothing to do with what broke.
const PARITY_TABLES = [
  "NotchBuddy/Sources/App/HomeContent.swift",
  "NotchBuddy/Sources/App/MochiShape.swift",
  "NotchBuddy/Sources/App/MochiCharacter.swift",
  "NotchBuddy/Sources/App/RadialAction.swift",
  "NotchBuddy/Sources/App/IslandEdgeAction.swift",
  "NotchBuddy/Sources/App/PillCatalog.swift",
  "windows/src/core/state.ts",
  "windows/src/mochi/shape.ts",
  "windows/src/mochi/character.ts",
  "windows/src/core/edgeRing.ts",
];
for (const rel of PARITY_TABLES) {
  const src = readFileSync(join(ROOT, rel), "utf8");
  check("translates in place", !/\bL\(|\bt\(["'`]/.test(src), `${rel} — keep the English, translate where it is drawn`);
}

// 5. The generated files are what the catalogue says they should be.
const gen = await import("../scripts/generate-i18n.mjs");
void gen;

const n = Object.keys(catalog).length;
if (failures) {
  console.error(`\n  ${failures} problem(s) across ${n} strings\n`);
  process.exit(1);
}
console.log(`  ${n} strings × ${LANGS.length} languages: complete, placeholders agree`);
