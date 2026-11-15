// Ato's mascot, checked against Actuar's own engine.
//
// design/ato/actuar-bot-v3.js is the script that draws the orb on
// blog.actuar.com and novo.actuar.com. This runs it, unchanged, on every input
// the Swift port printed (`AtoBotTests --dump`), and holds both ports to it:
//
//   - the pose: every number the drawing depends on, to 1e-7;
//   - the drawing: the SVG the original would write for that pose, every
//     element and attribute, every coordinate to its last printed decimal;
//   - the blog's resting loop: the gestures, the wink, the hop.
//
// The TypeScript port (windows/src/ato/bot.ts) is held to the same inputs.
//
// Run by scripts/test-ato-bot.sh, which supplies ATO_DUMP.

import { readFileSync } from "node:fs";
import * as Port from "../windows/src/ato/bot.ts";

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

// ── The original, loaded as the page loads it ────────────────────────────────

const source = readFileSync(new URL("../design/ato/actuar-bot-v3.js", import.meta.url), "utf8");
const [engineSource, driverSource] = source.split("// ---- driver (the blog hero) ----");
const g = globalThis as Record<string, unknown>;
g.window = g;
new Function(engineSource)();
// deno-lint-ignore no-explicit-any
const A = g.ActuarBot6 as any;

// The driver keeps its helpers inside a closure that also wires up the DOM.
// Lift out the pure part — from `const sm` up to the pointer state — as text.
const from = driverSource.indexOf("  const sm =");
const to = driverSource.indexOf("  let ptr =");
// deno-lint-ignore no-explicit-any
const D = new Function("A", driverSource.slice(from, to) + "\nreturn { gest, exprAt, bodyAt, idleLook };")(A) as any;

// ── Helpers ──────────────────────────────────────────────────────────────────

// deno-lint-ignore no-explicit-any
function numbers(P: any): number[] {
  const v: number[] = [P.r, P.sx, P.sy, P.x, P.y, P.roll, P.anchor, P.gray, P.look.x, P.look.y];
  for (const e of P.eyes) v.push(e.sy, e.pdx, e.pdy, e.arc, e.shut);
  v.push(P.eyeA, P.twist, P.wob, P.spread);
  for (const l of P.lay) v.push(l.x, l.y, l.s, l.a, l.rot ?? NaN);
  v.push(P.fo.x, P.fo.y, P.eyeS, P.drift, P.breathe, +P.blinkOK, +P.gazeFree, P.T, P.energy);
  v.push(P.decor.length);
  for (const d of P.decor) v.push(d.x, d.y, d.r ?? 0, d.s ?? 0, d.a);
  return v;
}

const parse = (csv: string) => csv.split(",").map((s) => (s === "nan" ? NaN : Number(s)));

function sameNumbers(a: number[], b: number[], tol: number): string | null {
  if (a.length !== b.length) return `${a.length} numbers against ${b.length}`;
  for (let i = 0; i < a.length; i++) {
    if (Number.isNaN(a[i]) && Number.isNaN(b[i])) continue;
    if (!(Math.abs(a[i] - b[i]) <= tol)) return `#${i}: ${a[i]} against ${b[i]}`;
  }
  return null;
}

// The SVG as text and numbers. The text must match exactly; a number may be off
// by one step of the last decimal the original prints — where a value sits on a
// rounding boundary, the last bit of a sine decides which side it lands.
const NUM = /-?\d+(?:\.\d+)?/g;
function sameSvg(a: string, b: string): string | null {
  if (a === b) return null;
  const ta = a.replace(NUM, "#"), tb = b.replace(NUM, "#");
  if (ta !== tb) {
    let i = 0;
    while (i < ta.length && ta[i] === tb[i]) i++;
    return `markup differs at …${ta.slice(Math.max(0, i - 40), i + 40)}… against …${tb.slice(Math.max(0, i - 40), i + 40)}…`;
  }
  return sameNumbers((a.match(NUM) ?? []).map(Number), (b.match(NUM) ?? []).map(Number), 0.1 + 1e-9);
}

const render = (P: unknown) =>
  A.render(P, { size: 160, body: "orbe", eyes: "pontinhos", pal: A.PAL_BY.oficial, bg: "escuro", noPaper: true });

function expr(s: number) {
  return D.exprAt(s);
}

// ── Every line Swift printed ─────────────────────────────────────────────────

const lines = readFileSync(process.env.ATO_DUMP!, "utf8").trimEnd().split("\n");
const tally: Record<string, { n: number; pose: string[]; svg: string[]; exact: number; port: string[] }> = {};
const note = (kind: string) => (tally[kind] ??= { n: 0, pose: [], svg: [], exact: 0, port: [] });

for (const line of lines) {
  const f = line.split("\t");
  const kind = f[0];
  const t = note(kind);
  t.n++;

  if (kind === "drive") {
    const s = Number(f[1]);
    const e = D.exprAt(s), l = D.idleLook(s);
    const css = D.bodyAt(s) as string;
    const m = (css.match(NUM) ?? []).map(Number);
    const motion = m.length === 2 ? [m[0], m[1], 1, 1] : m;
    const want = [e.eyes[0].sy, e.eyes[0].arc, e.eyes[1].sy, e.eyes[1].arc, l.x, l.y, ...motion];
    const got = parse(f[2]);
    // bodyAt prints 3 and 2 decimals; the rest is exact.
    const why = sameNumbers(got.slice(0, 6), want.slice(0, 6), 1e-9)
      ?? sameNumbers(got.slice(6), want.slice(6), 0.0051);
    if (why) t.pose.push(`s=${s}: ${why}`);
    const p = Port.restingFace(s), pl = Port.idleLook(s), pm = Port.bodyMotion(s);
    const portWhy = sameNumbers([p[0].sy, p[0].arc, p[1].sy, p[1].arc, pl.x, pl.y, pm.ty, pm.rot, pm.sx, pm.sy], got, 1e-9);
    if (portWhy) t.port.push(`s=${s}: ${portWhy}`);
    continue;
  }

  // deno-lint-ignore no-explicit-any
  let P: any, portP: Port.AtoPose, head: string;
  if (kind === "still") {
    const [state, tt] = [f[1], Number(f[2])];
    P = A.poseAt(state, tt, { expr: A.EXPR_BY.neutro, energy: 1 });
    portP = Port.poseAt(state as Port.AtoState, tt);
    head = `${state} t=${tt}`;
  } else if (kind === "live") {
    const [prev, cur, tl] = [f[1], f[2], Number(f[3])];
    const dur = A.STATE_BY[prev].dur, T = dur + tl;
    const pointer = { x: 0.3, y: -0.2 };
    P = A.sample(T, [{ state: prev, dur }, { state: cur, dur: 1000 }],
      { expr: expr(T), energy: 1, follow: true, pointer, followW: 1 });
    // The original finds tl from its timeline, `((T % tot) + tot) % tot` less
    // the blocks before; do the same arithmetic, last bit included.
    const tot = dur + 1000, liveTl = ((T % tot) + tot) % tot - dur;
    portP = Port.sampleLive(T, cur as Port.AtoState, liveTl, prev as Port.AtoState, dur,
      { expr: Port.restingFace(T), energy: 1, follow: true, pointer, followW: 1 });
    head = `${prev}→${cur} tl=${tl}`;
  } else {
    const [T, px, py] = [Number(f[1]), Number(f[2]), Number(f[3])];
    const pointer = { x: px, y: py };
    P = A.sample(T, [{ state: "idle", dur: 1e9 }],
      { expr: expr(T - 0.6), energy: 1, follow: true, pointer, followW: 1 });
    portP = Port.sampleLive(T, "idle", ((T % 1e9) + 1e9) % 1e9, "idle", 1e9,
      { expr: Port.restingFace(T - 0.6), energy: 1, follow: true, pointer, followW: 1 });
    head = `rest T=${T}`;
  }
  const swiftNums = parse(f[f.length - 2]), swiftSvg = f[f.length - 1];
  const want = numbers(P), wantSvg = render(P);

  const why = sameNumbers(swiftNums, want, 1e-7);
  if (why) t.pose.push(`${head}: ${why}`);
  const svgWhy = sameSvg(swiftSvg, wantSvg);
  if (svgWhy) t.svg.push(`${head}: ${svgWhy}`);
  if (swiftSvg === wantSvg) t.exact++;

  const portWhy = sameNumbers(numbers(portP), want, 1e-9) ?? (Port.render(portP) === wantSvg ? null : "SVG differs");
  if (portWhy) t.port.push(`${head}: ${portWhy}`);
}

const NAMES: Record<string, string> = {
  still: "each state, still",
  live: "changing state",
  loop: "the blog's resting loop",
  drive: "the resting gestures and gaze",
};
for (const [kind, t] of Object.entries(tally)) {
  const name = `${NAMES[kind] ?? kind} (${t.n})`;
  check(t.pose.length === 0, `Swift poses match the original — ${name}`);
  for (const w of t.pose.slice(0, 5)) console.log(`      ${w}`);
  if (kind !== "drive") {
    check(t.svg.length === 0, `Swift draws what the original draws — ${name}, ${t.exact} byte for byte`);
    for (const w of t.svg.slice(0, 5)) console.log(`      ${w}`);
  }
  check(t.port.length === 0, `TypeScript matches the original — ${name}`);
  for (const w of t.port.slice(0, 5)) console.log(`      ${w}`);
}

check(lines.length > 400, `Swift printed enough to mean something (${lines.length} lines)`);

console.log(failures === 0 ? "\nAto bot parity: all passed." : `\nAto bot parity: ${failures} FAILED.`);
process.exit(failures === 0 ? 0 : 1);
