// The clipboard tab: what you copied, searchable, with favourites.
//
// The history lives in Rust (src-tauri/src/clipboard.rs) and is never written
// down; only text favourites are. Watching is off until it is turned on here —
// the app does not start reading what somebody copies because it was launched.

import { h, clear, svg } from "./dom";
import { ICONS } from "./icons";
import { Bridge, onEvent, type ClipEntry } from "../core/bridge";
import type { ViewActions, ViewHost } from "./views";

/** "21m ago", the way the reference reads. */
function ago(ms: number): string {
  const s = Math.max(0, Math.round((Date.now() - ms) / 1000));
  if (s < 60) return "just now";
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
  const needle = q.toLowerCase();
  return (e.kind === "image" ? title(e) : e.body).toLowerCase().includes(needle);
}

/** The thumbnail, drawn from raw RGBA rather than decoded from a PNG. */
function thumbCanvas(e: ClipEntry): HTMLElement {
  const canvas = h("canvas", { class: "clip-thumb" }) as HTMLCanvasElement;
  canvas.width = e.thumbW;
  canvas.height = e.thumbH;
  const ctx = canvas.getContext("2d");
  if (ctx && e.thumb) {
    const bin = atob(e.thumb);
    const data = ctx.createImageData(e.thumbW, e.thumbH);
    for (let i = 0; i < data.data.length && i < bin.length; i++) {
      data.data[i] = bin.charCodeAt(i);
    }
    ctx.putImageData(data, 0, 0);
  }
  return canvas;
}

export function buildClipboard(actions: ViewActions): ViewHost {
  let entries: ClipEntry[] = [];
  let watching = false;
  let showingFavourites = false;
  let query = "";

  const historyTab = h("button", { class: "clip-tab on", onclick: () => { showingFavourites = false; render(); } });
  const favTab = h("button", { class: "clip-tab", onclick: () => { showingFavourites = true; render(); } });

  const search = h("input", { class: "clip-search", type: "text", placeholder: "Search" }) as HTMLInputElement;
  search.addEventListener("input", () => { query = search.value; renderList(); });
  // The island closes on its own timer, which knows nothing about a half-typed
  // search. The cursor being in the field is what holds it open.
  search.addEventListener("focus", () => actions.setPinned(true));
  search.addEventListener("blur", () => actions.setPinned(false));

  const trash = h("button", { class: "clip-trash", title: "Forget everything copied",
                              onclick: () => void Bridge.clipboardClear().then(refresh) },
                  svg(ICONS.trash, 11));

  const tools = h("div", { class: "clip-tools" }, search, trash);
  const header = h("div", { class: "clip-header" }, historyTab, favTab, h("div", { class: "spacer" }), tools);
  const list = h("div", { class: "clip-list" });
  const off = h("div", { class: "clip-off" },
    h("div", { class: "clip-off-title", text: "Coucou is not watching the clipboard." }),
    h("div", { class: "clip-off-body",
               text: "Turn it on and what you copy is kept here while the app runs — "
                   + "in memory only, never written to disk." }),
    h("button", { class: "btn secondary", text: "Start watching",
                  onclick: () => void Bridge.clipboardSetWatching(true).then(refresh) }),
  );

  const el = h("div", { class: "view clipboard" },
    h("div", { class: "card" }, h("div", { class: "clip-wrap" }, header, list, off)));

  async function refresh() {
    // Outside Tauri — `npm run dev` in a browser — there is no clipboard to
    // ask. Render the empty, not-watching state rather than leaving whatever
    // the markup happened to start as.
    const got = await Bridge.clipboardEntries();
    [entries, watching] = got ?? [[], false];
    render();
  }

  function render() {
    historyTab.textContent = `History ${entries.filter((e) => !e.favourite).length || ""}`.trim();
    favTab.textContent = `Favourites ${entries.filter((e) => e.favourite).length || ""}`.trim();
    historyTab.classList.toggle("on", !showingFavourites);
    favTab.classList.toggle("on", showingFavourites);
    off.style.display = watching ? "none" : "";
    list.style.display = watching ? "" : "none";
    tools.style.display = watching ? "" : "none";
    if (watching) renderList();
  }

  function renderList() {
    const shown = entries.filter((e) => (showingFavourites ? e.favourite : true) && matches(e, query));
    clear(list);
    if (shown.length === 0) {
      list.append(h("div", { class: "clip-empty",
        text: query !== "" ? "Nothing matches."
            : showingFavourites ? "Nothing kept yet."
            : "Copy something and it shows up here." }));
      return;
    }
    for (const e of shown) list.append(row(e));
  }

  function row(e: ClipEntry): HTMLElement {
    const icon = e.kind === "image"
      ? thumbCanvas(e)
      : h("div", { class: "clip-icon" }, svg(/^https?:\/\//.test(e.body) ? ICONS.arrowUpRight : ICONS.doc, 10));

    const fav = h("button", { class: `clip-act${e.favourite ? " on" : ""}`, title: "Keep",
      onclick: (ev: Event) => {
        ev.stopPropagation();
        void Bridge.clipboardToggleFavourite(e.id).then(refresh);
      } }, svg(ICONS.star, 10));
    const del = h("button", { class: "clip-act", title: "Forget",
      onclick: (ev: Event) => {
        ev.stopPropagation();
        void Bridge.clipboardRemove(e.id).then(refresh);
      } }, svg(ICONS.xmark, 9));

    const r = h("div", { class: "clip-row" },
      icon,
      h("div", { class: "clip-text" },
        h("div", { class: "clip-title", text: title(e) }),
        h("div", { class: "clip-sub", text: subtitle(e) })),
      h("div", { class: "clip-when", text: ago(e.copiedAt) }),
      h("div", { class: "clip-acts" }, fav, del),
    );
    // Text goes back on the clipboard; an image's thumbnail is far too small to
    // be worth pasting, and keeping every original would mean holding every
    // screenshot in memory for the one time somebody wants it again.
    if (e.kind === "text") {
      r.addEventListener("click", () => { void Bridge.clipboardCopy(e.id).then(refresh); actions.blip(); });
    } else {
      r.classList.add("not-copyable");
    }
    return r;
  }

  void onEvent("clipboard-changed", () => void refresh());
  void refresh();

  return { el, sync() { /* driven by the event, not the frame loop */ } };
}
