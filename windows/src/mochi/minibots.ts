// Mini Mochis (pills + compact grid) — port of MiniBotCanvasView.
// Each canvas owns a BotEngine; the island's frame loop ticks every live one.

import { BotEngine, hexToRGB } from "./engine";
import { State, type AgentTask } from "../core/state";
import type { BotStateName } from "../core/layout";
import { ATO_PILL, AtoDriver, atoStateFor, drawAtoInBotFrame } from "../ato/view";

interface MiniBot {
  canvas: HTMLCanvasElement;
  engine: BotEngine;
  cssSize: number;
  taskId: string;
  /** Ato wears its own mascot rather than a Mochi in Ato's colour. */
  ato: AtoDriver | null;
  state: BotStateName;
}

const live = new Map<HTMLCanvasElement, MiniBot>();

/**
 * Creates a mini Mochi whose **body** is `bodySize` CSS pixels across.
 *
 * The engine draws the body at 60 % of its canvas, so the canvas is
 * `bodySize / 0.6` and is centred in a `bodySize` slot, overflowing it — the
 * same thing SwiftUI does with a `.frame(width: 22/0.6)` inside a
 * `.frame(width: 22)`. Sizing the canvas itself to `bodySize` would shrink the
 * whole drawing to 60 %, which is what used to happen.
 */
export function createMiniBot(task: AgentTask, bodySize: number): HTMLElement {
  const slot = document.createElement("span");
  slot.className = "mini";
  slot.style.width = `${bodySize}px`;
  slot.style.height = `${bodySize}px`;

  const canvas = document.createElement("canvas");
  const engineSize = bodySize / 0.6;
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  canvas.width = Math.round(engineSize * dpr);
  canvas.height = Math.round(engineSize * dpr);
  canvas.style.width = `${engineSize}px`;
  canvas.style.height = `${engineSize}px`;
  slot.append(canvas);

  const engine = new BotEngine();
  engine.isMini = true;
  engine.bodyColor = hexToRGB(task.color);
  engine.setState(task.state, true);
  if (task.emote) engine.setPermanentEmote(task.emote);
  if (task.miniEye) {
    engine.permanentEye = task.miniEye;
    engine.eyeOverride = task.miniEye;
    engine.eyeOverrideUntil = Number.POSITIVE_INFINITY;
  }

  live.set(canvas, {
    canvas, engine, cssSize: engineSize, taskId: task.id, state: task.state,
    ato: task.id === ATO_PILL ? new AtoDriver(false) : null,
  });
  return slot;
}

export function releaseMiniBot(canvas: HTMLCanvasElement) {
  live.delete(canvas);
}

/** Drops every canvas no longer in the document (views are rebuilt wholesale). */
export function pruneMiniBots() {
  for (const [canvas] of live) {
    if (!canvas.isConnected) live.delete(canvas);
  }
}

export function syncMiniBotStates(tasks: AgentTask[]) {
  for (const mb of live.values()) {
    const task = tasks.find((t) => t.id === mb.taskId);
    if (!task) continue;
    mb.engine.setState(task.state);
    mb.state = task.state;
    mb.engine.bodyColor = hexToRGB(task.color);
    // Here rather than in createMiniBot, where the colour is also set once: a
    // mini bot's canvas is only rebuilt when the pill list changes, so a
    // character chosen in Settings would otherwise not show up until something
    // else forced a rebuild.
    mb.engine.character = State.characterFor(task.id);
  }
}

export function tickMiniBots(dt: number) {
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  for (const mb of live.values()) {
    const ctx = mb.canvas.getContext("2d");
    if (!ctx) continue;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, mb.cssSize, mb.cssSize);
    if (mb.ato) {
      const asked = atoStateFor(mb.state, State.messageStatus.ato?.state);
      drawAtoInBotFrame(ctx, mb.ato.frame(performance.now() / 1000, asked, null), mb.cssSize, mb.cssSize);
      continue;
    }
    mb.engine.update(dt);
    mb.engine.draw(ctx, mb.cssSize, mb.cssSize);
  }
}

export const miniBotCount = () => live.size;
