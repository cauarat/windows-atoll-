// Who Mochi is talking to, and what time of day it is for them.
//
// The rules of NotchBuddy/Sources/App/UserIdentity.swift, line for line:
// tests/welcome-parity.ts runs the Swift suite's inputs through these and fails
// on the first answer that differs. No imports, so that test can load this file
// in plain Node.

export type DayPeriod = "morning" | "afternoon" | "evening";

/**
 * The part of the day a greeting belongs to, by the clock on the wall. Three, not
 * four: "boa noite" / "buenas noches" run from nightfall until morning, and "good
 * night" is a goodbye, not a hello.
 */
export function dayPeriod(hour: number): DayPeriod {
  if (hour >= 5 && hour < 12) return "morning";
  if (hour >= 12 && hour < 18) return "afternoon";
  return "evening";
}

/**
 * The greeting's catalogue keys, in English. Translated where they are drawn —
 * `t(GREETING_KEYS[p].named, name)` — like every other table the parity tests read.
 */
export const GREETING_KEYS: Record<DayPeriod, { named: string; bare: string }> = {
  morning: { named: "Good morning, %@!", bare: "Good morning!" },
  afternoon: { named: "Good afternoon, %@!", bare: "Good afternoon!" },
  evening: { named: "Good evening, %@!", bare: "Good evening!" },
};

/** The most a typed name keeps — the Mac's `maxTypedUserNameLength`. */
export const MAX_TYPED_NAME = 40;
const MAX_FULL_NAME = 32;

/**
 * User-perceived characters, which is what Swift counts and cuts by. Code units
 * would split an accent typed as a combining mark from its letter.
 */
function graphemes(s: string): string[] {
  const Segmenter = (Intl as unknown as {
    Segmenter?: new (locale?: string, options?: { granularity: "grapheme" }) => {
      segment(input: string): Iterable<{ segment: string }>;
    };
  }).Segmenter;
  if (typeof Segmenter === "function") {
    return Array.from(new Segmenter(undefined, { granularity: "grapheme" }).segment(s), (g) => g.segment);
  }
  return Array.from(s);
}

/**
 * The name the user typed, as Mochi will say it: no space at either end, single
 * spaces inside, at most MAX_TYPED_NAME characters. Null when nothing is left, so
 * an empty field falls through to the account's name.
 */
export function cleanUserName(raw: string | null | undefined): string | null {
  if (raw == null) return null;
  const words = raw.split(/\p{White_Space}+/u).filter((w) => w !== "");
  if (words.length === 0) return null;
  const capped = graphemes(words.join(" ")).slice(0, MAX_TYPED_NAME).join("").trim();
  return capped === "" ? null : capped;
}

const isHandleMarker = (g: string) => /^\p{N}/u.test(g) || (g.length === 1 && "._-@".includes(g));
const isNamePart = (g: string) => /^\p{Alphabetic}/u.test(g) || g === "'" || g === "-";

/**
 * A single lowercase word, or one carrying digits or separators, is an account
 * handle rather than a name — "joaos", "t.riant2".
 */
function looksLikeLoginHandle(name: string): boolean {
  if (name.includes(" ")) return false;
  return name === name.toLowerCase() || graphemes(name).some(isHandleMarker);
}

/**
 * The first name in an account's full name, or null when it is not something you
 * would greet someone by. "Théodore Riant" gives "Théodore"; "theodoreriant" gives
 * null, because "Hey theodoreriant!" reads worse than no name at all.
 */
export function firstNameFromFullName(raw: string | null | undefined): string | null {
  if (raw == null) return null;
  const full = raw.trim();
  if (full === "" || graphemes(full).length > MAX_FULL_NAME) return null;
  if (looksLikeLoginHandle(full)) return null;
  const first = full.split(" ").find((w) => w !== "");
  if (!first || !graphemes(first).every(isNamePart)) return null;
  return first;
}

/**
 * What Mochi calls the user: the name they typed, or failing that the first name
 * in the account's, or null — and then the greeting has no name in it.
 */
export function greetingName(typed: string | null | undefined, accountName: string | null | undefined): string | null {
  return cleanUserName(typed) ?? firstNameFromFullName(accountName);
}
