// Thin wrapper over the Tauri commands/events. Every call is a no-op when the
// page is opened in a plain browser, so the island can be iterated on with
// `npm run dev` alone.

import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import type { Settings } from "./state";
import type { AgendaSnapshot } from "./agendaRules";

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
  /**
   * The name on the account, raw — the sign-in name on Windows, the passwd
   * entry's full name on Linux, null when there is none. Run it through
   * `firstNameFromFullName` (core/greetingName.ts) before saying it: a login
   * handle like "cauat" gives no name, the same rule as the Mac.
   */
  accountName: string | null;
  /**
   * The screen the welcome opened on while its window is up — "welcome", or
   * the one `NOTCHY_ONBOARDING` asks for — and null the rest of the time. The
   * island boots under a first-run welcome when this is set, and holds its
   * greeting until "onboarding-finished".
   */
  welcome: string | null;
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
  /**
   * Why the close shortcut is not registered, when it was asked for and the
   * system refused it; null when it took. Read after a save, which is when
   * Rust registers it.
   */
  closeShortcutError: () => call<string | null>("close_shortcut_error"),
  /**
   * Why the last change to "Launch at startup" did not reach the system; null
   * when it went through. Read after a save that changed it: Rust has already
   * put the stored value back to what the system has, and broadcast it.
   */
  autostartError: () => call<string | null>("autostart_error"),

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

  /**
   * Give the window keyboard focus (chat field) and take it away again. Taking
   * it away does not move the foreground: the island keeps it until it folds,
   * as the Mac's panel stays key until then, and the fold's `pageHideAll` gives
   * it back to the window that had it — the Mac's `resignKey`.
   */
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
  /** Today's meetings from the commercial panel; the island hands in the day. */
  agendaRefresh: (dayStartMs: number, dayEndMs: number) =>
    call<AgendaSnapshot>("agenda_refresh", { dayStartMs, dayEndMs }),
  /** The panel's agenda for one process, in the browser. */
  agendaOpen: (department: string) => call<void>("agenda_open", { department }),

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

  /**
   * Opens Settings — folding the island first and placing the window under it,
   * as the Mac does — on `section` when one is named (an id from
   * settings/sections.ts: "island", "integrations", "hydration", …), otherwise
   * on the pane it last showed.
   */
  openSettingsWindow: (section?: string) =>
    call<void>("open_settings_window", { section: section ?? null }),

  /**
   * The welcome is over — Open Notchy, Skip, or its red button. Rust stamps
   * `onboardingVersion`, hides the welcome's window and sends
   * "onboarding-finished" to it and to the island, which says hello.
   */
  finishOnboarding: () => call<void>("finish_onboarding"),
  /**
   * Settings' "Show the welcome again…": the welcome's window, from its first
   * screen, over an island that keeps running.
   */
  showOnboarding: () => call<void>("show_onboarding"),
  /** The welcome's background, pressed: the window follows the pointer. */
  dragOnboardingWindow: () => call<void>("drag_onboarding_window"),

  /** Writes to %LOCALAPPDATA%\Coucou\coucou.log, next to the Rust lines. */
  log: (message: string) => call<void>("log_line", { message }),


  approvalDecision: (requestId: string, decision: "allow" | "deny") =>
    call<void>("approval_decision", { requestId, decision }),
  /** t("The card is up") — until this lands the relay only waits a moment. */
  approvalAck: (requestId: string) => call<void>("approval_ack", { requestId }),
  /** t("Nobody can act on this") — Claude Code asks in the terminal right away. */
  approvalDecline: (requestId: string) => call<void>("approval_decline", { requestId }),

  // ── Chat, files, secrets ──────────────────────────────────────────────────
  /**
   * One chat turn. The API key and any file bytes never leave Rust. `name` is
   * what Mochi calls the user (`greetingName`), for the system prompt.
   */
  chatSend: (query: string, context: ChatContext | null, name: string | null = null) =>
    callOrThrow<{ text: string }>("chat_send", { query, context, name }),
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

  // ── Messages (Mattermost, Ato) ─────────────────────────────────────
  /**
   * Posts a reply into a Mattermost channel. Throws, unlike most of this file:
   * a reply that silently went nowhere is worse than a card saying why.
   */
  mattermostSendReply: (conversationId: string, body: string, attachments: string[] = []) =>
    callOrThrow<void>("mattermost_send_reply", replyArgs(conversationId, body, attachments)),
  /** Posts a reply into an Ato conversation, files uploaded first. */
  atoSendReply: (conversationId: string, body: string, attachments: string[] = []) =>
    callOrThrow<void>("ato_send_reply", replyArgs(conversationId, body, attachments)),
  /**
   * Signs in again, now, throwing the stored session away first.
   *
   * A supervisor that has been refused waits for the credentials to change
   * rather than retrying on a timer, and notices within a few seconds by
   * itself. This is for the person who has just typed a password and is
   * watching the dot.
   */
  mattermostSignIn: () => callOrThrow<void>("mattermost_sign_in"),
  /** The same, for Ato: the stored session is thrown away and it signs in now. */
  atoSignIn: () => callOrThrow<void>("ato_sign_in"),
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
    // All that differs is the command name. Mattermost uploads files first
    // and posts ids, as Ato does through Actuar's storage; WhatsApp hands them
    // to the page — but that is the Rust side's business, not this one's.
    callOrThrow<void>(SEND_REPLY_COMMAND[source], replyArgs(conversationId, body, attachments)),
  /**
   * A received Ato voice message's audio, as raw bytes — Rust fetches it
   * through Actuar's storage, which answers a short-lived address for it.
   */
  atoVoiceNote: (storageFileId: string) =>
    callOrThrow<ArrayBuffer>("ato_voice_note", { storageFileId }),
  /**
   * A received Mattermost photo, as raw bytes — the server's preview, or the
   * file itself when it made none. Rust holds the session; the card makes a
   * blob of what comes back.
   */
  mattermostPhoto: (fileId: string, hasPreview: boolean) =>
    callOrThrow<ArrayBuffer>("mattermost_photo", { fileId, hasPreview }),
  /** Opens a received Mattermost photo whole, in the system's image viewer. */
  mattermostOpenPhoto: (fileId: string, name: string, mimeType: string) =>
    callOrThrow<void>("mattermost_open_photo", { fileId, name, mimeType }),
  /** Copy on a message card: the sender's words, on the clipboard. */
  copyMessageText: (text: string) => callOrThrow<void>("copy_message_text", { text }),
  /** Copy on a message card: a Mattermost photo's original, as the image. */
  copyMessagePhoto: (fileId: string, name: string, mimeType: string) =>
    callOrThrow<void>("copy_message_photo", { fileId, name, mimeType }),
  /** Copy on a message card: an Ato voice message, as the audio file. */
  copyMessageVoice: (storageFileId: string, fileName: string) =>
    callOrThrow<void>("copy_message_voice", { storageFileId, fileName }),
  /** Shows WhatsApp Web for the QR code. Linking a phone is the sign-in. */
  whatsappShowLogin: () => callOrThrow<void>("whatsapp_show_login"),
  /** Unlinks this machine and clears the page's profile. */
  whatsappSignOut: () => callOrThrow<void>("whatsapp_sign_out"),

  // ── The pages the island draws ────────────────────────────────────────────
  //
  // ChatGPT ("webchat") and the site ("site") are native webviews Rust lays
  // over the card the island draws for them — a child of the island's own
  // window on Windows, a borderless window glued over the same rect on Linux.
  // island/pageHost.ts is what drives these; nothing else should.
  /**
   * Puts the page over `x, y, width, height` — the card's rect in the island
   * page's CSS px, inset by its 1 px stroke — loading it first if it is cold.
   * Rust shows it once it is "ready", on its own if it is still loading, unless
   * `pageHide` comes first. Answers with where the page stands.
   */
  pageShow: (label: PageLabel, x: number, y: number, width: number, height: number) =>
    call<PageState>("page_show", { label, x, y, width, height }),
  /**
   * Hides it at once — before any shrink starts, because a native page cannot
   * follow the island's spring — and starts its cold timer.
   *
   * `away`: the user left this screen for another island view, which is not
   * the island moving under it. The site goes cold at once then, as the Mac
   * blanks NotchSiteView the moment it disappears; ChatGPT keeps its 600 s.
   * The keyboard stays with the island either way: it is still open, and in
   * use. False for the island's own hides while it moves or settles.
   */
  pageHide: (label: PageLabel, away = false) => call<void>("page_hide", { label, away }),
  /**
   * Every page: the screen closed — the island folding, the close shortcut,
   * Escape, either X. The site goes cold at once, ChatGPT starts its 600 s,
   * and the keyboard goes back to the window that had it before the island.
   */
  pageHideAll: () => call<void>("page_hide_all"),
  pageReload: (label: PageLabel) => call<void>("page_reload", { label }),
  /** The site only; nothing when it cannot go back. */
  pageBack: (label: PageLabel) => call<void>("page_back", { label }),
  /** The page's current address, in the default browser. */
  pageOpenInBrowser: (label: PageLabel) => call<void>("page_open_in_browser", { label }),

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

/** Which page: ChatGPT, or the site. Contract values, matching web.rs. */
export type PageLabel = "webchat" | "site";

/**
 * Where a page stands — the "page-state" event, and what `pageShow` answers.
 *
 * - `cold`: nothing loaded and nothing talking to anyone (about:blank).
 * - `loading`: on its way; the island draws its dots under it.
 * - `ready`: loaded, and on screen whenever it has been asked to be.
 * - `blocked`: the main frame came back 403 or 503 — `status` says which.
 * - `failed`: it could not load at all — `error` is WebView2's name for why.
 */
export interface PageState {
  label: PageLabel;
  state: "cold" | "loading" | "ready" | "blocked" | "failed";
  status?: number;
  error?: string;
  url?: string;
  title?: string;
  canGoBack: boolean;
}

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

/** The Tauri command each source replies through. */
const SEND_REPLY_COMMAND: Record<MessageSource, string> = {
  mattermost: "mattermost_send_reply",
  ato: "ato_send_reply",
  whatsapp: "whatsapp_send_reply",
};

export type MediaAction = "play" | "pause" | "playpause" | "next" | "previous" | "seek";

export type MessageSource = "mattermost" | "ato" | "whatsapp";

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
  /** What a reply is addressed to: a Mattermost channel, an Ato conversation. */
  conversationId: string | null;
  body: string;
  /** Milliseconds since the epoch — straight into `new Date()`. */
  timestampMs: number;
  link: string | null;
  /**
   * A voice message, when that is what this was — Ato only. `body` then holds
   * its transcript, or says it is a voice message until there is one.
   */
  audio?: AtoAudio | null;
  /**
   * A photo, when one came — Mattermost only. `body` then says so, with what
   * was written beside it; the card draws the photo itself.
   */
  photo?: MessagePhoto | null;
  /**
   * What the sender wrote, exactly — absent when they wrote nothing: a voice
   * message, a photo alone, a file. What Copy puts on the clipboard; `body`
   * cannot, being what the card *says* ("📷 Photo", "📎 Sent a file").
   */
  text?: string | null;
}

/** `message_proto::MessagePhoto`: a received photo — `InboxPhoto` on the Mac. */
export interface MessagePhoto {
  /** What `mattermostPhoto` is asked for. */
  fileId: string;
  name: string;
  mimeType: string;
  /** Zero when the server did not say. */
  pixelWidth: number;
  pixelHeight: number;
  hasPreview: boolean;
  byteCount: number;
  /** A tiny JPEG, base64, drawn blurred while the photo is on its way. */
  miniPreview: string | null;
  /** What was written with it; null when the photo came alone. */
  caption: string | null;
  /** Other photos on the same post. */
  more: number;
}

/** `message_proto::AtoAudio`: a received voice message. */
export interface AtoAudio {
  attachmentId: string;
  /** What `atoVoiceNote` is asked for. */
  storageFileId: string;
  fileName: string;
  contentType: string;
  durationSeconds: number | null;
  transcriptStatus: "none" | "pending" | "ready" | "failed" | "skipped";
  /** Set only when the status is "ready". */
  transcript: string | null;
}

/** The "message-updated" event — a transcript landing on a message already shown. */
export interface MessageUpdate {
  id: string;
  body: string;
  audio: AtoAudio | null;
  /** Only present when the update is the photo arriving. */
  photo?: MessagePhoto | null;
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
  | { name: "message-updated"; payload: MessageUpdate }
  | { name: "update-state"; payload: UpdateState }
  | { name: "screen-changed"; payload: ScreenInfo }
  | { name: "page-state"; payload: PageState }
  /** Escape, pressed while a page has the keyboard: the island's own Escape. */
  | { name: "page-escape"; payload: { label: PageLabel } }
  /** Debug builds, `NOTCHY_SMOKE_VIEW` set: open this view as its control would. */
  | { name: "smoke-open-view"; payload: string };

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
