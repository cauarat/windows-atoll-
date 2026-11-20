// The macOS control kit for the Settings window: each function builds one
// control the way SwiftUI draws it in the Mac's Settings (GroupBox, checkbox,
// small switch, push buttons, popup, slider, rounded field, segmented control,
// stepper…). Styles are in settings.css under "Controls" (classes `mc-*`).
//
// Every builder returns the element itself, with a few methods attached, so it
// goes straight into `h(...)` or another builder as a child. Every control
// takes `disabled` and has `setDisabled(on)`; `disable(el, on)` disables a
// whole row the way `.disabled()` does on a SwiftUI stack.
//
// Text passed in is drawn as given: translate it with t() first.

import { h, clear } from "../views/dom";
import { t } from "../core/i18n";
import { acceleratorFrom, shortcutLabel } from "../core/shortcut";
import { symbol } from "./icons";
import { subscribe } from "./store";

/** Anything `h` takes as a child. */
export type Child = Node | string | null | undefined | false;

type WithDisabled = { setDisabled(on: boolean): void };

function append(parent: HTMLElement, children: Child[]): void {
  for (const c of children) {
    if (c == null || c === false) continue;
    parent.append(typeof c === "string" ? document.createTextNode(c) : c);
  }
}

/**
 * SwiftUI's `.disabled(on)` on a stack: everything in `el` stops taking clicks,
 * and its controls get `disabled`, so the keyboard skips them and each draws
 * its own disabled look — a field greys its text and keeps its fill. A plain
 * label is not dimmed: `.disabled()` leaves Text alone. Where the Mac also
 * fades the whole stack (`.opacity(0.4)`), add `mc-disabled` as well.
 */
export function disable(el: HTMLElement, on: boolean): void {
  el.classList.toggle("mc-inert", on);
  el.setAttribute("aria-disabled", String(on));
  for (const c of el.querySelectorAll<HTMLInputElement | HTMLButtonElement | HTMLSelectElement>(
    "input, button, select, textarea")) {
    c.disabled = on;
  }
}

// ── Layout ────────────────────────────────────────────────────────────────────

export interface GroupBoxOptions {
  /** Drawn above the box, 11px in the label colour. Omit for an untitled box. */
  title?: string | null;
  /** Space between the box's children, px — the Mac VStack's `spacing`. Default 6. */
  gap?: number;
}

/**
 * A macOS GroupBox: the title above, then a rounded, faintly filled box with
 * the children stacked in it (10px inset — the box's own plus `.padding(6)`).
 * `title` may be a string, null (no title), or the options object.
 *
 *   groupBox(t("Sound"), checkbox(…), inlineRow(…))
 *   groupBox({ title: t("Behavior"), gap: 10 }, …)
 *
 * `.box` is the inner box, to append to later.
 */
export function groupBox(
  title: string | null | GroupBoxOptions, ...children: Child[]
): HTMLElement & { box: HTMLElement } {
  const opts: GroupBoxOptions = title !== null && typeof title === "object" ? title : { title };
  const box = h("div", { class: "mc-gb-box" });
  box.style.gap = `${opts.gap ?? 6}px`;
  append(box, children);
  const el = h("div", { class: "mc-gb" },
    opts.title ? h("div", { class: "mc-gb-title", text: opts.title }) : null,
    box) as unknown as HTMLElement & { box: HTMLElement };
  el.box = box;
  return el;
}

/**
 * A row of controls, left to right, vertically centred, 8px apart — an HStack.
 * Set `.style.gap` for another spacing.
 */
export function inlineRow(...children: Child[]): HTMLElement {
  const el = h("div", { class: "mc-row" });
  append(el, children);
  return el;
}

/** A column, `gap` px apart — a VStack inside a box, when one box needs two spacings. */
export function stack(gap: number, ...children: Child[]): HTMLElement {
  const el = h("div", { class: "mc-stack" });
  el.style.gap = `${gap}px`;
  append(el, children);
  return el;
}

/** Takes the free space in an inlineRow — SwiftUI's Spacer(). */
export function spacer(): HTMLElement {
  return h("span", { class: "mc-spacer" });
}

/** A 1px horizontal separator line — Divider(). */
export function divider(): HTMLElement {
  return h("div", { class: "mc-divider", role: "separator" });
}

// ── Boxes as wide as what they hold ───────────────────────────────────────────

const px = (v: string) => parseFloat(v) || 0;

/** The widest line `el`'s text wraps into, as laid out now. */
function widestLine(el: HTMLElement): number {
  const range = document.createRange();
  range.selectNodeContents(el);
  let widest = 0;
  for (const rect of range.getClientRects()) widest = Math.max(widest, rect.width);
  return widest;
}

/** Whether `el` takes all the width it is offered: a Spacer, a slider, a field with no width of its own. */
function stretches(el: HTMLElement): boolean {
  if (el.matches(".mc-spacer, .mc-slider, .mc-seg.full, textarea")) return true;
  if (el.matches(".mc-field") && getComputedStyle(el).flexGrow !== "0") return true;
  return [...el.children].some((c) => stretches(c as HTMLElement));
}

/**
 * How wide a box's child would be on its own: the widest line of a text, the
 * width of a control that keeps its own size or of a row of them side by side,
 * or Infinity for anything that stretches — a row with a Spacer, a field, a
 * slider, a list.
 */
function naturalWidth(el: HTMLElement): number {
  const style = getComputedStyle(el);
  if (style.display === "none") return 0;
  const isText = el.childElementCount === 0 && !el.matches("input, select, textarea, button");
  if (isText) return widestLine(el);
  if (style.alignSelf === "flex-start") return el.getBoundingClientRect().width;
  if (stretches(el)) return Infinity;
  const was = el.style.width;
  el.style.width = "max-content";
  const width = el.getBoundingClientRect().width;
  el.style.width = was;
  return width;
}

/**
 * SwiftUI sizes a GroupBox to what it holds: wrapped text reports the width of
 * its widest line, and a row of fixed controls its own width, so a box of short
 * lines stops short of the pane's edge (the Mac's "Opening" and "Behavior"
 * boxes do). A block in CSS takes all the width it is offered instead. This
 * narrows each of `boxes` to its widest line or control, and leaves at full
 * width any box holding something that stretches, as the Mac does. `container`
 * is what holds them: when it changes size — the window, the scroll bar, a row
 * shown or hidden — they are measured again.
 */
export function hugBoxes(container: HTMLElement, boxes: readonly HTMLElement[]): void {
  const fit = () => {
    for (const gb of boxes) {
      gb.style.width = "";
      const inner = gb.querySelector<HTMLElement>(".mc-gb-box");
      if (!inner) continue;
      const cs = getComputedStyle(inner);
      const inset = px(cs.paddingLeft) + px(cs.paddingRight)
        + px(cs.borderLeftWidth) + px(cs.borderRightWidth);
      let need = 0;
      for (const child of inner.children) need = Math.max(need, naturalWidth(child as HTMLElement) + inset);
      const title = gb.querySelector<HTMLElement>(".mc-gb-title");
      if (title) need = Math.max(need, widestLine(title) + px(getComputedStyle(title).marginLeft));
      const full = gb.getBoundingClientRect();
      // A pixel of slack, so rounding never re-wraps a line that fitted.
      if (!Number.isFinite(need) || need + 1 >= full.width) continue;
      gb.style.width = `${Math.ceil(need) + 1}px`;
      // Narrower must not mean taller: if a line wrapped differently after all
      // (the hints wrap "pretty", which weighs the width), keep the full box.
      if (Math.abs(gb.getBoundingClientRect().height - full.height) > 0.5) gb.style.width = "";
    }
  };
  const observer = new ResizeObserver(() => {
    if (!container.isConnected) {
      observer.disconnect();
      return;
    }
    fit();
  });
  observer.observe(container);
  // What is in the boxes changing without moving the container: a popup that
  // gains "Where you dropped it", a label in a font that arrived late.
  // Registered after the boxes' own listeners, so it measures what they have
  // just drawn.
  subscribe("settings", fit);
  void document.fonts?.ready.then(() => { if (container.isConnected) fit(); });
}

/**
 * Body text in the label colour, 13px — a plain Text in a row. `width` fixes
 * it, as `.frame(width:)` does ("Volume" 56, "Shortcut" 70, Hydration's 150).
 */
export function label(text: string, width?: number): HTMLElement {
  const el = h("span", { class: "mc-label", text });
  if (width) {
    el.style.width = `${width}px`;
    el.style.flex = "none";
  }
  return el;
}

/** 11px semibold, secondary — the Mac's in-box section captions ("Where you code", "Messages"). */
export function caption(text: string): HTMLElement {
  return h("div", { class: "mc-caption", text });
}

/**
 * The secondary explanatory text under a control. 11px by default; the Mac
 * uses 10 in Integrations and 12 in Chat. Wraps.
 */
export function hint(text: string, size: 10 | 11 | 12 = 11): HTMLElement {
  return h("div", { class: size === 11 ? "mc-hint" : `mc-hint s${size}`, text });
}

// ── Checkbox and switch ───────────────────────────────────────────────────────

export interface CheckboxOptions {
  disabled?: boolean;
  /** 11px label, as the Displays checkboxes are. */
  small?: boolean;
  /** For a label-hidden checkbox (pass "" as the label): what a screen reader says. */
  ariaLabel?: string;
}

export type Checkbox = HTMLLabelElement & WithDisabled & {
  input: HTMLInputElement;
  /** Ticks or unticks it without calling onChange. */
  set(on: boolean): void;
  setLabel(text: string): void;
};

/**
 * A macOS checkbox — what a plain SwiftUI Toggle is in a Mac form: a 14x14
 * rounded box, ticked in the accent colour with a white check, the label to its
 * RIGHT. Pass "" as the label for the label-hidden one (the pill rows).
 */
export function checkbox(
  text: string, on: boolean, onChange: (on: boolean) => void, opts: CheckboxOptions = {},
): Checkbox {
  const input = h("input", { type: "checkbox", class: "mc-checkbox-input" });
  input.checked = on;
  if (opts.ariaLabel) input.setAttribute("aria-label", opts.ariaLabel);
  const box = h("span", { class: "mc-checkbox-box" }, symbol("checkmark", 12));
  const labelText = h("span", { class: "mc-checkbox-label", text });
  labelText.hidden = text === "";
  const el = h("label", { class: opts.small ? "mc-checkbox small" : "mc-checkbox" },
    input, box, labelText) as Checkbox;
  input.addEventListener("change", () => onChange(input.checked));
  el.input = input;
  el.set = (v) => { input.checked = v; };
  el.setLabel = (v) => { labelText.textContent = v; labelText.hidden = v === ""; };
  el.setDisabled = (d) => {
    input.disabled = d;
    el.classList.toggle("mc-disabled", d);
  };
  if (opts.disabled) el.setDisabled(true);
  return el;
}

export interface SwitchOptions {
  disabled?: boolean;
  ariaLabel?: string;
}

export type Switch = HTMLButtonElement & WithDisabled & {
  set(on: boolean): void;
  isOn(): boolean;
};

/**
 * The macOS small switch — `.toggleStyle(.switch).controlSize(.small)`, which
 * the Mac uses only for Hydration's Day streak, Quiet hours and "Today is hot".
 * About 26x15, the track in the accent colour when on.
 */
export function smallSwitch(on: boolean, onChange: (on: boolean) => void, opts: SwitchOptions = {}): Switch {
  const el = h("button", { type: "button", class: "mc-switch", role: "switch" }) as Switch;
  if (opts.ariaLabel) el.setAttribute("aria-label", opts.ariaLabel);
  el.set = (v) => {
    el.classList.toggle("on", v);
    el.setAttribute("aria-checked", String(v));
  };
  el.isOn = () => el.classList.contains("on");
  el.setDisabled = (d) => { el.disabled = d; };
  el.addEventListener("click", () => {
    const next = !el.isOn();
    el.set(next);
    onChange(next);
  });
  el.set(on);
  if (opts.disabled) el.setDisabled(true);
  return el;
}

// ── Buttons ───────────────────────────────────────────────────────────────────

/**
 * - "bordered": the default push button — grey fill (Button with no style, .bordered).
 * - "prominent": `.borderedProminent` — accent fill, white text.
 * - "link": `.link` — accent text, no chrome.
 * - "borderless": `.borderless` — bare text or glyph in the secondary colour.
 */
export type ButtonKind = "bordered" | "prominent" | "link" | "borderless";

export interface ButtonOptions {
  kind?: ButtonKind;
  /** `.controlSize(.small)`: 18px tall, 11px text. */
  small?: boolean;
  disabled?: boolean;
  title?: string;
  /** An SF Symbol drawn before the text ("plus" for "+ Add a button"). */
  symbol?: string;
}

export type PushButton = HTMLButtonElement & WithDisabled & { setText(text: string): void };

/** A macOS push button. 24px tall (18 when small), r6, 13px text. */
export function pushButton(text: string, onClick: () => void, opts: ButtonOptions = {}): PushButton {
  const kind = opts.kind ?? "bordered";
  const cls = ["mc-btn", kind, opts.small ? "small" : ""].filter(Boolean).join(" ");
  const textEl = h("span", { text });
  const el = h("button", { type: "button", class: cls },
    opts.symbol ? symbol(opts.symbol, opts.small ? 10 : 12) : null, textEl) as PushButton;
  if (opts.title) el.title = opts.title;
  el.addEventListener("click", () => onClick());
  el.setText = (v) => { textEl.textContent = v; };
  el.setDisabled = (d) => { el.disabled = d; };
  if (opts.disabled) el.setDisabled(true);
  return el;
}

export interface IconButtonOptions {
  /** Tooltip and accessible name. */
  title?: string;
  /** Glyph size, px. Default 13 (the ring editor's chevrons and minus.circle). */
  size?: number;
  disabled?: boolean;
}

/** A borderless glyph button — `Button { Image(systemName:) }.buttonStyle(.borderless)`. */
export function iconButton(symbolName: string, onClick: () => void, opts: IconButtonOptions = {}): PushButton {
  const el = h("button", { type: "button", class: "mc-btn borderless icon" },
    symbol(symbolName, opts.size ?? 13)) as PushButton;
  if (opts.title) {
    el.title = opts.title;
    el.setAttribute("aria-label", opts.title);
  }
  el.addEventListener("click", () => onClick());
  el.setText = () => {};
  el.setDisabled = (d) => { el.disabled = d; };
  if (opts.disabled) el.setDisabled(true);
  return el;
}

/**
 * The small indeterminate spinner — `ProgressView().controlSize(.small)`:
 * eight rounded spokes across 16x16, the darkest one stepping round clockwise
 * with the others fading behind it, as AppKit draws it.
 */
export function spinner(): HTMLElement {
  const spokes = Array.from({ length: 8 }, (_, i) =>
    // Spoke 0 is the head, at the top; each one counter-clockwise from it is fainter.
    `<line x1="8" y1="0.9" x2="8" y2="4.1" opacity="${(0.275 - i * 0.035).toFixed(3)}" `
    + `transform="rotate(${-i * 45} 8 8)"/>`).join("");
  const el = h("span", { class: "mc-spinner", role: "progressbar", "aria-busy": "true" });
  el.innerHTML = '<svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">'
    + `<g stroke="currentColor" stroke-width="1.75" stroke-linecap="round">${spokes}</g></svg>`;
  return el;
}

// ── Popup ─────────────────────────────────────────────────────────────────────

export type PopupOption<T extends string = string> = { value: T; label: string; disabled?: boolean } | "separator";

export interface PopupOptions {
  /** Shown to the LEFT of the popup, as a Picker with its label. Omit for `.labelsHidden()`. */
  label?: string;
  /** Fixed width of that label, px. */
  labelWidth?: number;
  /** Fixed width of the popup itself, px (the ring's side popup is 92). Default: fits its text. */
  width?: number;
  disabled?: boolean;
  ariaLabel?: string;
}

export type Popup<T extends string = string> = HTMLElement & WithDisabled & {
  select: HTMLSelectElement;
  value(): T;
  /** Shows `v` without calling onChange. */
  set(v: T): void;
  /** Replaces the options, keeping the value when it is still offered. */
  setOptions(options: PopupOption<T>[]): void;
};

/**
 * A macOS popup button: grey push-button fill, the value, and the
 * up-and-down chevrons on the right. A native <select> underneath, so the
 * list itself is the system's.
 */
export function popup<T extends string>(
  options: PopupOption<T>[], value: T, onChange: (v: T) => void, opts: PopupOptions = {},
): Popup<T> {
  const select = h("select", { class: "mc-select" });
  if (opts.ariaLabel ?? opts.label) select.setAttribute("aria-label", (opts.ariaLabel ?? opts.label)!);
  if (opts.width) select.style.width = `${opts.width}px`;
  const fill = (list: PopupOption<T>[]) => {
    clear(select);
    for (const o of list) {
      if (o === "separator") select.append(h("hr"));
      else select.append(h("option", { value: o.value, text: o.label, disabled: o.disabled }));
    }
  };
  fill(options);
  select.value = value;
  select.addEventListener("change", () => onChange(select.value as T));
  const el = h("label", { class: "mc-popup" },
    opts.label ? label(opts.label, opts.labelWidth) : null, select) as unknown as Popup<T>;
  el.select = select;
  el.value = () => select.value as T;
  el.set = (v) => { select.value = v; };
  el.setOptions = (list) => {
    const was = select.value;
    fill(list);
    select.value = was;
  };
  el.setDisabled = (d) => {
    select.disabled = d;
    el.classList.toggle("mc-disabled", d);
  };
  if (opts.disabled) el.setDisabled(true);
  return el;
}

// ── Menu button ───────────────────────────────────────────────────────────────

export type MenuEntry =
  | { label: string; onSelect: () => void; disabled?: boolean; symbol?: string; color?: string }
  | "separator";

export interface MenuButtonOptions {
  /** Leading glyph ("plus" for the ring editor's "+ Add a button"). */
  symbol?: string;
  /** Bare text (the ring editor's) rather than a bordered push button. Default true. */
  borderless?: boolean;
  disabled?: boolean;
}

export type MenuButton = HTMLButtonElement & WithDisabled & { setText(text: string): void };

let openMenu: { el: HTMLElement; close(): void } | null = null;

/**
 * Folds whichever menu is open. The shell calls it before a pane is drawn
 * again, and a pane before it rebuilds the controls a menu was opened from: a
 * menu lives on the body, and one left open would outlive its buttons.
 */
export function closeMenus(): void {
  openMenu?.close();
}

/** The ⌄ after a menu's title: chevron.down small and heavy, 7x4 as AppKit draws it. */
function menuIndicator(): SVGSVGElement {
  const chevron = symbol("chevron.down", 8);
  chevron.querySelector("path")?.setAttribute("stroke-width", "3.2");
  return chevron;
}

/**
 * A button that drops a menu — SwiftUI's `Menu`: the label, a small chevron,
 * and on click a list of entries with separators. `entries` may be a function,
 * read each time the menu opens, so it reflects the current state.
 * An entry may carry a colour dot (`color`) or a glyph (`symbol`).
 */
export function menuButton(
  text: string, entries: MenuEntry[] | (() => MenuEntry[]), opts: MenuButtonOptions = {},
): MenuButton {
  const textEl = h("span", { text });
  const el = h("button", {
    type: "button",
    class: opts.borderless === false ? "mc-btn bordered mc-menu-btn" : "mc-btn link-plain mc-menu-btn",
    "aria-haspopup": "menu",
  },
  opts.symbol ? symbol(opts.symbol, 11) : null,
  textEl,
  menuIndicator()) as MenuButton;

  const close = () => {
    if (!openMenu) return;
    openMenu.el.remove();
    openMenu = null;
    el.setAttribute("aria-expanded", "false");
    document.removeEventListener("mousedown", outside, true);
    document.removeEventListener("keydown", onKey, true);
    window.removeEventListener("blur", close);
  };
  const outside = (e: MouseEvent) => {
    if (openMenu && !openMenu.el.contains(e.target as Node) && !el.contains(e.target as Node)) close();
  };
  // Only while the keyboard is in the menu or on its button: the arrows of a
  // popup or of the sidebar elsewhere in the window are theirs.
  const onKey = (e: KeyboardEvent) => {
    if (!openMenu) return;
    const active = document.activeElement;
    const inMenu = openMenu.el.contains(active);
    if (!inMenu && active !== el) return;
    const items = [...openMenu.el.querySelectorAll<HTMLButtonElement>(".mc-menu-item:not(:disabled)")];
    const at = items.indexOf(active as HTMLButtonElement);
    if (e.key === "Escape") { e.preventDefault(); close(); el.focus(); }
    // An open NSMenu ignores Tab: the keyboard stays in the menu until it is
    // used or put away.
    else if (e.key === "Tab") e.preventDefault();
    else if (inMenu && e.key === "ArrowDown") { e.preventDefault(); items[Math.min(items.length - 1, at + 1)]?.focus(); }
    else if (inMenu && e.key === "ArrowUp") { e.preventDefault(); items[Math.max(0, at - 1)]?.focus(); }
  };
  // The keyboard taken somewhere else — not a click on the menu's own padding
  // or separator, which moves it nowhere (no relatedTarget).
  const focusLeft = (e: FocusEvent) => {
    const to = e.relatedTarget as Node | null;
    if (openMenu && to && !openMenu.el.contains(to) && !el.contains(to)) close();
  };
  el.addEventListener("focusout", focusLeft);

  el.addEventListener("click", () => {
    // A second click on the same button folds its menu, as AppKit's does.
    if (openMenu) {
      const mine = el.getAttribute("aria-expanded") === "true";
      openMenu.close();
      if (mine) return;
    }
    const list = typeof entries === "function" ? entries() : entries;
    const menu = h("div", { class: "mc-menu", role: "menu" });
    menu.addEventListener("focusout", focusLeft);
    for (const entry of list) {
      if (entry === "separator") { menu.append(h("div", { class: "mc-menu-sep", role: "separator" })); continue; }
      const item = h("button", { type: "button", class: "mc-menu-item", role: "menuitem", disabled: entry.disabled },
        entry.color ? h("i", { class: "mc-menu-dot", style: `background:${entry.color}` }) : null,
        entry.symbol ? symbol(entry.symbol, 12) : null,
        h("span", { text: entry.label }));
      item.addEventListener("click", () => { close(); entry.onSelect(); });
      menu.append(item);
    }
    document.body.append(menu);
    const r = el.getBoundingClientRect();
    const mh = menu.offsetHeight;
    const below = r.bottom + 4 + mh <= window.innerHeight;
    menu.style.left = `${Math.min(r.left, window.innerWidth - menu.offsetWidth - 8)}px`;
    menu.style.top = `${below ? r.bottom + 4 : Math.max(8, r.top - 4 - mh)}px`;
    openMenu = { el: menu, close };
    el.setAttribute("aria-expanded", "true");
    document.addEventListener("mousedown", outside, true);
    document.addEventListener("keydown", onKey, true);
    // As a menu folds when its app goes to the background.
    window.addEventListener("blur", close);
    menu.querySelector<HTMLButtonElement>(".mc-menu-item:not(:disabled)")?.focus();
  });
  el.setText = (v) => { textEl.textContent = v; };
  el.setDisabled = (d) => { el.disabled = d; };
  if (opts.disabled) el.setDisabled(true);
  return el;
}

// ── Slider ────────────────────────────────────────────────────────────────────

export interface SliderOptions {
  min: number;
  max: number;
  step?: number;
  disabled?: boolean;
  /** A trailing value label, e.g. (v) => `${Math.round(v / 0.2 * 100)} %`. */
  valueText?: (v: number) => string;
  /** Width of that label, px, right-aligned with tabular digits (36 for Volume, 44 for "NN pt"). */
  valueWidth?: number;
  /** "body" (13px label colour, Volume) or "secondary" (11px, the "NN pt" rows). Default "body". */
  valueStyle?: "body" | "secondary";
  /** Tick marks under the track, one per step — a stepped SwiftUI Slider. */
  ticks?: boolean;
  /** Called once the knob is let go, with the final value. */
  onCommit?: (v: number) => void;
  ariaLabel?: string;
}

export type Slider = HTMLElement & WithDisabled & { input: HTMLInputElement; set(v: number): void };

/**
 * A macOS slider: a thin track filled in the accent colour up to the knob, a
 * white knob with a shadow, and an optional value label after it. `onInput`
 * runs on every movement.
 */
export function slider(value: number, opts: SliderOptions, onInput: (v: number) => void): Slider {
  const input = h("input", {
    type: "range", class: "mc-range",
    min: String(opts.min), max: String(opts.max), step: String(opts.step ?? "any"),
  });
  if (opts.ariaLabel) input.setAttribute("aria-label", opts.ariaLabel);
  input.value = String(value);
  const valueEl = opts.valueText
    ? h("span", { class: opts.valueStyle === "secondary" ? "mc-slider-value secondary" : "mc-slider-value" })
    : null;
  if (valueEl && opts.valueWidth) valueEl.style.width = `${opts.valueWidth}px`;
  const paint = () => {
    paintRange(input);
    if (valueEl && opts.valueText) valueEl.textContent = opts.valueText(Number(input.value));
  };
  input.addEventListener("input", () => { paint(); onInput(Number(input.value)); });
  if (opts.onCommit) input.addEventListener("change", () => opts.onCommit!(Number(input.value)));
  const track = h("div", { class: opts.ticks ? "mc-slider-track ticks" : "mc-slider-track" }, input);
  if (opts.ticks && opts.step) {
    const n = Math.round((opts.max - opts.min) / opts.step);
    if (n > 0 && n <= 200) track.style.setProperty("--tick-count", String(n));
  }
  const el = h("div", { class: "mc-slider" }, track, valueEl) as unknown as Slider;
  el.input = input;
  el.set = (v) => { input.value = String(v); paint(); };
  // The slider alone: the value beside it is a Text of its own on the Mac
  // ("60 %" next to a disabled Volume slider), and keeps its colour.
  el.setDisabled = (d) => { input.disabled = d; };
  if (opts.disabled) el.setDisabled(true);
  paint();
  return el;
}

/**
 * Sets `--pct` on a range input, which the CSS fills the track to. The kit's
 * slider does this itself; the shell also runs it over every range input in a
 * pane, so a bare `<input type=range>` gets the accent fill too.
 */
export function paintRange(input: HTMLInputElement): void {
  const min = Number(input.min || 0);
  const max = Number(input.max || 100);
  const pct = max > min ? ((Number(input.value) - min) / (max - min)) * 100 : 0;
  input.style.setProperty("--pct", `${Math.max(0, Math.min(100, pct))}%`);
}

// ── Fields ────────────────────────────────────────────────────────────────────

export interface FieldOptions {
  placeholder?: string;
  /** Fixed width, px. Default: fills the row. */
  width?: number;
  disabled?: boolean;
  ariaLabel?: string;
  /** Every keystroke; onChange runs on Enter and on leaving the field. */
  onInput?: (v: string) => void;
  /** HTML input type for a plain field. Default "text". */
  type?: "text" | "url" | "email";
  /** Monospaced text (model ids, URLs). */
  mono?: boolean;
  maxLength?: number;
}

export type Field = HTMLInputElement & WithDisabled;

function makeField(type: string, value: string, onChange: (v: string) => void, opts: FieldOptions): Field {
  const el = h("input", {
    type, class: opts.mono ? "mc-field mono" : "mc-field",
    autocomplete: "off", spellcheck: "false",
  }) as Field;
  el.value = value;
  if (opts.placeholder) el.placeholder = opts.placeholder;
  if (opts.ariaLabel) el.setAttribute("aria-label", opts.ariaLabel);
  if (opts.maxLength) el.maxLength = opts.maxLength;
  if (opts.width) {
    el.style.width = `${opts.width}px`;
    el.style.flex = "none";
  }
  el.addEventListener("change", () => onChange(el.value));
  if (opts.onInput) el.addEventListener("input", () => opts.onInput!(el.value));
  el.setDisabled = (d) => { el.disabled = d; };
  if (opts.disabled) el.setDisabled(true);
  return el;
}

/** A `.roundedBorder` TextField: r5, the control background, an accent focus ring. */
export function textField(value: string, onChange: (v: string) => void, opts: FieldOptions = {}): Field {
  return makeField(opts.type ?? "text", value, onChange, opts);
}

/** A `.roundedBorder` SecureField. */
export function secureField(value: string, onChange: (v: string) => void, opts: FieldOptions = {}): Field {
  return makeField("password", value, onChange, opts);
}

export interface NumberFieldOptions {
  min: number;
  max: number;
  step?: number;
  /** Px. Default 64, the Mac's "Close after" / "Hide after" fields. */
  width?: number;
  disabled?: boolean;
  ariaLabel?: string;
  /** What an empty or unreadable entry becomes before clamping. Default: the previous value. */
  fallback?: number;
}

export type NumberField = Field & { set(v: number): void };

/**
 * A `.roundedBorder` TextField with a number in it. Clamped to min…max (and
 * rounded to `step`) when the field is committed, and rewritten to what was
 * kept, so it never shows a number that is not in force.
 */
export function numberField(value: number, opts: NumberFieldOptions, onChange: (v: number) => void): NumberField {
  let last = value;
  const el = makeField("text", String(value), (raw) => {
    const n = Number(raw.trim().replace(",", "."));
    let v = Number.isFinite(n) && raw.trim() !== "" ? n : (opts.fallback ?? last);
    if (opts.step) v = Math.round(v / opts.step) * opts.step;
    v = Math.max(opts.min, Math.min(opts.max, v));
    el.value = String(v);
    if (v !== last) {
      last = v;
      onChange(v);
    }
  }, { width: opts.width ?? 64, disabled: opts.disabled, ariaLabel: opts.ariaLabel }) as NumberField;
  el.inputMode = "numeric";
  el.classList.add("number");
  el.set = (v) => { last = v; el.value = String(v); };
  return el;
}

// ── Segmented control and stepper ─────────────────────────────────────────────

export interface SegmentedOptions {
  /** Stretch across the row, segments sharing it equally (the Dynamic Island tabs). */
  fullWidth?: boolean;
  disabled?: boolean;
  ariaLabel?: string;
}

export type Segmented<T extends string = string> = HTMLElement & WithDisabled & {
  set(v: T): void;
  value(): T;
};

/**
 * A macOS segmented control: a grey track, the chosen segment filled in the
 * accent colour. One stop for Tab, on the chosen segment; the arrow keys
 * choose the one beside it, Home and End the first and the last, as with any
 * group of radio buttons.
 */
export function segmented<T extends string>(
  options: { value: T; label: string }[], value: T, onChange: (v: T) => void, opts: SegmentedOptions = {},
): Segmented<T> {
  let currentValue = value;
  const el = h("div", { class: opts.fullWidth ? "mc-seg full" : "mc-seg", role: "radiogroup" }) as unknown as Segmented<T>;
  if (opts.ariaLabel) el.setAttribute("aria-label", opts.ariaLabel);
  const buttons = options.map((o) => {
    const b = h("button", { type: "button", class: "mc-seg-item", role: "radio", text: o.label });
    b.addEventListener("click", () => {
      if (currentValue === o.value) return;
      el.set(o.value);
      onChange(o.value);
    });
    el.append(b);
    return { value: o.value, b };
  });
  el.addEventListener("keydown", (e) => {
    const at = buttons.findIndex((x) => x.value === currentValue);
    const last = buttons.length - 1;
    let to: number;
    if (e.key === "ArrowLeft" || e.key === "ArrowUp") to = Math.max(0, at - 1);
    else if (e.key === "ArrowRight" || e.key === "ArrowDown") to = Math.min(last, at + 1);
    else if (e.key === "Home") to = 0;
    else if (e.key === "End") to = last;
    else return;
    e.preventDefault();
    const next = buttons[to];
    if (to === at || !next || next.b.disabled) return;
    // Focus first: a pane redrawn by onChange looks for the keyboard in here
    // to hand it back.
    next.b.focus();
    el.set(next.value);
    onChange(next.value);
  });
  el.set = (v) => {
    currentValue = v;
    buttons.forEach(({ value: bv, b }, i) => {
      const on = bv === v;
      b.setAttribute("aria-checked", String(on));
      b.classList.toggle("on", on);
      b.tabIndex = on ? 0 : -1;
      // No hairline either side of the chosen one, as AppKit draws it.
      b.classList.toggle("before-on", buttons[i + 1]?.value === v);
    });
    // A value none of the segments has still leaves a way in.
    if (!buttons.some((x) => x.value === v) && buttons[0]) buttons[0].b.tabIndex = 0;
  };
  el.value = () => currentValue;
  el.setDisabled = (d) => {
    for (const { b } of buttons) b.disabled = d;
    el.classList.toggle("mc-disabled", d);
  };
  el.set(value);
  if (opts.disabled) el.setDisabled(true);
  return el;
}

export interface StepperOptions {
  min: number;
  max: number;
  step?: number;
  disabled?: boolean;
  ariaLabel?: string;
}

export type Stepper = HTMLElement & WithDisabled & { set(v: number): void };

/** NSStepper's autorepeat: the first repeat after half a second, then ten a second. */
const STEP_DELAY = 500;
const STEP_EVERY = 100;

/**
 * A macOS Stepper: two small stacked arrow buttons. It shows no value of its
 * own — put a label beside it ("10 s"). Clamped to min…max.
 *
 * As NSStepper does, an arrow held down keeps stepping, and the stepper is one
 * stop for Tab that the Up and Down keys step.
 */
export function stepper(value: number, opts: StepperOptions, onChange: (v: number) => void): Stepper {
  let v = value;
  // Tab skips the halves: the keyboard goes to the stepper as a whole.
  const up = h("button", { type: "button", class: "mc-stepper-up", tabindex: "-1", "aria-label": "+" },
    symbol("chevron.up", 12));
  const down = h("button", { type: "button", class: "mc-stepper-down", tabindex: "-1", "aria-label": "−" },
    symbol("chevron.down", 12));
  const el = h("span", {
    class: "mc-stepper", role: "spinbutton", tabindex: "0",
    "aria-valuemin": String(opts.min), "aria-valuemax": String(opts.max),
  }, up, down) as Stepper;
  if (opts.ariaLabel) el.setAttribute("aria-label", opts.ariaLabel);
  const step = opts.step ?? 1;
  const off = () => el.classList.contains("mc-disabled");
  const paint = () => {
    up.disabled = off() || v >= opts.max;
    down.disabled = off() || v <= opts.min;
    el.setAttribute("aria-valuenow", String(v));
    el.tabIndex = off() ? -1 : 0;
  };
  /** One step; false when it is already at that end. */
  const move = (delta: number): boolean => {
    const next = Math.max(opts.min, Math.min(opts.max, v + delta));
    if (next === v) return false;
    v = next;
    paint();
    onChange(v);
    return true;
  };

  let timer: number | undefined;
  const release = () => {
    window.clearTimeout(timer);
    window.clearInterval(timer);
    timer = undefined;
  };
  const hold = (b: HTMLButtonElement, delta: number) => {
    // A step on the press itself, so the click that follows must not step again.
    b.addEventListener("pointerdown", (e) => {
      if (e.button !== 0 || b.disabled) return;
      release();
      if (!move(delta)) return;
      timer = window.setTimeout(() => {
        timer = window.setInterval(() => { if (!move(delta)) release(); }, STEP_EVERY);
      }, STEP_DELAY);
    });
    for (const type of ["pointerup", "pointercancel", "pointerleave"]) b.addEventListener(type, release);
    // Space or Return on a half that has focus is a click with no press before it.
    b.addEventListener("click", (e) => { if (e.detail === 0) move(delta); });
  };
  hold(up, step);
  hold(down, -step);
  el.addEventListener("keydown", (e) => {
    if (off() || (e.key !== "ArrowUp" && e.key !== "ArrowDown")) return;
    // Not the pane's scroll.
    e.preventDefault();
    move(e.key === "ArrowUp" ? step : -step);
  });

  el.set = (n) => { v = n; paint(); };
  el.setDisabled = (d) => {
    if (d) release();
    el.classList.toggle("mc-disabled", d);
    el.setAttribute("aria-disabled", String(d));
    paint();
  };
  if (opts.disabled) el.setDisabled(true);
  paint();
  return el;
}

// ── Status ────────────────────────────────────────────────────────────────────

export type StatusChip = HTMLElement & { set(text: string, color: string): void };

/** A coloured dot and a short state, e.g. a service's "Connected as …" on the right of its header. */
export function statusChip(text: string, color: string): StatusChip {
  const dot = h("i", { class: "mc-chip-dot" });
  const textEl = h("span", {});
  const el = h("span", { class: "mc-chip" }, dot, textEl) as StatusChip;
  el.set = (tx, c) => { textEl.textContent = tx; dot.style.background = c; };
  el.set(text, color);
  return el;
}

/** A plain coloured dot, `size` px (the pill rows' 10). */
export function colorDot(color: string, size = 10): HTMLElement {
  return h("i", { class: "mc-dot", style: `width:${size}px;height:${size}px;background:${color}` });
}

// ── Shortcut recorder ─────────────────────────────────────────────────────────

export interface ShortcutRecorderOptions {
  disabled?: boolean;
}

export type ShortcutRecorder = HTMLButtonElement & WithDisabled & {
  /** Shows `accelerator` (Tauri form, "Ctrl+Alt+X") without calling onChange. */
  set(accelerator: string): void;
};

/**
 * The Mac's ShortcutRecorderButton: the shortcut in 11px monospace on a small
 * bordered field; click it and the next chord pressed is the shortcut ("Press
 * keys…" meanwhile, the field tinted with the accent). Escape on its own, or
 * clicking away, keeps the old one. `onChange` gets the Tauri accelerator.
 */
export function shortcutRecorder(
  accelerator: string, onChange: (accelerator: string) => void, opts: ShortcutRecorderOptions = {},
): ShortcutRecorder {
  let value = accelerator;
  let recording = false;
  const el = h("button", { type: "button", class: "mc-shortcut", text: shortcutLabel(value) }) as ShortcutRecorder;
  const stop = () => {
    if (!recording) return;
    recording = false;
    window.removeEventListener("keydown", onKey, true);
    el.classList.remove("recording");
    el.textContent = shortcutLabel(value);
  };
  const onKey = (e: KeyboardEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (e.code === "Escape" && !e.ctrlKey && !e.altKey && !e.metaKey) {
      stop();
      return;
    }
    const next = acceleratorFrom(e);
    if (!next) return;
    value = next;
    stop();
    onChange(next);
  };
  el.addEventListener("click", () => {
    if (recording) return;
    recording = true;
    el.classList.add("recording");
    el.textContent = t("Press keys…");
    window.addEventListener("keydown", onKey, true);
  });
  el.addEventListener("blur", stop);
  el.set = (acc) => { value = acc; if (!recording) el.textContent = shortcutLabel(acc); };
  el.setDisabled = (d) => { if (d) stop(); el.disabled = d; };
  if (opts.disabled) el.setDisabled(true);
  return el;
}
