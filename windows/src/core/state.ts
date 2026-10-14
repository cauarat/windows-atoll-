// App state — mirror of AppState.swift (the parts the island needs).

import type { ReplyAttachment } from "./attachments";
import type { BotEmoteName, BotStateName, IslandMode, IslandViewName } from "./layout";
import type { ConnectionState, MediaState, MessageEvent, MessageKind, MessageSource } from "./bridge";
import type { EyeShape } from "../mochi/engine";
import { DEFAULT_POSITION, type IslandPosition } from "./anchor";
import { defaults as ringDefaults, type EdgeButton } from "./edgeRing";
import { characterFromStorage, type MochiCharacter } from "../mochi/character";

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
}

/** Where a source stands, as Rust last reported it. */
export interface SourceStatus {
  state: ConnectionState;
  detail: string | null;
}

export const MESSAGE_SOURCES: readonly MessageSource[] = ["mattermost", "clickmassa"];

/** Pill id per source. Contract values, matching `messages.rs`. */
export const PILL_FOR_SOURCE: Record<MessageSource, string> = {
  mattermost: "integration_mattermost",
  clickmassa: "integration_clickmassa",
};

/**
 * What the Home tab shows — port of HomeContent.swift.
 *
 * Home used to be whichever pill was in focus, which in practice meant the
 * VS Code card, always. The default now is that the two messaging integrations
 * take turns, so Home holds the last thing either of them said and the
 * notification is still there when you go back to it.
 */
export type HomeContent = "automatic" | "clickmassa" | "mattermost" | "timer" | "claudeCode";

export const HOME_CONTENTS: readonly HomeContent[] =
  ["automatic", "clickmassa", "mattermost", "timer", "claudeCode"];

export const HOME_LABEL: Record<HomeContent, string> = {
  automatic: "Last message",
  clickmassa: "ClickMassa",
  mattermost: "Mattermost",
  timer: "Timer",
  claudeCode: "Claude Code",
};

export const HOME_HINT: Record<HomeContent, string> = {
  automatic: "ClickMassa and Mattermost take turns — Home keeps whichever spoke last.",
  clickmassa: "Home keeps the last ClickMassa message.",
  mattermost: "Home keeps the last Mattermost message.",
  timer: "Home is the focus timer.",
  claudeCode: "Home is the integration you have in focus.",
};

/**
 * Which source Home should draw, or null when this choice is not a message.
 *
 * The whole of "they take turns" is here, over two plain values. Looking the
 * message up afterwards needs no rule.
 */
export function homeSource(content: HomeContent, lastSource: MessageSource | null): MessageSource | null {
  switch (content) {
    case "automatic": return lastSource;
    case "clickmassa": return "clickmassa";
    case "mattermost": return "mattermost";
    default: return null;
  }
}

export const SOURCE_LABEL: Record<MessageSource, string> = {
  mattermost: "Mattermost",
  clickmassa: "ClickMassa",
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
  clickmassa: "#41BFEF",
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
 * The Mochi a message carries, standing where the source's dot used to.
 *
 * The pill's live task when it is on, so a character chosen in Settings shows
 * up on the message too, and `syncMiniBotStates` keeps it in step; something
 * the same colour when it is off, because a message can arrive and be read with
 * its pill switched off.
 *
 * `null` is the queue over both services — the Notifications pill, white,
 * standing for no brand.
 */
export function messageMochiTask(source: MessageSource | null): AgentTask {
  const id = source ? PILL_FOR_SOURCE[source] : NOTIFICATIONS_PILL;
  const live = State.tasks.find((t) => t.id === id);
  if (live) return live;
  return task(
    id,
    source ? SOURCE_LABEL[source] : "Notifications",
    source ? SOURCE_COLOR[source] : "#FFFFFF",
    "n8n",
  );
}

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
  task("integration_clickmassa", "ClickMassa", SOURCE_COLOR.clickmassa, "n8n"),
  // One pill over both message services. White because it stands for no brand:
  // every other pill wears the colour of the thing behind it, and this one is
  // the island's own.
  task(NOTIFICATIONS_PILL, "Notifications", "#FFFFFF", "n8n"),
];

export const TOGGLEABLE_INTEGRATION_IDS = [
  NOTIFICATIONS_PILL, "integration_mattermost", "integration_clickmassa", "integration_music",
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
   */
  standby: boolean;
  activeIntegrations: string[];
  screen: "primary" | "cursor";
  /** Which of the six spots on that display the island sits in. */
  position: IslandPosition;
  /** What the Home tab shows. */
  homeContent: HomeContent;
  /**
   * Which character each pill wears, keyed by pill id, and the one everything
   * else gets. Stored as `"accessory:eye"` — see mochi/character.ts.
   */
  pillCharacters: Record<string, string>;
  defaultCharacter: string;
  autostart: boolean;
  hooksInstalled: boolean;
  /** Claude model used by the chat. */
  model: string;
  /**
   * Which buttons hang off the island's border, and on which side. Null means
   * "not chosen yet": the ring is then dealt from the active pills.
   */
  islandEdgeButtons: EdgeButton[] | null;
  /** The page the globe on the island opens, in a window of its own. */
  siteUrl: string;
  /** Whether the chat tab opens ChatGPT instead of the built-in chat. */
  webChat: boolean;
  /** Whether Coucou looks for a new release on its own, every six hours. */
  autoUpdate: boolean;
}

export const DEFAULT_SETTINGS: Settings = {
  enabled: true,
  soundEnabled: true,
  soundVolume: 0.12,
  autoCloseInterval: 5,
  absenceInterval: 180,
  standby: false,
  activeIntegrations: [
    NOTIFICATIONS_PILL, "integration_mattermost", "integration_clickmassa", "integration_music",
  ],
  screen: "primary",
  position: DEFAULT_POSITION,
  homeContent: "automatic",
  pillCharacters: {},
  defaultCharacter: "-:-",
  autostart: false,
  hooksInstalled: false,
  model: "claude-opus-5",
  islandEdgeButtons: null,
  siteUrl: "https://caus-macbook-pro.tail8e18f9.ts.net/",
  webChat: false,
  autoUpdate: true,
};

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
    return this.settings.homeContent === "claudeCode"
      && this.focusTask?.id === "integration_music";
  }

  uploadProgress = 0;
  uploadDuration = 2.4;
  fileDragOver = false;

  promptContext: PromptContext | null = null;
  droppedFile: { name: string; path: string } | null = null;
  /** Everything that came in on the same drop, `droppedFile` included. */
  droppedFiles: { name: string; path: string }[] = [];

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
   * the pills they already made active.
   *
   * The always-loaded pill is asked for by name and left out, which is what the
   * Mac does with it. Claude Code is the one pill every session routes to, so
   * it loads whether or not it was chosen — but that is a reason to keep it
   * loaded, not a reason to spend a disc on it. It is still a line away in the
   * ring editor for anyone who wants it there.
   */
  get edgeButtons(): EdgeButton[] {
    const chosen = this.settings.islandEdgeButtons;
    if (chosen) return chosen;
    const active = this.settings.activeIntegrations;
    return ringDefaults(
      INTEGRATION_AGENTS
        .map((task) => task.id)
        .filter((id) => id !== ALWAYS_LOADED_PILL && active.includes(id)),
    );
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
  characterFor(pillId: string | null | undefined): MochiCharacter {
    const stored = pillId ? this.settings.pillCharacters[pillId] : undefined;
    return characterFromStorage(stored ?? this.settings.defaultCharacter);
  }

  defaultView(): IslandViewName {
    return this.tasks.length === 0 ? "empty" : "overview";
  }
}

export const State = new AppState();
