// The snow on the island's floor, drawn.
//
// `snow.ts` is the arithmetic; this is a canvas and a ticker around it. The
// twin of IslandSnowView.swift.
//
// A detail, and it has to stay one. The canvas is the first thing inside
// `#island-clip`, so every card, canvas and Mochi draws over it and the
// island's own rounded corners clip it; it takes no pointer events — it is
// *told* where the pointer is — so nothing about hovering or clicking the
// island changes; and it keeps inside the 10 px every view leaves above the
// floor.
//
// The ticker is its own, not the island's frame loop, and it runs only while
// there is something to step: every frame while the pointer is in the snow or
// anything is still moving, twice a second while the island is open and the
// bank is getting deeper, and not at all otherwise.
//
// A second canvas, `fall`, is the snow coming down across the whole island.
// It is the one part drawn *over* what the island shows — the last thing in
// the clip — and it is made so that it cannot get in the way: no flake is as
// much as half opaque or wider than 3.4 px, and every flake is pure white,
// which can only lighten (the Mac blends its layer as `screen`, which for
// white is the same arithmetic; see `#island-snowfall`). White text under a
// flake is exactly as white as it was. Thirty frames a second while the island
// is on screen; nothing while it is hidden, switched off or asked for less
// motion.

import { SNOW, SnowField, snowFalling, snowFallVisibility, snowVisible } from "./snow";

/** Tall enough for the highest heap and the highest flake above it. */
const BAND = 28;
/** The canvas grows in steps this wide, so a spring does not reallocate it on
 *  every frame. What hangs past the island is clipped. */
const GRAIN = 96;

const MID = SNOW.columns / 2;

export class SnowLayer {
  readonly el = document.createElement("canvas");
  /** The snow coming down. Goes last in the clip, over the cards. */
  readonly fall = document.createElement("canvas");

  private field = new SnowField();
  private ctx = this.el.getContext("2d")!;
  private fallCtx = this.fall.getContext("2d")!;
  private dpr = Math.min(2, window.devicePixelRatio || 1);
  private reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)") ?? null;

  private width = 0;
  private height = 0;
  private visible = true;
  private fallFrame = 0;
  private fallLast = 0;
  private enabled = false;
  private expanded = false;
  private pointer: { x: number; above: number } | null = null;

  private frame = 0;
  private timeout = 0;
  private last = 0;

  constructor() {
    this.el.id = "island-snow";
    this.el.classList.add("off");
    this.el.style.height = `${BAND}px`;
    this.el.height = Math.round(BAND * this.dpr);
    this.fall.id = "island-snowfall";
    this.fall.classList.add("off");
    this.reduced?.addEventListener?.("change", () => {
      this.field = new SnowField();
      this.wake();
      this.kickFall();
    });
  }

  /** In season and switched on. Off, there is no canvas on screen and no ticker. */
  setEnabled(on: boolean) {
    if (on === this.enabled) return;
    this.enabled = on;
    this.el.classList.toggle("off", !on);
    this.fall.classList.toggle("off", !on);
    if (on) this.wake(); else this.stop();
    this.kickFall();
  }

  /** Whether the island is on screen at all. Hidden, nothing falls. */
  setVisible(on: boolean) {
    if (on === this.visible) return;
    this.visible = on;
    this.kickFall();
  }

  setExpanded(on: boolean) {
    if (on === this.expanded) return;
    this.expanded = on;
    this.wake();
  }

  /** The auto-close hairline is on the same edge: the snow steps aside for it. */
  setCounting(on: boolean) {
    this.el.classList.toggle("aside", on);
  }

  /** Where the pointer is — from the island's left edge, above its floor — or
   *  null once it has left the island. */
  setPointer(p: { x: number; above: number } | null) {
    const was = this.touching(this.pointer);
    this.pointer = p;
    if (this.touching(p) || was) this.wake();
  }

  /** The island's size, on every frame of its spring. */
  resize(width: number, height: number) {
    if (Math.abs(height - this.height) >= 0.01) {
      const was = this.height;
      this.height = height;
      const css = Math.ceil(Math.max(1, height) / GRAIN) * GRAIN;
      const px = Math.round(css * this.dpr);
      if (this.fall.height !== px) {
        this.fall.height = px;
        this.fall.style.height = `${css}px`;
      }
      if (was <= 0) this.kickFall();
    }
    if (Math.abs(width - this.width) < 0.01) return;
    this.width = width;
    const css = Math.ceil(Math.max(1, width) / GRAIN) * GRAIN;
    const px = Math.round(css * this.dpr);
    if (this.el.width !== px) {
      this.el.width = px;
      this.el.style.width = `${css}px`;
      this.fall.width = px;
      this.fall.style.width = `${css}px`;
    }
    if (this.enabled) this.draw();
  }

  private touching(p: { x: number; above: number } | null): boolean {
    return p != null && p.above >= -2 && p.above <= SNOW.touch + 4
      && p.x >= -4 && p.x <= this.width + 4;
  }

  /** Something changed: run at full rate until it has settled again. */
  private wake() {
    if (!this.enabled) return;
    window.clearTimeout(this.timeout);
    this.timeout = 0;
    if (!this.frame) this.frame = requestAnimationFrame(this.tick);
  }

  private stop() {
    cancelAnimationFrame(this.frame);
    window.clearTimeout(this.timeout);
    this.frame = 0;
    this.timeout = 0;
    this.last = 0;
  }

  private tick = (now: number) => {
    this.frame = 0;
    this.timeout = 0;
    if (!this.enabled) return;

    // Reduce Motion: the bank as it drifted and nothing else — no growing, no
    // ploughing, no flakes, and so no ticker either.
    if (this.reduced?.matches) {
      this.draw();
      this.last = 0;
      return;
    }

    // A long gap is the ticker having been stopped, not a long frame.
    const elapsed = this.last ? (now - this.last) / 1000 : 1 / 60;
    const dt = elapsed > 1 || elapsed <= 0 ? 1 / 60 : elapsed;
    this.last = now;

    const near = this.touching(this.pointer);
    this.field.step(dt, this.width, this.expanded, near ? this.pointer : null);
    this.draw();

    if (near || !this.field.isSettled) {
      this.frame = requestAnimationFrame(this.tick);
    } else if (this.expanded && this.field.isGrowing) {
      this.timeout = window.setTimeout(() => this.tick(performance.now()), 500);
    } else {
      this.last = 0;
    }
  };

  // ── Falling ────────────────────────────────────────────────────────────────

  private falling(): boolean {
    return this.enabled && this.visible && this.height > 0 && !this.reduced?.matches;
  }

  /** Start the fall if it should be running; it stops itself when it should not. */
  private kickFall() {
    if (this.fallFrame) return;
    if (this.falling()) this.fallFrame = requestAnimationFrame(this.fallTick);
    else this.clearFall();
  }

  private clearFall() {
    this.fallCtx.setTransform(1, 0, 0, 1, 0, 0);
    this.fallCtx.clearRect(0, 0, this.fall.width, this.fall.height);
  }

  private fallTick = (now: number) => {
    this.fallFrame = 0;
    if (!this.falling()) { this.clearFall(); return; }
    // Thirty a second is plenty for something that moves a pixel in that time.
    if (now - this.fallLast >= 30 || now < this.fallLast) {
      this.fallLast = now;
      this.drawFall(now / 1000);
    }
    this.fallFrame = requestAnimationFrame(this.fallTick);
  };

  private drawFall(time: number) {
    const ctx = this.fallCtx;
    this.clearFall();
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    const mid = this.width / 2;
    const height = this.height;
    // The field repeats down the island, for one taller than a period.
    const repeats = Math.max(1, Math.ceil(height / SNOW.fallPeriod));
    ctx.fillStyle = "#FFFFFF";
    for (let i = 0; i < SNOW.fallCount; i++) {
      const f = snowFalling(i, time);
      if (Math.abs(f.x) > mid + 2) continue;
      for (let k = 0; k < repeats; k++) {
        const y = f.y + k * SNOW.fallPeriod;
        const visible = snowFallVisibility(y, height);
        if (visible <= 0) continue;
        ctx.globalAlpha = f.alpha * visible;
        ctx.beginPath();
        ctx.arc(mid + f.x, y, f.radius, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
  }

  private draw() {
    const { ctx, field } = this;
    const w = this.width;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.clearRect(0, 0, this.el.width, BAND);
    if (w <= 0) return;

    const mid = w / 2;
    const [first, last] = snowVisible(w);
    const x = (i: number) => mid + (i - MID) * SNOW.pitch;

    ctx.beginPath();
    ctx.moveTo(x(first), BAND);
    for (let i = first; i <= last; i++) ctx.lineTo(x(i), BAND - field.height(i));
    ctx.lineTo(x(last), BAND);
    ctx.closePath();
    const fill = ctx.createLinearGradient(0, BAND - SNOW.capHeight, 0, BAND);
    fill.addColorStop(0, "#FFFFFF");
    fill.addColorStop(1, "#D3E2F2");
    ctx.fillStyle = fill;
    ctx.fill();

    ctx.fillStyle = "#FFFFFF";
    for (const f of field.flakes) {
      ctx.globalAlpha = Math.min(1, f.life / 0.25);
      ctx.beginPath();
      ctx.arc(mid + f.x, BAND - f.y, f.size, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }
}
