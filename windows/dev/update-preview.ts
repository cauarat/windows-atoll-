// Dev harness: the update card in each thing it can say, seeded straight into
// the store (`Updates.seed`), so nothing here asks Rust or GitHub.
//
// Mochi is the real engine, drawn where `botPosition` puts him. Buttons do
// nothing: Update now would call the updater, which is not here.
//
// `npx vite`, then /dev/update-preview.html — `?lang=pt-BR` or `?lang=es` for
// the other two languages.

import "../src/style.css";
import { buildUpdate } from "../src/views/update";
import type { ViewActions } from "../src/views/views";
import { Updates, type UpdateOffer } from "../src/core/updates";
import { setLanguage, type Language } from "../src/core/i18n";
import { botPosition, islandSize } from "../src/core/layout";
import { BotEngine } from "../src/mochi/engine";

const noop = () => {};
const actions: ViewActions = {
  setView: noop, collapse: noop, setFocus: noop, openUrl: noop, toggleSound: noop,
  setVolume: noop, setAutoClose: noop, openSettingsWindow: noop,
  setPinned: noop, focusField: noop, closeScreen: noop, blip: noop,
};

const asked = new URLSearchParams(location.search).get("lang");
if (asked) setLanguage(asked as Language);

const URL = "https://github.com/cauarat/windows-atoll-/releases";
const CASES: { label: string; offer: UpdateOffer }[] = [
  { label: "a new version — Update now / Later", offer: { kind: "available", version: "0.1.29" } },
  { label: "downloading, 42%", offer: { kind: "downloading", version: "0.1.29", progress: 0.42 } },
  { label: "installed, restarting", offer: { kind: "restarting", version: "0.1.29" } },
  { label: "a copy that cannot replace itself", offer: { kind: "manual", version: "0.1.29", url: URL } },
  {
    label: "the install failed",
    offer: { kind: "failed", version: "0.1.29", url: URL, error: "the signature was created with a different key" },
  },
];

const OVERHANG = 40;
const dpr = Math.min(2, window.devicePixelRatio || 1);
const cols = document.getElementById("cols")!;
Updates.current = "0.1.28";

for (const c of CASES) {
  const { h } = islandSize("expanded", "update", 0, "automatic", 0, false, false, 0);
  const bot = botPosition("expanded", "update", h);

  const col = document.createElement("div");
  col.className = "col";
  const label = Object.assign(document.createElement("div"), { className: "label", textContent: `${c.label} — ${h}px` });
  const stageEl = document.createElement("div");
  stageEl.className = "stage";
  stageEl.style.height = `${h}px`;
  const inner = document.createElement("div");
  inner.className = "inner";
  const host = buildUpdate(actions);
  host.el.classList.add("on");
  inner.append(host.el);

  const width = Math.round(bot.diameter / 0.6);
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(width * dpr);
  canvas.height = Math.round((width + OVERHANG) * dpr);
  canvas.style.width = `${width}px`;
  canvas.style.height = `${width + OVERHANG}px`;
  canvas.style.left = `${bot.cx - width / 2}px`;
  canvas.style.top = `${bot.cy - OVERHANG / 2 - (width + OVERHANG) / 2}px`;

  stageEl.append(inner, canvas);
  col.append(label, stageEl);
  cols.append(col);

  Updates.seed(c.offer);
  host.sync();

  const engine = new BotEngine();
  engine.particleOverhang = OVERHANG;
  const ctx = canvas.getContext("2d");
  if (ctx) {
    for (let i = 0; i < 2; i++) {
      engine.update(0.016);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, width, width + OVERHANG);
      engine.draw(ctx, width, width + OVERHANG);
    }
  }
}
