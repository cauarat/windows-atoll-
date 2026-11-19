// The Agenda tab — today's meetings from the commercial panel.
//
// Port of AgendaView.swift. Laid out like the messages list it sits beside: no
// Mochi gutter, the rows run the full width, and Mochi rides the header line.
// The meeting a heads-up opened the island for is outlined; otherwise the one
// on now, or the next, is the one tinted.
//
// `sync()` runs every frame while the tab is on screen, so the list is rebuilt
// only when something it shows has changed — a read, the heads-up, or the
// twenty-second step the countdowns move in.

import { h, svg, clear } from "./dom";
import { ICONS } from "./icons";
import { card, stack, type ViewActions, type ViewHost } from "./views";
import { Agenda } from "../island/agenda";
import {
  DEPARTMENT_COLOR, DEPARTMENT_LABEL, attemptStateLabel, focus, phase, stageLabel,
  type AgendaMeeting,
} from "../core/agendaRules";
import { Bridge } from "../core/bridge";
import { State } from "../core/state";
import { t } from "../core/i18n";

const ACCENT = "#38BDF8";

function clock(ms: number): string {
  const d = new Date(ms);
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

/** "Onboarding · 1ª conexão · Confirmada · 2ª tent." — the panel's own words. */
function subtitle(m: AgendaMeeting): string {
  const parts = [t(DEPARTMENT_LABEL[m.department]), t(stageLabel(m.stageKey))];
  const state = attemptStateLabel(m.attemptState);
  if (state) parts.push(t(state));
  if (m.attemptSequence > 1) parts.push(t("attempt %lld", m.attemptSequence));
  return parts.join(" · ");
}

function phaseText(m: AgendaMeeting, now: number): { text: string; color: string; strong: boolean } {
  const p = phase(m, now);
  switch (p.kind) {
    case "upcoming": {
      const color = p.minutes <= 15 ? "#FBBF24" : "#C5C8CD";
      if (p.minutes >= 60) {
        const hours = Math.floor(p.minutes / 60), rest = p.minutes % 60;
        return { text: rest === 0 ? t("in %lld h", hours) : t("in %lld h %lld min", hours, rest), color, strong: false };
      }
      return { text: t("in %lld min", p.minutes), color, strong: false };
    }
    case "now": return { text: t("now"), color: "#34D399", strong: true };
    case "ended": return { text: t("ended"), color: "#6B7079", strong: false };
    case "done": return { text: t("held"), color: "#6B7079", strong: false };
  }
}

function row(m: AgendaMeeting, now: number, isFocus: boolean, isHeadsUp: boolean): HTMLElement {
  const p = phase(m, now).kind;
  const past = p === "ended" || p === "done";
  const label = phaseText(m, now);

  const title = h("b", { class: "agenda-title", text: m.title || t("Unnamed customer") });
  const head = h("div", { class: "agenda-row-head" }, title);
  if (m.publicId) head.append(h("span", { class: "agenda-chip", text: m.publicId }));

  const el = h(
    "div",
    {
      class: `agenda-row${past ? " past" : ""}${isFocus ? " focus" : ""}${isHeadsUp ? " heads-up" : ""}`,
      title: t("Open in the commercial panel"),
      onclick: () => void Bridge.agendaOpen(m.department),
    },
    h("div", { class: "agenda-times" },
      h("b", { text: clock(m.startMs) }),
      h("span", { text: clock(m.endMs) })),
    h("i", { class: "agenda-bar" }),
    h("div", { class: "agenda-text" }, head, h("div", { class: "agenda-sub", text: subtitle(m) })),
    h("span", {
      class: "agenda-phase",
      text: label.text,
      style: `color:${label.color};font-weight:${label.strong || isHeadsUp ? 600 : 400}`,
    }),
  );
  el.style.setProperty("--accent", DEPARTMENT_COLOR[m.department]);
  el.dataset.id = m.attemptId;
  return el;
}

function emptyText(): { text: string; problem: boolean } {
  const s = Agenda.snapshot;
  switch (s.status) {
    case "off": return { text: t("Turn the Agenda on in Settings."), problem: true };
    case "signed-out": return { text: t("Sign in with your Actuar account in Settings."), problem: true };
    case "loading": return { text: t("Reading the commercial panel…"), problem: false };
    case "no-access": return { text: t("This Actuar account has no access to the commercial panel"), problem: true };
    case "failed": return { text: s.detail ? t(s.detail) : t("Server unreachable"), problem: true };
    case "ready": return { text: t("No meetings today."), problem: false };
  }
}

export function buildAgenda(actions: ViewActions): ViewHost {
  const mochi = h("div", { class: "msg-mochi" });
  const updated = h("span", { class: "msg-count" });
  const refreshBtn = h("button", {
    class: "tab", title: t("Refresh"),
    onclick: () => { actions.blip(); void Agenda.refresh(true); },
  }, svg(ICONS.refresh, 12, { stroke: 2 }));
  const openBtn = h("button", {
    class: "tab", title: t("Open the commercial panel"),
    onclick: () => { actions.blip(); void Bridge.agendaOpen("onboarding"); },
  }, svg(ICONS.arrowUpRight, 12));
  const icon = svg(ICONS.calendar, 12);
  icon.style.color = ACCENT;
  const head = h("div", { class: "msg-head" }, mochi, icon, h("b", { text: t("Agenda · today") }), updated,
                 refreshBtn, openBtn);

  const list = h("div", { class: "msg-list" });
  const body = stack(12, 12, head, list);
  body.style.justifyContent = "flex-start";
  const el = h("div", { class: "view" }, card("cyan", body));

  let signature = "";
  let lastSync = 0;
  let scrolledFor: string | null = null;

  return {
    el,
    sync() {
      const now = Date.now();
      // The tab came up: the first sync after a gap. Reads unless fresh.
      if (now - lastSync > 500) {
        Agenda.tabOpened();
        // A heads-up's mark is for the opening it caused.
        if (Agenda.highlight && now - Agenda.highlightAtMs > 5_000) Agenda.highlight = null;
      }
      lastSync = now;

      const snap = Agenda.snapshot;
      const key = [snap.status, snap.detail, snap.fetchedAtMs, Agenda.highlight,
                   Math.floor(now / 20_000), snap.meetings.map((m) => m.attemptId).join(",")].join("|");
      if (key === signature) return;
      signature = key;

      updated.textContent = snap.fetchedAtMs > 0 && snap.status === "ready"
        ? t("Updated %@", clock(snap.fetchedAtMs)) : "";

      clear(list);
      if (snap.meetings.length === 0) {
        const { text, problem } = emptyText();
        list.append(h("div", { class: "sub", style: problem ? "color:var(--red-text)" : "", text }));
        if (problem && snap.status !== "loading") {
          list.append(h("button", {
            class: "agenda-settings",
            text: t("Settings…"),
            onclick: () => { actions.blip(); actions.openSettingsWindow(); },
          }));
        }
        return;
      }
      const highlighted = Agenda.highlight
        ? snap.meetings.find((m) => m.attemptId === Agenda.highlight)
        : undefined;
      const lead = highlighted ?? focus(snap.meetings, now);
      for (const m of snap.meetings) {
        list.append(row(m, now, m.attemptId === lead?.attemptId, m.attemptId === Agenda.highlight));
      }
      // Lead with the heads-up's meeting, or the one on now — once per reason,
      // so reading down the list is not undone every twenty seconds.
      const scrollKey = `${lead?.attemptId ?? ""}|${Agenda.highlight ?? ""}`;
      if (lead && scrolledFor !== scrollKey) {
        scrolledFor = scrollKey;
        requestAnimationFrame(() => {
          const target = list.querySelector<HTMLElement>(`[data-id="${CSS.escape(lead.attemptId)}"]`);
          if (target) list.scrollTop = target.offsetTop - list.offsetTop;
        });
      }
    },
  };
}

/** Whether the header shows the Agenda's tab. */
export function agendaTabVisible(): boolean {
  return State.settings.agendaEnabled;
}
