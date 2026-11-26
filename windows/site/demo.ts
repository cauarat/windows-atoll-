// The island on the download page: the app's own island (src/main.ts), fed by
// the stand-ins in site/shim instead of Rust, and played through a scene.
//
// Scenes, from `?scene=`:
//   hero     opens as Notchy does at launch — "Boa noite, Cauã!", the Christmas
//            music from the first click — then lives a day: Mattermost,
//            WhatsApp and Ato messages arrive.
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
import { startMedia } from "./shim/core";
import { SCENE, MAC_CHARACTERS, MAC_DEFAULT_CHARACTER, SAVED_KEY, INBOX, ARRIVING, toEvent } from "./data";
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
  // An open card is left alone.
  if (State.mode === "expanded") return false;
  deliver(nextArrival());
  return true;
}

/** Inside the download page, the page says when; on its own, the island keeps time. */
const EMBEDDED = window.parent !== window;

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
  if (EMBEDDED) return;
  // On its own: a notification now and then, never two in a row — one arrives,
  // its card folds after a few seconds, and a while later the next comes from
  // somewhere else.
  await sleep(24_000);
  for (;;) {
    await whenQuiet();
    notifyOnce();
    await sleep(22_000 + Math.random() * 10_000);
  }
}

// ── Sound, and the Christmas music ──────────────────────────────────────────
// The hero starts the Christmas music with its greeting, as Notchy does at
// launch (`ChristmasMusic.startWithGreeting`, the setting is on there). A
// browser lets a page make sound only once the visitor has clicked or typed
// on it — or has played sound on the site before — so when YouTube is refused
// the music plays muted from the same moment, and its sound comes on with the
// first click or key anywhere on the page. The page shows a button meanwhile.
const YT_ORIGIN = "https://www.youtube-nocookie.com";
let musicMuted = false;
let activated = false;

const ytFrame = () => document.querySelector<HTMLIFrameElement>("iframe.christmas-player");
function yt(func: string, args: unknown[] = []) {
  ytFrame()?.contentWindow?.postMessage(JSON.stringify({ event: "command", func, args }), YT_ORIGIN);
}
const tellPage = (state: "muted" | "audible" | "off") =>
  window.parent?.postMessage({ type: "notchy-music", state }, "*");

/** After the greeting has asked for the music: playing, or refused sound. */
async function watchChristmasStart() {
  for (let i = 0; i < 40 && !ytFrame(); i++) await sleep(100);
  if (!ytFrame()) return tellPage("off");
  // Give YouTube its moment to start with sound, as it does where allowed.
  for (let i = 0; i < 25 && !ChristmasMusic.playing; i++) await sleep(100);
  if (ChristmasMusic.playing && !musicMuted) return tellPage("audible");
  if (activated) return unmute();
  // Refused: the same music from the same second, without its sound.
  musicMuted = true;
  yt("mute");
  yt("playVideo");
  tellPage("muted");
  // Nothing at all (an extension blocking YouTube): no button for nothing.
  for (let i = 0; i < 40 && !ChristmasMusic.playing; i++) await sleep(100);
  if (!ChristmasMusic.playing) tellPage("off");
}

function unmute() {
  if (!ytFrame()) return;
  musicMuted = false;
  yt("unMute");
  yt("setVolume", [100]);
  yt("playVideo");
  tellPage("audible");
}

function activate() {
  if (activated) return;
  activated = true;
  void Sound.resume();
  if (SCENE === "hero" && musicMuted) unmute();
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
    // Busy — a card open — and the page tries again soon.
    window.parent.postMessage({ type: "notchy-delivered", shown: notifyOnce() }, "*");
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

// ── Room ────────────────────────────────────────────────────────────────────
// The page gives each island a frame of a set height, and some of its screens
// are taller — ChatGPT's page, the clipboard window. Say how much room the
// island needs right now, in its own pixels; the page grows the frame to fit.
let lastNeed = 0;
function reportRoom() {
  const el = document.getElementById("island");
  if (!el) return;
  const bottom = (parseFloat(el.style.top) || 0) + (parseFloat(el.style.height) || 0);
  // The bottom row of the ring hangs under the island.
  let need = Math.ceil(bottom + 72);
  const clip = document.querySelector<HTMLIFrameElement>("iframe[title='Clipboard']");
  if (clip) need = Math.max(need, 50 + 460 + 20);
  if (Math.abs(need - lastNeed) < 4) return;
  lastNeed = need;
  window.parent?.postMessage({ type: "notchy-height", need }, "*");
}
if (EMBEDDED) {
  const watch = () => {
    const el = document.getElementById("island");
    if (!el) return void setTimeout(watch, 100);
    let queued = false;
    new MutationObserver(() => {
      if (queued) return;
      queued = true;
      requestAnimationFrame(() => { queued = false; reportRoom(); });
    }).observe(document.body, { attributes: true, attributeFilter: ["style"], subtree: true, childList: true });
    reportRoom();
  };
  watch();
}

// ── Scene ───────────────────────────────────────────────────────────────────
async function run() {
  const it = await island();
  if (SCENE !== "hero") startMedia();
  for (const source of ["mattermost", "ato", "whatsapp"] as const) {
    emitLocal("message-status", { source, state: "connected", detail: null });
  }
  Hydration.seedForPreview("mid");
  fillInboxes();

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
      void watchChristmasStart();
      void hero();
      break;
    default:
      break;
  }
  window.parent?.postMessage({ type: "notchy-demo-ready", scene: SCENE }, "*");
}

void run();
