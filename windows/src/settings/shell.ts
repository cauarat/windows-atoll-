// The Settings window's body, as SettingsView.swift lays it out: a 200px
// sidebar (app header, divider, one row per section), a 1px divider, and the
// detail pane — the section title, a scroll area holding the pane's groups,
// and the status line at the bottom.
//
// Panes register a render function; the shell calls it whenever that pane
// has to be drawn (selected, re-selected by a deep link, the language
// changed), after dropping every subscription the previous render made.

import { onEvent } from "../core/bridge";
import { t } from "../core/i18n";
import { h, clear } from "../views/dom";
import { boot, clearPaneSubscriptions, clearStatus, setStatusPainter, subscribe } from "./store";
import { DEFAULT_SECTION, SETTINGS_SECTIONS, sectionId, visibleSections } from "./sections";
import { symbolTile } from "./icons";
import { closeMenus, paintRange } from "./controls";
import appIcon from "../../src-tauri/icons/128x128.png";

/** What a pane module exports: build the pane's nodes, from scratch, now. */
export type PaneRender = () => Node | Node[];

const panes = new Map<string, PaneRender>();

/** The localStorage key the selection is kept in — the Mac's `settingsSection`. */
const STORAGE_KEY = "settingsSection";

let current = DEFAULT_SECTION;
let mounted = false;

// The parts the shell repaints, built once by `mountShell`.
let rootEl: HTMLElement;
let listEl: HTMLElement;
let titleEl: HTMLElement;
let scrollEl: HTMLElement;
let contentEl: HTMLElement;
let statusEl: HTMLElement;
let versionEl: HTMLElement;

/** Registers the function that draws section `id`. Call before `mountShell`. */
export function registerPane(id: string, render: PaneRender): void {
  panes.set(id, render);
  if (mounted && id === current) rerenderPane();
}

/** The id of the section on screen. */
export function currentSection(): string {
  return current;
}

/**
 * Shows section `id`, re-rendering it even when it is already the one on
 * screen (a deep link may have changed what the pane should show). Unknown and
 * pending ids are ignored. Clears the status bar when the section changes,
 * as the Mac does when the sidebar selection moves.
 */
export function selectSection(id: string): void {
  const next = sectionId(id);
  if (!next) return;
  const changed = next !== current;
  current = next;
  try { localStorage.setItem(STORAGE_KEY, next); } catch { /* private mode */ }
  if (changed) clearStatus();
  if (!mounted) return;
  paintSelection();
  rerenderPane(changed);
}

/**
 * Draws the current pane again from its render function. `toTop` resets the
 * scroll position; otherwise it is kept, so a repaint in place does not jump.
 */
export function rerenderPane(toTop = false): void {
  if (!mounted) return;
  const keep = toTop ? 0 : scrollEl.scrollTop;
  // A menu lives on the body, not in the pane: one left open would outlive
  // the buttons it acts on.
  closeMenus();
  clearPaneSubscriptions();
  const section = SETTINGS_SECTIONS.find((s) => s.id === current);
  titleEl.textContent = section ? t(section.title) : "";
  clear(contentEl);
  const render = panes.get(current);
  const nodes = render ? render() : [];
  contentEl.append(...(Array.isArray(nodes) ? nodes : [nodes]));
  // A bare <input type=range> gets the accent fill too, not only the kit's.
  for (const r of contentEl.querySelectorAll<HTMLInputElement>('input[type="range"]')) paintRange(r);
  scrollEl.scrollTop = keep;
}

/**
 * Redraws the whole window — the title bar text, the sidebar and the pane — in
 * the language now in force. Call after `applyLanguage()`.
 */
export function rerenderAll(): void {
  // The webview's document title is what Windows draws in the title bar, so
  // it is set here rather than left to the builder's title in Rust — and it
  // moves with the language, like every other string in the window.
  document.title = t("Settings — Notchy");
  if (!mounted) return;
  versionEl.textContent = boot.version;
  buildSidebar();
  rerenderPane();
}

/**
 * The rows, in the language now in force. Built once per language: the
 * selection moves in place (`paintSelection`), so the row that has the
 * keyboard keeps it.
 */
function buildSidebar(): void {
  const hadFocus = listEl.contains(document.activeElement);
  clear(listEl);
  listEl.setAttribute("aria-label", t("Settings"));
  for (const section of visibleSections()) {
    const row = h("button", {
      type: "button",
      class: "st-row",
      role: "option",
      "data-section": section.id,
      onclick: () => {
        // The row already selected changes nothing, as on the Mac: the pane
        // keeps whatever was half done in it.
        if (section.id !== current) selectSection(section.id);
        // A click leaves the keyboard on the list, as it does on a List — even
        // where a click does not focus a button (WebKitGTK).
        row.focus({ preventScroll: true });
      },
    },
    symbolTile(section.symbol, section.color),
    h("span", { class: "st-row-title", text: t(section.title) }));
    listEl.append(row);
  }
  paintSelection();
  if (hadFocus) listEl.querySelector<HTMLElement>(".st-row.selected")?.focus({ preventScroll: true });
}

/**
 * Marks the selected row. The list is one stop for Tab, on that row, and
 * Up/Down move within it, as a List is one key view.
 */
function paintSelection(): void {
  for (const row of listEl.querySelectorAll<HTMLElement>(".st-row")) {
    const selected = row.dataset.section === current;
    row.classList.toggle("selected", selected);
    row.setAttribute("aria-selected", String(selected));
    row.tabIndex = selected ? 0 : -1;
  }
}

/** Up/Down move the selection while the sidebar has the keyboard, as a List does. */
function onSidebarKey(e: KeyboardEvent): void {
  if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
  e.preventDefault();
  const ids = visibleSections().map((s) => s.id);
  const at = ids.indexOf(current);
  const next = ids[Math.max(0, Math.min(ids.length - 1, at + (e.key === "ArrowDown" ? 1 : -1)))];
  if (next && next !== current) {
    selectSection(next);
    listEl.querySelector<HTMLElement>(`[data-section="${next}"]`)?.focus();
  }
}

/** The first section: `?section=`, then the stored one, then General. */
function initialSection(): string {
  const asked = new URLSearchParams(location.search).get("section");
  let stored: string | null = null;
  try { stored = localStorage.getItem(STORAGE_KEY); } catch { /* private mode */ }
  return sectionId(asked) ?? sectionId(stored) ?? DEFAULT_SECTION;
}

/**
 * `?scheme=light|dark` forces one appearance — for the preview grid, which
 * shows both side by side. Without it the window follows the system.
 */
function applySchemeOverride(): void {
  const scheme = new URLSearchParams(location.search).get("scheme");
  if (scheme === "light" || scheme === "dark") {
    document.documentElement.classList.add(`scheme-${scheme}`);
  }
}

/**
 * Builds the window into `root` and draws the first section: `?section=`,
 * else the one stored in localStorage "settingsSection", else General.
 */
export function mountShell(root: HTMLElement): void {
  applySchemeOverride();
  current = initialSection();

  listEl = h("nav", { class: "st-list", role: "listbox" });
  listEl.addEventListener("keydown", onSidebarKey);
  versionEl = h("div", { class: "st-version", text: boot.version });
  titleEl = h("h1", { class: "st-title" });
  contentEl = h("div", { class: "st-content" });
  contentEl.addEventListener("input", (e) => {
    const target = e.target as HTMLInputElement;
    if (target.type === "range") paintRange(target);
  });
  scrollEl = h("div", { class: "st-scroll" }, contentEl);
  statusEl = h("div", { class: "st-status", role: "status" });

  rootEl = h("div", { class: "st-window" },
    h("aside", { class: "st-sidebar" },
      h("div", { class: "st-head" },
        h("img", { class: "st-app-icon", src: appIcon, width: "32", height: "32", alt: "" }),
        h("div", { class: "st-head-text" },
          h("div", { class: "st-app-name", text: "Notchy" }),
          versionEl,
        ),
      ),
      h("div", { class: "st-divider" }),
      listEl,
    ),
    h("div", { class: "st-vdivider" }),
    h("main", { class: "st-detail" },
      titleEl,
      scrollEl,
      statusEl,
    ),
  );

  // The selection turns grey while another window has the keyboard, as a
  // macOS source list does.
  const focus = () => rootEl.classList.toggle("st-blurred", !document.hasFocus());
  window.addEventListener("focus", focus);
  window.addEventListener("blur", focus);
  focus();

  setStatusPainter((text) => {
    statusEl.textContent = text;
    statusEl.hidden = text === "";
    statusEl.classList.toggle("error", text.startsWith("❌"));
  });

  // The welcome, or another window, chose another language: the whole window
  // follows, as the Mac's does whoever changed it.
  subscribe("language", rerenderAll, { lasting: true });

  clear(root);
  root.append(rootEl);
  mounted = true;
  rerenderAll();
}

/**
 * Follows the "settings-section" event Rust sends when something asks for
 * Settings on a given pane (the ring's gear, the hydration card, …). main.ts
 * calls it before anything else, so a request that lands while the window is
 * still booting is not lost: before `mountShell` it only records the choice,
 * which `mountShell` then opens on.
 */
export function listenForSections(): void {
  void onEvent<string>("settings-section", (id) => selectSection(id));
}
