// Who a Mochi is — port of MochiCharacter.swift.
//
// What sits on its head and what kind of eyes it has. Separate from everything
// the bot *does*: the state machine, the emotes and the mailbox morph go on
// driving the face exactly as before, and this only says what the face looks
// like when none of them is saying anything. That separation is the whole
// design — see `resolveEye`.
//
// The colour is deliberately not here. A Mochi's colour comes from the pill it
// belongs to, so the Ato bot keeps Ato's colour whichever
// character it wears and the pill border still matches the creature inside it.

import type { EyeShape } from "./engine";
import type { MochiShape } from "./shape";
export type { MochiShape } from "./shape";

/** What a Mochi wears. Null is bare-headed. */
export type MochiAccessory =
  | "catEars" | "horns" | "antenna" | "sprout" | "sparkles" | "bow" | "crown" | "beret";

/** The kind of eyes a Mochi has. */
export type MochiEye = "dot" | "glossy" | "pixel" | "sleepy" | "visor" | "shades";

/**
 * What a Mochi puts on for Christmas, one id per layer.
 *
 * A fourth axis laid over the other three rather than more entries in them: a
 * Santa hat is not an accessory the bow's code could draw, it is generated
 * artwork (festive.generated.ts) fitted to each body, and keeping it apart is
 * what lets every existing list, preset and tile stay exactly as it was.
 * `head` takes the accessory's place while it is set; `eyes` the eye's.
 */
export interface MochiFestive {
  head?: string;
  eyes?: string;
  texture?: string;
  extra?: string;
}

export interface MochiCharacter {
  accessory?: MochiAccessory | null;
  eye?: MochiEye | null;
  /** What it is shaped like. Absent is classic Mochi. */
  shape?: MochiShape | null;
  /** Christmas parts. Absent is none — which is how every character starts. */
  festive?: MochiFestive;
}

/** Classic Mochi: draws identically to the app before characters existed. */
export const CLASSIC: MochiCharacter = {};

export const ACCESSORIES: readonly MochiAccessory[] =
  ["catEars", "horns", "antenna", "sprout", "sparkles", "bow", "crown", "beret"];

export const EYES: readonly MochiEye[] =
  ["dot", "glossy", "pixel", "sleepy", "visor", "shades"];

/**
 * The bodies, by name.
 *
 * Written out here rather than imported from the generated table so this file
 * stays free of runtime imports — the parity test loads it under bare Node,
 * which cannot resolve the extensionless paths the bundler uses. The test
 * asserts this list against the generated one, so the two cannot drift.
 */
export const SHAPES: readonly MochiShape[] =
  ["round", "boxy", "fluffy", "pointy", "heart", "frog"];

/**
 * The Christmas ids, by layer.
 *
 * Hand-kept for the same reason `SHAPES` is: the catalogue lives in the
 * generated JSON, and importing it would give this file a runtime import. The
 * festive dev preview asserts these four against the generated catalogue and
 * says so in red when they drift.
 */
export const FESTIVE_HEADS: readonly string[] = [
  "santaHat", "elfHat", "elfEars", "antlers", "beanie", "topHat",
  "treeStar", "holly", "halo", "earmuffs", "giftBow",
];
export const FESTIVE_EYES: readonly string[] = [
  "starEye", "snowflake", "coal", "bauble", "peppermint", "bulb",
  "jolly", "treeGlasses", "wreathGlasses",
];
export const FESTIVE_TEXTURES: readonly string[] = [
  "sweater", "candyCane", "snowCap", "gingerbread", "giftWrap", "frost", "snowyPines",
];
export const FESTIVE_EXTRAS: readonly string[] = [
  "beard", "lights", "scarf", "snowfall", "redNose", "wreath", "bell", "carrot",
];

/** The four layers, in storage order. */
export const FESTIVE_SLOTS = ["head", "eyes", "texture", "extra"] as const;
export type FestiveSlot = (typeof FESTIVE_SLOTS)[number];

const FESTIVE_IDS: Record<FestiveSlot, readonly string[]> = {
  head: FESTIVE_HEADS, eyes: FESTIVE_EYES, texture: FESTIVE_TEXTURES, extra: FESTIVE_EXTRAS,
};

/** True when the character is wearing at least one Christmas part. */
export function hasFestive(character: MochiCharacter): boolean {
  const f = character.festive;
  return !!f && FESTIVE_SLOTS.some((slot) => !!f[slot]);
}

/**
 * The character with one Christmas layer changed, or taken off with null.
 *
 * Returns a character with no `festive` at all once the last part is gone, so
 * what gets stored is the same three-field string as before it wore anything.
 */
export function withFestive(
  character: MochiCharacter, parts: Partial<Record<FestiveSlot, string | null>>,
): MochiCharacter {
  const festive: MochiFestive = {};
  for (const slot of FESTIVE_SLOTS) {
    const value = slot in parts ? parts[slot] : character.festive?.[slot];
    if (value) festive[slot] = value;
  }
  const { festive: _old, ...rest } = character;
  return FESTIVE_SLOTS.some((slot) => festive[slot]) ? { ...rest, festive } : rest;
}

export function sameFestive(a: MochiCharacter, b: MochiCharacter): boolean {
  return FESTIVE_SLOTS.every((slot) => (a.festive?.[slot] ?? "") === (b.festive?.[slot] ?? ""));
}

/**
 * The glasses: frames worn over the eyes, so they stay on through every
 * expression exactly as the visor and the shades do.
 */
export function isFestiveEyewear(eyes: string | undefined): boolean {
  return eyes === "treeGlasses" || eyes === "wreathGlasses";
}

export const ACCESSORY_LABEL: Record<MochiAccessory, string> = {
  catEars: "Cat ears", horns: "Horns", antenna: "Antenna", sprout: "Sprout",
  sparkles: "Sparkles", bow: "Bow", crown: "Crown", beret: "Beret",
};

export const EYE_LABEL: Record<MochiEye, string> = {
  dot: "Dots", glossy: "Big and glossy", pixel: "Pixels",
  sleepy: "Sleepy", visor: "Visor", shades: "Sunglasses",
};

/**
 * Drawn before the body, so the silhouette swallows the base and the thing
 * looks like it grew there rather than being stuck on.
 */
export function isBehind(accessory: MochiAccessory): boolean {
  return accessory === "catEars" || accessory === "horns"
      || accessory === "antenna" || accessory === "sprout";
}

/**
 * True for the eyes that are worn rather than grown: one piece across both
 * sockets, always on, never replaced by an expression.
 */
export function isSpanning(eye: MochiEye): boolean {
  return eye === "visor" || eye === "shades";
}

/**
 * The two shapes that mean "nothing in particular is happening".
 *
 * `pill` is every calm state; `wide` is `approval`, which is calm but looking at
 * you. These are the only two a character's own eyes replace — everything else
 * is the bot expressing something and must survive.
 */
export function isNeutral(shape: EyeShape): boolean {
  return shape === "pill" || shape === "wide";
}

// ── The rule ──────────────────────────────────────────────────────────────────

export type EyeResolution =
  /** Draw the shape as the engine always has. */
  | { kind: "plain"; shape: EyeShape }
  /** Draw the character's own eyes. `wide` carries approval's enlargement. */
  | { kind: "character"; eye: MochiEye; wide: boolean }
  /** Draw the lens, with `shape` inside it as a glint. */
  | { kind: "behindLens"; shape: EyeShape; eye: MochiEye };

/**
 * What a character does with the eye shape the animation asked for.
 *
 * Two kinds of eyes, and the difference is not cosmetic:
 *
 * - `dot`, `glossy`, `pixel`, `sleepy` **are** the eye, so they only apply while
 *   nothing is being expressed. The moment the bot is dizzy, asleep, delighted
 *   or winking, its own eyes take over and the character steps aside.
 * - `visor` and `shades` are **worn over** the eyes, and the same rule would be
 *   a bug: eyewear does not come off because you got dizzy. They are always
 *   drawn, and the shape the animation asked for is drawn inside the lens as a
 *   glint — the spiral still spins, the sleeping arcs still close, you just
 *   watch it happen through the lens.
 */
export function resolveEye(character: MochiCharacter, shape: EyeShape): EyeResolution {
  const eye = character.eye;
  if (!eye) return { kind: "plain", shape };
  if (isSpanning(eye)) return { kind: "behindLens", shape, eye };
  return isNeutral(shape)
    ? { kind: "character", eye, wide: shape === "wide" }
    : { kind: "plain", shape };
}

export function isClassic(character: MochiCharacter): boolean {
  return !character.accessory && !character.eye;
}

export function sameCharacter(a: MochiCharacter, b: MochiCharacter): boolean {
  return sameFace(a, b) && (a.shape ?? null) === (b.shape ?? null) && sameFestive(a, b);
}

/**
 * The face alone — accessory and eyes, never the body.
 *
 * The presets name a face; the body is a separate axis with its own row of
 * tiles, so a Frog wearing Royal is still Royal. Highlighting the grid with
 * `sameCharacter` would leave nothing selected the moment anyone picked a shape.
 */
export function sameFace(a: MochiCharacter, b: MochiCharacter): boolean {
  return (a.accessory ?? null) === (b.accessory ?? null)
      && (a.eye ?? null) === (b.eye ?? null);
}

// ── Presets ───────────────────────────────────────────────────────────────────

export interface CharacterPreset {
  id: string;
  name: string;
  character: MochiCharacter;
}

/**
 * The eighteen, in grid order.
 *
 * Nothing but a shortcut. Settings resolves a preset to a character and stores
 * that, never the preset id, so picking a tile and then changing one of the two
 * pickers needs no second code path and no "custom" sentinel.
 */
export const CHARACTER_PRESETS: readonly CharacterPreset[] = [
  { id: "plain", name: "Plain", character: { eye: "dot" } },
  { id: "kitty", name: "Kitty", character: { accessory: "catEars", eye: "dot" } },
  { id: "horned", name: "Horned", character: { accessory: "horns", eye: "glossy" } },
  { id: "beacon", name: "Beacon", character: { accessory: "antenna", eye: "pixel" } },
  { id: "sprout", name: "Sprout", character: { accessory: "sprout", eye: "visor" } },
  { id: "sparkle", name: "Sparkle", character: { accessory: "sparkles", eye: "glossy" } },

  { id: "bow", name: "Bow", character: { accessory: "bow", eye: "dot" } },
  { id: "royal", name: "Royal", character: { accessory: "crown", eye: "glossy" } },
  { id: "beret", name: "Beret", character: { accessory: "beret", eye: "pixel" } },
  { id: "ghost", name: "Ghost", character: { eye: "visor" } },
  { id: "coolcat", name: "Cool Cat", character: { accessory: "catEars", eye: "shades" } },
  { id: "imp", name: "Imp", character: { accessory: "horns", eye: "dot" } },

  { id: "blip", name: "Blip", character: { accessory: "antenna", eye: "glossy" } },
  { id: "seedling", name: "Seedling", character: { accessory: "sprout", eye: "pixel" } },
  { id: "stardust", name: "Stardust", character: { accessory: "sparkles", eye: "visor" } },
  { id: "dapper", name: "Dapper", character: { accessory: "bow", eye: "shades" } },
  { id: "majesty", name: "Majesty", character: { accessory: "crown", eye: "dot" } },
  { id: "grumpy", name: "Grumpy", character: { accessory: "beret", eye: "sleepy" } },
];

/** The preset this character came from, if any — for marking the grid. */
export function presetMatching(character: MochiCharacter): CharacterPreset | null {
  return CHARACTER_PRESETS.find((p) => sameFace(p.character, character)) ?? null;
}

// ── Storage ───────────────────────────────────────────────────────────────────

/**
 * `"accessory:eye:shape"`, with `-` for absent. The form the settings file
 * stores, so Rust can relay a character it knows nothing about.
 *
 * The third field is an append, not a new format: a two-field string from an
 * older settings file still parses, and an older build reading a three-field
 * one ignores the tail and draws a classic body.
 *
 * Christmas is a fourth append on the same terms — `head.eyes.texture.extra`,
 * `-` for a layer with nothing on it — and only written when something is
 * worn. A character that never dressed up stores the same bytes it always did.
 */
export function characterToStorage(character: MochiCharacter): string {
  const base = `${character.accessory ?? "-"}:${character.eye ?? "-"}:${character.shape ?? "-"}`;
  if (!hasFestive(character)) return base;
  const f = character.festive!;
  return `${base}:${FESTIVE_SLOTS.map((slot) => f[slot] || "-").join(".")}`;
}

/**
 * Tolerant on purpose. A settings file written by a later build — or by hand —
 * must leave Mochi looking like Mochi, never throw and never take the island
 * down with it.
 */
export function characterFromStorage(text: string): MochiCharacter {
  const parts = (text ?? "").split(":");
  const accessory = ACCESSORIES.find((a) => a === parts[0]) ?? null;
  const eye = EYES.find((e) => e === parts[1]) ?? null;
  const shape = SHAPES.find((s) => s === parts[2]) ?? null;
  const character: MochiCharacter = { accessory, eye, shape };
  if (!parts[3]) return character;

  // An id this build has no artwork for is dropped, layer by layer: a hat from
  // next year's catalogue costs that hat, not the scarf beside it.
  const ids = parts[3].split(".");
  const festive: MochiFestive = {};
  FESTIVE_SLOTS.forEach((slot, i) => {
    if (FESTIVE_IDS[slot].includes(ids[i])) festive[slot] = ids[i];
  });
  return FESTIVE_SLOTS.some((slot) => festive[slot]) ? { ...character, festive } : character;
}

// ── Season ────────────────────────────────────────────────────────────────────

/**
 * Whether the Christmas parts are on offer: 15 November to 6 January, both
 * included, by the clock on the wall where the user is. It opens in the middle
 * of November, when the lights go up, rather than on the first of December.
 *
 * Only the picker asks. A character already wearing something keeps wearing it
 * in March — taking a hat off somebody's Mochi overnight is not ours to do.
 */
export function isFestiveSeason(date: Date = new Date()): boolean {
  const month = date.getMonth();   // 0 is January
  const day = date.getDate();
  return month === 11 || (month === 10 && day >= 15) || (month === 0 && day <= 6);
}
