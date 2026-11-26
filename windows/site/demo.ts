// The island on the download page: the app's own island (src/main.ts), fed by
// the stand-ins in site/shim instead of Rust, and played through a scene.
//
// Scenes, from `?scene=`:
//   hero     opens as Notchy does at launch — "Boa noite, Cauã!", the Christmas
//            music from the first click — then lives a day: an agent works and
//            asks permission, and Mattermost, WhatsApp and Ato messages arrive.
//   message  opens straight on a message (`?source=` picks the app).
//   water    opens straight on the water card.
//   rest     sits folded in the notch until hovered.
//   greet    only says hello (the sheet after a download).
//
// Every scene starts with the three inboxes "connected" in test mode: words, a
// photo and a voice note waiting in each, to open, browse and answer.

import "./preflag";
import "../src/main";
import { emitLocal } from "./shim/event";
import { startMedia, onApproval } from "./shim/core";
import { SCENE, S, MAC_CHARACTERS, MAC_DEFAULT_CHARACTER, SAVED_KEY, INBOX, ARRIVING, toEvent } from "./data";
import { State, type Settings } from "../src/core/state";
import { Hydration } from "../src/core/hydrationStore";
import { Sound } from "../src/core/sound";
import { ChristmasMusic } from "../src/island/christmasMusic";
import * as InboxPhoto from "../src/island/inboxPhoto";
import type { MessageEvent } from "../src/core/bridge";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// Fit the island's 760-wide window into whatever width the page gives it.
const STAGE_W = 760;
function fit() {
  if (window.innerWidth <= 0) return;
  const z = Math.min(1, window.innerWidth / STAGE_W);
  (document.documentElement.style as any).zoom = String(z);
}
fit();
window.addEventListener("resize", fit);

async function island(): Promise<any> {
  for (;;) {
    const it = (window as any).__notchyIsland;
    if (it && State.settings.language) return it;
    await sleep(40);
  }
}

// ── Messages ────────────────────────────────────────────────────────────────
const deliver = (m: MessageEvent) => emitLocal("message", m);

/** The inboxes as they stand when the island starts: unread, nothing opened. */
function fillInboxes() {
  for (const [sample, minutesAgo] of INBOX) {
    const ev = toEvent(sample, minutesAgo);
    State.ingestMessage(ev);
    if (ev.photo) InboxPhoto.load(ev.photo);
  }
  State.notify();
}

// The next sample to arrive, in turn — Mattermost, WhatsApp, Ato, … — carried
// across every island on the page, so the visitor never sees one twice in a row.
const ARRIVAL_KEY = "notchy-demo-arrival";
function nextArrival(): MessageEvent {
  let i = 0;
  try { i = Number(sessionStorage.getItem(ARRIVAL_KEY) ?? 0) || 0; } catch {}
  try { sessionStorage.setItem(ARRIVAL_KEY, String(i + 1)); } catch {}
  return toEvent(ARRIVING[i % ARRIVING.length]);
}

/** One notification, if the island is free to show it; false when it is busy. */
function notifyOnce(): boolean {
  // An open card is left alone. A permission nobody answered does not hold
  // the rest back: like the app, its card folds when its time is up and the
  // pill keeps the badge, so the next message may come in meanwhile.
  if (State.mode === "expanded") return false;
  deliver(nextArrival());
  return true;
}

/** Inside the download page, the page says when; on its own, the island keeps time. */
const EMBEDDED = window.parent !== window;

// ── An agent at work ────────────────────────────────────────────────────────
const CWD = "/Users/you/notchy";
const hook = (p: Record<string, unknown>) => emitLocal("hook", { session_id: "demo-session", cwd: CWD, ...p });

async function agentRun() {
  // The session the visitor watches is the pill in focus, as the one you are
  // working in is: a permission request then opens its card instead of only
  // badging the pill.
  State.setFocus("integration_claude");
  hook({ hook_event_name: "SessionStart" });
  await sleep(1500);
  hook({ hook_event_name: "UserPromptSubmit", prompt: S.prompt });
  await sleep(2600);
  hook({ hook_event_name: "PreToolUse", tool_name: "Read", tool_input: { file_path: `${CWD}/docs/download.html` } });
  await sleep(2600);
  hook({ hook_event_name: "PostToolUse", tool_name: "Read" });
  hook({ hook_event_name: "PreToolUse", tool_name: "Edit", tool_input: { file_path: `${CWD}/docs/download.css` } });
  await sleep(2800);
  hook({ hook_event_name: "PostToolUse", tool_name: "Edit" });
  // Permission: the card waits for a click, as it does on the Mac.
  const decision = await new Promise<string | null>((resolve) => {
    const off = onApproval((d) => { off(); resolve(d); });
    hook({
      hook_event_name: "PermissionRequest", tool_name: "Bash",
      tool_input: { command: "npm run build" }, request_id: `demo-${Date.now()}`,
    });
    // The relay gives up after 108 s and Claude Code asks in the terminal; a
    // visitor who looked away is let go sooner.
    setTimeout(() => { off(); resolve(null); }, 25_000);
  });
  if (decision === "allow") {
    hook({ hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: { command: "npm run build" } });
    await sleep(2400);
    hook({ hook_event_name: "PostToolUse", tool_name: "Bash" });
  }
  await sleep(1200);
  hook({ hook_event_name: "Stop", message: S.stop });
}

/** Waits until the island is folded and nobody is busy with it. */
async function whenQuiet() {
  for (;;) {
    if (State.mode !== "expanded") return;
    await sleep(800);
  }
}

async function hero() {
  // The greeting plays for about nine seconds before anything else may open.
  await sleep(10_500);
  void agentRun();
  if (EMBEDDED) return;
  // On its own: a notification now and then, never two in a row — one arrives,
  // its card folds after a few seconds, and a while later the next comes from
  // somewhere else.
  await sleep(24_000);
  for (let i = 1; ; i++) {
    await whenQuiet();
    notifyOnce();
    await sleep(22_000 + Math.random() * 10_000);
    if (i % 4 === 0) {
      await whenQuiet();
      void agentRun();
      await sleep(30_000);
    }
  }
}

// ── Sound, and the Christmas music ──────────────────────────────────────────
// A browser plays nothing before the visitor's first click, so the music the
// Mac starts with the greeting starts here with that click — and only then is
// YouTube loaded at all.
let activated = false;
function activate() {
  if (activated) return;
  activated = true;
  void Sound.resume();
  if (SCENE !== "hero") return;
  emitLocal("settings-changed", { ...State.settings, christmasMusic: true });
  ChristmasMusic.play();
}
window.addEventListener("pointerdown", activate, { once: true });
window.addEventListener("keydown", activate, { once: true });

// ── Settings from the page ──────────────────────────────────────────────────
// The Characters pane and the Settings window both speak through here.
window.addEventListener("message", (e) => {
  const data = e.data;
  if (!data) return;
  if (data.type === "notchy-activate") activate();
  if (data.type === "notchy-deliver") {
    // Busy — a card open, a permission waiting — and the page tries again soon.
    window.parent.postMessage({ type: "notchy-delivered", shown: notifyOnce() }, "*");
    return;
  }
  if (data.type === "notchy-agent") {
    if (SCENE === "hero" && State.mode !== "expanded" && !State.pendingApproval) void agentRun();
    return;
  }
  if (data.type !== "notchy-settings") return;
  let patch: Partial<Settings> = {};
  if (data.settings) {
    patch = { ...data.settings };
    // The box's own hold, and the music, stay the page's.
    delete patch.autoCloseInterval;
    delete patch.christmasMusic;
  }
  if (data.reset) {
    patch.pillCharacters = { ...MAC_CHARACTERS };
    patch.defaultCharacter = MAC_DEFAULT_CHARACTER;
  }
  if (data.slot && typeof data.character === "string") {
    if (data.slot === "default") patch.defaultCharacter = data.character;
    else patch.pillCharacters = { ...State.settings.pillCharacters, [data.slot]: data.character };
  }
  if (typeof data.hideCharacters === "boolean") patch.hideCharacters = data.hideCharacters;
  const next = { ...State.settings, ...patch };
  emitLocal("settings-changed", next);
  if (!data.settings) {
    try { sessionStorage.setItem(SAVED_KEY, JSON.stringify(next)); } catch {}
  }
});

// ── Scene ───────────────────────────────────────────────────────────────────
async function run() {
  const it = await island();
  if (SCENE !== "hero") startMedia();
  for (const source of ["mattermost", "ato", "whatsapp"] as const) {
    emitLocal("message-status", { source, state: "connected", detail: null });
  }
  Hydration.seedForPreview("mid");
  fillInboxes();
  // Outside the hero, Claude Code is busy in the background, as it is on the
  // Mac this was modelled on: Home shows the session rather than an idle pill.
  if (SCENE !== "hero") {
    hook({ hook_event_name: "SessionStart" });
    hook({ hook_event_name: "UserPromptSubmit", prompt: S.prompt });
    hook({ hook_event_name: "PreToolUse", tool_name: "Read", tool_input: { file_path: `${CWD}/docs/download.html` } });
  }

  switch (SCENE) {
    case "message": {
      await sleep(350);
      const source = new URLSearchParams(location.search).get("source");
      const pick = ARRIVING.find((s) => s.source === (source ?? "mattermost")) ?? ARRIVING[0];
      deliver(toEvent(pick));
      break;
    }
    case "water":
      await sleep(350);
      it.alert("hydration");
      break;
    case "hero":
      void hero();
      break;
    default:
      break;
  }
  window.parent?.postMessage({ type: "notchy-demo-ready", scene: SCENE }, "*");
}

void run();
