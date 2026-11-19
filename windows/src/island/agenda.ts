// The Agenda's clock on Windows and Linux — the timing half of
// AgendaClient.swift. Rust reads the panel (`agenda_refresh`); this decides
// when to ask, which day to ask about, and when a meeting gets its heads-up.
//
// Reads every ten minutes while the Agenda is on, just after local midnight,
// and when the tab opens. Between them, one timer for the next heads-up —
// in slices of five minutes at most, because a timer armed before the machine
// slept is not to be trusted after it wakes.

import { Bridge, IS_TAURI } from "../core/bridge";
import { State } from "../core/state";
import {
  dayStamp, localDay, nextReminder, reminderKey,
  type AgendaDepartment, type AgendaMeeting, type AgendaSnapshot,
} from "../core/agendaRules";

const REFRESH_MS = 10 * 60_000;
/** A tab opened within this of the last read shows that read. */
const TAB_FRESH_MS = 60_000;
/** A heads-up is given from a read at most this old; older, it reads first,
 *  so a meeting cancelled or moved in the meantime is not announced. */
const REMINDER_FRESH_MS = 2 * 60_000;
/** The longest a single timer is trusted across a possible sleep. */
const SLICE_MS = 5 * 60_000;
const NOTIFIED_KEY = "agendaNotified";

class AgendaController {
  snapshot: AgendaSnapshot = { status: "off", detail: null, meetings: [], fetchedAtMs: 0 };
  /** The meeting a heads-up opened the island for, by attempt id, and when.
   *  The tab forgets it on the next opening it did not cause. */
  highlight: string | null = null;
  highlightAtMs = 0;
  /** Set by main.ts: open the island on the Agenda. */
  onDue: ((attemptId: string) => void) | null = null;

  private loopTimer: number | undefined;
  private reminderTimer: number | undefined;
  private reading: Promise<void> | null = null;
  private seeded = false;
  private listeners = new Set<() => void>();

  subscribe(fn: () => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private emit() {
    for (const fn of this.listeners) fn();
  }

  private get enabled(): boolean {
    return State.settings.agendaEnabled;
  }

  private get leadMs(): number {
    return (State.settings.agendaLeadMinutes || 15) * 60_000;
  }

  private get departments(): Set<AgendaDepartment> {
    const set = new Set<AgendaDepartment>();
    if (State.settings.agendaNotifyOnboarding) set.add("onboarding");
    if (State.settings.agendaNotifyBackoffice) set.add("backoffice");
    return set;
  }

  /** On/off, the lead time or the processes changed — and once at launch. */
  settingsChanged() {
    if (!this.enabled) {
      this.stop();
      this.snapshot = { status: "off", detail: null, meetings: [], fetchedAtMs: 0 };
      this.emit();
      return;
    }
    if (this.loopTimer === undefined) this.scheduleLoop();
    if (this.snapshot.status === "off" || (this.snapshot.meetings.length === 0 && !this.reading)) {
      void this.refresh(true);
    } else {
      this.armReminder();
    }
  }

  /** The tab came up: read unless the last read is a minute old or less. */
  tabOpened() {
    void this.refresh(false);
  }

  refresh(force = true): Promise<void> {
    if (!this.enabled || this.seeded) return Promise.resolve();
    if (this.reading) return this.reading;
    if (!force && Date.now() - this.snapshot.fetchedAtMs < TAB_FRESH_MS) return Promise.resolve();
    if (this.snapshot.meetings.length === 0) {
      this.snapshot = { ...this.snapshot, status: "loading", detail: null };
      this.emit();
    }
    this.reading = (async () => {
      const [start, end] = localDay(Date.now());
      const snap = await Bridge.agendaRefresh(start, end).catch(() => null);
      if (snap && this.enabled) {
        this.snapshot = snap;
      } else if (!snap && this.snapshot.status === "loading") {
        this.snapshot = { ...this.snapshot, status: IS_TAURI ? "failed" : "signed-out",
                          detail: IS_TAURI ? "Server unreachable" : null };
      }
      this.reading = null;
      this.emit();
      this.armReminder();
    })();
    return this.reading;
  }

  private stop() {
    window.clearTimeout(this.loopTimer);
    window.clearTimeout(this.reminderTimer);
    this.loopTimer = undefined;
    this.reminderTimer = undefined;
    this.seeded = false;
  }

  /** Every ten minutes, and just after midnight so the new day is read first. */
  private scheduleLoop() {
    const now = Date.now();
    const [, midnight] = localDay(now);
    const wait = Math.max(30_000, Math.min(REFRESH_MS, midnight - now + 5_000));
    this.loopTimer = window.setTimeout(() => {
      this.loopTimer = undefined;
      if (!this.enabled) return;
      void this.refresh(true);
      this.scheduleLoop();
    }, wait);
  }

  // ── Heads-up ────────────────────────────────────────────────────────────────

  private notified(today: string): Set<string> {
    try {
      const raw = localStorage.getItem(NOTIFIED_KEY);
      const stored = raw ? JSON.parse(raw) as { day?: string; keys?: string[] } : null;
      return stored?.day === today ? new Set(stored.keys ?? []) : new Set();
    } catch {
      return new Set();
    }
  }

  private remember(keys: string[], today: string) {
    const set = this.notified(today);
    for (const key of keys) set.add(key);
    try {
      localStorage.setItem(NOTIFIED_KEY, JSON.stringify({ day: today, keys: [...set] }));
    } catch {
      // Private storage refused: the heads-up may repeat after a restart.
    }
  }

  private armReminder() {
    window.clearTimeout(this.reminderTimer);
    this.reminderTimer = undefined;
    if (!this.enabled) return;
    const now = Date.now();
    const next = nextReminder(this.snapshot.meetings, now, this.leadMs,
                              this.notified(dayStamp(now)), this.departments);
    if (!next) return;
    const delay = Math.max(0, next.fireAtMs - now);
    this.reminderTimer = window.setTimeout(() => {
      this.reminderTimer = undefined;
      // A slice, not the whole wait: past a sleep the clock is read again.
      if (Date.now() < next.fireAtMs) this.armReminder();
      else void this.due();
    }, Math.min(delay, SLICE_MS));
  }

  private async due() {
    if (!this.seeded && Date.now() - this.snapshot.fetchedAtMs > REMINDER_FRESH_MS) {
      await this.refresh(true);
    }
    const now = Date.now();
    const today = dayStamp(now);
    const notified = this.notified(today);
    const due: AgendaMeeting[] = [];
    for (;;) {
      const next = nextReminder(this.snapshot.meetings, now, this.leadMs, notified, this.departments);
      if (!next || next.fireAtMs > now + 1_000) break;
      due.push(next.meeting);
      notified.add(reminderKey(next.meeting));
    }
    if (due.length > 0) {
      this.remember(due.map(reminderKey), today);
      this.highlight = due[0].attemptId;
      this.highlightAtMs = Date.now();
      this.emit();
      this.onDue?.(due[0].attemptId);
    }
    this.armReminder();
  }

  // ── Preview ─────────────────────────────────────────────────────────────────

  /** Four meetings around now, for looking at the tab without an account. */
  seedForPreview(nowMs = Date.now()) {
    this.seeded = true;
    State.settings = { ...State.settings, agendaEnabled: true };
    const at = (minutes: number) => nowMs + minutes * 60_000;
    const meeting = (id: string, from: number, length: number, title: string, publicId: string | null,
                     stageKey: string, extra: Partial<AgendaMeeting> = {}): AgendaMeeting => ({
      attemptId: id, meetingId: `m-${id}`, caseId: `c-${id}`,
      department: stageKey === "contact" ? "backoffice" : "onboarding", stageKey,
      startMs: at(from), endMs: at(from + length), title, publicId, attemptSequence: 1,
      attemptState: "confirmed", meetingState: "open", ...extra,
    });
    this.snapshot = {
      status: "ready", detail: null, fetchedAtMs: nowMs,
      meetings: [
        meeting("seed-1", -150, 60, "Studio Movimento / actuar", "GB5940", "connection", { meetingState: "attended" }),
        meeting("seed-2", -20, 90, "Academia Forja", null, "contact"),
        meeting("seed-3", (State.settings.agendaLeadMinutes || 15) + 1, 90,
                "welber vieira freire santos - Toletus GK7045 - Actuar", "GM3941", "connection", { attemptSequence: 2 }),
        meeting("seed-4", 240, 60, "L.A. Esportes", null, "connection_2"),
      ],
    };
    this.emit();
    this.armReminder();
  }
}

export const Agenda = new AgendaController();
