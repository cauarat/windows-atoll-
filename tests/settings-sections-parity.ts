// The Windows Settings sidebar, checked against the Mac's.
//
// SettingsSection.swift and windows/src/settings/sections.ts are a hand-kept
// pair: the same rows in the same order, the same English titles (the
// catalogue keys), SF Symbols and tile colours. The Swift suite dumps its
// table and this compares, so a row added, moved or recoloured on one side
// only is a failing build rather than a window that looks almost right.
//
// It also holds the rows Windows hides to the panes that are not ported yet,
// and nothing else: a pending row is never drawn, and every other row is.
//
// Run by scripts/test-settings-sections.sh, which supplies SECTIONS_DUMP.

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import {
  DEFAULT_SECTION, PENDING, SETTINGS_SECTIONS, sectionId, visibleSections,
} from "../windows/src/settings/sections.ts";
import { SYMBOL_NAMES } from "../windows/src/settings/icons.ts";

const ROOT = join(import.meta.dirname, "..");

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

const rows = readFileSync(process.env.SECTIONS_DUMP!, "utf8")
  .trim().split("\n").map((line) => line.split("\t"));
const swift = rows.filter((r) => r[0] === "section")
  .map(([, id, title, symbol, color]) => ({ id, title, symbol, color }));
const swiftDefault = rows.find((r) => r[0] === "default")?.[1];

console.log("\nThe sidebar is the Mac's, row for row");

check(swift.length > 0, `Swift listed ${swift.length} rows`);
check(
  SETTINGS_SECTIONS.length === swift.length,
  `${swift.length} rows on both sides${SETTINGS_SECTIONS.length === swift.length ? "" : ` (Windows has ${SETTINGS_SECTIONS.length})`}`,
);
const order = (list: readonly { id: string }[]) => list.map((s) => s.id).join(", ");
check(order(SETTINGS_SECTIONS) === order(swift), `in the same order: ${order(swift)}`);

for (const mac of swift) {
  const win = SETTINGS_SECTIONS.find((s) => s.id === mac.id);
  if (!win) { check(false, `${mac.id} — missing on Windows`); continue; }
  const diffs: string[] = [];
  if (win.title !== mac.title) diffs.push(`title "${win.title}" ≠ "${mac.title}"`);
  if (win.symbol !== mac.symbol) diffs.push(`symbol ${win.symbol} ≠ ${mac.symbol}`);
  if (win.color !== mac.color) diffs.push(`colour ${win.color} ≠ ${mac.color}`);
  check(diffs.length === 0, `${mac.id}${diffs.length ? ` — ${diffs.join("; ")}` : ""}`);
}
for (const win of SETTINGS_SECTIONS) {
  if (!swift.some((s) => s.id === win.id)) check(false, `${win.id} — Windows only`);
}
check(DEFAULT_SECTION === swiftDefault, `opens on ${swiftDefault} when nothing else is asked for`);

console.log("\nOnly the panes not ported yet are hidden");

// Phase 1 of docs/parity: the radial menu is reworked on the Mac first
// (Phase 7) and AI Agents comes with its panel (Phase 5). Take an id out of
// here in the change that ports its pane, and out of PENDING with it.
const NOT_PORTED = ["radial", "aiagents"];

const pending = [...PENDING].sort();
check(
  pending.join(",") === [...NOT_PORTED].sort().join(","),
  `pending: ${NOT_PORTED.join(", ")}${pending.join(",") === [...NOT_PORTED].sort().join(",") ? "" : ` (Windows has ${pending.join(", ") || "none"})`}`,
);
const shown = visibleSections().map((s) => s.id);
for (const s of SETTINGS_SECTIONS) {
  const isPending = PENDING.has(s.id);
  check(
    shown.includes(s.id) === !isPending,
    `${s.id} is ${isPending ? "hidden" : "shown"}${shown.includes(s.id) === !isPending ? "" : " — it is not"}`,
  );
  check(
    sectionId(s.id) === (isPending ? null : s.id),
    `${s.id} ${isPending ? "cannot" : "can"} be opened by id`,
  );
}
check(
  shown.join(",") === SETTINGS_SECTIONS.filter((s) => !PENDING.has(s.id)).map((s) => s.id).join(","),
  "the rows shown keep the table's order",
);
check(sectionId("nope") === null, "an unknown id opens nothing");

// Every row drawn has a pane behind it, and a pending one has none: a row
// with nothing registered opens an empty page. Read from the source, because
// the settings modules build DOM when they load.
const registered = new Set<string>();
const settingsDir = join(ROOT, "windows/src/settings");
for (const file of walk(settingsDir)) {
  if (!file.endsWith(".ts")) continue;
  for (const m of readFileSync(file, "utf8").matchAll(/registerPane\(\s*["'`]([a-z]+)["'`]/g)) {
    registered.add(m[1]);
  }
}
check(
  registered.size > 0,
  "found the panes' registerPane(\"…\") calls — if they are registered another way, teach this test to read it",
);
for (const s of SETTINGS_SECTIONS) {
  const isPending = PENDING.has(s.id);
  check(
    registered.has(s.id) === !isPending,
    `${s.id} ${isPending ? "registers no pane" : "registers a pane"}${registered.has(s.id) === !isPending ? "" : " — it does not"}`,
  );
}
for (const id of registered) {
  if (!SETTINGS_SECTIONS.some((s) => s.id === id)) check(false, `registerPane("${id}") — no such row`);
}

console.log("\nEvery tile can be drawn, and every title translated");

for (const s of SETTINGS_SECTIONS) {
  check(SYMBOL_NAMES.includes(s.symbol), `${s.symbol} has an SVG in icons.ts`);
}
const catalog = JSON.parse(readFileSync(join(ROOT, "i18n/catalog.json"), "utf8")) as Record<string, unknown>;
for (const s of SETTINGS_SECTIONS) {
  check(s.title in catalog, `"${s.title}" is in i18n/catalog.json`);
}

console.log(failures === 0 ? "\nAll good." : `\n${failures} failed.`);
process.exit(failures === 0 ? 0 : 1);

function* walk(dir: string): Generator<string> {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) yield* walk(path);
    else yield path;
  }
}
