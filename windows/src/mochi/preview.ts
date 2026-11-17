// A character, drawn once and left alone — the tiles of the Settings picker.
//
// Deliberately static. These are identity swatches, not animations, and
// eighteen live engines breathing away in a settings window would burn a core
// for nothing. One frame, one engine, thrown away afterwards.

import { BotEngine, hexToRGB } from "./engine";
import type { MochiCharacter, MochiFestive } from "./character";
import { poseAt, scene } from "../ato/bot";
import { drawAtoInBotFrame } from "../ato/view";

function blank(size: number): [HTMLCanvasElement, CanvasRenderingContext2D | null, number] {
  const canvasSize = size / 0.6;
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(canvasSize * dpr);
  canvas.height = Math.round(canvasSize * dpr);
  canvas.style.width = `${canvasSize}px`;
  canvas.style.height = `${canvasSize}px`;
  const ctx = canvas.getContext("2d");
  ctx?.setTransform(dpr, 0, 0, dpr, 0, 0);
  return [canvas, ctx, canvasSize];
}

/**
 * Draws one character into a fresh canvas.
 *
 * @param size the body's size in CSS pixels; the canvas is bigger, because the
 *   engine draws the body at 60 % of its canvas and a crown needs the rest.
 */
export function characterPreview(
  character: MochiCharacter, color: string, size: number,
): HTMLCanvasElement {
  const [canvas, ctx, canvasSize] = blank(size);
  if (!ctx) return canvas;

  const engine = new BotEngine();
  engine.bodyColor = hexToRGB(color);
  engine.character = character;
  // A swatch shows the lights at rest, not at whatever instant it was drawn.
  engine.festiveStill = true;
  engine.setState("idle", true);
  // One update, so the idle pose settles rather than being drawn mid-spring.
  engine.update(0.6);
  // Facing you, eyes open: a swatch should show the character, not a mood.
  engine.yaw = 0;
  engine.pitch = 0;
  engine.roll = 0;
  engine.tilt = 0;
  engine.open = 1;
  engine.sx = 1;
  engine.sy = 1;
  engine.ox = 0;
  engine.oy = 0;

  engine.draw(ctx, canvasSize, canvasSize);
  return canvas;
}

/**
 * Ato at rest, wearing `festive` — its tile in the Christmas rows.
 *
 * Ato is not a Mochi and has no character to preview beyond this, so it is
 * the orb's own still (the pose its mark in the pill is cut from), drawn where
 * a Mochi's body would be so the two kinds of tile line up.
 */
export function atoPreview(festive: MochiFestive | undefined, size: number): HTMLCanvasElement {
  const [canvas, ctx, canvasSize] = blank(size);
  if (!ctx) return canvas;
  drawAtoInBotFrame(
    ctx, { scene: scene(poseAt("idle", 0)), motion: null, body: null },
    canvasSize, canvasSize, 0, festive ? { parts: festive, time: null } : null,
  );
  return canvas;
}
