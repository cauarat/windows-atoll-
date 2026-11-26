// The pages the island lays over its cards — ChatGPT behind the Chat tab, the
// site, WhatsApp Web — which the app draws with a native webview of its own.
//
// A web page cannot do that for ChatGPT: chatgpt.com allows itself to be framed
// only by itself (`frame-ancestors 'self'`). So where the app would put the page,
// at the very spot the island asks for, the demo puts a card in the island's
// own style that says so and opens ChatGPT in a tab of its own.

import { LANG } from "../data";
import type { PageLabel, PageState } from "../../src/core/bridge";

const URLS: Record<string, string> = {
  webchat: "https://chatgpt.com/",
};

const TEXT = {
  "pt-BR": {
    lead: "No Notchy, o ChatGPT abre aqui mesmo, dentro do notch, com a sua conta.",
    why: "Num site isso não dá: o ChatGPT não deixa ser aberto dentro de outra página. Aqui ele abre numa aba nova.",
    open: "Abrir o ChatGPT",
  },
  en: {
    lead: "In Notchy, ChatGPT opens right here, inside the notch, signed in as you.",
    why: "A website can’t do that: ChatGPT won’t open inside another page. Here it opens in a new tab.",
    open: "Open ChatGPT",
  },
  es: {
    lead: "En Notchy, ChatGPT se abre aquí mismo, dentro del notch, con tu cuenta.",
    why: "Una web no puede hacerlo: ChatGPT no se deja abrir dentro de otra página. Aquí se abre en una pestaña nueva.",
    open: "Abrir ChatGPT",
  },
}[LANG];

const shown = new Map<string, HTMLElement>();

function card(label: string): HTMLElement {
  const el = document.createElement("div");
  el.className = "demo-page";
  Object.assign(el.style, {
    position: "fixed", zIndex: "40", boxSizing: "border-box", display: "flex",
    flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "10px",
    padding: "14px 22px", textAlign: "center", borderRadius: "14px",
    background: "radial-gradient(120% 140% at 50% 120%, rgba(16,163,127,0.28), rgba(0,0,0,0) 60%), #0e0f11",
    border: "1px solid rgba(255,255,255,0.06)", color: "#f1f2f4",
    font: "13px/1.45 -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif",
  });
  const lead = document.createElement("p");
  lead.textContent = TEXT.lead;
  Object.assign(lead.style, { margin: "0", fontSize: "14px", fontWeight: "600", maxWidth: "460px" });
  const why = document.createElement("p");
  why.textContent = TEXT.why;
  Object.assign(why.style, { margin: "0", color: "#9398a1", maxWidth: "460px" });
  const open = document.createElement("button");
  open.type = "button";
  open.textContent = TEXT.open;
  Object.assign(open.style, {
    marginTop: "4px", height: "34px", padding: "0 18px", border: "0", borderRadius: "17px",
    background: "#f5f6f8", color: "#000", font: "600 13px -apple-system, BlinkMacSystemFont, system-ui, sans-serif",
    cursor: "pointer",
  });
  open.addEventListener("click", () => window.open(URLS[label] ?? URLS.webchat, "_blank", "noopener"));
  el.append(lead, why, open);
  document.body.append(el);
  return el;
}

export function pageShow(label: PageLabel, x: number, y: number, width: number, height: number): PageState {
  let el = shown.get(label);
  if (!el) shown.set(label, (el = card(label)));
  Object.assign(el.style, { left: `${x}px`, top: `${y}px`, width: `${width}px`, height: `${height}px`, display: "flex" });
  return { label, state: "ready", canGoBack: false, url: URLS[label] };
}

export function pageHide(label?: PageLabel) {
  for (const [key, el] of shown) {
    if (label && key !== label) continue;
    el.style.display = "none";
  }
}

export function pageOpenInBrowser(label: PageLabel) {
  window.open(URLS[label] ?? URLS.webchat, "_blank", "noopener");
}
