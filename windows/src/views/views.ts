// Island views — DOM ports of IslandViewContent.swift. Paddings, font sizes,
// colours and wording are copied from the Swift views so both platforms read
// identically.

import { h, svg, clear, dot } from "./dom";
import { HEADER_PX, ICONS } from "./icons";
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
import { buildMessages } from "./messages";
import { buildAgenda } from "./agenda";
import { buildHydration, buildSip } from "./hydration";
import { Hydration } from "../core/hydrationStore";
import { buildNowPlaying } from "./nowplaying";
import { buildSite, buildWebChat } from "./screens";
import { t } from "../core/i18n";

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
  /** Settings, on `section` (a settings/sections.ts id) when one is named. */
  openSettingsWindow(section?: string): void;
  /**
   * Holds the island open, or lets it close again. The reply box takes this
   * while it has the cursor: a card that slid away mid-sentence would throw the
   * sentence away with it.
   */
  setPinned(on: boolean): void;
  /**
   * Lets the island's window take the keyboard, or gives it back. Only ever
   * called from a click into a field: a card arriving must never take it.
   * Giving it back waits for the press under way, and does not happen if what
   * that press opened keeps the keyboard — the chat, ChatGPT, the site.
   */
  focusField(on: boolean): void;
  /**
   * Puts away the screen on the island — ChatGPT, the site — as its own X, the
   * island's X, Escape and the close shortcut all do: a pending approval takes
   * its place, otherwise the island folds. `IslandWindowController.closeScreen`.
   */
  closeScreen(): void;
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
  el.style.paddingTop = "4px";
  el.style.paddingBottom = "4px";
  el.style.paddingRight = `${padRight}px`;
  // The left is the Mochi gutter, or the card's own inset when there is no
  // character to leave it for. Handed to CSS as two custom properties rather
  // than decided here: a view is built once and kept, so the switch has to be
  // able to reach it long after this ran.
  el.style.setProperty("--gutter", `${padLeft}px`);
  el.style.setProperty("--flush", `${padRight}px`);
  return el;
}

// ── Header ────────────────────────────────────────────────────────────────────

/**
 * A header glyph in the frame the Mac lays its symbol out in, `w`×`h` px:
 * the path's 24-unit box shown `size` px across (HEADER_PX), centred on the
 * frame as SwiftUI centres a symbol in its own. A tab's frame is its 30×22
 * capsule; the gear and the speaker are as wide as their symbol lays out at
 * 14 pt and the X has its 18×18, so the buttons sit as far apart as the
 * Mac's.
 */
function mark(path: string, size: number, w: number, h: number): SVGSVGElement {
  const el = svg(path, size);
  const u = 24 / size;
  el.setAttribute("viewBox", `${12 - (w * u) / 2} ${12 - (h * u) / 2} ${w * u} ${h * u}`);
  el.setAttribute("width", String(w));
  el.setAttribute("height", String(h));
  return el;
}

const tabMark = (name: keyof typeof HEADER_PX) => mark(ICONS[name], HEADER_PX[name], 30, 22);

export function buildHeader(actions: ViewActions): ViewHost {
  // Every tab, the clipboard and the gear are silent, as the Mac's are: a
  // 'blip' belongs to a pill being opened.
  const tabHome = h("button", { class: "tab", title: t("Overview"), onclick: () => go("overview") }, tabMark("house"));
  // The chat tab opens the built-in chat, or ChatGPT's own page when that is
  // what the user asked for — the same choice `AppState.chatTabView` makes.
  // Either way it only selects a view, so a second press keeps it, and it is
  // silent: the Mac's tabs play nothing (WC-23).
  const tabChat = h("button", {
    class: "tab",
    title: t("Ask"),
    onclick: () => actions.setView(State.settings.webChat ? "webchat" : "prompt"),
  }, tabMark("chatSparkle"));
  // The site, as a screen on the island: a Windows tab the owner kept beside
  // the disc on the ring, which is the Mac's only way in. A tab, so it changes
  // the view like the others, over ChatGPT too; the disc, like the Mac's, does
  // nothing while a screen is up.
  const tabSite = h("button", {
    class: "tab",
    title: t("Site"),
    onclick: () => actions.setView("web"),
  }, tabMark("globe"));
  const tabPills = h("button", { class: "tab", title: t("Integrations"), onclick: () => go("integrations") }, tabMark("grid"));
  const tabTimer = h("button", { class: "tab", title: t("Timer"), onclick: () => go("timer") }, tabMark("timer"));
  // Only while the Agenda is on: it is an Actuar tool, and a tab onto a
  // sign-in prompt is not something everyone should carry.
  const tabAgenda = h("button", { class: "tab", title: t("Agenda"), onclick: () => go("agenda") }, tabMark("calendar"));
  // Always there, set up or not: before the questions are answered the tab is
  // where they are offered. Opening it by hand ends whatever the reminder card
  // had moved on to say — but a reminder nobody answered stays one.
  const tabWater = h("button", {
    class: "tab",
    title: t("Hydration"),
    onclick: () => {
      Hydration.clearPrompt();
      go("hydration");
    },
  }, tabMark("drop"));
  // Not a tab: the clipboard is a window of its own, so this opens it rather
  // than changing which view the island shows.
  const tabClip = h("button", { class: "tab", title: t("Clipboard"),
                                onclick: () => { void Bridge.toggleClipboardWindow(); } },
                    tabMark("clipboard"));

  // The real Settings window, not the cut-down card the island used to show.
  // These three sit in a row 18 tall, the X's frame, each centred in it as
  // the Mac's HStack centres them; drawn the row's full height, their boxes
  // start on a whole pixel. Widths are the Mac's: gearshape at 14 pt lays out
  // 17 wide.
  const gearBtn = h("button", { title: t("Settings"), onclick: () => actions.openSettingsWindow() },
                    mark(ICONS.gear, HEADER_PX.gear, 17, 18));
  // speaker.wave.2 at 14 pt lays out 19.5 wide, speaker.slash 14.5: muting
  // narrows the button, and the gear and the tabs beside it move over, as
  // they do on the Mac.
  const soundBtn = h("button", { title: t("Mute"), onclick: () => actions.toggleSound() });
  // Closes the island now, whatever brought it up — a message that arrived
  // mid-sentence should not take the whole hold to leave. The message stays
  // unread, as it does when Escape puts it away: `collapse` reads nothing.
  // The Mac's xmark at 13 pt in its 18×18 frame.
  const closeBtn = h("button", { class: "close", title: t("Close"), onclick: () => actions.collapse() },
                     mark(ICONS.xmarkRegular, HEADER_PX.xmarkRegular, 18, 18));

  function go(v: IslandViewName) {
    actions.setView(v);
  }

  const el = h(
    "div",
    { id: "header" },
    // Split either side of the notch rather than piled on the left: the four
    // you reach for to do something, then the rest. No fifth one for `upload`
    // — dragging a file over the island is what opens the bin, so a tab onto an
    // empty mailbox was a second door to the same room. The Mac's three first;
    // Integrations and Site are this platform's own. On the right, the Mac's
    // order: Agenda, Hydration, Timer.
    h("div", { class: "tabs" }, tabHome, tabChat, tabClip, tabPills, tabSite),
    h("div", { class: "tabs tabs-right" }, tabAgenda, tabWater, tabTimer),
    h("div", { class: "header-actions" }, gearBtn, soundBtn, closeBtn),
  );

  return {
    el,
    sync() {
      const v = State.view;
      tabHome.classList.toggle("on", v === "overview" || v === "empty");
      // Lit for either of the two things it opens, as `TabButton.isOn` has it.
      tabChat.classList.toggle("on", v === "prompt" || v === "webchat");
      tabSite.classList.toggle("on", v === "web");
      tabPills.classList.toggle("on", v === "integrations");
      tabTimer.classList.toggle("on", v === "timer");
      tabAgenda.classList.toggle("on", v === "agenda");
      tabWater.classList.toggle("on", v === "hydration");
      tabAgenda.style.display = State.settings.agendaEnabled ? "" : "none";
      clear(soundBtn);
      soundBtn.append(State.settings.soundEnabled
        ? mark(ICONS.speakerOn, HEADER_PX.speakerOn, 19.5, 18)
        : mark(ICONS.speakerOff, HEADER_PX.speakerOff, 14.5, 18));
      // `.confused` hides this row, and the site replaces it with a row of its
      // own. Hidden is not enough for the site: invisible, these buttons would
      // still take the clicks meant for its own. Kept in the flow rather than
      // removed, so the views below keep the height they were laid out against.
      const hidden = v === "confused" || v === "web";
      el.style.opacity = hidden ? "0" : "1";
      el.style.pointerEvents = hidden ? "none" : "";
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
    { class: "icon-btn jump", title: t("Open"), onclick: () => actions.openTarget() },
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
  const playerHost = buildNowPlaying();
  const pillBody = h("div", { class: "overview solo home-face" }, h("div", { class: "left" }, left));
  // Each face fills the tab the way a view fills the island; `home-face` is what
  // `view` was doing for them before they were nested here.
  for (const host of [timerHost, messageHost, playerHost]) {
    host.el.classList.remove("view");
    host.el.classList.add("home-face");
  }
  const el = h("div", { class: "view" }, pillBody, timerHost.el, messageHost.el, playerHost.el);

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
    // The Mac's integrations link opens Settings on Integrations.
    openSettings: () => actions.openSettingsWindow("integrations"),
  };

  return {
    el,
    tick(nowMs: number) {
      const kind = homeKind();
      if (kind === "player") {
        playerHost.tick?.(nowMs);
        return;
      }
      if (kind === "pill" && mode === "ticker") ticker.tick(nowMs);
    },
    sync() {
      const kind = homeKind();
      pillBody.classList.toggle("on", kind === "pill");
      timerHost.el.classList.toggle("on", kind === "timer");
      messageHost.el.classList.toggle("on", kind === "message");
      playerHost.el.classList.toggle("on", kind === "player");
      if (kind === "player") {
        playerHost.sync();
        return;
      }
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

/// Which of Home's four faces is on, given the preference.
function homeKind(): "timer" | "message" | "player" | "pill" {
  const content = State.settings.homeContent;
  if (content === "timer") return "timer";
  // Something playing takes Home while it is loaded, but only from automatic —
  // see `HomeContent.showsMusic`. A song starting is not a reason to take
  // Ato away from somebody who asked for Ato. The other way in is
  // the Now Playing pill itself; `homeShowsPlayer` holds both, and is also what
  // the island measures its height by, so the two cannot disagree.
  if (State.homeShowsPlayer) return "player";
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
      h("div", { class: "pills-title", text: t("Integrations") }),
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
                     h("span", { class: "t-play" }), h("span", { text: t("Start") }));
  const resetBtn = h("button", { class: "t-reset", onclick: () => FocusTimer.reset() },
                     h("span", { text: "↺" }), h("span", { text: t("Reset") }));

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
  const paused = h("span", { class: "timer-paused", text: t("paused") });
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
      h("button", { class: "btn secondary", text: t("+1 min"), onclick: () => FocusTimer.extend() }),
      h("button", { class: "btn secondary", text: t("Stop"), onclick: () => FocusTimer.stop() }),
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
  // With the characters off the pill is its label, its colour and its badge —
  // everything it ever said, minus the face. The canvas is not built at all,
  // rather than built and hidden: one per pill, each ticking every frame.
  const face: Node[] = State.settings.hideCharacters ? [] : [createMiniBot(task, 24)];
  const pill = h(
    "div",
    { class: "pill", onclick: () => { actions.setFocus(task.id); after?.(); } },
    ...face,
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
    { class: "stack", style: "padding-top:0;padding-bottom:0;padding-right:18px;--gutter:118px;--flush:18px;flex-direction:row;align-items:center;gap:16px" },
    h(
      "div",
      { style: "display:flex;flex-direction:column;gap:5px" },
      h("div", { class: "title", text: t("Nothing running right now.") }),
      h("div", { class: "sub", text: t("Drop a file or window, or ask me anything.") }),
    ),
    h("div", { class: "grow" }),
    btn(t("Ask Claude"), "primary", () => actions.setView("prompt")),
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
      who.append(agentWho(State.focusTask, t("Claude Code is asking a question")));
      const task = State.focusTask;
      title.textContent = task?.steps.at(-1) ?? t("Claude needs an answer.");
      clear(row);
      row.append(h("div", { class: "sub", text: t("Answer in your terminal — Notchy can't reply for you yet.") }));
    },
  };
}

// ── Error ─────────────────────────────────────────────────────────────────────

function buildError(actions: ViewActions): ViewHost {
  const who = h("div");
  const title = h("div", { class: "title", text: t("Workflow stopped.") });
  const detail = h("div", { class: "detail" });
  const row = h("div", { class: "actions" },
    btn("Retry", "primary", () => actions.setView(State.defaultView())),
    btn(t("Open in n8n"), "secondary", () => actions.openUrl("")),
  );
  const el = h("div", { class: "view" }, card("red", stack(116, 16, who, title, detail, row)));
  return {
    el,
    sync() {
      const task = State.focusTask;
      clear(who);
      who.append(agentWho(task, task?.source === "n8n" ? "n8n" : "Claude Code"));
      title.textContent = task?.source === "n8n" ? "Workflow stopped." : t("Session stopped on an error.");
      detail.textContent = task?.steps.at(-1) ?? t("No detail available.");
    },
  };
}

// ── Finished ──────────────────────────────────────────────────────────────────

function buildFinished(actions: ViewActions): ViewHost {
  const who = h("div");
  const title = h("div", { class: "title" });
  const row = h("div", { class: "actions" },
    btn(t("Open terminal"), "primary", () => actions.openTerminal()),
    btn("OK", "secondary", () => actions.collapse()),
  );
  const el = h("div", { class: "view" }, card("green", stack(116, 16, who, title, row)));
  return {
    el,
    sync() {
      clear(who);
      who.append(agentWho(State.focusTask, t("Claude Code finished")));
      title.textContent = State.focusTask?.steps.at(-1) ?? t("Session finished");
    },
  };
}

// ── Confused ──────────────────────────────────────────────────────────────────

function buildConfused(): ViewHost {
  const body = h(
    "div",
    { class: "stack", style: "padding-top:0;padding-bottom:0;padding-right:18px;--gutter:128px;--flush:18px" },
    h("div", { class: "title", text: t("Too many hits at once.") }),
    h("div", { class: "sub", text: t("Give me a sec — back to work in three seconds.") }),
  );
  return { el: h("div", { class: "view" }, card("pink", body)), sync() {} };
}

// ── Note ──────────────────────────────────────────────────────────────────────

function buildNote(): ViewHost {
  const title = h("div", { class: "title" });
  const el = h("div", { class: "view" }, card(null, h("div", { class: "stack", style: "padding-top:0;padding-bottom:0;padding-right:18px;--gutter:98px;--flush:18px" }, title)));
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
    { class: "stack", style: "padding-top:0;padding-bottom:0;padding-right:18px;--gutter:118px;--flush:18px" },
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
  map.set("messages", buildMessages(actions));
  map.set("agenda", buildAgenda(actions));
  map.set("hydration", buildHydration(actions));
  map.set("sip", buildSip(actions));
  map.set("prompt", buildPrompt(actions, onChatHeightChange));
  map.set("upload", buildUpload());
  map.set("uploading", buildUploading());
  map.set("choose", buildChoose(actions));
  // The two screens: the card and the header row around a page Rust lays over it.
  map.set("webchat", buildWebChat(actions));
  map.set("web", buildSite(actions));
  // Not in the Windows v1: sending a file by email, window attach + web result.
  map.set("mail", buildPlaceholder("Sending by email isn't in this version.", ""));
  map.set("searching", buildPlaceholder("Claude is searching…", ""));
  map.set("result", buildPlaceholder("Result", ""));
  return map;
}
