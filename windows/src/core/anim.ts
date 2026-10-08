// Easing + spring helpers.
// Ease.* mirrors BotEngine.swift `enum Ease` (itself the prototype's `E`).
// Spring mirrors SwiftUI `.spring(response:dampingFraction:)` so open/close motion
// matches the macOS app exactly.

export const Ease = {
  out: (t: number) => 1 - Math.pow(1 - t, 3),
  inOut: (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
  back: (t: number) => {
    const c1 = 1.7;
    const c3 = c1 + 1;
    return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
  },
  lin: (t: number) => t,
  easeIn: (t: number) => t * t * t,
};

export type EaseFn = (t: number) => number;

export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));
export const seg = (t: number, a: number, b: number) => clamp((t - a) / (b - a), 0, 1);

/** cubic-bezier(x1,y1,x2,y2) — used for the 340 ms close curve (.45,0,.2,1). */
export function cubicBezier(x1: number, y1: number, x2: number, y2: number): EaseFn {
  const cx = (t: number) => ((1 - t) ** 2 * 3 * t * x1) + (3 * (1 - t) * t * t * x2) + t ** 3;
  const cy = (t: number) => ((1 - t) ** 2 * 3 * t * y1) + (3 * (1 - t) * t * t * y2) + t ** 3;
  return (x) => {
    // Newton-ish bisection on x — 12 iterations is plenty at 60 fps.
    let lo = 0;
    let hi = 1;
    let t = x;
    for (let i = 0; i < 12; i++) {
      const v = cx(t);
      if (v < x) lo = t;
      else hi = t;
      t = (lo + hi) / 2;
    }
    return cy(t);
  };
}

export const closeCurve = cubicBezier(0.45, 0, 0.2, 1);

/**
 * SwiftUI-equivalent spring: ω₀ = 2π / response, ζ = dampingFraction.
 * Integrated per frame (sub-stepped) so a dropped frame never destabilises it.
 */
export class Spring {
  value: number;
  target: number;
  velocity = 0;
  omega: number;
  zeta: number;

  constructor(value: number, response = 0.5, damping = 0.72) {
    this.value = value;
    this.target = value;
    this.omega = (2 * Math.PI) / response;
    this.zeta = damping;
  }

  configure(response: number, damping: number) {
    this.omega = (2 * Math.PI) / response;
    this.zeta = damping;
  }

  set(value: number) {
    this.value = value;
    this.target = value;
    this.velocity = 0;
  }

  get settled(): boolean {
    return Math.abs(this.target - this.value) < 0.01 && Math.abs(this.velocity) < 0.05;
  }

  step(dt: number) {
    const steps = Math.max(1, Math.ceil(dt / (1 / 240)));
    const h = dt / steps;
    for (let i = 0; i < steps; i++) {
      const acc =
        this.omega * this.omega * (this.target - this.value) -
        2 * this.zeta * this.omega * this.velocity;
      this.velocity += acc * h;
      this.value += this.velocity * h;
    }
  }
}

/** Open motion, shared by every island dimension. Mirrors IslandMotion.open. */
export const OPEN_RESPONSE = 0.34;
export const OPEN_DAMPING = 0.78;
/** Close motion, in ms. Mirrors IslandMotion.closeDurationMs. */
export const CLOSE_MS = 220;
/** How much of a close's speed survives into the spring when it is reversed. */
const REVERSAL_MOMENTUM = 0.5;

/**
 * Value driven either by a spring (growing) or a timed curve (shrinking) —
 * matches IslandContainer: the open spring for grow, the close curve for shrink.
 *
 * Both directions are interruptible at any point. Whichever way it is going, the
 * value is continuous across the switch and so is its velocity: reversing mid-
 * close carries the speed it had into the spring, so the island turns around
 * rather than stopping dead and starting again.
 */
export class Tracked {
  private spring: Spring;
  private curveFrom = 0;
  private curveTo = 0;
  private curveStart = 0;
  private curveDur = 0;
  private mode: "spring" | "curve" | "idle" = "idle";

  constructor(value: number) {
    this.spring = new Spring(value, OPEN_RESPONSE, OPEN_DAMPING);
  }

  get value(): number {
    return this.spring.value;
  }

  get animating(): boolean {
    return this.mode !== "idle";
  }

  jump(v: number) {
    this.spring.set(v);
    this.mode = "idle";
  }

  /**
   * Instantaneous speed of the curve, in units per second, at `now`.
   *
   * Differentiated numerically over a 1/120 s window rather than solved: the
   * bezier is already an inverse-solve per sample and this only has to be good
   * enough to hand the spring a believable starting velocity.
   */
  private curveVelocity(now: number): number {
    const span = this.curveTo - this.curveFrom;
    if (this.curveDur <= 0 || span === 0) return 0;
    const h = 1000 / 120;
    const p0 = clamp((now - this.curveStart) / this.curveDur, 0, 1);
    const p1 = clamp((now + h - this.curveStart) / this.curveDur, 0, 1);
    if (p1 <= p0) return 0;
    return (span * (closeCurve(p1) - closeCurve(p0))) / ((p1 - p0) * this.curveDur * 0.001);
  }

  /** Spring to `v` (open / grow). */
  springTo(v: number, response = OPEN_RESPONSE, damping = OPEN_DAMPING, now = performance.now()) {
    // Coming out of a close, the curve owns the motion and the spring's velocity
    // is stale. Seed it, or the reversal starts from a standstill and the island
    // visibly stops before it turns around.
    //
    // Only part of it, though: the close curve is quickest in its middle, and
    // handing all of that to the spring makes the island sink for another couple
    // of frames before it comes back. Half keeps the motion continuous while
    // still reading as an immediate answer to the pointer.
    if (this.mode === "curve") this.spring.velocity = this.curveVelocity(now) * REVERSAL_MOMENTUM;
    this.spring.configure(response, damping);
    this.spring.target = v;
    this.mode = "spring";
  }

  /**
   * Timed curve to `v` (close / shrink), no overshoot.
   *
   * Re-aimed mid-flight — a second close to a new target — it restarts from
   * where the value is now, so the motion stays continuous.
   */
  curveTowards(v: number, durationMs = CLOSE_MS, now = performance.now()) {
    this.curveFrom = this.spring.value;
    this.curveTo = v;
    this.curveStart = now;
    this.curveDur = durationMs;
    this.spring.target = v;
    this.mode = "curve";
  }

  step(dt: number, now = performance.now()) {
    if (this.mode === "spring") {
      this.spring.step(dt);
      if (this.spring.settled) {
        this.spring.value = this.spring.target;
        this.spring.velocity = 0;
        this.mode = "idle";
      }
    } else if (this.mode === "curve") {
      const p = clamp((now - this.curveStart) / this.curveDur, 0, 1);
      this.spring.value = lerp(this.curveFrom, this.curveTo, closeCurve(p));
      if (p >= 1) {
        this.spring.velocity = 0;
        this.mode = "idle";
      }
    }
  }
}
