// The Agenda's clock on Windows and Linux — the same heads-up cases as
// tests/AgendaRulesTests.swift, over the three meetings "Ana Souza" had on
// 2026-11-19 in tests/fixtures/agenda/ (São Paulo, UTC-3).
//
// Which meetings are hers is Rust's (agenda_proto.rs, tested over the same
// fixtures); this checks what the island does with them: the local day, how
// far off each one is, and which heads-up comes next.
//
// Run by scripts/test-agenda-rules.sh, after the Swift suite.

process.env.TZ = "America/Sao_Paulo";

import {
  dayStamp, focus, localDay, nextReminder, phase, reminderKey,
  type AgendaDepartment, type AgendaMeeting,
} from "../windows/src/core/agendaRules.ts";

let failures = 0;
function check(label: string, got: unknown, expected: unknown) {
  const g = JSON.stringify(got), e = JSON.stringify(expected);
  if (g === e) console.log(`  ✓ ${label}`);
  else { console.log(`  ✗ ${label}\n    got:      ${g}\n    expected: ${e}`); failures++; }
}

const at = (iso: string) => Date.parse(iso);
const hm = (ms: number) => {
  const d = new Date(ms);
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
};

function meeting(id: string, start: string, end: string, title: string, dept: AgendaDepartment = "onboarding",
                  extra: Partial<AgendaMeeting> = {}): AgendaMeeting {
  return { attemptId: id, meetingId: `m-${id}`, caseId: `c-${id}`, department: dept, stageKey: "connection",
           startMs: at(start), endMs: at(end), title, publicId: null, attemptSequence: 1,
           attemptState: "confirmed", meetingState: "open", ...extra };
}

const a = [
  meeting("a12", "2026-11-19T12:00:00Z", "2026-11-19T13:30:00Z", "Studio 2 / actuar"),
  meeting("a1a", "2026-11-19T13:30:00Z", "2026-11-19T15:00:00Z", "Cliente 3"),
  meeting("a0a", "2026-11-19T17:30:00Z", "2026-11-19T19:00:00Z", "Academia 1 | TOLETUS"),
];
const contacts = [
  meeting("b2a", "2026-11-19T14:00:00Z", "2026-11-19T15:00:00Z", "Studio 6 / actuar", "backoffice"),
];

console.log("Agenda (island): the day");
const [start, end] = localDay(at("2026-11-19T15:00:00Z"));
check("starts at local midnight", new Date(start).toISOString(), "2026-11-19T03:00:00.000Z");
check("and ends at the next", new Date(end).toISOString(), "2026-11-20T03:00:00.000Z");
check("day stamp, late evening", dayStamp(at("2026-11-20T02:30:00Z")), "2026-11-19");

console.log("Agenda (island): the clock");
check("16 minutes out", phase(a[0], at("2026-11-19T11:44:00Z")), { kind: "upcoming", minutes: 16 });
check("half a minute out rounds up", phase(a[0], at("2026-11-19T11:59:30Z")), { kind: "upcoming", minutes: 1 });
check("on the minute it starts", phase(a[0], at("2026-11-19T12:00:00Z")), { kind: "now" });
check("after it ends", phase(a[0], at("2026-11-19T13:30:00Z")), { kind: "ended" });
check("held", phase({ ...a[0], meetingState: "attended" }, at("2026-11-19T11:00:00Z")), { kind: "done" });
check("focus is the next one", focus(a, at("2026-11-19T13:31:00Z"))?.title, "Cliente 3");
check("nothing left to focus", focus(a, at("2026-11-19T20:00:00Z")), null);

console.log("Agenda (island): heads-up");
const lead = 15 * 60_000;
const both = new Set<AgendaDepartment>(["onboarding", "backoffice"]);
function reminder(now: string, notified: string[] = [], departments = both, meetings = a): string {
  const r = nextReminder(meetings, at(now), lead, new Set(notified), departments);
  return r ? `${r.meeting.title} at ${hm(r.fireAtMs)}` : "nil";
}
check("15 minutes before the first", reminder("2026-11-19T11:00:00Z"), "Studio 2 / actuar at 08:45");
check("late but not started: right away", reminder("2026-11-19T11:50:00Z"), "Studio 2 / actuar at 08:50");
check("once announced, the next one", reminder("2026-11-19T11:50:00Z", [reminderKey(a[0])]), "Cliente 3 at 10:15");
check("a started meeting is never announced", reminder("2026-11-19T12:00:00Z"), "Cliente 3 at 10:15");
check("a process switched off is quiet",
      reminder("2026-11-19T11:00:00Z", [], new Set<AgendaDepartment>(["backoffice"])), "nil");
check("after the last one, nothing", reminder("2026-11-19T17:31:00Z"), "nil");
check("Backoffice alone still rings for contacts",
      reminder("2026-11-19T12:00:00Z", [], new Set<AgendaDepartment>(["backoffice"]), contacts), "Studio 6 / actuar at 10:45");
const moved = { ...a[0], startMs: a[0].startMs + 3_600_000, endMs: a[0].endMs + 3_600_000 };
check("an attempt moved in place is announced again",
      reminder("2026-11-19T11:50:00Z", [reminderKey(a[0])], both, [moved]), "Studio 2 / actuar at 09:45");

console.log(failures === 0 ? "All island agenda checks passed." : `${failures} island agenda check(s) failed.`);
if (failures > 0) process.exit(1);
