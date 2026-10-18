// The two decisions behind clicking a pill. Port of PillOpen.swift.
//
// A single click opens the island and nothing else; a second click on the
// same pill also opens the service behind it. Both halves are pure so the
// rule is the same on both platforms and can be read without a window.

/**
 * How long a second click still counts as part of the first. Comfortably over
 * the system double-click interval at its fastest, and short enough that two
 * deliberate visits a second apart stay two single clicks.
 */
export const DOUBLE_CLICK_WINDOW_MS = 450;

/**
 * Whether this click should also open the service.
 *
 * The first click is never held back waiting to find out — it opens the
 * island at once and this answers false. Asking the other way round would put
 * the window's delay in front of every single click.
 */
export function opensTarget(
  pill: string,
  last: { id: string; at: number } | null,
  now: number,
): boolean {
  if (!last) return false;
  // A different pill is a fresh first click, however fast it followed.
  if (last.id !== pill) return false;
  const gap = now - last.at;
  // A clock that went backwards is not a double click.
  return gap >= 0 && gap <= DOUBLE_CLICK_WINDOW_MS;
}

/** What a second click opens for a message service. */
export type PillTarget =
  | { kind: "website"; url: string }
  /** A path to an executable here, where macOS uses a bundle identifier. */
  | { kind: "application"; app: string }
  | { kind: "nothing" };

/** The stored setting's value for "the website rather than an app". */
export const WEBSITE_SETTING = "website";

/**
 * Resolve a service's second-click target.
 *
 * An app that was chosen and has since gone falls back to the website rather
 * than doing nothing: a click that silently does nothing is indistinguishable
 * from a broken one. The caller decides what "has since gone" means — here it
 * is simply whether `installedApp` was handed over.
 */
export function pillTarget(
  setting: string,
  installedApp: string | null,
  serverURL: string | null,
): PillTarget {
  const wantsApp = setting !== "" && setting !== WEBSITE_SETTING;
  if (wantsApp && installedApp) return { kind: "application", app: installedApp };
  if (serverURL) return { kind: "website", url: serverURL };
  return { kind: "nothing" };
}
