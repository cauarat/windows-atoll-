// ChatGPT and the site, drawn in the island — ports of `WebChatIslandView`
// (WebChatHostView.swift) and `NotchSiteView` (NotchSite.swift).
//
// What is here is everything the Mac draws around and under its web view: the
// header row, the card, the dots while the page loads, the copy when it
// cannot. The page itself is a native webview that Rust lays over the card once
// the island is still (island/pageHost.ts), and nothing can be drawn over it
// there — so all of this sits beside it or beneath it, never on top.

import { h } from "./dom";
import { siteIcon } from "./logos";
import { Bridge, type PageState } from "../core/bridge";
import { failureSentence, pageState, siteHost } from "../core/pageState";
import { State } from "../core/state";
import { t } from "../core/i18n";
import type { ViewActions, ViewHost } from "./views";

const NS = "http://www.w3.org/2000/svg";

/**
 * A header glyph, drawn in the 18 × 18 pt frame the Mac gives each button,
 * so every number below is a position in that frame.
 *
 * Stand-ins for the SF Symbols the Mac names — drawn here, not copied — with
 * the ink box, the line weight and the centre each symbol has at the size and
 * weight the Mac asks for, measured off `Image(systemName:)` rendered in that
 * frame at 8×.
 */
interface Glyph {
  d: string;
  /** Line weight, pt. */
  w: number;
}

const GLYPHS = {
  // ChatGPT's row: 11 pt, medium.
  /** arrow.clockwise — ink 4.25…13.88 × 3.12…14.88. */
  reloadSmall: {
    d: "M13.29 9.64A4.265 4.265 0 1 1 9.04 5.715L11 5.85M8.8 3.67 11 5.85 8.8 8.03",
    w: 1.07,
  },
  /** xmark — ink 4.62…13.38 square. */
  closeSmall: { d: "M5.23 5.23 12.77 12.77M12.77 5.23 5.23 12.77", w: 1.21 },
  // The site's row: 13 pt, regular — `IslandHeaderIconButton`.
  /** chevron.left — ink 5.00…11.25 × 3.25…14.25. */
  back: { d: "M10.68 3.83 5.58 8.75 10.68 13.67", w: 1.15 },
  /** arrow.clockwise — ink 3.25…14.50 × 2.00…15.62. */
  reload: {
    d: "M13.95 9.95A5.075 5.075 0 1 1 8.875 4.925L11.2 5.08M8.6 2.51 11.2 5.08 8.6 7.65",
    w: 1.02,
  },
  /** arrow.up.right — ink 4.25…13.75 × 4.25…13.62. */
  open: { d: "M4.8 13.08 13.2 4.81M6.55 4.81H13.2V11.08", w: 1.1 },
  /** xmark — ink 3.75…13.88 square. */
  close: { d: "M4.32 4.32 13.31 13.31M13.31 4.32 4.32 13.31", w: 1.14 },
} satisfies Record<string, Glyph>;

function glyph(g: Glyph): SVGSVGElement {
  const el = document.createElementNS(NS, "svg");
  el.setAttribute("viewBox", "0 0 18 18");
  el.setAttribute("width", "18");
  el.setAttribute("height", "18");
  el.setAttribute("aria-hidden", "true");
  const p = document.createElementNS(NS, "path");
  p.setAttribute("d", g.d);
  p.setAttribute("fill", "none");
  p.setAttribute("stroke", "currentColor");
  p.setAttribute("stroke-width", String(g.w));
  p.setAttribute("stroke-linecap", "round");
  p.setAttribute("stroke-linejoin", "round");
  el.append(p);
  return el;
}

/** One icon in a screen's header row: 18 × 18, its target grown 5 all round. */
function iconButton(g: Glyph, onClick: () => void): HTMLButtonElement {
  return h("button", { class: "screen-btn", onclick: onClick }, glyph(g));
}

/**
 * `ProgressView().controlSize(.small).scaleEffect(0.6)` in its 12 × 12 frame:
 * eight spokes, the lit one going round. The spokes and their fall-off are the
 * Mac's, read off the control drawn on black.
 */
function spinner(): HTMLElement {
  const el = document.createElementNS(NS, "svg");
  el.setAttribute("viewBox", "0 0 12 12");
  el.setAttribute("width", "12");
  el.setAttribute("height", "12");
  el.setAttribute("aria-hidden", "true");
  for (let i = 0; i < 8; i++) {
    const a = (i * Math.PI) / 4;
    const line = document.createElementNS(NS, "line");
    const at = (r: number) => [6 + r * Math.sin(a), 6 - r * Math.cos(a)].map((v) => v.toFixed(3));
    const [x1, y1] = at(2.6);
    const [x2, y2] = at(4.4);
    line.setAttribute("x1", x1);
    line.setAttribute("y1", y1);
    line.setAttribute("x2", x2);
    line.setAttribute("y2", y2);
    el.append(line);
  }
  return h("div", { class: "site-spinner" }, el);
}

/** `TypingDotsView`, centred on the bare card while the page loads. */
function dots(): HTMLElement {
  return h("div", { class: "typing page-dots" }, h("i"), h("i"), h("i"));
}

/**
 * The failure block both screens share: a title, a line of detail and a "Try
 * again" capsule, centred on the card under where the page would be.
 */
function failure(retry: () => void) {
  const title = h("div", { class: "page-fail-title" });
  const detail = h("div", { class: "page-fail-detail" });
  const el = h("div", { class: "page-fail" },
    title, detail, h("button", { class: "page-retry", text: t("Try again"), onclick: retry }));
  el.style.display = "none";
  return {
    el,
    show(head: string, line: string) {
      title.textContent = head;
      detail.textContent = line;
      detail.style.display = line ? "" : "none";
      el.style.display = "";
    },
    hide() {
      el.style.display = "none";
    },
  };
}

/** What the Mac would say for this failure, in the user's language — or the name as it came. */
function failureDetail(s: PageState): string {
  const sentence = failureSentence(s.error);
  return sentence ? t(sentence) : s.error ?? "";
}

const loading = (s: PageState) => s.state === "cold" || s.state === "loading";

// ── ChatGPT ───────────────────────────────────────────────────────────────────

/**
 * Under the island's own tabs: 8 pt, then a 34 pt row — Mochi, "ChatGPT", and
 * reload and close on the right — then the page's card.
 *
 * Mochi is the island's own, drawn over the seat this row leaves for him; the
 * view's layout puts him there (`VIEW_LAYOUTS.webchat`). With the characters
 * off the seat closes and the title moves to the edge, as on the Mac.
 */
export function buildWebChat(actions: ViewActions): ViewHost {
  const waiting = dots();
  const fail = failure(() => void Bridge.pageReload("webchat"));
  const card = h("div", { class: "page-card" }, h("div", { class: "page-under" }, waiting, fail.el));
  const head = h("div", { class: "screen-head wc-head" },
    h("div", { class: "wc-mochi" }),
    // A name, so not in the catalogue; the Mac's Text has nothing to look up either.
    h("div", { class: "wc-title", text: "ChatGPT" }),
    h("div", { class: "screen-actions" },
      iconButton(GLYPHS.reloadSmall, () => void Bridge.pageReload("webchat")),
      // The page holds the island open, so there has to be a way out that is
      // not a keystroke: the same mark, in the same place, as the site's.
      iconButton(GLYPHS.closeSmall, () => actions.closeScreen()),
    ),
  );
  return {
    el: h("div", { class: "view screen webchat" }, head, card),
    sync() {
      const s = pageState("webchat");
      waiting.style.display = loading(s) ? "" : "none";
      if (s.state === "blocked") {
        fail.show(t("ChatGPT is refusing the built-in browser (HTTP %@).", String(s.status ?? "")),
                  t("Open it in your browser instead, or try again."));
      } else if (s.state === "failed") {
        fail.show(t("Could not reach ChatGPT."), failureDetail(s));
      } else {
        fail.hide();
      }
    },
  };
}

// ── The site ──────────────────────────────────────────────────────────────────

/**
 * Over the whole island, its tabs hidden: a row of its own — back while there
 * is somewhere to go back to, the site's mark with where you are as its
 * tooltip, a spinner while it loads; reload, open in the browser and close on
 * the right — then the page's card.
 */
export function buildSite(actions: ViewActions): ViewHost {
  const back = iconButton(GLYPHS.back, () => void Bridge.pageBack("site"));
  // The mark alone. The page states its own name directly below, so a title
  // here would only say it twice.
  const mark = h("div", { class: "site-mark" }, siteIcon(16));
  const busy = spinner();
  const fail = failure(() => void Bridge.pageReload("site"));
  const head = h("div", { class: "screen-head site-head" },
    h("div", { class: "site-lead" }, back, mark, busy),
    h("div", { class: "screen-actions" },
      iconButton(GLYPHS.reload, () => void Bridge.pageReload("site")),
      iconButton(GLYPHS.open, () => void Bridge.pageOpenInBrowser("site")),
      iconButton(GLYPHS.close, () => actions.closeScreen()),
    ),
  );
  const card = h("div", { class: "page-card" }, h("div", { class: "page-under" }, fail.el));
  return {
    el: h("div", { class: "view screen site" }, head, card),
    sync() {
      const s = pageState("site");
      const host = siteHost(State.settings.siteUrl);
      back.style.display = s.canGoBack ? "" : "none";
      busy.style.display = loading(s) ? "" : "none";
      mark.title = s.title || host;
      if (s.state === "failed") fail.show(host, failureDetail(s));
      else if (s.state === "blocked") fail.show(host, `HTTP ${s.status ?? ""}`.trim());
      else fail.hide();
    },
  };
}
