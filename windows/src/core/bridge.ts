// Thin wrapper over the Tauri commands/events. Every call is a no-op when the
// page is opened in a plain browser, so the island can be iterated on with
// `npm run dev` alone.

import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import type { Settings } from "./state";

export const IS_TAURI =
  typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

/**
 * The arguments for a reply.
 *
 * Both commands take the same two, whichever source they address: Tauri matches
 * parameters by name, so a command whose Rust signature says `channel_id` while
 * this sends `ticketId` fails at the one moment nobody is watching — after the
 * reply has been typed. One spelling on both sides is what keeps that honest.
 */
function replyArgs(
  conversationId: string,
  body: string,
  attachments: string[] = [],
): Record<string, unknown> {
  return { conversationId, body, attachments };
}

async function call<T>(cmd: string, args?: Record<string, unknown>): Promise<T | null> {
  if (!IS_TAURI) return null;
  try {
    return await invoke<T>(cmd, args);
  } catch (err) {
    console.error(`[coucou] ${cmd} failed`, err);
    return null;
  }
}


/**
 * The display the island lives on, in logical pixels.
 *
 * `work*` is the display less whatever the taskbar keeps. A dropped point is a
 * fraction of *that*, so the island cannot draw itself at one without it.
 */
export interface ScreenInfo {
  x: number;
  y: number;
  width: number;
  height: number;
  scale: number;
  workX: number;
  workY: number;
  workWidth: number;
  workHeight: number;
}

export interface BootInfo {
  settings: Settings;
  /** Logical screen rect of the monitor the island lives on. */
  screen: ScreenInfo;
  version: string;
  hookPath: string;
  /** False where the OS has no global cursor (Wayland): see Island.followPageCursor. */
  cursorPoll: boolean;
  /** Whether this build can read what is playing — false on Linux, for now. */
  media: boolean;
  /** The last run crashed and Windows started this one. See lib.rs RECOVERED_ARG. */
  recovered: boolean;
}

/** One thing that was copied. Mirrors `clipboard::ClipEntry`. */
export interface ClipEntry {
  id: string;
  kind: "text" | "image";
  /** The text. Empty for an image. */
  body: string;
  /** An image's thumbnail, raw RGBA base64'd — drawn onto a canvas, because
   *  sending a PNG would mean carrying an encoder in Rust. */
  thumb: string;
  thumbW: number;
  thumbH: number;
  bytes: number;
  copiedAt: number;
  favourite: boolean;
}

export const Bridge = {
  boot: () => call<BootInfo>("boot"),

  saveSettings: (settings: Settings) => call<void>("save_settings", { settings }),

  /** Shrink the window down to the invisible wake strip (hidden) or back to full. */
  setCollapsed: (collapsed: boolean) => call<void>("set_collapsed", { collapsed }),
  /**
   * Tells Rust which language the tray should draw itself in.
   *
   * The webview is the only half that can read the system language on Windows,
   * so it is the one that resolves "system" -- see core/i18n.ts.
   */
  setLanguage: (language: string) => call<void>("set_language", { language }),

  /**
   * Pushes the island shape in window coordinates. Rust flips click-through from
   * its own cursor poll, so the flag is never a frame behind a click.
   */
  setIslandRect: (x: number, y: number, width: number, height: number) =>
    call<void>("set_island_rect", { x, y, width, height }),

  /** Give the window keyboard focus (chat field) and take it away again. */
  focusWindow: (focused: boolean) => call<void>("focus_window", { focused }),

  toggleClipboardWindow: () => call<void>("toggle_clipboard_window"),
  closeClipboardWindow: () => call<void>("close_clipboard_window"),
  clipboardEntries: () => call<[ClipEntry[], boolean]>("clipboard_entries"),
  clipboardSetWatching: (on: boolean) => call<void>("clipboard_set_watching", { on }),
  clipboardCopy: (id: string) => call<boolean>("clipboard_copy", { id }),
  clipboardToggleFavourite: (id: string) => call<void>("clipboard_toggle_favourite", { id }),
  clipboardRemove: (id: string) => call<void>("clipboard_remove", { id }),
  clipboardClear: () => call<void>("clipboard_clear"),

  /** Play, pause, skip or seek whatever the system is playing. */
  mediaCommand: (action: MediaAction, position?: number) =>
    call<void>("media_command", { action, position: position ?? null }),
  reposition: () => call<void>("reposition"),

  /**
   * The island has been held long enough to come unstuck; from here it follows
   * the pointer. Both points are in the window's own logical pixels.
   */
  startIslandDrag: (centreX: number, centreY: number, pointerX: number, pointerY: number) =>
    call<void>("start_island_drag", { centreX, centreY, pointerX, pointerY }),

  /**
   * Moves a picked-up island by how far the pointer has gone since the press.
   * Only needed where there is no global cursor for Rust to read (Wayland);
   * elsewhere the poll thread moves the window itself, in the same tick it
   * reads the pointer.
   */
  dragIsland: (dx: number, dy: number) => call<void>("drag_island", { dx, dy }),

  /** Puts the island down where it is. A no-op if it was never picked up. */
  endIslandDrag: () => call<void>("end_island_drag"),

  openUrl: (url: string) => call<void>("open_url", { url }),

  /** t("Open terminal") → opens the folder in VS Code when `code` is on PATH. */
  openInVSCode: (path: string | null) => call<boolean>("open_in_vscode", { path }),
  /** Launch an application by absolute path — the pill whose second click
   *  opens a desktop app rather than a web page. False if it is not there. */
  openApplication: (path: string) => call<boolean>("open_application", { path }),
  /** Open a message service the way the user reaches it — its page, or the
   *  app they chose. Resolved in Rust: the server address lives in the secret
   *  store, which the front end cannot read. */
  openMessageService: (source: MessageSource) =>
    call<void>("open_message_service", { source }),

  quit: () => call<void>("quit_app"),

  openSettingsWindow: () => call<void>("open_settings_window"),

  /** Writes to %LOCALAPPDATA%\Coucou\coucou.log, next to the Rust lines. */
  log: (message: string) => call<void>("log_line", { message }),

  // ── Claude Code hooks ─────────────────────────────────────────────────────
  hooksStatus: () => call<HookStatus>("hooks_status"),
  /** Diff to show before anything is written. `install: false` previews removal. */
  hooksPreview: (install: boolean) => callOrThrow<HookPreview>("hooks_preview", { install }),
  /**
   * Writes ~/.claude/settings.json — only ever after an explicit click, and only
   * when the file still matches the preview the user looked at.
   */
  hooksApply: (install: boolean, fingerprint: string) =>
    callOrThrow<string>("hooks_apply", { install, fingerprint }),

  approvalDecision: (requestId: string, decision: "allow" | "deny") =>
    call<void>("approval_decision", { requestId, decision }),
  /** t("The card is up") — until this lands the relay only waits a moment. */
  approvalAck: (requestId: string) => call<void>("approval_ack", { requestId }),
  /** t("Nobody can act on this") — Claude Code asks in the terminal right away. */
  approvalDecline: (requestId: string) => call<void>("approval_decline", { requestId }),

  // ── Chat, files, secrets ──────────────────────────────────────────────────
  /** One chat turn. The API key and any file bytes never leave Rust. */
  chatSend: (query: string, context: ChatContext | null) =>
    callOrThrow<{ text: string }>("chat_send", { query, context }),
  chatReset: () => call<void>("chat_reset"),
  /** Copies a dropped file into the inbox. */
  ingestFile: (path: string) => callOrThrow<DroppedFile>("ingest_file", { path }),
  /**
   * Writes pasted bytes into the inbox and hands back a real path.
   *
   * A pasted *file* already has one; a pasted *image* does not, and the
   * clipboard watcher cannot help — it keeps a 40 px thumbnail and throws the
   * original pixels away.
   */
  ingestBytes: (name: string, bytes: number[]) =>
    callOrThrow<DroppedFile>("ingest_bytes", { name, bytes }),
  /** Only ever tells you whether a key exists — never its value. */
  secretPresent: (key: string) => call<boolean>("secret_present", { key }),
  secretSet: (key: string, value: string) => callOrThrow<void>("secret_set", { key, value }),
  secretClear: (key: string) => callOrThrow<void>("secret_clear", { key }),

  // ── Messages (Mattermost, ClickMassa) ─────────────────────────────────────
  /**
   * Posts a reply into a Mattermost channel. Throws, unlike most of this file:
   * a reply that silently went nowhere is worse than a card saying why.
   */
  mattermostSendReply: (conversationId: string, body: string, attachments: string[] = []) =>
    callOrThrow<void>("mattermost_send_reply", replyArgs(conversationId, body, attachments)),
  /** Posts a reply onto a ClickMassa ticket. */
  clickmassaSendReply: (conversationId: string, body: string) =>
    callOrThrow<void>("clickmassa_send_reply", replyArgs(conversationId, body)),
  /**
   * Signs in again, now, throwing the stored session away first.
   *
   * A supervisor that has been refused waits for the credentials to change
   * rather than retrying on a timer, and notices within a few seconds by
   * itself. This is for the person who has just typed a password and is
   * watching the dot.
   */
  mattermostSignIn: () => callOrThrow<void>("mattermost_sign_in"),
  /**
   * The one the card calls. Both sources take the same two arguments, so the
   * pop-up never switches on a source string — it just hands the message back.
   */
  sendReply: (
    source: MessageSource,
    conversationId: string,
    body: string,
    attachments: string[] = [],
  ) =>
    source === "mattermost"
      ? callOrThrow<void>("mattermost_send_reply",
                          replyArgs(conversationId, body, attachments))
      // ClickMassa has no upload route to aim at, so a reply there is words
      // only; the card never offers the clip for it.
      : callOrThrow<void>("clickmassa_send_reply", replyArgs(conversationId, body)),

  // ── The pages the island opens ────────────────────────────────────────────
  //
  // Each is a window of its own, anchored to the island every time it is shown.
  // Both answer with whether the page ended up on screen, because the island
  // holds itself open while one is up: a page flush against a card that folded
  // away would be left hanging in mid-air.
  /** The globe: the configured page, anchored to the island. */
  toggleSiteWindow: () => call<boolean>("toggle_site_window"),
  /** The chat tab, when it is set to open ChatGPT rather than the built-in chat. */
  toggleWebchatWindow: () => call<boolean>("toggle_webchat_window"),
  /** Puts both away, when the island stops being expanded. */
  hidePages: () => call<void>("hide_pages"),

  // ── AI Agents ─────────────────────────────────────────────────────────────
  /**
   * What Claude Code has been doing, and what it cost.
   *
   * Read off disk every time rather than pushed: the dashboard asks while it is
   * on screen and nothing reads the transcripts when it is not.
   */

  // ── Updates ───────────────────────────────────────────────────────────────
  /** Where things stand, for a settings window that has just opened. */
  updateState: () => call<UpdateState>("update_state"),
  /** Check now — runs whether or not the six-hourly check is switched on. */
  updateCheck: () => call<void>("update_check"),
  /** Download, verify the signature, install, restart. Only ever from a click. */
  updateInstall: () => call<void>("update_install"),

  /** Tray → Pause. Stops the integration pollers, not just the island. */
};

/**
 * `update::UpdateState`. The "update-state" event carries the same shape, so a
 * window that was open while something changed and one that just opened and
 * called `updateState()` draw from exactly the same object.
 */
export interface UpdateState {
  phase: "idle" | "checking" | "upToDate" | "available" | "downloading" | "ready" | "error";
  /** The version on offer, once there is one. */
  version: string | null;
  notes: string | null;
  /** 0…1 while the package is coming down. */
  progress: number;
  error: string | null;
  /** False for the portable .zip and for .deb/.rpm: those get `releaseUrl` instead. */
  installable: boolean;
  /**
   * The release is signed with a key this build does not carry, so it could
   * never install it. `installable` is false too; this says which of the two
   * reasons it is, because they need different sentences.
   */
  keyMismatch: boolean;
  releaseUrl: string;
}

// ── Messages ─────────────────────────────────────────────────────────────────
// These three mirror `src-tauri/src/messages.rs` exactly. Both structs carry
// `#[serde(rename_all = "camelCase")]`, so `conversation_id` arrives as
// `conversationId` and `timestamp_ms` as `timestampMs`.

// ── Now Playing ──────────────────────────────────────────────────────────────
// Mirrors `src-tauri/src/media.rs::MediaState`, which carries
// `#[serde(rename_all = "camelCase")]`.

/** The "media" event. */
export interface MediaState {
  hasTrack: boolean;
  isPlaying: boolean;
  title: string;
  artist: string;
  album: string;
  /**
   * Where playback had got to when Rust sampled it, not now.
   *
   * The card advances it against its own clock while `isPlaying`, the way
   * `PlaybackState.estimatedTime` does on the Mac — which is why one event a
   * second would be wasteful and none arrives unless something changed.
   */
  elapsed: number;
  duration: number;
  /** The application it is coming from, in words. */
  sourceName: string;
  /** Its raw id — an AUMID on Windows. */
  sourceId: string;
  /** A complete `data:` URL, or empty when the player sent no art. */
  artwork: string;
}

export type MediaAction = "play" | "pause" | "playpause" | "next" | "previous" | "seek";

export type MessageSource = "mattermost" | "clickmassa";

/** `message_proto::KIND_*`, plus the fallback the clients use. */
export type MessageKind = "directMessage" | "mention" | "channel" | "generic";

export type ConnectionState = "disconnected" | "connecting" | "connected" | "failed";

/** The "message" event — `messages::MessageEvent`. */
export interface MessageEvent {
  /** The source's own id, which is what makes a replayed history harmless. */
  id: string;
  source: MessageSource;
  kind: MessageKind;
  sender: string;
  /** Null for a direct message, where the sender is the conversation. */
  channel: string | null;
  /** What a reply is addressed to: a Mattermost channel, a ClickMassa ticket. */
  conversationId: string | null;
  body: string;
  /** Milliseconds since the epoch — straight into `new Date()`. */
  timestampMs: number;
  link: string | null;
}

/** The "message-status" event — `messages::ConnectionStatus`. */
export interface ConnectionStatus {
  source: MessageSource;
  state: ConnectionState;
  /** The username when connected, the reason when failed. */
  detail: string | null;
}

export type ChatContext =
  | { kind: "file"; name: string; path: string }
  | { kind: "window"; appName: string; title: string; url?: string };

export interface DroppedFile {
  name: string;
  path: string;
  size: number;
}

export interface HookStatus {
  installed: boolean;
  settingsPath: string;
  hookPath: string;
  hookReady: boolean;
}

export interface HookPreview {
  diff: string;
  backup: string;
  settingsPath: string;
  /** Hand back to hooksApply so only the reviewed diff is ever written. */
  fingerprint: string;
}

/** Same as `call`, but surfaces the error so the UI can show what went wrong. */
async function callOrThrow<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  if (!IS_TAURI) throw new Error("not running inside Notchy");
  return invoke<T>(cmd, args);
}

export type BridgeEvent =
  | { name: "cursor"; payload: { x: number; y: number } }
  | { name: "tray"; payload: string }
  | { name: "hook"; payload: Record<string, unknown> }
  | { name: "message"; payload: MessageEvent }
  | { name: "message-status"; payload: ConnectionStatus }
  | { name: "update-state"; payload: UpdateState }
  | { name: "screen-changed"; payload: ScreenInfo };

export interface DragDropPayload {
  type: "enter" | "over" | "drop" | "leave";
  paths?: string[];
}

/** Files dragged onto the island. Only reaches us when the window takes the mouse. */
export async function onDragDrop(handler: (e: DragDropPayload) => void) {
  if (!IS_TAURI) return () => {};
  return getCurrentWebview().onDragDropEvent((event) => {
    handler(event.payload as DragDropPayload);
  });
}

export async function onEvent<T>(name: string, handler: (payload: T) => void) {
  if (!IS_TAURI) return () => {};
  return listen<T>(name, (e) => handler(e.payload));
}
