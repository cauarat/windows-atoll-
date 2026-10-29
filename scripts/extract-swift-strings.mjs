#!/usr/bin/env node
// Lists the user-visible strings in the Swift sources, as the catalogue keys
// they would need. Not part of the build: a drafting aid for whoever adds a
// language, and the way to find a string that was never put in i18n/catalog.json.

import { readFileSync, readdirSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { loadCatalog } from "./generate-i18n.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SRC = join(ROOT, "NotchBuddy", "Sources", "App");

/** Call sites whose first argument is shown to someone. */
const CALLS = [
  "Text", "Toggle", "Button", "GroupBox", "Picker", "TextField", "SecureField",
  "Label", "Section", "Link", "Stepper", "Menu",
];
const LABELLED = [
  "\\.help", "\\.navigationTitle", "\\.accessibilityLabel", "(?<![A-Za-z0-9_])L",
  "SettingsSidebarRow\\(title:", "addItem\\(withTitle:", "\\.title = ",
];

/** Reads the parenthesised argument that starts at `open`, skipping strings. */
function argOf(s, open) {
  let depth = 0;
  for (let i = open; i < s.length; i++) {
    const c = s[i];
    if (c === '"') { i++; while (i < s.length && s[i] !== '"') i += s[i] === "\\" ? 2 : 1; }
    else if (c === "(") depth++;
    else if (c === ")") { if (--depth === 0) return s.slice(open + 1, i); }
  }
  return null;
}

/** "a" + "b" -> ab, and \(expr) -> the placeholder that ends up in the key.
 *
 * SwiftUI and Foundation disagree about one character: a literal % is doubled
 * in a LocalizedStringKey and left alone in a String.LocalizationValue, so a
 * Text and an L() of the same sentence are two different keys. `swiftUI` says
 * which rule this call site follows.
 */
function keyOf(arg, swiftUI = true) {
  const t = arg.replace(/^\s*(loc|verbatim):\s*/, "").trim();
  if (!t.startsWith('"')) return null;
  let key = "", i = 0;
  while (i < t.length) {
    if (t[i] !== '"') { if (!/[\s+]/.test(t[i])) return null; i++; continue; }
    i++;
    while (i < t.length && t[i] !== '"') {
      if (t[i] === "\\" && t[i + 1] === "(") {
        let d = 0, j = i + 1;
        for (; j < t.length; j++) { if (t[j] === "(") d++; else if (t[j] === ")" && --d === 0) break; }
        const expr = t.slice(i + 2, j);
        key += /count|index|\bInt\b|statusCode|minutes|\.count\b/.test(expr) ? "%lld" : "%@";
        i = j + 1;
      } else if (t[i] === "\\") { key += { n: "\n", t: "\t", '"': '"', "\\": "\\" }[t[i + 1]] ?? t[i + 1]; i += 2; }
      else { key += t[i] === "%" && swiftUI ? "%%" : t[i]; i++; }
    }
    i++;
  }
  return key;
}

const catalog = loadCatalog(ROOT);
const only = process.argv[2];
const callRe = new RegExp(`\\b(?:${CALLS.join("|")})\\(`, "g");
const labRe = new RegExp(`(?:${LABELLED.join("|")})\\s*`, "g");
const rows = new Map();

for (const f of readdirSync(SRC).filter((f) => f.endsWith(".swift"))) {
  if (f === "Localized.swift" || f === "AppLanguage.swift") continue;  // the helpers' own doc comments
  if (only && !f.toLowerCase().includes(only.toLowerCase())) continue;
  const s = readFileSync(join(SRC, f), "utf8");
  const take = (arg, swiftUI = true) => {
    const k = keyOf(arg ?? "", swiftUI);
    if (!k || !/[A-Za-z]/.test(k) || k.length < 2) return;
    if (!rows.has(k)) rows.set(k, basename(f));
  };
  for (const m of s.matchAll(callRe)) take(argOf(s, m.index + m[0].length - 1));
  for (const m of s.matchAll(labRe)) {
    const rest = s.slice(m.index + m[0].length);
    const foundation = m[0] === "L";
    if (rest.startsWith('"')) take(rest.slice(0, rest.indexOf('"', 1) + 1), !foundation);
    else if (rest.startsWith("(")) take(argOf(rest, 0), !foundation);
  }
}

const missing = [...rows].filter(([k]) => !(k in catalog));
for (const [k, f] of missing) console.log(`${f}\t${JSON.stringify(k)}`);
console.error(`\n  ${rows.size} keys found, ${rows.size - missing.length} already translated, ${missing.length} missing`);
