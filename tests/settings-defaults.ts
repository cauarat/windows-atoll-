// The Windows front end's corner of tests/fixtures/settings-defaults.json.
//
// The fixture writes down where a fresh install starts, once, for both
// platforms, and tests/SettingsDefaultsTests.swift holds the Mac to it. This
// holds DEFAULT_SETTINGS in windows/src/core/state.ts to the same file — the
// defaults the settings window and the island fall back on before Rust has
// answered, and the ones a field missing from settings.json reads as. Rust's
// own Default is held to it by settings_defaults_test.rs, under cargo test.
// It also holds the front end's field list to settings.rs's, since the page
// writes the whole object back.
//
// Run by scripts/test-settings-defaults.sh.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import * as State from "../windows/src/core/state.ts";

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

interface Fixture {
  defaults: Record<string, unknown>;
  ranges: Record<string, [number, number]>;
  settingsWindow: Record<string, number>;
  platformForced: Record<string, { mac: unknown; windows: unknown; why: string }>;
}
const fixture = JSON.parse(
  readFileSync(join(import.meta.dirname, "fixtures/settings-defaults.json"), "utf8"),
) as Fixture;

const defaults = State.DEFAULT_SETTINGS as unknown as Record<string, unknown>;
const show = (v: unknown) => (v === undefined ? "missing" : JSON.stringify(v));

console.log("\nA fresh Windows install starts where the Mac does");

for (const [key, want] of Object.entries(fixture.defaults)) {
  const got = defaults[key];
  check(got === want, `${key} is ${show(want)}${got === want ? "" : ` (DEFAULT_SETTINGS: ${show(got)})`}`);
}

console.log("\nWhere it differs, on purpose");

for (const [key, forced] of Object.entries(fixture.platformForced)) {
  const got = defaults[key];
  check(
    got === forced.windows,
    `${key} is ${show(forced.windows)} — ${forced.why}${got === forced.windows ? "" : ` (DEFAULT_SETTINGS: ${show(got)})`}`,
  );
}

// The fields' limits are inline in the settings panes today, so there is
// nothing importable to compare; the Mac's half checks them. Exported as
// SETTINGS_RANGES from state.ts (field → [min, max]), they are checked here.
const ranges = (State as Record<string, unknown>).SETTINGS_RANGES as
  Record<string, readonly [number, number]> | undefined;
console.log("\nThe fields accept the same numbers");
if (!ranges) {
  console.log("  – not checked: windows/src/core/state.ts exports no SETTINGS_RANGES yet");
} else {
  for (const [key, [min, max]] of Object.entries(fixture.ranges)) {
    const got = ranges[key];
    const same = got !== undefined && got[0] === min && got[1] === max;
    check(same, `${key} takes ${min}…${max}${same ? "" : ` (Windows: ${got ? got.join("…") : "missing"})`}`);
  }
}

// The front end writes the whole object back through save_settings, so a
// field one side has and the other does not is either dropped on every save or
// never shown at all. Rust's own names, camel-cased as serde writes them,
// against DEFAULT_SETTINGS — which has to name every field of Settings.
console.log("\nThe front end and Rust carry the same fields");
const rust = readFileSync(
  join(import.meta.dirname, "..", "windows/src-tauri/src/settings.rs"), "utf8",
);
const struct = rust.slice(rust.indexOf("pub struct Settings {"));
const body = struct.slice(0, struct.indexOf("\n}\n"));
const rustKeys = [...body.matchAll(/^\s*pub (\w+):/gm)]
  .map(([, name]) => name.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase()));
const tsKeys = Object.keys(defaults);
const onlyRust = rustKeys.filter((k) => !tsKeys.includes(k));
const onlyTs = tsKeys.filter((k) => !rustKeys.includes(k));
check(rustKeys.length > 30, `read ${rustKeys.length} fields from settings.rs`);
check(onlyRust.length === 0, `every settings.rs field is in DEFAULT_SETTINGS${onlyRust.length ? ` (missing: ${onlyRust.join(", ")})` : ""}`);
check(onlyTs.length === 0, `every DEFAULT_SETTINGS field is in settings.rs${onlyTs.length ? ` (missing: ${onlyTs.join(", ")})` : ""}`);

console.log(failures === 0 ? "\nAll good." : `\n${failures} failed.`);
process.exit(failures === 0 ? 0 : 1);
