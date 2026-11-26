// Dev harness: the dictation card in each of its states, seeded through
// `Dictation.seedForPreview` — made-up words, no microphone, no connection and
// no service behind them. Mochi is a plain disc where `botPosition` puts him.
//
// `npx vite`, then /dev/dictation-preview.html — `?lang=pt-BR` or `?lang=es`.

import "../src/style.css";
import { buildDictation } from "../src/views/dictation";
import type { ViewActions } from "../src/views/views";
import { Dictation } from "../src/island/dictation";
import { State } from "../src/core/state";
import { setLanguage, type Language } from "../src/core/i18n";
import { botPosition, islandSize } from "../src/core/layout";

const noop = () => {};
const actions: ViewActions = {
  setView: noop, collapse: noop, setFocus: noop, openTerminal: noop,
  openTarget: noop, openUrl: noop, decide: noop, toggleSound: noop,
  setVolume: noop, setAutoClose: noop, openSettingsWindow: noop,
  setPinned: noop, focusField: noop, closeScreen: noop, blip: noop,
};

const asked = new URLSearchParams(location.search).get("lang");
if (asked) setLanguage(asked as Language);

const CASES: [string, string][] = [
  ["idle", "opened from the tray, the service answering"],
  ["offline", "opened from the tray, nothing running at the address"],
  ["recording", "recording, offline backend (text at the end)"],
  ["streaming", "recording, streaming backend (partials)"],
  ["finishing", "stopped, waiting for the final"],
  ["done", "the final, to edit, copy or paste"],
  ["pasted", "from the held key: pasted where the cursor was"],
  ["failed-offline", "the service went away"],
  ["failed-model", "the service cannot run the model, a partial kept"],
];

State.view = "dictation";
State.mode = "expanded";
const cols = document.getElementById("cols")!;
const { h } = islandSize("expanded", "dictation", 0, "automatic", 0, false, false, 0);
const bot = botPosition("expanded", "dictation", h);
const col = document.createElement("div");
col.className = "col";
cols.append(col);
for (const [scene, label] of CASES) {
  Dictation.seedForPreview(scene);
  const view = buildDictation(actions);
  view.sync();
  view.tick?.(performance.now());
  const caption = document.createElement("div");
  caption.className = "label";
  caption.innerHTML = `<b>${scene}</b> — ${label}`;
  const stage = document.createElement("div");
  stage.className = "stage";
  stage.style.height = `${h}px`;
  const inner = document.createElement("div");
  inner.className = "inner";
  inner.append(view.el);
  view.el.classList.add("on");
  const mochi = document.createElement("div");
  mochi.className = "mochi";
  mochi.style.width = mochi.style.height = `${bot.diameter}px`;
  mochi.style.left = `${bot.cx - bot.diameter / 2}px`;
  mochi.style.top = `${bot.cy - bot.diameter / 2}px`;
  stage.append(inner, mochi);
  col.append(caption, stage);
}
