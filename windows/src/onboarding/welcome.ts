// The welcome's seven screens, with Mochi alive at the top of each — the twin of
// NotchBuddy/Sources/App/OnboardingView.swift, screen for screen and point for
// point. The window is Rust's (lib.rs, create_onboarding_window) and main.ts
// beside this file starts and stops it; which screens there are, in what order
// and when the welcome shows are core/onboarding.ts, shared with the Mac.
//
// Every choice goes into the settings the moment it is made, so skipping or
// closing halfway keeps whatever was already picked. The name is the one
// exception, as on the Mac: it is written when its screen is left, so a name
// half-typed is never what the greeting says.

import { ONBOARDING_STEPS, onboardingProgress, type OnboardingStep } from "../core/onboarding";
import { GREETING_KEYS, dayPeriod, firstNameFromFullName, greetingName } from "../core/greetingName";
import { LANGUAGES, LANGUAGE_LABEL, language, t, type Language } from "../core/i18n";
import { Sound } from "../core/sound";
import { INTEGRATION_AGENTS, TOGGLEABLE_INTEGRATION_IDS, type Settings } from "../core/state";
import {
  CHARACTER_PRESETS, characterFromStorage, characterToStorage, hasFestive, sameFace,
  type MochiCharacter,
} from "../mochi/character";
import { BotEngine, hexToRGB } from "../mochi/engine";
import { characterPreview } from "../mochi/preview";
import { h, clear, svg } from "../views/dom";
import { ICONS } from "../views/icons";

/** What the screens need from whoever put them up — main.ts, or a preview. */
export interface WelcomeHost {
  /**
   * The settings, read through this every time and never kept: main.ts
   * replaces its object on every "settings-changed".
   */
  settings(): Settings;
  /** Saves the whole object, the way `save_settings` wants it. */
  save(): void;
  /** Puts `settings.language` in force here, and tells Rust. */
  applyLanguage(): void;
  /** The account's name, raw — `BootInfo.accountName`. */
  accountName: string | null;
  /** Whether this build can read what is playing — `BootInfo.media`. */
  media: boolean;
  /** The welcome is over: Open Notchy, Skip, or the red button. */
  finish(): void;
  /** The panel's background was pressed: the window follows the pointer. */
  drag(): void;
}

/** Mochi on the hello and the last screen, and on the five questions. */
const BIG = 84;
const SMALL = 56;
/** Headroom above him for hearts and stars, as `BotPlacement` leaves. */
const OVERHANG = 34;
/** The look screen's tiles. */
const TILE = 34;
/** Pills the island has room for, Claude Code aside. */
const SLOTS = 4;
/** How long Mochi takes to change size between screens — the Mac's step animation. */
const RESIZE_MS = 200;

// The three tips' symbols: SF's cursorarrow.rays, a screen with its taskbar
// (the Mac's menubar.rectangle, turned the way a PC's tray sits), and
// slider.horizontal.3 — stroked on the 24 grid the other icons use.
const TIP_POINTER = "M11 11l8 3-3.4 1.4L14 19zM8.2 8.2 6 6M11 7.6V4.6M7.6 11H4.6M13.7 8.3l1.8-1.8M8.3 13.7l-1.8 1.8";
const TIP_TRAY = "M3.5 5.5h17v13h-17zM3.5 15h17M15.5 17h2";
const TIP_SLIDERS = "M4 7h9m4 0h3M4 12h3m4 0h9M4 17h11m4 0h1M15 5v4M9 10v4M17 15v4";

// ── Where it stands ───────────────────────────────────────────────────────────
//
// Here, not in the DOM: picking a language rebuilds every node, and must not
// send anyone back to the first screen or lose the name being typed.

let host: WelcomeHost | null = null;
let root: HTMLElement | null = null;
/** The screen up, as an index into ONBOARDING_STEPS. */
let index = 0;
/** The name field, as typed. */
let draftName = "";
/** How full the progress bar was, so the next screen's grows from there. */
let shownProgress = 0;
/** The button Enter presses. */
let primary: HTMLButtonElement | null = null;
/** Repaints the look screen's marks after a pick, without new previews. */
let markLooks: (() => void) | null = null;
let helloTimer = 0;

/** Mochi at the top: one engine for the whole welcome, so he never blinks out between screens. */
const mochi = {
  engine: null as BotEngine | null,
  canvas: null as HTMLCanvasElement | null,
  raf: 0,
  last: 0,
  /** His size as drawn, easing from `from` to `to` over RESIZE_MS since `t0`. */
  size: BIG,
  from: BIG,
  to: BIG,
  t0: 0,
  /** The backing store last sized, so it is only resized on a change. */
  px: "",
};

/** Whether the welcome is up. */
export function welcomeShowing(): boolean {
  return host !== null;
}

/**
 * Puts the welcome up on `step` — the hello, unless a screenshot asked for
 * another — with the settings as they are now.
 */
export function startWelcome(into: HTMLElement, by: WelcomeHost, step: string = "welcome") {
  stopWelcome();
  host = by;
  root = into;
  const found = ONBOARDING_STEPS.indexOf(step as OnboardingStep);
  index = found < 0 ? 0 : found;
  const s = by.settings();
  // Whatever Mochi would call the user today, so most people only press Continue.
  draftName = s.userName || (firstNameFromFullName(by.accountName) ?? "");
  const progress = onboardingProgress(index);
  shownProgress = progress ? progress.current / progress.total : 0;

  Sound.setEnabled(s.soundEnabled && s.enabled);
  Sound.setVolume(s.soundVolume);
  void Sound.preload();

  const engine = new BotEngine();
  // The island's white, as Claude Code's pill gives him.
  engine.bodyColor = hexToRGB("#F5F6F8");
  engine.particleOverhang = OVERHANG;
  engine.setState("idle", true);
  mochi.engine = engine;
  mochi.canvas = h("canvas", { "aria-hidden": "true" });
  mochi.px = "";
  resize(progress ? SMALL : BIG, false);

  render(false);
  // The window is up: say hello, a beat after it appears.
  helloTimer = window.setTimeout(react, 450);
}

/** Takes the welcome down: nothing of it keeps drawing or listening. */
export function stopWelcome() {
  window.clearTimeout(helloTimer);
  stopLoop();
  const had = host !== null;
  host = null;
  primary = null;
  markLooks = null;
  mochi.engine = null;
  mochi.canvas = null;
  if (root) clear(root);
  if (had) Sound.idle();
}

/** Redraws the screen that is up — the language changed somewhere else. */
export function refreshWelcome() {
  if (host) render(false);
}

/**
 * Draws Mochi `dt` seconds on and stops — the only frames a hidden preview
 * pane ever gets. Never needed in the app, where the loop runs.
 */
export function stepWelcomeMochi(dt: number) {
  drawMochi(performance.now(), dt);
}

// ── Moving through it ─────────────────────────────────────────────────────────

/** Continue — or, on the last screen, Open Notchy. */
function advance() {
  if (!host) return;
  leaveStep();
  if (index >= ONBOARDING_STEPS.length - 1) {
    host.finish();
    return;
  }
  go(index + 1);
}

function back() {
  if (!host) return;
  leaveStep();
  go(Math.max(0, index - 1));
}

/** Skip, and the red button: over, with whatever was already chosen. */
function skip() {
  if (!host) return;
  leaveStep();
  host.finish();
}

function go(to: number) {
  index = to;
  // Eased while frames are running; with none — a window not on screen — there
  // is nothing to ease through, and the layout has to be right at once.
  resize(onboardingProgress(index) ? SMALL : BIG, mochi.raf !== 0);
  render(true);
  react();
}

/** Saves the name, which is only written once its screen is left. */
function leaveStep() {
  if (!host || ONBOARDING_STEPS[index] !== "name") return;
  commitName();
}

function commitName() {
  if (!host) return;
  const s = host.settings();
  const name = draftName.trim();
  if (s.userName === name) return;
  s.userName = name;
  host.save();
}

/** Mochi answers each screen: a wave on the hello, pride on the last, a smile between. */
function react() {
  const engine = mochi.engine;
  if (!engine) return;
  switch (ONBOARDING_STEPS[index]) {
    case "welcome": engine.greet(); break;
    case "ready": engine.triggerEmote("proud"); break;
    default: engine.triggerEmote("happy");
  }
}

// ── Drawing it ────────────────────────────────────────────────────────────────

interface Screen {
  nodes: Node[];
  /** The button's word, when it is not Continue. */
  go?: string;
  /** What takes the keyboard, when it is not the button. */
  focus?: HTMLElement;
  /** Anything to do once it is on screen. */
  after?: () => void;
}

const SCREENS: Record<OnboardingStep, () => Screen> = {
  welcome: welcomeScreen,
  name: nameScreen,
  language: languageScreen,
  look: lookScreen,
  tools: toolsScreen,
  startup: startupScreen,
  ready: readyScreen,
};

/** Builds the panel for the screen up. `fade` is for a new screen, not a redraw. */
function render(fade: boolean) {
  if (!host || !root || !mochi.canvas) return;
  const step = ONBOARDING_STEPS[index];
  const question = onboardingProgress(index) !== null;
  // What the window is called — in Alt+Tab and to a screen reader — in the
  // language it speaks.
  document.title = t("Welcome to Notchy");
  document.documentElement.lang = language();

  markLooks = null;
  const screen = SCREENS[step]();
  const button = h("button", {
    type: "button", class: "ob-go", text: screen.go ?? t("Continue"), onclick: advance,
  });
  primary = button;

  const panel = h("div", { class: "ob" },
    h("button", {
      type: "button", class: "ob-close", "aria-label": t("Close"), title: t("Close"), onclick: skip,
    }, svg("M7.5 7.5l9 9M16.5 7.5l-9 9", 8, { stroke: 3 })),
    topBar(step),
    h("div", { class: "ob-stage" }, mochi.canvas),
    progressRow(),
    h("div", { class: question ? "ob-screen" : "ob-screen center" },
      h("div", { class: fade ? "ob-inner fade" : "ob-inner" }, ...screen.nodes)),
    h("div", { class: "ob-foot" }, button),
  );
  panel.addEventListener("mousedown", onPress);
  clear(root);
  root.append(panel);

  // A frame now, so the canvas is never blank — and the only one a hidden
  // window would get until it is shown.
  if (!mochi.raf) drawMochi(performance.now(), 0);
  startLoop();
  (screen.focus ?? button).focus({ preventScroll: true });
  screen.after?.();
}

/** Skip, across from the close button — on every screen but the last. */
function topBar(step: OnboardingStep): HTMLElement {
  const bar = h("div", { class: "ob-top" });
  if (step !== "ready") {
    bar.append(h("button", { type: "button", class: "ob-skip", text: t("Skip"), onclick: skip }));
  }
  return bar;
}

/** Back, a bar, and "2 of 5" — the hydration questionnaire's row, on the five questions. */
function progressRow(): HTMLElement | null {
  const progress = onboardingProgress(index);
  if (!progress) return null;
  const label = t("%lld of %lld", progress.current, progress.total);
  const to = progress.current / progress.total;
  const fill = h("i", { style: `width:${to * 100}%;--from:${shownProgress * 100}%` });
  shownProgress = to;
  return h("div", { class: "ob-progress" },
    h("button", { type: "button", class: "ob-back", onclick: back },
      svg(ICONS.chevronLeft, 10, { stroke: 2.6 }),
      h("span", { text: t("Back") }),
    ),
    h("div", {
      class: "ob-bar", role: "progressbar", "aria-label": label,
      "aria-valuemin": "0", "aria-valuemax": String(progress.total), "aria-valuenow": String(progress.current),
    }, fill),
    h("span", { class: "ob-step", text: label }),
  );
}

function heading(title: string, hint?: string): HTMLElement {
  return h("div", { class: "ob-heading" },
    h("h1", { class: "ob-title", text: title }),
    hint ? h("p", { class: "ob-hint", text: hint }) : null,
  );
}

// ── The seven screens ─────────────────────────────────────────────────────────

function welcomeScreen(): Screen {
  return {
    go: t("Begin"),
    nodes: [h("div", { class: "ob-hello" },
      h("h1", { class: "ob-big", text: t("Hi, I'm Mochi!") }),
      h("p", {
        class: "ob-body",
        text: t("I live at the edge of your screen. I keep an eye on your AI agents, your messages and your music, and you answer them without leaving what you are doing."),
      }),
      h("p", { class: "ob-body quiet", text: t("Let's set me up for you. It takes about a minute.") }),
    )],
  };
}

function nameScreen(): Screen {
  const by = host!;
  const field = h("input", {
    type: "text", class: "ob-field", value: draftName, placeholder: t("Your first name"),
    "aria-label": t("Your name"), maxlength: "80", autocomplete: "off", spellcheck: "false",
  });
  const line = h("div", { class: "ob-line" });
  // The greeting the next launch will actually say, by today's clock.
  const keys = GREETING_KEYS[dayPeriod(new Date().getHours())];
  const paint = () => {
    const name = greetingName(field.value, by.accountName);
    line.textContent = name ? t(keys.named, name) : t(keys.bare);
  };
  field.addEventListener("input", () => {
    draftName = field.value;
    paint();
  });
  paint();
  return {
    nodes: [h("div", { class: "ob-name" },
      heading(t("What should I call you?")),
      field,
      h("div", { class: "ob-preview" },
        h("p", { class: "ob-note", text: t("I'll greet you like this every time Notchy starts:") }),
        line,
      ),
    )],
    focus: field,
    // Selected, so typing replaces the guess and Continue keeps it.
    after: () => field.select(),
  };
}

function languageScreen(): Screen {
  const current = host!.settings().language;
  const options = LANGUAGES.map((value) => {
    const on = current === value;
    // Each language names itself; only "Same as system" is a sentence.
    return h("button", {
      type: "button", class: "ob-option", "aria-pressed": String(on),
      onclick: () => pickLanguage(value),
    },
    h("span", { text: value === "system" ? t(LANGUAGE_LABEL[value]) : LANGUAGE_LABEL[value] }),
    on ? svg(ICONS.check, 12, { stroke: 2.4 }) : null);
  });
  return {
    nodes: [h("div", { class: "ob-col gap16" },
      heading(t("Which language should I speak?"), t("Everywhere: the island, Settings and the notifications.")),
      h("div", { class: "ob-options", role: "group" }, ...options),
    )],
  };
}

function pickLanguage(value: Language) {
  if (!host) return;
  const s = host.settings();
  if (s.language === value) return;
  s.language = value;
  host.save();
  host.applyLanguage();
  // The same screen, now in the new language; the keyboard stays on the pick.
  render(false);
  root?.querySelector<HTMLElement>('.ob-option[aria-pressed="true"]')?.focus({ preventScroll: true });
}

function lookScreen(): Screen {
  const current = characterFromStorage(host!.settings().defaultCharacter);
  const shape = current.shape ?? null;
  // Classic, then the eighteen. A tile is its face on the body already chosen.
  const faces: { face: MochiCharacter; name: string }[] = [
    { face: {}, name: "Classic" },
    ...CHARACTER_PRESETS.map((p) => ({ face: p.character, name: p.name })),
  ];
  const tiles = faces.map(({ face, name }) => {
    const worn: MochiCharacter = { accessory: face.accessory ?? null, eye: face.eye ?? null, shape };
    const label = t(name);
    const el = h("button", { type: "button", class: "ob-tile", title: label, onclick: () => pickLook(worn) },
      characterPreview(worn, "#F5F6F8", TILE),
      h("span", { text: label }),
    );
    return { el, worn };
  });
  const mark = () => {
    const now = characterFromStorage(host?.settings().defaultCharacter ?? "");
    // A tile is "the one" only while nothing is worn over it: under a Santa hat
    // the matching face is not what anybody sees.
    const bare = !hasFestive(now);
    for (const tile of tiles) {
      const on = bare && sameFace(tile.worn, now);
      tile.el.classList.toggle("on", on);
      tile.el.setAttribute("aria-pressed", String(on));
    }
  };
  mark();
  markLooks = mark;
  return {
    nodes: [h("div", { class: "ob-col gap14" },
      heading(t("Pick my look")),
      h("div", { class: "ob-looks", role: "group" }, ...tiles.map((tile) => tile.el)),
      h("p", {
        class: "ob-hint small",
        text: t("There is more under Settings › Characters: shapes, eyes and a look for each pill."),
      }),
    )],
  };
}

/**
 * A tile becomes the whole look: its face, the body kept, and the Christmas
 * outfit taken off — a hat sits where the accessory goes and festive eyes
 * replace the eyes, so keeping it made a click change nothing you could see,
 * here or on the island. Settings' grid keeps the outfit; it has its own
 * Christmas block.
 */
function pickLook(worn: MochiCharacter) {
  if (!host) return;
  const s = host.settings();
  const next = characterToStorage(worn);
  if (next === s.defaultCharacter) return;
  s.defaultCharacter = next;
  host.save();
  markLooks?.();
  // A look was picked: Mochi likes it.
  mochi.engine?.triggerEmote("love");
}

function toolsScreen(): Screen {
  const by = host!;
  const counter = h("p", { class: "ob-count" });
  const rows: { id: string; row: HTMLElement; sw: HTMLButtonElement }[] = [];
  const update = () => {
    const active = host?.settings().activeIntegrations ?? [];
    const used = active.length;
    counter.textContent = t("%lld/4 slots used", used);
    counter.classList.toggle("full", used >= SLOTS);
    for (const { id, row, sw } of rows) {
      const on = active.includes(id);
      const full = used >= SLOTS && !on;
      setSwitch(sw, on);
      sw.disabled = full;
      row.classList.toggle("full", full);
    }
  };
  // Services only, in the catalogue's order. Claude Code is reached and
  // switched in Settings, never from the welcome.
  for (const agent of INTEGRATION_AGENTS) {
    if (!TOGGLEABLE_INTEGRATION_IDS.includes(agent.id)) continue;
    // Not where this build cannot read what is playing — as Settings does.
    if (agent.id === "integration_music" && !by.media) continue;
    const sw = toggleSwitch(false, () => togglePill(agent.id, update));
    const row = h("label", { class: "ob-row" },
      h("i", { class: "ob-dot", style: `background:${agent.color}` }),
      h("span", { class: "ob-row-name", text: t(agent.name) }),
      sw,
    );
    rows.push({ id: agent.id, row, sw });
  }
  update();
  return {
    nodes: [h("div", { class: "ob-col gap12" },
      heading(t("What should I keep an eye on?"),
        t("Up to four. Mattermost, Ato and WhatsApp ask you to sign in, under Settings › Integrations.")),
      h("div", { class: "ob-rows" }, ...rows.map((r) => r.row)),
      counter,
    )],
  };
}

/** On or off, the way Settings does it: four at most, and a fifth refused. */
function togglePill(id: string, after: () => void) {
  if (!host) return;
  const s = host.settings();
  const active = s.activeIntegrations;
  if (active.includes(id)) {
    s.activeIntegrations = active.filter((x) => x !== id);
  } else {
    if (active.length >= SLOTS) return;
    s.activeIntegrations = [...active, id];
  }
  host.save();
  after();
}

function startupScreen(): Screen {
  const s = host!.settings();
  const row = (label: string, on: boolean, set: (v: boolean) => void) => {
    const sw: HTMLButtonElement = toggleSwitch(on, () => {
      const next = !sw.classList.contains("on");
      setSwitch(sw, next);
      set(next);
    });
    return h("label", { class: "ob-row" }, h("span", { class: "ob-row-name", text: label }), sw);
  };
  return {
    nodes: [h("div", { class: "ob-col gap16" },
      heading(t("Almost there"), t("Two last things. Both can be changed in Settings.")),
      h("div", { class: "ob-rows narrow" },
        row(t("Launch at startup"), s.autostart, (v) => {
          if (!host) return;
          host.settings().autostart = v;
          host.save();
        }),
        row(t("Enable sounds"), s.soundEnabled, (v) => {
          if (!host) return;
          const now = host.settings();
          now.soundEnabled = v;
          Sound.setEnabled(v && now.enabled);
          host.save();
        }),
      ),
    )],
  };
}

function readyScreen(): Screen {
  const by = host!;
  const name = greetingName(by.settings().userName, by.accountName);
  const tip = (path: string, text: string) => h("li", {},
    h("span", { class: "ob-tip-icon" }, svg(path, 15, { stroke: 1.7 })),
    h("span", { text }),
  );
  return {
    go: t("Open Notchy"),
    nodes: [h("div", { class: "ob-ready" },
      h("h1", { class: "ob-big", text: name ? t("All set, %@!", name) : t("All set!") }),
      h("ul", { class: "ob-tips" },
        tip(TIP_POINTER, t("Move the pointer to my spot on the screen whenever you want to see me.")),
        tip(TIP_TRAY, t("Settings are in the tray icon.")),
        tip(TIP_SLIDERS, t("Everything you picked here can be changed there.")),
      ),
    )],
  };
}

// ── Pieces ────────────────────────────────────────────────────────────────────

/** The Mac's small switch. The row around it is a <label>, so the whole row flips it. */
function toggleSwitch(on: boolean, onToggle: () => void): HTMLButtonElement {
  const el = h("button", { type: "button", class: "ob-switch", role: "switch" });
  setSwitch(el, on);
  el.addEventListener("click", onToggle);
  return el;
}

function setSwitch(el: HTMLElement, on: boolean) {
  el.classList.toggle("on", on);
  el.setAttribute("aria-checked", String(on));
}

/**
 * The panel's background moves the window, the way the Mac's is movable by
 * its background — anywhere that is not something to click or type in.
 */
function onPress(e: MouseEvent) {
  if (!host || e.button !== 0) return;
  if ((e.target as Element | null)?.closest("button, input, label, a")) return;
  host.drag();
}

// Enter is the button's, from anywhere — the Mac's default action. A focused
// button answers it itself.
document.addEventListener("keydown", (e) => {
  if (!host || e.key !== "Enter" || e.isComposing || e.repeat) return;
  if ((e.target as Element | null)?.closest("button")) return;
  e.preventDefault();
  primary?.click();
});

// ── Mochi ─────────────────────────────────────────────────────────────────────

/** Sets the size he is heading for; `animate` eases there, as the Mac's step change does. */
function resize(to: number, animate: boolean) {
  mochi.from = animate ? mochi.size : to;
  mochi.to = to;
  mochi.t0 = performance.now();
  if (!animate) mochi.size = to;
}

function drawMochi(now: number, dt: number) {
  const { engine, canvas } = mochi;
  if (!engine || !canvas || !host) return;
  const k = Math.min(1, Math.max(0, (now - mochi.t0) / RESIZE_MS));
  const eased = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
  mochi.size = mochi.from + (mochi.to - mochi.from) * eased;

  const w = mochi.size / 0.6;
  const height = w + OVERHANG;
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const key = `${w.toFixed(2)}@${dpr}`;
  if (key !== mochi.px) {
    mochi.px = key;
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(height * dpr);
    canvas.style.width = `${w}px`;
    canvas.style.height = `${height}px`;
  }
  const ctx = canvas.getContext("2d");
  if (!ctx) return;
  // Whatever he is wearing right now, so the look screen changes him under
  // the user's eyes.
  engine.character = characterFromStorage(host.settings().defaultCharacter);
  engine.update(dt);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, height);
  engine.draw(ctx, w, height);
}

function tick(now: number) {
  mochi.raf = 0;
  if (!host || document.hidden) return;
  const dt = Math.min(0.05, Math.max(0, (now - mochi.last) / 1000));
  mochi.last = now;
  drawMochi(now, dt);
  mochi.raf = requestAnimationFrame(tick);
}

/** Frames only while the welcome is up and its window can be seen. */
function startLoop() {
  if (mochi.raf || !host || document.hidden) return;
  mochi.last = performance.now();
  mochi.raf = requestAnimationFrame(tick);
}

function stopLoop() {
  if (mochi.raf) cancelAnimationFrame(mochi.raf);
  mochi.raf = 0;
}

document.addEventListener("visibilitychange", () => {
  if (!host) return;
  if (document.hidden) {
    stopLoop();
    Sound.idle();
  } else {
    startLoop();
  }
});
