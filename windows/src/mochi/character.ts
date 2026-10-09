// Who a Mochi is — port of MochiCharacter.swift.
//
// What sits on its head and what kind of eyes it has. Separate from everything
// the bot *does*: the state machine, the emotes and the mailbox morph go on
// driving the face exactly as before, and this only says what the face looks
// like when none of them is saying anything. That separation is the whole
// design — see `resolveEye`.
//
// The colour is deliberately not here. A Mochi's colour comes from the pill it
// belongs to, so the ClickMassa bot stays cyan whichever character it wears and
// the pill border still matches the creature inside it.

import type { EyeShape } from "./engine";

/** What a Mochi wears. Null is bare-headed. */
export type MochiAccessory =
  | "catEars" | "horns" | "antenna" | "sprout" | "sparkles" | "bow" | "crown" | "beret";

/** The kind of eyes a Mochi has. */
export type MochiEye = "dot" | "glossy" | "pixel" | "sleepy" | "visor" | "shades";

export interface MochiCharacter {
  accessory?: MochiAccessory | null;
  eye?: MochiEye | null;
}

/** Classic Mochi: draws identically to the app before characters existed. */
export const CLASSIC: MochiCharacter = {};

export const ACCESSORIES: readonly MochiAccessory[] =
  ["catEars", "horns", "antenna", "sprout", "sparkles", "bow", "crown", "beret"];

export const EYES: readonly MochiEye[] =
  ["dot", "glossy", "pixel", "sleepy", "visor", "shades"];

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
  return CHARACTER_PRESETS.find((p) => sameCharacter(p.character, character)) ?? null;
}

// ── Storage ───────────────────────────────────────────────────────────────────

/**
 * `"accessory:eye"`, with `-` for absent. The form the settings file stores, so
 * Rust can relay a character it knows nothing about.
 */
export function characterToStorage(character: MochiCharacter): string {
  return `${character.accessory ?? "-"}:${character.eye ?? "-"}`;
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
  return { accessory, eye };
}
