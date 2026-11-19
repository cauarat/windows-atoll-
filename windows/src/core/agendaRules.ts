// The Agenda's clock — the half of AgendaRules.swift that Rust leaves to the
// island, because the island is the one that knows the local time zone.
//
// Which meetings are yours is decided in Rust (`agenda_proto.rs`); this is when
// it is today, how far off each one is, and which heads-up comes next.
// Pure and import-free, so tests/agenda-rules.ts runs it under Node.

export type AgendaDepartment = "onboarding" | "backoffice";

/** One effective attempt of one of your meetings, as `agenda_refresh` sends it. */
export interface AgendaMeeting {
  attemptId: string;
  meetingId: string;
  caseId: string;
  department: AgendaDepartment;
  stageKey: string;
  startMs: number;
  endMs: number;
  /** The customer, as the panel titles the card; empty when there is no name. */
  title: string;
  /** The case code the panel shows as a chip ("GM3941"). */
  publicId: string | null;
  attemptSequence: number;
  attemptState: string;
  meetingState: string;
}

export type AgendaStatus = "off" | "loading" | "ready" | "signed-out" | "no-access" | "failed";

export interface AgendaSnapshot {
  status: AgendaStatus;
  detail: string | null;
  meetings: AgendaMeeting[];
  fetchedAtMs: number;
}

export type AgendaPhase =
  | { kind: "upcoming"; minutes: number }
  | { kind: "now" }
  | { kind: "ended" }
  | { kind: "done" };

export const LEAD_CHOICES = [5, 10, 15, 30, 60];
export const DEFAULT_LEAD_MINUTES = 15;

/** Held and recorded: still listed, dimmed, never announced. */
export function isClosed(m: AgendaMeeting): boolean {
  return m.meetingState === "attended" || m.meetingState === "completed";
}

/** What the heads-up set remembers: the attempt and its start, so an attempt
 *  whose time was edited in place is announced again. */
export function reminderKey(m: AgendaMeeting): string {
  return `${m.attemptId}@${Math.floor(m.startMs / 1000)}`;
}

/** The local day `nowMs` falls in, as `[start, end)`. */
export function localDay(nowMs: number): [number, number] {
  const d = new Date(nowMs);
  const start = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const end = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime();
  return [start, end];
}

/** "2026-11-19", what remembered heads-ups are filed under. */
export function dayStamp(nowMs: number): string {
  const d = new Date(nowMs);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function phase(m: AgendaMeeting, nowMs: number): AgendaPhase {
  if (isClosed(m)) return { kind: "done" };
  if (nowMs < m.startMs) return { kind: "upcoming", minutes: Math.ceil((m.startMs - nowMs) / 60_000) };
  return nowMs < m.endMs ? { kind: "now" } : { kind: "ended" };
}

/** The meeting the list leads with: the one on now, else the next. */
export function focus(meetings: AgendaMeeting[], nowMs: number): AgendaMeeting | null {
  return meetings.find((m) => {
    const p = phase(m, nowMs).kind;
    return p === "upcoming" || p === "now";
  }) ?? null;
}

/**
 * The next heads-up, and when. One whose time has already gone by — Notchy
 * was off, the machine asleep, the meeting booked ten minutes out — is given
 * at once, as long as the meeting has not started.
 */
export function nextReminder(
  meetings: AgendaMeeting[],
  nowMs: number,
  leadMs: number,
  notified: Set<string>,
  departments: Set<AgendaDepartment>,
): { meeting: AgendaMeeting; fireAtMs: number } | null {
  let best: { meeting: AgendaMeeting; fireAtMs: number } | null = null;
  for (const m of meetings) {
    if (isClosed(m) || m.startMs <= nowMs || !departments.has(m.department) || notified.has(reminderKey(m))) {
      continue;
    }
    const fireAtMs = Math.max(m.startMs - leadMs, nowMs);
    if (!best || fireAtMs < best.fireAtMs || (fireAtMs === best.fireAtMs && m.startMs < best.meeting.startMs)) {
      best = { meeting: m, fireAtMs };
    }
  }
  return best;
}

/** The panel's names for its stages — English catalogue keys, translated where drawn. */
export function stageLabel(stageKey: string): string {
  switch (stageKey) {
    case "contact": return "Contact";
    case "connection": return "1st connection";
    case "connection_2": return "2nd connection";
    case "connection_3": return "3rd connection";
    case "follow_up": return "Follow-up";
    case "turnstile": return "Turnstile setup";
    case "go_live_validation": return "Go-live validation";
    default: return stageKey;
  }
}

export function attemptStateLabel(state: string): string | null {
  switch (state) {
    case "confirmed": return "Confirmed";
    case "scheduled": return "Scheduled";
    case "pending": return "Pending";
    default: return null;
  }
}

export const DEPARTMENT_LABEL: Record<AgendaDepartment, string> = {
  onboarding: "Onboarding",
  backoffice: "Backoffice",
};

export const DEPARTMENT_COLOR: Record<AgendaDepartment, string> = {
  onboarding: "#A78BFA",
  backoffice: "#22D3EE",
};
