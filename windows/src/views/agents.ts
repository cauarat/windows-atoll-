// The AI Agents dashboard — port of AgentsDashboardView.swift.
//
// Everything here is read off disk: Claude Code writes every assistant turn to
// ~/.claude/projects with its model, its four token counts and its cwd, and
// `usage.rs` turns those into spend, tokens and activity. No network call is
// made for any of it.
//
// What the Mac has above these cards and this does not is the pair of plan
// gauges, which come from Claude Code's statusline relay — not ported yet, so
// the dashboard opens on Spending rather than on Session and Week.

import { h, svg, clear } from "./dom";
import { ICONS } from "./icons";
import { Bridge } from "../core/bridge";
import { card, type ViewHost } from "./views";
import { t } from "../core/i18n";

/** How often the dashboard re-reads while it is the view on screen. */
const REFRESH_MS = 20_000;

export interface UsageRow {
  name: string;
  spend: number;
}

export interface ActivityDay {
  /** `yyyy-MM-dd`, local. */
  day: string;
  spend: number;
}

/** Mirrors `usage::Snapshot`. */
export interface UsageSnapshot {
  spendToday: number;
  tokensToday: number;
  cacheShareToday: number;
  hourlyToday: number[];
  byModel: UsageRow[];
  byProject: UsageRow[];
  activity: ActivityDay[];
  windowSpend: number;
  windowWeeks: number;
  activeDays: number;
  busiestDay: ActivityDay | null;
  /** Epoch seconds, UTC. */
  lastActivity: number | null;
  hasUnknownModel: boolean;
  isEmpty: boolean;
}

// ── Formatting ────────────────────────────────────────────────────────────────

/**
 * Past a thousand the cents stop telling anyone anything, and the card is
 * narrow — "$1,242" rather than "$1242.45".
 */
export function money(value: number): string {
  if (value >= 1000) {
    return `$${Math.round(value).toLocaleString("en-US")}`;
  }
  return `$${value.toFixed(2)}`;
}

export function compactTokens(n: number): string {
  if (n >= 1_000_000_000) return `${(n / 1_000_000_000).toFixed(1)}B`;
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return `${n}`;
}

/** Seconds since `epochSecs`, read the way the Mac's `relative` reads it. */
export function relative(epochSecs: number, nowMs = Date.now()): string {
  const secs = nowMs / 1000 - epochSecs;
  if (secs < 60) return t("%lld sec. ago", Math.max(1, Math.floor(secs)));
  if (secs < 3600) return t("%lld min. ago", Math.floor(secs / 60));
  if (secs < 86_400) return t("%lld h ago", Math.floor(secs / 3600));
  return t("%lld d ago", Math.floor(secs / 86_400));
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** `2026-10-12` → `Oct 12`. Split rather than `new Date`, which would read the
 *  key as UTC midnight and show the day before in a western timezone. */
export function monthDay(day: string): string {
  const [, month, date] = day.split("-");
  const index = Number(month) - 1;
  if (!MONTHS[index] || !date) return day;
  return `${MONTHS[index]} ${Number(date)}`;
}

// ── Shared chrome ─────────────────────────────────────────────────────────────

/** Title row used by every card: a small tinted glyph, the name, and an
 *  optional trailing note. */
function cardTitle(icon: string, text: string, accent: string): {
  el: HTMLElement;
  trailing: HTMLElement;
} {
  const mark = svg(icon, 9);
  mark.style.color = accent;
  const trailing = h("span", { class: "ag-trailing" });
  return {
    el: h("div", { class: "ag-title" }, mark, h("span", { class: "ag-title-text", text }), trailing),
    trailing,
  };
}

function bar(className: string): HTMLElement {
  return h("div", { class: className });
}

// ── Cards ─────────────────────────────────────────────────────────────────────

function spendingCard() {
  const title = cardTitle(ICONS.dollar, t("Spending"), "#34D399");
  title.trailing.textContent = t("Today");
  const amount = h("div", { class: "ag-amount", text: "—" });
  const fresh = bar("ag-cache-fresh");
  const cached = bar("ag-cache-cached");
  const cacheBar = h("div", { class: "ag-cache" }, fresh, cached);
  const note = h("div", { class: "ag-note", text: t("Reading transcripts…") });
  const el = card(null, h("div", { class: "ag-card" }, title.el, amount, cacheBar, note));
  el.classList.add("ag-tile");

  return {
    el,
    sync(usage: UsageSnapshot | null) {
      amount.textContent = usage ? money(usage.spendToday) : "—";
      cacheBar.style.display = usage ? "" : "none";
      if (!usage) {
        note.textContent = t("Reading transcripts…");
        return;
      }
      const share = usage.cacheShareToday;
      fresh.style.flex = `${Math.max(0.02, 1 - share)}`;
      cached.style.flex = `${Math.max(0.02, share)}`;
      note.textContent =
        t("%@ tokens · %lld% from cache", compactTokens(usage.tokensToday), Math.round(share * 100));
    },
  };
}

function nowCard() {
  const title = cardTitle(ICONS.timer, t("Now"), "#8E939C");
  const who = h("span", { class: "ag-who", text: t("Claude") });
  const when = h("span", { class: "ag-when" });
  const row = h("div", { class: "ag-now-row" }, who, when);
  const idle = h("div", { class: "ag-note", text: t("Nothing running") });
  const warning = h("div", { class: "ag-warn", text: t("A new model was seen — figures are estimates") });
  const el = card(null, h("div", { class: "ag-card" }, title.el, row, idle, warning));
  el.classList.add("ag-tile");

  return {
    el,
    sync(usage: UsageSnapshot | null) {
      const last = usage?.lastActivity ?? null;
      row.style.display = last == null ? "none" : "";
      idle.style.display = last == null ? "" : "none";
      if (last != null) when.textContent = relative(last);
      warning.style.display = usage?.hasUnknownModel ? "" : "none";
    },
  };
}

function trendCard() {
  const title = cardTitle(ICONS.chart, t("Trend"), "#7C8BF5");
  const bars: HTMLElement[] = [];
  const chart = h("div", { class: "ag-trend" });
  for (let hour = 0; hour < 24; hour++) {
    // Morning in the Mac's amber, afternoon and evening in its indigo, so the
    // shape of a day is readable without an axis.
    const b = h("div", { class: hour < 12 ? "ag-bar morning" : "ag-bar evening" });
    bars.push(b);
    chart.append(b);
  }
  const axis = h(
    "div",
    { class: "ag-axis" },
    h("span", { text: t("12 AM") }),
    h("span", { text: t("12 PM") }),
    h("span", { text: t("11 PM") }),
  );
  const el = card(null, h("div", { class: "ag-card" }, title.el, chart, axis));
  el.classList.add("ag-tile", "ag-wide");

  return {
    el,
    sync(usage: UsageSnapshot | null) {
      const hours = usage?.hourlyToday ?? new Array<number>(24).fill(0);
      title.trailing.textContent = usage ? t("Today · %@", money(usage.spendToday)) : "";
      const peak = Math.max(...hours, 0.0001);
      hours.forEach((value, i) => {
        const b = bars[i];
        b.classList.toggle("empty", value <= 0);
        b.style.height = value > 0 ? `${Math.max(3, (value / peak) * 52)}px` : "3px";
      });
    },
  };
}

function breakdownCard(label: string, icon: string, accent: string) {
  const title = cardTitle(icon, t(label), accent);
  const rows = h("div", { class: "ag-rows" });
  const empty = h("div", { class: "ag-note", text: t("Nothing today") });
  const el = card(null, h("div", { class: "ag-card" }, title.el, rows, empty));
  el.classList.add("ag-tile");

  return {
    el,
    sync(list: UsageRow[]) {
      clear(rows);
      empty.style.display = list.length === 0 ? "" : "none";
      // Three rows: the fourth-richest model of a day is noise, and the card
      // is as tall as the one beside it.
      const top = list.slice(0, 3);
      const peak = Math.max(top[0]?.spend ?? 1, 0.0001);
      for (const row of top) {
        const fill = h("div", { class: "ag-row-fill" });
        fill.style.background = accent;
        fill.style.width = `${Math.max(3, (row.spend / peak) * 100)}%`;
        rows.append(
          h(
            "div",
            { class: "ag-row" },
            h("span", { class: "ag-row-name", text: row.name, title: row.name }),
            h("div", { class: "ag-row-track" }, fill),
            h("span", { class: "ag-row-value", text: money(row.spend) }),
          ),
        );
      }
    },
  };
}

function activityCard() {
  const title = cardTitle(ICONS.grid, t("Activity"), "#8E939C");
  const grid = h("div", { class: "ag-grid" });
  const cells: HTMLElement[] = [];
  // 13 columns of 7, oldest column first — the same shape as Claude Code's own.
  for (let col = 0; col < 13; col++) {
    const column = h("div", { class: "ag-grid-col" });
    for (let row = 0; row < 7; row++) {
      const cell = h("div", { class: "ag-cell" });
      cells.push(cell);
      column.append(cell);
    }
    grid.append(column);
  }
  const total = h("div", { class: "ag-amount small", text: "—" });
  const weeks = h("div", { class: "ag-note", text: t("13 weeks") });
  const busiestLabel = h("div", { class: "ag-note tiny", text: t("Busiest day") });
  const busiest = h("div", { class: "ag-busiest" });
  const stats = h("div", { class: "ag-stats" }, total, weeks, busiestLabel, busiest);
  const el = card(null, h("div", { class: "ag-card" }, title.el,
                          h("div", { class: "ag-activity" }, grid, stats)));
  el.classList.add("ag-tile", "ag-wide");

  /** Four steps, like a contribution graph; square-rooted so a single very
   *  expensive day doesn't flatten everything else to the floor. */
  function shade(spend: number, peak: number): number {
    if (spend <= 0) return 0.055;
    const t = Math.sqrt(spend / peak);
    if (t > 0.75) return 0.92;
    if (t > 0.45) return 0.62;
    if (t > 0.2) return 0.38;
    return 0.2;
  }

  return {
    el,
    sync(usage: UsageSnapshot | null) {
      const days = usage?.activity ?? [];
      const peak = Math.max(...days.map((d) => d.spend), 0.0001);
      cells.forEach((cell, index) => {
        const day = days[index];
        cell.style.background = `rgba(255,255,255,${shade(day?.spend ?? 0, peak)})`;
        cell.title = day ? `${monthDay(day.day)} · ${money(day.spend)}` : "";
      });
      title.trailing.textContent = usage ? `${usage.activeDays} active days` : "";
      total.textContent = money(usage?.windowSpend ?? 0);
      weeks.textContent = `${usage?.windowWeeks ?? 13} weeks`;
      const best = usage?.busiestDay ?? null;
      const show = best != null && best.spend > 0;
      busiestLabel.style.display = show ? "" : "none";
      busiest.style.display = show ? "" : "none";
      if (show && best) busiest.textContent = `${monthDay(best.day)} · ${money(best.spend)}`;
    },
  };
}

// ── The view ──────────────────────────────────────────────────────────────────

export function buildAgents(): ViewHost {
  const spending = spendingCard();
  const now = nowCard();
  const trend = trendCard();
  const models = breakdownCard("Models", ICONS.stack, "#C98B6B");
  const projects = breakdownCard("Projects", ICONS.folder, "#7C8BF5");
  const activity = activityCard();

  const nothing = h("div", { class: "ag-empty" },
                    h("div", { class: "ag-note", text: t("Claude Code has not run on this machine yet.") }));
  const body = h(
    "div",
    { class: "ag-body" },
    h("div", { class: "ag-pair" }, spending.el, now.el),
    trend.el,
    h("div", { class: "ag-pair" }, models.el, projects.el),
    activity.el,
  );
  const el = h("div", { class: "view ag-view" }, body, nothing);

  let usage: UsageSnapshot | null = null;
  let lastRead = 0;
  let reading = false;

  async function read() {
    if (reading) return;
    reading = true;
    lastRead = performance.now();
    const fresh = await Bridge.agentUsage();
    reading = false;
    if (!fresh) return;
    usage = fresh;
    draw();
  }

  function draw() {
    const empty = usage?.isEmpty ?? false;
    body.style.display = empty ? "none" : "";
    nothing.style.display = empty ? "" : "none";
    spending.sync(usage);
    now.sync(usage);
    trend.sync(usage);
    models.sync(usage?.byModel ?? []);
    projects.sync(usage?.byProject ?? []);
    activity.sync(usage);
  }

  draw();

  return {
    el,
    sync() {
      // Nothing here is driven by island state: the numbers come from disk,
      // and `tick` is what keeps them current while the view is on screen.
    },
    tick(nowMs: number) {
      if (nowMs - lastRead < REFRESH_MS) {
        // The "x min. ago" line is the one thing that goes stale without a
        // re-read, and redrawing it costs nothing.
        if (usage?.lastActivity != null) now.sync(usage);
        return;
      }
      void read();
    },
  };
}
