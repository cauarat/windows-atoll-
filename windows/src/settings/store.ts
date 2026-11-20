// The Settings window's shared state: the preferences, what boot said, which
// Credential Manager keys hold something, the bottom status line, and the
// events from Rust. Every pane reads and writes through here.
//
// `settings` is ONE object, mutated in place and never reassigned, so a pane
// can `import { settings }` and always see the current values.

import {
  Bridge, IS_TAURI, onEvent,
  type ConnectionStatus, type MessageSource, type UpdateState,
} from "../core/bridge";
import { DEFAULT_SETTINGS, type Settings, type SourceStatus } from "../core/state";
import { resolve, setLanguage } from "../core/i18n";

// ── Preferences ───────────────────────────────────────────────────────────────

/** The live preferences. Mutate a field, then call `save()`. */
export const settings: Settings = { ...DEFAULT_SETTINGS };

/** Writes `settings` through Rust, which broadcasts "settings-changed" to every window. */
export async function save(): Promise<void> {
  await Bridge.saveSettings(settings);
}

/** Never more pills than this switched on at once. */
export const MAX_ACTIVE = 4;

// ── What boot said ────────────────────────────────────────────────────────────

export const boot = {
  /** "0.1.22" — shown in the sidebar header and the Updates group. */
  version: "",
  /** The account's name, raw — what an empty "Your name" falls back to. */
  accountName: null as string | null,
  /** Whether this build can read what is playing (false on Linux). */
  media: false,
  /** The last update state Rust reported; kept current by the "update-state" event. */
  update: null as UpdateState | null,
};

/**
 * The Credential Manager keys boot checks, so a pane can say "(stored)"
 * without a round trip. A pane that cares about another key calls
 * `refreshSecret(key)` itself.
 */
export const SECRET_KEYS = [
  "anthropic-api-key",
  "mattermost-url", "mattermost-login", "mattermost-password",
  "ato-email", "ato-password",
  // Not a secret: "1" once a phone has been linked (whatsapp.rs).
  "whatsapp-linked",
] as const;

/** key → whether the Credential Manager holds a value for it. Mutated in place. */
export const secrets: Record<string, boolean> = {};

/** Asks Rust again whether `key` holds something, and records the answer. */
export async function refreshSecret(key: string): Promise<boolean> {
  const present = (await Bridge.secretPresent(key)) ?? false;
  secrets[key] = present;
  return present;
}

/** Last reported connection per message source, as far as this window has heard. */
export const connection: Partial<Record<MessageSource, SourceStatus>> = {};

// ── Events ────────────────────────────────────────────────────────────────────

/**
 * - "settings": Rust broadcast a settings change (the tray's master switch, the
 *   island, another save). `settings` already holds the new values.
 * - "active": the set of active pills changed (from a pane in this window).
 * - "connection": a message source's connection state changed (`connection`).
 * - "update": the updater's state changed (`boot.update`).
 */
export type Topic = "settings" | "active" | "connection" | "update";

const paneListeners = new Map<Topic, Set<() => void>>();
const lasting = new Map<Topic, Set<() => void>>();

/**
 * Calls `fn` on every `topic`. Scoped to the pane being rendered: the shell
 * drops every pane subscription before it renders a pane again, so a pane can
 * subscribe freely in its render function without leaking. Pass
 * `{ lasting: true }` for one that outlives pane changes.
 */
export function subscribe(topic: Topic, fn: () => void, opts: { lasting?: boolean } = {}): () => void {
  const table = opts.lasting ? lasting : paneListeners;
  let set = table.get(topic);
  if (!set) table.set(topic, (set = new Set()));
  set.add(fn);
  return () => { set!.delete(fn); };
}

/** Runs every subscriber of `topic`. */
export function emit(topic: Topic): void {
  for (const table of [lasting, paneListeners]) {
    for (const fn of [...(table.get(topic) ?? [])]) fn();
  }
}

/** Shell only: forgets every pane-scoped subscription. */
export function clearPaneSubscriptions(): void {
  paneListeners.clear();
}

// ── The status bar ────────────────────────────────────────────────────────────

let statusText = "";
let statusPainter: (text: string) => void = () => {};

/**
 * Shows one line at the bottom of the detail pane, the Mac's `statusMessage`:
 * every save and connect message goes here ("✓ Key saved.", "❌ Startup: …").
 * Drawn in red when it starts with ❌, secondary otherwise. Pass text that is
 * already translated. Cleared when the sidebar selection changes.
 */
export function setStatus(text: string): void {
  statusText = text;
  statusPainter(statusText);
}

export function clearStatus(): void {
  setStatus("");
}

export function currentStatus(): string {
  return statusText;
}

/** Shell only: the function that draws the status bar. */
export function setStatusPainter(fn: (text: string) => void): void {
  statusPainter = fn;
  fn(statusText);
}

// ── Language ──────────────────────────────────────────────────────────────────

/**
 * Puts the chosen language in force and tells Rust, whose tray cannot read the
 * system language on Windows without a crate for it. Call `rerenderAll()`
 * (shell.ts) afterwards to redraw the window in it.
 */
export function applyLanguage(): void {
  setLanguage(settings.language);
  void Bridge.setLanguage(resolve(settings.language));
}

// ── Boot ──────────────────────────────────────────────────────────────────────

/**
 * Reads everything the panes need once, so a pane change costs no round trip.
 * Outside Tauri (plain Vite, the preview grid) every Bridge call is a no-op,
 * so it fills in believable stand-ins instead.
 */
export async function loadStore(): Promise<void> {
  const info = await Bridge.boot();
  if (info) {
    Object.assign(settings, info.settings);
    boot.version = info.version;
    boot.accountName = info.accountName ?? null;
    boot.media = info.media;
  } else if (!IS_TAURI) {
    boot.version = "0.1.22";
    boot.accountName = "Alex Morgan";
    boot.media = true;
  }
  // Before the first pane is built, so nothing is drawn in English and then
  // corrected a frame later.
  applyLanguage();
  boot.update = await Bridge.updateState();
  for (const key of SECRET_KEYS) secrets[key] = (await Bridge.secretPresent(key)) ?? false;

  void onEvent<Settings>("settings-changed", (s) => {
    Object.assign(settings, s);
    emit("settings");
    // The dots read the pill switches as well as the connection.
    emit("connection");
  });

  void onEvent<UpdateState>("update-state", (next) => {
    boot.update = next;
    emit("update");
  });

  // Rust used to address this at the island alone, so it never reached this
  // window: the dots fell back to what is stored, and a failure latched once
  // stayed on screen however the credentials changed. It is sent here too now.
  void onEvent<ConnectionStatus>("message-status", (status) => {
    connection[status.source] = { state: status.state, detail: status.detail };
    emit("connection");
  });
}
