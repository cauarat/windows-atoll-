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
//
// Mochi up there is the island's Mochi: he watches the pointer, widens his eyes
// when it lands on him, sends hearts if it stays, and takes a slap — three in a
// row and he is dizzy. Only he is; the island never hears of it.

import { ONBOARDING_STEPS, onboardingProgress, type OnboardingStep } from "../core/onboarding";
import { GREETING_KEYS, dayPeriod, firstNameFromFullName, greetingName } from "../core/greetingName";
import { LANGUAGES, LANGUAGE_LABEL, language, t, type Language } from "../core/i18n";
import { Sound } from "../core/sound";
import { INTEGRATION_AGENTS, type Settings } from "../core/state";
import { ATO_PILL, AtoDriver, atoFestiveFrom, drawAtoInBotFrame, reactionFrom } from "../ato/view";
import {
  CHARACTER_PRESETS, CLASSIC, FESTIVE_SLOTS, SHAPES, characterFromStorage, characterToStorage,
  hasFestive, isFestiveSeason, sameFace, withFestive,
  type FestiveSlot, type MochiCharacter, type MochiShape,
} from "../mochi/character";
import { BotEngine, hexToRGB } from "../mochi/engine";
import { festiveData } from "../mochi/festive";
import { atoPreview, characterPreview } from "../mochi/preview";
import { MOCHI_SHAPE_LABEL } from "../mochi/shape";
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

/** Whose look and which tab the look screen opens on — a screenshot's choice. */
export interface LookStart {
  /** A pill's id; anything the look screen cannot dress is everyone. */
  editing?: string | null;
  /** `face`, `body` or `christmas`. */
  tab?: string | null;
}

/** Mochi on the hello and the last screen, and on the five questions. */
const BIG = 84;
const SMALL = 56;
/** Headroom above him for hearts and stars, as `BotPlacement` leaves. */
const OVERHANG = 34;
/** The look screen's tiles, and the chips that say whose look it is. */
const TILE = 30;
const CHIP = 20;
/** Pills the island has room for. */
const SLOTS = 4;
/** How long Mochi takes to change size between screens — the Mac's step animation. */
const RESIZE_MS = 200;
/** Everyone's Mochi: the island's off-white, which no pill wears. */
const EVERYONE = "#F5F6F8";
/**
 * How far a long name may shrink before it is cut — the Mac's
 * `minimumScaleFactor`: a tile's name, and a chip's, which has less room.
 */
const TILE_NAME_SCALE = 0.8;
const CHIP_NAME_SCALE = 0.65;

// The three tips' symbols: SF's cursorarrow.rays, a screen with its taskbar
// (the Mac's menubar.rectangle, turned the way a PC's tray sits), and
// slider.horizontal.3 — stroked on the 24 grid the other icons use.
const TIP_POINTER = "M11 11l8 3-3.4 1.4L14 19zM8.2 8.2 6 6M11 7.6V4.6M7.6 11H4.6M13.7 8.3l1.8-1.8M8.3 13.7l-1.8 1.8";
const TIP_TRAY = "M3.5 5.5h17v13h-17zM3.5 15h17M15.5 17h2";
const TIP_SLIDERS = "M4 7h9m4 0h3M4 12h3m4 0h9M4 17h11m4 0h1M15 5v4M9 10v4M17 15v4";

/** The look screen's tabs. */
const LOOK_TABS = ["face", "body", "christmas"] as const;
type LookTab = (typeof LOOK_TABS)[number];
const LOOK_TAB_LABEL: Record<LookTab, string> = { face: "Face", body: "Body", christmas: "Christmas" };

/**
 * The look screen's rows and scrolling grid. A press there — in a gap, or on
 * the scrollbar — is not the panel's background, so it never moves the window,
 * and an Enter from there is not the Continue button's.
 */
const LOOK_CONTROLS = ".ob-who, .ob-tabs, .ob-scroll";

type Point = { x: number; y: number };
interface Circle { x: number; y: number; r: number }

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
/** Repaints the look screen after a pick: its chips, tabs and marks, and the previews that changed. */
let repaintLook: (() => void) | null = null;
let helloTimer = 0;
/** Brings him round from a dizzy spell. */
let dizzyTimer = 0;

/** Whose look is being changed: "" for everyone — the default — or a pill's id. */
let editing = "";
/** The tab last picked. Ato, which only wears Christmas, shows that one whatever this says. */
let lookTab: LookTab = "face";
/** How far down each tab was scrolled, so going back to one finds it where it was left. */
let lookScroll: Partial<Record<LookTab, number>> = {};

/** Where the pointer is in the window, or null while it is somewhere else. */
let pointer: Point | null = null;

/**
 * Where he is looking, eased: the island's pull toward the pointer, followed
 * over 0.28 s rather than jumped to, so his face never runs ahead of him.
 */
const pull = { x: 0, y: 0 };
/** The frame the pull was last eased on, in ms; null before the first. */
let pullAt: number | null = null;

/** The pointer resting on him — the island's bot hover, timer and all. */
const hover = {
  on: false,
  /** Where the pointer was when the wait for hearts last began. */
  start: { x: 0, y: 0 } as Point,
  timer: 0,
  /** When he last sent hearts, in seconds: six apart at least. */
  lastLove: -Infinity,
};

/** Mochi at the top: one engine for the whole welcome, so he never blinks out between screens. */
const mochi = {
  engine: null as BotEngine | null,
  /** Ato's own mascot, for when the look screen is dressing Ato. */
  ato: null as AtoDriver | null,
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
  /** The body colour last given to the engine. */
  colour: "",
};

/** Whether the welcome is up. */
export function welcomeShowing(): boolean {
  return host !== null;
}

/**
 * Puts the welcome up on `step` — the hello, unless a screenshot asked for
 * another — with the settings as they are now.
 */
export function startWelcome(
  into: HTMLElement, by: WelcomeHost, step: string = "welcome", look: LookStart = {},
) {
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
  // The look screen opens on everyone's face, unless a screenshot asked otherwise.
  const pill = look.editing ?? "";
  editing = lookable(pill, by.media) ? pill : "";
  lookTab = LOOK_TABS.find((tab) => tab === look.tab) ?? "face";
  lookScroll = {};
  pointer = null;
  pull.x = 0;
  pull.y = 0;
  pullAt = null;
  hover.on = false;
  hover.lastLove = -Infinity;

  Sound.setEnabled(s.soundEnabled && s.enabled);
  Sound.setVolume(s.soundVolume);
  void Sound.preload();

  const engine = new BotEngine();
  engine.bodyColor = hexToRGB(EVERYONE);
  engine.particleOverhang = OVERHANG;
  engine.setState("idle", true);
  // Three slaps in a row: dizzy, the island's spell without its confused card,
  // which has nowhere to go here.
  engine.onDizzy = () => {
    engine.setState("dizzy");
    Sound.play("dizzy");
    window.clearTimeout(dizzyTimer);
    dizzyTimer = window.setTimeout(() => {
      dizzyTimer = 0;
      engine.setState("idle");
      engine.triggerEmote("happy");
    }, 3300);
  };
  mochi.engine = engine;
  mochi.ato = new AtoDriver(true);
  mochi.colour = EVERYONE;
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
  window.clearTimeout(dizzyTimer);
  dizzyTimer = 0;
  cancelHover();
  hover.on = false;
  stopLoop();
  const had = host !== null;
  host = null;
  primary = null;
  repaintLook = null;
  mochi.engine = null;
  mochi.ato = null;
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

/** The engine behind the Mochi at the top, for a preview to look into. */
export function welcomeEngine(): BotEngine | null {
  return mochi.engine;
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
  /**
   * Down to the button rather than only as tall as it is: the look screen,
   * whose tiles scroll in whatever room the rest leaves them.
   */
  fill?: boolean;
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

  repaintLook = null;
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
    h("div", { class: !question ? "ob-screen center" : screen.fill ? "ob-screen fill" : "ob-screen" },
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
        text: t("I live at the edge of your screen. I keep an eye on your messages and your music, and you answer them without leaving what you are doing."),
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

/**
 * Settings › Characters on one screen: whose look along the top — everyone,
 * then each pill — and a tab each for the face, the body and Christmas. Its
 * own code rather than Settings', which ships as it is, with Settings' rules:
 * the colour is always the pill's, a pick is saved at once, and Ato, which is
 * not a Mochi, only ever wears Christmas.
 *
 * A pick repaints in place — the chips, the tabs, the marks — and draws again
 * only the previews whose character it changed.
 */
function lookScreen(): Screen {
  const who = h("div", {
    class: "ob-who", role: "group", tabindex: "-1", "aria-label": t("Character for"),
  });
  const resetLine = h("div", { class: "ob-reset" },
    h("button", {
      type: "button", class: "ob-link", text: t("Use the default for this one"), onclick: useDefault,
    }));
  const tabBar = h("div", { class: "ob-tabs", role: "tablist", tabindex: "-1" });
  const scroller = h("div", { class: "ob-scroll", role: "tabpanel", tabindex: "-1" });

  let chips: { id: string; el: HTMLButtonElement; drawn: string }[] = [];
  let tabsDrawn = "";
  let gridTab: LookTab | null = null;
  let tiles: LookTile[] = [];

  scroller.addEventListener("scroll", () => {
    if (gridTab) lookScroll[gridTab] = scroller.scrollTop;
  }, { passive: true });

  const paintChips = (s: Settings) => {
    const ids = lookChoices(s, host?.media ?? false);
    const fresh = ids.join(" ") !== chips.map((chip) => chip.id).join(" ");
    if (fresh) {
      chips = ids.map((id) => {
        const name = id ? t(INTEGRATION_AGENTS.find((a) => a.id === id)?.name ?? id) : t("Everyone");
        const el = h("button", { type: "button", class: "ob-chip", title: name, onclick: () => pickWho(id) },
          h("span", { text: name }));
        return { id, el, drawn: "" };
      });
      clear(who);
      who.append(...chips.map((chip) => chip.el));
    }
    for (const chip of chips) {
      paintPreview(chip, characterOf(s, chip.id), colourOf(chip.id), chip.id === ATO_PILL, CHIP);
      mark(chip.el, chip.id === editing);
    }
    if (fresh && who.isConnected) fitNames(who);
  };

  const paintTabs = (c: MochiCharacter) => {
    const list = lookTabs(c);
    if (list.join(" ") !== tabsDrawn) {
      tabsDrawn = list.join(" ");
      clear(tabBar);
      for (const tab of list) {
        tabBar.append(h("button", {
          type: "button", class: "ob-tab", role: "tab", "data-tab": tab,
          text: t(LOOK_TAB_LABEL[tab]), onclick: () => pickTab(tab),
        }));
      }
    }
    const shown = shownTab(c);
    for (const el of tabBar.querySelectorAll<HTMLElement>(".ob-tab")) {
      el.setAttribute("aria-selected", String(el.dataset.tab === shown));
    }
  };

  const paintGrid = (c: MochiCharacter, colour: string) => {
    const tab = shownTab(c);
    const ato = editing === ATO_PILL;
    const fresh = tab !== gridTab;
    if (fresh) {
      gridTab = tab;
      tiles = [];
      clear(scroller);
      scroller.append(lookTabContent(tab, tiles));
    }
    for (const tile of tiles) {
      paintPreview(tile, tile.shows(c), colour, ato, TILE);
      mark(tile.el, tile.worn(c));
    }
    if (fresh && scroller.isConnected) settleGrid();
  };

  /** A tab once on screen: its names fitted, and scrolled to where it was left. */
  const settleGrid = () => {
    fitNames(scroller);
    if (gridTab) scroller.scrollTop = lookScroll[gridTab] ?? 0;
  };

  const paint = () => {
    if (!host) return;
    const s = host.settings();
    const c = characterOf(s, editing);
    paintChips(s);
    // There whether or not there is a look of its own to undo, so nothing
    // under it jumps when there is.
    resetLine.classList.toggle("shown", editing !== "" && s.pillCharacters[editing] != null);
    paintTabs(c);
    paintGrid(c, colourOf(editing));
  };
  paint();
  repaintLook = paint;

  return {
    nodes: [h("div", { class: "ob-look" },
      heading(t("Pick a look for each Mochi"),
        t("Give each pill its own face. The colour still comes from the pill, so you always know who is talking.")),
      who,
      resetLine,
      tabBar,
      scroller,
    )],
    fill: true,
    after: () => {
      fitNames(who);
      settleGrid();
    },
  };
}

/** One tile of the look screen: a preview, a name, and what picking it writes. */
interface LookTile {
  el: HTMLButtonElement;
  /** Who its preview shows, for the character being edited. */
  shows: (c: MochiCharacter) => MochiCharacter;
  /** Whether it is what is worn now. */
  worn: (c: MochiCharacter) => boolean;
  /** What its preview was last drawn from, so it is drawn again only when that changes. */
  drawn: string;
}

/** A tile; picking it writes what it shows, unless `pick` says otherwise. Its name may shrink. */
function lookTile(
  name: string,
  shows: (c: MochiCharacter) => MochiCharacter,
  worn: (c: MochiCharacter) => boolean,
  pick: (c: MochiCharacter) => MochiCharacter = shows,
): LookTile {
  const el = h("button", { type: "button", class: "ob-tile shrink", title: name },
    h("span", { text: name }));
  el.addEventListener("click", () => {
    if (host) writeLook(pick(characterOf(host.settings(), editing)));
  });
  return { el, shows, worn, drawn: "" };
}

/** The tiles of one tab, collected into `tiles`, in whatever holds them. */
function lookTabContent(tab: LookTab, tiles: LookTile[]): HTMLElement {
  const content = tab === "face" ? lookGrid(faceTiles(), tiles)
    : tab === "body" ? lookGrid(bodyTiles(), tiles)
    : christmasContent(tiles);
  // A sliver above and below, so the first and last rows' edges are not cut.
  return h("div", { class: "ob-pane" }, content);
}

function lookGrid(list: LookTile[], into: LookTile[]): HTMLElement {
  into.push(...list);
  return h("div", { class: "ob-looks", role: "group" }, ...list.map((tile) => tile.el));
}

/**
 * Classic, then the eighteen, each on the body already chosen. A face is the
 * whole look: the Christmas outfit comes off with it — a hat sits where the
 * accessory goes and festive eyes replace the eyes, so keeping it made a pick
 * change nothing you could see, here or on the island. Settings' grid keeps
 * the outfit; it has its own Christmas block, and so has this screen.
 */
function faceTiles(): LookTile[] {
  const faces: { face: MochiCharacter; name: string }[] = [
    { face: CLASSIC, name: "Classic" },
    ...CHARACTER_PRESETS.map((p) => ({ face: p.character, name: p.name })),
  ];
  return faces.map(({ face, name }) => lookTile(t(name),
    (c) => ({ accessory: face.accessory ?? null, eye: face.eye ?? null, shape: c.shape ?? null }),
    // The one only while nothing is worn over it: under a Santa hat the
    // matching face is not what anybody sees.
    (c) => !hasFestive(c) && sameFace(face, c)));
}

/**
 * Classic and the six bodies, each wearing the face chosen now. Only the body
 * changes: the face stays, and so does anything worn over it.
 */
function bodyTiles(): LookTile[] {
  const bodies: (MochiShape | null)[] = [null, ...SHAPES];
  return bodies.map((shape) => lookTile(t(shape ? MOCHI_SHAPE_LABEL[shape] : "Classic"),
    (c) => ({ accessory: c.accessory ?? null, eye: c.eye ?? null, shape }),
    (c) => (c.shape ?? null) === shape,
    (c) => ({ ...c, shape })));
}

/**
 * Christmas: a whole outfit at once, then one part at a time. Each tile is the
 * Mochi being edited — or Ato — with that one thing changed; the face and the
 * body underneath are left alone, and come back when the hat comes off.
 */
function christmasContent(into: LookTile[]): HTMLElement {
  const { catalog } = festiveData();
  const box = h("div", { class: "ob-fest" });
  // In season only: past it the tab is here so that something can be taken
  // off, and the date would be a lie.
  if (christmasOffered()) box.append(h("span", { class: "ob-badge", text: t("Until January 6") }));
  const section = (label: string, list: LookTile[]) => {
    box.append(h("div", { class: "ob-part" },
      h("div", { class: "ob-section", text: t(label) }),
      lookGrid(list, into)));
  };

  const bare = { head: null, eyes: null, texture: null, extra: null };
  section("Ready-made", [
    lookTile(t("None"), (c) => withFestive(c, bare), (c) => !hasFestive(c)),
    ...catalog.presets.map((preset) => {
      const parts = { head: preset.head, eyes: preset.eyes, texture: preset.texture, extra: preset.extra };
      return lookTile(t(preset.name), (c) => withFestive(c, parts),
        (c) => FESTIVE_SLOTS.every((slot) => (c.festive?.[slot] ?? null) === parts[slot]));
    }),
  ]);
  const rows: [string, FestiveSlot, [string, string][]][] = [
    ["Head", "head", catalog.heads],
    ["Eyes", "eyes", catalog.eyes],
    ["Texture", "texture", catalog.textures],
    ["Extra", "extra", catalog.extras],
  ];
  for (const [label, slot, list] of rows) {
    section(label, [
      lookTile(t("None"), (c) => withFestive(c, { [slot]: null }), (c) => !c.festive?.[slot]),
      ...list.map(([id, name]) =>
        lookTile(t(name), (c) => withFestive(c, { [slot]: id }), (c) => c.festive?.[slot] === id)),
    ]);
  }
  return box;
}

/** Draws a chip's or a tile's preview again — only when what it shows has changed. */
function paintPreview(
  item: { el: HTMLElement; drawn: string }, c: MochiCharacter, colour: string, ato: boolean, size: number,
) {
  // Ato has one colour of its own and wears nothing but Christmas, so that is
  // all its preview depends on.
  const key = ato ? `ato ${characterToStorage({ festive: c.festive })}` : `${colour} ${characterToStorage(c)}`;
  if (key === item.drawn) return;
  item.drawn = key;
  const canvas = ato ? atoPreview(c.festive, size) : characterPreview(c, colour, size);
  const old = item.el.querySelector("canvas");
  if (old) old.replaceWith(canvas);
  else item.el.prepend(canvas);
}

function mark(el: HTMLElement, on: boolean) {
  el.classList.toggle("on", on);
  el.setAttribute("aria-pressed", String(on));
}

/**
 * Long names shrink before they are cut — the Mac's `minimumScaleFactor`, 0.8
 * on a tile and 0.65 on a chip. Measured, so only once they are on screen;
 * every one read before any is written, so it costs one layout.
 */
function fitNames(within: HTMLElement) {
  const spans = [...within.querySelectorAll<HTMLElement>(".ob-chip > span, .ob-tile.shrink > span")];
  for (const span of spans) span.style.fontSize = "";
  const sizes = spans.map((span) => {
    const box = span.clientWidth;
    const text = span.scrollWidth;
    if (box === 0 || text <= box) return null;
    const style = getComputedStyle(span);
    const pad = parseFloat(style.paddingLeft) + parseFloat(style.paddingRight);
    const least = span.parentElement?.classList.contains("ob-chip") ? CHIP_NAME_SCALE : TILE_NAME_SCALE;
    // A pixel to spare: glyphs do not scale exactly with the font size.
    const k = Math.max(least, (box - pad - 1) / (text - pad));
    return parseFloat(style.fontSize) * k;
  });
  spans.forEach((span, i) => {
    const size = sizes[i];
    if (size != null) span.style.fontSize = `${size.toFixed(2)}px`;
  });
}

/**
 * Saves a pick for whoever is being edited, on a fresh read of the settings —
 * nothing at all when it is what they already look like, so a pill only gets
 * a look of its own by being given a different one.
 */
function writeLook(next: MochiCharacter) {
  if (!host) return;
  const s = host.settings();
  const text = characterToStorage(next);
  if (text === characterToStorage(characterOf(s, editing))) return;
  if (editing) {
    s.pillCharacters = { ...s.pillCharacters, [editing]: text };
  } else {
    s.defaultCharacter = text;
  }
  host.save();
  picked();
}

/** "Use the default for this one": the pill's own look goes, and the default reaches it again. */
function useDefault() {
  if (!host || !editing) return;
  const s = host.settings();
  if (s.pillCharacters[editing] == null) return;
  const { [editing]: _, ...rest } = s.pillCharacters;
  s.pillCharacters = rest;
  host.save();
  picked();
}

/** A look changed: the screen catches up, and Mochi likes it. */
function picked() {
  repaintLook?.();
  mochi.engine?.triggerEmote("love");
}

function pickWho(id: string) {
  if (editing === id) return;
  editing = id;
  repaintLook?.();
}

function pickTab(tab: LookTab) {
  lookTab = tab;
  repaintLook?.();
}

/** Christmas on offer: in season, and always in a dev build — Settings' rule. */
function christmasOffered(): boolean {
  return import.meta.env.DEV || isFestiveSeason();
}

/** A pill's colour, or everyone's white. */
function colourOf(id: string): string {
  return INTEGRATION_AGENTS.find((a) => a.id === id)?.color ?? EVERYONE;
}

/** Who a pill is now: its own character, or the default's — `State.characterFor`. */
function characterOf(s: Settings, id: string): MochiCharacter {
  const own = id ? s.pillCharacters[id] : undefined;
  return characterFromStorage(own ?? s.defaultCharacter);
}

/**
 * Whether the look screen dresses this pill: every one, as on the screen after
 * it, except the player where this build cannot read one.
 */
function lookable(id: string, media: boolean): boolean {
  return id !== "integration_music" || media;
}

/**
 * The chips, in the catalogue's order: everyone, then each pill it can dress.
 * Ato only while Christmas has something for it — the Mac's `pickable` — since
 * Christmas is all it wears.
 */
function lookChoices(s: Settings, media: boolean): string[] {
  const ids = [""];
  for (const agent of INTEGRATION_AGENTS) {
    if (!lookable(agent.id, media)) continue;
    if (agent.id === ATO_PILL && !christmasOffered() && editing !== ATO_PILL
      && !hasFestive(characterOf(s, ATO_PILL))) continue;
    ids.push(agent.id);
  }
  return ids;
}

/**
 * The tabs for the Mochi being edited. Christmas while it is in season, and
 * past it for as long as something is still worn — a hat nobody can take off
 * is worse than a tab that outstays its month. Ato has nothing else.
 */
function lookTabs(c: MochiCharacter): LookTab[] {
  if (editing === ATO_PILL) return ["christmas"];
  return christmasOffered() || hasFestive(c) ? ["face", "body", "christmas"] : ["face", "body"];
}

/** The tab on screen: the one picked, while it is on offer. */
function shownTab(c: MochiCharacter): LookTab {
  const tabs = lookTabs(c);
  return tabs.includes(lookTab) ? lookTab : tabs[0];
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
  // Every pill, in the catalogue's order.
  for (const agent of INTEGRATION_AGENTS) {
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
 * its background — anywhere that is not something to click or type in. Mochi
 * is something to click: a press on him is a slap, as on the island, and
 * never a drag.
 */
function onPress(e: MouseEvent) {
  if (!host || e.button !== 0) return;
  const circle = mochiCircle();
  if (circle && inCircle(circle, { x: e.clientX, y: e.clientY })) {
    Sound.resume();
    cancelHover();
    mochi.engine?.slap();
    return;
  }
  if ((e.target as Element | null)?.closest(`button, input, label, a, ${LOOK_CONTROLS}`)) return;
  host.drag();
}

// Enter is the button's, from anywhere — the Mac's default action. A focused
// button answers it itself, and the look screen's rows and grid keep it.
document.addEventListener("keydown", (e) => {
  if (!host || e.key !== "Enter" || e.isComposing || e.repeat) return;
  if ((e.target as Element | null)?.closest(`button, ${LOOK_CONTROLS}`)) return;
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
  // Whoever the look screen is dressing — everyone, or one pill in its own
  // colour — and everyone everywhere else. Read every frame, so a pick changes
  // him under the user's eyes.
  const who = ONBOARDING_STEPS[index] === "look" ? editing : "";
  const colour = colourOf(who);
  if (colour !== mochi.colour) {
    mochi.colour = colour;
    engine.bodyColor = hexToRGB(colour);
  }
  engine.character = characterOf(host.settings(), who);
  follow(now);
  engine.update(dt);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, height);
  // He leans toward the pointer, all of him as one piece — the hat, the nose
  // and the beard with the face — about the middle of his body.
  const mx = w / 2;
  const my = w / 2 + OVERHANG;
  ctx.translate(mx + pull.x * 3, my - pull.y * 2.5);
  ctx.rotate(pull.x * 0.07);
  ctx.translate(-mx, -my);
  engine.applyDance(ctx, w, height);
  // Ato wears its own mascot, as on the island; the engine underneath still
  // runs every hover, slap and emote for it to wear.
  if (who === ATO_PILL && mochi.ato && engine.morph < 0.05) {
    const nowS = now / 1000;
    drawAtoInBotFrame(ctx, mochi.ato.frame(nowS, "idle", reactionFrom(engine)), w, height, OVERHANG,
      atoFestiveFrom(engine, nowS));
    engine.drawParticlesOnly(ctx, w, height);
    return;
  }
  engine.draw(ctx, w, height);
}

/**
 * Where he can be petted and slapped, in window coordinates — the island's
 * `isBotHit`: a circle half the canvas across, on the middle of his body as it
 * stands, never as it leans.
 */
function mochiCircle(): Circle | null {
  const canvas = mochi.canvas;
  if (!canvas?.isConnected) return null;
  const box = canvas.getBoundingClientRect();
  const r = box.width / 2;
  return { x: box.left + r, y: box.top + OVERHANG + r, r };
}

function inCircle(c: Circle, p: Point): boolean {
  return (p.x - c.x) ** 2 + (p.y - c.y) ** 2 <= c.r * c.r;
}

/**
 * His gaze, once a frame. The island's pull toward the pointer — tanh of the
 * distance to his body — eased over 0.28 s of real time, then taken in part:
 * the pointer is never far from him here, and at the island's full strength
 * his eyes swung past his own face and slid off the parts that do not turn
 * with them. The rest of the pull is the lean `drawMochi` gives all of him.
 */
function follow(now: number) {
  const engine = mochi.engine;
  if (!engine) return;
  const c = mochiCircle();
  const p = pointer;
  const tx = c && p ? Math.tanh((p.x - c.x) / 260) : 0;
  const ty = c && p ? -Math.tanh((p.y - c.y) / 200) : 0;
  const dt = pullAt === null ? 0 : Math.min(0.1, Math.max(0, (now - pullAt) / 1000));
  pullAt = now;
  const k = 1 - Math.exp(-dt / 0.28);
  pull.x += (tx - pull.x) * k;
  pull.y += (ty - pull.y) * k;
  engine.lookX = pull.x * 0.3;
  engine.lookY = pull.y * 0.24;
  // Every frame as well as every move: he changes size between screens under
  // a pointer that never moved.
  trackHover(c, p);
}

/**
 * The island's petting, to the letter: wider eyes the moment the pointer lands
 * on him, hearts if it stays 1.9 s, never twice within 6 s, and nothing while
 * he is dizzy. A hand that wanders more than 40 px starts the wait again.
 */
function trackHover(c: Circle | null, p: Point | null) {
  const engine = mochi.engine;
  if (!engine) return;
  if (!c || !p || engine.state === "dizzy" || !inCircle(c, p)) {
    if (hover.on) cancelHover();
    hover.on = false;
    return;
  }
  if (!hover.on) hoverIn(p);
  hover.on = true;
  if (Math.hypot(p.x - hover.start.x, p.y - hover.start.y) > 40) {
    hover.start = { x: p.x, y: p.y };
    scheduleLove();
  }
}

function hoverIn(p: Point) {
  const engine = mochi.engine;
  if (!engine || performance.now() / 1000 - hover.lastLove < 6) return;
  hover.start = { x: p.x, y: p.y };
  engine.blink();
  engine.tgEs = 1.08;
  Sound.play("hover");
  scheduleLove();
}

function scheduleLove() {
  window.clearTimeout(hover.timer);
  hover.timer = window.setTimeout(() => {
    hover.timer = 0;
    const engine = mochi.engine;
    if (!engine || !hover.on || engine.state === "dizzy") return;
    if (performance.now() / 1000 - hover.lastLove < 6) return;
    hover.lastLove = performance.now() / 1000;
    engine.triggerEmote("love");
    Sound.play("love");
  }, 1900);
}

/** The island's `cancelBotHover`: the wait for hearts is off and his eyes go back. */
function cancelHover() {
  window.clearTimeout(hover.timer);
  hover.timer = 0;
  if (mochi.engine) mochi.engine.tgEs = 1;
}

// The pointer, from the page's own events, in window coordinates: his eyes
// follow it on the next frame, and landing on him counts at once.
document.addEventListener("pointermove", (e) => {
  if (!host) return;
  pointer = { x: e.clientX, y: e.clientY };
  trackHover(mochiCircle(), pointer);
});

// Out of the window: nobody to look at, and nobody petting him.
document.addEventListener("mouseout", (e) => {
  if (!host || e.relatedTarget) return;
  pointer = null;
  trackHover(null, null);
});

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
