// Dev harness: ChatGPT and the site drawn in the island — the real `Island`,
// opened on "webchat" or "web" exactly as its tab or its ring disc opens them,
// with the page that Rust lays over the card faked here. Not in the bundle.
//
// Bridge calls do nothing outside Tauri, so the page-host commands are swapped
// for a stand-in for Rust: `pageShow` answers with the state the case asks for
// and, once that is "ready", puts a block where the native page would go —
// over the card, inside its stroke, rounded 16, on top of everything as the
// real child webview is. Reload makes it load again for a moment.
//
//   /dev/webchat-preview.html                               every case
//   /dev/webchat-preview.html?view=webchat&state=loading    one case, as the window
//
// One case takes: view=webchat|web, state=cold|loading|ready|blocked|failed,
// status=<HTTP status>, error=<WebView2's error name>, back=1 (the site can go
// back), pos=<an island position, top-centre by default>, lang=en|es|pt-BR,
// mochi=off, ring=site (the site's disc on the border). Each one writes what it
// measured into <pre id="measure">, which `chrome --headless --dump-dom` prints.
//
// `from=<view>&at=<ms>&motion=1` films the way in instead: the island settles
// on `from` first, then the view is opened as its tab opens it, and everything
// — the island's frames and the views' fades — stops `at` ms later, so a
// screenshot is that instant. `#measure` then has where both Mochis were.
// `still=1` pins both Mochis in the Settings picker's pose (facing you, eyes
// open) for the picture, and `header=0` leaves the tab row out, as the SwiftUI
// reference renders of these screens do.
//
//   /dev/webchat-preview.html?check=1
//
// runs the screens' behaviour against the real island instead — what is placed
// where and when, what holds it, what is turned away — and lists the results.
// Headless: `--virtual-time-budget=90000 --dump-dom`, then read #measure.

import "../src/style.css";
import { Island } from "../src/island/island";
import { Bridge, type PageLabel, type PageState } from "../src/core/bridge";
import { failureSentence, setPageState } from "../src/core/pageState";
import { State } from "../src/core/state";
import { setLanguage, type Language } from "../src/core/i18n";

const CASES: { label: string; q: string }[] = [
  { label: "ChatGPT, loading", q: "view=webchat&state=loading" },
  { label: "ChatGPT, ready — the block is where the page goes", q: "view=webchat&state=ready" },
  { label: "ChatGPT, blocked", q: "view=webchat&state=blocked&status=403" },
  { label: "ChatGPT, failed", q: "view=webchat&state=failed&error=HostNameNotResolved" },
  { label: "ChatGPT, characters off", q: "view=webchat&state=loading&mochi=off" },
  { label: "ChatGPT at the default corner, bottom right", q: "view=webchat&state=ready&pos=bottom-right" },
  { label: "The site, loading, with somewhere to go back to", q: "view=web&state=loading&back=1" },
  { label: "The site, ready", q: "view=web&state=ready" },
  { label: "The site, failed", q: "view=web&state=failed&error=HostNameNotResolved" },
  { label: "The site, with no address in Settings", q: "view=web&state=failed&error=InvalidUrl" },
  { label: "ChatGPT, blocked, in Portuguese", q: "view=webchat&state=blocked&status=503&lang=pt-BR" },
  { label: "ChatGPT on its way in from Home, 200 ms", q: "view=webchat&state=loading&from=overview&at=200&motion=1" },
];

const params = new URLSearchParams(location.search);
const view = params.get("view");

if (params.get("check") === "1") void check();
else if (view === "webchat" || view === "web") one(view);
else gallery();

/**
 * Headless Chrome under a virtual time budget, and a hidden preview pane, hand
 * out animation frames sparingly or not at all, and the island's spring only
 * moves when one arrives. Timers do run on virtual time, so frames come from a
 * timer here: the island grows, settles and gets its page as it would on
 * screen, whatever is rendering it.
 *
 * CSS transitions need real frames too, and without them a view stays at the
 * start of its fade — and a page is only placed over a card that has finished
 * arriving. They snap here; the island's own spring still runs. `?motion=1`
 * keeps them, for a browser that has frames to give.
 */
function headless() {
  window.requestAnimationFrame = (cb: FrameRequestCallback) =>
    window.setTimeout(() => { if (!frozen) cb(performance.now()); }, 16);
  if (params.get("motion") !== "1") {
    document.head.append(Object.assign(document.createElement("style"), {
      textContent: "*, *::before, *::after { transition: none !important; }",
    }));
  }
}

/** Set by `freeze`: no frame is handed out after it. */
let frozen = false;

/**
 * Everything stops where it is: the island's frames, and every fade still
 * running, each held `elapsed` ms into its run — they all started with the
 * view, one island frame after it was asked for. The document timeline need not
 * keep step with a virtual clock the way timers do, so the fades are put where
 * the time says by hand. One that has already ended is gone from the list: a
 * picture taken at 100 ms has no Home card fading out under it.
 */
function freeze(elapsed?: number) {
  frozen = true;
  for (const a of document.getAnimations()) {
    a.pause();
    if (elapsed != null) a.currentTime = Math.max(0, elapsed - 16);
  }
}

/**
 * Both Mochis facing you, eyes open, at rest — CharacterPreviewView's pose,
 * which is what the Mac reference is drawn in — and drawn once more like that.
 * A frame caught mid-blink or mid-glance is not a comparison.
 */
function pose(island: Island) {
  const p = island as unknown as Record<string, unknown> & {
    engine: Record<string, unknown>; rowEngine: Record<string, unknown>;
    drawBot(dt: number): void; drawRowBot(dt: number): void; rowMochiOn: boolean;
  };
  for (const e of [p.engine, p.rowEngine]) {
    // A blink half way through would set the lids again on the next update.
    (e.tweens as Map<unknown, unknown>).clear();
    (e.locks as Set<unknown>).clear();
    Object.assign(e, {
      yaw: 0, pitch: 0, roll: 0, tilt: 0, open: 1, sx: 1, sy: 1, ox: 0, oy: 0,
      tgYaw: 0, tgPitch: 0, tgTilt: 0, tgSx: 1, tgSy: 1, lookX: 0, lookY: 0,
      nextBlink: Number.POSITIVE_INFINITY, col: e.colT,
    });
  }
  if (!State.settings.hideCharacters) p.drawBot(0);
  if (p.rowMochiOn) p.drawRowBot(0);
}

function gallery() {
  document.documentElement.classList.add("gallery");
  const cases = document.createElement("div");
  cases.className = "cases";
  for (const c of CASES) {
    const box = document.createElement("div");
    box.className = "case";
    const label = document.createElement("div");
    label.className = "label";
    label.append(c.label, " ", Object.assign(document.createElement("b"), { textContent: `?${c.q}` }));
    const frame = document.createElement("iframe");
    frame.src = `${location.pathname}?${c.q}`;
    box.append(label, frame);
    cases.append(box);
  }
  document.body.append(cases);
}

function one(which: "webchat" | "web") {
  headless();
  const label: PageLabel = which === "webchat" ? "webchat" : "site";
  const lang = params.get("lang");
  if (lang) setLanguage(lang as Language);
  // `header=0`: the island's tab row left out, as the SwiftUI reference renders
  // leave it out — another surface, compared on its own (header-preview.html).
  if (params.get("header") === "0") {
    document.head.append(Object.assign(document.createElement("style"), {
      textContent: "#header { visibility: hidden !important; }",
    }));
  }

  State.settings = {
    ...State.settings,
    webChat: true,
    // Snow falls at random; without it two renders of a case are the same picture.
    islandSnow: false,
    position: params.get("pos") ?? "top-centre",
    hideCharacters: params.get("mochi") === "off",
    // `ring=site`: the site's own disc on the border, alone.
    ...(params.get("ring") === "site"
      ? { islandEdgeButtons: [{ action: "site", side: "left" as const }] } : {}),
  };

  const asked = (params.get("state") ?? "loading") as PageState["state"];
  const fake: PageState = {
    label,
    state: asked,
    status: params.has("status") ? Number(params.get("status")) : undefined,
    error: params.get("error") ?? undefined,
    url: label === "site" ? State.settings.siteUrl : "https://chatgpt.com/",
    title: label === "site" ? "The site's own title" : "ChatGPT",
    canGoBack: params.get("back") === "1",
  };

  // Rust, as far as the island can tell.
  let page: HTMLElement | null = null;
  let placed: { label: PageLabel; x: number; y: number; width: number; height: number } | null = null;
  const take = () => {
    page?.remove();
    page = null;
  };
  const put = () => {
    take();
    if (!placed || fake.state !== "ready") return;
    page = buildPage(placed.label, placed.x, placed.y, placed.width, placed.height);
    document.body.append(page);
  };
  const stub = Bridge as unknown as Record<string, unknown>;
  stub.pageShow = async (l: PageLabel, x: number, y: number, width: number, height: number) => {
    placed = { label: l, x, y, width, height };
    put();
    return { ...fake };
  };
  stub.pageHide = async () => { placed = null; take(); };
  stub.pageHideAll = async () => { placed = null; take(); };
  stub.pageReload = async (l: PageLabel) => {
    fake.state = "loading";
    take();
    setPageState({ ...fake, label: l });
    window.setTimeout(() => {
      fake.state = asked;
      setPageState({ ...fake, label: l });
      put();
    }, 1200);
  };
  stub.pageBack = async () => {};
  stub.pageOpenInBrowser = async () => {};

  const root = document.getElementById("root")!;
  const island = new Island(root);
  island.applySettings();
  State.loadIntegrationTasks();
  island.start();
  setPageState({ ...fake });

  // What landed where.
  const measure = () => {
    const isl = document.getElementById("island")!.getBoundingClientRect();
    const rel = (el: Element | null) => {
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return { x: +(r.left - isl.left).toFixed(2), y: +(r.top - isl.top).toFixed(2),
               w: +r.width.toFixed(2), h: +r.height.toFixed(2) };
    };
    const screen = document.querySelector(which === "webchat" ? ".view.webchat" : ".view.site");
    const bot = document.getElementById("bot-canvas")!;
    const springs = island as unknown as Record<"botCx" | "botCy" | "botSize", { value: number }>;
    const out = {
      island: { x: isl.left, y: isl.top, w: isl.width, h: isl.height },
      placed: placed && { ...placed, x: placed.x - isl.left, y: placed.y - isl.top },
      card: rel(screen?.querySelector(".page-card") ?? null),
      title: rel(screen?.querySelector(".wc-title") ?? null),
      mochiSeat: rel(screen?.querySelector(".wc-mochi") ?? null),
      rowMochi: rel(screen?.querySelector(".wc-mochi canvas") ?? null),
      buttons: [...(screen?.querySelectorAll(".screen-btn") ?? [])]
        .filter((b) => (b as HTMLElement).offsetParent != null).map(rel),
      mark: rel(screen?.querySelector(".site-mark") ?? null),
      spinner: rel(screen?.querySelector(".site-spinner") ?? null),
      failTitle: rel(screen?.querySelector(".page-fail-title") ?? null),
      failDetail: rel(screen?.querySelector(".page-fail-detail") ?? null),
      failText: screen?.querySelector(".page-fail-detail")?.textContent ?? null,
      retry: rel(screen?.querySelector(".page-retry") ?? null),
      dots: rel(screen?.querySelector(".page-dots") ?? null),
      bot: rel(bot),
      // The island's Mochi as his springs have him, island coordinates; and
      // the view his row is in, as far through its fade as it has got.
      mochi: {
        cx: +springs.botCx.value.toFixed(3), cy: +springs.botCy.value.toFixed(3),
        canvas: +springs.botSize.value.toFixed(3), opacity: bot.style.opacity,
      },
      view: screen && {
        opacity: getComputedStyle(screen).opacity, transform: getComputedStyle(screen).transform,
      },
      owner: { id: State.characterOwnerId, color: State.characterOwnerColor, state: State.effectiveState },
      header: { opacity: getComputedStyle(document.getElementById("header")!).opacity },
      chatTabLit: document.querySelector("#header .tabs .tab:nth-child(2)")?.classList.contains("on") ?? false,
      held: island.viewHoldsIslandOpen,
    };
    const pre = Object.assign(document.createElement("pre"), { id: "measure", textContent: JSON.stringify(out) });
    pre.style.display = "none";
    document.body.append(pre);
  };

  const from = params.get("from");
  const at = params.get("at");
  const still = params.get("still") === "1";
  const open = () => {
    // As the chat tab and the site's tab do.
    island.setView(which);
    if (at != null) {
      window.setTimeout(() => {
        freeze(Number(at));
        if (still) pose(island);
        measure();
      }, Number(at));
      return;
    }
    // Once everything has settled.
    window.setTimeout(() => {
      if (still) {
        freeze();
        pose(island);
      }
      measure();
    }, 3000);
  };
  if (from) {
    island.setView(from as Parameters<Island["setView"]>[0]);
    window.setTimeout(open, 1500);
  } else {
    open();
  }
}

/** The stand-in for the page itself. */
function buildPage(label: PageLabel, x: number, y: number, w: number, h: number): HTMLElement {
  const el = document.createElement("div");
  el.id = "fake-page";
  if (label === "site") el.classList.add("site");
  Object.assign(el.style, { left: `${x}px`, top: `${y}px`, width: `${w}px`, height: `${h}px` });
  const head = Object.assign(document.createElement("div"), {
    textContent: label === "site" ? "The site" : "What are you working on?",
  });
  head.style.fontSize = "22px";
  const bar = Object.assign(document.createElement("div"), {
    className: "bar", textContent: label === "site" ? "Search" : "Ask ChatGPT",
  });
  const note = Object.assign(document.createElement("div"), {
    className: "note", textContent: `the native page goes here — ${w}×${h} at ${x},${y}`,
  });
  el.append(head, bar, note);
  return el;
}

/** A promise to settle by hand, for a reply or an answer that is still on its way. */
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (err: unknown) => void;
  const promise = new Promise<T>((a, b) => { resolve = a; reject = b; });
  return { promise, resolve, reject };
}

/** How many of a canvas's pixels have anything drawn in them. */
function inked(canvas: HTMLCanvasElement | null): number {
  if (!canvas || canvas.width === 0 || canvas.height === 0) return 0;
  const data = canvas.getContext("2d")!.getImageData(0, 0, canvas.width, canvas.height).data;
  let n = 0;
  for (let i = 3; i < data.length; i += 4) if (data[i] > 0) n++;
  return n;
}

/**
 * `?check=1`: the screens' behaviour, run against the real island with the
 * page-host commands recorded instead of sent — what is placed where and when,
 * what holds the island, what gets through and what is turned away. The
 * results go into <pre id="measure"> and onto the page, one line a check.
 */
async function check() {
  headless();
  State.settings = {
    ...State.settings,
    webChat: true,
    islandSnow: false,
    position: "top-centre",
    // A site disc on the ring, so it can be pressed.
    islandEdgeButtons: [{ action: "site", side: "left" }, { action: "timer", side: "left" }],
  };
  const calls: string[] = [];
  const islandEl = () => document.getElementById("island")!;
  const size = () => `${parseFloat(islandEl().style.width)}x${parseFloat(islandEl().style.height)}`;
  const stub = Bridge as unknown as Record<string, unknown>;
  const answer: Record<PageLabel, PageState> = {
    webchat: { label: "webchat", state: "ready", canGoBack: false },
    site: { label: "site", state: "loading", canGoBack: false },
  };
  // The page calls and the keyboard's comings and goings, in the order they
  // went out — kept apart from `calls`, whose checks count page calls only.
  const order: string[] = [];
  stub.pageShow = async (l: PageLabel, x: number, y: number, w: number, h: number) => {
    calls.push(`show ${l} ${x},${y} ${w}x${h}`);
    order.push(`show ${l}`);
    return answer[l];
  };
  // `away` is the user leaving the screen; without it, the island moving.
  stub.pageHide = async (l: PageLabel, away = false) => {
    calls.push(`hide ${l}${away ? " away" : ""} while ${size()}`);
    order.push(`hide ${l}${away ? " away" : ""}`);
  };
  stub.pageHideAll = async () => {
    calls.push(`hideAll while ${size()}`);
    order.push("hideAll");
  };
  stub.focusWindow = async (focused: boolean) => { order.push(`focus ${focused}`); };

  const root = document.getElementById("root")!;
  const island = new Island(root);
  island.applySettings();
  State.loadIntegrationTasks();
  island.start();

  const results: string[] = [];
  const ok = (what: string, pass: boolean, got = "") =>
    results.push(`${pass ? "✓" : "✗"} ${what}${pass || !got ? "" : ` — got ${got}`}`);
  const sleep = (ms: number) => new Promise((r) => window.setTimeout(r, ms));
  const since = () => { const n = calls.length; return () => calls.slice(n); };
  const sinceOrder = () => { const n = order.length; return () => order.slice(n); };
  const click = (sel: string) => (document.querySelector(sel) as HTMLElement | null)?.click();
  const fsm = island.fsm as unknown as { heldOpen: boolean; state: string };
  // What the island keeps to itself, read and poked here only.
  const priv = island as unknown as {
    pages: { pending: boolean };
    botSize: { value: number; target: number };
    width: { springTo(v: number): void };
    engine: { particles: unknown[] };
    rowEngine: { state: string; eyeOverride: string | null; particles: unknown[] };
    views: Map<string, { el: HTMLElement }>;
    emote(name: string): void;
    swallow(path: string): void;
  };
  const botCanvas = () => document.getElementById("bot-canvas") as HTMLCanvasElement;
  const rowCanvas = () => document.querySelector<HTMLCanvasElement>(".view.webchat .wc-mochi canvas");
  const relToIsland = (el: Element | null) => {
    if (!el) return "none";
    const r = el.getBoundingClientRect();
    const i = islandEl().getBoundingClientRect();
    return `${Math.round(r.left - i.left)},${Math.round(r.top - i.top)} ${Math.round(r.width)}x${Math.round(r.height)}`;
  };
  const press = (input: HTMLInputElement | null, text: string) => {
    if (!input) return;
    input.value = text;
    input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
  };

  // Opened the way the chat tab opens it, from a closed island.
  let seen = since();
  island.setView("webchat");
  await sleep(150);
  ok("nothing is placed while the island is still growing",
     seen().length === 0 && parseFloat(islandEl().style.height) < 650, `${size()}: ${seen().join("; ")}`);
  await sleep(1350);
  ok("ChatGPT is placed inside the card's stroke once the island is still",
     seen().includes("show webchat 101,85 558x544"), seen().join("; "));
  ok("the screen holds the island open", island.viewHoldsIslandOpen && fsm.heldOpen);
  ok("the chat tab is lit", document.querySelector("#header .tab:nth-child(2)")?.classList.contains("on") === true);
  await sleep(6500);
  ok("no hold folds it — not the one the opening armed", State.mode === "expanded" && State.view === "webchat",
     `${State.mode}/${State.view}`);

  // ChatGPT's row Mochi is a Mochi of his own; the island's has stepped out.
  ok("ChatGPT's row has a Mochi of its own: 34 × 34 at x 24, y 50, and drawn",
     relToIsland(rowCanvas()) === "24,50 34x34" && inked(rowCanvas()) > 100,
     `${relToIsland(rowCanvas())}, ${inked(rowCanvas())} px inked`);
  ok("the island's own Mochi has stepped out of the view, as the Mac's does (diameter 0)",
     priv.botSize.target === 0 && Math.abs(priv.botSize.value) < 1 && botCanvas().style.opacity === "0",
     `target ${priv.botSize.target}, size ${priv.botSize.value.toFixed(2)}, opacity ${botCanvas().style.opacity}`);
  ok("the row's Mochi wears the island's state", priv.rowEngine.state === State.effectiveState,
     `${priv.rowEngine.state} vs ${State.effectiveState}`);
  priv.emote("happy");
  ok("an emote reaches the row's Mochi too, as .triggerEmote reaches every canvas",
     priv.rowEngine.eyeOverride === "happy", String(priv.rowEngine.eyeOverride));
  const labels = [...document.querySelectorAll<HTMLButtonElement>(".view.webchat .screen-btn")]
    .map((b) => `${b.getAttribute("aria-label")}${b.title ? `/${b.title}` : ""}`).join(", ");
  ok("its two buttons are named for a screen reader, with no tooltip", labels === "Reload, Close", labels);

  island.alert("approval");
  ok("an alert does not replace the screen", State.view === "webchat", State.view);

  setPageState({ label: "webchat", state: "failed", error: "COREWEBVIEW2_WEB_ERROR_STATUS_TIMEOUT", canGoBack: false });
  await sleep(100);
  const failTitle = () => document.querySelector(".view.webchat .page-fail-title")?.textContent;
  const failDetail = () => document.querySelector<HTMLElement>(".view.webchat .page-fail-detail");
  ok("a failure says so under the page", failTitle() === "Could not reach ChatGPT."
     && failDetail()?.textContent === "The request timed out.", `${failTitle()} / ${failDetail()?.textContent}`);
  setPageState({ label: "webchat", state: "failed", error: "RedirectFailed", canGoBack: false });
  await sleep(100);
  ok("a failed redirect is CFNetwork's sentence, not WebView2's name",
     failDetail()?.textContent === "too many HTTP redirects", failDetail()?.textContent ?? "");
  setPageState({ label: "webchat", state: "failed", error: "Unavailable", canGoBack: false });
  await sleep(100);
  ok("a page that could not be built says so in words",
     failDetail()?.textContent === "The page could not be started.", failDetail()?.textContent ?? "");
  setPageState({ label: "webchat", state: "failed", error: "SomethingNobodyNamed", canGoBack: false });
  await sleep(100);
  ok("a name with no sentence shows no line at all, never the name",
     failDetail()?.textContent === "" && failDetail()?.style.display === "none",
     `"${failDetail()?.textContent}" ${failDetail()?.style.display}`);
  setPageState({ label: "webchat", state: "ready", canGoBack: false });
  // Every name web.rs can put in a failed state: `page_model::web_error_name`
  // and the three it coins itself.
  const names = [
    "CertificateCommonNameIsIncorrect", "CertificateExpired", "ClientCertificateContainsErrors",
    "CertificateRevoked", "CertificateIsInvalid", "ServerUnreachable", "Timeout",
    "ErrorHttpInvalidServerResponse", "ConnectionAborted", "ConnectionReset", "Disconnected",
    "CannotConnect", "HostNameNotResolved", "OperationCanceled", "RedirectFailed", "UnexpectedError",
    "ValidAuthenticationCredentialsRequired", "ValidProxyAuthenticationRequired", "Unknown",
    "InvalidUrl", "Unavailable",
  ];
  const unsaid = names.filter((n) => failureSentence(n) == null);
  ok("every name web.rs can send has a sentence", unsaid.length === 0, unsaid.join(", "));

  // The island moving under the page is not the user leaving it.
  // Poked straight in, the island's loop has to be woken by hand: it sleeps
  // once nothing moves.
  const nudge = (w: number) => { priv.width.springTo(w); island.ensureRunning(); };
  seen = since();
  nudge(620);
  await sleep(100);
  ok("a hide while the island moves is not a leave", seen()[0]?.startsWith("hide webchat while") === true,
     seen().join("; "));
  await sleep(1400);
  ok("and the page comes back once the island is still", seen().some((c) => c.startsWith("show webchat ")),
     seen().join("; "));
  nudge(600);
  await sleep(1500);

  seen = since();
  click("#header .tab:nth-child(1)");
  ok("leaving for Home takes the page off first, before the island moves, as a leave",
     seen()[0] === "hide webchat away while 600x650", seen().join("; "));
  ok("Home does not hold the island", State.view === "overview" && !fsm.heldOpen);
  await sleep(1200);
  ok("and the island's Mochi comes back for it", priv.botSize.target > 50 && botCanvas().style.opacity === "1",
     `${priv.botSize.target} ${botCanvas().style.opacity}`);

  seen = since();
  click("#header .tab:nth-child(2)");
  await sleep(100);
  const midW = parseFloat(botCanvas().style.width);
  ok("on the way in the island's Mochi shrinks away in sight rather than vanishing",
     botCanvas().style.opacity === "1" && midW > 1 && midW < 96, `opacity ${botCanvas().style.opacity}, ${midW} px`);
  await sleep(1400);
  ok("the chat tab brings it back and places it again", seen().includes("show webchat 101,85 558x544"), seen().join("; "));
  seen = since();
  click("#header .tab:nth-child(2)");
  await sleep(300);
  ok("pressing the tab again keeps it, page and all", seen().length === 0 && State.view === "webchat", seen().join("; "));

  // A leave while the page is off for a settle is still a leave.
  seen = since();
  nudge(612);
  await sleep(60);
  click("#header .tab:nth-child(1)");
  ok("leaving while the page is off for a moment still says it is a leave",
     seen().length === 2 && !seen()[0].includes("away") && seen()[1].startsWith("hide webchat away"),
     seen().join("; "));
  await sleep(1200);
  click("#header .tab:nth-child(2)");
  await sleep(1500);

  // With the characters off the row closes up, and nothing draws into it.
  State.settings = { ...State.settings, hideCharacters: true };
  island.applySettings();
  await sleep(200);
  rowCanvas()?.getContext("2d")?.clearRect(0, 0, 999, 999);
  await sleep(300);
  const seat = document.querySelector<HTMLElement>(".view.webchat .wc-mochi");
  ok("with the characters off the seat closes, the title moves to x 24 and nothing is drawn",
     seat != null && getComputedStyle(seat).display === "none"
     && relToIsland(document.querySelector(".view.webchat .wc-title")).startsWith("24,")
     && inked(rowCanvas()) === 0,
     `${seat && getComputedStyle(seat).display} ${relToIsland(document.querySelector(".view.webchat .wc-title"))} ${inked(rowCanvas())}`);
  State.settings = { ...State.settings, hideCharacters: false };
  island.applySettings();
  await sleep(200);

  const disc = [...document.querySelectorAll<HTMLElement>(".ring-btn")].find((b) => !b.title.includes("Focus"));
  ok("the site's disc wears its mark and its host", disc?.title === "caus-macbook-pro.tail8e18f9.ts.net"
     && disc.querySelector("circle") != null, disc?.title);
  disc?.click();
  await sleep(300);
  ok("the site's disc does nothing over a screen", State.view === "webchat", State.view);

  seen = since();
  click("#header .tab:nth-child(5)");
  await sleep(1500);
  ok("the site's tab swaps one screen for the other, the one left as a leave",
     seen()[0] === "hide webchat away while 600x650" && seen().includes("show site 91,43 578x596"), seen().join("; "));
  ok("the tab row steps aside for the site's own",
     getComputedStyle(document.getElementById("header")!).opacity === "0"
     && document.getElementById("header")!.style.pointerEvents === "none");
  const siteLabels = [...document.querySelectorAll<HTMLButtonElement>(".view.site .screen-btn")]
    .map((b) => `${b.getAttribute("aria-label")}${b.title ? `/${b.title}` : ""}`).join(", ");
  ok("the site's four buttons are named for a screen reader, with no tooltip",
     siteLabels === "Back, Reload, Open in browser, Close", siteLabels);
  setPageState({ label: "site", state: "failed", error: "InvalidUrl", canGoBack: false });
  await sleep(100);
  const siteDetail = document.querySelector(".view.site .page-fail-detail")?.textContent;
  ok("an empty Site setting says what is wrong with it",
     siteDetail === "The site address in Settings is not a web address.", siteDetail ?? "");
  setPageState({ label: "site", state: "loading", canGoBack: false });

  State.pendingApproval = { requestId: "r1", sessionId: "s1", tool: "Bash", command: "ls" };
  State.isPinned = true;
  seen = since();
  click(".view.site .screen-actions .screen-btn:last-child");
  await sleep(300);
  ok("its X hands over to the approval that waited", State.view === "approval" && State.mode === "expanded"
     && seen()[0]?.startsWith("hideAll") && !seen().some((c) => c.startsWith("hide ")),
     `${State.mode}/${State.view}: ${seen().join("; ")}`);
  State.pendingApproval = null;
  State.isPinned = false;

  island.setView("webchat");
  await sleep(1500);
  seen = since();
  window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
  await sleep(600);
  ok("Escape puts the screen away and folds, with nothing said after the close",
     State.mode === "compact" && State.view === State.defaultView()
     && seen()[0] === "hideAll while 600x650" && !seen().some((c) => c.startsWith("hide ")),
     `${State.mode}/${State.view}: ${seen().join("; ")}`);

  seen = since();
  island.openForSmoke("site");
  await sleep(1500);
  ok("the smoke run opens the site from a closed island", State.mode === "expanded" && State.view === "web"
     && seen().includes("show site 91,43 578x596"), seen().join("; "));
  seen = since();
  window.dispatchEvent(new Event("resize"));
  await sleep(300);
  ok("a resize places it again", seen().includes("show site 91,43 578x596"), seen().join("; "));

  seen = since();
  island.dismiss();
  await sleep(600);
  ok("the island's X folds a screen too", State.mode === "compact" && seen()[0] === "hideAll while 600x650",
     `${State.mode}: ${seen().join("; ")}`);

  // ── Work started before a screen came up, finishing after ───────────────

  // The built-in chat, failing behind the site.
  State.settings = { ...State.settings, webChat: false };
  let chat = deferred<{ text: string }>();
  stub.chatSend = () => chat.promise;
  const promptField = () => priv.views.get("prompt")?.el.querySelector<HTMLInputElement>("input") ?? null;
  island.setView("prompt");
  await sleep(800);
  press(promptField(), "What is the capital of Peru?");
  await sleep(100);
  click("#header .tab:nth-child(5)");
  await sleep(1500);
  seen = since();
  chat.reject(new Error("The request timed out."));
  await sleep(300);
  ok("a chat that fails behind a screen leaves the screen up, held, its page placed",
     State.view === "web" && fsm.heldOpen && !priv.pages.pending && seen().length === 0,
     `${State.view} held=${fsm.heldOpen} pending=${priv.pages.pending}: ${seen().join("; ")}`);
  const said = State.chatHistory.at(-1);
  ok("and keeps why in the conversation, under the question",
     said?.role === "assistant" && said.content === "The request timed out.", JSON.stringify(said));

  // …and failing on screen: the note, through the island.
  click("#header .tab:nth-child(2)");
  await sleep(800);
  chat = deferred<{ text: string }>();
  press(promptField(), "Again?");
  await sleep(100);
  chat.reject(new Error("Overloaded."));
  await sleep(300);
  ok("a chat that fails on screen puts its note up", State.view === "note" && State.noteMessage === "Overloaded."
     && !fsm.heldOpen, `${State.view} "${State.noteMessage}" held=${fsm.heldOpen}`);
  State.settings = { ...State.settings, webChat: true };

  // A view written straight into State, round the island, is still caught.
  click("#header .tab:nth-child(2)");
  await sleep(1500);
  seen = since();
  // Through a wider type: written as `State.view = …`, TypeScript would take
  // every later read of it for "note".
  (State as { view: string }).view = "note";
  State.notify();
  await sleep(80);
  ok("a view written straight into State is caught before the island moves",
     seen()[0] === "hide webchat away while 600x650" && !fsm.heldOpen && !priv.pages.pending,
     `${seen().join("; ")} held=${fsm.heldOpen} pending=${priv.pages.pending}`);
  click("#header .tab:nth-child(1)");
  await sleep(1200);

  // A reply that lands after the user went to ChatGPT.
  const reply = deferred<void>();
  stub.sendReply = () => reply.promise;
  State.ingestMessage({
    id: "m1", source: "mattermost", kind: "directMessage", sender: "Ana", channel: null,
    conversationId: "c1", body: "Lunch?", timestampMs: Date.now(), link: null,
  });
  island.setView("message");
  await sleep(800);
  press(priv.views.get("message")?.el.querySelector<HTMLInputElement>("input") ?? null, "Sure");
  await sleep(50);
  click("#header .tab:nth-child(2)");
  await sleep(1500);
  seen = since();
  reply.resolve();
  await sleep(300);
  ok("a reply that finishes after ChatGPT was opened leaves ChatGPT up",
     State.view === "webchat" && fsm.heldOpen && seen().length === 0, `${State.view}: ${seen().join("; ")}`);
  ok("and the message it answered is read", State.messages.find((m) => m.id === "m1")?.read === true);
  click("#header .tab:nth-child(1)");
  await sleep(1200);

  // A drop whose copy fails after the user went to ChatGPT…
  let ingest = deferred<never>();
  stub.ingestFile = () => ingest.promise;
  priv.swallow("C:\\Users\\ana\\notes.txt");
  await sleep(200);
  click("#header .tab:nth-child(2)");
  await sleep(1500);
  seen = since();
  ingest.reject(new Error("Access is denied."));
  await sleep(2700);
  ok("a drop that fails behind ChatGPT leaves it up", State.view === "webchat" && seen().length === 0,
     `${State.view}: ${seen().join("; ")}`);
  click("#header .tab:nth-child(1)");
  await sleep(1200);

  // …and one that fails on screen, with ChatGPT opened inside its 2.4 s.
  ingest = deferred<never>();
  priv.swallow("C:\\Users\\ana\\notes.txt");
  await sleep(200);
  ingest.reject(new Error("Access is denied."));
  await sleep(100);
  ok("a drop that fails on screen says so", State.view === "note" && State.noteMessage === "Access is denied.",
     `${State.view} "${State.noteMessage}"`);
  click("#header .tab:nth-child(2)");
  await sleep(2800);
  ok("and its 2.4 s do not take ChatGPT away when they run out", State.view === "webchat", State.view);
  click("#header .tab:nth-child(1)");
  await sleep(1200);

  // ── ChatGPT's row Mochi lives as long as the Mac's ──────────────────────

  // On Home he is there, out of sight, and what reaches him plays out there
  // and then — hearts, and the sparks a "finished" sends half a second on.
  for (let i = 0; i < 5; i++) priv.emote("love");
  for (let i = 0; i < 5; i++) {
    State.stateOverride = "finished";
    State.notify();
    await sleep(120);
    State.stateOverride = null;
    State.notify();
    await sleep(120);
  }
  const reached = priv.rowEngine.particles.length;
  await sleep(3500);
  click("#header .tab:nth-child(2)");
  await sleep(200);
  ok("hearts and sparks from Home play out on the row's Mochi on Home, none saved up for ChatGPT",
     reached > 0 && priv.rowEngine.particles.length === 0 && priv.engine.particles.length === 0,
     `${reached} reached him on Home, ${priv.rowEngine.particles.length} left when ChatGPT opened`
     + ` (the island's: ${priv.engine.particles.length})`);

  // Folded, there is no row Mochi to hear anything, and opening makes a new one.
  island.dismiss();
  await sleep(800);
  const before = priv.rowEngine;
  const beforeCount = before.particles.length;
  for (let i = 0; i < 5; i++) priv.emote("proud");
  const afterFold = before.particles.length;
  island.setView("webchat");
  await sleep(100);
  ok("nothing said while the island is folded reaches him, and ChatGPT opens on a new row Mochi",
     State.mode === "expanded" && afterFold === beforeCount && priv.rowEngine !== before
     && priv.rowEngine.particles.length === 0,
     `folded: ${beforeCount} → ${afterFold}; new: ${priv.rowEngine !== before}, ${priv.rowEngine.particles.length} queued`);
  await sleep(1400);

  // ── The keyboard, on the way from a field to a screen ───────────────────

  // A tab pressed as Windows presses it, with the pointer on it: Chromium
  // focuses the button on the way down, so the field loses its caret a whole
  // press before the click does anything. `onHold` looks while it is down.
  // The pointer stays on the island afterwards, as a hand that clicked does;
  // `pointAway` takes it off.
  const pressTab = async (n: number, onHold?: () => void) => {
    const tab = document.querySelector<HTMLButtonElement>(`#header .tab:nth-child(${n})`)!;
    const r = tab.getBoundingClientRect();
    const at = { clientX: r.left + r.width / 2, clientY: r.top + r.height / 2, bubbles: true };
    tab.dispatchEvent(new MouseEvent("mousemove", at));
    tab.dispatchEvent(new PointerEvent("pointerdown", at));
    tab.focus();
    await sleep(120);
    onHold?.();
    tab.dispatchEvent(new PointerEvent("pointerup", at));
    tab.click();
  };
  const pointAway = () => document.body.dispatchEvent(new MouseEvent("mouseout", { bubbles: true }));
  const replyField = () => priv.views.get("message")?.el.querySelector<HTMLInputElement>("input") ?? null;
  const intoReply = async () => {
    island.setView("message");
    await sleep(800);
    replyField()?.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));
    replyField()?.focus();
    await sleep(50);
    return document.activeElement === replyField();
  };
  State.ingestMessage({
    id: "m2", source: "mattermost", kind: "directMessage", sender: "Ana", channel: null,
    conversationId: "c1", body: "Still on for lunch?", timestampMs: Date.now(), link: null,
  });

  let caret = await intoReply();
  let keys = sinceOrder();
  let held: string[] = [];
  await pressTab(2, () => { held = keys(); });
  await sleep(1500);
  ok("from the reply field to ChatGPT by its tab the keyboard stays: no hand-back before the page, or after",
     caret && State.view === "webchat" && keys().includes("show webchat") && !keys().includes("focus false"),
     `caret ${caret}, ${State.view}: ${keys().join("; ")}`);

  caret = await intoReply();
  keys = sinceOrder();
  await pressTab(1, () => { held = keys(); });
  await sleep(300);
  ok("from the reply field to another card it is handed back — once the press is over, not on the way down",
     caret && State.view === "overview" && !held.includes("focus false") && keys().includes("focus false"),
     `caret ${caret}, while held: ${held.join("; ")}; after: ${keys().join("; ")}`);
  pointAway();
  await sleep(400);

  // The chat to the site: the hand-back syncDom used to send. A click with no
  // press, so the chat's field still has the caret when the site comes up.
  State.settings = { ...State.settings, webChat: false };
  click("#header .tab:nth-child(2)");
  await sleep(800);
  caret = document.activeElement === promptField();
  keys = sinceOrder();
  click("#header .tab:nth-child(5)");
  await sleep(1500);
  ok("from the chat to the site the keyboard stays, and the chat's hidden field gives up its caret",
     caret && State.view === "web" && keys().includes("show site") && !keys().includes("focus false")
     && document.activeElement !== promptField(),
     `caret ${caret}, ${State.view}: ${keys().join("; ")}; focused ${document.activeElement?.tagName}`);
  keys = sinceOrder();
  window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
  await sleep(600);
  ok("closing the screen still hands it back", State.mode === "compact"
     && keys().includes("hideAll") && keys().includes("focus false"), `${State.mode}: ${keys().join("; ")}`);

  // And the chat to ChatGPT, the setting turned on while the chat was up.
  island.setView("prompt");
  await sleep(800);
  State.settings = { ...State.settings, webChat: true };
  keys = sinceOrder();
  click("#header .tab:nth-child(2)");
  await sleep(1500);
  ok("from the chat to ChatGPT the keyboard stays too",
     State.view === "webchat" && keys().includes("show webchat") && !keys().includes("focus false"),
     `${State.view}: ${keys().join("; ")}`);
  click("#header .tab:nth-child(1)");
  await sleep(1200);

  // ── The keyboard, once nobody is typing in the field ────────────────────

  // Alt+Tab, as Chromium reports it: the field is told it lost the caret, but
  // it stays the document's active element — the window went, not the field —
  // and `document.hasFocus()` is false. Nothing is typed into a field in a
  // window without the keyboard, so the island goes back to being a window a
  // click does not activate; kept, the next click on any of its controls took
  // the keyboard from the app the user went to, and put the caret back here.
  caret = await intoReply();
  keys = sinceOrder();
  Object.defineProperty(document, "hasFocus", { configurable: true, value: () => false });
  replyField()?.dispatchEvent(new FocusEvent("blur"));
  window.dispatchEvent(new FocusEvent("blur"));
  await sleep(100);
  const stayedActive = document.activeElement === replyField();
  delete (document as { hasFocus?: () => boolean }).hasFocus;
  ok("a reply field whose window loses the keyboard lets the island go back to not activating on a click",
     caret && stayedActive && keys().includes("focus false"),
     `caret ${caret}, still the active element ${stayedActive}: ${keys().join("; ")}`);
  replyField()?.blur();
  click("#header .tab:nth-child(1)");
  await sleep(1200);

  // A card that takes the chat's place — an approval, put up as hooks.ts puts
  // one — while something is typed in it. Left in the chat's hidden field,
  // the caret would take what is typed on the card: Enter sending the draft
  // nobody can see, Escape kept from the island by the field.
  State.settings = { ...State.settings, webChat: false };
  let asked = 0;
  stub.chatSend = () => { asked++; return new Promise<never>(() => {}); };
  click("#header .tab:nth-child(2)");
  await sleep(800);
  caret = document.activeElement === promptField();
  if (promptField()) promptField()!.value = "half a thought";
  keys = sinceOrder();
  State.pendingApproval = { requestId: "r2", sessionId: "s1", tool: "Bash", command: "rm -rf build" };
  State.isPinned = true;
  island.alert("approval");
  await sleep(100);
  const typedInto = document.activeElement;
  typedInto?.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
  await sleep(50);
  ok("a card that takes the chat's place takes the caret out of its field: Enter on the card sends nothing",
     caret && State.view === "approval" && typedInto !== promptField() && asked === 0
     && keys().includes("focus false"),
     `caret ${caret}, ${State.view}, typing into ${typedInto === promptField() ? "the chat's field" : typedInto?.tagName}, `
     + `${asked} sent: ${keys().join("; ")}`);
  State.pendingApproval = null;
  State.isPinned = false;
  island.dropPin();
  State.settings = { ...State.settings, webChat: true };
  click("#header .tab:nth-child(1)");
  await sleep(1200);

  // The reply card the same way. The approval keeps the pin it came with —
  // the field letting go is not the approval being answered — and the hold
  // that went with the field is not swapped for the 0.12 s leave: the card
  // that took its place stays, as the Mac's does once its reply card is gone.
  caret = await intoReply();
  keys = sinceOrder();
  State.pendingApproval = { requestId: "r3", sessionId: "s1", tool: "Bash", command: "ls" };
  State.isPinned = true;
  island.alert("approval");
  await sleep(100);
  const replyKeptCaret = document.activeElement === replyField();
  pointAway();
  await sleep(400);
  const pins = island.fsm as unknown as { pinned: boolean; heldOpen: boolean };
  ok("a card that takes the reply card's place takes its caret, and the approval keeps its pin through the pointer leaving",
     caret && !replyKeptCaret && State.mode === "expanded" && State.view === "approval"
     && State.isPinned && pins.pinned && !pins.heldOpen && keys().includes("focus false"),
     `caret ${caret}, kept ${replyKeptCaret}, ${State.mode}/${State.view}, pinned ${State.isPinned}/${pins.pinned}, `
     + `held ${pins.heldOpen}: ${keys().join("; ")}`);
  State.pendingApproval = null;
  State.isPinned = false;
  island.dropPin();
  island.setView("overview");
  await sleep(1200);

  // And a card that pins nothing — a focus timer running out — over the
  // reply card, with the pointer away: it is still there a moment later.
  caret = await intoReply();
  pointAway();
  await sleep(200);
  island.alert("timer");
  await sleep(600);
  ok("a card that takes the reply card's place with the pointer away is not folded away on the leave grace",
     caret && State.mode === "expanded" && State.view === "timer" && document.activeElement !== replyField(),
     `caret ${caret}, ${State.mode}/${State.view}, caret left in the reply ${document.activeElement === replyField()}`);
  island.setView("overview");
  await sleep(1200);

  // ── A reply answers the message it was written to ───────────────────────

  // The field is disabled while the reply goes, and Chromium takes the caret
  // out of a disabled field, so nothing holds the card and a message arriving
  // meanwhile takes it — on the Mac too. The reply is still Ana's.
  const inbound = (id: string, sender: string, body: string) => ({
    id, source: "mattermost" as const, kind: "directMessage" as const, sender, channel: null,
    conversationId: `c-${id}`, body, timestampMs: Date.now(), link: null,
  });
  const isRead = (id: string) => State.messages.find((m) => m.id === id)?.read;
  const going = deferred<void>();
  stub.sendReply = () => going.promise;
  State.ingestMessage(inbound("m3", "Ana", "Did the deploy go out?"));
  island.setView("message");
  await sleep(800);
  press(replyField(), "Yes, at noon");
  await sleep(50);
  // What messages.ts does with a message nobody is typing an answer to.
  State.ingestMessage(inbound("m4", "Bruno", "Can you look at my PR?"));
  island.setView("message");
  await sleep(100);
  going.resolve();
  await sleep(300);
  ok("a reply marks read the message it answered, not the one that took the card while it went",
     isRead("m3") === true && isRead("m4") === false && State.activeMessage?.id === "m4",
     `m3 read ${isRead("m3")}, m4 read ${isRead("m4")}, the card on ${State.activeMessage?.id}`);

  // From Home too: it shows the last thing its source said, so a message
  // arriving while the reply goes is a new message on Home.
  island.setView("overview");
  await sleep(1200);
  const homeField = () => priv.views.get("overview")?.el.querySelector<HTMLInputElement>("input.chat-input") ?? null;
  const fromHome = deferred<void>();
  stub.sendReply = () => fromHome.promise;
  State.ingestMessage(inbound("m5", "Ana", "Lunch at one?"));
  await sleep(100);
  const homeShowed = State.homeMessage?.id;
  press(homeField(), "Sounds good");
  await sleep(50);
  State.ingestMessage(inbound("m6", "Ana", "Or two?"));
  await sleep(100);
  fromHome.resolve();
  await sleep(300);
  ok("so does one sent from Home",
     homeShowed === "m5" && isRead("m5") === true && isRead("m6") === false && State.homeMessage?.id === "m6",
     `Home showed ${homeShowed}; m5 read ${isRead("m5")}, m6 read ${isRead("m6")}, Home on ${State.homeMessage?.id}`);
  island.setView("overview");
  await sleep(600);

  island.launch();
  await sleep(200);
  island.openForSmoke("webchat");
  await sleep(300);
  ok("the smoke run waits out the greeting", State.view === "greeting", State.view);
  await sleep(9000);
  ok("and then opens ChatGPT", State.mode === "expanded" && State.view === "webchat" && island.viewHoldsIslandOpen,
     `${State.mode}/${State.view}`);

  const pre = Object.assign(document.createElement("pre"), { id: "measure", textContent: results.join("\n") });
  pre.style.cssText = "position:fixed;left:8px;bottom:8px;margin:0;font:11px ui-monospace,monospace;color:#ddd;"
    + "background:rgba(0,0,0,.8);padding:6px 8px;z-index:2000;white-space:pre";
  document.body.append(pre);
}
