// What the island tells the phone link (src-tauri/src/phone_link, docs/PHONE_LINK.md).
//
// The twin of the Mac's PhoneLinkService (observe, publish and the mapping under
// it). While the link is on, the island publishes a picture of its agent sessions
// and of the permission request on its card; Rust works out what changed and
// sends it to the paired phones. A phone's Allow or Deny comes back through Rust,
// which answers the waiting hook exactly as the card's own buttons do, and only
// the card is closed here. While the link is off nothing is computed and no timer
// runs: a change of state costs one boolean test.
//
// What the Windows island does not have yet, it says nothing about: there is no
// AskUserQuestion card and no per-file diff (docs/parity, Phase 5), so no question
// is ever published and a phone that asks for a file's lines is told it is gone.

import {
  Bridge, onEvent,
  type PhoneLinkApproval, type PhoneLinkDiff, type PhoneLinkSession,
} from "../core/bridge";
import { State } from "../core/state";
import { FESTIVE_SLOTS, hasFestive, type MochiCharacter } from "../mochi/character";
import type { Island } from "./island";

const CLAUDE_ID = "integration_claude";

/** Changes arrive in bursts (a tool call is several events); one picture per burst, as the Mac's debounce. */
const DEBOUNCE_MS = 150;

/**
 * The island labels what it shows as "Bash · npm test". The phone shows the tool on its own
 * line, so it gets the bare command.
 */
export function bareCommand(tool: string, command: string): string {
  const prefix = `${tool} · `;
  return command.startsWith(prefix) ? command.slice(prefix.length) : command;
}

/**
 * A character as the wire carries it: the raw values the island stores, and nothing for
 * classic — the Mac's `PhoneLinkService.character`. A festive outfit is `head.eyes.texture.extra`.
 */
export function linkCharacter(c: MochiCharacter): Record<string, string> {
  const v: Record<string, string> = {};
  if (c.accessory) v.accessory = c.accessory;
  if (c.eye) v.eye = c.eye;
  if (c.shape) v.shape = c.shape;
  if (hasFestive(c)) v.festive = FESTIVE_SLOTS.map((slot) => c.festive?.[slot] || "-").join(".");
  return v;
}

/**
 * One session per agent pill, as the island shows them: services (Mattermost, Ato, Now
 * Playing…) are not sessions. Rust sends the details, files and character only to a phone
 * that was offered them, cuts everything to size and keeps only the folder's name.
 */
export function linkSessions(): PhoneLinkSession[] {
  return State.tasks
    .filter((t) => t.source !== "n8n")
    .map((t) => ({
      pillId: t.id,
      agent: t.name,
      state: t.state,
      statusText: t.steps[t.stepIndex] ?? t.steps[t.steps.length - 1] ?? "",
      stepIndex: t.stepIndex,
      stepCount: t.steps.length,
      steps: [...t.steps],
      project: t.sessionCwd || undefined,
      color: t.color,
      files: [],
      character: linkCharacter(State.characterFor(t.id)),
    }));
}

/**
 * The request on the card. Its request id goes into the fingerprint (Rust), so asking for the
 * same command twice gives two fingerprints, and a late decision for the first can never
 * answer the second. Only Claude Code's requests reach the card here.
 */
export function linkApproval(): PhoneLinkApproval | null {
  const a = State.pendingApproval;
  if (!a || !a.requestId) return null;
  return { requestId: a.requestId, sessionId: a.sessionId, pillId: CLAUDE_ID, tool: a.tool, command: bareCommand(a.tool, a.command) };
}

/** A file the island no longer has — and here, none yet: Windows keeps no per-file diffs (Phase 5). */
export function goneDiff(pillId: string, fileId: number): PhoneLinkDiff {
  return { pillId, fileId, name: "", added: 0, removed: 0, tooLarge: false, gone: true, lines: [] };
}

/**
 * The card was answered from a phone: Rust has already told the agent. The card goes the way
 * the Mac's `sendApprovalDecision` takes it down — no sound, the pill back to working.
 */
function dropAnsweredCard(island: Island, requestId: string) {
  if (State.pendingApproval?.requestId !== requestId) return;
  State.pendingApproval = null;
  State.isPinned = false;
  island.dropPin();
  State.updateTask(CLAUDE_ID, "working");
  State.setPillBadge(CLAUDE_ID, null);
  if (State.view === "approval") island.setView(State.defaultView());
  State.notify();
}

/** Returns what undoes it (a test may; the app registers once and keeps it). */
export function registerPhoneLink(island: Island): () => void {
  let running = false;
  /** What was last sent, as JSON; "" before anything was, so a link that comes up gets the whole picture. */
  let last = "";
  let lastQuestion = "";
  let timer: number | null = null;

  const publish = () => {
    timer = null;
    if (!running) return;
    const sessions = linkSessions();
    const approval = linkApproval();
    const key = JSON.stringify([sessions, approval]);
    if (key !== last) {
      last = key;
      void Bridge.phoneLinkPublish(sessions, approval);
    }
    // No AskUserQuestion card here yet: the hub is told there is no question, once.
    if (lastQuestion !== "null") {
      lastQuestion = "null";
      void Bridge.phoneLinkPublishQuestion(null);
    }
  };

  const schedule = () => {
    if (!running || timer != null) return;
    timer = window.setTimeout(publish, DEBOUNCE_MS);
  };

  const refresh = async () => {
    const now = (await Bridge.phoneLinkStatus())?.running ?? false;
    if (now === running) return;
    running = now;
    last = "";
    lastQuestion = "";
    if (running) schedule();
    else if (timer != null) {
      window.clearTimeout(timer);
      timer = null;
    }
  };

  const unsubscribe = State.subscribe(schedule);
  // Turning the link on or off in Settings reaches the island as settings-changed, and so does
  // a change of character, which phones with `character` see.
  void onEvent("settings-changed", () => {
    if (running) schedule();
    void refresh();
  });
  void onEvent<string>("phone-link-decided", (requestId) => dropAnsweredCard(island, requestId));
  // A phone asked for a file's lines: the answer goes to that phone only (Rust cuts it to the limits).
  void onEvent<{ conn: number; pillId: string; fileId: number }>("phone-link-getdiff", (ask) => {
    if (!running || typeof ask?.conn !== "number") return;
    void Bridge.phoneLinkSendDiff(ask.conn, goneDiff(String(ask.pillId), Number(ask.fileId)));
  });
  void refresh();
  return () => {
    unsubscribe();
    if (timer != null) window.clearTimeout(timer);
    timer = null;
    running = false;
  };
}
