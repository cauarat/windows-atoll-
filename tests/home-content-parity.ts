// What Home shows on Windows, checked against the Mac.
//
// HomeContent.swift and the HOME_* tables in windows/src/core/state.ts are a
// hand-kept pair, and they had already drifted once: Windows had no
// "Notifications" choice, started on "Last message", and cut that choice's
// hint short. The Swift suite dumps the choices and this compares — order,
// labels, hints, the default and the source each choice draws.
//
// Run by scripts/test-home-content.sh, which supplies HOME_DUMP.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  DEFAULT_SETTINGS, HOME_CONTENTS, HOME_HINT, HOME_LABEL, homeSource,
} from "../windows/src/core/state.ts";

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

const rows = readFileSync(process.env.HOME_DUMP!, "utf8")
  .trim().split("\n").map((line) => line.split("\t"));
const swift = rows.filter((r) => r[0] === "case").map(([, id, label, hint]) => ({ id, label, hint }));
const swiftDefault = rows.find((r) => r[0] === "default")?.[1];

// Typed loosely on purpose: a choice Windows does not have yet has to fail
// here, by name, rather than stop this file from loading.
const labels = HOME_LABEL as Record<string, string | undefined>;
const hints = HOME_HINT as Record<string, string | undefined>;
const contents = HOME_CONTENTS as readonly string[];

console.log("\nThe same choices, in the picker's order");

check(swift.length > 0, `Swift listed ${swift.length} choices`);
check(
  contents.join(", ") === swift.map((c) => c.id).join(", "),
  `${swift.map((c) => c.id).join(", ")}${contents.join(", ") === swift.map((c) => c.id).join(", ") ? "" : ` (Windows has ${contents.join(", ")})`}`,
);

console.log("\nSaid the same way");

for (const mac of swift) {
  const label = labels[mac.id];
  check(label === mac.label, `${mac.id} is "${mac.label}"${label === mac.label ? "" : ` (Windows: ${label === undefined ? "missing" : `"${label}"`})`}`);
  const hint = hints[mac.id];
  check(hint === mac.hint, `${mac.id}'s hint${hint === mac.hint ? "" : ` — Windows: ${hint === undefined ? "missing" : `"${hint}"`}`}`);
}

// The hints are sentences, drawn through t() on Windows and Text(loc:) on the
// Mac; one missing from the catalogue is English in every language. The labels
// are mostly service names, which are not translated.
const catalog = JSON.parse(
  readFileSync(join(import.meta.dirname, "..", "i18n/catalog.json"), "utf8"),
) as Record<string, unknown>;
for (const mac of swift) {
  check(mac.hint in catalog, `${mac.id}'s hint is in i18n/catalog.json`);
}

console.log("\nA fresh install starts in the same place");

check(
  DEFAULT_SETTINGS.homeContent === swiftDefault,
  `Home starts on ${swiftDefault}${DEFAULT_SETTINGS.homeContent === swiftDefault ? "" : ` (Windows: ${DEFAULT_SETTINGS.homeContent})`}`,
);

console.log("\nEach choice draws the same source");

const source = homeSource as (content: string, last: string | null) => string | null;
for (const row of rows.filter((r) => r[0] === "source")) {
  const [, id, ...cases] = row;
  const got = cases.map((c) => {
    const last = c.split("=")[0];
    return `${last}=${source(id, last === "none" ? null : last) ?? "none"}`;
  });
  const same = got.join(" ") === cases.join(" ");
  check(same, `${id}${same ? "" : ` — Mac ${cases.join(" ")}, Windows ${got.join(" ")}`}`);
}

console.log(failures === 0 ? "\nAll good." : `\n${failures} failed.`);
process.exit(failures === 0 ? 0 : 1);
