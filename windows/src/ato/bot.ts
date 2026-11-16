// Ato's own mascot — the TypeScript twin of NotchBuddy/Sources/App/AtoBot.swift.
//
// Both are ports of design/ato/actuar-bot-v3.js, "Actuar Bot v3": the script
// behind the orb on blog.actuar.com and the support launcher on
// novo.actuar.com. Three wobbly layers (orange, cyan, blue) turning against
// each other, two white dot eyes, a blink, and the eight states Notchy plays.
// tests/ato-bot-parity.ts runs the original under Node and holds this file to
// it, pose for pose and SVG for SVG.
//
// Pure — no DOM — so the test can load it under bare Node. ./view.ts draws it.

export type AtoState = "idle" | "thinking" | "notify" | "success" | "error" | "offline" | "sleep" | "welcome";
export const ATO_STATES: AtoState[] = ["idle", "thinking", "notify", "success", "error", "offline", "sleep", "welcome"];

export interface AtoEye { sy: number; pdx: number; pdy: number; arc: number; shut: number }
export interface AtoVec { x: number; y: number }
export interface AtoLayer { x: number; y: number; s: number; a: number; rot?: number }
export type AtoDecor =
  | { type: "badge"; x: number; y: number; r: number; a: number }
  | { type: "text"; txt: string; x: number; y: number; s: number; a: number };

export interface AtoPose {
  r: number; sx: number; sy: number; x: number; y: number; roll: number; anchor: number; gray: number;
  look: AtoVec; eyes: AtoEye[]; eyeA: number;
  twist: number; wob: number; spread: number;
  lay: AtoLayer[]; fo: AtoVec; eyeS: number; decor: AtoDecor[];
  drift: number; breathe: number; blinkOK: number; gazeFree: number;
  T: number; energy: number;
  /** The original's cheeks ("bochechas": blush with style 6). */
  blush: number;
  /** Notchy's own: a Mochi eye drawn white in place of the dots. Never set by a pose. */
  glyph?: AtoGlyph;
}

/** The Mochi eyes Ato borrows when it reacts like one. Not in the original. */
export type AtoGlyph = "heart" | "star" | "line" | "spiral";

type Patch = Partial<Omit<AtoPose, "lay">> & { lay?: Partial<AtoLayer>[] };

export interface AtoContext {
  /** The resting face — the original's `expr`. */
  expr: AtoEye[];
  energy?: number;
  follow?: boolean;
  pointer?: AtoVec;
  followW?: number;
  /** The original's `expr.blush`. */
  blush?: number;
  /** Notchy's own, off by default: follow the pointer in every state, as a Mochi's eyes do. */
  gazeAlways?: boolean;
  /** Notchy's own: the eyelid from a Mochi engine's `open`, in place of the original's blinks. */
  lid?: number;
}

const TAU = Math.PI * 2;
/** The orb is drawn at radius 196; this brings it to 100. */
const K = 100 / 196;
const EYX = 68, EY = -14;

/** Back to front: orange chevron, cyan wave, blue. */
const ORB = [
  { k: "ch", R: 196, A: 14, n: 5, ph: 0, base: 0, dir: 1 },
  { k: "wv", R: 192, A: 12, n: 6, ph: 1.2, base: 20, dir: -1 },
  { k: "bl", R: 196, A: 13, n: 7, ph: 2.4, base: 40, dir: 0.7 },
] as const;

export const ATO_ORANGE = "#FB5423", ATO_BLUE = "#1B2FEB", ATO_CYAN = "#1FEFFF", ATO_INK = "#0A1130";

const SPEC: Record<AtoState, { dur: number; f: number; z: number; blinkIn: boolean }> = {
  idle: { dur: 3.2, f: 2.2, z: 0.5, blinkIn: true },
  thinking: { dur: 3.2, f: 2, z: 0.45, blinkIn: false },
  notify: { dur: 2.6, f: 2.6, z: 0.4, blinkIn: true },
  success: { dur: 2.6, f: 2.2, z: 0.5, blinkIn: false },
  error: { dur: 2.6, f: 2.4, z: 0.45, blinkIn: true },
  offline: { dur: 3, f: 1.6, z: 0.7, blinkIn: true },
  sleep: { dur: 3.4, f: 1.4, z: 0.7, blinkIn: false },
  welcome: { dur: 3, f: 2, z: 0.45, blinkIn: false },
};
export const atoStateDuration = (s: AtoState) => SPEC[s].dur;

// ── The original's helpers ───────────────────────────────────────────────────

const clamp = (x: number, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const easeOut = (t: number) => 1 - Math.pow(1 - clamp(t), 3);
const easeInOut = (t: number) => { t = clamp(t); return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; };
const bump = (t: number, a: number, b: number) => (t <= a || t >= b) ? 0 : Math.sin(Math.PI * (t - a) / (b - a));
const hash = (n: number) => { const x = Math.sin(n * 127.1 + 0.3) * 43758.5453; return x - Math.floor(x); };
function spring(t: number, f = 2.2, z = 0.5) {
  if (t <= 0) return 0;
  const w = TAU * f, wd = w * Math.sqrt(1 - z * z);
  return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + (z * w / wd) * Math.sin(wd * t));
}
const kick = (t: number, f = 2.2, d = 4) => t <= 0 ? 0 : Math.exp(-d * t) * Math.sin(TAU * f * t);
const sm = (x: number) => x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x);

// ── Faces ────────────────────────────────────────────────────────────────────

const EYE = (o: Partial<AtoEye> = {}): AtoEye => Object.assign({ sy: 1, pdx: 1, pdy: -1, arc: 0, shut: 0 }, o);
const pair = (o: Partial<AtoEye> = {}): AtoEye[] => [EYE(o), EYE(o)];
const FACES = {
  neutro: () => pair(),
  atento: () => pair({ pdx: -3, pdy: 4 }),
  curioso: () => pair({ pdx: 11, pdy: -6 }),
  surpreso: () => pair({ pdx: 0, pdy: -8 }),
  animado: () => pair({ arc: 1 }),
  sonolento: () => pair({ pdy: 8 }),
};
export const neutralFace = FACES.neutro;
const L3 = (f: (i: number) => Partial<AtoLayer>) => [0, 1, 2].map(f);

// ── Poses: each state with its overlay applied ───────────────────────────────

function pose(s: AtoState, t: number): Patch {
  switch (s) {
    case "idle":
      return { gazeFree: 1 };
    case "thinking": {
      const a = t * 2.4;
      const sat = (k: number) => { const q = a + k * Math.PI, z = Math.sin(q); return { x: Math.cos(q) * 285, y: -30 + z * 70, s: 0.34 + 0.1 * z }; };
      const fx = Math.cos(a), fz = Math.sin(a), front = fz > 0 ? fx : -fx;
      return { eyes: FACES.curioso(), r: 0.95, look: { x: front * 1.1, y: -0.9 }, roll: 8, drift: 0, twist: t * 90, wob: 1.25,
        spread: 0.04 + 0.03 * Math.sin(t * 5), lay: [sat(0), sat(1), { s: 0.7 + 0.02 * Math.sin(t * 3) }], eyeS: 0.74 };
    }
    case "notify": {
      const m = easeInOut((t - 1.3) / 0.45);
      return { eyes: FACES.surpreso(), r: 1 + 0.12 * kick(t, 2.2, 4), look: { x: lerp(1, 0, m), y: lerp(-1, 0, m) }, drift: m,
        twist: 60 * easeOut(t / 0.6) - 60 * m,
        decor: [{ type: "badge", x: 0.74, y: -0.74, r: Math.max(0, 0.21 * spring(t - 0.12, 2.4, 0.35)), a: 1 }],
        lay: L3((i) => ({ y: -70 * Math.max(0, kick(t - i * 0.09, 2.2, 4)) })) };
    }
    case "success": {
      const ant = bump(t, 0, 0.22), air = t > 0.2 && t < 0.78 ? Math.sin(Math.PI * (t - 0.2) / 0.58) : 0;
      let sy = 1 - 0.07 * ant;
      if (air > 0) sy = 1 + 0.04 * (1 - air) * (t < 0.49 ? 1 : 0) + 0.015 * air;
      if (t >= 0.78) sy = 1 - 0.07 * Math.exp(-6 * (t - 0.78)) * Math.cos(TAU * 2.4 * (t - 0.78));
      const e = Math.sin(Math.PI * clamp((t - 0.75) / 1.1)), T3 = TAU / 3;
      return { eyes: FACES.animado(), y: -0.2 * air, sy, sx: 1 + (1 - sy) * 0.6, anchor: 1, drift: 0,
        twist: 360 * easeInOut((t - 0.15) / 0.9), spread: 0.1 * air, wob: 1 + 0.3 * air,
        lay: L3((i) => ({ x: Math.cos(i * T3 - Math.PI / 2) * 150 * e, y: Math.sin(i * T3 - Math.PI / 2) * 150 * e, s: 1 - 0.3 * e })) };
    }
    case "error": {
      const sh = (i: number) => t > 0.1 ? Math.sin(TAU * 3.6 * (t - 0.1) - i * 0.7) * Math.exp(-2.6 * (t - 0.1)) : 0;
      return { eyes: pair({ pdx: 4, pdy: -5 }), x: 0.12 * sh(0), roll: 9 * sh(0), drift: 0.4, twist: 25 * sh(0),
        decor: [{ type: "text", txt: "?", x: 0.9, y: -0.78, s: 0.62 * Math.max(0, spring(t - 0.3, 2.2, 0.35)), a: clamp((t - 0.3) / 0.15) }],
        lay: L3((i) => ({ x: 60 * sh(i) })) };
    }
    case "offline":
      return { eyes: FACES.sonolento(), gray: 1, r: 0.92, y: 0.05, look: { x: 0, y: 0.6 }, drift: 0.3, breathe: 1.6, wob: 0.5,
        lay: L3((i) => ({ y: 40 * (i - 1), s: 0.92 - 0.06 * i, a: i === 2 ? 1 : 0.5 })) };
    case "sleep": {
      const b = Math.sin(t * TAU / 2.6);
      return { eyes: pair({ shut: 1 }), sy: 1 + 0.05 * b, sx: 1 - 0.038 * b, anchor: 1, drift: 0.55, blinkOK: 0, wob: 1 + 0.08 * b,
        decor: [0, 1, 2].map((i) => {
          const p = ((t / 2.6 + i / 3) % 1 + 1) % 1;
          return { type: "text" as const, txt: "z", x: 0.6 + 0.3 * p, y: -0.62 - 0.56 * p, s: 0.22 + 0.2 * p, a: Math.sin(Math.PI * p) * 0.85 };
        }) };
    }
    case "welcome": {
      const g = spring(t - 0.1, 1.5, 0.36), eo = clamp((t - 0.55) / 0.2);
      const wk = clamp((t - 1.5) / 0.1) * (1 - clamp((t - 2.05) / 0.15));
      const k = (i: number) => clamp((t - 0.05 - i * 0.12) / 0.75);
      const e = (i: number) => { const x = k(i), c1 = 1.4; return 1 + (c1 + 1) * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); };
      return { eyes: [EYE({ sy: Math.max(0.06, eo) }), EYE({ sy: Math.max(0.06, eo), arc: wk })],
        r: Math.max(0.06, 0.08 + 0.92 * g), drift: 0, blinkOK: 0, twist: -540 * (1 - easeOut(t / 1.5)), wob: 1.4,
        lay: L3((i) => ({ s: Math.max(0.001, e(i)), rot: (1 - k(i)) * (i - 1) * 80 })) };
    }
  }
}

// ── Assembly ─────────────────────────────────────────────────────────────────

function base(X: AtoContext): AtoPose {
  return {
    r: 1, sx: 1, sy: 1, x: 0, y: 0, roll: 0, anchor: 0, gray: 0, look: { x: 0, y: 0 },
    eyes: X.expr.map((e) => ({ ...e })), eyeA: 1, twist: 0, wob: 1, spread: 0,
    lay: [0, 1, 2].map(() => ({ x: 0, y: 0, s: 1, a: 1 })), fo: { x: 0, y: 0 }, eyeS: 1, decor: [],
    drift: 1, breathe: 1, blinkOK: 1, gazeFree: 0, T: 0, energy: 1, blush: X.blush ?? 0,
  };
}

function full(s: AtoState, t: number, X: AtoContext): AtoPose {
  const P = base(X), o = pose(s, t);
  // Every state but idle builds its face with the original's `face()`, which
  // brings its own cheeks — none — over the resting face's.
  if (s !== "idle") P.blush = 0;
  for (const k in o) {
    const key = k as keyof Patch;
    if (key === "look" || key === "fo") P[key] = { ...P[key], ...o[key]! };
    else if (key === "lay") P.lay = P.lay.map((l, i) => ({ ...l, ...(o.lay![i] ?? {}) }));
    else (P as unknown as Record<string, unknown>)[key] = o[key];
  }
  return P;
}

const mixEye = (a: AtoEye, b: AtoEye, k: number): AtoEye => ({
  sy: lerp(a.sy, b.sy, k), pdx: lerp(a.pdx, b.pdx, k), pdy: lerp(a.pdy, b.pdy, k), arc: lerp(a.arc, b.arc, k), shut: lerp(a.shut, b.shut, k),
});
/** The original walks b's keys: a `rot` only a has is dropped. */
function mixLayer(a: AtoLayer, b: AtoLayer, k: number): AtoLayer {
  const l: AtoLayer = { x: lerp(a.x, b.x, k), y: lerp(a.y, b.y, k), s: lerp(a.s, b.s, k), a: lerp(a.a, b.a, k) };
  if (b.rot !== undefined) l.rot = lerp(a.rot ?? b.rot, b.rot, k);
  return l;
}

function mixPose(a: AtoPose, b: AtoPose, k: number, kc: number): AtoPose {
  const L = (key: keyof AtoPose, kk = k) => lerp(a[key] as number, b[key] as number, kk);
  return {
    r: L("r"), sx: L("sx"), sy: L("sy"), x: L("x"), y: L("y"), roll: L("roll"), anchor: L("anchor", kc), gray: L("gray", kc),
    look: { x: lerp(a.look.x, b.look.x, k), y: lerp(a.look.y, b.look.y, k) },
    eyes: [mixEye(a.eyes[0], b.eyes[0], k), mixEye(a.eyes[1], b.eyes[1], k)], eyeA: L("eyeA", kc),
    twist: L("twist", kc), wob: L("wob"), spread: L("spread"),
    lay: a.lay.map((l, i) => mixLayer(l, b.lay[i], k)),
    fo: { x: lerp(a.fo.x, b.fo.x, k), y: lerp(a.fo.y, b.fo.y, k) }, eyeS: L("eyeS"),
    decor: a.decor.map((d) => ({ ...d, a: d.a * (1 - kc) })).concat(b.decor.map((d) => ({ ...d, a: d.a * kc }))),
    drift: L("drift", kc), breathe: L("breathe", kc), blinkOK: b.blinkOK, gazeFree: b.gazeFree, T: 0, energy: 1,
    blush: L("blush", kc),
  };
}

/** Eyelid openness: a blink about every 4.1 s, jittered, a third of them double. */
export function blink(T: number): number {
  const P = 4.1, k = Math.floor(T / P);
  for (const kk of [k - 1, k]) {
    const t0 = kk * P + hash(kk) * 2.2, d = T - t0;
    if (d >= 0 && d < 0.2) return 1 - Math.sin(Math.PI * d / 0.2) * 0.94;
    if (hash(kk + 99) > 0.68) { const d2 = d - 0.32; if (d2 >= 0 && d2 < 0.18) return 1 - Math.sin(Math.PI * d2 / 0.18) * 0.94; }
  }
  return 1;
}

function post(P: AtoPose, T: number, tl: number, S: AtoState | null, X: AtoContext, noBlink = false): AtoPose {
  const enter = S && SPEC[S].blinkIn && tl < 0.22 ? 1 - Math.sin(Math.PI * tl / 0.22) * 0.94 : 1;
  const bl = noBlink ? 1 : (P.blinkOK ? (X.lid ?? blink(T)) : 1) * enter;
  P.eyes = P.eyes.map((e) => ({ ...e, sy: e.sy * bl }));
  const d = P.drift;
  P.look = {
    x: P.look.x + d * (0.35 * Math.sin(T * 0.71) + 0.2 * Math.sin(T * 1.93 + 1)),
    y: P.look.y + d * (0.25 * Math.sin(T * 0.93 + 2) + 0.1 * Math.sin(T * 2.3)),
  };
  if (X.follow && X.pointer && (P.gazeFree || X.gazeAlways)) {
    const w = 0.85 * (X.followW ?? 1);
    P.look = { x: lerp(P.look.x, X.pointer.x, w), y: lerp(P.look.y, X.pointer.y, w) };
  }
  const en = X.energy ?? 1, br = Math.sin(T * TAU / (3.4 * (P.breathe || 1)));
  P.sx = 1 + (P.sx * (1 - 0.01 * br) - 1) * en;
  P.sy = 1 + (P.sy * (1 + 0.016 * br) - 1) * en;
  P.y *= en; P.twist *= en; P.wob = 1 + (P.wob - 1) * en;
  P.T = T; P.energy = en;
  return P;
}

/**
 * The pose at clock `T`, `tl` seconds into `state`, having come from
 * `previous` (held as it stood at `previousAt`) — the original's `sample` with
 * the timeline lookup taken out, so a live state can drive it.
 */
export function sampleLive(T: number, state: AtoState, tl: number, previous: AtoState, previousAt: number, X: AtoContext): AtoPose {
  const S = SPEC[state];
  let P = full(state, tl, X);
  if (tl < 1.1) P = mixPose(full(previous, previousAt, X), P, spring(tl, S.f, S.z), easeInOut(tl / 0.5));
  P.twist += 38 * kick(tl, 1.3, 3.2);
  return post(P, T, tl, state, X);
}

/** A still, without blinks. */
export function poseAt(s: AtoState, t: number, X: AtoContext = { expr: FACES.neutro(), energy: 1 }): AtoPose {
  return post(full(s, t, X), 1.3, 1, s, X, true);
}

// ── The blog's driver — Ato at rest ──────────────────────────────────────────

const CY = 6;
const env = (c: number, a: number, b: number, i = 0.3, o = 0.35) => sm((c - a) / i) * (1 - sm((c - (b - o)) / o));
function gesture(s: number) { const c = s % CY; return { k: Math.floor(s / CY) % 2, c, g: env(c, 3.4, 5.1) }; }

/** Every 6 s a gesture, alternating: a tilt and a wink, then a smile and a hop. */
export function restingFace(s: number): AtoEye[] {
  const { k, g } = gesture(s), E = FACES.neutro(), w = sm(g * 1.3);
  if (k === 0) { E[1].arc = w; E[0].sy = 1 - 0.1 * w; } else { E[0].arc = E[1].arc = w; }
  return E;
}
export function gestureAmount(s: number): number { return gesture(s).g; }

/** With nobody pointing: at the title, at you, back. */
export function idleLook(s: number): AtoVec {
  const c = s % CY, y = sm((c - 1.3) / 0.45) * (1 - sm((c - 2.7) / 0.45));
  return { x: -0.6 * (1 - y), y: 0.06 };
}

/** The gesture's whole-body move: % of the box down, degrees, scale — about a point 62 % down. */
export function bodyMotion(s: number): { ty: number; rot: number; sx: number; sy: number } {
  const { k, g, c } = gesture(s), sway = Math.sin(s * 1.05) * 1.4, bob = Math.sin(s * 2.1) * 0.5;
  if (k === 0) return { ty: bob - 1.5 * g, rot: sway - 10 * g, sx: 1, sy: 1 };
  const hop = Math.sin(sm((c - 3.5) / 0.55) * Math.PI) * 3.4, squash = Math.sin(sm((c - 3.35) / 0.2) * Math.PI) * 0.04;
  return { ty: bob - hop, rot: sway + 2.5 * g, sx: 1 + squash, sy: 1 - squash };
}

// ── Drawing ──────────────────────────────────────────────────────────────────

function hexMix(a: string, b: string, t: number): string {
  const pa = parseInt(a.slice(1), 16), pb = parseInt(b.slice(1), 16);
  const ch = (sh: number) => Math.round(lerp((pa >> sh) & 255, (pb >> sh) & 255, clamp(t)));
  return "#" + ((1 << 24) + (ch(16) << 16) + (ch(8) << 8) + ch(0)).toString(16).slice(1);
}

function wav(R: number, A: number, n: number, ph: number): [number, number][] {
  const pts: [number, number][] = [];
  for (let i = 0; i <= 120; i++) { const t = i / 120 * TAU, r = R + A * Math.sin(n * t + ph); pts.push([r * Math.cos(t), r * Math.sin(t)]); }
  return pts;
}

export interface AtoSceneLayer { points: [number, number][]; fill: string; opacity: number; tx: number; ty: number; s: number; rot: number }
export type AtoEyeMark =
  | { kind: "dot"; cx: number; cy: number; ry: number; opacity: number }
  | { kind: "arc"; x0: number; y0: number; qx: number; qy: number; x1: number; y1: number; width: number; opacity: number }
  /** A borrowed Mochi eye: filled when `width` is 0, else a stroke. */
  | { kind: "glyph"; glyph: AtoGlyph; points: AtoVec[]; width: number; opacity: number };

/** What there is to draw, in the original's 320-unit box (orb radius 100). */
export interface AtoScene {
  px: number; py: number; roll: number; anchorY: number; sx: number; sy: number; s: number;
  layers: AtoSceneLayer[];
  eyesOpacity: number; fx: number; fy: number; eyeS: number; blush: number; eyes: AtoEyeMark[];
  decor: AtoDecor[];
}

export function scene(P: AtoPose): AtoScene {
  const g = "#6B7079", gm = (c: string) => hexMix(c, g, P.gray);
  const pal: Record<string, string> = { ch: gm(ATO_ORANGE), bl: gm(ATO_BLUE), wv: gm(ATO_CYAN) };
  const T = P.T, s = K * P.r, A = P.anchor * 100 * P.r;
  const layers = ORB.map((L, i) => {
    const rot = L.base + L.dir * (P.twist + T * 7 * (P.energy ?? 1)) + (P.lay[i].rot || 0), sc = 1 + P.spread * (i - 1) * 0.6;
    const ly = P.lay[i];
    return {
      points: wav(L.R * sc, L.A * P.wob * (1 + 0.12 * Math.sin(T * 1.4 + i * 2)), L.n, L.ph + T * 0.35 * L.dir),
      fill: pal[L.k], opacity: 0.88 * clamp(ly.a),
      tx: ly.x + P.look.x * (i - 1) * 9, ty: ly.y + P.look.y * (i - 1) * 6, s: Math.max(0, ly.s), rot,
    };
  });
  const eyes: AtoEyeMark[] = [];
  P.eyes.forEach((e, i) => {
    const sd = i ? 1 : -1, x = sd * EYX, y = EY;
    const open = clamp(1 - e.arc) * clamp(1 - e.shut);
    const lx = x + e.pdx + clamp(P.look.x, -1.3, 1.3) * 10, ly = y + e.pdy + clamp(P.look.y, -1.3, 1.3) * 8;
    if (P.glyph) {
      eyes.push({ kind: "glyph", glyph: P.glyph, points: glyph(P.glyph, lx, y + (ly - y) * 0.6, T), width: glyphWidth(P.glyph), opacity: 1 });
      return;
    }
    if (open > 0.02) eyes.push({ kind: "dot", cx: lx, cy: y + (ly - y) * 0.6, ry: Math.max(0.5, 26 * e.sy * (1 - 0.75 * clamp(e.arc + e.shut))), opacity: open });
    if (e.arc > 0.02) eyes.push({ kind: "arc", x0: x - 32, y0: y + 12, qx: x, qy: y - 36, x1: x + 32, y1: y + 12, width: 17, opacity: clamp(e.arc) });
    if (e.shut > 0.02) eyes.push({ kind: "arc", x0: x - 28, y0: y, qx: x, qy: y + 24, x1: x + 28, y1: y, width: 14, opacity: clamp(e.shut) });
  });
  return {
    px: P.x * 100, py: P.y * 100, roll: P.roll, anchorY: A, sx: P.sx, sy: P.sy, s, layers,
    eyesOpacity: clamp(P.eyeA), fx: P.look.x * 7 + P.fo.x, fy: P.look.y * 5 + P.fo.y, eyeS: P.eyeS, blush: P.blush, eyes,
    decor: P.decor.filter((d) => d.a >= 0.01),
  };
}

// ── Reacting like a Mochi ────────────────────────────────────────────────────

/**
 * Puts a Mochi engine's reaction on a sampled pose — AtoBot.react in Swift:
 * its eye shape, cheeks and eye swell, and the original's "follow the cursor"
 * lean toward the gaze. Ato's own faces where the original has them, a Mochi
 * eye in white where it does not.
 */
export function react(P: AtoPose, eye: string | null, blush: number, eyeScale: number) {
  P.twist += P.look.x * 14;
  P.roll += P.look.x * 4;
  P.blush = Math.max(P.blush, blush);
  P.eyeS *= eyeScale;
  switch (eye) {
    case "happy": for (const e of P.eyes) e.arc = 1; break;
    case "closed": for (const e of P.eyes) e.shut = 1; break;
    case "wink": P.eyes[1].arc = 1; break;
    case "tired": for (const e of P.eyes) e.sy *= 0.45; break;
    case "heart": P.glyph = "heart"; break;
    case "star": P.glyph = "star"; break;
    case "line": case "flat": P.glyph = "line"; break;
    case "spiral": P.glyph = "spiral"; break;
  }
}

// ── Borrowed eyes ───────────────────────────────────────────────────────────

/** Stroke width of a borrowed eye; 0 means filled. */
export const glyphWidth = (g: AtoGlyph) => (g === "line" ? 11 : g === "spiral" ? 7 : 0);

/**
 * The outline of a borrowed eye centred on (cx, cy), in orb units — the dot it
 * replaces is 26 across. Sampled, so it matches AtoBot.swift point for point.
 */
export function glyph(g: AtoGlyph, cx: number, cy: number, T: number): AtoVec[] {
  switch (g) {
    case "heart": {
      const k = 30 / 17, pts: AtoVec[] = [];
      for (let i = 0; i < 48; i++) {
        const t = i / 48 * TAU;
        const x = 16 * Math.pow(Math.sin(t), 3);
        const y = -(13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t));
        pts.push({ x: cx + x * k, y: cy + (y - 2.5) * k });
      }
      return pts;
    }
    case "star": {
      const pts: AtoVec[] = [];
      for (let i = 0; i < 10; i++) {
        const a = -Math.PI / 2 + i * Math.PI / 5, r = i % 2 === 0 ? 30 : 13;
        pts.push({ x: cx + Math.cos(a) * r, y: cy + Math.sin(a) * r });
      }
      return pts;
    }
    case "line":
      return [{ x: cx - 24, y: cy }, { x: cx + 24, y: cy }];
    case "spiral": {
      const pts: AtoVec[] = [];
      for (let i = 0; i < 60; i++) {
        const f = i / 59, a = T * 4 + f * 2.25 * TAU, r = 3 + 23 * f;
        pts.push({ x: cx + Math.cos(a) * r, y: cy + Math.sin(a) * r });
      }
      return pts;
    }
  }
}

const f1 = (n: number) => Math.round(n * 10) / 10;
const PAPER = "#1D1E1F", TEXT_INK = "#FFFFFF";

/** The original's `render(P, {body:'orbe', pal: oficial, bg:'escuro', noPaper: true})`, as an SVG string. */
export function render(P: AtoPose, size = 160, uid = "ab"): string {
  const S = scene(P), px = size * 1.6;
  let out = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="-160 -160 320 320" width="${f1(px)}" height="${f1(px)}" style="display:block;overflow:visible">`;
  out += `<g transform="translate(${f1(S.px)} ${f1(S.py)}) rotate(${f1(S.roll)}) translate(0 ${f1(S.anchorY)}) scale(${S.sx.toFixed(3)} ${S.sy.toFixed(3)}) translate(0 ${f1(-S.anchorY)}) scale(${S.s.toFixed(4)})">`;
  out += `<g style="isolation:isolate">`;
  for (const L of S.layers) {
    const d = L.points.map((p, i) => (i ? "L" : "M") + f1(p[0]) + " " + f1(p[1])).join("") + "Z";
    out += `<path d="${d}" fill="${L.fill}" opacity="${L.opacity.toFixed(2)}" transform="translate(${f1(L.tx)} ${f1(L.ty)}) scale(${L.s.toFixed(3)}) rotate(${f1(L.rot)})"/>`;
  }
  out += `</g>`;
  out += `<g opacity="${S.eyesOpacity.toFixed(2)}" transform="translate(${f1(S.fx)} ${f1(S.fy)}) translate(0 ${EY}) scale(${S.eyeS.toFixed(3)}) translate(0 ${-EY})">`;
  if (S.blush > 0.01) {
    const b = S.blush, C6 = "#FFB4C4";
    for (const sd of [-1, 1]) {
      const gid = `${uid}bg${sd > 0 ? 1 : 0}`;
      out += `<defs><radialGradient id="${gid}"><stop offset="0" stop-color="${C6}" stop-opacity="${b.toFixed(2)}"/><stop offset=".62" stop-color="${C6}" stop-opacity="${(b * 0.92).toFixed(2)}"/><stop offset="1" stop-color="${C6}" stop-opacity="0"/></radialGradient></defs><ellipse cx="${sd * 118}" cy="46" rx="26" ry="21" fill="url(#${gid})"/>`;
    }
  }
  for (const m of S.eyes) {
    if (m.kind === "dot") out += `<ellipse cx="${f1(m.cx)}" cy="${f1(m.cy)}" rx="26" ry="${f1(m.ry)}" fill="#FFFFFF" opacity="${m.opacity.toFixed(2)}"/>`;
    else if (m.kind === "arc") out += `<path d="M${m.x0} ${m.y0}Q${m.qx} ${m.qy} ${m.x1} ${m.y1}" stroke="#FFFFFF" stroke-width="${m.width}" stroke-linecap="round" fill="none" opacity="${m.opacity.toFixed(2)}"/>`;
    else {
      // Notchy's own — the original has no such element.
      const d = m.points.map((p, i) => (i ? "L" : "M") + f1(p.x) + " " + f1(p.y)).join("");
      out += m.width === 0
        ? `<path d="${d}Z" fill="#FFFFFF" opacity="${m.opacity.toFixed(2)}"/>`
        : `<path d="${d}" stroke="#FFFFFF" stroke-width="${m.width}" stroke-linecap="round" stroke-linejoin="round" fill="none" opacity="${m.opacity.toFixed(2)}"/>`;
    }
  }
  out += `</g></g>`;
  for (const d of S.decor) {
    const op = clamp(d.a).toFixed(2);
    if (d.type === "badge") out += `<circle cx="${f1(d.x * 100)}" cy="${f1(d.y * 100)}" r="${f1(d.r * 100 + 7)}" fill="${PAPER}" opacity="${op}"/><circle cx="${f1(d.x * 100)}" cy="${f1(d.y * 100)}" r="${f1(d.r * 100)}" fill="#FB5423" opacity="${op}"/>`;
    else out += `<text x="${f1(d.x * 100)}" y="${f1(d.y * 100)}" font-family="Open Sans, Arial, sans-serif" font-weight="800" font-size="${f1(d.s * 100)}" text-anchor="middle" dominant-baseline="central" fill="${TEXT_INK}" opacity="${op}">${d.txt}</text>`;
  }
  return out + `</svg>`;
}
