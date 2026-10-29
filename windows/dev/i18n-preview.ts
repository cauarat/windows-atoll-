// Dev harness: one island view drawn in all three languages at once.
//
// Spanish and Portuguese run 20-30% longer than English, and the island is
// 640 px whatever language it is in. Reading the three side by side is how a
// label that has stopped fitting gets noticed before a release does it.
// Not part of the app bundle.

import "../src/style.css";
import { Bridge } from "../src/core/bridge";
import { setLanguage } from "../src/core/i18n";
import { buildAgents, type UsageSnapshot } from "../src/views/agents";

const DAY = 86_400;
const now = Math.floor(Date.now() / 1000);

function dayKey(secs: number): string {
  const d = new Date(secs * 1000);
  const p = (n: number) => `${n}`.padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

const activity = Array.from({ length: 91 }, (_, i) => {
  const back = 90 - i;
  const date = new Date((now - back * DAY) * 1000);
  const weekend = date.getDay() === 0 || date.getDay() === 6;
  return {
    date: dayKey(now - back * DAY),
    spend: weekend ? 0 : back === 23 ? 61.2 : 2 + ((back * 7) % 11),
  };
});

const SNAPSHOT: UsageSnapshot = {
  spendToday: 12.4,
  tokensToday: 1_840_000,
  cacheShareToday: 62,
  hourlyToday: Array.from({ length: 24 }, (_, h) => (h > 8 && h < 19 ? (h * 37) % 90 : 0)),
  byModel: [{ name: "claude-sonnet-4-6", spend: 9.1, tokens: 1_400_000 }],
  byProject: [{ name: "windows-atoll-", spend: 7.3, tokens: 980_000 }],
  activity,
  windowSpend: 184.5,
  activeDays: 63,
  busiestDay: { date: dayKey(now - 23 * DAY), spend: 61.2 },
  lastActivity: now - 900,
  hasUnknownModel: true,
  isEmpty: false,
};

Bridge.agentUsage = () => Promise.resolve(SNAPSHOT);

// One at a time, and awaited: the view fills itself from a promise, and three
// of them in flight at once would all finish in whichever language the loop had
// reached last. That is a harness problem rather than an app one -- the app only
// ever has one language in force -- but it makes the preview lie.
for (const lang of ["en", "es", "pt-BR"] as const) {
  setLanguage(lang);
  const host = buildAgents();
  host.el.classList.add("on");
  document.getElementById(lang)!.append(host.el);
  host.tick?.(performance.now() + 60_000);
  await new Promise((r) => setTimeout(r, 150));
}
