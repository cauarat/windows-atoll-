// Dev harness: the message card at four body lengths, built twice — clamped to
// two lines as it ships, and let out to hold the whole message. The only way to
// check this layout without Windows, and the only way at all on a Mac: the
// island will not open from a hook event here.
//
// Each stage is the height `islandSize` actually asks for, not the table's 160,
// so a card that grew wrong is visible rather than a matter of opinion. The red
// hairline is `MESSAGE_EXPANDED_CAP`; the green circle is where `botPosition`
// puts Mochi, which must stay level with the name whatever the card does.

import "../src/style.css";
import { buildMessage } from "../src/views/message";
import type { ViewActions } from "../src/views/views";
import { State, type InboxMessage } from "../src/core/state";
import {
  MESSAGE_BODY_TWO_LINES, MESSAGE_EXPANDED_CAP, botPosition, islandSize,
  messageBodyWidth,
} from "../src/core/layout";
import { measureBodyHeight } from "../src/views/dom";

const noop = () => {};
const actions: ViewActions = {
  setView: noop, collapse: noop, setFocus: noop, openTerminal: noop,
  openTarget: noop, openUrl: noop, decide: noop, toggleSound: noop,
  setVolume: noop, setAutoClose: noop, openSettingsWindow: noop,
  setPinned: noop, focusField: noop, blip: noop,
};

const LONG = "Olá! 😊 Tudo bem? Passando para avisar que o pedido 48213 foi "
  + "separado e sai hoje à tarde. O cliente pediu para antecipar a entrega, "
  + "mas a transportadora só tem janela na quinta — confirmei com ele por "
  + "telefone e ficou acertado assim. Se precisar de algo antes disso me chama "
  + "aqui mesmo que eu resolvo.";

const FIXTURES: { label: string; body: string }[] = [
  { label: "one line", body: "Bom dia 😃" },
  { label: "two lines — the card as it is today", body: "Olá! 😊 Tudo bem? Passando para avisar que o pedido 48213 foi separado e sai hoje à tarde." },
  { label: "a paragraph", body: LONG },
  { label: "past the cap — this one scrolls", body: Array(8).fill(LONG).join("\n\n") },
];

function message(body: string): InboxMessage {
  return {
    id: `m-${body.length}`, source: "clickmassa", kind: "directMessage",
    sender: "~cato", channel: null, conversationId: "c1", body,
    timestampMs: Date.now() - 40_000, link: "https://example.invalid/", read: false,
  };
}

function column(id: string, full: boolean) {
  const host = document.getElementById(id)!;
  const built: { sync(): void }[] = [];

  for (const fixture of FIXTURES) {
    State.settings = { ...State.settings, messageFullBody: full };
    const view = buildMessage(actions);
    const msg = message(fixture.body);
    State.messages = [msg];
    State.activeMessageId = msg.id;

    // The same two steps `island.bodyOverflow` takes, so the stage is the size
    // the real island would ask for.
    const overflow = full
      ? Math.max(0, measureBodyHeight(fixture.body, messageBodyWidth(false)) - MESSAGE_BODY_TWO_LINES)
      : 0;
    const { h } = islandSize("expanded", "message", 0, "automatic", 0, false, false, overflow);
    const bot = botPosition("expanded", "message", h);

    host.append(Object.assign(document.createElement("div"),
      { className: "label", textContent: `${fixture.label} — ${h}px` }));

    const stage = document.createElement("div");
    stage.className = "stage";
    stage.style.height = `${h}px`;
    const inner = document.createElement("div");
    inner.className = "inner";
    view.el.classList.add("on");
    inner.append(view.el);

    const cap = document.createElement("div");
    cap.className = "cap";
    cap.style.top = `${MESSAGE_EXPANDED_CAP - 1}px`;
    const face = document.createElement("div");
    face.className = "mochi";
    face.style.left = `${bot.cx - bot.diameter / 2}px`;
    face.style.top = `${bot.cy - bot.diameter / 2}px`;
    face.style.width = `${bot.diameter}px`;
    face.style.height = `${bot.diameter}px`;

    stage.append(inner, cap, face);
    host.append(stage);
    view.sync();
    built.push(view);
  }
  return built;
}

// Built once and left: every stage holds its own card, and syncing them all
// from one loop would show every card the last fixture's message.
column("clamped", false);
column("full", true);
