// What a Mochi wears at Christmas — the half of it that is not data.
//
// Every shape here was worked out by scripts/generate-mochi-festive.mjs, per
// body, and arrives as paths in festive.generated.ts. This file only puts them
// on screen: it decodes the document once, turns a path string into a Path2D
// once, resolves the colours that depend on who is wearing the part, and knows
// how the lit parts breathe. The engines (engine.ts for a Mochi, ato/view.ts
// for Ato) decide where each layer goes and what moves with it.

import {
  FESTIVE_JSON, type FestiveBody, type FestiveData, type FestivePrim,
} from "./festive.generated";

export type { FestiveBody, FestiveData, FestivePrim } from "./festive.generated";

type RGB = readonly [number, number, number]; // components 0…1

// ── The data ──────────────────────────────────────────────────────────────────

let data: FestiveData | null = null;

/** The whole document. Parsed on first use: 320 KB nobody pays for in July. */
export function festiveData(): FestiveData {
  return (data ??= JSON.parse(FESTIVE_JSON) as FestiveData);
}

/** One body's parts: a shape id, `classic`, or `ato`. Classic if unknown. */
export function festiveBody(key: string): FestiveBody {
  const bodies = festiveData().bodies;
  return bodies[key] ?? bodies.classic;
}

// A prim is immutable and lives as long as the document does, so its Path2D is
// keyed on the object itself — no hashing a 2 KB string sixty times a second.
const paths = new WeakMap<FestivePrim, Path2D>();
const clips = new Map<FestiveBody, Path2D>();

function pathOf(prim: FestivePrim): Path2D {
  let p = paths.get(prim);
  if (!p) { p = new Path2D(prim.d); paths.set(prim, p); }
  return p;
}

/** The body's outline as the generator saw it, for a body no engine redraws. */
export function festiveClip(body: FestiveBody): Path2D {
  let p = clips.get(body);
  if (!p) { p = new Path2D(body.clip); clips.set(body, p); }
  return p;
}

// ── Season ────────────────────────────────────────────────────────────────────

// The rule itself is beside the character it gates, where the parity test can
// reach it without the generated parts.
export { isFestiveSeason } from "./character";

// ── Colour ────────────────────────────────────────────────────────────────────

/** What the tokens in a prim's fill and stroke mean for one wearer, this frame. */
export interface FestivePaint {
  /** `@skin:K` is this times K. */
  skin: RGB;
  ink: string;
  glint: string;
  flake: string;
  /** Null where there is no edge to draw: the prim is skipped. */
  flakeEdge: string | null;
  /** Seconds, for the lit parts; null draws each at its own resting opacity. */
  time: number | null;
}

const GINGER: RGB = [0xB5 / 255, 0x74 / 255, 0x3A / 255]; // #B5743A
const ATO_BLUE: RGB = [0x1B / 255, 0x2F / 255, 0xEB / 255]; // #1B2FEB
const FROST_BLUE = "#3FA9F5";
const FROST_EDGE = "#5FAEE6";

/**
 * The paint for a Mochi.
 *
 * @param body the colour the body is filled with — the pill's, or the engine's
 *   own pale top for the big bot.
 * @param ink the engine's eye ink at this size.
 */
export function mochiPaint(
  body: RGB, texture: string | undefined, ink: string, time: number | null,
): FestivePaint {
  // A snowflake has to show against what it is drawn on. Blue on a pale body;
  // but frost and gingerbread repaint the body, so the body's own colour stops
  // being what the flake sits on.
  const pale = 0.299 * body[0] + 0.587 * body[1] + 0.114 * body[2] >= 0.75;
  return {
    skin: texture === "gingerbread" ? GINGER : body,
    ink,
    glint: "#FFFFFF",
    flake: pale && texture !== "frost" && texture !== "gingerbread" ? FROST_BLUE : "#FFFFFF",
    flakeEdge: pale && texture === "frost" ? FROST_EDGE : null,
    time,
  };
}

/**
 * The paint for Ato, whose face is white on blue.
 *
 * @param skin the fill of the disc its face is on, as drawn this frame — blue,
 *   or the grey it fades to offline, so its elf ears go grey with it.
 */
export function atoPaint(
  texture: string | undefined, time: number | null, skin?: string,
): FestivePaint {
  return {
    skin: texture === "gingerbread" ? GINGER : hexRGB(skin) ?? ATO_BLUE,
    ink: "#FFFFFF",
    glint: "#1B2FEB",
    flake: "#FFFFFF",
    flakeEdge: null,
    time,
  };
}

function hexRGB(hex: string | undefined): RGB | null {
  if (!hex || !/^#[0-9a-fA-F]{6}$/.test(hex)) return null;
  const v = parseInt(hex.slice(1), 16);
  return [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255];
}

function resolve(token: string, paint: FestivePaint): string | null {
  if (token.charCodeAt(0) !== 64 /* @ */) return token;
  if (token.startsWith("@skin:")) {
    const k = Number(token.slice(6)) * 255;
    const c = paint.skin;
    return `rgb(${Math.round(c[0] * k)},${Math.round(c[1] * k)},${Math.round(c[2] * k)})`;
  }
  switch (token) {
    case "@ink": return paint.ink;
    case "@glint": return paint.glint;
    case "@flake": return paint.flake;
    case "@flakeEdge": return paint.flakeEdge;
    default: return null;   // a token from a later generator: skip, never guess
  }
}

// ── Light ─────────────────────────────────────────────────────────────────────

const smooth = (x: number) => x * x * (3 - 2 * x);

/**
 * The opacity of a lit prim at `t` seconds.
 *
 * The string lights are two sets taking turns on a 2.2 s cycle: each holds,
 * then eases across in under 0.2 s, so they read as bulbs switching rather
 * than as a sine wave. The star's three layers breathe together on 1.8 s.
 */
export function festiveLight(k: string, t: number): number {
  switch (k) {
    case "bulbA": case "bulbB": case "glowA": case "glowB": {
      const u = (((t % 2.2) + 2.2) % 2.2) / 2.2;
      const a = u < 0.42 ? 1
        : u < 0.5 ? 1 - smooth((u - 0.42) / 0.08)
        : u < 0.92 ? 0
        : smooth((u - 0.92) / 0.08);
      if (k === "bulbA") return 0.3 + 0.7 * a;
      if (k === "bulbB") return 0.3 + 0.7 * (1 - a);
      return k === "glowA" ? 0.3 * a : 0.3 * (1 - a);
    }
    case "lit": case "shineA": case "shineB": {
      const c = 0.5 - 0.5 * Math.cos((2 * Math.PI * t) / 1.8);
      if (k === "lit") return 0.6 + 0.4 * c;
      return k === "shineA" ? 0.08 + 0.32 * c : 0.28 + 0.52 * c;
    }
    default:
      return 1;
  }
}

// ── Drawing ───────────────────────────────────────────────────────────────────

/**
 * Draws a list of prims.
 *
 * The context arrives with its origin at the body centre, in whatever units
 * the caller draws its own body in. `scale` takes the data from there to its
 * own units (R / 100 for a Mochi), after `tx`/`ty` has moved it — and both
 * happen *inside* the clip, never before it: `clip` is the caller's body, in
 * the caller's units, and a hat sliding with the head must not drag the
 * silhouette it is cut against along with it.
 *
 * Only the prims marked `c` are clipped. Consecutive ones share a clip, so a
 * texture — all clipped — costs one, not one per stripe.
 */
export function drawFestive(
  x: CanvasRenderingContext2D, prims: readonly FestivePrim[], paint: FestivePaint,
  alpha: number, clip: Path2D | null,
  tx = 0, ty = 0, scale = 1,
) {
  if (!prims.length || alpha <= 0.004) return;
  const base = x.globalAlpha * alpha;

  x.save();
  x.lineCap = "round";
  x.lineJoin = "round";

  // -1 nothing open, 0 an unclipped group, 1 a clipped one.
  let open = -1;
  for (const prim of prims) {
    const fill = prim.f !== undefined ? resolve(prim.f, paint) : null;
    const stroke = prim.s !== undefined ? resolve(prim.s, paint) : null;
    if (!fill && !stroke) continue;

    const o = prim.k && paint.time !== null ? festiveLight(prim.k, paint.time) : prim.o ?? 1;
    if (o <= 0.004) continue;

    const want = prim.c && clip ? 1 : 0;
    if (want !== open) {
      if (open !== -1) x.restore();
      x.save();
      if (want === 1) x.clip(clip!);
      if (tx !== 0 || ty !== 0) x.translate(tx, ty);
      if (scale !== 1) x.scale(scale, scale);
      open = want;
    }

    const path = pathOf(prim);
    x.globalAlpha = base * o;
    if (fill) {
      x.fillStyle = fill;
      x.fill(path);
    }
    if (stroke) {
      x.strokeStyle = stroke;
      x.lineWidth = prim.w ?? 1;
      x.stroke(path);
    }
  }
  if (open !== -1) x.restore();
  x.restore();
}
