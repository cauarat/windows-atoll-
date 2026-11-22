// Dev harness: the island's header — the row of tabs and buttons over every
// expanded view — in the states it can be in, each row the real `buildHeader`
// on the real stylesheet. Put beside the Mac's IslandHeader to check the
// glyphs icon for icon.
//
// `npx vite`, then /dev/header-preview.html. For measuring rather than
// looking:
//   ?bare           one row at the top-left, on black, no labels
//   &only=gear      every other glyph hidden and every plate off, so a
//                   screenshot's ink is that glyph alone
//   &view=hydration which tab is lit (default overview)
//   &hover=chat     draws that button as hovered
//   &sound=0  &agenda=0  &lang=pt-BR

import "../src/style.css";
import { buildHeader, type ViewActions } from "../src/views/views";
import { State } from "../src/core/state";
import type { IslandViewName } from "../src/core/layout";
import { setLanguage, type Language } from "../src/core/i18n";

const noop = () => {};
const actions: ViewActions = {
  setView: noop, collapse: noop, setFocus: noop, openTerminal: noop,
  openTarget: noop, openUrl: noop, decide: noop, toggleSound: noop,
  setVolume: noop, setAutoClose: noop, openSettingsWindow: noop,
  setPinned: noop, focusField: noop, blip: noop,
};

const q = new URLSearchParams(location.search);
if (q.get("lang")) setLanguage(q.get("lang") as Language);

// The buttons, by what they are rather than where they sit, so a reordered
// row still finds them. Titles are the English catalogue keys.
const IDS: Record<string, string> = {
  Overview: "home", Ask: "chat", Clipboard: "clip", Integrations: "grid", Site: "globe",
  Agenda: "calendar", Hydration: "drop", Timer: "timer",
  Settings: "gear", Mute: "speaker", Close: "x",
};

// Hover cannot be held in a screenshot, so every `:hover` rule the header
// has is copied once onto a class the page can set.
for (const sheet of Array.from(document.styleSheets)) {
  let rules: CSSRuleList;
  try { rules = sheet.cssRules; } catch { continue; }
  for (const rule of Array.from(rules)) {
    if (!(rule instanceof CSSStyleRule) || !rule.selectorText.includes(":hover")) continue;
    if (!/\.tab|header-actions/.test(rule.selectorText)) continue;
    sheet.insertRule(rule.cssText.replace(/:hover/g, ".dev-hover"), sheet.cssRules.length);
  }
}

interface Row {
  label: string;
  view?: IslandViewName;
  sound?: boolean;
  agenda?: boolean;
  hover?: string[];
  only?: string;
}

const ROWS: Row[] = [
  { label: "Home lit, the way the Mac's capture shows it" },
  { label: "Hydration lit", view: "hydration" },
  { label: "the chat tab and the X hovered", hover: ["chat", "x"] },
  { label: "the clipboard and the gear hovered — the gear has no hover on the Mac", hover: ["gear", "clip"] },
  { label: "muted, Agenda off", sound: false, agenda: false },
  { label: "Timer lit, Integrations hovered", view: "timer", hover: ["grid"] },
];

function stage(row: Row): HTMLElement {
  State.view = row.view ?? "overview";
  State.settings = {
    ...State.settings,
    soundEnabled: row.sound ?? true,
    agendaEnabled: row.agenda ?? true,
    webChat: false,
  };
  const header = buildHeader(actions);
  header.sync();
  for (const b of Array.from(header.el.querySelectorAll("button"))) {
    const id = IDS[b.getAttribute("title") ?? ""] ?? "";
    b.dataset.glyph = id;
    if (row.hover?.includes(id)) b.classList.add("dev-hover");
    if (row.only && id !== row.only) {
      (b.firstElementChild as HTMLElement | null)?.style.setProperty("visibility", "hidden");
    }
    if (row.only) {
      b.classList.remove("on", "dev-hover");
      b.style.background = "transparent";
    }
  }
  // The island's own content box: 8 px down, 10 in, and the header pulled
  // back out to the full width, as `#content` and `#header` do it.
  const content = document.createElement("div");
  content.id = "content";
  content.append(header.el);
  const s = document.createElement("div");
  s.className = "stage";
  s.append(content);
  return s;
}

const rows = document.getElementById("rows")!;
if (q.has("bare")) {
  document.body.classList.add("bare");
  const s = stage({
    label: "",
    view: (q.get("view") as IslandViewName | null) ?? "overview",
    sound: q.get("sound") !== "0",
    agenda: q.get("agenda") !== "0",
    hover: q.get("hover")?.split(","),
    only: q.get("only") ?? undefined,
  });
  rows.append(s);
  // &rects: every button's frame in header points, for `--dump-dom`.
  if (q.has("rects")) {
    const top = s.getBoundingClientRect().top + 8;
    const out = Array.from(s.querySelectorAll("button")).map((b) => {
      const r = b.getBoundingClientRect(), g = b.querySelector("svg")!.getBoundingClientRect();
      return `${(b as HTMLElement).dataset.glyph} button x ${r.left}–${r.right} y ${r.top - top}–${r.bottom - top}`
        + ` · svg x ${g.left}–${g.right} y ${g.top - top}–${g.bottom - top}`;
    });
    rows.append(Object.assign(document.createElement("pre"), { id: "rects", textContent: out.join("\n") }));
  }
} else {
  for (const row of ROWS) {
    const label = document.createElement("div");
    label.className = "label";
    label.innerHTML = `<b>${row.view ?? "overview"}</b> — ${row.label}`;
    rows.append(label, stage(row));
  }
}
