// Dev harness: the Agenda tab with meetings around now — a day with one held,
// one on now, one a heads-up just opened the island for and one this
// afternoon — then the empty and signed-out cards. The green circle is where
// `botPosition` puts Mochi, which has to sit in the header's empty seat.
//
// `npx vite`, then /dev/agenda-preview.html.

import "../src/style.css";
import { buildAgenda } from "../src/views/agenda";
import type { ViewActions } from "../src/views/views";
import { Agenda } from "../src/island/agenda";
import { State } from "../src/core/state";
import { botPosition, islandSize } from "../src/core/layout";
import type { AgendaSnapshot } from "../src/core/agendaRules";

const noop = () => {};
const actions: ViewActions = {
  setView: noop, collapse: noop, setFocus: noop, openTerminal: noop,
  openTarget: noop, openUrl: noop, decide: noop, toggleSound: noop,
  setVolume: noop, setAutoClose: noop, openSettingsWindow: noop,
  setPinned: noop, focusField: noop, closeScreen: noop, blip: noop,
};

State.settings = { ...State.settings, agendaEnabled: true };
Agenda.seedForPreview();
const day = Agenda.snapshot;

const CASES: { label: string; snapshot: AgendaSnapshot; highlight: string | null }[] = [
  { label: "a heads-up for the 2nd attempt with welber", snapshot: day, highlight: "seed-3" },
  { label: "opened by hand — the one on now leads", snapshot: day, highlight: null },
  { label: "a free day", snapshot: { status: "ready", detail: null, meetings: [], fetchedAtMs: Date.now() }, highlight: null },
  { label: "no Actuar account yet", snapshot: { status: "signed-out", detail: null, meetings: [], fetchedAtMs: 0 }, highlight: null },
];

const cols = document.getElementById("cols")!;
const { h } = islandSize("expanded", "agenda", 0, "automatic", 0, false, false, 0);
const bot = botPosition("expanded", "agenda", h);

for (const c of CASES) {
  const col = document.createElement("div");
  col.className = "col";
  col.append(Object.assign(document.createElement("div"), { className: "label", textContent: `${c.label} — ${h}px` }));
  const stage = document.createElement("div");
  stage.className = "stage";
  stage.style.height = `${h}px`;
  const inner = document.createElement("div");
  inner.className = "inner";
  const view = buildAgenda(actions);
  view.el.classList.add("on");
  inner.append(view.el);
  const face = document.createElement("div");
  face.className = "mochi";
  face.style.left = `${bot.cx - bot.diameter / 2}px`;
  face.style.top = `${bot.cy - bot.diameter / 2}px`;
  face.style.width = face.style.height = `${bot.diameter}px`;
  stage.append(inner, face);
  col.append(stage);
  cols.append(col);

  Agenda.snapshot = c.snapshot;
  Agenda.highlight = c.highlight;
  Agenda.highlightAtMs = Date.now();
  view.sync();
}
