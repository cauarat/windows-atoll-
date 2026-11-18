// The snow lying on the island's floor, as arithmetic.
//
// The twin of NotchBuddy/Sources/App/IslandSnow.swift, kept by hand: the same
// numbers, the same step, the same sequence of thrown flakes.
// scripts/test-island-snow.sh runs one script through both and compares, so a
// number changed here and not there is a failing build.
//
// A bank of snow along the bottom edge: thin on the resting bar, slowly deeper
// while the island stays open, and soft — a pointer passing through it ploughs
// a gap, heaps what it moved in front of itself and throws the rest up as a few
// flakes, and the gap fills back in over the next seconds.
//
// Heights are in CSS pixels above the floor. Columns are counted from the
// island's centre, so the humps stay put while the island springs wider.

export const SNOW = {
  /** How deep the bank is on the resting bar, and the moment the island opens. */
  restDepth: 6,
  /** How deep it gets if the island is left open. */
  maxDepth: 8.5,
  /** Time constant of that growth, seconds. */
  growTime: 30,
  /** After this long open there is nothing left to grow. */
  grownAfter: 150,
  /** No heap rises past this: the views leave 10 px clear above the floor. */
  capHeight: 9.8,
  pitch: 2,
  columns: 2048,
  /** How far above the floor the pointer still touches the snow. */
  touch: 12,
  /** Half the width of what it ploughs. */
  radius: 11,
  /** What it leaves behind. */
  dusting: 0.5,
  heapSpan: 14,
  /** Slower than this and the pointer is resting in the snow, not sweeping it. */
  sweepSpeed: 30,
  scoopRate: 22,
  /** How much of a column goes when the pointer passes right across it. */
  sweepTake: 0.85,
  slumpTime: 2.5,
  refillTime: 5,
  closeTime: 0.12,
  epsilon: 0.02,
  flakeCost: 1.2,
  maxFlakes: 40,
  gravity: 560,
  /** How many falling flakes there are in the whole field. */
  fallCount: 220,
  /** The field they are scattered over, and how tall before it repeats. */
  fallField: 4096,
  fallPeriod: 160,
  /** A flake fades in and out over this far from the top and the floor. */
  fallFade: 8,
} as const;

const MID = SNOW.columns / 2;

/** One thrown flake. `y` is height above the floor. */
export interface Flake {
  x: number; y: number; vx: number; vy: number; life: number; size: number;
}

/** How deep the bank is `seconds` after the island opened. */
export function snowDepth(seconds: number): number {
  return SNOW.restDepth
    + (SNOW.maxDepth - SNOW.restDepth) * (1 - Math.exp(-Math.max(0, seconds) / SNOW.growTime));
}

/** The surface `x` from the centre, as a fraction of the depth: 0.44 to 1. */
export function snowUnit(x: number): number {
  const wave = Math.sin(x * 0.071 + 1.3) * 0.5 + Math.sin(x * 0.183 + 0.4) * 0.3
    + Math.sin(x * 0.41 + 2.1) * 0.2;
  return 0.72 + 0.28 * wave;
}

const SHAPE = new Float64Array(SNOW.columns);
for (let i = 0; i < SNOW.columns; i++) SHAPE[i] = snowUnit((i - MID) * SNOW.pitch);

/** Swift's `rounded()`: halves away from zero, where Math.round goes up. */
const round = (v: number) => Math.sign(v) * Math.round(Math.abs(v));

/** The column under `x`, measured from the centre. */
export function snowColumn(x: number): number {
  return round(x / SNOW.pitch) + MID;
}

/** The columns an island `width` wide shows, both ends included. */
export function snowVisible(width: number): [number, number] {
  const half = Math.ceil(width / 2 / SNOW.pitch) + 1;
  return [Math.max(0, MID - half), Math.min(SNOW.columns - 1, MID + half)];
}

// ── Falling ──────────────────────────────────────────────────────────────────
//
// The snow coming down across the whole island, faint, in front of the cards
// but blended so it can only ever lighten what is under it. No state: every
// flake is a function of the clock, so there is nothing to step.

/** One flake, somewhere in its fall. `x` from the centre, `y` down from the top. */
export interface Falling { x: number; y: number; radius: number; alpha: number }

const FALL_SEEDS = new Float64Array(SNOW.fallCount * 4);
{
  let seed = 0x12345678;
  for (let i = 0; i < FALL_SEEDS.length; i++) {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    FALL_SEEDS[i] = seed / 4294967296;
  }
}

/** Where flake `i` is at `time`, seconds. Never as much as half opaque. */
export function snowFalling(i: number, time: number): Falling {
  const across = FALL_SEEDS[i * 4], start = FALL_SEEDS[i * 4 + 1];
  const near = FALL_SEEDS[i * 4 + 2], sway = FALL_SEEDS[i * 4 + 3];
  const speed = 10 + 16 * near;
  const y = (time * speed + start * SNOW.fallPeriod) % SNOW.fallPeriod;
  const x = (across - 0.5) * SNOW.fallField
    + Math.sin(time * (0.4 + 0.6 * sway) + sway * 6.283) * (2 + 4 * near);
  return { x, y, radius: 0.7 + 1.0 * near, alpha: 0.2 + 0.25 * near };
}

/** How much of a flake at `y` shows in an island `height` tall. */
export function snowFallVisibility(y: number, height: number): number {
  if (!(y >= 0 && y <= height)) return 0;
  return Math.max(0, Math.min(1, y / SNOW.fallFade, (height - y) / SNOW.fallFade));
}

export class SnowField {
  /** What the pointer has done to each column: negative where it ploughed,
   *  positive where it heaped. Zero is the bank as it drifted. */
  readonly offsets = new Float64Array(SNOW.columns);
  flakes: Flake[] = [];
  /** The depth being drawn. Follows `snowDepth` up, and eases down. */
  depth: number = SNOW.restDepth;
  openFor = 0;
  /** Nothing is moving: no flake in the air, no column out of place. */
  isSettled = true;

  private lastX: number | null = null;
  private budget = 0;
  private seed = 0x9e3779b9;

  /** Still getting deeper, so worth a slow tick with nothing else going on. */
  get isGrowing(): boolean { return this.openFor > 0 && this.openFor < SNOW.grownAfter; }

  height(i: number): number {
    return Math.min(SNOW.capHeight, Math.max(0, this.depth * SHAPE[i] + this.offsets[i]));
  }

  /**
   * Advance by `dt` seconds. `pointer` is where the pointer is if it is over
   * the island — `x` from the island's left edge, `above` the floor — or null.
   */
  step(dt: number, width: number, expanded: boolean,
       pointer: { x: number; above: number } | null): void {
    // Depth: up with the clock, down on a curve.
    this.openFor = expanded ? this.openFor + dt : 0;
    const goal = expanded ? snowDepth(this.openFor) : SNOW.restDepth;
    if (goal < this.depth) {
      this.depth += (goal - this.depth) * (1 - Math.exp(-dt / SNOW.closeTime));
      if (this.depth - goal < SNOW.epsilon) this.depth = goal;
    } else {
      this.depth = goal;
    }

    // Heaps slump and gaps fill.
    const slump = Math.exp(-dt / SNOW.slumpTime);
    const refill = Math.exp(-dt / SNOW.refillTime);
    const o = this.offsets;
    let moving = false;
    for (let i = 0; i < SNOW.columns; i++) {
      if (o[i] === 0) continue;
      o[i] *= o[i] > 0 ? slump : refill;
      if (Math.abs(o[i]) < SNOW.epsilon) o[i] = 0; else moving = true;
    }

    if (pointer && pointer.above >= -2 && pointer.above <= SNOW.touch
        && pointer.x >= 0 && pointer.x <= width) {
      this.plough(pointer.x - width / 2, dt);
      moving = true;
    } else {
      this.lastX = null;
    }

    // Flakes fly, fall and are gone: the bank refills on its own.
    if (this.flakes.length) {
      const drag = Math.exp(-1.5 * dt);
      for (const f of this.flakes) {
        f.vy -= SNOW.gravity * dt;
        f.vx *= drag;
        f.x += f.vx * dt;
        f.y += f.vy * dt;
        f.life -= dt;
      }
      this.flakes = this.flakes.filter((f) => !(f.life <= 0 || f.y < 0));
    }

    this.isSettled = !moving && this.flakes.length === 0 && this.depth === goal;
  }

  /** The pointer is in the snow at `cx`, measured from the centre. */
  private plough(cx: number, dt: number): void {
    const from = this.lastX ?? cx;
    const velocity = (cx - from) / Math.max(dt, 1e-4);
    this.lastX = cx;
    const direction = Math.abs(velocity) > SNOW.sweepSpeed ? (velocity > 0 ? 1 : -1) : 0;

    // Scoop what is under it — and everything it crossed since the last step.
    // A pointer covers ten or twenty pixels between two frames, and clearing
    // only where it happens to be seen would leave a dotted line, not a furrow.
    const take = 1 - Math.exp(-dt * SNOW.scoopRate);
    const lo = Math.min(from, cx), hi = Math.max(from, cx);
    const first = Math.max(0, snowColumn(lo - SNOW.radius));
    const last = Math.min(SNOW.columns - 1, snowColumn(hi + SNOW.radius));
    let moved = 0;
    for (let i = first; i <= last; i++) {
      const x = (i - MID) * SNOW.pitch;
      const crossed = hi > lo && x >= lo && x <= hi;
      const weight = Math.max(0, 1 - Math.abs(x - cx) / SNOW.radius);
      const part = crossed ? Math.max(SNOW.sweepTake, weight * take) : weight * take;
      const scoop = Math.max(0, this.height(i) - SNOW.dusting) * part;
      this.offsets[i] -= scoop;
      moved += scoop;
    }
    if (!(moved > 0)) return;

    // Half goes in a heap ahead of a moving pointer and half into the air; a
    // resting one just parts it, to both sides, and nothing flies.
    if (direction === 0) {
      this.heap(moved / 2, cx, -1);
      this.heap(moved / 2, cx, 1);
      return;
    }
    this.budget += moved / 2 + this.heap(moved / 2, cx, direction);

    const top = this.height(Math.max(0, Math.min(SNOW.columns - 1, snowColumn(cx))));
    while (this.budget >= SNOW.flakeCost && this.flakes.length < SNOW.maxFlakes) {
      this.budget -= SNOW.flakeCost;
      const speed = 60 + Math.min(Math.abs(velocity), 900) * 0.25;
      // Field by field, in Swift's order: each one draws from the sequence.
      const x = cx + direction * SNOW.radius * this.random();
      const vx = direction * speed * (0.5 + this.random()) + (this.random() - 0.5) * 30;
      const vy = 45 + 75 * this.random();
      const life = 0.5 + 0.4 * this.random();
      const size = 0.6 + 0.8 * this.random();
      this.flakes.push({ x, y: top + 1, vx, vy, life, size });
    }
    // The air is full: the rest is lost rather than saved up for a burst.
    this.budget = Math.min(this.budget, SNOW.flakeCost);
  }

  /** Spread `amount` over the heap on one side. Returns what the cap refused. */
  private heap(amount: number, cx: number, side: number): number {
    const near = snowColumn(cx + side * SNOW.radius);
    const far = snowColumn(cx + side * (SNOW.radius + SNOW.heapSpan));
    const first = Math.max(0, Math.min(near, far));
    const last = Math.min(SNOW.columns - 1, Math.max(near, far));
    if (first > last) return amount;
    // A mound, not a box: most of it lands in the middle, and the middle is
    // allowed to stand tallest, so a full heap still has a rounded top.
    const count = last - first + 1;
    const hump = (i: number) => Math.sin(Math.PI * (i - first + 0.5) / count);
    let total = 0;
    for (let i = first; i <= last; i++) total += hump(i);
    let spilled = 0;
    for (let i = first; i <= last; i++) {
      const share = amount * hump(i) / total;
      const limit = SNOW.capHeight * (0.55 + 0.45 * hump(i));
      const put = Math.min(share, Math.max(0, limit - this.height(i)));
      this.offsets[i] += put;
      spilled += share - put;
    }
    return spilled;
  }

  /** A fixed sequence, the same one Swift draws from. */
  private random(): number {
    this.seed = (Math.imul(this.seed, 1664525) + 1013904223) >>> 0;
    return this.seed / 4294967296;
  }
}
