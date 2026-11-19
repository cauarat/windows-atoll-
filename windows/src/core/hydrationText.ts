// Hydration: the few numbers the island and the settings window both write out.
//
// Apart from core/hydration.ts because that file is the Swift one's twin and
// knows no language; these read the language in force, so they are drawn where
// they are called and never kept.

import { hydrationAmount } from "./hydration";
import { language, t } from "./i18n";

/** "1,1 L" in Spanish and Portuguese, "1.1 L" in English. */
export function amountText(ml: number): string {
  return hydrationAmount(ml, language() === "en" ? "." : ",");
}

/** "45 min", "2 h", "1 h 30" — an interval, or how long ago the last glass was. */
export function durationText(minutes: number): string {
  const m = Math.max(0, Math.round(minutes));
  if (m < 60) return t("%lld min", m);
  const rest = m % 60;
  if (rest === 0) return t("%lld h", m / 60);
  return t("%lld h %lld", Math.floor(m / 60), String(rest).padStart(2, "0"));
}

/** "10:15" for a moment, on the machine's own clock. */
export function clockText(ms: number): string {
  const d = new Date(ms);
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

/** Follows the system setting; asked each time, since it can change under us. */
export function reducedMotion(): boolean {
  return typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;
}
