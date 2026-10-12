// The message list — everything still unanswered from one service.
//
// Port of MessagesListView in IslandViewContent.swift. The card answers one
// message at a time, which is right for something that has just arrived and
// wrong for going back through what piled up while you were busy: from the card
// there is no way to the third thing down. This is that way.
//
// Newest at the top, oldest at the bottom, and the whole row is the target: a
// message is one thing to answer, not a title with a button beside it.

import { h, svg, clear, dot } from "./dom";
import { ICONS } from "./icons";
import { timeAgo } from "./integrations";
import { card, stack, type ViewActions, type ViewHost } from "./views";
import {
  CONNECTION_LABEL,
  SOURCE_COLOR,
  SOURCE_LABEL,
  State,
  sourceForPill,
  type InboxMessage,
} from "../core/state";
import type { MessageSource } from "../core/bridge";

/** One waiting message: who, where from, how long ago, and their first line. */
function row(message: InboxMessage, onOpen: () => void): HTMLElement {
  const accent = SOURCE_COLOR[message.source];
  const where = message.channel
    ? `in ${message.channel}`
    : `${SOURCE_LABEL[message.source]} · direct`;

  const head = h(
    "div",
    { class: "msg-row-head" },
    dot(accent, 5),
    h("b", { text: message.sender || SOURCE_LABEL[message.source] }),
    h("span", { class: "msg-where", text: where }),
    h("span", { class: "msg-age", text: timeAgo(message.timestampMs) }),
  );

  const el = h(
    "div",
    { class: "msg-row", onclick: onOpen },
    head,
    h("div", { class: "msg-body", text: message.body }),
  );
  el.style.setProperty("--accent", accent);
  return el;
}

/**
 * Why nothing is waiting, when the reason is the connection rather than a quiet
 * morning. Null while connected, because then an empty list means what it says.
 */
function connectionProblem(source: MessageSource): string | null {
  const status = State.messageStatus[source];
  const state = status?.state ?? "disconnected";
  if (state === "connected") return null;
  return status?.detail
    ? `${CONNECTION_LABEL[state]} · ${status.detail}`
    : CONNECTION_LABEL[state];
}

export function buildMessages(actions: ViewActions): ViewHost {
  const back = h(
    "button",
    {
      class: "tab",
      title: "Back",
      onclick: () => {
        State.closeMessageList();
        actions.setView("overview");
      },
    },
    svg(ICONS.chevronLeft, 12, { stroke: 2 }),
  );
  const sourceDot = dot("#6B7079", 7);
  const name = h("b", {});
  const count = h("span", { class: "msg-count" });
  const head = h("div", { class: "msg-head" }, back, sourceDot, name, count);

  const list = h("div", { class: "msg-list" });
  const body = stack(108, 12, head, list);
  // A list fills from the top; .stack centres what it holds.
  body.style.justifyContent = "flex-start";
  const cardEl = card("indigo", body);
  const el = h("div", { class: "view" }, cardEl);

  /** Whose list this is. The focused pill is the fallback, so the view still
   *  knows what to draw if it is reached any other way. */
  function source(): MessageSource | null {
    return State.listSource ?? (State.focusId ? sourceForPill(State.focusId) : null);
  }

  return {
    el,
    sync() {
      const src = source();
      const waiting = src ? State.unreadList(src) : [];

      sourceDot.style.background = src ? SOURCE_COLOR[src] : "#6B7079";
      name.textContent = src ? SOURCE_LABEL[src] : "Messages";
      count.textContent = waiting.length > 0 ? `${waiting.length} waiting` : "";
      if (src) cardEl.style.setProperty("--wash", `${SOURCE_COLOR[src]}8c`);

      clear(list);
      if (waiting.length === 0) {
        // An empty list has two meanings, and saying the wrong one is how
        // someone spends an afternoon waiting on a socket that was never
        // connected.
        const problem = src ? connectionProblem(src) : null;
        list.append(
          h("div", {
            class: "sub",
            style: problem ? "color:var(--red-text)" : "",
            text: problem ?? "Nothing waiting.",
          }),
        );
        return;
      }
      for (const message of waiting) {
        list.append(
          row(message, () => {
            State.selectMessage(message.id);
            actions.setView("message");
          }),
        );
      }
    },
  };
}
