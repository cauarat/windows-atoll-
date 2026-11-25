// App state — mirror of AppState.swift (the parts the island needs).

import type { ReplyAttachment } from "./attachments";
import type { BotEmoteName, BotStateName, IslandMode, IslandViewName } from "./layout";
import type {
  AtoAudio, ConnectionState, MediaState, MessageEvent, MessageFile, MessageKind, MessagePhoto, MessageSource,
  MessageUpdate,
} from "./bridge";
import { islandOwner } from "./owner";
import type { EyeShape } from "../mochi/engine";
import { DEFAULT_POSITION, type IslandPosition } from "./anchor";
import { defaults as ringDefaults, type EdgeButton } from "./edgeRing";
import { characterFromStorage, type MochiCharacter } from "../mochi/character";
import type { Language } from "./i18n";

export type AgentSource = "claudeCode" | "n8n" | "agent";
export type PillBadge = "approval" | "finished" | "error";

export interface AgentTask {
  id: string;
  name: string;
  color: string;
  state: BotStateName;
  stepIndex: number;
  steps: string[];
  source: AgentSource;
  isIntegration: boolean;
  emote?: BotEmoteName | null;
  miniEye?: EyeShape | null;
  pillBadge?: PillBadge | null;
  sessionCwd?: string | null;
}

export interface ApprovalInfo {
  requestId: string;
  sessionId: string;
  tool: string;
  command: string;
}

export interface ChatMessage {
  id: number;
  role: "user" | "assistant";
  content: string;
}

export type PromptContext =
  | { kind: "window"; appName: string; title: string; url?: string }
  | { kind: "file"; name: string; path?: string };

export interface ResultItem {
  label: string;
  detail: string;
  url?: string;
}

export interface SearchResult {
  title: string;
  items: ResultItem[];
  note?: string;
}

// ── Messages ─────────────────────────────────────────────────────────────────
// Port of MessageInbox.swift, minus everything the island already owns: no
// persistence, no popup styles, no freshness window.

/** A message that arrived, plus whether it has been seen. */
export interface InboxMessage {
  id: string;
  source: MessageSource;
  kind: MessageKind;
  sender: string;
  channel: string | null;
  conversationId: string | null;
  body: string;
  timestampMs: number;
  link: string | null;
  read: boolean;
  /** A voice message — see `MessageEvent.audio`. */
  audio?: AtoAudio | null;
  /** A photo — see `MessageEvent.photo`. */
  photo?: MessagePhoto | null;
  /** What the sender wrote, exactly — see `MessageEvent.text`. */
  text?: string | null;
  /** Every file that came with it — see `MessageEvent.files`. */
  files?: MessageFile[] | null;
}

/** Where a source stands, as Rust last reported it. */
export interface SourceStatus {
  state: ConnectionState;
  detail: string | null;
}

export const MESSAGE_SOURCES: readonly MessageSource[] = ["mattermost", "ato", "whatsapp"];

/** Pill id per source. Contract values, matching `messages.rs`. */
export const PILL_FOR_SOURCE: Record<MessageSource, string> = {
  mattermost: "integration_mattermost",
  ato: "integration_ato",
  whatsapp: "integration_whatsapp",
};

/**
 * What the Home tab shows — port of HomeContent.swift.
 *
 * Home used to be whichever pill was in focus, which in practice meant the
 * VS Code card, always. The default now is the message services as one queue,
 * so Home holds the last thing any of them said and the notification is still
 * there when you go back to it.
 *
 * In the picker's order, which is the Swift enum's. The labels and hints are
 * the catalogue keys, translated where they are drawn; tests/home-content-parity.ts
 * holds all of it to HomeContent.swift.
 */
export type HomeContent =
  | "notifications" | "automatic" | "ato" | "mattermost" | "whatsapp" | "timer" | "claudeCode";

export const HOME_CONTENTS: readonly HomeContent[] =
  ["notifications", "automatic", "ato", "mattermost", "whatsapp", "timer", "claudeCode"];

export const HOME_LABEL: Record<HomeContent, string> = {
  notifications: "Notifications",
  automatic: "Last message",
  ato: "Ato",
  mattermost: "Mattermost",
  whatsapp: "WhatsApp",
  timer: "Timer",
  claudeCode: "Claude Code",
};

export const HOME_HINT: Record<HomeContent, string> = {
  notifications: "Every message service as one queue — Home keeps the last thing any of them said, and keeps it while something is playing.",
  automatic: "Your message services take turns — Home keeps whichever spoke last, and hands over to whatever is playing while something is.",
  ato: "Home keeps the last Ato message.",
  mattermost: "Home keeps the last Mattermost message.",
  whatsapp: "Home keeps the last WhatsApp message.",
  timer: "Home is the focus timer.",
  claudeCode: "Home is the integration you have in focus.",
};

/**
 * Which source Home should draw, or null when this choice is not a message —
 * `HomeContent.source(lastSource:)`.
 *
 * The whole of "they take turns" is here, over two plain values. Looking the
 * message up afterwards needs no rule. Notifications draws exactly what
 * automatic draws; what sets it apart is that a song never takes Home from it,
 * and that rule is `homeShowsPlayer`'s.
 */
export function homeSource(content: HomeContent, lastSource: MessageSource | null): MessageSource | null {
  switch (content) {
    case "notifications":
    case "automatic": return lastSource;
    case "ato": return "ato";
    case "mattermost": return "mattermost";
    case "whatsapp": return "whatsapp";
    default: return null;
  }
}

export const SOURCE_LABEL: Record<MessageSource, string> = {
  mattermost: "Mattermost",
  ato: "Ato",
  whatsapp: "WhatsApp",
};

/** Nothing playing — what the card draws before the first event arrives. */
export const EMPTY_MEDIA: MediaState = {
  hasTrack: false,
  isPlaying: false,
  title: "",
  artist: "",
  album: "",
  elapsed: 0,
  duration: 0,
  sourceName: "",
  sourceId: "",
  artwork: "",
};

/** The Now Playing pill's own red — `PillCatalog.swift`'s `integration_music`. */
export const MUSIC_COLOR = "#FA2D48";

/** MessageSource.accentHex from MessageInbox.swift. */
export const SOURCE_COLOR: Record<MessageSource, string> = {
  mattermost: "#1B6FF3",
  // The blue of Ato's mascot — its front layer, Actuar's own.
  ato: "#1B2FEB",
  whatsapp: "#25D366",
};

/** The message source a pill drives, or null for every other pill. */
export function sourceForPill(id: string): MessageSource | null {
  return MESSAGE_SOURCES.find((s) => PILL_FOR_SOURCE[s] === id) ?? null;
}

/** How a connection state reads, in the island card and in settings alike. */
export const CONNECTION_LABEL: Record<ConnectionState, string> = {
  disconnected: "Not connected",
  connecting: "Connecting…",
  connected: "Connected",
  failed: "Connection failed",
};

export const CONNECTION_COLOR: Record<ConnectionState, string> = {
  disconnected: "#8C8C8C",
  connecting: "#F5A524",
  connected: "#22C55E",
  failed: "#F4505E",
};

/** Enough to scroll, not enough to grow without bound. */
const MAX_MESSAGES = 50;

const task = (
  id: string, name: string, color: string, source: AgentSource,
): AgentTask => ({
  id, name, color, state: "idle", stepIndex: 0, steps: [], source, isIntegration: true,
});

/** The pill that stands for both message services — `PillCatalog.notificationsID`. */
export const NOTIFICATIONS_PILL = "integration_notifications";

/**
 * The pill that loads whether or not it was switched on, because the hook
 * relay needs somewhere to put a session that just arrived —
 * `PillCatalog.alwaysLoadedID`.
 */
export const ALWAYS_LOADED_PILL = "integration_claude";

/** AgentTask.integrationAgents — same ids, names and colours as macOS. */
export const INTEGRATION_AGENTS: AgentTask[] = [
  // Named for what it is. "VS Code" was the editor it was first wired to, and
  // it has not meant that for a long time.
  task("integration_claude", "Claude Code", "#F5F6F8", "claudeCode"),
  task("integration_music", "Now Playing", MUSIC_COLOR, "n8n"),
  task("integration_mattermost", "Mattermost", SOURCE_COLOR.mattermost, "n8n"),
  task("integration_ato", "Ato", SOURCE_COLOR.ato, "n8n"),
  task("integration_whatsapp", "WhatsApp", SOURCE_COLOR.whatsapp, "n8n"),
  // One pill over both message services. White because it stands for no brand:
  // every other pill wears the colour of the thing behind it, and this one is
  // the island's own.
  task(NOTIFICATIONS_PILL, "Notifications", "#FFFFFF", "n8n"),
];

export const TOGGLEABLE_INTEGRATION_IDS = [
  NOTIFICATIONS_PILL, "integration_mattermost", "integration_ato", "integration_music",
  "integration_whatsapp",
];

/** What an integration poller last reported. */
export interface IntegrationInfo {
  data: Record<string, unknown>;
  error: string | null;
  loaded: boolean;
  configured: boolean;
}

export interface Settings {
  /** The master switch. False means Coucou is off. */
  enabled: boolean;
  soundEnabled: boolean;
  soundVolume: number;
  autoCloseInterval: number;
  absenceInterval: number;
  /**
   * Standby: once the island has folded away, leave it folded until a message
   * arrives — the wake strip stops answering the mouse.
   *
   * Retired: the Mac has no such thing, Settings no longer offers it (W-15),
   * and settings.rs's version-1 migration switched it off for everyone. Still
   * carried, because Rust's Settings has the field and this side writes the
   * whole object back.
   */
  standby: boolean;
  /**
   * Always visible: the island never folds away. With nothing left to say it
   * rests as the compact bar in its corner rather than retracting into the
   * screen edge. "Never", beside "Hide after … s without movement", in
   * Settings › General.
   */
  alwaysVisible: boolean;
  activeIntegrations: string[];
  screen: "primary" | "cursor";
  /** Which of the six spots on that display the island sits in. */
  /**
   * One of the six names, or `free:fx,fy` for an island that was dragged where
   * the user wanted it. One field either way — see core/anchor.ts.
   */
  position: IslandPosition | string;
  /** What the Home tab shows. */
  homeContent: HomeContent;
  /**
   * Which language every string is shown in. "system" asks the OS.
   *
   * The same key and the same spellings as the Mac preference -- see
   * NotchBuddy/Sources/App/AppLanguage.swift -- and core/i18n.ts resolves it.
   */
  language: Language;
  /**
   * Which character each pill wears, keyed by pill id, and the one everything
   * else gets. Stored as `"accessory:eye"` — see mochi/character.ts.
   */
  pillCharacters: Record<string, string>;
  defaultCharacter: string;
  /**
   * Whether the characters are drawn at all. Not the master switch: every job
   * the island has it keeps, and only the faces go. The compact bar and the
   * drop keep theirs — there Mochi is the only thing on screen.
   */
  hideCharacters: boolean;
  /**
   * How far the player's two round buttons jump, in seconds.
   *
   * Apart, because they are usually wanted apart — a longer jump forward
   * clears an ad, a shorter one back catches what you missed. The number is
   * drawn on the button, so these are a label as well as a distance.
   */
  skipBackSeconds: number;
  skipForwardSeconds: number;
  /**
   * What a second click on a message pill opens: "website", or the path to an
   * application. One click opens the island either way.
   *
   * A path here, where macOS stores a bundle identifier — same setting, each
   * platform's own way of naming an app.
   */
  mattermostOpenTarget: string;
  atoOpenTarget: string;
  whatsappOpenTarget: string;
  autostart: boolean;
  hooksInstalled: boolean;
  /** Claude model used by the chat. */
  model: string;
  /**
   * Which buttons hang off the island's border, and on which side. Null means
   * "not chosen yet": the ring is then dealt from the active pills.
   */
  islandEdgeButtons: EdgeButton[] | null;
  /** The page the globe on the island opens, in the island. */
  siteUrl: string;
  /** Whether the chat tab opens ChatGPT instead of the built-in chat. */
  webChat: boolean;
  /**
   * Whether the message card grows to hold the whole message instead of
   * clamping it to two lines. Off by default — two lines and an ellipsis is
   * the card that ships, and the rest is behind Open.
   */
  messageFullBody: boolean;
  /**
   * Snow on the island's floor, from 15 November to 6 January. On unless
   * somebody turns it off; outside the season it does nothing at all.
   */
  islandSnow: boolean;
  /**
   * Christmas music as the greeting plays, from 15 November to 6 January. On
   * unless somebody turns it off; the Christmas album on the player plays it
   * whenever it is clicked, whichever way this is set.
   */
  christmasMusic: boolean;
  /**
   * The Agenda tab: today's meetings from Actuar's commercial panel, with a
   * heads-up before each. Off unless somebody turns it on.
   */
  agendaEnabled: boolean;
  /** Minutes before a meeting to open the island: 5, 10, 15, 30 or 60. */
  agendaLeadMinutes: number;
  /** Which processes give a heads-up; both are always listed. */
  agendaNotifyOnboarding: boolean;
  agendaNotifyBackoffice: boolean;
  /** Whether Coucou looks for a new release on its own, every six hours. */
  autoUpdate: boolean;
  /**
   * Whether a global shortcut closes the island. Off by default: it takes its
   * keys away from every other app. Registered by Rust (src-tauri/src/shortcut.rs).
   */
  closeShortcutEnabled: boolean;
  /** That shortcut, as core/shortcut.ts records it — "Ctrl+Alt+X". */
  closeShortcut: string;
  /**
   * What Mochi calls the user — in the launch greeting and in the chat. As
   * typed in the welcome or under Settings › General, trimmed; cleaned where
   * it is read (`greetingName` in core/greetingName.ts). Empty means the
   * account's own first name, when it has one worth greeting.
   */
  userName: string;
  /**
   * Which welcome this install has been through: `ONBOARDING_VERSION` once it
   * has been finished, skipped or closed, 0 before — core/onboarding.ts.
   */
  onboardingVersion: number;
  /**
   * Which of settings.rs's migrations this settings.json has been through —
   * `SETTINGS_VERSION` there. Rust's alone to write: it keeps its own value
   * whatever a page sends back, so a page never changes it.
   */
  settingsVersion: number;
}

export const DEFAULT_SETTINGS: Settings = {
  enabled: true,
  soundEnabled: true,
  soundVolume: 0.12,
  autoCloseInterval: 5,
  absenceInterval: 180,
  standby: false,
  alwaysVisible: true,
  activeIntegrations: [
    NOTIFICATIONS_PILL, "integration_mattermost", "integration_ato", "integration_music",
  ],
  screen: "primary",
  position: DEFAULT_POSITION,
  homeContent: "notifications",
  language: "system",
  pillCharacters: {},
  defaultCharacter: "-:-",
  hideCharacters: false,
  skipBackSeconds: 10,
  skipForwardSeconds: 10,
  mattermostOpenTarget: "website",
  atoOpenTarget: "website",
  whatsappOpenTarget: "website",
  autostart: false,
  hooksInstalled: false,
  model: "claude-opus-5",
  islandEdgeButtons: null,
  siteUrl: "https://caus-macbook-pro.tail8e18f9.ts.net/",
  webChat: false,
  messageFullBody: false,
  islandSnow: true,
  christmasMusic: true,
  agendaEnabled: false,
  agendaLeadMinutes: 15,
  agendaNotifyOnboarding: true,
  agendaNotifyBackoffice: true,
  autoUpdate: true,
  closeShortcutEnabled: false,
  closeShortcut: "Ctrl+Alt+X",
  userName: "",
  onboardingVersion: 0,
  settingsVersion: 1,
};

/**
 * What the Settings fields accept, field by field, as [min, max] — the Mac's
 * `SettingsDefaults` ranges. The panes clamp to these, and
 * tests/settings-defaults.ts holds them to tests/fixtures/settings-defaults.json.
 */
export const SETTINGS_RANGES = {
  soundVolume: [0, 0.2],
  autoCloseInterval: [2, 120],
  absenceInterval: [5, 3600],
  skipBackSeconds: [1, 120],
  skipForwardSeconds: [1, 120],
} as const satisfies Partial<Record<keyof Settings, readonly [number, number]>>;

/**
 * The buttons on the island's border: the stored choice, or — while nothing
 * has been chosen — a ring dealt from the pills that are on.
 *
 * The always-loaded pill is left out of the dealing, which is what the Mac
 * does with it. Claude Code is the one pill every session routes to, so it
 * loads whether or not it was chosen — but that is a reason to keep it loaded,
 * not a reason to spend a disc on it. It is still a line away in the ring
 * editor for anyone who wants it there.
 *
 * The island (`State.edgeButtons`) and the ring editor in Settings both ask
 * here, so the ring Settings shows is the ring the island draws.
 */
export function edgeButtonsFor(
  settings: Pick<Settings, "islandEdgeButtons" | "activeIntegrations">,
): EdgeButton[] {
  const chosen = settings.islandEdgeButtons;
  if (chosen) return chosen;
  const active = settings.activeIntegrations;
  return ringDefaults(
    INTEGRATION_AGENTS
      .map((task) => task.id)
      .filter((id) => id !== ALWAYS_LOADED_PILL && active.includes(id)),
  );
}

type Listener = () => void;

class AppState {
  mode: IslandMode = "hidden";
  view: IslandViewName = "overview";

  tasks: AgentTask[] = [];
  focusId: string | null = null;

  stateOverride: BotStateName | null = null;

  /** Cursor in logical screen pixels, origin top-left (like AppState.mousePosition). */
  mouse = { x: 0, y: 0 };
  /** Cursor relative to the island's top-left corner. */
  mouseInIsland = { x: 0, y: 0 };

  isPinned = false;

  /**
   * Derived from the master switch rather than held separately.
   *
   * There used to be a second flag here, set from the tray and never written to
   * disk, so the app came back on after every restart. One source of truth means
   * the guards that already read `State.paused` keep working untouched.
   */
  get paused(): boolean {
    return !this.settings.enabled;
  }

  /** What is playing, as Rust last reported it. See `island/media.ts`. */
  media: MediaState = EMPTY_MEDIA;

  /**
   * Whether this build can read what is playing at all — `BootInfo.media`.
   *
   * False on Linux, which has no GSMTC. The pill is then left out of the island
   * entirely rather than offered as one of four slots for a card that can never
   * fill; settings carried over from a Windows machine cannot resurrect it.
   * Defaults to true so a plain browser preview still draws the card.
   */
  mediaAvailable = true;

  /**
   * The name on the account Notchy runs under, raw — `BootInfo.accountName`.
   *
   * What the greeting and the chat fall back to when nothing was typed under
   * Your name; `greetingName` decides whether it is a name at all, so a login
   * handle never gets said out loud. Null in a plain browser preview.
   */
  accountName: string | null = null;

  /**
   * Home is holding the player, with something in it — `AppState.homeShowsPlayer`.
   *
   * Two routes reach the same card: Home on automatic while something is
   * loaded, or the Now Playing pill in focus. An empty player needs neither the
   * taller island nor the gutter, so it is not one of them.
   */
  get homeShowsPlayer(): boolean {
    if (!this.media.hasTrack) return false;
    if (this.settings.homeContent === "automatic") return true;
    // `focusTask`, not `focusId`: that is what the card itself is chosen by, and
    // the island's height has to be decided by the same question as its content.
    //
    // Whatever Home is pinned to. Pinning says a song must not *take* Home; it
    // never said the player was unreachable, and with the `claudeCode` test
    // that used to be here it was — clicking the pill left the island on
    // whatever it already had. Mirrors `HomeContent.playerTakesHome`.
    return this.focusTask?.id === "integration_music";
  }

  uploadProgress = 0;
  uploadDuration = 2.4;
  fileDragOver = false;

  promptContext: PromptContext | null = null;
  droppedFile: { name: string; path: string } | null = null;
  /** Everything that came in on the same drop, `droppedFile` included. */
  droppedFiles: { name: string; path: string }[] = [];

  /**
   * When the voice note being recorded started, or null.
   *
   * Holds the card open for the same reason `pickingFile` does: the microphone
   * is a click, not a focus, so nothing else is pinning the island while
   * someone talks into it, and the idle timer would fold the card away
   * mid-sentence.
   */
  recordingSince: number | null = null;

  /**
   * Files staged on the reply being written, in the order they arrived.
   *
   * Deliberately not `droppedFile`: that one belongs to the upload → choose
   * flow and survives it, while these live only until the reply is sent or
   * the card is dismissed.
   */
  replyAttachments: ReplyAttachment[] = [];
  /** A file is hovering over an open reply box rather than over the notch. */
  replyDragOver = false;
  /** Why the last file was turned away, or null. */
  replyNotice: string | null = null;
  /**
   * The file picker is up for the reply box.
   *
   * The dialog takes focus, which blurs the input and un-pins the card; this
   * holds it open so the draft and the other attachments survive the trip.
   */
  pickingFile = false;
  noteMessage: string | null = null;
  searchResult: SearchResult | null = null;
  chatHistory: ChatMessage[] = [];
  pendingApproval: ApprovalInfo | null = null;

  integrations: Record<string, IntegrationInfo> = {};

  /** Newest first, capped at MAX_MESSAGES. */
  messages: InboxMessage[] = [];
  /** Which message the pop-up is showing; null falls back to the newest. */
  activeMessageId: string | null = null;
  /**
   * The newest from each source, kept whether or not it has been read, and who
   * spoke last. `activeMessage` empties when a message is answered; Home needs
   * the opposite — the last thing each source said, still there after the
   * notification has folded away.
   */
  lastBySource: Partial<Record<MessageSource, InboxMessage>> = {};
  lastSource: MessageSource | null = null;
  /**
   * Whose list is open, null when nobody is in one.
   *
   * `"all"` is the Notifications pill: one queue over both services, rather
   * than a service picked to be first.
   */
  listSource: MessageSource | "all" | null = null;
  /** Per-source connection state, keyed by MessageEvent.source. */
  messageStatus: Record<string, SourceStatus> = {};

  lastActivity = performance.now();

  settings: Settings = { ...DEFAULT_SETTINGS };

  private listeners = new Set<Listener>();

  subscribe(fn: Listener): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  /** Marks the UI dirty; the island re-renders on the next frame. */
  notify() {
    for (const fn of this.listeners) fn();
  }

  get focusTask(): AgentTask | null {
    return this.tasks.find((t) => t.id === this.focusId) ?? this.tasks[0] ?? null;
  }

  get effectiveState(): BotStateName {
    return this.stateOverride ?? this.focusTask?.state ?? "idle";
  }

  get otherTasks(): AgentTask[] {
    return this.tasks.filter((t) => t.id !== this.focusId);
  }

  setFocus(id: string) {
    const t = this.tasks.find((x) => x.id === id);
    if (!t) return;
    this.focusId = id;
    t.pillBadge = null;
    this.notify();
  }

  updateTask(id: string, state: BotStateName) {
    const t = this.tasks.find((x) => x.id === id);
    if (!t) return;
    t.state = state;
    this.notify();
  }

  appendStep(id: string, step: string) {
    const t = this.tasks.find((x) => x.id === id);
    if (!t) return;
    t.steps.push(step);
    if (t.steps.length > 20) t.steps.shift();
    t.stepIndex = t.steps.length - 1;
    this.notify();
  }

  setPillBadge(id: string, badge: PillBadge | null) {
    const t = this.tasks.find((x) => x.id === id);
    if (!t) return;
    t.pillBadge = badge;
    this.notify();
  }

  // ── Inbox ───────────────────────────────────────────────────────────────────

  /** What the pop-up draws: the message that arrived, or the newest one left. */
  get activeMessage(): InboxMessage | null {
    if (this.activeMessageId != null) {
      const found = this.messages.find((m) => m.id === this.activeMessageId);
      if (found) return found;
    }
    return this.messages[0] ?? null;
  }

  get unreadMessages(): InboxMessage[] {
    return this.messages.filter((m) => !m.read);
  }

  /**
   * Everything still waiting from one source, newest first.
   *
   * Sorted rather than trusted in array order: `ingestMessage` always unshifts,
   * so a reconnect replaying its history would otherwise stack older messages
   * above newer ones.
   */
  unreadList(source: MessageSource): InboxMessage[] {
    return this.messages
      .filter((m) => m.source === source && !m.read)
      .sort((a, b) => b.timestampMs - a.timestampMs);
  }

  /** Puts the card on one particular message, chosen from a list. */
  selectMessage(id: string) {
    if (!this.messages.some((m) => m.id === id)) return;
    this.activeMessageId = id;
    this.notify();
  }

  /**
   * Everything still waiting from every source, newest first.
   *
   * What the Notifications pill opens. Sorted across the sources rather than
   * concatenated, so the queue reads in the order things actually arrived.
   */
  unreadAllList(): InboxMessage[] {
    return this.messages
      .filter((m) => !m.read)
      .sort((a, b) => b.timestampMs - a.timestampMs);
  }

  /**
   * What the ring actually shows: the user's choice, or a default dealt from
   * the pills they already made active — see `edgeButtonsFor`.
   */
  get edgeButtons(): EdgeButton[] {
    return edgeButtonsFor(this.settings);
  }

  /** Opens the one queue over both services — the Notifications pill. */
  openAllMessageLists() {
    this.listSource = "all";
    this.activeMessageId = null;
    this.notify();
  }

  /** Opens a source's list. Nothing is picked out of it yet. */
  openMessageList(source: MessageSource) {
    this.listSource = source;
    this.activeMessageId = null;
    this.notify();
  }

  /** Leaves the list, so the card goes back to announcing what arrives. */
  closeMessageList() {
    if (this.listSource == null) return;
    this.listSource = null;
    this.activeMessageId = null;
    this.notify();
  }

  unreadFrom(source: MessageSource): number {
    return this.messages.reduce((n, m) => (m.source === source && !m.read ? n + 1 : n), 0);
  }

  /**
   * Takes a message in. Returns false when the id is already held, which is
   * what makes a reconnect replaying its history harmless — MessageInbox.ingest.
   */
  ingestMessage(event: MessageEvent): boolean {
    if (this.messages.some((m) => m.id === event.id)) return false;
    const stored: InboxMessage = { ...event, read: false };
    this.messages.unshift(stored);
    if (this.messages.length > MAX_MESSAGES) this.messages.length = MAX_MESSAGES;
    this.activeMessageId = event.id;
    // Set before the cap trims anything: these two outlive the history.
    this.lastBySource[event.source] = stored;
    this.lastSource = event.source;
    // What arrives takes the card — but not out from under someone reading one
    // they picked out of a list themselves.
    if (this.listSource == null) this.activeMessageId = event.id;
    this.notify();
    return true;
  }

  markMessageRead(id: string) {
    const m = this.messages.find((x) => x.id === id);
    if (!m || m.read) return;
    m.read = true;
    this.notify();
  }

  /** Answered or waved away: move the pop-up on to the next unread one. */
  /**
   * Changes a message already held, without announcing it again — what a
   * transcript arriving after its voice message does. The object is changed
   * in place, so `lastBySource` and the list hold the new text too.
   */
  updateMessage(update: MessageUpdate): InboxMessage | null {
    const message = this.messages.find((m) => m.id === update.id);
    if (!message) return null;
    message.body = update.body;
    message.audio = update.audio;
    // Absent from a transcript's update, which must not take a photo away —
    // nor the files.
    if (update.photo) message.photo = update.photo;
    if (update.files) message.files = update.files;
    this.notify();
    return message;
  }

  dismissMessage(id: string) {
    const m = this.messages.find((x) => x.id === id);
    if (m) m.read = true;
    if (this.activeMessageId === id || this.activeMessageId == null) {
      // Inside the same source while a list is open, so a reply never drops
      // someone into another service's messages.
      this.activeMessageId = this.messages.find(
        (x) => !x.read
          && (this.listSource == null || this.listSource === "all" || x.source === this.listSource),
      )?.id ?? null;
    }
    this.notify();
  }

  setMedia(media: MediaState) {
    this.media = media;
    this.notify();
  }

  setMessageStatus(source: string, status: SourceStatus) {
    this.messageStatus[source] = status;
    this.notify();
  }

  /** loadIntegrationTasks() — VS Code always on, the rest opt-in (max 4). */
  loadIntegrationTasks() {
    for (const proto of INTEGRATION_AGENTS) {
      const shouldLoad =
        (proto.id !== "integration_music" || this.mediaAvailable)
        && (proto.id === "integration_claude"
          || this.settings.activeIntegrations.includes(proto.id));
      const idx = this.tasks.findIndex((t) => t.id === proto.id);
      if (shouldLoad && idx < 0) this.tasks.push({ ...proto, steps: [] });
      if (!shouldLoad && idx >= 0) this.tasks.splice(idx, 1);
    }
    // Order: integration_claude first, then agent_* pills (visible in slice(0,4)),
    // then other integrations in declaration order.
    const order = INTEGRATION_AGENTS.map((t) => t.id);
    this.tasks.sort((a, b) => {
      const isAgentA = a.id.startsWith("agent_");
      const isAgentB = b.id.startsWith("agent_");
      // integration_claude always first
      if (a.id === "integration_claude") return -1;
      if (b.id === "integration_claude") return 1;
      // agent_* before other integrations; preserve insertion order among themselves
      if (isAgentA && !isAgentB) return -1;
      if (isAgentB && !isAgentA) return 1;
      if (isAgentA && isAgentB) return 0;
      // both known integrations → declaration order
      return order.indexOf(a.id) - order.indexOf(b.id);
    });
    if (!this.focusId) this.focusId = "integration_claude";
    this.notify();
  }

  removeTask(id: string) {
    const idx = this.tasks.findIndex((t) => t.id === id);
    if (idx < 0) return;
    this.tasks.splice(idx, 1);
    if (this.focusId === id) this.focusId = this.tasks[0]?.id ?? "integration_claude";
    this.notify();
  }

  /** Creates a dynamic agent_ pill on first event; no-ops if it already exists.
   *  Inserted right after integration_claude so it appears in the visible slice(0,4). */
  upsertExternalAgent(id: string, name: string, color: string) {
    if (this.tasks.some((t) => t.id === id)) return;
    const at = this.tasks.findIndex((t) => t.id === "integration_claude") + 1;
    this.tasks.splice(at, 0, {
      id, name, color,
      state: "idle", stepIndex: 0, steps: [],
      source: "agent", isIntegration: false,
    });
    if (!this.focusId) this.focusId = id;
    this.notify();
  }

  toggleIntegration(id: string) {
    if (id === "integration_claude") return;
    const active = this.settings.activeIntegrations;
    if (active.includes(id)) {
      this.settings.activeIntegrations = active.filter((x) => x !== id);
      if (this.focusId === id) this.focusId = "integration_claude";
    } else {
      if (active.length >= 4) return;
      this.settings.activeIntegrations = [...active, id];
    }
    this.loadIntegrationTasks();
  }

  /** The message Home should show, or null. */
  get homeMessage(): InboxMessage | null {
    const source = homeSource(this.settings.homeContent, this.lastSource);
    return source ? this.lastBySource[source] ?? null : null;
  }

  /** The character a given pill wears, falling back to the default. */
  /**
   * The pill whose character and colour the island should be wearing —
   * `AppState.characterOwnerID`. Not `focusTask`: a view that speaks for one
   * service outranks whatever was clicked last. `core/owner.ts` holds the rule.
   */
  get characterOwnerId(): string | null {
    const source = this.listSource;
    const owner = islandOwner(
      this.view,
      source && source !== "all" ? PILL_FOR_SOURCE[source] : null,
      source === "all",
      this.activeMessage ? PILL_FOR_SOURCE[this.activeMessage.source] : null,
      this.focusTask?.id ?? null,
    );
    if (owner.kind === "pill") return owner.id;
    return owner.kind === "everyService" ? NOTIFICATIONS_PILL : null;
  }

  /**
   * The brand colour that goes with `characterOwnerId`, or null for an agent
   * pill, whose body is painted from its state instead — `characterOwnerColor`.
   */
  get characterOwnerColor(): string | null {
    const id = this.characterOwnerId;
    if (!id) return null;
    const task = this.tasks.find((t) => t.id === id);
    if (task && !task.isIntegration) return null;
    return INTEGRATION_AGENTS.find((t) => t.id === id)?.color ?? task?.color ?? null;
  }

  characterFor(pillId: string | null | undefined): MochiCharacter {
    const stored = pillId ? this.settings.pillCharacters[pillId] : undefined;
    return characterFromStorage(stored ?? this.settings.defaultCharacter);
  }

  defaultView(): IslandViewName {
    return this.tasks.length === 0 ? "empty" : "overview";
  }
}

export const State = new AppState();
