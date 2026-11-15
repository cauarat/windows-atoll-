// The two marks that are drawn rather than lettered, ported from the Mac.
//
// `svg()` in dom.ts renders one path in `currentColor`, which is all a symbol
// ever needs. Neither of these fits that: Mattermost's mark is a boolean of
// three shapes, and Ato's is a three-colour orb. So they are built here, as
// whole elements.
//
// Mattermost's ratios were copied verbatim from
// NotchBuddy/Sources/App/MattermostLogo.swift. That artwork is in neither
// repository, so that file and this one are the only record of it: change
// these numbers against the real thing, not against how the result looks, and
// change them in both places at once. Ato's comes from Actuar's own engine,
// design/ato/actuar-bot-v3.js, through ../ato/bot.ts.

import { poseAt, render } from "../ato/bot";

const NS = "http://www.w3.org/2000/svg";

/** Masks need an id, and several discs are on screen at once. */
let uid = 0;

function node<K extends keyof SVGElementTagNameMap>(
  tag: K, attrs: Record<string, string | number>,
): SVGElementTagNameMap[K] {
  const el = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, String(v));
  return el;
}

/** A square mark, drawn in a 100-unit box so the numbers below read as percents. */
function box(side: number): SVGSVGElement {
  const el = document.createElementNS(NS, "svg");
  el.setAttribute("viewBox", "0 0 100 100");
  el.setAttribute("width", String(side));
  el.setAttribute("height", String(side));
  el.setAttribute("aria-hidden", "true");
  return el;
}

// ── Mattermost ───────────────────────────────────────────────────────────────

/**
 * A ring opening at the top with a blade hanging inside it, its tip pointing
 * out through the opening.
 *
 * Three things the measuring turned up on the Mac, none of them guessable, and
 * all three survive the port:
 *
 * The ring's two circles are *not* concentric. The inner one sits up and to the
 * right, which is what makes the stroke taper — 79 px at the bottom against 23
 * at the top, on a 391 px mark. A constant-width ring is the obvious reading of
 * the shape and it is the wrong one. Here that is one path of two circles under
 * `evenodd` rather than a stroked circle.
 *
 * The blade's bulb is concentric with that inner circle, so the whole mark is
 * built on two centres rather than three.
 *
 * The opening is not a wedge. It is the blade's own outline expanded by a
 * margin, which is why its edges are neither radial nor parallel. The Mac cuts
 * it with `ring.subtracting(blade.strokedPath(...).union(blade))`. SVG has no
 * boolean operators, but a mask is the same thing: one path carrying both a
 * fill and a round-capped stroke *is* the fattened blade, and painting it black
 * takes it out of the ring.
 */
const MM = {
  /** Fractions of the outer radius. */
  innerCentre: { x: 0.0409, y: -0.1381 },
  innerRadius: 0.7391,
  /**
   * The bulb very nearly shares the inner circle's centre, but not quite —
   * measured 3 px apart on a 391 px mark, which is small enough to look like
   * rounding and large enough to lean the blade visibly if it is collapsed.
   */
  bulbCentre: { x: 0.0563, y: -0.1458 },
  bulbRadius: 0.2864,
  /** Bulb centre to the blade's furthest point. */
  tipReach: 0.8031,
  tipRadius: 0.0510,
  /** Which way the blade points, and so where the ring opens. */
  axisDeg: 287.7,
  /**
   * How far the opening stands off the blade. Tuned against the artwork's own
   * gap rather than measured off one edge: at this value the opening lands
   * within 0.3 deg of the published one at every radius checked.
   */
  margin: 0.2500,
  /**
   * The mark comes both ways, and both are the logo: Mattermost's blue on a
   * pale ground, or knocked out white on that same blue. The island's discs are
   * near-black whatever the system is set to, so they ask for the dark reading
   * explicitly rather than inheriting it — the blue is about 1.9:1 against the
   * disc, which is no mark at all.
   */
  onDark: "#FFFFFF",
} as const;

/**
 * The blade: the hull of the bulb and a small circle at the tip, joined by
 * their outer tangents. Giving the tip a radius rather than a point is what the
 * artwork shows, and it keeps the blade from going to a needle on the island's
 * 34 px discs.
 */
function bladePath(cx: number, cy: number, r: number): string {
  const r1 = r * MM.bulbRadius;
  const r2 = r * MM.tipRadius;
  const d = r * MM.tipReach - r2;           // centre to centre
  const phi = (MM.axisDeg * Math.PI) / 180;
  const tx = cx + d * Math.cos(phi);
  const ty = cy + d * Math.sin(phi);
  // Where the outer tangents leave each circle. The contact angle is
  // acos((r1 - r2) / d): the radii at the two contact points are parallel,
  // which falls out of (T2 - T1) . (cos b, sin b) == 0.
  const off = Math.acos((r1 - r2) / d);

  const at = (x: number, y: number, rad: number, a: number) =>
    `${(x + rad * Math.cos(a)).toFixed(3)},${(y + rad * Math.sin(a)).toFixed(3)}`;

  // Both arcs run in the direction of increasing angle, which with y pointing
  // down is SVG's sweep flag 1. The bulb keeps the long way round — the short
  // way is the face the blade grows out of — so it alone is a large arc.
  return [
    `M${at(cx, cy, r1, phi + off)}`,
    `A${r1.toFixed(3)} ${r1.toFixed(3)} 0 1 1 ${at(cx, cy, r1, phi - off)}`,
    `L${at(tx, ty, r2, phi - off)}`,
    `A${r2.toFixed(3)} ${r2.toFixed(3)} 0 0 1 ${at(tx, ty, r2, phi + off)}`,
    "Z",
  ].join("");
}

export function mattermostMark(side: number, ink: string = MM.onDark): SVGSVGElement {
  const el = box(side);
  const r = 50;
  const ix = 50 + r * MM.innerCentre.x;
  const iy = 50 + r * MM.innerCentre.y;
  const ir = r * MM.innerRadius;
  const blade = bladePath(50 + r * MM.bulbCentre.x, 50 + r * MM.bulbCentre.y, r);

  const id = `mm-${++uid}`;
  const mask = node("mask", { id });
  mask.append(node("rect", { x: 0, y: 0, width: 100, height: 100, fill: "#fff" }));
  // Fill and stroke on one path: the blade's outline pushed out by `margin` all
  // round, which is exactly what the Mac unions out of the ring.
  mask.append(node("path", {
    d: blade, fill: "#000", stroke: "#000",
    "stroke-width": r * MM.margin * 2,
    "stroke-linecap": "round", "stroke-linejoin": "round",
  }));

  const defs = document.createElementNS(NS, "defs");
  defs.append(mask);
  el.append(defs);
  // Two circles under evenodd are the ring; the mask opens it for the blade.
  el.append(node("path", {
    d: `M${50 - r},50a${r} ${r} 0 1 0 ${r * 2} 0a${r} ${r} 0 1 0 ${-r * 2} 0Z`
      + `M${ix - ir},${iy}a${ir} ${ir} 0 1 0 ${ir * 2} 0a${ir} ${ir} 0 1 0 ${-ir * 2} 0Z`,
    "fill-rule": "evenodd", fill: ink, mask: `url(#${id})`,
  }));
  el.append(node("path", { d: blade, fill: ink }));
  return el;
}

// ── Ato ──────────────────────────────────────────────────────────────────────

/**
 * Ato's mark: a still of Ato's own mascot — the orange, cyan and blue orb with
 * two white dot eyes — drawn by the port of Actuar's engine that animates it
 * (../ato/bot.ts), at rest, eyes open. The same SVG the original writes, cropped
 * to the orb: its lobes reach 107 % of the radius, so 110 keeps them all in.
 */
export function atoMark(side: number): SVGSVGElement {
  const doc = new DOMParser().parseFromString(render(poseAt("idle", 0)), "image/svg+xml");
  const el = document.importNode(doc.documentElement, true) as unknown as SVGSVGElement;
  el.setAttribute("viewBox", "-110 -110 220 220");
  el.setAttribute("width", String(side));
  el.setAttribute("height", String(side));
  el.setAttribute("aria-hidden", "true");
  el.removeAttribute("style");
  return el;
}

/** The pills whose mark is drawn rather than lettered. */
export const PILL_LOGOS: Record<string, (side: number) => SVGSVGElement> = {
  integration_mattermost: (side) => mattermostMark(side),
  integration_ato: atoMark,
};
