// What the settings window is made of, and in what order.
//
// The macOS window is the original: a sidebar of nine rows beside a detail pane,
// with one of those rows — Dynamic Island — carrying four sub-tabs of its own.
// This is that list, so the two platforms put the same setting in the same place
// and a person who uses both only has to learn it once.
//
// Kept as data rather than built into the markup because
// tests/settings-parity.ts reads it and compares it against
// NotchBuddy/Sources/App/SettingsView.swift. Where they disagree the build goes
// red, which is the only thing that has ever stopped these two drifting apart.
//
// Like the other tables compared across platforms, every title here stays in
// English: it is the catalogue key, and the translation happens where it is
// drawn. tests/i18n.ts enforces that.

import type { ICONS } from "../views/icons.ts";

export interface SettingsSection {
  /** The Mac's `.tag(…)`. Stable: it is what gets stored. */
  id: string;
  /** English — the catalogue key, translated where it is drawn, never here. */
  title: string;
  /** The hex the Mac fills the row's rounded square with. */
  color: string;
  /** The SF Symbol the Mac draws. Carried so the parity test has something the
   *  two platforms genuinely share; this platform draws `icon` instead. */
  symbol: string;
  /** The stand-in path in views/icons.ts that is drawn here. */
  icon: keyof typeof ICONS;
}

/** The sidebar, top to bottom. */
export const SETTINGS_SECTIONS: SettingsSection[] = [
  { id: "general",      title: "General",       color: "#8E939C", symbol: "gearshape.fill",                    icon: "gearFill" },
  { id: "activepills",  title: "Active pills",  color: "#F5A524", symbol: "square.grid.2x2.fill",              icon: "grid" },
  { id: "island",       title: "Dynamic Island", color: "#EC4899", symbol: "capsule.fill",                     icon: "capsule" },
  { id: "aiagents",     title: "AI Agents",     color: "#E07950", symbol: "sparkles",                          icon: "sparkles" },
  { id: "agents",       title: "Agents",        color: "#3B9EFF", symbol: "terminal.fill",                     icon: "code" },
  { id: "chat",         title: "Chat",          color: "#E07950", symbol: "bubble.left.and.bubble.right.fill", icon: "bubble" },
  { id: "integrations", title: "Integrations",  color: "#7C5CFF", symbol: "puzzlepiece.extension.fill",        icon: "puzzle" },
  { id: "characters",   title: "Characters",    color: "#2DD4BF", symbol: "face.smiling.inverse",              icon: "smiley" },
];

/**
 * Dynamic Island's four sub-tabs, in the Mac's order.
 *
 * Four tabs rather than four sidebar rows for the reason given in
 * IslandSettingsView.swift: they are all the same object seen from different
 * angles, and the sidebar is long enough already.
 */
export const ISLAND_TABS: { id: string; title: string }[] = [
  { id: "layout",   title: "Layout" },
  { id: "content",  title: "Content" },
  { id: "activity", title: "Activity" },
  { id: "behavior", title: "Behavior" },
];

/**
 * Rows the Mac has and this platform does not. Every entry needs a reason, and
 * the parity test checks each one still exists on the Mac — so the day the
 * radial menu lands here, the test tells you to delete the line rather than
 * letting the exemption quietly swallow it.
 */
export const MAC_ONLY_SECTIONS: { id: string; why: string }[] = [
  { id: "radial", why: "the two-button mouse chord has no implementation on this platform" },
];

export const DEFAULT_SECTION = "general";
export const DEFAULT_ISLAND_TAB = "layout";

/** Falls back rather than showing a blank pane when a stored id has gone away. */
export function sectionFor(id: string | null): SettingsSection {
  return SETTINGS_SECTIONS.find((s) => s.id === id) ?? SETTINGS_SECTIONS[0];
}
