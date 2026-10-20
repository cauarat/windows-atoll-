// The two decisions behind clicking a pill. Port of PillOpen.swift.
//
// A single click opens the island and nothing else; a second click on the
// same pill also opens the service behind it. Both halves are pure so the
// rule is the same on both platforms and can be read without a window.

/** A click on a pill's button, remembered until the island it opened goes. */
export interface PillClick {
  /** Which pill's button it landed on. */
  pill: string;
  /** Where the pointer was, in screen coordinates. */
  pointer: { x: number; y: number };
}

/**
 * How far the pointer may drift between the two clicks and still be the same
 * pair — for the second click that misses the button because the button
 * moved. The slop a hand resting on a trackpad has, and no more.
 */
export const POINTER_SLOP = 6;

/**
 * Whether this click should also open the service behind `pill`.
 *
 * What makes it the second click is the island, not a stopwatch: the first
 * click is remembered while the island it opened is on screen and forgotten
 * when that closes, so "the pill I am already looking at, clicked again" is
 * the whole rule.
 *
 * It used to be a click within 450 ms, which is to say a double click at the
 * system's pace, and that is why a service opened only sometimes. Two
 * unhurried clicks are the ordinary way to click a thing twice, and a message
 * pill invites them: the first click opens the list, the island grows, and
 * anyone watching it waits to see what happened before clicking again.
 */
export function opensTarget(pill: string, last: PillClick | null): boolean {
  if (!last) return false;
  // A different pill is a fresh first click, however fast it followed.
  return last.pill === pill;
}

/**
 * Whether a click that landed on the island itself, rather than on the pill's
 * button, is the second half of that pair.
 *
 * Opening a view resizes the island and the ring hangs off its edge, so the
 * disc slides out from under a pointer that never moved and the click lands
 * on the island instead. The island is a large target and a click anywhere on
 * it is plainly not a second click — one from a pointer that has not moved
 * since the first one is.
 */
export function opensTargetAt(
  pointer: { x: number; y: number },
  last: PillClick | null,
): boolean {
  if (!last) return false;
  return (
    Math.abs(pointer.x - last.pointer.x) <= POINTER_SLOP &&
    Math.abs(pointer.y - last.pointer.y) <= POINTER_SLOP
  );
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
