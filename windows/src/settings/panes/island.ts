// Dynamic Island — the Mac's IslandSettingsView: four tabs over the one object
// (Layout, Content, Activity, Behavior), the remembered tab, the ring editor
// (IslandRingEditor), Christmas in season, the player's skip distances and
// where the island sits. One Windows-only group, kept by the owner, sits under
// Content: the site the globe opens.
//
// "Big screen" (Layout) is not here yet: Windows has no setting for the large
// island's size, and that group comes with it (docs/parity W-27, Phase 3).

import "./island.css";
import { t } from "../../core/i18n";
import {
  INTEGRATION_AGENTS, SETTINGS_RANGES, edgeButtonsFor, type AgentTask,
} from "../../core/state";
import { POSITIONS, isFree } from "../../core/anchor";
import { EDGE_ACTIONS, edgeAction, type EdgeButton, type EdgeSide } from "../../core/edgeRing";
import { isFestiveSeason } from "../../mochi/festive";
import { h, clear, svg } from "../../views/dom";
import { ICONS } from "../../views/icons";
import { PILL_LOGOS, mattermostMark } from "../../views/logos";
import { boxedSymbol } from "../icons";
import {
  checkbox, closeMenus, colorDot, groupBox, hint, hugBoxes, iconButton, inlineRow, label, menuButton,
  popup, segmented, spacer, stack, stepper, textField,
  type MenuEntry, type PopupOption,
} from "../controls";
import { boot, save, setStatus, settings, subscribe } from "../store";
import { rerenderPane } from "../shell";

// ── The tabs ──────────────────────────────────────────────────────────────────

type Tab = "layout" | "content" | "activity" | "behavior";

/** IslandSettingsView.Tab, in its order. The titles are catalogue keys. */
const TABS: readonly { id: Tab; title: string }[] = [
  { id: "layout", title: "Layout" },
  { id: "content", title: "Content" },
  { id: "activity", title: "Activity" },
  { id: "behavior", title: "Behavior" },
];

/** The Mac's `@AppStorage("islandTab")`, under the same name. */
const TAB_KEY = "islandTab";

function isTab(value: string | null): value is Tab {
  return TABS.some((x) => x.id === value);
}

/**
 * The tab to open on: `?islandTab=` (the preview grid's, as the Mac's capture
 * script sets NOTCHY_ISLAND_TAB), else the one remembered, else Layout. Read
 * once; from then on the module keeps it, so a repaint stays where you are.
 */
function initialTab(): Tab {
  const asked = new URLSearchParams(location.search).get("islandTab");
  if (isTab(asked)) return asked;
  let stored: string | null = null;
  try { stored = localStorage.getItem(TAB_KEY); } catch { /* private mode */ }
  return isTab(stored) ? stored : "layout";
}

let tab: Tab = initialTab();

// ── What each button on the border is ─────────────────────────────────────────

/** Pills, in the catalogue's order, with Now Playing only where it can play. */
function availablePills(): AgentTask[] {
  return INTEGRATION_AGENTS.filter((p) => p.id !== "integration_music" || boot.media);
}

function pillDef(id: string): AgentTask | undefined {
  return INTEGRATION_AGENTS.find((p) => p.id === id);
}

/**
 * The name a button goes by. The tables keep their English, because the Swift
 * side is compared against them value for value; it is translated here, where
 * it is drawn.
 */
function nameOf(action: string): string {
  return t(pillDef(action)?.name ?? edgeAction(action)?.title ?? action);
}

function colorOf(action: string): string {
  return pillDef(action)?.color ?? edgeAction(action)?.color ?? "#8E939C";
}

/**
 * The symbol each pill and built-in wears, as the island draws it on its
 * border (RING_MARKS in island/island.ts). Mattermost and Ato draw their own
 * marks instead, and WhatsApp's phone.bubble.fill and Now Playing's
 * music.note are settings/icons.ts's.
 */
const MARKS: Readonly<Record<string, string>> = {
  integration_claude: ICONS.code,
  integration_notifications: ICONS.bell,
  agents: ICONS.sparkles,
  clipboard: ICONS.clipboard,
  timer: ICONS.timer,
  settings: ICONS.gear,
  site: ICONS.globe,
  hydration: ICONS.drop,
  agenda: ICONS.calendar,
};

/**
 * The row's mark, in a 16px frame: a pill's own logo at 13px, in its own
 * colours, or the symbol in the secondary colour — the row's `logo.view(side:
 * 13, detail: .simplified)` or `Image(systemName:)` at 11pt.
 */
function markFor(action: string): HTMLElement {
  const frame = h("span", { class: "ip-mark" });
  const logo = PILL_LOGOS[action];
  if (action === "integration_mattermost") {
    // MattermostLogo's two inks: navy on a light window, white on a dark one.
    frame.classList.add("ip-mark-mm");
    frame.append(mattermostMark(13, "currentColor"));
  } else if (logo) {
    frame.append(logo(13));
  } else if (action === "integration_whatsapp") {
    // The Mac's Image(systemName:) at 11pt: 12x11 of ink, as on the Mac.
    frame.append(boxedSymbol("phone.bubble.fill", 11));
  } else if (action === "integration_music") {
    // music.note, one eighth note — not the pair of the player's own mark.
    frame.append(boxedSymbol("music.note", 11));
  } else {
    // circle.fill, the Mac's fallback for an id it cannot name.
    frame.append(svg(MARKS[action] ?? "M12 4a8 8 0 1 0 0 16a8 8 0 1 0 0-16z", 13));
  }
  return frame;
}

// ── Buttons around the island ─────────────────────────────────────────────────

/** IslandEdgeSide.allCases, in its order, and the word each is shown as. */
const SIDES: readonly EdgeSide[] = ["left", "right", "bottom"];
const SIDE_TITLE: Readonly<Record<EdgeSide, string>> = {
  left: "Left",
  right: "Right",
  bottom: "Bottom",
};

/**
 * What the ring shows: the arrangement chosen here, or — until one has been
 * — the one dealt from the active pills. The island draws from the same rule
 * (`edgeButtonsFor` in core/state.ts), so the two cannot disagree.
 */
function currentRing(): EdgeButton[] {
  return edgeButtonsFor(settings);
}

/**
 * Moves button `index` within its own side. Order inside a side is the order
 * in the list, so this swaps it with the neighbour that shares its side. Null
 * when it is already at that end.
 */
function moved(list: readonly EdgeButton[], index: number, delta: number): EdgeButton[] | null {
  const side = list[index].side;
  const neighbours = list.flatMap((b, i) => (b.side === side ? [i] : []));
  const to = neighbours.indexOf(index) + delta;
  if (to < 0 || to >= neighbours.length) return null;
  const next = [...list];
  const other = neighbours[to];
  [next[index], next[other]] = [next[other], next[index]];
  return next;
}

/** A control of the editor — `action:control`, or "add" — and the row it is on. */
interface FocusSpot {
  key: string;
  row: number;
}

/** Which control had the keyboard, so a repaint can hand it back. */
function focusedSpot(root: HTMLElement): FocusSpot | null {
  const active = document.activeElement as HTMLElement | null;
  const el = active && root.contains(active) ? active.closest<HTMLElement>("[data-ring]") : null;
  if (!el?.dataset.ring) return null;
  const rows = [...root.querySelectorAll(".ip-ring-row")];
  const row = el.closest(".ip-ring-row");
  return { key: el.dataset.ring, row: row ? rows.indexOf(row) : -1 };
}

/**
 * Puts the keyboard back where it was: on the same control of the same button,
 * or — that button just went — on the same control of the row that took its
 * place, or on "+ Add a button".
 */
function refocus(root: HTMLElement, spot: FocusSpot | null): void {
  if (!spot) return;
  const same = root.querySelector<HTMLElement>(`[data-ring="${CSS.escape(spot.key)}"]`);
  if (same) {
    same.focus();
    return;
  }
  const control = spot.key.slice(spot.key.lastIndexOf(":") + 1);
  const rows = root.querySelectorAll<HTMLElement>(".ip-ring-row");
  const row = rows[Math.min(spot.row, rows.length - 1)];
  (row?.querySelector<HTMLElement>(`[data-ring$=":${CSS.escape(control)}"]`)
    ?? root.querySelector<HTMLElement>('[data-ring="add"]'))?.focus();
}

/**
 * IslandRingEditor: a list rather than a drag-and-drop miniature — it is
 * keyboard-reachable, it is what a drag would have to fall back to anyway, and
 * it makes the feature usable without a gesture to get wrong.
 *
 * A side is a contract value and keeps its name, but on this platform "Bottom"
 * is the side away from the screen edge the island rests on — above the island
 * when it sits at the bottom of the screen — and a left or right button moves
 * inward when the island is flush against that side (core/edgeRing.ts), so
 * nothing on the border can end up off the screen.
 */
function ringEditor(): HTMLElement {
  const editor = stack(6);
  editor.classList.add("ip-ring");
  let painted = "";

  function store(next: EdgeButton[], spot = focusedSpot(editor)): void {
    settings.islandEdgeButtons = next;
    void save();
    paint(spot);
  }

  /** Whichever side has fewer, so a ring fills out evenly without asking. */
  function add(action: string): void {
    const ring = currentRing();
    const left = ring.filter((b) => b.side === "left").length;
    const right = ring.filter((b) => b.side === "right").length;
    // The menu that was used has gone; the keyboard goes back to its button.
    store([...ring, { action, side: left <= right ? "left" : "right" }], { key: "add", row: -1 });
  }

  function row(ring: EdgeButton[], index: number): HTMLElement {
    const button = ring[index];
    const name = nameOf(button.action);
    const key = (control: string) => `${button.action}:${control}`;

    const side = popup<EdgeSide>(
      SIDES.map((s) => ({ value: s, label: t(SIDE_TITLE[s]) })),
      button.side,
      (next) => store(ring.map((b, i) => (i === index ? { ...b, side: next } : b))),
      { width: 92, ariaLabel: name },
    );
    side.select.dataset.ring = key("side");

    // Bare glyphs, as the Mac's are: no tooltip, but a name for a screen reader.
    const glyph = (symbolName: string, control: string, text: string, onClick: () => void) => {
      const b = iconButton(symbolName, onClick);
      b.setAttribute("aria-label", text);
      b.dataset.ring = key(control);
      return b;
    };
    const up = glyph("chevron.up", "up", t("Move up"), () => {
      const next = moved(ring, index, -1);
      if (next) store(next);
    });
    const down = glyph("chevron.down", "down", t("Move down"), () => {
      const next = moved(ring, index, 1);
      if (next) store(next);
    });
    const remove = glyph("minus.circle", "remove", t("Remove"), () =>
      store(ring.filter((_, i) => i !== index)));

    const el = inlineRow(
      colorDot(colorOf(button.action), 10),
      markFor(button.action),
      h("span", { class: "ip-ring-name", text: name }),
      spacer(),
      side, up, down, remove,
    );
    el.classList.add("ip-ring-row");
    return el;
  }

  /** "+ Add a button": the built-ins not on the border yet, a divider, then the pills. */
  function addMenu(ring: EdgeButton[]): HTMLElement | null {
    const taken = new Set(ring.map((b) => b.action));
    const actions = EDGE_ACTIONS.filter((a) => !taken.has(a.id));
    const pills = availablePills().filter((p) => !taken.has(p.id));
    if (actions.length === 0 && pills.length === 0) return null;
    const entries: MenuEntry[] = actions.map((a) => ({ label: t(a.title), onSelect: () => add(a.id) }));
    if (actions.length > 0 && pills.length > 0) entries.push("separator");
    for (const p of pills) entries.push({ label: t(p.name), onSelect: () => add(p.id) });
    const menu = menuButton(t("Add a button"), entries, { symbol: "plus" });
    menu.classList.add("ip-add");
    menu.dataset.ring = "add";
    return menu;
  }

  function paint(spot = focusedSpot(editor)): void {
    const ring = currentRing();
    // The broadcast of a change made here comes back as "settings" too, and
    // rebuilding identical rows would only take the keyboard away.
    const signature = JSON.stringify(ring);
    if (signature === painted) return;
    painted = signature;

    // An open "+ Add a button" lists what was free before this change.
    closeMenus();
    clear(editor);
    if (ring.length === 0) editor.append(hint(t("No buttons yet.")));
    ring.forEach((_, i) => editor.append(row(ring, i)));
    const menu = addMenu(ring);
    if (menu) editor.append(menu);
    refocus(editor, spot);
  }

  subscribe("settings", () => paint());
  paint();
  return editor;
}

// ── Layout ────────────────────────────────────────────────────────────────────

/**
 * Snow and the Christmas music, only while they are on offer: a switch for
 * something that is not there in March is a switch that appears to do nothing.
 */
function christmasBox(): HTMLElement {
  const snow = checkbox(t("Snow on the island"), settings.islandSnow, (on) => {
    settings.islandSnow = on;
    void save();
  });
  const music = checkbox(t("Christmas music when Notchy starts"), settings.christmasMusic, (on) => {
    settings.christmasMusic = on;
    void save();
  });
  subscribe("settings", () => {
    snow.set(settings.islandSnow);
    music.set(settings.christmasMusic);
  });
  return groupBox({ title: t("Christmas"), gap: 8 },
    snow,
    hint(t("A little snow falls faintly behind what the island shows and settles along its "
      + "bottom edge until January 6. It gets deeper while the island is open, and the "
      + "pointer sweeps it aside. It never takes a click.")),
    music,
    hint(t("Notchy plays its Christmas music as it says hello, until January 6. The Christmas "
      + "album on the left of the player plays it again after anything else, whichever way "
      + "this is set.")),
  );
}

function layoutTab(): HTMLElement[] {
  const groups: HTMLElement[] = [
    groupBox({ title: t("Buttons around the island"), gap: 10 },
      hint(t("Anything here sits on the island's border, so one click opens it without "
        + "opening the island first.")),
      ringEditor(),
    ),
  ];
  if (import.meta.env.DEV || isFestiveSeason()) groups.push(christmasBox());
  return groups;
}

// ── Content ───────────────────────────────────────────────────────────────────

/**
 * One of the player's two jumps: the name, then "10 s" and a stepper over
 * `range` (1 to 120). The number is drawn on the button, so it is a label as
 * well as a distance.
 */
function skipRow(
  title: string,
  range: readonly [number, number],
  get: () => number,
  set: (seconds: number) => void,
): HTMLElement {
  const value = h("span", { class: "ip-skip-value" });
  const show = () => { value.textContent = t("%lld s", get()); };
  const [min, max] = range;
  const control = stepper(get(), { min, max, ariaLabel: t(title) }, (seconds) => {
    set(seconds);
    show();
    void save();
  });
  subscribe("settings", () => {
    control.set(get());
    show();
  });
  show();
  return inlineRow(label(t(title)), spacer(), value, control);
}

/**
 * How far the player's two round buttons jump. Apart, because they are usually
 * wanted apart — a longer jump forward clears an ad, a shorter one back
 * catches what you missed. Only where there is a player to jump in.
 */
function nowPlayingBox(): HTMLElement {
  return groupBox({ title: t("Now Playing"), gap: 8 },
    hint(t("How far the player's two round buttons jump. They are set apart because they are "
      + "usually wanted apart — a longer jump forward clears an ad, a shorter one back "
      + "catches what you missed.")),
    skipRow("Skip back", SETTINGS_RANGES.skipBackSeconds,
      () => settings.skipBackSeconds, (s) => { settings.skipBackSeconds = s; }),
    skipRow("Skip forward", SETTINGS_RANGES.skipForwardSeconds,
      () => settings.skipForwardSeconds, (s) => { settings.skipForwardSeconds = s; }),
    // The Mac's sentence goes on about the system's numbered dials; this
    // player draws every number onto the same dial (views/nowplaying.ts).
    hint(t("The number is drawn on the button.")),
  );
}

/**
 * The site behind the globe. Windows only — the Mac's is fixed — and kept by
 * the owner. Anything that is not a web address would have nothing to load,
 * so it is refused rather than saved; an empty field is allowed, and the site
 * then says on its card that there is no address to open. The page is loaded
 * when it is opened, so a new one takes over the next time the site is.
 */
function siteBox(): HTMLElement {
  const field = textField(settings.siteUrl, (raw) => {
    const next = raw.trim();
    if (next === settings.siteUrl) return;
    if (next !== "" && !/^https?:\/\//i.test(next)) {
      setStatus(`❌ ${t("That needs to start with http:// or https://.")}`);
      return;
    }
    settings.siteUrl = next;
    field.value = next;
    setStatus(`✓ ${t("Saved. The new page loads the next time the site is opened.")}`);
    void save();
  }, { type: "url", placeholder: "https://example.com/", ariaLabel: t("Site") });
  subscribe("settings", () => {
    if (document.activeElement !== field) field.value = settings.siteUrl;
  });
  // Where its links go is the Mac's rule now — any web link stays in the
  // island — so there is nothing left to warn about.
  return groupBox({ title: t("Site"), gap: 8 },
    field,
    hint(t("The page the globe on the island opens.")),
  );
}

function contentTab(): HTMLElement[] {
  const groups: HTMLElement[] = [
    groupBox({ title: t("What the island carries"), gap: 8 },
      hint(t("Which pills are on. A pill does not have to be on to have a button — a button "
        + "opens its app or its dashboard either way — but only the ones that are on report "
        + "what they are doing.")),
      hint(t("Set these under Active pills.")),
    ),
  ];
  if (boot.media) groups.push(nowPlayingBox());
  groups.push(siteBox());
  return groups;
}

// ── Activity ──────────────────────────────────────────────────────────────────

function activityTab(): HTMLElement[] {
  return [
    groupBox({ title: t("What it shows by itself"), gap: 8 },
      hint(t("Home, auto-close and how long it waits before it decides you have gone — these "
        + "still live under General for now.")),
    ),
  ];
}

// ── Behavior ──────────────────────────────────────────────────────────────────

/**
 * The six spots, and — for an island that was dragged somewhere — "Where you
 * dropped it", which is not one of the six: a popup with no matching entry
 * shows blank. Picking one of the six is how you put it back on an edge.
 * POSITIONS keeps its English (tests/island-anchor-parity.ts compares it with
 * IslandAnchor.swift); it is translated here, where it is drawn.
 */
function positionOptions(): PopupOption<string>[] {
  const options: PopupOption<string>[] = POSITIONS.map(([value, text]) => ({ value, label: t(text) }));
  if (isFree(settings.position)) options.push({ value: settings.position, label: t("Where you dropped it") });
  return options;
}

function behaviorTab(): HTMLElement[] {
  const position = popup<string>(positionOptions(), settings.position, (value) => {
    settings.position = value;
    position.setOptions(positionOptions());
    position.set(value);
    void save();
  }, { label: t("Island sits at") });
  subscribe("settings", () => {
    position.setOptions(positionOptions());
    position.set(settings.position);
  });
  return [
    groupBox({ title: t("Where it sits"), gap: 8 },
      position,
      hint(t("Hold the resting island for two seconds and it comes unstuck: it follows the "
        + "pointer, across displays, until you let go. Drop it near an edge and it settles "
        + "into that corner.")),
    ),
    groupBox({ title: t("Opening"), gap: 8 },
      hint(t("Which display the island lives on, how tall it rests and the shortcut that calls "
        + "it still live under General for now.")),
    ),
  ];
}

// ── The pane ──────────────────────────────────────────────────────────────────

/** The Dynamic Island pane. */
export function render(): Node[] {
  const tabs = segmented(
    TABS.map((x) => ({ value: x.id, label: t(x.title) })),
    tab,
    (next) => {
      const hadFocus = tabs.contains(document.activeElement);
      tab = next;
      try { localStorage.setItem(TAB_KEY, next); } catch { /* private mode */ }
      rerenderPane();
      if (hadFocus) {
        document.querySelector<HTMLElement>(".ip-tabs .mc-seg-item.on")?.focus();
      }
    },
    { fullWidth: true, ariaLabel: t("Dynamic Island") },
  );
  tabs.classList.add("ip-tabs");

  const groups = tab === "content" ? contentTab()
    : tab === "activity" ? activityTab()
      : tab === "behavior" ? behaviorTab()
        : layoutTab();

  // The segmented control and the tab's groups, 12 apart — the spacing of
  // IslandSettingsView's own VStack, not the 18 between a pane's groups.
  const body = stack(12, tabs, ...groups);
  hugBoxes(body, groups);
  return [body];
}
