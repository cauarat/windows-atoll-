// Translating the strings the frontend draws.
//
// The table is generated into i18n.generated.ts from i18n/catalog.json by
// scripts/generate-i18n.mjs -- the same catalogue the Mac app and the Rust tray
// read. Nothing here holds a translation.
//
// Keys are the English sentence, not an identifier, so a string nobody has
// translated yet shows as English rather than as `settings.general.sound`.

import { CATALOG } from "./i18n.generated";

export type Language = "system" | "en" | "es" | "pt-BR";
export const LANGUAGES: Language[] = ["system", "en", "es", "pt-BR"];

/** Each language names itself, the way language menus do everywhere else. */
export const LANGUAGE_LABEL: Record<Language, string> = {
  system: "Same as system",
  en: "English",
  es: "Español",
  "pt-BR": "Português (Brasil)",
};

/**
 * A BCP-47 tag resolved to one of the three languages that exist.
 *
 * Portuguese from Portugal lands on the Brazilian strings rather than on
 * English: the two are close enough that the wrong Portuguese beats no
 * Portuguese. The same rule as AppLanguage.resolved on the Mac and
 * i18n::from_tag in Rust.
 */
export function fromTag(tag: string): Exclude<Language, "system"> {
  const t = (tag || "").toLowerCase();
  if (t.startsWith("pt")) return "pt-BR";
  if (t.startsWith("es")) return "es";
  return "en";
}

export function resolve(preference: Language | undefined): Exclude<Language, "system"> {
  if (preference && preference !== "system") return preference;
  return fromTag(navigator.language);
}

let current: Exclude<Language, "system"> = "en";

/** Returns true when the language actually changed, so callers know to redraw. */
export function setLanguage(preference: Language | undefined): boolean {
  const next = resolve(preference);
  if (next === current) return false;
  current = next;
  return true;
}

export function language(): Exclude<Language, "system"> {
  return current;
}

/**
 * The translation of `key`, with each placeholder replaced by `values` in order.
 *
 * The placeholders are `%@`, `%lld`, `%lf` and `%u`, and `%%` is a literal per
 * cent -- printf's, not this file's choice. A Swift literal compiles to a key
 * spelled that way, and the catalogue holds one key per sentence for all three
 * platforms, so this has to read the same spelling rather than invent its own.
 *
 * English is the key, so an untranslated string is still a sentence.
 */
const PLACEHOLDER = /%@|%lld|%lf|%u|%%/g;

export function t(key: string, ...values: (string | number)[]): string {
  const row = CATALOG[key];
  const text = (current !== "en" && row?.[current]) || key;
  let i = 0;
  return text.replace(PLACEHOLDER, (m) => (m === "%%" ? "%" : String(values[i++] ?? m)));
}
