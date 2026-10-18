// Dev harness: every card that leaves a gutter for Mochi, built twice — once
// with the characters on, once with them off — so the two can be read side by
// side. The only way to check this layout without Windows. Not in the bundle.
//
// The left column is the app as it ships. The right column is the same views
// built with `hideCharacters` on, inside a `.no-mochi` wrapper, which is what
// `island.applySettings()` puts on `<body>` for real.

import "../src/style.css";
import { buildViews, type ViewActions } from "../src/views/views";
import { tickMiniBots } from "../src/mochi/minibots";
import { State } from "../src/core/state";
import type { IslandViewName } from "../src/core/layout";
import { VIEW_LAYOUTS } from "../src/core/layout";

const noop = () => {};
const actions: ViewActions = {
  setView: noop, collapse: noop, setFocus: noop, openTerminal: noop,
  openTarget: noop, openUrl: noop, decide: noop, toggleSound: noop,
  setVolume: noop, setAutoClose: noop, openSettingsWindow: noop,
  setPinned: noop, focusField: noop, blip: noop,
};

/** The cards worth looking at: each one pads around a face. */
const SHOWN: IslandViewName[] = [
  "overview", "empty", "approval", "question", "error", "finished",
  "confused", "note", "message", "messages", "integrations", "timer",
  "upload", "choose",
];

State.tasks = [
  { id: "claude_code", name: "claude-code", color: "#E07950", state: "working",
    stepIndex: 0, steps: ["Reading IslandRootView.swift"], source: "claudeCode", isIntegration: false },
  { id: "integration_mattermost", name: "Mattermost", color: "#1E325C", state: "idle",
    stepIndex: 0, steps: [], source: "n8n", isIntegration: true },
  { id: "integration_clickmassa", name: "ClickMassa", color: "#7C5CFF", state: "idle",
    stepIndex: 0, steps: [], source: "n8n", isIntegration: true },
];
State.focusId = "claude_code";
State.noteMessage = "Saved to the clipboard.";

// The message list is the one card with no gutter: Mochi sits on its header
// line instead. Empty it would say nothing about that, so it gets something to
// hold — rows are what the full width is for.
State.listSource = "clickmassa";
State.messages = [
  { id: "m1", source: "clickmassa", kind: "directMessage", sender: "~cato",
    channel: null, conversationId: null, body: "Bom dia 😃",
    timestampMs: Date.now() - 40_000, link: null, read: false },
  { id: "m2", source: "clickmassa", kind: "channel", sender: "~cato",
    channel: "suporte", conversationId: null,
    body: "O cliente respondeu, dá uma olhada quando puder",
    timestampMs: Date.now() - 9 * 60_000, link: null, read: false },
];

function column(id: string, hide: boolean) {
  State.settings = { ...State.settings, hideCharacters: hide };
  const host = document.getElementById(id)!;
  const views = buildViews(actions, noop);
  const built: { sync(): void; tick?(n: number): void }[] = [];

  for (const name of SHOWN) {
    const v = views.get(name);
    if (!v) continue;
    const h = VIEW_LAYOUTS[name].height;
    host.append(Object.assign(document.createElement("div"),
      { className: "label", textContent: name }));
    const stage = document.createElement("div");
    stage.className = "stage";
    stage.style.height = `${h}px`;
    const inner = document.createElement("div");
    inner.className = "inner";
    // A hairline where the gutter ends, so a card that did not close up is
    // obvious rather than a matter of opinion.
    const rule = document.createElement("div");
    rule.className = "rule";
    rule.style.left = hide ? "18px" : "116px";
    v.el.classList.add("on");
    inner.append(v.el);
    stage.append(inner, rule);
    host.append(stage);
    built.push(v);
  }
  return built;
}

const columns = [
  { views: column("on", false), hide: false },
  { views: column("off", true), hide: true },
];

let last = performance.now();
function loop(now: number) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  // Both columns read the same global State, so the flag has to be put back
  // before each one syncs — `buildPill` rebuilds its row from it every time.
  for (const col of columns) {
    State.settings = { ...State.settings, hideCharacters: col.hide };
    for (const v of col.views) { v.sync(); v.tick?.(now); }
  }
  tickMiniBots(dt);
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
