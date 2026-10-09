// Mochi — direct port of NotchBuddy/Sources/App/BotEngine.swift to Canvas 2D.
// Same constants, same tweens, same easings, same particles. The only intentional
// difference is the `happy`/`wink` eye arc, which follows the prototype
// (design/prototype/notch-buddy.html, the visual source of truth) — the Swift
// arc angles produce a different shape.

import { Ease, lerp, type EaseFn } from "../core/anim";
import { Sound } from "../core/sound";
import type { BotEmoteName, BotStateName } from "../core/layout";

import {
  resolveEye, isBehind, type MochiCharacter, type MochiEye,
} from "./character";

// ── Types ─────────────────────────────────────────────────────────────────────

export type EyeShape =
  | "pill" | "wide" | "dot" | "line" | "flat" | "happy" | "closed"
  | "spiral" | "heart" | "star" | "tired" | "wink" | "cup";

/** Where one eye lands on the head this frame, after the fake-3D projection. */
export interface EyeSlot {
  x: number;
  y: number;
  /** Foreshortening, the eye squashing as it rotates away from you. */
  fx: number;
  fy: number;
}

/**
 * What an expression is drawn in when it happens behind a lens. The ordinary
 * ink would be invisible against the dark glass.
 */
const GLINT: Record<MochiEye, string> = {
  visor: "#DFF4FF", shades: "#FFD9A0",
  dot: "#FFFFFF", glossy: "#FFFFFF", pixel: "#FFFFFF", sleepy: "#FFFFFF",
};

const LENS_FRAME = "#15171C";

export type BadgeKind = "dots" | "bang" | "question" | "dot";

export interface Badge {
  kind: BadgeKind;
  color: RGB;
}

export type RGB = readonly [number, number, number]; // components 0…1

export type TweenKey = readonly [target: number, durationMs: number, ease: EaseFn];

interface Tween {
  prop: PropKey;
  keys: TweenKey[];
  index: number;
  from: number;
  startMs: number;
  onComplete?: () => void;
}

type PropKey =
  | "yaw" | "pitch" | "roll" | "tilt" | "open" | "sx" | "sy"
  | "oy" | "ox" | "tint" | "morph" | "hands" | "blush" | "es" | "badgeS";

interface BotStateCfg {
  color: RGB;
  tint: number;
  eye: EyeShape;
  badge: Badge | null;
  bounces: boolean;
  scans: boolean;
  breathes: boolean;
  zz: boolean;
  sweat: boolean;
  look: readonly [number, number] | null;
  tilt: number;
}

interface Particle {
  type: "heart" | "star" | "spark" | "sweat" | "z";
  x: number; y: number; vx: number; vy: number;
  age: number; life: number; rot: number; size: number;
}

// ── Constants (MochiConst / PISTES.mochi) ─────────────────────────────────────

const EYE_W = 0.25;
const EYE_H = 0.27;
const EYE_SP = 0.37;
const EYE_P = -0.12;
const BASE_TOP: RGB = [0.929, 0.929, 0.937]; // #EDEDEF
const BASE_BOTTOM: RGB = [0.769, 0.773, 0.792]; // #C4C5CA
const INK = "rgb(26,20,18)"; // #1A1412
const MINI_INK = "rgb(16,19,26)"; // #10131A

const C = {
  idle: [0.902, 0.914, 0.933] as RGB,
  working: [0.231, 0.62, 1] as RGB,
  thinking: [0.545, 0.361, 0.965] as RGB,
  searching: [0.388, 0.396, 0.949] as RGB,
  approval: [0.961, 0.647, 0.141] as RGB,
  question: [0.133, 0.827, 0.933] as RGB,
  error: [0.957, 0.314, 0.369] as RGB,
  finished: [0.204, 0.831, 0.6] as RGB,
  ratelimit: [0.984, 0.573, 0.235] as RGB,
  sleeping: [0.58, 0.635, 0.722] as RGB,
  dizzy: [0.957, 0.447, 0.714] as RGB,
};

const base = {
  bounces: false, scans: false, breathes: false, zz: false, sweat: false,
  look: null, tilt: 0,
};

export const BOT_STATES: Record<BotStateName, BotStateCfg> = {
  idle: { ...base, color: C.idle, tint: 0, eye: "pill", badge: null },
  working: { ...base, color: C.working, tint: 0.72, eye: "pill", badge: { kind: "dots", color: C.working } },
  thinking: { ...base, color: C.thinking, tint: 0.72, eye: "pill", badge: { kind: "dots", color: C.thinking }, look: [0.55, 0.55] },
  searching: { ...base, color: C.searching, tint: 0.72, eye: "pill", badge: { kind: "dots", color: C.searching }, scans: true },
  approval: { ...base, color: C.approval, tint: 0.78, eye: "wide", badge: { kind: "bang", color: C.approval }, bounces: true },
  question: { ...base, color: C.question, tint: 0.75, eye: "pill", badge: { kind: "question", color: C.question }, tilt: 0.17 },
  error: { ...base, color: C.error, tint: 0.78, eye: "flat", badge: { kind: "dot", color: C.error } },
  finished: { ...base, color: C.finished, tint: 0.35, eye: "happy", badge: { kind: "dot", color: C.finished } },
  ratelimit: { ...base, color: C.ratelimit, tint: 0.72, eye: "tired", badge: { kind: "dot", color: C.ratelimit }, sweat: true },
  sleeping: { ...base, color: C.sleeping, tint: 0.32, eye: "closed", badge: null, breathes: true, zz: true },
  dizzy: { ...base, color: C.dizzy, tint: 0.7, eye: "spiral", badge: null },
};

/** State → sound, as in BotStateCfg.sound. */
export const STATE_SOUND: Partial<Record<BotStateName, string>> = {
  working: "work", thinking: "think", searching: "search", approval: "approval",
  question: "question", error: "error", finished: "finish", ratelimit: "rate",
  sleeping: "sleep", dizzy: "dizzy",
};

const EMOTE_EYE: Record<BotEmoteName, EyeShape> = {
  love: "heart", surprised: "dot", proud: "star", wink: "wink",
  yawn: "tired", happy: "happy", annoyed: "line",
};

// ── Small helpers ─────────────────────────────────────────────────────────────

const now = () => performance.now() / 1000;

export function hexToRGB(hex: string): RGB {
  const h = hex.replace("#", "");
  const v = parseInt(h, 16);
  return [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255];
}

const rgba = (c: RGB, a = 1) =>
  `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a})`;

const mix3 = (a: RGB, b: RGB, t: number): RGB => [
  lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t),
];

function roundRectPath(x: CanvasRenderingContext2D, X: number, Y: number, W: number, H: number, R: number) {
  const r = Math.max(0, Math.min(R, W / 2, H / 2));
  x.beginPath();
  x.moveTo(X + r, Y);
  x.arcTo(X + W, Y, X + W, Y + H, r);
  x.arcTo(X + W, Y + H, X, Y + H, r);
  x.arcTo(X, Y + H, X, Y, r);
  x.arcTo(X, Y, X + W, Y, r);
  x.closePath();
}

function heartPath(x: CanvasRenderingContext2D, s: number) {
  x.beginPath();
  x.moveTo(0, s * 0.38);
  x.bezierCurveTo(-s * 1.05, -s * 0.15, -s * 0.5, -s * 0.95, 0, -s * 0.38);
  x.bezierCurveTo(s * 0.5, -s * 0.95, s * 1.05, -s * 0.15, 0, s * 0.38);
  x.closePath();
}

/**
 * A four-point twinkle with concave sides — the shape of a glint, not of a star
 * in the sky. `starPath` is hard-coded to ten vertices, so this is its own
 * function rather than a parameter on that one.
 */
function sparklePath(r: number): Path2D {
  const p = new Path2D();
  const waist = r * 0.17;
  p.moveTo(0, -r);
  p.quadraticCurveTo(waist, -waist, r, 0);
  p.quadraticCurveTo(waist, waist, 0, r);
  p.quadraticCurveTo(-waist, waist, -r, 0);
  p.quadraticCurveTo(-waist, -waist, 0, -r);
  p.closePath();
  return p;
}

function starPath(x: CanvasRenderingContext2D, ro: number, ri: number) {
  x.beginPath();
  for (let i = 0; i < 10; i++) {
    const r = i % 2 ? ri : ro;
    const a = -Math.PI / 2 + (i * Math.PI) / 5;
    x.lineTo(Math.cos(a) * r, Math.sin(a) * r);
  }
  x.closePath();
}

const FONT = `system-ui, "Segoe UI Variable Text", "Segoe UI", sans-serif`;

// ── Engine ────────────────────────────────────────────────────────────────────

export class BotEngine {
  isMini = false;
  /** Solid body colour for mini bots / integration pills (null = Mochi gradient). */
  bodyColor: RGB | null = null;
  /**
   * Who this Mochi is: what it wears and what kind of eyes it has.
   *
   * Pushed in every frame beside `bodyColor`, never once at creation — the user
   * can change it in Settings while the island is on screen, and a value
   * captured at creation would go stale. Default is classic Mochi, which draws
   * exactly as it did before characters existed.
   */
  character: MochiCharacter = {};

  // Animated state (BotEngine `s`)
  yaw = 0; pitch = 0; roll = 0; tilt = 0; open = 1;
  sx = 1; sy = 1; oy = 0; ox = 0;
  tint = 0; morph = 0; hands = 0; blush = 0; es = 1; badgeS = 0;

  // Targets
  tgYaw = 0; tgPitch = 0; tgTilt = 0; tgSy = 1; tgSx = 1; tgEs = 1;

  /** Extra canvas height above the body so hearts can fly out without clipping. */
  particleOverhang = 0;

  // Mouth spring (fraction of R)
  slotH = 0; slotHTarget = 0; slotHVel = 0; isChewing = false;

  col: RGB = C.idle;
  colT: RGB = C.idle;

  state: BotStateName = "idle";
  cfg: BotStateCfg = BOT_STATES.idle;

  eyeOverride: EyeShape | null = null;
  eyeOverrideUntil = 0;
  permanentEye: EyeShape | null = null;
  permanentEmote: BotEmoteName | null = null;
  miniNextBehavior = 0;

  badge: Badge | null = null;
  private badgeKey = "none";
  private badgeToken = 0;

  private tweens = new Map<PropKey, Tween>();
  private locks = new Set<PropKey>();
  private particles: Particle[] = [];

  lookX = 0;
  lookY = 0;

  lastTime = now();
  private t0 = now() - Math.random() * 5;
  private nextBlink = now() + 1.5 + Math.random() * 2;
  waveUntil = 0;
  waveStart = 0;
  private greetToken = 0;
  private lastAmbient = 0;
  private slapTimes: number[] = [];
  private miniLookTarget = { x: 0, y: 0 };
  private miniLookNextTime = 0;

  /** Fired when three slaps land inside 1.7 s (→ dizzy + confused view). */
  onDizzy: (() => void) | null = null;

  // ── Public API ──────────────────────────────────────────────────────────────

  setState(next: BotStateName, force = false) {
    if (this.state === next && !force) return;
    const prev = this.state;
    this.state = next;
    this.cfg = BOT_STATES[next];
    this.colT = this.cfg.color;
    if (!this.locks.has("tint")) this.tint = this.cfg.tint;
    if (!this.locks.has("tilt")) this.tgTilt = this.cfg.tilt;
    this.setBadge(this.cfg.badge);

    switch (next) {
      case "finished":
        this.doRoll(950, 1);
        setTimeout(() => this.emit("spark", 5), 500);
        break;
      case "error":
        this.anim("ox", [
          [0.08, 50, Ease.out], [-0.08, 70, Ease.inOut],
          [0.05, 70, Ease.inOut], [0, 90, Ease.out],
        ]);
        break;
      case "approval":
        this.anim("oy", [[-0.2, 150, Ease.out], [0, 300, Ease.back]]);
        break;
      case "dizzy":
        this.doRoll(1300, 2);
        break;
      case "question":
        this.blink();
        break;
      case "ratelimit":
        this.emit("sweat", 1);
        break;
      default:
        if (prev !== "idle" || next !== "idle") this.blink();
    }
  }

  setBadge(b: Badge | null) {
    const key = b ? `${b.kind}-${b.color.join(",")}` : "none";
    if (key === this.badgeKey) return;
    this.badgeKey = key;
    const tok = ++this.badgeToken;
    this.anim("badgeS", [[0, 90, Ease.inOut]]);
    setTimeout(() => {
      if (tok !== this.badgeToken) return;
      this.badge = b;
      if (b) this.anim("badgeS", [[1, 280, Ease.back]]);
    }, 100);
  }

  blink() {
    if (this.locks.has("open")) return;
    this.anim("open", [[0.06, 70, Ease.inOut], [1, 130, Ease.out]]);
  }

  squash() {
    this.anim("sy", [[0.78, 70, Ease.out], [1.1, 130, Ease.out], [1, 170, Ease.inOut]]);
    this.anim("sx", [[1.16, 70, Ease.out], [0.95, 130, Ease.out], [1, 170, Ease.inOut]]);
  }

  /** Mailbox swallow — opens the slot, chews, then closes. */
  gulp() {
    this.slotHTarget = 0.42;
    setTimeout(() => {
      this.slotHTarget = 0;
      this.isChewing = true;
      setTimeout(() => { this.isChewing = false; }, 800);
    }, 460);
    this.anim("sy", [[0.78, 80, Ease.out], [1.18, 130, Ease.out], [1, 220, Ease.back]]);
    this.anim("sx", [[1.28, 80, Ease.out], [0.92, 130, Ease.out], [1, 220, Ease.back]]);
    this.blink();
  }

  slap() {
    this.interruptGreet();
    if (this.state === "dizzy") return;
    const t = now();
    this.slapTimes = this.slapTimes.filter((s) => t - s < 1.7);
    this.slapTimes.push(t);
    Sound.play("slap");
    this.squash();
    if (this.slapTimes.length >= 3) {
      this.slapTimes = [];
      this.onDizzy?.();
    } else {
      this.eyeOverride = "line";
      this.eyeOverrideUntil = t + 0.8;
      setTimeout(() => Sound.play("annoyed"), 60);
    }
  }

  doRoll(durationMs: number, turns: number) {
    this.roll = 0;
    this.anim("roll", [[Math.PI * 2 * turns, durationMs, Ease.inOut]], () => { this.roll = 0; });
  }

  /** Peek wave — the "coucou". Timings from BotEngine.greet(). */
  greet() {
    const t = now();
    const tok = ++this.greetToken;
    this.waveStart = t + 0.45;
    this.waveUntil = t + 1.55;

    this.eyeOverride = "happy";
    this.eyeOverrideUntil = t + 2.0;
    this.anim("oy", [[-0.06, 220, Ease.out], [0.0, 220, Ease.back]]);

    setTimeout(() => {
      if (this.greetToken !== tok) return;
      this.anim("hands", [[1, 280, Ease.out]]);
      this.anim("sy", [[0.95, 100, Ease.out], [1.0, 260, Ease.back]]);
      this.anim("sx", [[1.04, 100, Ease.out], [1.0, 260, Ease.back]]);
      Sound.play("greet");
    }, 250);

    setTimeout(() => { if (this.greetToken === tok) this.blink(); }, 550);
    setTimeout(() => { if (this.greetToken === tok) this.blink(); }, 1500);
    setTimeout(() => {
      if (this.greetToken !== tok) return;
      this.waveUntil = 0;
      this.anim("hands", [[0, 200, Ease.inOut]]);
    }, 1550);
    setTimeout(() => {
      if (this.greetToken !== tok) return;
      this.eyeOverride = "happy";
      this.eyeOverrideUntil = now() + 0.3;
    }, 1750);
  }

  interruptGreet() {
    if (this.hands <= 0.01 && now() >= this.waveUntil) return;
    this.greetToken++;
    this.waveUntil = 0;
    this.waveStart = 0;
    this.anim("hands", [[0, 150, Ease.inOut]]);
  }

  setPermanentEmote(emote: BotEmoteName | null) {
    this.permanentEmote = emote;
    if (emote === "wink") {
      this.miniNextBehavior = now() + 0.8 + Math.random() * 1.7;
      return;
    }
    this.permanentEye = emote ? EMOTE_EYE[emote] : null;
    if (this.permanentEye) {
      this.eyeOverride = this.permanentEye;
      this.eyeOverrideUntil = Number.POSITIVE_INFINITY;
    } else if (this.eyeOverrideUntil === Number.POSITIVE_INFINITY) {
      this.eyeOverride = null;
      this.eyeOverrideUntil = 0;
    }
    this.miniNextBehavior = now() + 0.8 + Math.random() * 1.7;
  }

  triggerEmote(emote: BotEmoteName, duration = 1.8) {
    const t = now();
    this.eyeOverride = EMOTE_EYE[emote];
    this.eyeOverrideUntil = t + duration;

    switch (emote) {
      case "love":
        this.anim("blush", [
          [1, 300, Ease.out], [1, (duration - 0.6) * 1000, Ease.lin], [0, 300, Ease.inOut],
        ]);
        this.emit("heart", 4);
        this.anim("oy", [[-0.1, 160, Ease.out], [0, 300, Ease.back]]);
        break;
      case "surprised":
        this.anim("oy", [[-0.3, 140, Ease.out], [0, 380, Ease.back]]);
        this.anim("es", [[1.25, 120, Ease.out], [1, 500, Ease.inOut]]);
        break;
      case "proud":
        this.emit("star", 5);
        this.anim("tilt", [
          [-0.14, 220, Ease.out], [-0.14, (duration - 0.5) * 1000, Ease.lin], [0, 280, Ease.inOut],
        ]);
        this.anim("blush", [
          [0.7, 250, Ease.out], [0.7, (duration - 0.5) * 1000, Ease.lin], [0, 300, Ease.inOut],
        ]);
        break;
      case "wink":
        this.anim("tilt", [
          [0.12, 160, Ease.out], [0.12, (duration - 0.4) * 1000, Ease.lin], [0, 240, Ease.inOut],
        ]);
        break;
      case "yawn":
        this.anim("sy", [[1.12, 500, Ease.inOut], [1, 500, Ease.inOut]]);
        this.anim("sx", [[0.94, 500, Ease.inOut], [1, 500, Ease.inOut]]);
        setTimeout(() => { this.eyeOverride = "closed"; this.emit("z", 2); }, 700);
        break;
      case "happy":
        this.anim("blush", [[0.6, 200, Ease.out], [0, 600, Ease.inOut]]);
        break;
      case "annoyed":
        this.eyeOverride = "line";
        this.eyeOverrideUntil = t + 0.8;
        setTimeout(() => Sound.play("annoyed"), 60);
        break;
    }
  }

  emit(type: Particle["type"], count: number) {
    for (let i = 0; i < count; i++) {
      const isZ = type === "z";
      this.particles.push({
        type,
        x: (Math.random() - 0.5) * 0.9 + (isZ ? 0.55 : 0),
        y: -0.7 - Math.random() * 0.2,
        vx: (Math.random() - 0.5) * 0.35 + (isZ ? 0.18 : 0),
        vy: -(0.45 + Math.random() * 0.35),
        age: -i * 0.14,
        life: 1.3 + Math.random() * 0.5,
        rot: Math.random() * Math.PI * 2,
        size: 0.15 + Math.random() * 0.08,
      });
    }
  }

  animateMorph(target: number, durationMs?: number) {
    const dur = durationMs ?? (target > 0.5 ? 550 : 650);
    this.anim("morph", [[target, dur, Ease.inOut]]);
  }

  resetMorph() {
    this.tweens.delete("morph");
    this.locks.delete("morph");
    this.morph = 0;
  }

  /** True while anything is still moving — lets the island stop its RAF loop. */
  get busy(): boolean {
    return (
      this.tweens.size > 0 ||
      this.particles.length > 0 ||
      this.cfg.bounces || this.cfg.scans || this.cfg.breathes || this.cfg.zz || this.cfg.sweat ||
      this.isMini ||
      Math.abs(this.tgYaw - this.yaw) > 0.002 ||
      Math.abs(this.tgPitch - this.pitch) > 0.002 ||
      Math.abs(this.tgTilt - this.tilt) > 0.002 ||
      Math.abs(this.tgSy - this.sy) > 0.002 ||
      Math.abs(this.tgSx - this.sx) > 0.002 ||
      Math.abs(this.tgEs - this.es) > 0.002 ||
      this.slotH > 0.001 || Math.abs(this.slotHVel) > 0.001 ||
      Math.abs(this.col[0] - this.colT[0]) > 0.003 ||
      Math.abs(this.col[1] - this.colT[1]) > 0.003 ||
      Math.abs(this.col[2] - this.colT[2]) > 0.003
    );
  }

  // ── Tweens ──────────────────────────────────────────────────────────────────

  anim(prop: PropKey, keys: TweenKey[], onComplete?: () => void) {
    this.tweens.set(prop, {
      prop, keys, index: 0, from: this[prop], startMs: performance.now(), onComplete,
    });
    this.locks.add(prop);
  }

  // ── Update ──────────────────────────────────────────────────────────────────

  update(dt: number) {
    const n = now();
    const nowMs = performance.now();

    for (const tw of [...this.tweens.values()]) {
      const k = tw.keys[tw.index];
      const p = Math.min(1, Math.max(0, (nowMs - tw.startMs) / k[1]));
      this[tw.prop] = tw.from + (k[0] - tw.from) * k[2](p);
      if (p >= 1) {
        tw.from = k[0];
        tw.index += 1;
        tw.startMs = nowMs;
        if (tw.index >= tw.keys.length) {
          this.tweens.delete(tw.prop);
          this.locks.delete(tw.prop);
          tw.onComplete?.();
        }
      }
    }

    const t = n - this.t0;
    let ty = this.lookX * 0.62;
    let tp = this.lookY * 0.5;

    if (this.cfg.look) {
      ty = ty * 0.35 + this.cfg.look[0] * 0.55;
      tp = tp * 0.3 + this.cfg.look[1] * 0.5;
    }
    if (this.cfg.scans) {
      ty = Math.sin(t * 2.6) * 0.6;
      tp = -0.06;
    }
    if (this.state === "sleeping") { ty = 0; tp = -0.14; }
    if (this.state === "dizzy") { ty = Math.sin(t * 9) * 0.25; }

    // Mini bots never follow the mouse — they wander.
    if (this.isMini && !this.cfg.look && !this.cfg.scans && this.state !== "sleeping" && this.state !== "dizzy") {
      if (n > this.miniLookNextTime) {
        this.miniLookTarget = {
          x: -0.88 + Math.random() * 1.76,
          y: -0.55 + Math.random() * 1.0,
        };
        this.miniLookNextTime = n + 0.5 + Math.random() * 1.5;
      }
      ty = this.miniLookTarget.x * 0.62;
      tp = this.miniLookTarget.y * 0.5;
    }

    this.tgYaw = ty;
    this.tgPitch = tp;
    this.tgTilt = this.cfg.tilt;

    if (n > this.waveStart && n < this.waveUntil) {
      const wt = n - this.waveStart;
      this.tgTilt = -0.06 + Math.sin(2 * Math.PI * 1.2 * wt) * 0.07;
    }

    const bounce = this.cfg.bounces ? -Math.abs(Math.sin(t * 5.2)) * 0.07 : 0;
    const kGen = 1 - Math.pow(0.0008, dt);
    if (!this.locks.has("oy")) this.oy += (bounce - this.oy) * kGen;

    if (this.cfg.breathes) {
      const amp = this.isMini ? 0.07 : 0.035;
      this.tgSy = 1 + Math.sin(t * 1.8) * amp;
      this.tgSx = 1 - Math.sin(t * 1.8) * amp * 0.57;
    } else if (this.isMini) {
      this.tgSy = 1 + Math.sin(t * 2.2) * 0.04;
      this.tgSx = 1 - Math.sin(t * 2.2) * 0.02;
    } else {
      this.tgSy = 1;
      this.tgSx = 1;
    }

    if (this.isMini && n > this.miniNextBehavior) this.doMiniBehaviorLoop();

    const kLook = 1 - Math.pow(0.0025, dt);
    if (!this.locks.has("yaw")) this.yaw += (this.tgYaw - this.yaw) * kLook;
    if (!this.locks.has("pitch")) this.pitch += (this.tgPitch - this.pitch) * kLook;
    if (!this.locks.has("tilt")) this.tilt += (this.tgTilt - this.tilt) * kGen;
    if (!this.locks.has("sy")) this.sy += (this.tgSy - this.sy) * kGen;
    if (!this.locks.has("sx")) this.sx += (this.tgSx - this.sx) * kGen;
    if (!this.locks.has("es")) this.es += (this.tgEs - this.es) * kGen;

    this.col = mix3(this.col, this.colT, 1 - Math.pow(0.002, dt));

    if (n > this.nextBlink) {
      if (this.state !== "sleeping" && this.state !== "dizzy") {
        this.blink();
        if (Math.random() < 0.22) setTimeout(() => this.blink(), 230);
      }
      this.nextBlink = n + 2.2 + Math.random() * 3.2;
    }

    if (this.eyeOverride && n > this.eyeOverrideUntil) {
      this.eyeOverride = this.permanentEye;
      if (this.permanentEye) this.eyeOverrideUntil = Number.POSITIVE_INFINITY;
    }

    if (n - this.lastAmbient > 1.3) {
      this.lastAmbient = n;
      if (this.cfg.zz) this.emit("z", 1);
      if (!this.isMini && this.cfg.sweat && Math.random() < 0.5) this.emit("sweat", 1);
    }

    for (const p of this.particles) p.age += dt;
    this.particles = this.particles.filter((p) => p.age < p.life);

    // Mouth slot spring — ω₀ = 2π/0.25, ζ = 0.6
    const omega = (2 * Math.PI) / 0.25;
    const zeta = 0.6;
    const acc = omega * omega * (this.slotHTarget - this.slotH) - 2 * zeta * omega * this.slotHVel;
    this.slotHVel += acc * dt;
    this.slotH = Math.max(0, this.slotH + this.slotHVel * dt);

    this.lastTime = n;
  }

  private doMiniBehaviorLoop() {
    const n = now();
    switch (this.permanentEmote) {
      case "happy":
        if (this.locks.has("oy")) { this.miniNextBehavior = n + 0.4; return; }
        this.anim("oy", [[-0.3, 120, Ease.out], [0.03, 200, Ease.inOut], [0, 160, Ease.back]]);
        this.anim("sy", [[0.82, 80, Ease.out], [1.18, 130, Ease.out], [0.88, 160, Ease.inOut], [1, 200, Ease.back]]);
        this.anim("sx", [[1.15, 80, Ease.out], [0.88, 130, Ease.out], [1.06, 160, Ease.inOut], [1, 200, Ease.back]]);
        this.miniNextBehavior = n + 2.2 + Math.random() * 1.2;
        break;
      case "annoyed":
        if (this.locks.has("yaw")) { this.miniNextBehavior = n + 0.5; return; }
        this.anim("yaw", [
          [-0.65, 50, Ease.out], [0.65, 90, Ease.inOut], [-0.5, 80, Ease.inOut],
          [0.4, 75, Ease.inOut], [-0.2, 70, Ease.inOut], [0, 140, Ease.out],
        ]);
        this.miniNextBehavior = n + 3.0 + Math.random() * 2.5;
        break;
      case "wink":
        this.eyeOverride = "wink";
        this.eyeOverrideUntil = n + 0.55;
        this.anim("tilt", [[0.13, 100, Ease.out], [0.13, 320, Ease.lin], [0, 200, Ease.inOut]]);
        this.miniNextBehavior = n + 2.2 + Math.random() * 2.0;
        break;
      case "love":
        this.emit("heart", 2);
        this.anim("tilt", [[-0.1, 180, Ease.out], [0.1, 340, Ease.inOut], [0, 220, Ease.inOut]]);
        this.miniNextBehavior = n + 2.6 + Math.random() * 1.5;
        break;
      default:
        this.miniNextBehavior = n + 3.0 + Math.random() * 2.0;
    }
  }

  // ── Draw ────────────────────────────────────────────────────────────────────

  /**
   * Draws hands, body, blush, eyes, mouth, badge and particles into a canvas of
   * `w`×`h` CSS pixels (the caller has already applied the DPR transform).
   */
  draw(x: CanvasRenderingContext2D, W: number, H: number) {
    const R = W * 0.3;
    const rx = R * 1.14;
    const ry = R * 0.88;
    const cx = W / 2 + this.ox * R;
    const cy = H / 2 + this.particleOverhang / 2 + this.oy * R + R * 0.06;

    this.drawHandsBehind(x, R, rx, ry, cx, cy);

    x.save();
    x.translate(cx, cy);
    if (this.tilt !== 0) x.rotate(this.tilt);
    x.scale(this.sx, this.sy);

    const body = this.bodyPath(rx, ry, R);
    // Behind the body, so it swallows their base and they look grown rather
    // than stuck on. (Swift has to snapshot the context here because its
    // `drawEyes` leaves the clip on; this one saves and restores.)
    this.drawAccessory(x, true, R, rx, ry, body);
    this.drawBody(x, body, R, rx, ry);

    const blushVal = Math.max(this.blush, this.tint * 0.5) * (1 - this.morph);
    if (blushVal > 0.01) {
      x.save();
      x.clip(body);
      const yOffset = Math.sin(this.yaw) * rx * 0.8;
      x.fillStyle = `rgba(255,120,150,${0.5 * blushVal})`;
      for (const sd of [-1, 1]) {
        x.beginPath();
        x.ellipse(sd * rx * 0.55 + yOffset, ry * 0.2, R * 0.17, R * 0.1, 0, 0, Math.PI * 2);
        x.fill();
      }
      x.restore();
    }

    this.drawEyes(x, body, R, rx, ry);
    if (this.morph > 0.05) this.drawMouth(x, body, R);
    this.drawAccessory(x, false, R, rx, ry, body);

    x.restore();

    if (this.badge && this.badgeS > 0.01 && this.morph < 0.25) {
      this.drawBadge(x, this.badge, R, cx, cy);
    }
    this.drawParticles(x, R, cx, cy);
  }

  private bodyPath(rx: number, ry: number, R: number): Path2D {
    const n = 72;
    const expN = 2.0 / 2.7;
    const tw = R * 1.0;
    const th = R * 0.94;
    const tr = R * 0.42;
    const p = new Path2D();
    const m = this.morph;
    for (let i = 0; i <= n; i++) {
      const a = (i / n) * Math.PI * 2;
      const ca = Math.cos(a);
      const sa = Math.sin(a);
      const px0 = rx * (ca >= 0 ? Math.pow(ca, expN) : -Math.pow(-ca, expN));
      const py0 = ry * (sa >= 0 ? Math.pow(sa, expN) : -Math.pow(-sa, expN));
      let px = px0;
      let py = py0;
      if (m >= 0.005) {
        const rr = rrPoint(ca, sa, tw, th, tr);
        px = lerp(px0, rr.x, m);
        py = lerp(py0, rr.y, m);
      }
      if (i === 0) p.moveTo(px, py);
      else p.lineTo(px, py);
    }
    p.closePath();
    return p;
  }

  private drawBody(x: CanvasRenderingContext2D, body: Path2D, R: number, rx: number, ry: number) {
    if (this.bodyColor) {
      // Mini bots: flat solid fill — no gradient, no reflection, no highlight
      x.fillStyle = rgba(this.bodyColor, 1);
      x.fill(body);
      return;
    }
    const g = x.createLinearGradient(rx * 0.7, -ry * 0.85, -rx * 0.8, ry * 0.9);
    g.addColorStop(0, rgba(BASE_TOP));
    g.addColorStop(1, rgba(BASE_BOTTOM));
    x.fillStyle = g;
    x.fill(body);

    const effectiveTint = this.tint * (1 - this.morph);
    if (effectiveTint > 0.01) {
      const tg = x.createLinearGradient(0, ry, 0, -ry);
      tg.addColorStop(0, rgba(this.col, 0.72 * effectiveTint));
      tg.addColorStop(1, rgba(this.col, 0));
      x.fillStyle = tg;
      x.fill(body);
    }

    const sh = x.createRadialGradient(0, 0, R * 0.15, 0, 0, R * 1.25);
    sh.addColorStop(0, "rgba(0,0,0,0)");
    sh.addColorStop(0.6, "rgba(0,0,0,0)");
    sh.addColorStop(1, "rgba(0,0,0,0.2)");
    x.fillStyle = sh;
    x.fill(body);

    const hl = x.createRadialGradient(rx * 0.34, -ry * 0.46, 0, rx * 0.34, -ry * 0.46, R * 0.42);
    hl.addColorStop(0, "rgba(255,255,255,0.55)");
    hl.addColorStop(1, "rgba(255,255,255,0)");
    x.fillStyle = hl;
    x.fill(body);
  }

  // ── Accessories ────────────────────────────────────────────────────────────

  /**
   * A point on the head, projected the same way the eyes are.
   *
   * Everything a Mochi wears hangs off this, which is what makes a crown slide
   * exactly as an eye does when the head turns, and ride right round the head
   * during the dizzy roll.
   *
   * `a0` 0 faces you, positive is the bot's left; `e0` +PI/2 is the crown of the
   * head. `cullAt` is how far round the back before it is gone — not 0.04 for
   * anything on top: near the pole cos(elevation) is small, so a crown would
   * blink out of existence on a modest head turn.
   */
  private headPoint(a0: number, e0: number, rx: number, ry: number, cullAt: number) {
    const az = a0 + this.yaw;
    let el = e0 + this.pitch + this.roll;
    el = (((el + Math.PI) % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2) - Math.PI;
    const ce = Math.cos(el);
    const depth = Math.cos(az) * ce;
    if (depth <= cullAt) return null;
    // Foreshortening is relative to where the thing sits at rest, not absolute.
    // An eye lives near the equator, so cos(elevation) is ~1 for it either way —
    // but a crown lives near the pole, where cos is small before the head has
    // moved at all. Taken absolutely it would crush every hat flat the moment it
    // was drawn. Dividing by the rest value means 1 at rest and squashing only
    // as the head actually turns.
    const clamp = (v: number) => Math.min(Math.max(v, 0.2), 1.6);
    const restX = Math.max(0.12, Math.cos(a0));
    const restY = Math.max(0.12, Math.abs(Math.cos(e0)));
    return {
      x: Math.sin(az) * ce * rx,
      y: -Math.sin(el) * ry,
      fx: clamp(Math.max(0.18, Math.cos(az)) / restX),
      fy: clamp(Math.max(0.18, Math.abs(ce)) / restY),
      // Ramped rather than cut, so nothing pops at the boundary.
      alpha: Math.min(Math.max((depth - cullAt) / 0.25, 0), 1),
    };
  }

  /**
   * How much of an accessory is worth drawing at this size.
   *
   * Minis run at R = 6, 8 and 11 px. The accessory is the user's identity
   * choice, so these degrade rather than disappear — a crown that vanished on
   * the 12 px grid would defeat the whole feature.
   */
  private detail(R: number): "full" | "simple" | "silhouette" {
    return R > 16 ? "full" : R > 11 ? "simple" : "silhouette";
  }

  /** The creature's own material, for the parts that are made of Mochi. */
  private bodyMaterial(darken: number): string {
    const c = this.bodyColor ?? BASE_TOP;   // components 0…1
    const k = (1 - darken) * 255;
    return `rgb(${Math.round(c[0] * k)},${Math.round(c[1] * k)},${Math.round(c[2] * k)})`;
  }

  /**
   * Places an accessory's own little coordinate frame on the head, and returns
   * the alpha it should be drawn at. The caller restores.
   */
  private anchor(
    x: CanvasRenderingContext2D, a0: number, e0: number,
    rx: number, ry: number, cullAt: number, fade: number, lift: number, rotate = 0,
  ): number | null {
    const p = this.headPoint(a0, e0, rx, ry, cullAt);
    if (!p) return null;
    x.save();
    x.translate(p.x, p.y - lift);
    x.scale(p.fx, p.fy);
    if (rotate !== 0) x.rotate(rotate);
    return p.alpha * fade;
  }

  /**
   * Ears, horns, antenna, sprout before the body so it swallows their base;
   * crown, bow, beret, sparkles after it, since they have to overhang the
   * silhouette to read as worn.
   */
  drawAccessory(
    x: CanvasRenderingContext2D, behind: boolean,
    R: number, rx: number, ry: number, body: Path2D,
  ) {
    const item = this.character.accessory;
    if (!item || isBehind(item) !== behind || R <= 4) return;

    // A mailbox wears nothing. Gone well before the box is recognisable.
    const fade = Math.min(Math.max(1 - this.morph * 1.6, 0), 1);
    if (fade <= 0.02) return;
    const detail = this.detail(R);
    const lift = ry * 0.06 * this.morph;   // lift off rather than sink in

    x.save();
    switch (item) {
      case "catEars":  this.accCatEars(x, R, rx, ry, fade, lift, detail); break;
      case "horns":    this.accHorns(x, R, rx, ry, fade, lift, detail); break;
      case "antenna":  this.accAntenna(x, R, rx, ry, fade, lift, detail); break;
      case "sprout":   this.accSprout(x, R, rx, ry, fade, lift, detail); break;
      case "sparkles": this.accSparkles(x, R, rx, ry, fade, lift, detail); break;
      case "bow":      this.accBow(x, R, rx, ry, fade, lift, detail); break;
      case "crown":    this.accCrown(x, R, rx, ry, fade, lift, detail); break;
      case "beret":    this.accBeret(x, R, rx, ry, fade, lift, detail, body); break;
    }
    x.restore();
  }

  // Each accessory's geometry is in units of R, so minis and the big bot share
  // one set of numbers.

  private accCatEars(x: CanvasRenderingContext2D, R: number, rx: number, ry: number,
                     fade: number, lift: number, detail: string) {
    for (const sd of [-1, 1]) {
      const alpha = this.anchor(x, sd * 0.62, 1.02, rx, ry, -0.20, fade, lift,
                                sd * 0.38 + Math.sin(sd * 0.62 + this.yaw) * 0.25);
      if (alpha === null) continue;
      x.globalAlpha = alpha;
      const ear = new Path2D();
      ear.moveTo(-R * 0.32, R * 0.18);
      // Bulged rather than straight, or it is a tortilla chip.
      ear.quadraticCurveTo(-R * 0.28, -R * 0.38, 0, -R * 0.80);
      ear.quadraticCurveTo(R * 0.28, -R * 0.38, R * 0.32, R * 0.18);
      ear.closePath();
      x.fillStyle = this.bodyMaterial(0.14);
      x.fill(ear);
      if (detail !== "silhouette") {
        const inner = new Path2D();
        inner.addPath(ear, new DOMMatrix().translateSelf(0, R * 0.10).scaleSelf(0.52, 0.52));
        x.fillStyle = "rgba(255,120,150,0.5)";
        x.fill(inner);
      }
      x.restore();
    }
  }

  private accHorns(x: CanvasRenderingContext2D, R: number, rx: number, ry: number,
                   fade: number, lift: number, detail: string) {
    for (const sd of [-1, 1]) {
      const alpha = this.anchor(x, sd * 0.50, 1.12, rx, ry, -0.20, fade, lift);
      if (alpha === null) continue;
      x.globalAlpha = alpha;
      const horn = new Path2D();
      horn.moveTo(-sd * R * 0.13, R * 0.10);
      horn.quadraticCurveTo(sd * R * 0.015, -R * 0.30, sd * R * 0.17, -R * 0.62);
      horn.quadraticCurveTo(sd * R * 0.26, -R * 0.26, sd * R * 0.15, R * 0.10);
      horn.closePath();
      x.fillStyle = "#F3E3C4";
      x.fill(horn);
      if (detail === "full") {
        x.strokeStyle = "rgba(26,20,18,0.16)";
        x.lineWidth = Math.max(R * 0.035, 0.75);
        x.lineCap = "round";
        for (const t of [0.32, 0.52, 0.72]) {
          const y = lerp(R * 0.06, -R * 0.50, t);
          const half = lerp(R * 0.12, R * 0.045, t);
          x.beginPath();
          x.moveTo(-half * 0.6 + sd * R * 0.02, y);
          x.lineTo(half + sd * R * 0.02, y - R * 0.02);
          x.stroke();
        }
      }
      x.restore();
    }
  }

  private accAntenna(x: CanvasRenderingContext2D, R: number, rx: number, ry: number,
                     fade: number, lift: number, detail: string) {
    const alpha = this.anchor(x, 0, 1.30, rx, ry, -0.60, fade, lift);
    if (alpha === null) return;
    x.globalAlpha = alpha;

    // No velocity is stored anywhere, but `yaw` lags its target by construction
    // — so the gap between them *is* the head's speed, free and with no new
    // state to fall out of sync.
    const sway = (this.yaw - this.tgYaw) * R * 0.9;
    const bob = (this.pitch - this.tgPitch) * R * 0.5;
    const tipX = sway;
    const tipY = -R * 0.62 + bob;

    if (detail !== "silhouette") {
      x.strokeStyle = this.bodyMaterial(0.22);
      x.lineWidth = Math.max(R * 0.085, 0.9);
      x.lineCap = "round";
      x.beginPath();
      x.moveTo(0, 0);
      x.quadraticCurveTo(sway * 0.35, -R * 0.34, tipX, tipY);
      x.stroke();
    }
    // Below that, the stalk is sub-pixel: the ball alone reads as a bobble.
    const bx = detail === "silhouette" ? 0 : tipX;
    const by = detail === "silhouette" ? -R * 0.42 : tipY;
    const r = R * (detail === "silhouette" ? 0.182 : 0.135);
    x.fillStyle = "#FF4D6D";
    x.beginPath();
    x.ellipse(bx, by, r, r, 0, 0, Math.PI * 2);
    x.fill();
    if (detail === "full") {
      x.fillStyle = "rgba(255,255,255,0.75)";
      x.beginPath();
      x.ellipse(bx - r * 0.26, by - r * 0.41, r * 0.26, r * 0.19, 0, 0, Math.PI * 2);
      x.fill();
    }
    x.restore();
  }

  private accSprout(x: CanvasRenderingContext2D, R: number, rx: number, ry: number,
                    fade: number, lift: number, detail: string) {
    const alpha = this.anchor(x, 0.10, 1.33, rx, ry, -0.60, fade, lift);
    if (alpha === null) return;
    x.globalAlpha = alpha;
    const green = "#34D399";
    const t = now();

    x.strokeStyle = green;
    x.lineWidth = Math.max(R * 0.07, 0.9);
    x.lineCap = "round";
    x.beginPath();
    x.moveTo(0, 0);
    x.quadraticCurveTo(-R * 0.02, -R * 0.14, R * 0.01, -R * 0.26);
    x.stroke();

    // Two leaves off the top of a short stem, spreading apart — the shape you
    // recognise as something sprouting rather than a bent twig.
    const leaves = detail === "silhouette"
      ? [[1.0, -1.35]]
      : [[0.92, -1.35], [1.0, -0.15]];
    leaves.forEach(([at, rot], i) => {
      x.save();
      x.translate(R * 0.01 * at, -R * 0.26 * at);
      x.rotate(rot + Math.sin(t * 1.6 + i) * 0.07);
      const len = R * (detail === "silhouette" ? 0.40 : 0.36);
      const half = R * 0.13;
      const blade = new Path2D();
      blade.moveTo(0, 0);
      blade.quadraticCurveTo(len * 0.5, -half, len, 0);
      blade.quadraticCurveTo(len * 0.5, half, 0, 0);
      blade.closePath();
      x.fillStyle = green;
      x.fill(blade);
      if (detail === "full") {
        x.strokeStyle = "rgba(0,0,0,0.12)";
        x.lineWidth = Math.max(R * 0.012, 0.5);
        x.beginPath();
        x.moveTo(0, 0);
        x.lineTo(len * 0.9, 0);
        x.stroke();
      }
      x.restore();
    });
    x.restore();
  }

  private accSparkles(x: CanvasRenderingContext2D, R: number, rx: number, ry: number,
                      fade: number, lift: number, detail: string) {
    const t = now();
    // Quieter while the bot is throwing its own sparks, so the state signal
    // stays louder than the decoration.
    const busy = this.particles.some((p) => p.type === "spark") ? 0.4 : 1;
    const spec: [number, number, number][] = [
      [-1.05, 0.80, 0.21], [0.95, 1.02, 0.16],
      [-0.45, 1.34, 0.12], [1.20, 0.48, 0.17],
    ];
    const shown = detail === "silhouette" ? spec.slice(0, 2) : spec;
    shown.forEach(([a0, e0, size], i) => {
      const p = this.headPoint(a0, e0, rx, ry, -0.35);
      if (!p) return;
      const twinkle = 0.35 + 0.65 * Math.max(0, Math.sin(t * 2.1 + i * 1.7));
      x.save();
      // Pushed out so they float off the surface rather than sit on it.
      x.translate(p.x * 1.26, p.y * 1.26 - lift);
      x.rotate(t * 0.6 + i);
      x.globalAlpha = p.alpha * fade * twinkle * busy;
      x.fillStyle = "#F7B32B";
      x.fill(sparklePath(R * size * (0.75 + 0.35 * twinkle)));
      x.restore();
    });
  }

  private accBow(x: CanvasRenderingContext2D, R: number, rx: number, ry: number,
                 fade: number, lift: number, detail: string) {
    const alpha = this.anchor(x, -0.72, 0.88, rx, ry, 0.0, fade, lift,
                              0.22 + Math.sin(this.yaw) * 0.18);
    if (alpha === null) return;
    x.globalAlpha = alpha;
    const pink = "#FF4D6D";

    if (detail !== "silhouette") {
      x.strokeStyle = pink;
      x.lineWidth = Math.max(R * 0.07, 0.8);
      x.lineCap = "round";
      for (const sd of [-1, 1]) {
        x.beginPath();
        x.moveTo(0, 0);
        x.quadraticCurveTo(sd * R * 0.02, R * 0.16, sd * R * 0.18, R * 0.28);
        x.stroke();
      }
    }
    x.fillStyle = pink;
    for (const sd of [-1, 1]) {
      const loop = new Path2D();
      loop.moveTo(0, 0);
      loop.quadraticCurveTo(sd * R * 0.20, -R * 0.24, sd * R * 0.40, -sd * R * 0.02);
      loop.quadraticCurveTo(sd * R * 0.22, R * 0.20, 0, 0);
      loop.closePath();
      x.fill(loop);
    }
    const knot = new Path2D();
    knot.roundRect(-R * 0.065, -R * 0.055, R * 0.13, R * 0.11, R * 0.05);
    x.fillStyle = "#D43B57";
    x.fill(knot);
    x.restore();
  }

  private accCrown(x: CanvasRenderingContext2D, R: number, rx: number, ry: number,
                   fade: number, lift: number, detail: string) {
    const alpha = this.anchor(x, 0, 1.17, rx, ry, -0.35, fade, lift,
                              Math.sin(this.yaw) * 0.16);   // a crown tips
    if (alpha === null) return;
    x.globalAlpha = alpha;

    const points = new Path2D();
    points.moveTo(-R * 0.40, -R * 0.02);
    points.lineTo(-R * 0.26, -R * 0.34);
    points.lineTo(-R * 0.13, -R * 0.08);
    points.lineTo(0, -R * 0.40);
    points.lineTo(R * 0.13, -R * 0.08);
    points.lineTo(R * 0.26, -R * 0.34);
    points.lineTo(R * 0.40, -R * 0.02);
    points.closePath();

    // At 6 px the band and jewels are mush; the silhouette is what carries the
    // identity, so draw only that.
    if (detail === "silhouette") {
      x.fillStyle = "#F7B32B";
      x.fill(points);
      x.restore();
      return;
    }

    const g = x.createLinearGradient(0, -R * 0.40, 0, R * 0.14);
    g.addColorStop(0, "#F7B32B");
    g.addColorStop(1, "#D99415");
    x.fillStyle = g;
    x.fill(points);

    const band = new Path2D();
    band.roundRect(-R * 0.40, -R * 0.04, R * 0.80, R * 0.18, R * 0.05);
    x.fillStyle = "#E8A520";
    x.fill(band);

    if (detail === "full") {
      const jewels: [number, string][] = [[-0.26, "#FF4D6D"], [0, "#7CC7FF"], [0.26, "#FF4D6D"]];
      for (const [jx, hex] of jewels) {
        x.fillStyle = hex;
        x.beginPath();
        x.ellipse(R * jx, -R * 0.27, R * 0.045, R * 0.045, 0, 0, Math.PI * 2);
        x.fill();
      }
    }
    x.restore();
  }

  private accBeret(x: CanvasRenderingContext2D, R: number, rx: number, ry: number,
                   fade: number, lift: number, detail: string, body: Path2D) {
    // The contact shadow is what makes it sit *on* the head. Clipped, or it
    // smears off the side. Drawn before the anchor, in body coordinates.
    if (detail !== "silhouette") {
      x.save();
      x.clip(body);
      x.globalAlpha = fade * 0.18;
      x.fillStyle = "#000000";
      x.beginPath();
      x.ellipse(-R * 0.10, -ry * 0.72, R * 0.23, R * 0.05, 0, 0, Math.PI * 2);
      x.fill();
      x.restore();
    }

    // Anchored lower than the other hats: a beret is pulled down over the head,
    // and one perched on top looks like it is about to blow off.
    const alpha = this.anchor(x, -0.34, 1.02, rx, ry, -0.30, fade, lift,
                              -0.24 + Math.sin(this.yaw) * 0.14);
    if (alpha === null) return;
    x.globalAlpha = alpha;

    // Flat-bottomed, and wider than the head it sits on — the overhang is what
    // makes it a beret rather than a smudge.
    x.fillStyle = "#1F2228";
    x.beginPath();
    x.ellipse(0, R * 0.05, R * 0.62, R * 0.34, 0, Math.PI, Math.PI * 2);
    x.closePath();
    x.fill();

    const brim = new Path2D();
    brim.roundRect(-R * 0.64, R * 0.01, R * 1.28, R * 0.095, R * 0.047);
    x.fillStyle = "#0E1013";
    x.fill(brim);

    if (detail !== "silhouette") {
      x.fillStyle = "#333842";
      x.beginPath();
      x.ellipse(-R * 0.14, -R * 0.26, R * 0.065, R * 0.065, 0, 0, Math.PI * 2);
      x.fill();
    }
    x.restore();
  }

  /**
   * Where one eye lands on the head this frame, or null once it has turned far
   * enough to be behind it.
   *
   * Lifted out of `drawEyes` unchanged. A visor spans both eyes, so it has to
   * see where both of them are before either is drawn.
   */
  private eyeSlot(sd: number, rx: number, ry: number): EyeSlot | null {
    const eyeYaw = sd * EYE_SP + this.yaw;
    let eyePitch = EYE_P + this.pitch + this.roll;
    eyePitch = (((eyePitch + Math.PI) % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2) - Math.PI;
    const cp = Math.cos(eyePitch);
    if (Math.cos(eyeYaw) * cp <= 0.04) return null;
    return {
      x: Math.sin(eyeYaw) * cp * rx,
      y: -Math.sin(eyePitch) * ry + (this.morph > 0 ? ry * 0.14 * this.morph : 0),
      fx: lerp(Math.max(0.18, Math.cos(eyeYaw)), 1, this.morph * 0.7),
      fy: lerp(Math.max(0.18, cp), 1, this.morph * 0.7),
    };
  }

  private drawEyes(x: CanvasRenderingContext2D, body: Path2D, R: number, rx: number, ry: number) {
    let shape: EyeShape = this.eyeOverride ?? this.cfg.eye;
    if (this.morph > 0.5) {
      if (this.isChewing) shape = "happy";
      else if (this.slotHTarget > 0.05 || this.slotH > 0.1) shape = "cup";
    }

    // The character has the last word, and only after every animation above has
    // had its say — `resolveEye` is given the *final* shape, so there is one
    // rule and no ordering surprises. Characters fade out over the mailbox
    // morph: a mailbox wears nothing.
    const dressed = this.morph < 0.62
      ? resolveEye(this.character, shape)
      : ({ kind: "plain", shape } as const);

    x.save();
    x.clip(body);
    const ink = this.isMini ? MINI_INK : INK;
    x.fillStyle = ink;
    x.strokeStyle = ink;

    const slots: [number, EyeSlot | null][] = [
      [-1, this.eyeSlot(-1, rx, ry)],
      [1, this.eyeSlot(1, rx, ry)],
    ];

    // Lenses first, so the glints land inside them.
    let lens: Path2D | null = null;
    if (dressed.kind === "behindLens") {
      lens = this.drawLens(x, dressed.eye, slots, R, rx);
    }

    for (const [sd, slot] of slots) {
      if (!slot) continue;

      // Sunglasses at 1.9x would merge into one blob on a 12 px pill.
      const eyeMult = this.isMini ? (lens ? 1.3 : 1.9) : 1.0;
      const ew = R * EYE_W * this.es * eyeMult;
      const eh = R * EYE_H * this.es * eyeMult;

      x.save();
      // Before the translate: the lens path is in body coordinates, and `clip`
      // composes with whatever transform is current.
      if (lens) x.clip(lens);
      x.translate(slot.x, slot.y);
      x.scale(slot.fx, slot.fy);

      if (dressed.kind === "plain") {
        x.fillStyle = ink;
        x.strokeStyle = ink;
        this.drawEyeShape(x, dressed.shape, ew, eh, sd, ink);
      } else if (dressed.kind === "character") {
        this.drawCharacterEye(x, dressed.eye, ew, eh, sd, dressed.wide, ink);
      } else {
        // The expression still happens — you watch it through the lens.
        const glint = GLINT[dressed.eye];
        x.fillStyle = glint;
        x.strokeStyle = glint;
        this.drawEyeShape(x, dressed.shape, ew * 0.62, eh * 0.62, sd, glint);
      }
      x.restore();
    }
    x.restore();
  }

  /**
   * The four eye styles that *are* the eye.
   *
   * Each honours `open`, because `open` is the blink and a character that
   * stopped blinking would stop looking alive. Note today's `dot` ignores it —
   * right for a one-off surprised expression, wrong for eyes somebody has to
   * look at all day, so the character dot has its own.
   */
  private drawCharacterEye(
    x: CanvasRenderingContext2D, style: MochiEye,
    rawW: number, rawH: number, _sd: number, wide: boolean, ink: string,
  ) {
    // `approval`'s only eye cue. Applied here rather than hoisted out of
    // drawEyeShape, where the wide → pill recursion would double it.
    const w = wide ? rawW * 1.16 : rawW;
    const h = wide ? rawH * 1.12 : rawH;
    x.fillStyle = ink;
    x.strokeStyle = ink;

    switch (style) {
      case "dot": {
        const d = w * 0.92;
        const hh = Math.max(d * this.open, d * 0.26);   // a squashed circle reads as a blink
        x.beginPath();
        x.ellipse(0, 0, d / 2, hh / 2, 0, 0, Math.PI * 2);
        x.fill();
        break;
      }
      case "pixel": {
        const hh = Math.max(w * 0.92 * this.open, w * 0.22);
        // Square corners, deliberately. Borrowing the pill's
        // min(w/2, hh/2) turns a blinking pixel back into a pill.
        x.fillRect(-w * 0.46, -hh / 2, w * 0.92, hh);
        break;
      }
      case "glossy": {
        const d = w * 1.24;
        const hh = Math.max(h * 1.22 * this.open, d * 0.26);
        x.beginPath();
        x.ellipse(0, 0, d / 2, hh / 2, 0, 0, Math.PI * 2);
        x.fillStyle = "#FBFCFE";
        x.fill();
        x.strokeStyle = "rgba(26,20,18,0.22)";
        x.lineWidth = Math.max(d * 0.035, 0.6);
        x.stroke();

        // The pupil looks where the head looks, which is what makes these read
        // as eyes rather than beads.
        const px = Math.sin(this.yaw) * d * 0.13;
        const py = -Math.sin(this.pitch) * hh * 0.13;
        const pd = Math.min(d * 0.58, hh * 0.86);
        x.beginPath();
        x.ellipse(px, py, pd / 2, pd / 2, 0, 0, Math.PI * 2);
        x.fillStyle = ink;
        x.fill();

        if (this.open > 0.35) {
          x.beginPath();
          x.ellipse(px - pd * 0.25, py - pd * 0.30, pd * 0.17, pd * 0.14, 0, 0, Math.PI * 2);
          x.fillStyle = "rgba(255,255,255,0.92)";
          x.fill();
        }
        x.fillStyle = ink;
        x.strokeStyle = ink;
        break;
      }
      case "sleepy": {
        // Already half shut, so `h * open` alone would make the blink invisible.
        // The lid moving is what you actually see.
        const hh = Math.max(h * 0.44 * this.open, w * 0.20);
        roundRectPath(x, -w / 2, -hh / 2, w, hh, Math.min(w / 2, hh / 2));
        x.fill();
        const lidY = lerp(-hh / 2 - w * 0.10, -hh / 2, this.open);
        roundRectPath(x, -w * 0.60, lidY, w * 1.20, w * 0.17, w * 0.085);
        x.fill();
        break;
      }
      default:
        break;   // visor and shades are worn, not grown — see drawLens
    }
  }

  /**
   * Visor and sunglasses: one piece across both eyes.
   *
   * Returns the lens path so the caller can clip the glints to it. Drawn in
   * body coordinates rather than per eye, because `drawEyeShape` is called once
   * per eye and a bridge has no side to belong to.
   *
   * The lens itself never squashes with `open` — an opaque object with eyelids
   * looks like melting hardware. The blink lives in the glint, which goes
   * through the ordinary eye path and so keeps the ordinary timing.
   */
  private drawLens(
    x: CanvasRenderingContext2D, style: MochiEye,
    slots: [number, EyeSlot | null][], R: number, rx: number,
  ): Path2D | null {
    const live = slots.map(([, s]) => s).filter((s): s is EyeSlot => s !== null);
    if (!live.length) return null;   // face is round the back

    // One eye culled: hold the bar between the one we have and the silhouette,
    // so it slides off the edge instead of vanishing.
    const a = slots[0][1] ?? { x: -rx * 0.98, y: live[0].y, fx: 0.18, fy: live[0].fy };
    const b = slots[1][1] ?? { x: rx * 0.98, y: live[0].y, fx: 0.18, fy: live[0].fy };

    const span = Math.hypot(b.x - a.x, b.y - a.y);
    const angle = Math.atan2(b.y - a.y, b.x - a.x);
    const cx = (a.x + b.x) / 2;
    const cy = (a.y + b.y) / 2;
    // `es` thickens the lens but must not stretch the span, or a surprised
    // bot's visor detaches from its eyes.
    const ew = R * EYE_W * (this.isMini ? 1.3 : 1.0);
    const eh = R * EYE_H * this.es * (this.isMini ? 1.3 : 1.0);

    const local = new Path2D();
    if (style === "visor") {
      const barW = Math.min(span + ew * 2.7, rx * 1.62);
      const barH = eh * 0.92 * a.fy;
      local.roundRect(-barW / 2, -barH / 2, barW, barH, barH / 2);
    } else {
      const lw = ew * 1.5;
      const lh = eh * 1.02 * a.fy;
      for (const side of [-1, 1]) {
        const f = side < 0 ? a.fx : b.fx;
        local.roundRect(side * span / 2 - (lw * f) / 2, -lh / 2, lw * f, lh, lh * 0.42);
      }
    }

    // Body coordinates, so the caller can clip the glints with it.
    const placed = new Path2D();
    const m = new DOMMatrix().translateSelf(cx, cy).rotateSelf((angle * 180) / Math.PI);
    placed.addPath(local, m);

    x.save();
    x.fillStyle = LENS_FRAME;
    if (style === "shades") {
      // Bridge, then the lenses on top so the join disappears under them.
      const lh = eh * 1.02 * a.fy;
      const bridge = new Path2D();
      bridge.roundRect(-span / 2, -lh * 0.16, span, lh * 0.24, lh * 0.12);
      const placedBridge = new Path2D();
      placedBridge.addPath(bridge, m);
      x.fill(placedBridge);
    }
    x.fill(placed);
    if (style === "visor") {
      x.strokeStyle = "rgba(255,255,255,0.14)";
      x.lineWidth = Math.max(eh * 0.055, 0.6);
      x.stroke(placed);
    }
    x.restore();

    return placed;
  }

  private drawEyeShape(
    x: CanvasRenderingContext2D, shape: EyeShape,
    w: number, h: number, sd: number, ink: string,
  ) {
    const t = now();
    switch (shape) {
      case "wide":
        this.drawEyeShape(x, "pill", w * 1.16, h * 1.12, sd, ink);
        break;
      case "pill": {
        const hh = Math.max(h * this.open, w * 0.3);
        roundRectPath(x, -w / 2, -hh / 2, w, hh, Math.min(w / 2, hh / 2));
        x.fill();
        break;
      }
      case "dot":
        x.beginPath();
        x.arc(0, 0, w * 0.45, 0, Math.PI * 2);
        x.fill();
        break;
      case "line":
        x.rotate(-sd * 0.2);
        roundRectPath(x, -w * 0.78, -w * 0.21, w * 1.56, w * 0.42, w * 0.21);
        x.fill();
        break;
      case "flat":
        roundRectPath(x, -w * 0.72, -w * 0.2, w * 1.44, w * 0.4, w * 0.2);
        x.fill();
        break;
      case "happy":
        x.lineWidth = w * 0.5;
        x.lineCap = "round";
        x.beginPath();
        x.arc(0, h * 0.18, w * 0.82, Math.PI * 1.12, Math.PI * 1.88);
        x.stroke();
        break;
      case "closed":
        x.lineWidth = w * 0.36;
        x.lineCap = "round";
        x.beginPath();
        x.arc(0, -h * 0.08, w * 0.78, Math.PI * 0.15, Math.PI * 0.85);
        x.stroke();
        break;
      case "spiral": {
        x.lineWidth = w * 0.22;
        x.lineCap = "round";
        x.beginPath();
        for (let a = 0; a < 4.4 * Math.PI; a += 0.2) {
          const r = w * 0.06 + a * w * 0.058;
          const aa = a + t * 9 * sd;
          const px = Math.cos(aa) * r;
          const py = Math.sin(aa) * r;
          if (a === 0) x.moveTo(px, py);
          else x.lineTo(px, py);
        }
        x.stroke();
        break;
      }
      case "heart":
        x.fillStyle = "#FF4D6D";
        heartPath(x, w * 1.2);
        x.fill();
        x.fillStyle = ink;
        break;
      case "star":
        x.fillStyle = "#F7B32B";
        x.rotate(t * 1.5 * sd);
        starPath(x, w * 1.05, w * 0.46);
        x.fill();
        x.fillStyle = ink;
        break;
      case "tired":
        roundRectPath(x, -w / 2, -h * 0.02, w, h * 0.38, w / 2);
        x.fill();
        roundRectPath(x, -w * 0.62, -h * 0.1, w * 1.24, w * 0.22, w * 0.11);
        x.fill();
        break;
      case "wink":
        if (sd < 0) {
          const hh = Math.max(h * this.open, w * 0.3);
          roundRectPath(x, -w / 2, -hh / 2, w, hh, Math.min(w / 2, hh / 2));
          x.fill();
        } else {
          x.lineWidth = w * 0.5;
          x.lineCap = "round";
          x.beginPath();
          x.arc(0, h * 0.18, w * 0.82, Math.PI * 1.12, Math.PI * 1.88);
          x.stroke();
        }
        break;
      case "cup": {
        // Flat top, rounded bottom corners (U shape) — used while the box is open
        const hh = Math.max(h * this.open, w * 0.3);
        const cr = Math.min(w / 2, hh / 2);
        x.beginPath();
        x.moveTo(-w / 2, -hh / 2);
        x.lineTo(w / 2, -hh / 2);
        x.lineTo(w / 2, hh / 2 - cr);
        x.quadraticCurveTo(w / 2, hh / 2, w / 2 - cr, hh / 2);
        x.lineTo(-w / 2 + cr, hh / 2);
        x.quadraticCurveTo(-w / 2, hh / 2, -w / 2, hh / 2 - cr);
        x.closePath();
        x.fill();
        break;
      }
    }
  }

  /** Mailbox slot: dark pill cut into the box face, with rim and lip highlights. */
  private drawMouth(x: CanvasRenderingContext2D, body: Path2D, R: number) {
    const m = this.morph;
    const hW = R * 1.8 * m;
    const hH = this.slotH * R * m;
    const hX = -hW / 2;
    const boxTop = -R * (0.88 + 0.06 * m);
    const hY = boxTop + R * 0.08 * m;

    x.save();
    x.clip(body);

    x.strokeStyle = `rgba(255,255,255,${0.55 * m})`;
    x.lineWidth = 1;
    x.lineCap = "round";
    x.beginPath();
    x.moveTo(-R * 0.9 * m, boxTop + 1);
    x.lineTo(R * 0.9 * m, boxTop + 1);
    x.stroke();

    if (hH > 0.8) {
      const hR = Math.min(hW / 2, hH / 2);
      const g = x.createLinearGradient(0, hY, 0, hY + hH);
      g.addColorStop(0, "rgb(7,8,10)");
      g.addColorStop(1, "rgb(16,19,26)");
      roundRectPath(x, hX, hY, hW, hH, hR);
      x.fillStyle = g;
      x.fill();
      if (hH > 4) {
        const lipR = Math.min(hR, (hW - 2) / 2);
        x.strokeStyle = `rgba(255,255,255,${0.28 * m})`;
        x.beginPath();
        x.moveTo(hX + lipR, hY + hH - 0.5);
        x.lineTo(hX + hW - lipR, hY + hH - 0.5);
        x.stroke();
      }
    }
    x.restore();
  }

  /** Hands sit behind the body — drawn before it, in world coordinates. */
  private drawHandsBehind(
    x: CanvasRenderingContext2D,
    R: number, rx: number, ry: number, cx: number, cy: number,
  ) {
    if (this.hands <= 0.01 || this.isMini) return;
    if (R <= 14) return; // meaningless at compact/peek sizes

    const n = now();
    const bodyH = 2 * ry;
    const hew = 0.3 * ry * this.hands;
    const heh = 0.26 * ry * this.hands;
    const hwB = rx * this.sx;
    const hhB = ry * this.sy;
    const isWaving = n >= this.waveStart && this.waveStart > 0 && n < this.waveUntil;

    for (const sd of [-1, 1]) {
      let localX: number;
      let localY: number;
      let handRot = 0;

      if (sd > 0 && isWaving) {
        const wt = n - this.waveStart;
        const rise = Math.min(1, wt / 0.18);
        const riseEased = 1 - Math.pow(1 - rise, 3);
        const restX = hwB * 1.08;
        const restY = hhB * 0.7;
        const oscX = Math.cos(13 * wt) * 0.06 * bodyH;
        const oscY = -Math.sin(13 * wt) * 0.14 * bodyH;
        const waveX = hwB * 1.1 + oscX;
        const waveY = -hhB * 0.15 + oscY;
        localX = restX + (waveX - restX) * riseEased;
        localY = restY + (waveY - restY) * riseEased;
        handRot = (-0.5 + Math.sin(13 * wt) * 0.35) * riseEased;
      } else if (sd < 0 && isWaving) {
        const wt = n - this.waveStart;
        localX = -hwB * 1.08;
        localY = hhB * 0.7 + Math.sin(6 * wt) * 0.04 * bodyH;
      } else {
        localX = sd * hwB * 1.08;
        localY = hhB * 0.7;
      }

      const cosT = Math.cos(this.tilt);
      const sinT = Math.sin(this.tilt);
      const worldX = cx + cosT * localX - sinT * localY;
      const worldY = cy + sinT * localX + cosT * localY;

      x.save();
      x.translate(worldX, worldY);
      if (handRot !== 0) x.rotate(handRot);
      const g = x.createLinearGradient(hew * 0.7, -heh * 0.85, -hew * 0.8, heh * 0.9);
      if (this.bodyColor) {
        g.addColorStop(0, rgba(mix3(this.bodyColor, [1, 1, 1], 0.35)));
        g.addColorStop(1, rgba(this.bodyColor));
      } else {
        g.addColorStop(0, rgba(BASE_TOP));
        g.addColorStop(1, rgba(BASE_BOTTOM));
      }
      x.beginPath();
      x.ellipse(0, 0, hew, heh, 0, 0, Math.PI * 2);
      x.fillStyle = g;
      x.fill();
      x.strokeStyle = "rgba(0,0,0,0.08)";
      x.lineWidth = 1;
      x.stroke();
      x.restore();
    }
  }

  private drawBadge(x: CanvasRenderingContext2D, badge: Badge, R: number, cx: number, cy: number) {
    const bs = this.badgeS * (this.isMini ? 1.25 : 1);
    const bx = cx - R * 0.72 * this.sx;
    const by = cy - R * 0.72 * this.sy;
    const t = now();

    x.save();
    x.translate(bx, by);
    x.scale(bs, bs);
    const col = rgba(badge.color);

    if (badge.kind === "dots") {
      if (this.isMini) {
        const phase = (t * 2.4) % 1;
        const dotR = R * 0.22 * (1 + 0.25 * Math.sin(phase * Math.PI * 2));
        x.fillStyle = "#000";
        x.beginPath();
        x.arc(0, 0, R * 0.2, 0, Math.PI * 2);
        x.fill();
        x.fillStyle = col;
        x.beginPath();
        x.arc(0, 0, dotR, 0, Math.PI * 2);
        x.fill();
      } else {
        const pw = R * 0.72;
        const ph = R * 0.36;
        roundRectPath(x, -pw / 2, -ph / 2, pw, ph, ph / 2);
        x.fillStyle = col;
        x.fill();
        for (let i = 0; i < 3; i++) {
          const phase = (((t * 2.4 - i * 0.22) % 1) + 1) % 1;
          const dotR = R * 0.055 * (1 + 0.4 * Math.max(0, Math.sin(phase * Math.PI * 2)));
          x.fillStyle = "#fff";
          x.beginPath();
          x.arc((i - 1) * R * 0.18, 0, dotR, 0, Math.PI * 2);
          x.fill();
        }
      }
    } else if (badge.kind === "bang" || badge.kind === "question") {
      x.fillStyle = "#000";
      x.beginPath();
      x.arc(0, 0, R * 0.3, 0, Math.PI * 2);
      x.fill();
      x.fillStyle = col;
      x.beginPath();
      x.arc(0, 0, R * 0.23, 0, Math.PI * 2);
      x.fill();
      if (!this.isMini) {
        x.fillStyle = "#fff";
        x.font = `900 ${R * 0.32}px ${FONT}`;
        x.textAlign = "center";
        x.textBaseline = "middle";
        x.fillText(badge.kind === "bang" ? "!" : "?", 0, R * 0.02);
      }
    } else {
      x.fillStyle = "#000";
      x.beginPath();
      x.arc(0, 0, R * 0.2, 0, Math.PI * 2);
      x.fill();
      x.fillStyle = col;
      x.beginPath();
      x.arc(0, 0, R * 0.135, 0, Math.PI * 2);
      x.fill();
    }
    x.restore();
  }

  private drawParticles(x: CanvasRenderingContext2D, R: number, cx: number, cy: number) {
    for (const p of this.particles) {
      if (p.age <= 0) continue;
      const k = p.age / p.life;
      const a = k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8;
      const px = cx + (p.x + p.vx * p.age) * R * 1.3;
      const py = cy + (p.y + p.vy * p.age) * R * 1.3;
      const sz = R * p.size * (1 + k * 0.4);

      x.save();
      x.translate(px, py);
      x.globalAlpha = Math.min(1, Math.max(0, a));
      switch (p.type) {
        case "heart":
          x.rotate(Math.sin(p.age * 6) * 0.3);
          x.fillStyle = "#FF4D6D";
          heartPath(x, sz);
          x.fill();
          break;
        case "star":
          x.rotate(p.rot + p.age * 2);
          x.fillStyle = "#F7B32B";
          starPath(x, sz, sz * 0.45);
          x.fill();
          break;
        case "spark":
          x.rotate(p.rot);
          x.fillStyle = "#fff";
          starPath(x, sz * 0.8, sz * 0.18);
          x.fill();
          break;
        case "sweat":
          x.fillStyle = "#7CC7FF";
          x.beginPath();
          x.moveTo(0, -sz);
          x.quadraticCurveTo(sz * 0.8, sz * 0.2, 0, sz * 0.6);
          x.quadraticCurveTo(-sz * 0.8, sz * 0.2, 0, -sz);
          x.fill();
          break;
        case "z":
          x.fillStyle = "rgb(209,219,235)";
          x.font = `700 ${sz * 1.9}px ${FONT}`;
          x.textAlign = "center";
          x.textBaseline = "middle";
          x.fillText("z", 0, 0);
          break;
      }
      x.restore();
    }
  }
}

/** Ray → rounded-rect boundary intersection, for the mailbox morph. */
function rrPoint(ca: number, sa: number, W: number, H: number, cr: number): { x: number; y: number } {
  const eps = 1e-6;
  const kx = ca >= 0 ? 1 : -1;
  const ky = sa >= 0 ? 1 : -1;
  const cx = kx * (W - cr);
  const cy = ky * (H - cr);

  const dot = ca * cx + sa * cy;
  const disc = dot * dot - (cx * cx + cy * cy - cr * cr);
  if (disc >= 0) {
    const t = dot + Math.sqrt(disc);
    if (t > eps) {
      const px = ca * t;
      const py = sa * t;
      if (Math.abs(px) >= W - cr - eps && Math.abs(py) >= H - cr - eps) return { x: px, y: py };
    }
  }
  if (Math.abs(sa) > eps) {
    const t = (ky * H) / sa;
    if (t > eps) {
      const px = ca * t;
      if (Math.abs(px) <= W - cr + eps) return { x: px, y: ky * H };
    }
  }
  if (Math.abs(ca) > eps) {
    const t = (kx * W) / ca;
    if (t > eps) {
      const py = sa * t;
      if (Math.abs(py) <= H - cr + eps) return { x: kx * W, y: py };
    }
  }
  return { x: kx * W, y: ky * H };
}
