// Hydration on the island — port of HydrationView.swift.
//
// Two views. `hydration` is the tab: a glass you click when you drink, today's
// count against the goal, the portions and the last few glasses — or, once the
// goal is reached with the streak on, the week of frozen days. `sip` is the
// reminder that opens the island: one question, two buttons.
//
// Everything is read from `Hydration` in `sync()`, which the island calls
// whenever the store says something changed. Nothing here keeps a clock, and
// every button is built once: rebuilding one between a mouse-down and a
// mouse-up would swallow the click.

import { h, svg, clear, dot } from "./dom";
import { ICONS } from "./icons";
import { btn, card, type ViewActions, type ViewHost } from "./views";
import { HYDRATION, hydrationKeyDate, type HydrationDot, type HydrationEntry } from "../core/hydration";
import { Hydration, type HydrationPrompt } from "../core/hydrationStore";
import { amountText, clockText, durationText, reducedMotion } from "../core/hydrationText";
import { language, t } from "../core/i18n";

const LIQUID = "#22D3EE";
/** The water loses its colour while reminders are paused. */
const LIQUID_PAUSED = "#94A3B8";
/** The ice of a frozen day. */
const ICE = "#9EDCFF";
const WASH_WATER = "rgba(34,211,238,0.38)";
const WASH_REACHED = "rgba(52,211,153,0.5)";
const WASH_ICE = "rgba(125,211,252,0.36)";
const WASH_NONE = "rgba(0,0,0,0)";

/** The streak's marks: the next one is what the small bar fills towards. */
const STREAK_MARKS = [3, 7, 14, 30, 60, 100, 365];

// ── The snowflake ─────────────────────────────────────────────────────────────

// Six arms and a hollow hexagon, drawn about 0,0 in a 108-wide box and filled.
// Ice rather than the usual flame: a day that counted is a day frozen.
const SNOWFLAKE =
  "M3 -16 L2.2 -23.8 L11 -30 L11 -36 L2.5 -30.5 L2.5 -34.5 L8.5 -38.5 L7 -43.5 L2.5 -41.5 L2.5 -44.5 L4.3 -47 L2.7 -50.3 L0 -52.5 L-2.7 -50.3 L-4.3 -47 L-2.5 -44.5 L-2.5 -41.5 L-7 -43.5 L-8.5 -38.5 L-2.5 -34.5 L-2.5 -30.5 L-11 -36 L-11 -30 L-2.2 -23.8 L-3 -16 Z "
  + "M15.4 -5.4 L21.7 -9.9 L31.5 -5.5 L36.7 -8.5 L27.7 -13.1 L31.1 -15.1 L37.6 -11.9 L41.2 -15.7 L37.2 -18.6 L39.8 -20.1 L42.9 -19.8 L44.9 -22.8 L45.5 -26.3 L42.2 -27.5 L38.6 -27.2 L37.3 -24.4 L34.7 -22.9 L34.2 -27.8 L29.1 -26.6 L28.6 -19.4 L25.2 -17.4 L25.7 -27.5 L20.5 -24.5 L19.4 -13.8 L12.4 -10.6 Z "
  + "M12.4 10.6 L19.4 13.8 L20.5 24.5 L25.7 27.5 L25.2 17.4 L28.6 19.4 L29.1 26.6 L34.2 27.8 L34.7 22.9 L37.3 24.4 L38.6 27.2 L42.2 27.5 L45.5 26.2 L44.9 22.8 L42.9 19.8 L39.8 20.1 L37.2 18.6 L41.2 15.7 L37.6 11.9 L31.1 15.1 L27.7 13.1 L36.7 8.5 L31.5 5.5 L21.7 9.9 L15.4 5.4 Z "
  + "M-3 16 L-2.2 23.8 L-11 30 L-11 36 L-2.5 30.5 L-2.5 34.5 L-8.5 38.5 L-7 43.5 L-2.5 41.5 L-2.5 44.5 L-4.3 47 L-2.7 50.3 L0 52.5 L2.7 50.3 L4.3 47 L2.5 44.5 L2.5 41.5 L7 43.5 L8.5 38.5 L2.5 34.5 L2.5 30.5 L11 36 L11 30 L2.3 23.8 L3 16 Z "
  + "M-15.4 5.4 L-21.7 9.9 L-31.5 5.5 L-36.7 8.5 L-27.7 13.1 L-31.1 15.1 L-37.6 11.9 L-41.2 15.7 L-37.2 18.6 L-39.8 20.1 L-42.9 19.8 L-44.9 22.8 L-45.5 26.3 L-42.2 27.5 L-38.6 27.2 L-37.3 24.4 L-34.7 22.9 L-34.2 27.8 L-29.1 26.6 L-28.6 19.4 L-25.2 17.4 L-25.7 27.5 L-20.5 24.5 L-19.4 13.8 L-12.4 10.6 Z "
  + "M-12.4 -10.6 L-19.4 -13.8 L-20.5 -24.5 L-25.7 -27.5 L-25.2 -17.4 L-28.6 -19.4 L-29.1 -26.6 L-34.2 -27.8 L-34.7 -22.9 L-37.3 -24.4 L-38.6 -27.2 L-42.2 -27.5 L-45.5 -26.3 L-44.9 -22.8 L-42.9 -19.8 L-39.8 -20.1 L-37.2 -18.6 L-41.2 -15.7 L-37.6 -11.9 L-31.1 -15.1 L-27.7 -13.1 L-36.7 -8.5 L-31.5 -5.5 L-21.7 -9.9 L-15.4 -5.4 Z "
  + "M18.9 0 L9.4 16.3 L-9.4 16.3 L-18.9 0 L-9.4 -16.3 L9.4 -16.3 Z "
  + "M4.9 -8.4 L-4.9 -8.4 L-9.8 0 L-4.9 8.4 L4.9 8.4 L9.8 0 Z";

const SVG_NS = "http://www.w3.org/2000/svg";

function snowflake(size: number): SVGSVGElement {
  const el = document.createElementNS(SVG_NS, "svg");
  el.setAttribute("viewBox", "-54 -54 108 108");
  el.setAttribute("width", String(size));
  el.setAttribute("height", String(size));
  el.setAttribute("aria-hidden", "true");
  const p = document.createElementNS(SVG_NS, "path");
  p.setAttribute("d", SNOWFLAKE);
  // Non-zero, the default: the hexagon's inner outline runs the other way
  // round, which is what leaves the hole in the middle.
  p.setAttribute("fill", "currentColor");
  el.append(p);
  return el;
}

// ── The glass ─────────────────────────────────────────────────────────────────

/** Where the water can be: the tumbler's cavity, a little inside its wall. */
const CAVITY = "M12.6 8 L87.4 8 L77.9 104.6 Q77.2 111.6 70 111.6 L30 111.6 Q22.8 111.6 22.1 104.6 Z";
/** How far down the liquid sits when the glass is empty, and how far it rises. */
const LEVEL_EMPTY = 107.6;
const LEVEL_TRAVEL = 93.6;
/** The wave runs this long after a change, then lies down over the rest. */
const STIR_MS = 1500;
const SETTLE_MS = 3300;

let glassSerial = 0;

export interface Glass {
  el: HTMLElement;
  /** `pulse` is the store's log counter: when it moves, a drop falls. */
  set(level: number, pulse?: number): void;
  setColor(color: string): void;
}

/**
 * A tapered tumbler, with the liquid clipped to its cavity.
 *
 * The wave is a CSS animation that is paused whenever the water is not
 * moving: it runs for a second and a half after a change, lies flat over the
 * next two, and stops. A glass nobody is touching costs nothing.
 *
 * `mini` is the 12 px one on the closed island: a thicker wall, no shine and
 * no motion at all.
 */
export function buildGlass(width: number, mini = false): Glass {
  // Every instance needs ids of its own, or the second glass on the page would
  // be clipped by the first one's cavity.
  const id = `hy-glass-${++glassSerial}`;
  const wall = mini ? 8 : 2.4;
  const el = h("div", { class: mini ? "hy-glass hy-mini" : "hy-glass", "aria-hidden": "true" });
  el.style.width = `${width}px`;
  el.innerHTML = `
<svg viewBox="0 0 100 120" width="100%" height="100%">
  <defs>
    <clipPath id="${id}-c"><path d="${CAVITY}"/></clipPath>
    <linearGradient id="${id}-g" x1="0" y1="0" x2="0" y2="1">
      <stop class="hy-liquid-stop" offset="0" stop-opacity=".95"/>
      <stop class="hy-liquid-stop" offset="1" stop-opacity=".6"/>
    </linearGradient>
  </defs>
  <path d="${CAVITY}" fill="#fff" fill-opacity=".05"/>
  <g clip-path="url(#${id}-c)">
    <g class="hy-level hy-move">
      <rect x="-10" y="4" width="120" height="150" fill="url(#${id}-g)"/>
      <rect x="-10" y="4" width="120" height="1.3" fill="#fff" fill-opacity=".3"/>
      <g transform="translate(0 4)">
        <g class="hy-amp hy-move">
          <g class="hy-wave back hy-move"><path class="hy-liquid" fill-opacity=".45" d="M-50 -6.5 q12.5 -3.4 25 0 t25 0 t25 0 t25 0 t25 0 t25 0 t25 0 t25 0 t25 0 V0.5 H-50 Z"/></g>
          <g class="hy-wave hy-move"><path class="hy-liquid" fill-opacity=".96" d="M-50 -4 q12.5 -3.2 25 0 t25 0 t25 0 t25 0 t25 0 t25 0 t25 0 t25 0 t25 0 V0.5 H-50 Z"/></g>
        </g>
      </g>
      <g class="hy-bubbles hy-move" fill="#fff">
        <circle class="hy-move" cx="36" cy="52" r="2.2" fill-opacity=".55"/>
        <circle class="hy-move" cx="54" cy="64" r="1.6" fill-opacity=".5"/>
        <circle class="hy-move" cx="66" cy="48" r="1.3" fill-opacity=".5"/>
      </g>
      <g transform="translate(50 4)">
        <ellipse class="hy-ripple hy-move" cx="0" cy="0" rx="15" ry="2.6" fill="none" stroke="#fff" stroke-opacity=".75" stroke-width="1.2"/>
      </g>
    </g>
  </g>
  <path d="M9 6 L19.6 105.5 Q20.7 115 30.5 115 L69.5 115 Q79.3 115 80.4 105.5 L91 6" fill="none" stroke="#fff" stroke-opacity=".36" stroke-width="${wall}" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M9 6 L91 6" fill="none" stroke="#fff" stroke-opacity=".16" stroke-width="${wall}" stroke-linecap="round"/>
  ${mini ? "" : `<path d="M19.5 18 L25.8 82" fill="none" stroke="#fff" stroke-opacity=".24" stroke-width="3.2" stroke-linecap="round"/>
  <path d="M83.2 15 L81.6 31" fill="none" stroke="#fff" stroke-opacity=".14" stroke-width="2.4" stroke-linecap="round"/>
  <path class="hy-drop hy-liquid hy-move" d="M50 -7 C54 -1 56.5 2.5 56.5 6 A6.5 6.5 0 0 1 43.5 6 C43.5 2.5 46 -1 50 -7 Z"/>`}
</svg>`;

  let shown: number | null = null;
  let seen = 0;
  let stirring: number | undefined;
  let settling: number | undefined;

  function place(level: number) {
    el.style.setProperty("--hy-y", `${(LEVEL_EMPTY - LEVEL_TRAVEL * level).toFixed(2)}px`);
  }

  /** The water moved: wave, then calm — and a drop, if a glass was logged. */
  function stir(dropped: boolean, wet: boolean) {
    window.clearTimeout(stirring);
    window.clearTimeout(settling);
    // With nothing in the glass there is no surface to make a wave on.
    el.classList.toggle("agitated", wet);
    el.classList.add("settling");
    if (dropped) {
      // Off, a reflow, on again: the only way to run a finished animation twice.
      el.classList.remove("dropping");
      void el.offsetWidth;
      el.classList.add("dropping");
    }
    stirring = window.setTimeout(() => el.classList.remove("agitated"), STIR_MS);
    settling = window.setTimeout(() => el.classList.remove("settling", "dropping"), SETTLE_MS);
  }

  return {
    el,
    set(level: number, pulse = 0) {
      const next = Math.min(1, Math.max(0, Number.isFinite(level) ? level : 0));
      if (shown === null) {
        // The first level is where the glass starts, not a change to animate:
        // without this it would fill from empty the first time its tab opened.
        el.classList.add("still");
        place(next);
        void el.offsetWidth;
        el.classList.remove("still");
        shown = next;
        seen = pulse;
        return;
      }
      if (next === shown && pulse === seen) return;
      const dropped = pulse > seen;
      shown = next;
      seen = pulse;
      place(next);
      // Reduced motion: the level changes at once (the stylesheet drops the
      // transition) and nothing else moves. The number confirms the log.
      if (mini || reducedMotion()) return;
      stir(dropped, next > 0);
    },
    setColor(color: string) {
      el.style.setProperty("--hy-liquid", color);
    },
  };
}

/**
 * The confetti around Mochi when the goal is first reached: a ring and nine
 * pieces, once. Placed where `VIEW_LAYOUTS` puts him in these two views — the
 * middle of the 108 px gutter, a little under the card's centre — and drawn
 * under his canvas, so the pieces fly out from behind him.
 */
function buildBurst(): { el: HTMLElement; fire(): void } {
  const pieces: [angle: number, size: number, color: string, round: boolean, delay: number][] = [
    [-80, 4, ICE, false, 0], [-52, 3.6, "#34D399", true, 60], [-24, 3.2, "#F5F6F8", false, 20],
    [4, 4, "#F472B6", true, 90], [30, 4, LIQUID, false, 40], [56, 3.4, ICE, true, 110],
    [82, 3.2, "#34D399", false, 70], [-108, 3, "#F5F6F8", true, 130], [108, 3, "#F472B6", true, 150],
  ];
  const el = h("div", { class: "hy-burst", "aria-hidden": "true" }, h("i", { class: "ring" }));
  for (const [angle, size, color, round, delay] of pieces) {
    el.append(h("span", { style: `transform:rotate(${angle}deg)` },
      h("i", {
        style: `left:${-size / 2}px;top:${-size / 2}px;width:${size}px;height:${size}px;`
          + `background:${color};border-radius:${round ? "50%" : "1px"};animation-delay:${delay}ms`,
      })));
  }
  return {
    el,
    fire() {
      if (reducedMotion()) return;
      el.classList.remove("go");
      void el.offsetWidth;
      el.classList.add("go");
    },
  };
}

// ── Small pieces ──────────────────────────────────────────────────────────────

/** "Log 250 ml. 850 ml of 2.2 L today." — what the glass says to a screen reader. */
function glassLabel(): string {
  const portion = amountText(Hydration.settings.portionML);
  const total = amountText(Hydration.total);
  return Hydration.goal.ml > 0
    ? t("Log %@. %@ of %@ today.", portion, total, amountText(Hydration.goal.ml))
    : t("Log %@. %@ today.", portion, total);
}

/** "850 ml of 2.2 L", or just the amount with no goal to measure against. */
function progressText(): string {
  const total = amountText(Hydration.total);
  return Hydration.goal.ml > 0 ? `${total} ${t("of %@", amountText(Hydration.goal.ml))}` : total;
}

function undoButton(onClick: () => void): HTMLButtonElement {
  return h("button", { class: "hy-undo", type: "button", onclick: onClick },
    svg(ICONS.undo, 13, { stroke: 2.4 }), h("span", { text: t("Undo") }));
}

/** M T W T F S S, in the app's language. 1 January 2024 was a Monday. */
function weekdayInitials(): string[] {
  const format = new Intl.DateTimeFormat(language(), { weekday: "narrow" });
  return [1, 2, 3, 4, 5, 6, 7].map((day) => format.format(new Date(2024, 0, day)));
}

function frozenThisWeek(week: HydrationDot[]): number {
  return week.filter((d) => d === "frozen").length;
}

/** The line under the counter: first match wins. */
function message(): string {
  const { goal } = Hydration;
  const total = Hydration.total;
  if (Hydration.paused) return t("Reminders paused. You can still log whenever you like.");
  if (goal.kind === "limit" && goal.ml > 0) {
    if (total >= goal.ml) return t("You have reached today's limit.");
    return t("Up to %@ today. Reminders stop before you get there.", amountText(goal.ml));
  }
  if (goalReached()) {
    if (total >= goal.ml + Hydration.settings.portionML) {
      return t("Today's goal is already reached. From here on, follow your thirst.");
    }
    const days = Hydration.streak.days;
    return Hydration.settings.streakEnabled && days >= 2
      ? t("Today's goal reached: %lld days in a row. Reminders rest until tomorrow.", days)
      : t("Today's goal reached. Reminders rest until tomorrow.");
  }
  if (total === 0) return t("Your glass is waiting. Tap it when you drink.");
  return t("Tap the glass whenever you drink. At your own pace.");
}

/** A goal to reach has been reached — an estimate or a number of one's own. */
function goalReached(): boolean {
  const { goal } = Hydration;
  return (goal.kind === "estimated" || goal.kind === "target") && goal.ml > 0 && Hydration.total >= goal.ml;
}

/** What the pause button's tooltip adds after its own name. */
function reminderStatus(): string {
  if (Hydration.paused) return t("Reminders paused");
  if (Hydration.done) return t("Reminders rest until tomorrow");
  return Hydration.next !== null ? t("Next reminder at %@", clockText(Hydration.next)) : "";
}

// ── The tab ───────────────────────────────────────────────────────────────────

export function buildHydration(actions: ViewActions): ViewHost {
  const burst = buildBurst();

  // ── Before it is set up ─────────────────────────────────────────────────────
  const introGlass = buildGlass(58);
  introGlass.set(0.55);
  const intro = h("div", { class: "hy-wrap" },
    h("div", { class: "hy-text hy-intro" },
      h("div", { class: "hy-who" }, dot(LIQUID, 7), h("b", { text: t("Hydration") })),
      h("div", { class: "title", text: t("A glass of water, now and then") }),
      h("div", {
        class: "sub",
        text: t("A few quick questions suggest a daily goal to start from. Reminders stay gentle and you can pause them."),
      }),
      h("div", { class: "actions" },
        // The questions live in Settings: eight screens do not fit a card, and
        // an answer about one's health is not something to ask over the notch.
        btn(t("Answer the questions"), "primary", () => {
          actions.blip();
          Hydration.askForSetup();
          actions.openSettingsWindow("hydration");
        }),
        btn(t("Just remind me"), "secondary", () => {
          actions.blip();
          Hydration.setEnabled(true);
        }),
      ),
    ),
    h("div", { class: "hy-side" }, introGlass.el),
  );

  // ── Today ───────────────────────────────────────────────────────────────────
  const glass = buildGlass(100);
  const plus = h("span", { class: "hy-plus" });
  const glassBtn = h("button", { class: "hy-glass-btn", type: "button", onclick: () => Hydration.log() },
    glass.el, plus);

  const whoDot = dot(LIQUID, 7);
  const weekDots = h("div", { class: "hy-week", role: "img" });
  const streakText = h("span");
  const streakPill = h("span", { class: "hy-streak" }, snowflake(13), streakText);
  const pauseBtn = h("button", {
    class: "hy-round", type: "button",
    onclick: () => {
      actions.blip();
      if (Hydration.paused) Hydration.resume();
      else Hydration.pause("indefinitely");
    },
  });
  const count = h("span", { class: "hy-count" });
  const of = h("span", { class: "hy-of" });
  const note = h("div", { class: "sub hy-msg", "aria-live": "polite" });

  const portions = HYDRATION.portions.map((ml) => {
    const el = h("button", {
      class: "hy-chip", type: "button", text: amountText(ml),
      // Choosing a portion is not drinking one: it only sets what the glass logs.
      onclick: () => {
        actions.blip();
        Hydration.setSettings({ portionML: ml });
      },
    });
    return { ml, el };
  });

  const undoMain = undoButton(() => { actions.blip(); Hydration.undo(); });
  const entries = h("span", { class: "hy-entries" });
  const more = h("span", { class: "hy-more" });

  const main = h("div", { class: "hy-wrap" },
    glassBtn,
    h("div", { class: "hy-text hy-main" },
      h("div", { class: "hy-who" }, whoDot, h("b", { text: t("Hydration") }), h("span", { text: t("today") }),
        h("span", { class: "hy-who-end" }, weekDots, streakPill, pauseBtn)),
      h("div", { class: "hy-count-row" }, count, of),
      note,
      h("div", { class: "hy-portions" },
        h("span", { class: "hy-label", text: t("Portion") }), ...portions.map((p) => p.el)),
      h("div", { class: "hy-log" }, undoMain, entries, more),
    ),
  );

  // ── Goal reached: the week of frozen days ───────────────────────────────────
  const fullGlass = buildGlass(66);
  const flake = snowflake(30);
  flake.classList.add("hy-flake");
  const fullGlassBtn = h("button", { class: "hy-glass-btn small", type: "button", onclick: () => Hydration.log() },
    fullGlass.el);
  const headline = h("span");
  const days = h("div", { class: "hy-days", role: "img" });
  const markText = h("span");
  const markFill = h("i");
  const markRow = h("span", { class: "hy-mark-next" }, markText, h("span", { class: "hy-bar", "aria-hidden": "true" }, markFill));
  const restText = h("span");
  const restPill = h("span", { class: "hy-rest" }, svg(ICONS.moon, 10), restText);
  const amount = h("span", { class: "hy-amount" });
  const undoStreak = undoButton(() => { actions.blip(); Hydration.undo(); });

  const streak = h("div", { class: "hy-wrap" },
    h("div", { class: "hy-text" },
      h("div", { class: "hy-who" }, dot(ICE, 7), h("b", { text: t("Hydration") }),
        h("span", { text: t("today's goal reached") })),
      h("div", { class: "hy-headline" }, flake, headline),
      days,
      h("div", { class: "hy-mark" }, markRow, restPill),
    ),
    h("div", { class: "hy-side" }, fullGlassBtn, amount, undoStreak),
  );

  const cardEl = card("cyan", intro, main, streak, burst.el);
  const el = h("div", { class: "view hydration" }, cardEl);

  let weekKey = "";
  let daysKey = "";
  let entriesKey = "";
  let pauseKey = "";
  let celebrated = false;

  function syncWeekDots(week: HydrationDot[]) {
    const key = week.join(",");
    if (key === weekKey) return;
    weekKey = key;
    clear(weekDots);
    for (const d of week) weekDots.append(h("i", { class: `hy-dot ${d}` }));
    weekDots.setAttribute("aria-label", t("This week: %lld of 7 days frozen", frozenThisWeek(week)));
  }

  function syncEntries(list: HydrationEntry[]) {
    const recent = list.slice(-2).reverse();
    const key = recent.map((e) => `${e.id}:${e.ml}`).join("|");
    if (key !== entriesKey) {
      entriesKey = key;
      clear(entries);
      for (const e of recent) {
        const text = amountText(e.ml);
        const at = clockText(e.at);
        entries.append(h("span", { class: "hy-entry" },
          h("span", { text: `${at} · ${text}` }),
          h("button", {
            type: "button", "aria-label": t("Remove the %@ logged at %@", text, at),
            title: t("Remove the %@ logged at %@", text, at),
            onclick: () => { actions.blip(); Hydration.remove(e.id); },
          }, svg(ICONS.xmark, 8))));
      }
    }
    const rest = list.length - recent.length;
    more.textContent = rest > 0 ? t("+%lld today", rest) : "";
  }

  function syncMain() {
    const paused = Hydration.paused;
    const total = Hydration.total;
    const goal = Hydration.goal;
    const portion = Hydration.settings.portionML;
    const streakOn = Hydration.settings.streakEnabled;

    glass.setColor(paused ? LIQUID_PAUSED : LIQUID);
    glass.set(Hydration.level, Hydration.pulse);
    plus.textContent = `+${amountText(portion)}`;
    glassBtn.setAttribute("aria-label", glassLabel());
    whoDot.style.background = paused ? LIQUID_PAUSED : LIQUID;

    weekDots.style.display = streakOn ? "" : "none";
    if (streakOn) syncWeekDots(Hydration.week);
    const run = Hydration.streak.days;
    streakPill.style.display = streakOn && run > 0 ? "" : "none";
    streakText.textContent = run === 1 ? t("1 day") : t("%lld days", run);
    streakPill.classList.toggle("frozen", Hydration.streak.marks[Hydration.todayKey] === "frozen");

    // Rebuilt only when it flips: it is the thing under the pointer when it does.
    const label = paused ? t("Resume reminders") : t("Pause reminders");
    const status = reminderStatus();
    if (pauseKey !== label) {
      pauseKey = label;
      clear(pauseBtn);
      pauseBtn.append(svg(paused ? ICONS.play : ICONS.pause, 10));
      pauseBtn.setAttribute("aria-label", label);
    }
    pauseBtn.title = status ? `${label} · ${status}` : label;

    count.textContent = amountText(total);
    of.textContent = goal.ml > 0 ? t("of %@", amountText(goal.ml)) : "";
    const text = message();
    if (note.textContent !== text) note.textContent = text;

    for (const p of portions) p.el.setAttribute("aria-pressed", String(p.ml === portion));
    undoMain.disabled = Hydration.day.entries.length === 0;
    syncEntries(Hydration.day.entries);

    cardEl.style.setProperty("--wash", paused ? WASH_NONE : goalReached() ? WASH_REACHED : WASH_WATER);
  }

  function syncStreak() {
    fullGlass.set(Hydration.level, Hydration.pulse);
    fullGlassBtn.setAttribute("aria-label", glassLabel());
    amount.textContent = progressText();

    const run = Hydration.streak.days;
    headline.textContent = run <= 1 ? t("First day frozen") : t("%lld days in a row", run);

    const week = Hydration.week;
    const key = `${week.join(",")}|${Hydration.todayKey}|${language()}`;
    if (key !== daysKey) {
      daysKey = key;
      const initials = weekdayInitials();
      // The hydration day, not the calendar's: at half past midnight "today"
      // is still the column of the day that has not ended yet.
      const date = hydrationKeyDate(Hydration.todayKey);
      const todayIndex = date ? (date.getDay() + 6) % 7 : -1;
      clear(days);
      week.forEach((d, i) => {
        const disc = h("span", { class: d === "frozen" || d === "rest" ? `hy-disc ${d}` : "hy-disc" });
        if (d === "frozen") disc.append(snowflake(18));
        else if (d === "rest") disc.append(svg(ICONS.moon, 12));
        days.append(h("span", { class: i === todayIndex ? "hy-day today" : "hy-day" },
          disc, h("span", { text: initials[i] })));
      });
      days.setAttribute("aria-label", t("This week: %lld of 7 days frozen", frozenThisWeek(week)));
    }

    const nextMark = STREAK_MARKS.find((m) => m > run);
    markRow.style.display = nextMark ? "" : "none";
    if (nextMark) {
      markText.textContent = t("Next mark: %lld days", nextMark);
      markFill.style.width = `${Math.round((run / nextMark) * 1000) / 10}%`;
    }
    const rests = Hydration.streak.rests;
    restPill.style.display = rests > 0 ? "" : "none";
    restText.textContent = rests === 1 ? t("1 rest day saved") : t("%lld rest days saved", rests);

    cardEl.style.setProperty("--wash", WASH_ICE);
  }

  return {
    el,
    sync() {
      const layout = !Hydration.enabled ? "intro"
        : Hydration.celebrates && Hydration.settings.streakEnabled ? "streak" : "main";
      intro.style.display = layout === "intro" ? "" : "none";
      main.style.display = layout === "main" ? "" : "none";
      streak.style.display = layout === "streak" ? "" : "none";
      if (layout === "intro") cardEl.style.setProperty("--wash", WASH_WATER);
      else if (layout === "main") syncMain();
      else syncStreak();

      if (Hydration.celebrating && !celebrated) burst.fire();
      celebrated = Hydration.celebrating;
    },
  };
}

// ── The reminder ──────────────────────────────────────────────────────────────

/**
 * "Cauã! How about some water?" with the name set quieter than the question,
 * as the design has it. The sentence is split where the translation puts the
 * name, so each language keeps its own word order.
 */
function askTitle(into: HTMLElement) {
  clear(into);
  const name = Hydration.name.trim();
  if (!name) {
    into.textContent = t("How about some water?");
    return;
  }
  const mark = "\u0001";
  const whole = t("%@! How about some water?", mark);
  const split = /^(.*?\u0001[!,.:;]?\s*)(.*)$/s.exec(whole);
  if (!split) {
    into.textContent = whole.replace(mark, name);
    return;
  }
  into.append(h("span", { class: "hy-name", text: split[1].replace(mark, name) }), split[2]);
}

export function buildSip(actions: ViewActions): ViewHost {
  const burst = buildBurst();
  const glass = buildGlass(54);
  const amount = h("span", { class: "hy-amount" });
  const title = h("div", { class: "title hy-sip-title" });
  const sub = h("div", { class: "sub" });

  // One row of buttons per thing the card can be saying, each built once.
  const drankLabel = h("span");
  const drankMoreLabel = h("span");
  const drank = h("button", { class: "btn primary", type: "button", onclick: () => Hydration.log() }, drankLabel);
  const drankMore = h("button", { class: "btn primary", type: "button", onclick: () => Hydration.log() }, drankMoreLabel);
  const undo = () => { actions.blip(); Hydration.undo(); };
  const rows: Record<HydrationPrompt, HTMLElement> = {
    reminder: h("div", { class: "actions" },
      drank, btn(t("Later"), "secondary", () => { actions.blip(); Hydration.snooze(); })),
    logged: h("div", { class: "actions" }, drankMore, btn(t("Undo"), "secondary", undo)),
    goal: h("div", { class: "actions" }, btn(t("Undo"), "secondary", undo)),
    snoozed: h("div", { class: "actions" },
      btn(t("Undo"), "secondary", () => { actions.blip(); Hydration.unsnooze(); })),
  };

  const body = h("div", { class: "hy-sip-body" }, title, sub, ...Object.values(rows));
  const wrap = h("div", { class: "hy-wrap" },
    h("div", { class: "hy-text" },
      h("div", { class: "hy-who" }, dot(LIQUID, 7), h("b", { text: t("Hydration") })),
      body),
    h("div", { class: "hy-side" }, glass.el, amount),
  );
  const cardEl = card("cyan", wrap, burst.el);
  const el = h("div", { class: "view sip" }, cardEl);

  let saying: HydrationPrompt | null = null;
  let celebrated = false;

  return {
    el,
    sync() {
      // With nothing said yet the card is the question: a reminder still
      // waiting from before a restart has no prompt, only `awaiting`.
      const prompt: HydrationPrompt = Hydration.prompt ?? "reminder";
      const portion = amountText(Hydration.settings.portionML);
      const total = amountText(Hydration.total);
      const goal = Hydration.goal;

      glass.set(Hydration.level, Hydration.pulse);
      amount.textContent = progressText();
      for (const [kind, row] of Object.entries(rows)) row.style.display = kind === prompt ? "" : "none";
      drankLabel.textContent = t("I drank %@", portion);
      drankMoreLabel.textContent = t("I drank %@ more", portion);

      switch (prompt) {
        case "reminder": {
          askTitle(title);
          const last = Hydration.day.entries[Hydration.day.entries.length - 1];
          sub.textContent = last
            ? t("Your last log was %@ ago.", durationText((Date.now() - last.at) / 60_000))
            : t("Nothing logged yet today.");
          break;
        }
        case "logged": {
          const last = Hydration.day.entries[Hydration.day.entries.length - 1];
          title.textContent = t("Logged: +%@", amountText(last ? last.ml : Hydration.settings.portionML));
          sub.textContent = goal.ml > 0
            ? t("%@ of %@ today. Nice sip.", total, amountText(goal.ml))
            : t("%@ today. Nice sip.", total);
          break;
        }
        case "goal":
          title.textContent = t("Congratulations, today's goal is reached!");
          sub.textContent = t("Glass full, mascot full. Reminders rest until tomorrow.");
          break;
        case "snoozed":
          title.textContent = t("Deal, I'll be back in 30 min.");
          sub.textContent = t("If you drink before that, just tap the glass.");
          break;
      }
      cardEl.style.setProperty("--wash", prompt === "goal" ? WASH_ICE : WASH_WATER);

      // The words slide in when the card moves on to say something else.
      if (saying !== prompt) {
        if (saying !== null && !reducedMotion()) {
          body.classList.remove("hy-enter");
          void body.offsetWidth;
          body.classList.add("hy-enter");
        }
        saying = prompt;
      }

      if (Hydration.celebrating && !celebrated) burst.fire();
      celebrated = Hydration.celebrating;
    },
  };
}

// ── The closed island ─────────────────────────────────────────────────────────

/**
 * What the compact bar shows on its right while a reminder waits for an
 * answer: a 12 px glass at today's level, and a slow ring around it. The ring
 * is the stylesheet's, and only runs while `on` is set.
 */
export function buildCompactSip(): { el: HTMLElement; sync(on: boolean): void } {
  const glass = buildGlass(12, true);
  const el = h("div", { id: "compact-sip", "aria-hidden": "true" }, glass.el);
  return {
    el,
    sync(on: boolean) {
      el.classList.toggle("on", on);
      if (on) glass.set(Hydration.level);
    },
  };
}
