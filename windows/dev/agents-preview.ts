// Dev harness: the AI Agents dashboard in a plain browser, with a fake
// snapshot, so the layout can be checked without Claude Code transcripts.
// Not part of the app bundle.

import "../src/style.css";
import { Bridge } from "../src/core/bridge";
import { buildAgents, type UsageSnapshot } from "../src/views/agents";

const DAY = 86_400;
const now = Math.floor(Date.now() / 1000);

/** `yyyy-MM-dd`, local — the shape `usage.rs` emits. */
function dayKey(secs: number): string {
  const d = new Date(secs * 1000);
  const p = (n: number) => `${n}`.padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

const activity = Array.from({ length: 91 }, (_, i) => {
  const back = 90 - i;
  // A working week with quiet weekends, and one very expensive Tuesday, so the
  // four shades and the square root are all exercised.
  const date = new Date((now - back * DAY) * 1000);
  const weekend = date.getDay() === 0 || date.getDay() === 6;
  const spend = weekend ? 0 : (back === 23 ? 61.2 : 2 + ((back * 7) % 11));
  return { day: dayKey(now - back * DAY), spend };
});

const BUSY: UsageSnapshot = {
  spendToday: 18.43,
  tokensToday: 14_200_000,
  cacheShareToday: 0.78,
  hourlyToday: Array.from({ length: 24 }, (_, h) =>
    h < 8 || h > 21 ? 0 : Math.max(0, Math.sin((h - 8) / 3) * 2.4 + 1.1)),
  byModel: [
    { name: "Opus 5.5", spend: 14.02 },
    { name: "Sonnet 5.5", spend: 3.61 },
    { name: "Haiku 5.5", spend: 0.8 },
  ],
  byProject: [
    { name: "windows-atoll-", spend: 11.9 },
    { name: "a-very-long-project-name-here", spend: 5.2 },
    { name: "notes", spend: 1.33 },
  ],
  activity,
  windowSpend: 1242.57,
  windowWeeks: 13,
  activeDays: 64,
  busiestDay: { day: dayKey(now - 23 * DAY), spend: 61.2 },
  lastActivity: now - 184,
  hasUnknownModel: true,
  isEmpty: false,
};

const EMPTY: UsageSnapshot = {
  ...BUSY,
  spendToday: 0,
  tokensToday: 0,
  cacheShareToday: 0,
  hourlyToday: new Array(24).fill(0),
  byModel: [],
  byProject: [],
  activity: activity.map((d) => ({ ...d, spend: 0 })),
  windowSpend: 0,
  activeDays: 0,
  busiestDay: null,
  lastActivity: null,
  hasUnknownModel: false,
  isEmpty: true,
};

// Each stage reads its own snapshot, so both states are on screen at once.
let next: UsageSnapshot = BUSY;
Bridge.agentUsage = () => Promise.resolve(next);

for (const [id, snapshot] of [["busy", BUSY], ["empty", EMPTY]] as const) {
  next = snapshot;
  const host = buildAgents();
  host.el.classList.add("on");
  document.getElementById(id)!.append(host.el);
  host.tick?.(performance.now() + 60_000);
}
