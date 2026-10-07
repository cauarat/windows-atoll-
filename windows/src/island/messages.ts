// Message events → island state. The Mattermost / ClickMassa counterpart of
// src/island/integrations.ts, and deliberately the same shape: a genuinely new
// item flips the pill, badges it when the pill isn't focused, plays a sound,
// wakes the island and clears itself after 60 s.
//
// The one difference is what happens next. A deployment is news; a message is
// someone waiting, so this one opens the card rather than only revealing the
// compact island.

import { Bridge, onEvent, type ConnectionStatus, type MessageEvent } from "../core/bridge";
import { Sound } from "../core/sound";
import {
  INTEGRATION_AGENTS, PILL_FOR_SOURCE, SOURCE_LABEL, State, type InboxMessage,
} from "../core/state";
import type { Island } from "./island";

/** Same 60 s the pollers use before a pill goes quiet again. */
const CLEAR_AFTER_MS = 60_000;

/** What a pill is called when nothing is waiting on it. */
const DEFAULT_PILL_NAME: Record<string, string> = Object.fromEntries(
  INTEGRATION_AGENTS.map((agent) => [agent.id, agent.name]),
);

const clearTimers = new Map<string, number>();

export function registerMessageHandlers(island: Island) {
  void onEvent<MessageEvent>("message", (event) => handle(island, event));
  void onEvent<ConnectionStatus>("message-status", (status) => {
    State.setMessageStatus(status.source, { state: status.state, detail: status.detail });
  });
}

/**
 * Sends a reply from the card.
 *
 * Throws rather than reporting false: the card has a line to show the reason
 * in, and "it didn't send" without the reason is the worst of both.
 */
export async function replyToMessage(message: InboxMessage, text: string): Promise<void> {
  const conversationId = message.conversationId;
  if (!conversationId) throw new Error("There is nowhere to reply to this one.");
  await Bridge.sendReply(message.source, conversationId, text);
  Sound.play("send");
}

function handle(island: Island, event: MessageEvent) {
  if (State.paused) return;

  // Someone mid-sentence in the reply box keeps their card. The pin is set by
  // the field taking the cursor and by nothing else on this view, so it is the
  // honest answer to "is anybody typing". The new message is still taken in,
  // badged and counted; it comes up when they are done with the one in front
  // of them.
  const typing = State.view === "message" && State.isPinned;
  const held = State.activeMessageId;

  // A reconnect replays history, so the id decides whether this is news.
  if (!State.ingestMessage(event)) return;
  if (typing && held != null) State.activeMessageId = held;

  const pillId = PILL_FOR_SOURCE[event.source];
  const task = State.tasks.find((t) => t.id === pillId);
  if (task) {
    // The pill shows who is waiting, the way the music pill shows the track.
    task.state = "question";
    task.name = event.sender || SOURCE_LABEL[event.source];
    task.steps = [event.channel ?? SOURCE_LABEL[event.source], event.body];
    task.stepIndex = task.steps.length - 1;
    if (State.focusId !== pillId) task.pillBadge = "approval";
    scheduleClear(pillId);
  }

  Sound.play("question");
  if (!typing) {
    island.reveal();
    island.setView("message");
  }
  State.notify();
}

function scheduleClear(pillId: string) {
  const existing = clearTimers.get(pillId);
  if (existing != null) window.clearTimeout(existing);
  clearTimers.set(
    pillId,
    window.setTimeout(() => {
      clearTimers.delete(pillId);
      const task = State.tasks.find((t) => t.id === pillId);
      if (!task || task.state !== "question") return;
      task.state = "idle";
      task.steps = [];
      task.stepIndex = 0;
      task.pillBadge = null;
      task.name = DEFAULT_PILL_NAME[pillId] ?? task.name;
      State.notify();
    }, CLEAR_AFTER_MS),
  );
}
