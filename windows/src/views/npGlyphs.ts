// The Now Playing card's symbols, drawn in the frames the Mac's SF Symbols
// take on the card — `NowPlayingCardView.swift` and `ChristmasAlbumView.swift`.
//
// The card used to draw its transport from 24-unit icons squeezed into a box
// the size of the Mac's point size: 13 px for backward.fill, 17 for play.fill.
// But a symbol's point size is not its size. At 13 pt backward.fill is 19.5 pt
// wide and 12 tall; play.fill at 17 pt is 15 x 17. So every button came out
// small, and the row of five was narrower and further apart than the Mac's.
//
// Each glyph here is the Mac's own render of its symbol, at the card's size and
// weight, measured offscreen at 16x: the frame SwiftUI lays it out in, and the
// shape inside it — corners, radii, the ring's centre and weight, where the
// arrowhead sits — fitted until the two inks overlap (dev/_glyphfit, against
// the Mac's renders). Built from those numbers, not traced. The frame is the
// svg's own box, so a glyph in a row lands where the Mac's does.
//
// Pure data and DOM: no state, so the dev harness can draw every one of them.

/** One mark of a glyph, in the frame's points. */
export type Prim =
  | { kind: "fill"; d: string; transform?: Affine }
  | { kind: "stroke"; d: string; width: number; transform?: Affine }
  /** Cut out of everything drawn before it — the gap either side of a slash. */
  | { kind: "erase"; d: string; width: number }
  | { kind: "text"; x: number; y: number; size: number; weight: number; text: string };

/** `[sx, sy, tx, ty]`: scale, then move. */
export type Affine = readonly [number, number, number, number];

export interface Glyph {
  /** The frame SwiftUI gives the symbol, in points. */
  w: number;
  h: number;
  prims: Prim[];
}

const r2 = (n: number) => Math.round(n * 1000) / 1000;

/**
 * A closed polygon with each corner rounded by its own radius.
 *
 * Each vertex is `[x, y, r]`; a radius of 0 keeps the corner sharp, which is
 * what a concave one (the speaker's neck) wants. Tangent points sit `r / tan(θ/2)`
 * along both edges, joined by an arc of radius `r`.
 */
export function roundedPolygon(pts: readonly (readonly [number, number, number])[]): string {
  const n = pts.length;
  let d = "";
  for (let i = 0; i < n; i++) {
    const [px, py, r] = pts[i];
    const [ax, ay] = pts[(i + n - 1) % n];
    const [bx, by] = pts[(i + 1) % n];
    if (r <= 0) {
      d += `${i === 0 ? "M" : "L"}${r2(px)} ${r2(py)}`;
      continue;
    }
    const ul = Math.hypot(ax - px, ay - py);
    const vl = Math.hypot(bx - px, by - py);
    const ux = (ax - px) / ul;
    const uy = (ay - py) / ul;
    const vx = (bx - px) / vl;
    const vy = (by - py) / vl;
    const theta = Math.acos(Math.max(-1, Math.min(1, ux * vx + uy * vy)));
    const t = Math.min(r / Math.tan(theta / 2), ul / 2, vl / 2);
    const rr = t * Math.tan(theta / 2);
    // A turn clockwise on screen (y down) is a convex corner of a clockwise
    // polygon, and its arc is drawn clockwise too.
    const sweep = (px - ax) * (by - py) - (py - ay) * (bx - px) > 0 ? 1 : 0;
    d += `${i === 0 ? "M" : "L"}${r2(px + ux * t)} ${r2(py + uy * t)}`;
    d += `A${r2(rr)} ${r2(rr)} 0 0 ${sweep} ${r2(px + vx * t)} ${r2(py + vy * t)}`;
  }
  return `${d}Z`;
}

// ── Parameters ─────────────────────────────────────────────────────────────────
// Fitted against the Mac's render; the comment on each says which symbol, at
// which size, and the frame it comes in.

export interface TriPairParams {
  /** Where the leading triangle's point would be, unrounded. */
  tipX: number;
  cy: number;
  /** Its flat side. */
  baseX: number;
  halfH: number;
  rTip: number;
  rBase: number;
  /** How far along the second triangle sits. */
  shift: number;
}

export interface PlayParams { x0: number; y0: number; y1: number; tipX: number; tipY: number; rBack: number; rTip: number }
export interface PauseParams { x0: number; bw: number; gap: number; y0: number; y1: number; r: number }

export interface SkipParams {
  cx: number;
  cy: number;
  /** The ring's centre line, and its weight. */
  R: number;
  sw: number;
  /** Where the ring stops, in degrees clockwise from three o'clock. */
  endDeg: number;
  /** The arrowhead: its point, the line through its middle, its back. */
  tipX: number;
  acy: number;
  backX: number;
  halfH: number;
  rA: number;
}

export interface SpeakerParams {
  x0: number;
  /** Where the box meets the cone. */
  jx: number;
  by0: number;
  by1: number;
  backX: number;
  coneTop: number;
  coneBot: number;
  rBody: number;
  rCone: number;
}

export interface SlashParams { x0: number; y0: number; x1: number; y1: number; sw: number; gap: number }

/** backward.fill, 13 pt regular — a 19.5 x 12 frame. */
export const BACKWARD: TriPairParams = { tipX: -0.222, cy: 5.845, baseX: 9.139, halfH: 5.46, rTip: 0.743, rBase: 0.82, shift: 8.605 };
/** forward.fill, 13 pt regular — 19.5 x 12. Its mirror, a point to the right. */
export const FORWARD: TriPairParams = { tipX: 19.46, cy: 5.845, baseX: 10.105, halfH: 5.46, rTip: 0.742, rBase: 0.82, shift: -8.605 };
/** play.fill, 17 pt regular — 15 x 17. */
export const PLAY: PlayParams = { x0: 2.0, y0: 0.658, y1: 16.282, tipX: 15.35, tipY: 8.469, rBack: 1.113, rTip: 0.975 };
/** pause.fill, 17 pt regular — 14.5 x 17. */
export const PAUSE: PauseParams = { x0: 1.994, bw: 4.108, gap: 1.924, y0: 1.5, y1: 15.219, r: 1.013 };
/** gobackward(.N), 14 pt regular — 16.5 x 17.94. */
export const SKIP_BACK: SkipParams = { cx: 8.223, cy: 9.678, R: 6.389, sw: 1.162, endDeg: 234.563, tipX: 6.111, acy: 3.436, backX: 9.538, halfH: 2.409, rA: 0.4 };
/** goforward(.N): the same dial turned round. */
export const SKIP_FWD: SkipParams = {
  ...SKIP_BACK,
  endDeg: 540 - SKIP_BACK.endDeg,
  tipX: 2 * SKIP_BACK.cx - SKIP_BACK.tipX,
  backX: 2 * SKIP_BACK.cx - SKIP_BACK.backX,
};
/** The number on the dial: SF's own digits in gobackward.10 sit 5.1 tall on a
 *  baseline 12.3 down, about the ring's centre. */
export const SKIP_DIGITS = { baseline: 12.3, size: 7.2, weight: 600 };
/** speaker.fill, 10 pt regular — 10 x 10.375. */
export const SPEAKER: SpeakerParams = { x0: 1.5, jx: 4.006, by0: 3.226, by1: 7.166, backX: 7.316, coneTop: 0.06, coneBot: 10.316, rBody: 0.956, rCone: 0.608 };
/** speaker.slash.fill, 10 pt regular — 9.94 x 12.25: the speaker, and a slash
 *  with a gap cut either side of it. */
export const SPEAKER_MUTED: SpeakerParams = { x0: 1.513, jx: 3.885, by0: 3.912, by1: 7.712, backX: 7.323, coneTop: 0.688, coneBot: 10.8, rBody: 0.856, rCone: 0.588 };
export const SLASH: SlashParams = { x0: 0.86, y0: 1.91, x1: 9.245, y1: 10.277, sw: 0.756, gap: 0.569 };

// ── Glyphs ─────────────────────────────────────────────────────────────────────

function triPair(p: TriPairParams): Prim[] {
  const tri = (dx: number) => {
    const tip: [number, number, number] = [p.tipX + dx, p.cy, p.rTip];
    const top: [number, number, number] = [p.baseX + dx, p.cy - p.halfH, p.rBase];
    const bottom: [number, number, number] = [p.baseX + dx, p.cy + p.halfH, p.rBase];
    // Clockwise on screen whichever way it points.
    return roundedPolygon(p.tipX < p.baseX ? [tip, top, bottom] : [top, tip, bottom]);
  };
  return [{ kind: "fill", d: tri(0) }, { kind: "fill", d: tri(p.shift) }];
}

export function backwardGlyph(p = BACKWARD): Glyph {
  return { w: 19.5, h: 12, prims: triPair(p) };
}

export function forwardGlyph(p = FORWARD): Glyph {
  return { w: 19.5, h: 12, prims: triPair(p) };
}

export function playGlyph(p = PLAY): Glyph {
  return {
    w: 15,
    h: 17,
    prims: [{ kind: "fill", d: roundedPolygon([[p.x0, p.y0, p.rBack], [p.tipX, p.tipY, p.rTip], [p.x0, p.y1, p.rBack]]) }],
  };
}

export function pauseGlyph(p = PAUSE): Glyph {
  const bar = (x: number) =>
    roundedPolygon([[x, p.y0, p.r], [x + p.bw, p.y0, p.r], [x + p.bw, p.y1, p.r], [x, p.y1, p.r]]);
  return {
    w: 14.5,
    h: 17,
    prims: [{ kind: "fill", d: bar(p.x0) }, { kind: "fill", d: bar(p.x0 + p.bw + p.gap) }],
  };
}

/**
 * gobackward / goforward, with the number written in the ring.
 *
 * The Mac has SF's numbered dial for 5, 10, 15, 30, 45, 60, 75 and 90 and
 * writes any other number onto the plain dial; one drawing does both here, with
 * the number where SF's own digits sit.
 */
export function skipGlyph(seconds: number | null, forward: boolean, p = forward ? SKIP_FWD : SKIP_BACK): Glyph {
  const rad = (deg: number) => (deg * Math.PI) / 180;
  // From under the arrowhead at twelve, round the long way to where it stops.
  const sx = p.cx;
  const sy = p.cy - p.R;
  const ex = p.cx + p.R * Math.cos(rad(p.endDeg));
  const ey = p.cy + p.R * Math.sin(rad(p.endDeg));
  const sweep = forward ? 0 : 1;
  const ring = `M${r2(sx)} ${r2(sy)}A${p.R} ${p.R} 0 1 ${sweep} ${r2(ex)} ${r2(ey)}`;
  const head = roundedPolygon(forward
    ? [[p.backX, p.acy - p.halfH, p.rA], [p.tipX, p.acy, p.rA], [p.backX, p.acy + p.halfH, p.rA]]
    : [[p.tipX, p.acy, p.rA], [p.backX, p.acy - p.halfH, p.rA], [p.backX, p.acy + p.halfH, p.rA]]);
  const prims: Prim[] = [
    { kind: "stroke", d: ring, width: p.sw },
    { kind: "fill", d: head },
  ];
  if (seconds != null) {
    const text = String(seconds);
    // Three digits would touch the ring either side at the dial's size.
    const size = text.length >= 3 ? SKIP_DIGITS.size * 0.78 : SKIP_DIGITS.size;
    prims.push({ kind: "text", x: p.cx, y: SKIP_DIGITS.baseline, size, weight: SKIP_DIGITS.weight, text });
  }
  return { w: 16.5, h: 17.938, prims };
}

function speakerPath(p: SpeakerParams): string {
  return roundedPolygon([
    [p.x0, p.by0, p.rBody],
    [p.jx, p.by0, 0],
    [p.backX, p.coneTop, p.rCone],
    [p.backX, p.coneBot, p.rCone],
    [p.jx, p.by1, 0],
    [p.x0, p.by1, p.rBody],
  ]);
}

export function speakerGlyph(p = SPEAKER): Glyph {
  return { w: 10, h: 10.375, prims: [{ kind: "fill", d: speakerPath(p) }] };
}

export function speakerMutedGlyph(p = SPEAKER_MUTED, s = SLASH): Glyph {
  const line = `M${s.x0} ${s.y0}L${s.x1} ${s.y1}`;
  return {
    w: 9.938,
    h: 12.25,
    prims: [
      { kind: "fill", d: speakerPath(p) },
      { kind: "erase", d: line, width: s.sw + 2 * s.gap },
      { kind: "stroke", d: line, width: s.sw },
    ],
  };
}

export interface NoteParams {
  /** The head: an ellipse, tilted. */
  hx: number;
  hy: number;
  rx: number;
  ry: number;
  rot: number;
  /** The stem's two sides and its top. */
  x0: number;
  x1: number;
  stemTop: number;
  /** The flag: its far corners, and where its underside meets the stem. */
  trX: number;
  trY: number;
  brY: number;
  blY: number;
  r: number;
}

/** music.note, 20 pt regular — 16.94 x 23.25: the artwork's stand-in. */
export const NOTE_20: NoteParams = { hx: 5.613, hy: 18.642, rx: 3.186, ry: 2.718, rot: -24.437, x0: 7.523, x1: 8.851, stemTop: 3.172, trX: 14.407, trY: 1.65, brY: 6.802, blY: 8.031, r: 0.735 };
/** music.note, 9 pt semibold — 7.875 x 10.69: the source badge with no icon. */
export const NOTE_9: NoteParams = { hx: 2.617, hy: 8.501, rx: 1.522, ry: 1.3, rot: -23, x0: 3.423, x1: 4.175, stemTop: 1.485, trX: 6.7, trY: 0.764, brY: 3.228, blY: 3.8, r: 0.376 };

export interface SnowflakeParams {
  cx: number;
  cy: number;
  /** Each of the six arms, from the centre: its width there and at its
   *  rounded tip — SF's arms swell a little towards the end. */
  L: number;
  w0: number;
  w1: number;
  /** The V's weight. */
  w: number;
  /** The V on each arm: how far out, how long its sides, how open. */
  d: number;
  c: number;
  ang: number;
}

/** snowflake, 26 pt semibold — 27.69 x 30.81: the Christmas sleeve. */
export const SNOW_26: SnowflakeParams = { cx: 13.836, cy: 15.399, L: 11.989, w0: 1.806, w1: 2.304, w: 1.919, d: 7.747, c: 4.134, ang: 59.203 };
/** snowflake, 8 pt bold — 8.625 x 9.625: the Christmas album's badge. */
export const SNOW_8: SnowflakeParams = { cx: 4.286, cy: 4.788, L: 3.702, w0: 0.614, w1: 0.791, w: 0.626, d: 2.31, c: 1.33, ang: 54.969 };

export function noteGlyph(size: 9 | 20, p = size === 9 ? NOTE_9 : NOTE_20): Glyph {
  const a = (p.rot * Math.PI) / 180;
  const ex = p.rx * Math.cos(a);
  const ey = p.rx * Math.sin(a);
  const head = `M${r2(p.hx - ex)} ${r2(p.hy - ey)}A${p.rx} ${p.ry} ${p.rot} 1 1 ${r2(p.hx + ex)} ${r2(p.hy + ey)}`
    + `A${p.rx} ${p.ry} ${p.rot} 1 1 ${r2(p.hx - ex)} ${r2(p.hy - ey)}Z`;
  const stem = roundedPolygon([[p.x0, p.stemTop, 0], [p.x1, p.stemTop, 0], [p.x1, p.hy, 0], [p.x0, p.hy, 0]]);
  const flag = roundedPolygon([[p.x0, p.stemTop, p.r], [p.trX, p.trY, p.r], [p.trX, p.brY, p.r], [p.x1, p.blY, 0]]);
  return size === 9
    ? { w: 7.875, h: 10.688, prims: [{ kind: "fill", d: head + stem + flag }] }
    : { w: 16.938, h: 23.25, prims: [{ kind: "fill", d: head + stem + flag }] };
}

export function snowflakeGlyph(size: 26 | 8, p = size === 26 ? SNOW_26 : SNOW_8): Glyph {
  let arms = "";
  let vees = "";
  const at = (deg: number, len: number, ox = p.cx, oy = p.cy) => {
    const a = (deg * Math.PI) / 180;
    return [ox + len * Math.cos(a), oy + len * Math.sin(a)] as const;
  };
  for (let arm = 0; arm < 6; arm++) {
    const deg = -90 + arm * 60;
    const [tx, ty] = at(deg, p.L);
    // A bar of changing width, drawn clockwise, with a round end: the arm.
    const [ax, ay] = at(deg - 90, p.w0 / 2);
    const [bx, by] = at(deg - 90, p.w1 / 2, tx, ty);
    const [cx2, cy2] = at(deg + 90, p.w1 / 2, tx, ty);
    const [dx, dy] = at(deg + 90, p.w0 / 2);
    arms += `M${r2(ax)} ${r2(ay)}L${r2(bx)} ${r2(by)}L${r2(cx2)} ${r2(cy2)}L${r2(dx)} ${r2(dy)}Z`;
    const rr = p.w1 / 2;
    arms += `M${r2(tx - rr)} ${r2(ty)}A${r2(rr)} ${r2(rr)} 0 1 1 ${r2(tx + rr)} ${r2(ty)}A${r2(rr)} ${r2(rr)} 0 1 1 ${r2(tx - rr)} ${r2(ty)}Z`;
    const [vx, vy] = at(deg, p.d);
    const [lx, ly] = at(deg - p.ang, p.c, vx, vy);
    const [rx, ry] = at(deg + p.ang, p.c, vx, vy);
    vees += `M${r2(lx)} ${r2(ly)}L${r2(vx)} ${r2(vy)}L${r2(rx)} ${r2(ry)}`;
  }
  const prims: Prim[] = [{ kind: "fill", d: arms }, { kind: "stroke", d: vees, width: p.w }];
  return size === 26 ? { w: 27.688, h: 30.812, prims } : { w: 8.625, h: 9.625, prims };
}

// ── Drawing ────────────────────────────────────────────────────────────────────

const NS = "http://www.w3.org/2000/svg";
let maskSeq = 0;

function transformAttr(t: Affine | undefined): string | null {
  return t ? `matrix(${t[0]} 0 0 ${t[1]} ${t[2]} ${t[3]})` : null;
}

/** The glyph as an svg the size of its Mac frame, inked in `currentColor`. */
export function glyphSvg(g: Glyph): SVGSVGElement {
  const el = document.createElementNS(NS, "svg");
  el.setAttribute("viewBox", `0 0 ${g.w} ${g.h}`);
  el.setAttribute("width", String(g.w));
  el.setAttribute("height", String(g.h));
  el.setAttribute("aria-hidden", "true");
  el.style.overflow = "visible";

  // Everything up to an erase is drawn inside a group masked by it.
  let group: SVGElement = el;
  for (const prim of g.prims) {
    if (prim.kind === "erase") {
      const id = `np-glyph-cut-${++maskSeq}`;
      const mask = document.createElementNS(NS, "mask");
      mask.setAttribute("id", id);
      mask.setAttribute("maskUnits", "userSpaceOnUse");
      const all = document.createElementNS(NS, "rect");
      all.setAttribute("x", "-2");
      all.setAttribute("y", "-2");
      all.setAttribute("width", String(g.w + 4));
      all.setAttribute("height", String(g.h + 4));
      all.setAttribute("fill", "#fff");
      const cut = document.createElementNS(NS, "path");
      cut.setAttribute("d", prim.d);
      cut.setAttribute("stroke", "#000");
      cut.setAttribute("stroke-width", String(prim.width));
      cut.setAttribute("stroke-linecap", "round");
      cut.setAttribute("fill", "none");
      mask.append(all, cut);
      const masked = document.createElementNS(NS, "g");
      masked.setAttribute("mask", `url(#${id})`);
      masked.append(...Array.from(group.childNodes));
      group.append(mask, masked);
      group = el;
      continue;
    }
    if (prim.kind === "text") {
      const t = document.createElementNS(NS, "text");
      t.setAttribute("x", String(prim.x));
      t.setAttribute("y", String(prim.y));
      t.setAttribute("text-anchor", "middle");
      t.setAttribute("font-size", String(prim.size));
      t.setAttribute("font-weight", String(prim.weight));
      t.setAttribute("fill", "currentColor");
      t.style.fontVariantNumeric = "tabular-nums";
      t.textContent = prim.text;
      group.append(t);
      continue;
    }
    const path = document.createElementNS(NS, "path");
    path.setAttribute("d", prim.d);
    const tf = transformAttr(prim.transform);
    if (tf) path.setAttribute("transform", tf);
    if (prim.kind === "fill") {
      path.setAttribute("fill", "currentColor");
    } else {
      path.setAttribute("fill", "none");
      path.setAttribute("stroke", "currentColor");
      path.setAttribute("stroke-width", String(prim.width));
      path.setAttribute("stroke-linecap", "round");
      path.setAttribute("stroke-linejoin", "round");
    }
    group.append(path);
  }
  return el;
}

/**
 * The glyph onto a canvas already scaled to points — the dev harness compares
 * this against the Mac's render. Text is left out: it is the one part that is
 * a font's and not a measurement's.
 */
export function drawGlyph(ctx: CanvasRenderingContext2D, g: Glyph): void {
  for (const prim of g.prims) {
    if (prim.kind === "text") continue;
    ctx.save();
    if (prim.kind !== "erase" && prim.transform) {
      const [sx, sy, tx, ty] = prim.transform;
      ctx.transform(sx, 0, 0, sy, tx, ty);
    }
    const path = new Path2D(prim.d);
    if (prim.kind === "fill") {
      ctx.fill(path);
    } else {
      ctx.lineWidth = prim.width;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      if (prim.kind === "erase") ctx.globalCompositeOperation = "destination-out";
      ctx.stroke(path);
    }
    ctx.restore();
  }
}
