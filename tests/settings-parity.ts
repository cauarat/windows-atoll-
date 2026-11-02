// The settings window's shape, checked against the macOS one.
//
// Both platforms have very nearly the same settings; for a long time they did
// not put them in the same place, so the same preference lived under General on
// one and under Dynamic Island on the other. This compares the sidebar and the
// island's sub-tabs row for row, so that cannot happen again quietly.
//
// Node only, like tests/i18n.ts and for the same reason: this reads data, not
// code, and SettingsView.swift cannot be compiled on its own anyway.
//
// Run by scripts/test-settings-parity.sh.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  ISLAND_TABS, MAC_ONLY_SECTIONS, SETTINGS_SECTIONS,
} from "../windows/src/settings/sections.ts";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

const swift = (rel: string) => readFileSync(join(ROOT, rel), "utf8");

// ── What the Mac declares ─────────────────────────────────────────────────────

const settingsView = swift("NotchBuddy/Sources/App/SettingsView.swift");

interface MacRow { id: string; title: string; symbol: string; color: string }

const ROW = /SettingsSidebarRow\(title:\s*"([^"]+)",\s*icon:\s*"([^"]+)",\s*color:\s*"(#[0-9A-Fa-f]{6})"\)\s*\.tag\("([^"]+)"\)/g;
const macRows: MacRow[] = [...settingsView.matchAll(ROW)]
  .map(([, title, symbol, color, id]) => ({ id, title, symbol, color }));

const islandView = swift("NotchBuddy/Sources/App/IslandSettingsView.swift");
const TAB = /case\s+\.(layout|content|activity|behavior):\s*return\s+"([^"]+)"/g;
const macTabs = [...islandView.matchAll(TAB)].map(([, id, title]) => ({ id, title }));

console.log("\nThe settings window is the same on both platforms");

// Read first, compare second. A reformat of the Swift that defeats the regex
// must read as "the table could not be read", not as a silent pass.
check(macRows.length > 0, `read ${macRows.length} sidebar rows from SettingsView.swift`);
check(macTabs.length === 4, `read ${macTabs.length} island tabs from IslandSettingsView.swift`);
if (!macRows.length || macTabs.length !== 4) {
  console.error("\n  the Swift tables could not be read — the regexes above are stale\n");
  process.exit(1);
}

// ── The sidebar ───────────────────────────────────────────────────────────────

// Every exemption has to name a row the Mac actually still has. Without this
// the list quietly swallows any row somebody adds to it instead of to Windows.
for (const { id, why } of MAC_ONLY_SECTIONS) {
  check(macRows.some((r) => r.id === id), `"${id}" is exempt and still exists on the Mac — ${why}`);
}

const exempt = new Set(MAC_ONLY_SECTIONS.map((s) => s.id));
const expected = macRows.filter((r) => !exempt.has(r.id));

check(
  expected.length === SETTINGS_SECTIONS.length,
  `${SETTINGS_SECTIONS.length} sections here against ${macRows.length} on the Mac, less ${exempt.size} exempt`,
);

// Order matters as much as membership: a sidebar with the same rows in another
// order is still a window you have to learn twice.
for (const [i, mac] of expected.entries()) {
  const mine = SETTINGS_SECTIONS[i];
  if (!mine) {
    check(false, `row ${i + 1} — the Mac has "${mac.id}" and this platform has nothing`);
    continue;
  }
  const same = mine.id === mac.id
    && mine.title === mac.title
    && mine.symbol === mac.symbol
    && mine.color.toUpperCase() === mac.color.toUpperCase();
  check(same, same
    ? `${i + 1}. ${mac.title} — same id, title, symbol and colour`
    : `${i + 1}. expected ${JSON.stringify(mac)}, got ${JSON.stringify(
      { id: mine.id, title: mine.title, symbol: mine.symbol, color: mine.color })}`);
}

// ── The island's four tabs ────────────────────────────────────────────────────

check(
  macTabs.length === ISLAND_TABS.length,
  `${ISLAND_TABS.length} island tabs, as on the Mac`,
);
for (const [i, mac] of macTabs.entries()) {
  const mine = ISLAND_TABS[i];
  const same = mine && mine.id === mac.id && mine.title === mac.title;
  check(!!same, same
    ? `${mac.title} — same id and title`
    : `island tab ${i + 1}: expected ${mac.id}/${mac.title}, got ${mine?.id}/${mine?.title}`);
}

// ── Every declared section is actually drawn ──────────────────────────────────

// A row in the table with no pane behind it is a sidebar entry that opens
// nothing. The builders live in main.ts and importing it here would drag the
// DOM and @tauri-apps into this process, so this is textual, like check #4 in
// tests/i18n.ts.
const main = readFileSync(join(ROOT, "windows/src/settings/main.ts"), "utf8");
const panes = main.slice(main.indexOf("const PANES"), main.indexOf("function islandPane"));
for (const { id } of SETTINGS_SECTIONS) {
  check(new RegExp(`\\b${id}:`).test(panes), `${id} has a pane in main.ts`);
}

const n = SETTINGS_SECTIONS.length;
if (failures) {
  console.error(`\n  ${failures} problem(s) — the two settings windows have drifted apart\n`);
  process.exit(1);
}
console.log(`  ${n} sections × ${ISLAND_TABS.length} island tabs: the same window on both platforms`);
