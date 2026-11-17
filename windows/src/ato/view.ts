// Draws Ato's mascot (./bot.ts) on a canvas and keeps it alive — the twin of
// NotchBuddy/Sources/App/AtoBotView.swift.
//
// Ato does not wear a Mochi. Wherever the Ato pill would put one — its mini
// bot, the big bot while Ato is in focus — this draws the orb from Actuar's
// own engine instead.

import type { BotStateName } from "../core/layout";
import type { ConnectionState } from "../core/bridge";
import type { BotEngine } from "../mochi/engine";
import { isFestiveEyewear, type MochiFestive } from "../mochi/character";
import { atoPaint, drawFestive, festiveBody, festiveClip } from "../mochi/festive";
import {
  type AtoContext, type AtoScene, type AtoState, type AtoVec, ATO_ORANGE,
  atoStateDuration, react, bodyMotion, gestureAmount, idleLook, neutralFace, restingFace, sampleLive, scene,
} from "./bot";

export const ATO_PILL = "integration_ato";

/**
 * What a pill's state means for Ato: a waiting message is the badge. Dizzy is
 * not an error here: a dizzy Ato is itself, with a Mochi's spiral eyes and its
 * tumble (`reactionFrom`).
 */
export function atoStateFor(state: BotStateName, connection: ConnectionState | undefined): AtoState {
  // Unreachable is offline whatever the pill says; connecting is thinking.
  if (connection === "connecting") return "thinking";
  if (connection && connection !== "connected") return "offline";
  switch (state) {
    case "idle": case "dizzy": return "idle";
    case "working": case "thinking": case "searching": return "thinking";
    case "approval": case "question": return "notify";
    case "finished": return "success";
    case "error": return "error";
    case "ratelimit": return "offline";
    case "sleeping": return "sleep";
  }
}

// ── Reacting like a Mochi ────────────────────────────────────────────────────

/**
 * What a Mochi would be doing right now, read off its engine — AtoBotView.swift's
 * `AtoReaction`. The island hands every hover, love, slap and dizzy spell to
 * that engine already, on its own timers and with its sounds; Ato wears the
 * result: where it looks, its blinks, its eyes, its cheeks, how its body is
 * squashed, tilted and thrown.
 */
export interface AtoReaction {
  /** Ato's look units, ±1, +y down. */
  look: AtoVec;
  lid: number;
  eye: string | null;
  blush: number;
  eyeScale: number;
  ox: number; oy: number; sx: number; sy: number; tilt: number; roll: number;
}

export function reactionFrom(e: BotEngine): AtoReaction {
  let eye: string | null = e.state === "dizzy" ? "spiral" : e.eyeOverride;
  // A dancing Mochi is a happy one, in the calm states.
  if (eye === null && e.isDancing && e.dancingLevel > 0.15 && !e.isMini && (e.state === "idle" || e.state === "finished")) {
    eye = "happy";
  }
  // The engine turns its look into a head turn of 0.62 and a nod of 0.5, eyes
  // up for a positive nod; Ato's look is ±1, +y down.
  return {
    look: { x: e.yaw / 0.62, y: -e.pitch / 0.5 }, lid: e.open, eye, blush: e.blush, eyeScale: e.es,
    ox: e.ox, oy: e.oy, sx: e.sx, sy: e.sy, tilt: e.tilt, roll: e.roll,
  };
}

const isQuiet = (r: AtoReaction | null) => !r || (r.eye === null && r.blush < 0.05);

interface Motion { ty: number; rot: number; sx: number; sy: number; w: number }
export interface AtoFrame { scene: AtoScene; motion: Motion | null; body: AtoReaction | null }

const easeInOut = (t: number) => { t = Math.min(1, Math.max(0, t)); return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; };

/** One orb's clock and memory. `lively` is the blog hero (gestures); otherwise its small orb. */
export class AtoDriver {
  private startedAt: number | null = null;
  private last = 0;
  private current: AtoState = "idle";
  private previous: AtoState = "idle";
  private enteredAt = 0;
  private requested: AtoState | null = null;
  private oneShot: { state: AtoState; until: number } | null = null;
  private pointer: AtoVec = { x: -0.6, y: 0.06 };

  constructor(readonly lively: boolean) {}

  /** `reaction` is the Mochi engine behind this orb: given, Ato looks, blinks and reacts as it does. */
  frame(nowS: number, asked: AtoState, reaction: AtoReaction | null): AtoFrame {
    if (this.startedAt === null) { this.startedAt = nowS; this.last = nowS; }
    const s = nowS - this.startedAt;
    const dt = Math.min(0.25, Math.max(0, nowS - this.last));
    this.last = nowS;
    // The blog starts its big orb 0.6 s into its clock and its small one 3.1.
    const T = (this.lively ? 0.6 : 3.1) + s;

    // Back from offline it greets you, as the widget does when it opens; the
    // big bot also does it the first time it draws.
    if ((this.requested === null && this.lively && asked !== "offline")
      || (this.requested === "offline" && asked !== "offline")) {
      this.oneShot = { state: "welcome", until: T + atoStateDuration("welcome") };
    }
    this.requested = asked;
    if (this.oneShot && (T >= this.oneShot.until || asked === "offline")) this.oneShot = null;
    const want = this.oneShot?.state ?? asked;

    if (s === 0) {
      this.current = this.previous = want;
      this.enteredAt = want === "welcome" ? T : 0;
    } else if (want !== this.current) {
      this.previous = this.current;
      this.current = want;
      this.enteredAt = T;
    }
    const tl = T - this.enteredAt;

    // The blog's gesture every 6 s, unless the engine has Ato mid-reaction.
    const quiet = isQuiet(reaction);
    let X: AtoContext = { expr: neutralFace(), energy: 1 };
    if (reaction) {
      X = { expr: this.lively && quiet ? restingFace(s) : neutralFace(), energy: 1,
        follow: true, gazeAlways: true, pointer: reaction.look, lid: Math.max(0.06, reaction.lid) };
    } else if (this.lively) {
      const g = gestureAmount(s), base = idleLook(s);
      const goal = { x: base.x * (1 - g), y: base.y * (1 - g) + 0.04 * g };
      const k = 1 - Math.pow(1 - 0.16, dt / 0.03);
      this.pointer = { x: this.pointer.x + (goal.x - this.pointer.x) * k, y: this.pointer.y + (goal.y - this.pointer.y) * k };
      X = { expr: restingFace(s), energy: 1, follow: true, pointer: this.pointer, followW: 1 };
    }
    let motion: Motion | null = null;
    if (this.lively && quiet) {
      const fade = easeInOut(tl / 0.5);
      const w = this.current === "idle" ? (this.previous === "idle" ? 1 : fade)
        : (this.previous === "idle" && tl < 0.5 ? 1 - fade : 0);
      if (w > 0) motion = { ...bodyMotion(s), w };
    }
    const pose = sampleLive(T, this.current, tl, this.previous, atoStateDuration(this.previous), X);
    if (reaction) react(pose, reaction.eye, reaction.blush, reaction.eyeScale);
    return { scene: scene(pose), motion, body: reaction };
  }
}

/**
 * What Ato has on for Christmas, and the clock its lights run on — seconds, or
 * null for a still. Ato wears nothing else: the parts are the one way it is
 * customised, and its orb, colours and motion are untouched by them.
 */
export interface AtoFestive { parts: MochiFestive; time: number | null }

/** The orb is drawn in units of 196 to the radius; the artwork in 100. */
const ART = 196 / 100;
/** Ato's eyes at rest, in the orb's own units — `EYX`, `EY` in bot.ts. */
const EYE_X = 68, EYE_Y = -14;

/**
 * Draws `S` with the orb's centre at (cx, cy) and `unit` px per orb unit (the
 * orb's radius is 100) — the canvas twin of the original's SVG, group for group.
 */
export function drawAtoScene(x: CanvasRenderingContext2D, S: AtoScene, cx: number, cy: number, unit: number,
  motion: Motion | null = null, body: AtoReaction | null = null, festive: AtoFestive | null = null) {
  // Looked up once. Null for an Ato that never dressed up, and then nothing
  // below that mentions it runs.
  const f = festive?.parts;
  const worn = f && (f.head || f.eyes || f.texture || f.extra) ? festiveBody("ato") : null;
  const paint = worn ? atoPaint(f!.texture, festive!.time, S.layers[2]?.fill) : null;
  const clip = worn ? festiveClip(worn) : null;
  const hat = (worn && f!.head && worn.heads[f!.head]) || null;
  const extra = (worn && f!.extra && worn.extras[f!.extra]) || null;
  const texture = (worn && f!.texture && worn.textures[f!.texture]) || null;
  const eyes = (worn && f!.eyes && worn.eyes[f!.eyes]) || null;
  const eyewear = eyes !== null && isFestiveEyewear(f!.eyes);
  // The blue disc is the one the face is on, and several states resize it on
  // its own — born from nothing in `welcome`, a small core between two
  // satellites in `thinking`. What Ato wears is worn on that disc, so it takes
  // its size, or a full-sized hat would hang over an orb a third as big.
  const core = worn ? ART * Math.max(0, S.layers[2]?.s ?? 1) : 0;

  x.save();
  x.translate(cx, cy);
  x.scale(unit, unit);
  if (body) {
    // The engine's own body move, about the orb's centre, as it moves a Mochi.
    x.translate(body.ox * 100, body.oy * 100);
    x.rotate(body.tilt + body.roll);
    x.scale(body.sx, body.sy);
  }
  if (motion) {
    // The blog's CSS on the orb, about a point 62 % down its 320-unit box.
    const oy = -160 + 0.62 * 320, w = motion.w;
    x.translate(0, oy + motion.ty * 3.2 * w);
    x.rotate((motion.rot * w * Math.PI) / 180);
    x.scale(1 + (motion.sx - 1) * w, 1 + (motion.sy - 1) * w);
    x.translate(0, -oy);
  }

  x.save();
  x.translate(S.px, S.py);
  x.rotate((S.roll * Math.PI) / 180);
  x.translate(0, S.anchorY);
  x.scale(S.sx, S.sy);
  x.translate(0, -S.anchorY);
  x.scale(S.s, S.s);
  // The artwork shares the orb's centre and is fitted to a radius of 100, so
  // inside the orb's own pose it only needs the units changed — and it then
  // leans, squashes and tumbles with the orb for free.
  if (hat && core > 0) drawFestive(x, hat.b, paint!, 1, null, 0, 0, core);
  for (const L of S.layers) {
    if (L.opacity <= 0.001 || L.s <= 0) continue;
    x.save();
    x.translate(L.tx, L.ty);
    x.scale(L.s, L.s);
    x.rotate((L.rot * Math.PI) / 180);
    x.beginPath();
    L.points.forEach((p, i) => (i ? x.lineTo(p[0], p[1]) : x.moveTo(p[0], p[1])));
    x.closePath();
    x.globalAlpha = L.opacity;
    x.fillStyle = L.fill;
    x.fill();
    x.restore();
  }
  if (texture && core > 0) drawInArt(x, core, () => drawFestive(x, texture, paint!, 1, clip));
  // Where the two dots are this frame, for what is worn across both of them.
  let shiftX = 0, shiftY = 0, dots = 0, dotAlpha = 0;
  if (S.eyesOpacity > 0.001) {
    x.save();
    x.translate(S.fx, S.fy);
    x.translate(0, -14);
    x.scale(S.eyeS, S.eyeS);
    x.translate(0, 14);
    if (S.blush > 0.01) {
      // The original's cheeks: a 52 × 42 ellipse at (±118, 46), its radial
      // gradient stretched to the ellipse as SVG stretches one to its box.
      for (const sd of [-1, 1]) {
        x.save();
        x.globalAlpha = S.eyesOpacity;
        x.translate(sd * 118, 46);
        x.scale(1, 21 / 26);
        const g = x.createRadialGradient(0, 0, 0, 0, 0, 26);
        g.addColorStop(0, `rgba(255,180,196,${S.blush})`);
        g.addColorStop(0.62, `rgba(255,180,196,${S.blush * 0.92})`);
        g.addColorStop(1, "rgba(255,180,196,0)");
        x.fillStyle = g;
        x.beginPath(); x.arc(0, 0, 26, 0, Math.PI * 2); x.fill();
        x.restore();
      }
    }
    x.fillStyle = x.strokeStyle = "#FFFFFF";
    x.lineCap = "round";
    x.lineJoin = "round";
    for (const m of S.eyes) {
      x.globalAlpha = S.eyesOpacity * m.opacity;
      if (eyes && m.kind === "dot") {
        // Christmas eyes are Ato's two dots and nothing else: the arcs, the
        // closed lids and the borrowed Mochi glyphs are it expressing
        // something, and stay. Carried to where the dot is, and squashed as
        // the dot's own blink squashes it.
        const sd = m.cx < 0 ? -1 : 1;
        shiftX += m.cx - sd * EYE_X; shiftY += m.cy - EYE_Y; dots += 1;
        dotAlpha = Math.max(dotAlpha, m.opacity);
        x.save();
        x.translate(m.cx, m.cy);
        x.scale(ART, ART * Math.min(1, Math.max(0.1, m.ry / 26)));
        x.translate(-sd * worn!.eye.x, -worn!.eye.y);
        drawFestive(x, sd < 0 ? eyes.l : eyes.r, paint!, 1, null);
        x.restore();
        continue;
      }
      x.beginPath();
      if (m.kind === "dot") {
        x.ellipse(m.cx, m.cy, 26, m.ry, 0, 0, Math.PI * 2);
        x.fill();
      } else if (m.kind === "glyph") {
        m.points.forEach((p, i) => (i ? x.lineTo(p.x, p.y) : x.moveTo(p.x, p.y)));
        if (m.width === 0) { x.closePath(); x.fill(); } else { x.lineWidth = m.width; x.stroke(); }
      } else {
        x.moveTo(m.x0, m.y0);
        x.quadraticCurveTo(m.qx, m.qy, m.x1, m.y1);
        x.lineWidth = m.width;
        x.stroke();
      }
    }
    x.restore();
  }
  // Cheeks go with the eyes they belong to; frames stay on through every face,
  // as glasses do. Moved as the face group moves the dots: by the gaze, by the
  // eye swell about the eye line, and by the mean of the two.
  if (eyes && eyes.over.length && S.eyesOpacity > 0.001 && (dots > 0 || eyewear)) {
    const n = Math.max(dots, 1), e = S.eyeS;
    drawInArt(x, ART, () => drawFestive(
      x, eyes.over, paint!, S.eyesOpacity * (eyewear ? 1 : dotAlpha), clip,
      (S.fx + e * (shiftX / n)) / ART,
      (S.fy + EYE_Y + e * (shiftY / n - EYE_Y)) / ART,
      e,
    ));
  }
  if ((extra || hat) && core > 0) {
    drawInArt(x, core, () => {
      if (extra) drawFestive(x, extra.a, paint!, 1, clip);
      if (hat) drawFestive(x, hat.f, paint!, 1, clip);
      if (extra) drawFestive(x, extra.z, paint!, 1, clip);
    });
  }
  x.restore();

  for (const d of S.decor) {
    x.globalAlpha = Math.min(1, Math.max(0, d.a));
    if (d.type === "badge") {
      x.fillStyle = "#1D1E1F";
      x.beginPath(); x.arc(d.x * 100, d.y * 100, d.r * 100 + 7, 0, Math.PI * 2); x.fill();
      x.fillStyle = ATO_ORANGE;
      x.beginPath(); x.arc(d.x * 100, d.y * 100, Math.max(0, d.r * 100), 0, Math.PI * 2); x.fill();
    } else {
      x.fillStyle = "#FFFFFF";
      x.font = `800 ${Math.max(1, d.s * 100)}px "Open Sans", Arial, sans-serif`;
      x.textAlign = "center";
      x.textBaseline = "middle";
      x.fillText(d.txt, d.x * 100, d.y * 100);
    }
  }
  x.restore();
}

/** Runs `draw` in the artwork's units, inside whatever pose the orb is in. */
function drawInArt(x: CanvasRenderingContext2D, scale: number, draw: () => void) {
  x.save();
  x.scale(scale, scale);
  draw();
  x.restore();
}

/** Where a Mochi's body would be in a canvas W × H: radius 0.3 W. */
export function drawAtoInBotFrame(x: CanvasRenderingContext2D, frame: AtoFrame, W: number, H: number, overhang = 0,
  festive: AtoFestive | null = null) {
  const R = W * 0.3;
  drawAtoScene(x, frame.scene, W / 2, H / 2 + overhang / 2 + R * 0.06, R / 100, frame.motion, frame.body, festive);
}

/**
 * The Christmas parts on the engine behind an orb, on the clock that engine's
 * own eyes already read. Null — and no allocation — when it wears none.
 */
export function atoFestiveFrom(e: BotEngine, nowS: number): AtoFestive | null {
  const parts = e.character.festive;
  return parts ? { parts, time: e.festiveStill ? null : nowS } : null;
}
