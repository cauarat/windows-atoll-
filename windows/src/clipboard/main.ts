// The Clipboard Manager, in a window of its own — port of ClipboardPanel.swift.
//
// Not a tab in the island: a list you search and scroll wants more room than
// the island's 640 × 240, and it wants the keyboard, which the island's window
// refuses by design so it never steals focus from what you are typing in.

import "./clipboard.css";
import { Bridge, onEvent, type ClipEntry } from "../core/bridge";
import { h, clear, svg } from "../views/dom";
import { ICONS } from "../views/icons";

const root = document.getElementById("clip-root")!;

let entries: ClipEntry[] = [];
let showingFavourites = false;
let query = "";
/** The row that was just put back on the clipboard, so it can say so. */
let justCopied: string | null = null;
let justCopiedTimer: number | null = null;

function ago(ms: number): string {
  const s = Math.max(0, Math.round((Date.now() - ms) / 1000));
  if (s < 60) return "Just now";
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86_400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86_400)}d ago`;
}

function sizeLabel(bytes: number): string {
  return bytes >= 1_048_576
    ? `${(bytes / 1_048_576).toFixed(1)} MB`
    : `${Math.max(1, Math.round(bytes / 1024))} KB`;
}

function title(e: ClipEntry): string {
  if (e.kind === "image") return `Image (${sizeLabel(e.bytes)})`;
  const line = e.body.trim().split("\n", 1)[0] ?? "";
  return line === "" ? "Blank" : line;
}

function subtitle(e: ClipEntry): string {
  if (e.kind === "image") return "Image";
  if (/^https?:\/\//.test(e.body)) return "Link";
  const lines = e.body.split("\n").length;
  return lines > 1 ? `Text · ${lines} lines` : "Text";
}

function matches(e: ClipEntry, q: string): boolean {
  if (q === "") return true;
  return (e.kind === "image" ? title(e) : e.body).toLowerCase().includes(q.toLowerCase());
}

/** The thumbnail, drawn from raw RGBA rather than decoded from a PNG. */
function thumb(e: ClipEntry): HTMLElement {
  const canvas = h("canvas", { class: "row-icon" }) as HTMLCanvasElement;
  canvas.width = e.thumbW;
  canvas.height = e.thumbH;
  const ctx = canvas.getContext("2d");
  if (ctx && e.thumb) {
    const bin = atob(e.thumb);
    const data = ctx.createImageData(e.thumbW, e.thumbH);
    for (let i = 0; i < data.data.length && i < bin.length; i++) data.data[i] = bin.charCodeAt(i);
    ctx.putImageData(data, 0, 0);
  }
  return canvas;
}

// ── Chrome ───────────────────────────────────────────────────────────────────

const closeBtn = h("button", { class: "chrome-close", title: "Close",
                               onclick: () => void Bridge.closeClipboardWindow() });
const trashBtn = h("button", { class: "chrome-trash", title: "Forget everything",
                               onclick: () => void Bridge.clipboardClear().then(refresh) },
                   svg(ICONS.trash, 14));

const historyTab = h("button", { class: "tab on", onclick: () => { showingFavourites = false; render(); } });
const favTab = h("button", { class: "tab", onclick: () => { showingFavourites = true; render(); } });

const search = h("input", { class: "search", type: "text", placeholder: "Search clipboard…" }) as HTMLInputElement;
search.addEventListener("input", () => { query = search.value; renderList(); });

const list = h("div", { class: "list" });

root.append(
  h("div", { class: "chrome" },
    closeBtn,
    h("span", { class: "chrome-icon" }, svg(ICONS.clipboard, 15)),
    h("span", { class: "chrome-title", text: "Clipboard Manager" }),
    h("span", { class: "spacer" }),
    trashBtn),
  h("div", { class: "tabs" }, historyTab, favTab),
  h("div", { class: "search-wrap" }, h("span", { class: "search-icon" }, svg(ICONS.search, 12)), search),
  h("div", { class: "divider" }),
  list,
);

// ── Rendering ────────────────────────────────────────────────────────────────

function render() {
  clear(historyTab);
  historyTab.append(svg(ICONS.timer, 12), h("span", { text: "History" }));
  const n = entries.length;
  if (n > 0) historyTab.append(h("span", { class: "count", text: String(n) }));

  clear(favTab);
  favTab.append(svg(ICONS.heart, 12), h("span", { text: "Favorites" }));

  historyTab.classList.toggle("on", !showingFavourites);
  favTab.classList.toggle("on", showingFavourites);
  renderList();
}

function renderList() {
  const shown = entries.filter((e) => (showingFavourites ? e.favourite : true) && matches(e, query));
  clear(list);
  if (shown.length === 0) {
    list.append(h("div", { class: "empty",
      text: query !== "" ? "Nothing matches."
          : showingFavourites ? "Nothing kept yet."
          : "Copy something and it shows up here." }));
    return;
  }
  for (const e of shown) list.append(row(e));
}

function row(e: ClipEntry): HTMLElement {
  const copied = justCopied === e.id;

  const icon = e.kind === "image"
    ? thumb(e)
    : h("span", { class: "row-icon text" },
        svg(/^https?:\/\//.test(e.body) ? ICONS.arrowUpRight : ICONS.doc, 12));

  const acts = h("div", { class: "acts" },
    h("button", { class: `act fav${e.favourite ? " on" : ""}`, title: "Keep",
      onclick: (ev: Event) => { ev.stopPropagation(); void Bridge.clipboardToggleFavourite(e.id).then(refresh); } },
      svg(ICONS.heart, 13)),
    h("button", { class: "act copy", title: "Copy",
      onclick: (ev: Event) => { ev.stopPropagation(); copy(e); } },
      svg(ICONS.clipboard, 13)),
    h("button", { class: "act del", title: "Forget",
      onclick: (ev: Event) => { ev.stopPropagation(); void Bridge.clipboardRemove(e.id).then(refresh); } },
      svg(ICONS.trash, 13)),
  );

  const r = h("div", { class: `row${copied ? " copied" : ""}` },
    icon,
    h("div", { class: "row-text" },
      h("div", { class: "row-title", text: title(e) }),
      h("div", { class: "row-sub", text: copied ? "Copied" : subtitle(e) })),
    h("span", { class: "row-when", text: copied ? "" : ago(e.copiedAt) }),
    acts,
  );
  r.addEventListener("click", () => copy(e));
  return r;
}

/// Puts it back, then says so on the row itself for a moment — the feedback
/// belongs where the eye already is, not in a corner of the window.
function copy(e: ClipEntry) {
  void Bridge.clipboardCopy(e.id).then(() => {
    justCopied = e.id;
    renderList();
    if (justCopiedTimer != null) window.clearTimeout(justCopiedTimer);
    justCopiedTimer = window.setTimeout(() => {
      justCopied = null;
      justCopiedTimer = null;
      void refresh();
    }, 1100);
  });
}

async function refresh() {
  const got = await Bridge.clipboardEntries();
  [entries] = got ?? [[]];
  render();
}

// Escape closes, the way a popover behaves.
window.addEventListener("keydown", (e) => {
  if (e.key === "Escape") void Bridge.closeClipboardWindow();
});

void onEvent("clipboard-changed", () => void refresh());
void refresh();
// Opening the manager is the clearest statement that you want the clipboard
// kept, so watching starts here rather than needing a second decision.
void Bridge.clipboardSetWatching(true);
search.focus();
