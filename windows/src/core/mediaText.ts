// What the player trims off a title and an artist before the card and the pill
// show them — the twin of `MediaText.swift`, kept in step by
// scripts/test-media-text.sh.
//
// "Song - 2011 Remaster (Live)" is the song, and "Drake feat. Rihanna" is
// Drake: the card has one line for each, and the pill's name is the title.

/** Swift's `.whitespaces`: tab and the Unicode space separators, not newlines. */
const EDGES = /^[\t\p{Zs}]+|[\t\p{Zs}]+$/gu;

function trimSpaces(s: string): string {
  return s.replace(EDGES, "");
}

/** Cut at the first " - ", then strip trailing (…) and […] groups for as long
 *  as something is left. A title that would come out empty stays as it was. */
export function shortTitle(raw: string): string {
  if (raw === "") return raw;
  let s = raw;
  const dash = s.indexOf(" - ");
  if (dash >= 0) s = s.slice(0, dash);
  for (;;) {
    const t = trimSpaces(s);
    const last = t.slice(-1);
    if (last !== ")" && last !== "]") break;
    const idx = t.lastIndexOf(last === ")" ? "(" : "[");
    if (idx < 0) break;
    const candidate = trimSpaces(t.slice(0, idx));
    if (candidate === "") break;
    s = candidate;
  }
  const result = trimSpaces(s);
  return result === "" ? raw : result;
}

/** Cut at " feat." or " ft.", in any case. */
export function shortArtist(raw: string): string {
  if (raw === "") return raw;
  const lower = raw.toLowerCase();
  for (const tag of [" feat.", " ft."]) {
    const at = lower.indexOf(tag);
    if (at >= 0) {
      const result = trimSpaces(raw.slice(0, at));
      return result === "" ? raw : result;
    }
  }
  return raw;
}
