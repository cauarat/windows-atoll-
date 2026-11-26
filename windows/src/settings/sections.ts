// The Settings sidebar, row for row as SettingsView.swift lists it (the
// `SettingsSidebarRow(...)` lines in its body). A parity test compares this
// table with the Swift, so it stays a plain exported constant: same ids, same
// order, the English title (the catalogue key — translated where it is drawn),
// the SF Symbol name and the tile colour.

export interface SettingsSection {
  /** The id `settingsSection` stores and the deep links name. Stable. */
  id: string;
  /** The English title, which is the catalogue key. */
  title: string;
  /** SF Symbol name; ./icons.ts draws it. */
  symbol: string;
  /** The tile colour. */
  color: string;
}

export const SETTINGS_SECTIONS: readonly SettingsSection[] = [
  { id: "general",      title: "General",        symbol: "gearshape.fill",                    color: "#8E939C" },
  { id: "activepills",  title: "Active pills",   symbol: "square.grid.2x2.fill",              color: "#F5A524" },
  { id: "island",       title: "Dynamic Island", symbol: "capsule.fill",                      color: "#EC4899" },
  { id: "radial",       title: "Radial menu",    symbol: "circle.grid.cross.fill",            color: "#F472B6" },
  { id: "chat",         title: "Chat",           symbol: "bubble.left.and.bubble.right.fill", color: "#E07950" },
  { id: "integrations", title: "Integrations",   symbol: "puzzlepiece.extension.fill",        color: "#7C5CFF" },
  { id: "characters",   title: "Characters",     symbol: "face.smiling.inverse",              color: "#2DD4BF" },
  { id: "hydration",    title: "Hydration",      symbol: "drop.fill",                         color: "#22D3EE" },
];

/** Panes Windows does not have yet: their rows are hidden until they land. */
export const PENDING: ReadonlySet<string> = new Set(["radial"]);

/** Where Settings opens when nothing else is asked for. */
export const DEFAULT_SECTION = "general";

/** The rows the sidebar shows, in order. */
export function visibleSections(): SettingsSection[] {
  return SETTINGS_SECTIONS.filter((s) => !PENDING.has(s.id));
}

/** `id` if it names a visible section, else null. */
export function sectionId(id: string | null | undefined): string | null {
  return id && SETTINGS_SECTIONS.some((s) => s.id === id) && !PENDING.has(id) ? id : null;
}
