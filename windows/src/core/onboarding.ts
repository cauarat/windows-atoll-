// The welcome a first run shows before the island opens, as data: which screens,
// in what order, and whether this launch shows it at all.
//
// The twin of NotchBuddy/Sources/App/Onboarding.swift; tests/welcome-parity.ts
// holds the two to the same answers. No imports, so that test can load it in
// plain Node. What the screens look like is settings/onboarding.ts's business.

/** The seven screens, in the order they come. */
export const ONBOARDING_STEPS = ["welcome", "name", "language", "look", "tools", "startup", "ready"] as const;
export type OnboardingStep = (typeof ONBOARDING_STEPS)[number];

/**
 * What a finished welcome is stamped with, in `settings.onboardingVersion` — the
 * key the Mac uses too. Raise it when the welcome gains a screen everybody should
 * see: whoever finished an older one is shown the new one, once.
 */
export const ONBOARDING_VERSION = 1;

/**
 * Whether this launch opens on the welcome. Not while Notchy is switched off: the
 * welcome ends by opening the island, and an island that is off cannot.
 */
export function shouldShowOnboarding(seen: number | undefined, enabled: boolean): boolean {
  return enabled && (seen ?? 0) < ONBOARDING_VERSION;
}

/**
 * "2 of 5" for the five questions; null on the hello and on the last screen,
 * which ask nothing and so carry no progress row.
 */
export function onboardingProgress(index: number): { current: number; total: number } | null {
  const step = ONBOARDING_STEPS[index];
  if (step === undefined || step === "welcome" || step === "ready") return null;
  return { current: index, total: ONBOARDING_STEPS.length - 2 };
}
