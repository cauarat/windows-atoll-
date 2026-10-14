// Dev harness: the message list and the message card in a plain browser, with a
// fake inbox, so the layout can be checked without a Mattermost server. Not part
// of the app bundle.
//
// It imports the stylesheet, like `nowplaying-preview.ts` and for the same
// reason: these views are DOM, not a canvas. The mini Mochis they carry are
// canvases, though, so the loop at the bottom ticks them.

import "../src/style.css";
import { buildMessage } from "../src/views/message";
import { buildMessages } from "../src/views/messages";
import { tickMiniBots } from "../src/mochi/minibots";
import { State, type InboxMessage } from "../src/core/state";
import type { ViewActions } from "../src/views/views";
import type { MessageSource } from "../src/core/bridge";

const now = Date.now();

function msg(
  id: string,
  source: MessageSource,
  sender: string,
  channel: string | null,
  body: string,
  agoSeconds: number,
): InboxMessage {
  return {
    id,
    source,
    kind: channel == null ? "directMessage" : "mention",
    sender,
    channel,
    conversationId: "preview",
    body,
    timestampMs: now - agoSeconds * 1000,
    link: "https://example.com",
    read: false,
  };
}

/** Enough that the list has to scroll, and both services are represented. */
const INBOX: InboxMessage[] = [
  msg("1", "mattermost", "pedro_h", null, "me avisa quando der", 300),
  msg("2", "clickmassa", "Ticket #4821", null, "Novo atendimento aguardando resposta na fila.", 900),
  msg("3", "mattermost", "ana.lima", "suporte", "subi o patch em produção, pode conferir", 3_600),
  msg("4", "clickmassa", "Maria Eduarda", null, "Bom dia! O cliente perguntou se o plano anual tem desconto.", 5_400),
  msg("5", "mattermost", "julia.c", "produto", "a copy nova entrou no Figma", 7_200),
  msg("6", "mattermost", "rafael", null, "bom dia! consegue revisar o PR 6?", 9_000),
  msg("7", "mattermost", "time-infra", "alertas", "deploy de staging concluído sem erros", 11_000),
  msg("8", "mattermost", "fran_rodrigues", null, "muito obrigada", 43_200),
];

// Every method, because a view may reach for any of them and a missing one is a
// crash rather than a layout to look at. The three that matter here say so.
const log = document.createElement("div");
const actions: ViewActions = {
  setView: (v) => { log.textContent = `setView(${v})`; },
  collapse: () => {},
  setFocus: () => {},
  openTerminal: () => {},
  openTarget: () => {},
  openUrl: (url) => { log.textContent = `openUrl(${url})`; },
  decide: () => {},
  toggleSound: () => {},
  setVolume: () => {},
  setAutoClose: () => {},
  openSettingsWindow: () => {},
  setPinned: (on) => { log.textContent = `setPinned(${on})`; },
  focusField: () => {},
  blip: () => {},
};

/**
 * Each stage reads the same global `State`, so it is pointed at the right inbox
 * and the right open list immediately before that stage syncs — the same trick
 * `nowplaying-preview` uses for three cards and one media state.
 */
const stages = [
  { id: "one", host: buildMessages(actions), inbox: INBOX, list: "mattermost" as const },
  { id: "all", host: buildMessages(actions), inbox: INBOX, list: "all" as const },
  { id: "quiet", host: buildMessages(actions), inbox: [], list: "mattermost" as const },
  { id: "card", host: buildMessage(actions), inbox: INBOX, list: null },
  { id: "home", host: buildMessage(actions, true), inbox: INBOX, list: null },
];

for (const stage of stages) {
  stage.host.el.classList.add("on");
  document.getElementById(stage.id)!.append(stage.host.el);
}

let last = performance.now();

function loop(at: number) {
  const dt = Math.min(0.05, (at - last) / 1000);
  last = at;
  for (const stage of stages) {
    State.messages = stage.inbox;
    State.listSource = stage.list;
    State.activeMessageId = stage.inbox[0]?.id ?? null;
    State.lastSource = stage.inbox[0]?.source ?? null;
    State.lastBySource = stage.inbox[0] ? { [stage.inbox[0].source]: stage.inbox[0] } : {};
    stage.host.sync();
  }
  tickMiniBots(dt);
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
