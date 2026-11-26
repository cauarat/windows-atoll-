// Island views — DOM ports of IslandViewContent.swift. Paddings, font sizes,
// colours and wording are copied from the Swift views so both platforms read
// identically.

import { h, svg, clear } from "./dom";
import { HEADER_PX, ICONS } from "./icons";
import { Bridge } from "../core/bridge";
import { State, type AgentTask } from "../core/state";
import { washRGBA, type IslandViewName, type Wash } from "../core/layout";
import { FocusTimer, TIMER_COLOR, TIMER_LABEL, TIMER_PRESETS } from "../core/timer";
import { createMiniBot, pruneMiniBots } from "../mochi/minibots";
import { buildPrompt } from "./chat";
import { buildChoose, buildUpload, buildUploading } from "./upload";
import { buildMessage } from "./message";
import { buildMessages } from "./messages";
import { buildAgenda } from "./agenda";
import { buildHydration, buildSip } from "./hydration";
import { buildUpdate } from "./update";
import { buildNowPlaying } from "./nowplaying";
import { buildSite, buildWebChat } from "./screens";
import { t } from "../core/i18n";

export interface ViewActions {
  setView(v: IslandViewName): void;
  collapse(): void;
  setFocus(id: string): void;
  openUrl(url: string): void;
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
   * island's X, Escape and the close shortcut all do: the island folds.
   * `IslandWindowController.closeScreen`.
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

export function btn(label: string, kind: "primary" | "secondary", onClick: () => void): HTMLElement {
  return h("button", { class: `btn ${kind}`, onclick: onClick }, h("span", { text: label }));
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
  // Water and the calendar used to be tabs here too. They hang off the island
  // now, on the ring (`pressRingButton` in island/island.ts), as on the Mac.
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
    // Timer.
    h("div", { class: "tabs" }, tabHome, tabChat, tabClip, tabPills, tabSite),
    h("div", { class: "tabs tabs-right" }, tabTimer),
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

/**
 * Home: the message card, the timer or the player, whichever the preference
 * and what is playing make it — each built once and swapped in, rather than
 * this view trying to be all three.
 *
 * There was a fourth face, the pill in focus — a Claude Code session's step
 * ticker, or an integration's own card — for a Home set to "Claude Code". It
 * went with the coding agents, and the cards with it.
 */
function buildOverview(actions: ViewActions): ViewHost {
  const timerHost = buildTimer();
  const messageHost = buildMessage(actions, true);
  const playerHost = buildNowPlaying();
  // Each face fills the tab the way a view fills the island; `home-face` is what
  // `view` was doing for them before they were nested here.
  for (const host of [timerHost, messageHost, playerHost]) {
    host.el.classList.remove("view");
    host.el.classList.add("home-face");
  }
  const el = h("div", { class: "view" }, timerHost.el, messageHost.el, playerHost.el);

  return {
    el,
    tick(nowMs: number) {
      if (homeKind() === "player") playerHost.tick?.(nowMs);
    },
    sync() {
      const kind = homeKind();
      timerHost.el.classList.toggle("on", kind === "timer");
      messageHost.el.classList.toggle("on", kind === "message");
      playerHost.el.classList.toggle("on", kind === "player");
      if (kind === "player") playerHost.sync();
      else if (kind === "timer") timerHost.sync();
      else messageHost.sync();
    },
  };
}

/// Which of Home's three faces is on, given the preference.
function homeKind(): "timer" | "message" | "player" {
  const content = State.settings.homeContent;
  if (content === "timer") return "timer";
  // Something playing takes Home while it is loaded, but only from automatic —
  // see `HomeContent.showsMusic`. A song starting is not a reason to take
  // Ato away from somebody who asked for Ato. The other way in is
  // the Now Playing pill itself; `homeShowsPlayer` holds both, and is also what
  // the island measures its height by, so the two cannot disagree.
  if (State.homeShowsPlayer) return "player";
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
  const label = task.name;
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

  // A message waiting on a pill that is not in focus: amber, with a bang.
  if (task.pillBadge === "approval") {
    const color = "#F5A524";
    const inner = h("i", { style: `background:${color}` }, svg(ICONS.bang, 6, { stroke: 0 }));
    const badge = h("div", { class: "pill-badge" }, inner);
    badge.style.boxShadow = `0 0 4px ${color}99`;
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
  map.set("confused", buildConfused());
  map.set("note", buildNote());
  map.set("message", buildMessage(actions));
  map.set("integrations", buildIntegrations(actions));
  map.set("timer", buildTimer());
  map.set("messages", buildMessages(actions));
  map.set("agenda", buildAgenda(actions));
  map.set("hydration", buildHydration(actions));
  map.set("sip", buildSip(actions));
  map.set("update", buildUpdate(actions));
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
