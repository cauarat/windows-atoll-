// App state — mirror of AppState.swift (the parts the island needs).

import type { BotEmoteName, BotStateName, IslandMode, IslandViewName } from "./layout";
import type { ConnectionState, MessageEvent, MessageKind, MessageSource } from "./bridge";
import type { EyeShape } from "../mochi/engine";

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

export const SOURCE_LABEL: Record<MessageSource, string> = {
  mattermost: "Mattermost",
  clickmassa: "ClickMassa",
};

/** MessageSource.accentHex from MessageInbox.swift. */
export const SOURCE_COLOR: Record<MessageSource, string> = {
  mattermost: "#1B6FF3",
  clickmassa: "#00C7D9",
};

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

/** AgentTask.integrationAgents — same ids, names and colours as macOS. */
export const INTEGRATION_AGENTS: AgentTask[] = [
  task("integration_claude", "VS Code", "#F5F6F8", "claudeCode"),
  task("integration_resend", "Resend", "#22C55E", "n8n"),
  task("integration_n8n", "n8n", "#F29B38", "n8n"),
  task("integration_vercel", "Vercel", "#7C5CFF", "n8n"),
  task("integration_github", "GitHub", "#F4505E", "n8n"),
  task("integration_notion", "Notion", "#8C8C8C", "n8n"),
  task("integration_calcom", "Cal.com", "#C9956A", "n8n"),
  task("integration_stripe", "Stripe", "#0570DE", "n8n"),
  task("integration_mattermost", "Mattermost", SOURCE_COLOR.mattermost, "n8n"),
  task("integration_clickmassa", "ClickMassa", SOURCE_COLOR.clickmassa, "n8n"),
];

export const TOGGLEABLE_INTEGRATION_IDS = [
  "integration_resend", "integration_n8n", "integration_vercel", "integration_github",
  "integration_notion", "integration_calcom", "integration_stripe",
  "integration_mattermost", "integration_clickmassa",
];

/** What an integration poller last reported. */
export interface IntegrationInfo {
  data: Record<string, unknown>;
  error: string | null;
  loaded: boolean;
  configured: boolean;
}

export interface Settings {
  soundEnabled: boolean;
  soundVolume: number;
  autoCloseInterval: number;
  absenceInterval: number;
  activeIntegrations: string[];
  screen: "primary" | "cursor";
  autostart: boolean;
  hooksInstalled: boolean;
  /** Claude model used by the chat. */
  model: string;
}

export const DEFAULT_SETTINGS: Settings = {
  soundEnabled: true,
  soundVolume: 0.12,
  autoCloseInterval: 15,
  absenceInterval: 180,
  activeIntegrations: [
    "integration_resend", "integration_n8n", "integration_vercel", "integration_github",
  ],
  screen: "primary",
  autostart: false,
  hooksInstalled: false,
  model: "claude-opus-5",
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
  paused = false;

  uploadProgress = 0;
  uploadDuration = 2.4;
  fileDragOver = false;

  promptContext: PromptContext | null = null;
  droppedFile: { name: string; path: string } | null = null;
  noteMessage: string | null = null;
  searchResult: SearchResult | null = null;
  chatHistory: ChatMessage[] = [];
  pendingApproval: ApprovalInfo | null = null;

  integrations: Record<string, IntegrationInfo> = {};

  /** Newest first, capped at MAX_MESSAGES. */
  messages: InboxMessage[] = [];
  /** Which message the pop-up is showing; null falls back to the newest. */
  activeMessageId: string | null = null;
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

  unreadFrom(source: MessageSource): number {
    return this.messages.reduce((n, m) => (m.source === source && !m.read ? n + 1 : n), 0);
  }

  /**
   * Takes a message in. Returns false when the id is already held, which is
   * what makes a reconnect replaying its history harmless — MessageInbox.ingest.
   */
  ingestMessage(event: MessageEvent): boolean {
    if (this.messages.some((m) => m.id === event.id)) return false;
    this.messages.unshift({ ...event, read: false });
    if (this.messages.length > MAX_MESSAGES) this.messages.length = MAX_MESSAGES;
    this.activeMessageId = event.id;
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
      this.activeMessageId = this.messages.find((x) => !x.read)?.id ?? null;
    }
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
        proto.id === "integration_claude" || this.settings.activeIntegrations.includes(proto.id);
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

  defaultView(): IslandViewName {
    return this.tasks.length === 0 ? "empty" : "overview";
  }
}

export const State = new AppState();
