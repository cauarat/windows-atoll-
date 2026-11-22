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
//   /dev/webchat-preview.html?check=1
//
// runs the screens' behaviour against the real island instead — what is placed
// where and when, what holds it, what is turned away — and lists the results.
// Headless: `--virtual-time-budget=45000 --dump-dom`, then read #measure.

import "../src/style.css";
import { Island } from "../src/island/island";
import { Bridge, type PageLabel, type PageState } from "../src/core/bridge";
import { setPageState } from "../src/core/pageState";
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
  { label: "ChatGPT, blocked, in Portuguese", q: "view=webchat&state=blocked&status=503&lang=pt-BR" },
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
    window.setTimeout(() => cb(performance.now()), 16);
  if (params.get("motion") !== "1") {
    document.head.append(Object.assign(document.createElement("style"), {
      textContent: "*, *::before, *::after { transition: none !important; }",
    }));
  }
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
  // As the chat tab and the site's tab do.
  island.setView(which);

  // What landed where, once everything has settled.
  window.setTimeout(() => {
    const isl = document.getElementById("island")!.getBoundingClientRect();
    const rel = (el: Element | null) => {
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return { x: +(r.left - isl.left).toFixed(2), y: +(r.top - isl.top).toFixed(2),
               w: +r.width.toFixed(2), h: +r.height.toFixed(2) };
    };
    const screen = document.querySelector(which === "webchat" ? ".view.webchat" : ".view.site");
    const out = {
      island: { x: isl.left, y: isl.top, w: isl.width, h: isl.height },
      placed: placed && { ...placed, x: placed.x - isl.left, y: placed.y - isl.top },
      card: rel(screen?.querySelector(".page-card") ?? null),
      title: rel(screen?.querySelector(".wc-title") ?? null),
      mochiSeat: rel(screen?.querySelector(".wc-mochi") ?? null),
      buttons: [...(screen?.querySelectorAll(".screen-btn") ?? [])]
        .filter((b) => (b as HTMLElement).offsetParent != null).map(rel),
      mark: rel(screen?.querySelector(".site-mark") ?? null),
      spinner: rel(screen?.querySelector(".site-spinner") ?? null),
      failTitle: rel(screen?.querySelector(".page-fail-title") ?? null),
      failDetail: rel(screen?.querySelector(".page-fail-detail") ?? null),
      retry: rel(screen?.querySelector(".page-retry") ?? null),
      dots: rel(screen?.querySelector(".page-dots") ?? null),
      bot: rel(document.getElementById("bot-canvas")),
      header: { opacity: getComputedStyle(document.getElementById("header")!).opacity },
      chatTabLit: document.querySelector("#header .tabs .tab:nth-child(2)")?.classList.contains("on") ?? false,
      held: island.viewHoldsIslandOpen,
    };
    const pre = Object.assign(document.createElement("pre"), { id: "measure", textContent: JSON.stringify(out) });
    pre.style.display = "none";
    document.body.append(pre);
  }, 3000);
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
  stub.pageShow = async (l: PageLabel, x: number, y: number, w: number, h: number) => {
    calls.push(`show ${l} ${x},${y} ${w}x${h}`);
    return answer[l];
  };
  stub.pageHide = async (l: PageLabel) => { calls.push(`hide ${l} while ${size()}`); };
  stub.pageHideAll = async () => { calls.push(`hideAll while ${size()}`); };

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
  const click = (sel: string) => (document.querySelector(sel) as HTMLElement | null)?.click();
  const fsm = island.fsm as unknown as { heldOpen: boolean; state: string };

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

  island.alert("approval");
  ok("an alert does not replace the screen", State.view === "webchat", State.view);

  setPageState({ label: "webchat", state: "failed", error: "COREWEBVIEW2_WEB_ERROR_STATUS_TIMEOUT", canGoBack: false });
  await sleep(100);
  const failTitle = document.querySelector(".view.webchat .page-fail-title")?.textContent;
  const failDetail = document.querySelector(".view.webchat .page-fail-detail")?.textContent;
  ok("a failure says so under the page", failTitle === "Could not reach ChatGPT." && failDetail === "The request timed out.",
     `${failTitle} / ${failDetail}`);
  setPageState({ label: "webchat", state: "ready", canGoBack: false });

  seen = since();
  click("#header .tab:nth-child(1)");
  ok("leaving for Home takes the page off first, before the island moves",
     seen()[0] === "hide webchat while 600x650", seen().join("; "));
  ok("Home does not hold the island", State.view === "overview" && !fsm.heldOpen);
  await sleep(1200);

  seen = since();
  click("#header .tab:nth-child(2)");
  await sleep(1500);
  ok("the chat tab brings it back and places it again", seen().includes("show webchat 101,85 558x544"), seen().join("; "));
  seen = since();
  click("#header .tab:nth-child(2)");
  await sleep(300);
  ok("pressing the tab again keeps it, page and all", seen().length === 0 && State.view === "webchat", seen().join("; "));

  const disc = [...document.querySelectorAll<HTMLElement>(".ring-btn")].find((b) => !b.title.includes("Focus"));
  ok("the site's disc wears its mark and its host", disc?.title === "caus-macbook-pro.tail8e18f9.ts.net"
     && disc.querySelector("circle") != null, disc?.title);
  disc?.click();
  await sleep(300);
  ok("the site's disc does nothing over a screen", State.view === "webchat", State.view);

  seen = since();
  click("#header .tab:nth-child(5)");
  await sleep(1500);
  ok("the site's tab swaps one screen for the other",
     seen()[0] === "hide webchat while 600x650" && seen().includes("show site 91,43 578x596"), seen().join("; "));
  ok("the tab row steps aside for the site's own",
     getComputedStyle(document.getElementById("header")!).opacity === "0"
     && document.getElementById("header")!.style.pointerEvents === "none");

  State.pendingApproval = { requestId: "r1", sessionId: "s1", tool: "Bash", command: "ls" };
  State.isPinned = true;
  seen = since();
  click(".view.site .screen-actions .screen-btn:last-child");
  await sleep(300);
  ok("its X hands over to the approval that waited", State.view === "approval" && State.mode === "expanded"
     && seen()[0]?.startsWith("hideAll"), `${State.mode}/${State.view}: ${seen().join("; ")}`);
  State.pendingApproval = null;
  State.isPinned = false;

  island.setView("webchat");
  await sleep(1500);
  seen = since();
  window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
  await sleep(600);
  ok("Escape puts the screen away and folds", State.mode === "compact" && State.view === State.defaultView()
     && seen()[0] === "hideAll while 600x650", `${State.mode}/${State.view}: ${seen().join("; ")}`);

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
