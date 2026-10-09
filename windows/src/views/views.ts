// Island views — DOM ports of IslandViewContent.swift. Paddings, font sizes,
// colours and wording are copied from the Swift views so both platforms read
// identically.

import { h, svg, clear, dot } from "./dom";
import { ICONS } from "./icons";
import { Ticker } from "./ticker";
import { Bridge } from "../core/bridge";
import { State, type AgentTask } from "../core/state";
import { washRGBA, type IslandViewName, type Wash } from "../core/layout";
import { FocusTimer, TIMER_COLOR, TIMER_LABEL, TIMER_PRESETS } from "../core/timer";
import { createMiniBot, pruneMiniBots } from "../mochi/minibots";
import { buildPrompt } from "./chat";
import { buildChoose, buildUpload, buildUploading } from "./upload";
import { renderIntegrationCard, type IntegrationCardHooks } from "./integrations";
import { buildMessage } from "./message";

export interface ViewActions {
  setView(v: IslandViewName): void;
  collapse(): void;
  setFocus(id: string): void;
  openTerminal(): void;
  /** The ↗ button: opens whatever the focused pill points at. */
  openTarget(): void;
  openUrl(url: string): void;
  decide(d: "allow" | "deny"): void;
  toggleSound(): void;
  setVolume(v: number): void;
  setAutoClose(seconds: number): void;
  openSettingsWindow(): void;
  /**
   * Holds the island open, or lets it close again. The reply box takes this
   * while it has the cursor: a card that slid away mid-sentence would throw the
   * sentence away with it.
   */
  setPinned(on: boolean): void;
  /**
   * Lets the island's window take the keyboard, or gives it back. Only ever
   * called from a click into a field: a card arriving must never take it.
   */
  focusField(on: boolean): void;
  blip(): void;
}

export interface ViewHost {
  el: HTMLElement;
  sync(): void;
  /** Called when the view becomes active, for views with a text field. */
  focus?(): void;
  /** Called every frame while the view is on screen. */
  tick?(nowMs: number): void;
}

// ── Shared pieces ─────────────────────────────────────────────────────────────

export function card(wash: Wash, ...children: (Node | string)[]): HTMLElement {
  const el = h("div", { class: wash ? "card wash" : "card" }, ...children);
  if (wash) el.style.setProperty("--wash", washRGBA(wash));
  return el;
}

export function btn(
  label: string,
  kind: "primary" | "secondary",
  onClick: () => void,
  kbd?: string,
): HTMLElement {
  return h(
    "button",
    { class: `btn ${kind}`, onclick: onClick },
    h("span", { text: label }),
    kbd ? h("span", { class: "kbd", text: kbd }) : null,
  );
}

/** AgentWho — coloured dot + task name + grey label. */
function agentWho(task: AgentTask | null, label: string): HTMLElement {
  const row = h("div", { class: "who-row" });
  if (task) {
    row.append(dot(task.color, 8), h("span", { class: "n", text: task.name }));
  }
  row.append(h("span", { text: label }));
  return row;
}

export function stack(padLeft: number, padRight: number, ...children: Node[]): HTMLElement {
  const el = h("div", { class: "stack" }, ...children);
  el.style.padding = `4px ${padRight}px 4px ${padLeft}px`;
  return el;
}

// ── Header ────────────────────────────────────────────────────────────────────

export function buildHeader(actions: ViewActions): ViewHost {
  const tabHome = h("button", { class: "tab", title: "Overview", onclick: () => go("overview") }, svg(ICONS.house, 13));
  const tabChat = h("button", { class: "tab", title: "Ask", onclick: () => go("prompt") }, svg(ICONS.bubble, 13));
  const tabDrop = h("button", { class: "tab", title: "Drop", onclick: () => go("upload") }, svg(ICONS.plus, 13));
  const tabPills = h("button", { class: "tab", title: "Integrations", onclick: () => go("integrations") }, svg(ICONS.grid, 13));
  const tabTimer = h("button", { class: "tab", title: "Timer", onclick: () => go("timer") }, svg(ICONS.timer, 13));
  // Not a tab: the clipboard is a window of its own, so this opens it rather
  // than changing which view the island shows.
  const tabClip = h("button", { class: "tab", title: "Clipboard",
                                onclick: () => { actions.blip(); void Bridge.toggleClipboardWindow(); } },
                    svg(ICONS.clipboard, 13));

  // The real Settings window, not the cut-down card the island used to show.
  const gearBtn = h("button", { title: "Settings",
                                onclick: () => { actions.blip(); actions.openSettingsWindow(); } },
                    svg(ICONS.gear, 14));
  const soundBtn = h("button", { title: "Mute", onclick: () => actions.toggleSound() }, svg(ICONS.speakerOn, 14));

  function go(v: IslandViewName) {
    actions.blip();
    actions.setView(v);
  }

  const el = h(
    "div",
    { id: "header" },
    // Split either side of the notch rather than piled on the left: the four
    // you reach for to do something, then the rest.
    h("div", { class: "tabs" }, tabHome, tabChat, tabDrop, tabPills),
    h("div", { class: "tabs tabs-right" }, tabTimer, tabClip),
    h("div", { class: "header-actions" }, gearBtn, soundBtn),
  );

  return {
    el,
    sync() {
      const v = State.view;
      tabHome.classList.toggle("on", v === "overview" || v === "empty");
      tabChat.classList.toggle("on", v === "prompt");
      tabDrop.classList.toggle("on", v === "upload");
      tabPills.classList.toggle("on", v === "integrations");
      tabTimer.classList.toggle("on", v === "timer");
      clear(soundBtn);
      soundBtn.append(svg(State.settings.soundEnabled ? ICONS.speakerOn : ICONS.speakerOff, 14));
      el.style.opacity = v === "confused" ? "0" : "1";
    },
  };
}

// ── Overview ──────────────────────────────────────────────────────────────────

function buildOverview(actions: ViewActions): ViewHost {
  const ticker = new Ticker();
  const who = h("div", { class: "who" });
  const tickerBody = h("div", { class: "card-body" }, who, ticker.el);
  const leftBody = h("div", { class: "left-body" });
  const jump = h(
    "button",
    { class: "icon-btn jump", title: "Open", onclick: () => actions.openTarget() },
    svg(ICONS.arrowUpRight, 8),
  );
  const left = card(null, leftBody, jump);

  // One card, full width. The pills used to take the right-hand column and are
  // their own tab now, so the overview shows the integration in focus and
  // nothing else.
  // Home is a choice now. The timer and the message card are built once and
  // swapped in, rather than this view trying to be all three.
  const timerHost = buildTimer();
  const messageHost = buildMessage(actions, true);
  const pillBody = h("div", { class: "overview solo home-face" }, h("div", { class: "left" }, left));
  // Each face fills the tab the way a view fills the island; `home-face` is what
  // `view` was doing for them before they were nested here.
  for (const host of [timerHost, messageHost]) {
    host.el.classList.remove("view");
    host.el.classList.add("home-face");
  }
  const el = h("div", { class: "view" }, pillBody, timerHost.el, messageHost.el);

  let detailOpen = false;
  let lastFocus: string | null = null;
  let mode: "ticker" | "card" | null = null;
  let cardKey = "";

  const hooks: IntegrationCardHooks = {
    get detailOpen() {
      return detailOpen;
    },
    openDetail() {
      detailOpen = true;
      cardKey = "";
      State.notify();
    },
    closeDetail() {
      detailOpen = false;
      cardKey = "";
      State.notify();
    },
    openSettings: () => actions.openSettingsWindow(),
  };

  return {
    el,
    tick(nowMs: number) {
      if (homeKind() === "pill" && mode === "ticker") ticker.tick(nowMs);
    },
    sync() {
      const kind = homeKind();
      pillBody.classList.toggle("on", kind === "pill");
      timerHost.el.classList.toggle("on", kind === "timer");
      messageHost.el.classList.toggle("on", kind === "message");
      if (kind === "timer") {
        timerHost.sync();
        return;
      }
      if (kind === "message") {
        messageHost.sync();
        return;
      }

      const task = State.focusTask;
      if (task?.id !== lastFocus) {
        lastFocus = task?.id ?? null;
        detailOpen = false;
        cardKey = "";
        mode = null;
      }

      // VS Code with a live Claude Code session keeps the ticker; every other
      // pill shows its own card, exactly like IntegrationCardView.
      const sessionActive =
        task?.id === "integration_claude" && (task.state !== "idle" || task.steps.length > 0);

      if (task && sessionActive) {
        if (mode !== "ticker") {
          clear(leftBody);
          leftBody.append(tickerBody);
          mode = "ticker";
          cardKey = "";
        }
        clear(who);
        who.append(
          dot(task.color, 7),
          h("span", { class: "name", text: task.name }),
          h("span", { class: "tool", text: task.source === "claudeCode" ? "Claude Code" : "n8n" }),
        );
        if (task.steps.length > 1) {
          who.append(h("span", {
            class: "count",
            text: `${Math.min(task.stepIndex + 1, task.steps.length)}/${task.steps.length}`,
          }));
        }
        ticker.sync(task);
      } else if (task) {
        const info = State.integrations[task.id];
        const key = [
          task.id, detailOpen, task.state, task.steps.join("|"),
          info?.loaded, info?.error, info?.configured,
          JSON.stringify(info?.data ?? {}),
        ].join("~");
        if (key !== cardKey) {
          cardKey = key;
          mode = "card";
          clear(leftBody);
          leftBody.append(renderIntegrationCard(task, hooks));
        }
      }

      jump.style.display = detailOpen ? "none" : "";
    },
  };
}

/// Which of Home's three faces is on, given the preference.
function homeKind(): "timer" | "message" | "pill" {
  const content = State.settings.homeContent;
  if (content === "timer") return "timer";
  if (content === "claudeCode") return "pill";
  return "message";
}

/**
 * The pills, on their own tab.
 *
 * They used to sit in a 278 px column beside the overview's card, which is why
 * only four fitted. Here they get the full width, and picking one goes straight
 * back to the overview so the integration you chose is what you see.
 */
function buildIntegrations(actions: ViewActions): ViewHost {
  const grid = h("div", { class: "pills pills-tab" });
  const el = h("div", { class: "view integrations" },
    card(null, h("div", { class: "pills-wrap" },
      h("div", { class: "pills-title", text: "Integrations" }),
      grid,
    )),
  );

  let key = "";
  return {
    el,
    sync() {
      const tasks = State.tasks;
      const next = tasks.map((t) => `${t.id}:${t.pillBadge ?? ""}:${t.id === State.focusId}`).join("|");
      if (next === key) return;
      key = next;
      clear(grid);
      for (const t of tasks) {
        const pill = buildPill(t, actions, () => actions.setView("overview"));
        pill.classList.toggle("focused", t.id === State.focusId);
        grid.append(pill);
      }
      pruneMiniBots();
    },
  };
}

/**
 * The timer tab: pick a length, or watch the one that is running.
 *
 * The clock lives in `FocusTimer`, not here — every view is built once and kept,
 * so state owned by this function would outlive nothing and a ticker here would
 * run while you were on Home. `sync()` is called by the island's frame loop.
 */
function buildTimer(): ViewHost {
  // ── The picker ─────────────────────────────────────────────────────────────
  const tile = (part: "hours" | "minutes" | "seconds", label: string) => {
    const input = h("input", { class: "t-tile", type: "text", inputmode: "numeric" }) as HTMLInputElement;
    const commit = () => FocusTimer.setPicker(part, Number(input.value));
    input.addEventListener("change", commit);
    input.addEventListener("blur", commit);
    // Scrolling over a number is the fastest way to nudge it, and costs nothing
    // to offer beside typing.
    input.addEventListener("wheel", (e: WheelEvent) => {
      e.preventDefault();
      FocusTimer.setPicker(part, Number(input.value) - Math.sign(e.deltaY));
    }, { passive: false });
    const wrap = h("div", { class: "t-tile-wrap" }, input, h("div", { class: "t-tile-label", text: label }));
    return { wrap, input };
  };
  const hours = tile("hours", "Hours");
  const minutes = tile("minutes", "Minutes");
  const seconds = tile("seconds", "Seconds");
  const colon = () => h("div", { class: "t-colon" }, h("i"), h("i"));

  const startBtn = h("button", { class: "t-start", onclick: () => FocusTimer.startFromPicker() },
                     h("span", { class: "t-play" }), h("span", { text: "Start" }));
  const resetBtn = h("button", { class: "t-reset", onclick: () => FocusTimer.reset() },
                     h("span", { text: "↺" }), h("span", { text: "Reset" }));

  const picker = h("div", { class: "t-picker" },
    h("div", { class: "t-tiles" }, hours.wrap, colon(), minutes.wrap, colon(), seconds.wrap),
    h("div", { class: "t-actions" }, startBtn, resetBtn),
  );

  // ── The presets ────────────────────────────────────────────────────────────
  const presets = h("div", { class: "t-presets" });
  for (const p of TIMER_PRESETS) {
    const row = h("button", { class: "t-preset", onclick: () => FocusTimer.load(p.kind, p.minutes) },
      h("span", { class: "t-dot" }),
      h("span", { class: "t-preset-text" },
        h("span", { class: "t-preset-name", text: TIMER_LABEL[p.kind] }),
        h("span", { class: "t-preset-time", text: `${String(p.minutes).padStart(2, "0")}:00` })),
    );
    (row.querySelector(".t-dot") as HTMLElement).style.background = TIMER_COLOR[p.kind];
    (row.querySelector(".t-preset-name") as HTMLElement).style.color = TIMER_COLOR[p.kind];
    presets.append(row);
  }

  const idle = h("div", { class: "t-idle" }, picker, presets);

  // ── Counting ───────────────────────────────────────────────────────────────
  const dot = h("span", { class: "timer-dot" });
  const label = h("span", { class: "timer-label" });
  const paused = h("span", { class: "timer-paused", text: "paused" });
  const clock = h("span", { class: "timer-clock" });
  const fill = h("div", { class: "timer-fill" });
  const pauseBtn = h("button", { class: "btn secondary", onclick: () => {
    if (FocusTimer.isPaused) FocusTimer.resume(); else FocusTimer.pause();
  } });
  const running = h("div", { class: "timer-running" },
    h("div", { class: "timer-row" }, dot, label, paused, clock),
    h("div", { class: "timer-track" }, fill),
    h("div", { class: "timer-actions" },
      pauseBtn,
      h("button", { class: "btn secondary", text: "+1 min", onclick: () => FocusTimer.extend() }),
      h("button", { class: "btn secondary", text: "Stop", onclick: () => FocusTimer.stop() }),
    ),
  );

  const el = h("div", { class: "view timer" }, card(null, h("div", { class: "timer-wrap" }, idle, running)));

  return {
    el,
    sync() {
      const active = FocusTimer.isActive;
      idle.style.display = active ? "none" : "";
      running.style.display = active ? "" : "none";
      if (!active) {
        // Not while it has the caret, or typing would be overwritten each frame.
        const pad = (n: number) => String(n).padStart(2, "0");
        if (document.activeElement !== hours.input) hours.input.value = pad(FocusTimer.pickerHours);
        if (document.activeElement !== minutes.input) minutes.input.value = pad(FocusTimer.pickerMinutes);
        if (document.activeElement !== seconds.input) seconds.input.value = pad(FocusTimer.pickerSeconds);
        startBtn.toggleAttribute("disabled", FocusTimer.pickerTotal <= 0);
        return;
      }
      const accent = TIMER_COLOR[FocusTimer.kind];
      dot.style.background = accent;
      label.textContent = TIMER_LABEL[FocusTimer.kind];
      paused.style.display = FocusTimer.isPaused ? "" : "none";
      clock.textContent = FocusTimer.clock;
      clock.style.color = FocusTimer.isPaused ? "var(--dim)" : "var(--ink)";
      fill.style.width = `${FocusTimer.progress * 100}%`;
      fill.style.background = accent;
      pauseBtn.textContent = FocusTimer.isPaused ? "Resume" : "Pause";
    },
  };
}

function buildPill(task: AgentTask, actions: ViewActions, after?: () => void): HTMLElement {
  const label = task.id === "integration_claude" ? "VS Code" : task.name;
  const canvas = createMiniBot(task, 24);
  const pill = h(
    "div",
    { class: "pill", onclick: () => { actions.setFocus(task.id); after?.(); } },
    canvas,
    h("span", { class: "lbl", text: label }),
  );
  pill.style.borderColor = `${task.color}24`;
  pill.addEventListener("mouseenter", () => {
    pill.style.background = `${task.color}2e`;
    pill.style.borderColor = `${task.color}8c`;
    pill.style.boxShadow = `0 2px 10px ${task.color}59`;
    (pill.querySelector(".lbl") as HTMLElement).style.color = lighten(task.color, 0.3);
  });
  pill.addEventListener("mouseleave", () => {
    pill.style.background = "";
    pill.style.borderColor = `${task.color}24`;
    pill.style.boxShadow = "";
    (pill.querySelector(".lbl") as HTMLElement).style.color = "";
  });

  if (task.pillBadge) {
    const colors = { approval: "#F5A524", finished: "#22C55E", error: "#F4505E" } as const;
    const icons = { approval: ICONS.bang, finished: ICONS.check, error: ICONS.xmark } as const;
    const inner = h("i", { style: `background:${colors[task.pillBadge]}` }, svg(icons[task.pillBadge], 6, { stroke: task.pillBadge === "finished" ? 3 : 0 }));
    const badge = h("div", { class: "pill-badge" }, inner);
    badge.style.boxShadow = `0 0 4px ${colors[task.pillBadge]}99`;
    pill.append(badge);
  }
  return pill;
}

function lighten(hex: string, amount: number): string {
  const v = parseInt(hex.replace("#", ""), 16);
  const c = [(v >> 16) & 255, (v >> 8) & 255, v & 255].map((x) =>
    Math.min(255, Math.round(x + amount * 255)),
  );
  return `rgb(${c[0]},${c[1]},${c[2]})`;
}

// ── Empty ─────────────────────────────────────────────────────────────────────

function buildEmpty(actions: ViewActions): ViewHost {
  const body = h(
    "div",
    { class: "stack", style: "padding:0 18px 0 118px;flex-direction:row;align-items:center;gap:16px" },
    h(
      "div",
      { style: "display:flex;flex-direction:column;gap:5px" },
      h("div", { class: "title", text: "Nothing running right now." }),
      h("div", { class: "sub", text: "Drop a file or window, or ask me anything." }),
    ),
    h("div", { class: "grow" }),
    btn("Ask Claude", "primary", () => actions.setView("prompt")),
  );
  return { el: h("div", { class: "view" }, card(null, body)), sync() {} };
}

// ── Approval ──────────────────────────────────────────────────────────────────

function buildApproval(actions: ViewActions): ViewHost {
  const who = h("div");
  const code = h("div", { class: "code" });
  const row = h("div", { class: "actions" });
  const el = h("div", { class: "view" }, card("amber", stack(116, 16, who, code, row)));
  let rowKey = "";
  return {
    el,
    sync() {
      clear(who);
      who.append(agentWho(State.focusTask, "needs permission"));
      // The whole point of approving here rather than in the terminal: this line
      // is the command, the file path or the URL being authorised, not just the
      // name of the tool asking.
      code.textContent = State.pendingApproval?.command || State.pendingApproval?.tool || "…";
      // Two buttons, built once. Rebuilding them between a mouse-down and a
      // mouse-up would swallow the click, and there is nothing left to vary:
      // "Always" is gone until the remembered-rules list exists to back it.
      if (rowKey === "built") return;
      rowKey = "built";
      clear(row);
      row.append(
        btn("Deny", "secondary", () => actions.decide("deny"), "N"),
        btn("Allow", "primary", () => actions.decide("allow"), "Y"),
      );
    },
  };
}

// ── Question ──────────────────────────────────────────────────────────────────

function buildQuestion(): ViewHost {
  const who = h("div");
  const title = h("div", { class: "title" });
  const row = h("div", { class: "actions" });
  const el = h("div", { class: "view" }, card("cyan", stack(116, 16, who, title, row)));
  return {
    el,
    sync() {
      clear(who);
      who.append(agentWho(State.focusTask, "Claude Code is asking a question"));
      const task = State.focusTask;
      title.textContent = task?.steps.at(-1) ?? "Claude needs an answer.";
      clear(row);
      row.append(h("div", { class: "sub", text: "Answer in your terminal — Coucou can't reply for you yet." }));
    },
  };
}

// ── Error ─────────────────────────────────────────────────────────────────────

function buildError(actions: ViewActions): ViewHost {
  const who = h("div");
  const title = h("div", { class: "title", text: "Workflow stopped." });
  const detail = h("div", { class: "detail" });
  const row = h("div", { class: "actions" },
    btn("Retry", "primary", () => actions.setView(State.defaultView())),
    btn("Open in n8n", "secondary", () => actions.openUrl("")),
  );
  const el = h("div", { class: "view" }, card("red", stack(116, 16, who, title, detail, row)));
  return {
    el,
    sync() {
      const task = State.focusTask;
      clear(who);
      who.append(agentWho(task, task?.source === "n8n" ? "n8n" : "Claude Code"));
      title.textContent = task?.source === "n8n" ? "Workflow stopped." : "Session stopped on an error.";
      detail.textContent = task?.steps.at(-1) ?? "No detail available.";
    },
  };
}

// ── Finished ──────────────────────────────────────────────────────────────────

function buildFinished(actions: ViewActions): ViewHost {
  const who = h("div");
  const title = h("div", { class: "title" });
  const row = h("div", { class: "actions" },
    btn("Open terminal", "primary", () => actions.openTerminal()),
    btn("OK", "secondary", () => actions.collapse()),
  );
  const el = h("div", { class: "view" }, card("green", stack(116, 16, who, title, row)));
  return {
    el,
    sync() {
      clear(who);
      who.append(agentWho(State.focusTask, "Claude Code finished"));
      title.textContent = State.focusTask?.steps.at(-1) ?? "Session finished";
    },
  };
}

// ── Confused ──────────────────────────────────────────────────────────────────

function buildConfused(): ViewHost {
  const body = h(
    "div",
    { class: "stack", style: "padding:0 18px 0 128px" },
    h("div", { class: "title", text: "Too many hits at once." }),
    h("div", { class: "sub", text: "Give me a sec — back to work in three seconds." }),
  );
  return { el: h("div", { class: "view" }, card("pink", body)), sync() {} };
}

// ── Note ──────────────────────────────────────────────────────────────────────

function buildNote(): ViewHost {
  const title = h("div", { class: "title" });
  const el = h("div", { class: "view" }, card(null, h("div", { class: "stack", style: "padding:0 18px 0 98px" }, title)));
  return {
    el,
    sync() {
      title.textContent = State.noteMessage ?? "";
    },
  };
}

// ── Placeholders filled in later stages ───────────────────────────────────────

function buildPlaceholder(title: string, sub: string): ViewHost {
  const body = h(
    "div",
    { class: "stack", style: "padding:0 18px 0 118px" },
    h("div", { class: "title", text: title }),
    h("div", { class: "sub", text: sub }),
  );
  return { el: h("div", { class: "view" }, card(null, body)), sync() {} };
}

// ── Registry ──────────────────────────────────────────────────────────────────

export function buildViews(
  actions: ViewActions,
  onChatHeightChange: () => void,
): Map<IslandViewName, ViewHost> {
  const map = new Map<IslandViewName, ViewHost>();
  map.set("overview", buildOverview(actions));
  map.set("empty", buildEmpty(actions));
  map.set("approval", buildApproval(actions));
  map.set("question", buildQuestion());
  map.set("error", buildError(actions));
  map.set("finished", buildFinished(actions));
  map.set("confused", buildConfused());
  map.set("note", buildNote());
  map.set("message", buildMessage(actions));
  map.set("integrations", buildIntegrations(actions));
  map.set("timer", buildTimer());
  map.set("prompt", buildPrompt(onChatHeightChange));
  map.set("upload", buildUpload());
  map.set("uploading", buildUploading());
  map.set("choose", buildChoose(actions));
  // Not in the Windows v1: sending a file by email, window attach + web result.
  map.set("mail", buildPlaceholder("Sending by email isn't in this version.", ""));
  map.set("searching", buildPlaceholder("Claude is searching…", ""));
  map.set("result", buildPlaceholder("Result", ""));
  return map;
}
