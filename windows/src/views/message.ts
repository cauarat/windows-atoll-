// The message pop-up — the card Mattermost and ClickMassa messages land in.
//
// Atoll's behaviour is the specification: who it is from on the first line, the
// message under it, a reply field on the left and Open on the far right. Return
// sends and the card goes; Escape waves it away. While the field has the cursor
// the island is pinned, because a card that slid away on its own timer would
// take a half-written sentence with it.
//
// One card for both sources, like MessageEvent is one shape for both: the only
// thing that varies is the accent colour and what the ↗ points at.

import { h, svg, clear, dot } from "./dom";
import { ICONS } from "./icons";
import { timeAgo } from "./integrations";
import { btn, card, stack, type ViewActions, type ViewHost } from "./views";
import { State, SOURCE_COLOR, SOURCE_LABEL, homeSource, type InboxMessage } from "../core/state";
import { replyToMessage } from "../island/messages";

/** Who it is from, where it came from, and how long ago. */
function whoRow(message: InboxMessage, others: number): Node[] {
  const accent = SOURCE_COLOR[message.source];
  const where = message.channel
    ? `in ${message.channel}`
    : `${SOURCE_LABEL[message.source]} · direct`;
  const age = timeAgo(message.timestampMs);
  return [
    dot(accent, 8),
    h("span", { class: "n", text: message.sender || SOURCE_LABEL[message.source] }),
    h("span", { text: where }),
    h("span", {
      style: "margin-left:auto;flex:0 0 auto;font:400 11px var(--font);color:var(--dim-3)",
      text: others > 0 ? `${others} more waiting · ${age}` : age,
    }),
  ];
}

/**
 * @param home Built for the Home tab rather than as the notification pop-up.
 *
 * The difference is which message, and that is the point. The pop-up shows
 * `State.activeMessage` — the newest **unread** — so it empties the moment you
 * answer. Home shows the newest from its source whether or not it has been
 * read, so the notification is still here when you come back to it after the
 * card has folded away. Home also never takes itself off screen: you opened it.
 */
export function buildMessage(actions: ViewActions, home = false): ViewHost {
  const who = h("div", { class: "who-row", style: "flex:0 0 auto" });
  const body = h("div", {
    class: "sub",
    // Two lines, then an ellipsis. The card is a fixed 160 and the three rows
    // fill it exactly, so each one refuses to be squeezed: letting the body
    // shrink instead clipped its second line in half.
    style:
      "flex:0 0 auto;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;" +
      "overflow:hidden;line-height:1.35;height:36px;white-space:pre-wrap;word-break:break-word",
  });

  const input = h("input", {
    type: "text",
    class: "chat-input",
    placeholder: "Reply…",
    spellcheck: "false",
    autocomplete: "off",
  }) as HTMLInputElement;
  // A notch shorter than the chat's: three rows have to fit inside 160.
  const send = h("button", {
    class: "send-btn", title: "Send", style: "width:24px;height:24px;flex:0 0 24px",
  }, svg(ICONS.arrowUp, 11));
  const bar = h("div", { class: "chat-bar", style: "flex:1 1 auto;min-width:0" }, input, send);
  const open = btn("Open", "secondary", () => openCurrent());
  const row = h("div", { class: "actions", style: "flex:0 0 auto;align-items:center" }, bar, open);

  // The pop-up is tinted by whoever wrote; Home draws its own background, like
  // every other thing Home can hold.
  const cardEl = card(home ? null : "indigo", stack(116, 16, who, body, row));
  const el = h("div", { class: "view" }, cardEl);

  /** The id the fields were last reset for, so typing survives a re-sync. */
  let shownId: string | null = null;
  let sending = false;
  let error: string | null = null;

  function current(): InboxMessage | null {
    return home ? State.homeMessage : State.activeMessage;
  }

  /** Done with this card: mark it read and show the next one, or go home. */
  function dismiss() {
    const message = current();
    if (message) State.dismissMessage(message.id);
    input.value = "";
    error = null;
    sending = false;
    // Home stays. Taking the tab away after a reply would undo the whole reason
    // Home holds the last message in the first place.
    if (home) return;
    const more = State.unreadMessages.length > 0;
    // Keep the cursor — and with it the pin — only while there is another card
    // to answer. Letting go anywhere else would leave the island pinned open on
    // a field nobody can see.
    if (!more) input.blur();
    actions.setView(more ? "message" : State.defaultView());
  }

  function openCurrent() {
    const message = current();
    if (message?.link) actions.openUrl(message.link);
    dismiss();
  }

  async function submit() {
    const message = current();
    const text = input.value.trim();
    if (!message || !text || sending) return;
    if (!message.conversationId) {
      error = "There is nowhere to reply to this one.";
      State.notify();
      return;
    }
    sending = true;
    error = null;
    State.notify();
    try {
      await replyToMessage(message, text);
      input.value = "";
      sending = false;
      dismiss();
    } catch (err) {
      // The card says what went wrong and keeps what was typed: a reply that
      // vanished with the error would have to be written twice.
      sending = false;
      error = String(err).replace(/^Error:\s*/, "");
      State.notify();
    }
  }

  /** What an empty card says — named by its source when Home has one. */
  function emptyLine(): string {
    if (!home) return "Nothing waiting.";
    const source = homeSource(State.settings.homeContent, State.lastSource);
    if (source === "clickmassa") return "Nothing from ClickMassa yet.";
    if (source === "mattermost") return "Nothing from Mattermost yet.";
    return "No messages yet.";
  }

  send.addEventListener("click", () => void submit());

  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      void submit();
    } else if (e.key === "Escape") {
      e.preventDefault();
      input.blur();
      if (!home) dismiss();
    }
    // The island closes on Escape too; handling it here means it closes once.
    e.stopPropagation();
  });

  // Clicking into the field is a request for the keyboard, and the window has to
  // be allowed to take it before the keystrokes can land — the island is created
  // non-activating precisely so a card arriving never does this on its own.
  // `mousedown` rather than `focus`: it runs before the field takes the caret.
  input.addEventListener("mousedown", () => void actions.focusField(true));
  input.addEventListener("focus", () => actions.setPinned(true));
  input.addEventListener("blur", () => {
    actions.setPinned(false);
    void actions.focusField(false);
  });

  return {
    el,
    sync() {
      const message = current();
      if (!message) {
        who.replaceChildren(h("span", { text: emptyLine() }));
        body.textContent = "";
        row.style.display = "none";
        return;
      }
      row.style.display = "";

      if (message.id !== shownId) {
        shownId = message.id;
        input.value = "";
        error = null;
      }

      if (!home) cardEl.style.setProperty("--wash", `${SOURCE_COLOR[message.source]}8c`);

      const others = State.unreadMessages.filter((m) => m.id !== message.id).length;
      clear(who);
      for (const node of whoRow(message, others)) who.append(node);

      body.textContent = error ?? message.body;
      body.style.color = error ? "var(--red-text)" : "";

      input.disabled = sending;
      input.placeholder = !message.conversationId
        ? "No reply channel"
        : sending
          ? "Sending…"
          : `Reply to ${message.sender || SOURCE_LABEL[message.source]}…`;
      send.style.opacity = sending ? "0.4" : "1";
      open.style.display = message.link ? "" : "none";
    },
    focus() {
      input.focus();
      input.select();
    },
  };
}
