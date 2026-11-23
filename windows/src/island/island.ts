// The island: DOM shell, sizing animation, Mochi placement, mouse handling.
// Mirrors IslandRootView.swift + IslandWindowController.swift.

import { CLOSE_MS, OPEN_DAMPING, OPEN_RESPONSE, Spring, Tracked, clamp } from "../core/anim";
import {
  DEFAULT_POSITION, METRICS, anchorFor, islandOrigin, islandX, islandY, radiusCss,
  type IslandAnchor,
} from "../core/anchor";
import { asleepFor, drawModeFor, foldFor, refoldNeeded, type Fold } from "../core/fold";
import { FocusTimer, TIMER_COLOR } from "../core/timer";
import { Hydration } from "../core/hydrationStore";
import { Bridge, IS_TAURI, onDragDrop } from "../core/bridge";
import {
  EXPANDED_CORNER, EXPANDED_W, MESSAGE_BODY_TWO_LINES, messageBodyWidth,
  VOICE_GAP, VOICE_PLAYER_HEIGHT, VOICE_SCROLLER_ROOM,
  NOTCH_W, PANEL_H, PANEL_W,
  ROUNDED_CORNER, VIEW_LAYOUTS, WAKE_STRIP_H, WAKE_STRIP_W,
  botGlowColor, botGlowOpacity, botPosition, chatPromptHeight,
  isScreen, islandSize,
  type BotEmoteName, type BotStateName, type IslandMode, type IslandViewName,
} from "../core/layout";
import { pageForView, siteHost } from "../core/pageState";
import { PageHost } from "./pageHost";
import { Sound } from "../core/sound";
import { opensTarget, opensTargetAt, type PillClick } from "../core/pillOpen";
import {
  ALWAYS_LOADED_PILL, INTEGRATION_AGENTS, NOTIFICATIONS_PILL, State, sourceForPill,
} from "../core/state";
import * as ReplyAttachments from "./replyAttachments";
import { BotEngine, hexToRGB } from "../mochi/engine";
import { Greeting, GREETING_COLLAPSE_MS } from "../mochi/greeting";
import { createMiniBot, pruneMiniBots, syncMiniBotStates, tickMiniBots } from "../mochi/minibots";
import { UploadCanvas } from "../upload/canvas";
import { USC, UploadSeq } from "../upload/sequence";
import { buildHeader, buildViews, type ViewActions, type ViewHost } from "../views/views";
import { buildCompactSip } from "../views/hydration";
import { h, svg, clear, measureBodyHeight } from "../views/dom";
import { ICONS } from "../views/icons";
import { PILL_LOGOS, siteGlyph } from "../views/logos";
import { ATO_PILL, AtoDriver, atoFestiveFrom, atoStateFor, drawAtoInBotFrame, reactionFrom } from "../ato/view";
import {
  DIAMETER as RING_D, chromeBounds, drawn as ringDrawn, edgeAction, layout as ringLayout, visible as ringVisible,
  type EdgeButton,
} from "../core/edgeRing";
import { IslandStateMachine } from "./fsm";
import { SnowLayer } from "./snowLayer";
import { ChristmasMusic } from "./christmasMusic";
import { isFestiveSeason } from "../mochi/character";
import { t } from "../core/i18n";
import { GREETING_KEYS, dayPeriod, greetingName } from "../core/greetingName";
import * as VoicePlayer from "./voicePlayer";

const BOT_OVERHANG = 40;
/** ChatGPT's row Mochi: the side of his canvas, `WebChatIslandView`'s 34 × 34. */
const ROW_MOCHI = 34;
/**
 * How long a view takes to fade out once another has taken its place — the
 * Mac's `.easeIn(duration: 0.16)`, and `.view`'s transition in style.css.
 */
const VIEW_FADE_OUT_MS = 160;

/**
 * What each button on the border draws.
 *
 * Mattermost and Ato are missing here because they wear their own marks,
 * out of `PILL_LOGOS`. They shared a bubble while this was a port of the Mac's
 * symbols: approximating someone else's logo is worse than not drawing it. But
 * nothing here is approximate — the Mac draws both in code, and its ratios came
 * off the published artwork. Carrying the same numbers across reproduces the
 * mark rather than guessing at it, so the two now look like what they are.
 */
const RING_MARKS: Record<string, string> = {
  integration_claude: ICONS.code,
  integration_music: ICONS.musicNote,
  integration_notifications: ICONS.bell,
  clipboard: ICONS.clipboard,
  timer: ICONS.timer,
  settings: ICONS.gear,
  hydration: ICONS.drop,
  agenda: ICONS.calendar,
};

/**
 * How long the pointer has to stay in a bottom wake strip before Mochi peeks.
 * Long enough that crossing it on the way to the tray does nothing, short
 * enough that aiming for it still feels immediate.
 */
/**
 * How long the resting island has to be held before it comes unstuck, in ms.
 *
 * Long, deliberately. The island is one press away from opening, and it sits
 * where the pointer passes on its way to the clock: anything quick enough to
 * feel like a shortcut would be short enough to trip over.
 */
const HOLD_MS = 2000;

/** How far the pointer may wander during that hold, in logical px. */
const HOLD_SLOP = 6;

const WAKE_DWELL_MS = 220;
/** Same margin as the Rust hit test (src-tauri/src/island.rs). */
/** Slack around the island that still counts as reaching it. */
const ENTER_MARGIN = 14;
/**
 * Slack around an open island that still counts as being on it.
 *
 * Wider than `ENTER_MARGIN` on purpose: opening asks the pointer to arrive
 * somewhere specific, closing asks it to clearly leave. Without the gap a
 * cursor resting on the boundary crosses it several times a second and the
 * island chatters.
 */
const STAY_MARGIN = 28;

/** The three views the drop sequence owns; leaving them stops the engine. */
const UPLOAD_VIEWS: ReadonlySet<IslandViewName> = new Set(["upload", "uploading", "choose"]);

/**
 * The views with a text field. These are the only times the island is allowed
 * to take keyboard focus — it is a non-activating window the rest of the time,
 * so whatever you were typing in keeps the cursor.
 */
const FIELD_VIEWS: ReadonlySet<IslandViewName> = new Set(["prompt", "message"]);

/** The two hydration cards: the only views where Mochi is drawn as a glass. */
const WATER_VIEWS: ReadonlySet<IslandViewName> = new Set(["hydration", "sip"]);
/** The water in him: cyan, or grey while reminders are paused. */
const WATER_COLOR = hexToRGB("#22D3EE");
const WATER_PAUSED = hexToRGB("#94A3B8");

/** Seconds between the drop and the moment the progress bar starts filling. */
const PRE_PROGRESS = USC.T_PROG_START - USC.T_DROP;

const modeOrder = (m: IslandMode) => (m === "hidden" ? 0 : m === "compact" ? 1 : 2);

export class Island {
  readonly fsm = new IslandStateMachine();

  private root: HTMLElement;
  private islandEl!: HTMLElement;
  private clipEl!: HTMLElement;
  private contentEl!: HTMLElement;
  private viewsEl!: HTMLElement;
  private botCanvas!: HTMLCanvasElement;
  /** Ato's orb, for while Ato is in focus — kept beside the engine, not instead of it. */
  private readonly ato = new AtoDriver(true);
  private botGlow!: HTMLElement;
  /** The ring that fills while the island is being held, and glows once it lifts. */
  private grabGlow!: HTMLElement;
  private greetingCanvas!: HTMLCanvasElement;
  private miniGrid!: HTMLElement;
  private compactTimer!: HTMLElement;
  /** The little glass on the closed island while a reminder waits for an answer. */
  private compactSip = buildCompactSip();
  private lastTimerSync = 0;
  private countdown!: HTMLElement;
  /** Snow on the island's floor, in season. */
  private snow = new SnowLayer();
  private wakeStrip!: HTMLElement;
  private ringEl!: HTMLElement;
  /** The buttons currently on the border, in the order `State.edgeButtons` gave. */
  private ring: { el: HTMLElement; button: EdgeButton }[] = [];
  /** What the ring was built from, so it is only rebuilt when it changes. */
  private ringKey = "";
  /** Mirrored from the settings so the frame loop never reaches into State. */
  private position: string = DEFAULT_POSITION;
  /**
   * The work area of the display the island is on, in logical pixels.
   *
   * Only a dropped point reads it — the six names answer without it — so the
   * placeholder here is never seen: Rust sends the real one with `boot` and
   * again on every `screen-changed`, both of which land before a free position
   * can have been chosen.
   */
  private area = { w: 1920, h: 1080 };
  private anchorGeom: IslandAnchor = anchorFor(DEFAULT_POSITION, 1920, 1080);

  /**
   * A press on the resting island that has not become anything yet.
   *
   * It turns into an open when the button comes back up, or into a drag when it
   * has been held for `HOLD_MS` — which is why opening waits for the mouse-up
   * rather than firing on the way down. The Mac has always opened on mouse-up
   * (`leftMouseUp` in IslandWindowController), so this is the two of them
   * landing on the same behaviour rather than parting ways.
   */
  private grab: { x: number; y: number; screenX: number; screenY: number; timer: number } | null =
    null;
  /** True from the moment the island comes unstuck until it is put down. */
  private dragging = false;
  /** Where the pointer was when the island lifted, in screen px (the Wayland delta). */
  private liftFrom = { x: 0, y: 0 };
  /** True where Rust has no global cursor to read and the page drives the drag. */
  private pageCursor = false;
  /** Set while the pointer waits out the dwell on a bottom wake strip. */
  private wakeDwell: number | null = null;

  private header!: ViewHost;
  private views!: Map<IslandViewName, ViewHost>;
  /** Puts ChatGPT and the site over the cards their views draw — island/pageHost.ts. */
  private pages!: PageHost;
  /** The reply field has the cursor: what `setPinned` was last told. */
  private fieldHeld = false;
  /**
   * Set while `dropCaret` takes the caret out of a view that has gone: the
   * field it was in is letting go because its card went, not because the
   * user left it.
   */
  private fieldLeftWithView = false;
  /** Kept so the views can be built a second time when the language changes. */
  private viewActions!: ViewActions;
  private uploadCanvas!: UploadCanvas;

  private width = new Tracked(NOTCH_W);
  private height = new Tracked(0);
  private radius = new Tracked(ROUNDED_CORNER);
  private botCx = new Spring(46);
  private botCy = new Spring(16);
  private botSize = new Spring(10);

  private engine = new BotEngine();
  /**
   * ChatGPT's row Mochi: an engine and an orb of his own, as the Mac's row has
   * a `BotCanvasView` of its own beside the island's — dressed from the same
   * state every frame, drawn into the row's canvas while the view is up
   * (`drawRowBot`). Made again each time the row comes to have a Mochi at all
   * (`liveRow`), which is how long the Mac's lives.
   */
  private rowEngine = new BotEngine();
  private rowAto = new AtoDriver(true);
  /** `rowEngine` is the row's Mochi as of now, rather than one left from an earlier opening. */
  private rowLive = false;
  /** ChatGPT's view was up, with its Mochi, on the last frame. */
  private rowWasUp = false;
  /** When it last stopped being up: he is drawn on through the view's fade. */
  private rowLeftAt = Number.NEGATIVE_INFINITY;
  /** The row's canvas, looked up again once the views have been built again. */
  private rowCanvas: HTMLCanvasElement | null = null;
  private greeting = new Greeting();
  /** The Christmas music setting and the master switch, as last applied. */
  private christmasWasOn = true;

  private running = false;
  /** Set once `start()` has run: it subscribes, and a second time would double every answer. */
  private started = false;
  private lastFrame = 0;
  private dirty = true;
  private canvasPx = 0;

  // Rust starts the window at full size so the launch greeting has room.
  /** What Rust has been asked for. Set the moment the request goes out. */
  private collapsed = false;
  /**
   * What the window actually is, which is what the island is drawn against.
   *
   * Apart from `collapsed` because the resize is an IPC round trip: through one
   * the island has to go on using the panel's offsets, while everything that
   * decides what to ask Rust for next has to know the request is already out.
   */
  private windowIsBar = false;
  private collapseTimer: number | null = null;
  /** A collapsed window asked for again (`refoldNeeded`), and not answered yet. */
  private refolding = false;
  /** `enabled` as of the last `applySettings`, to catch the switch coming on. */
  private wasEnabled = true;
  private wasInIsland = false;
  /** Last shape handed to Rust for the click-through test. */
  private pushedRect = { x: -1, y: -1, w: -1, h: -1 };
  private homeCollapseAt: number | null = null;
  /**
   * A card that arrived while the greeting was still playing.
   *
   * The greeting owns the island until it has run its course, so `alert()`
   * parks the view here instead of expanding onto it; the `coucou` → `petit`
   * arm of `wireFsm` hands it on once the canvas has folded.
   */
  private pendingAlertView: IslandViewName | null = null;

  // Bot hover → love (IslandWindowController.botHoverIn)
  private botHovering = false;
  private botHoverTimer: number | null = null;
  private lastLoveTime = 0;
  private botHoverStart = { x: 0, y: 0 };

  private confusedRecovery: number | null = null;
  private prevViewBeforeConfused: IslandViewName = "overview";
  private lastSyncedView: IslandViewName | null = null;
  /**
   * The view `screenChanged` last saw. Every route to a new view goes through
   * it; one that wrote `State.view` directly is caught by the difference.
   */
  private screenView: IslandViewName | null = null;

  /** Drop sequence bookkeeping: last tick played, and whether the ✓ has fired. */
  private uploadTens = 0;
  private uploadDone = false;

  constructor(root: HTMLElement) {
    this.root = root;
    // Asked for the card each time rather than handed one: the views are built
    // again when the language changes.
    this.pages = new PageHost((label) => {
      const view = label === "webchat" ? "webchat" : "web";
      return this.views?.get(view)?.el.querySelector<HTMLElement>(".page-card") ?? null;
    }, () => this.ensureRunning());
    this.build();
    this.wireFsm();
    this.wireInput();
    this.watchPointer();
    this.engine.onDizzy = () => this.handleDizzy();
    this.greeting.onComplete = () => this.fsm.greetComplete();
    State.subscribe(() => {
      this.dirty = true;
      this.ensureRunning();
    });
  }

  // ── DOM ─────────────────────────────────────────────────────────────────────

  private build() {
    const actions: ViewActions = {
      setView: (v) => this.setView(v),
      // The header's X and a card's OK. Through `dismiss`, so on a screen the X
      // puts it away the way the screen's own X does.
      collapse: () => this.dismiss(),
      closeScreen: () => this.closeScreen(),
      setFocus: (id) => {
        Sound.play("blip");
        this.openPill(id);
      },
      openTerminal: () => {
        const cwd = State.focusTask?.sessionCwd ?? null;
        void Bridge.openInVSCode(cwd);
      },
      // The ↗ button — same targets as openPillTarget() on macOS, and the
      // same method here, so the button and two clicks cannot drift
      // apart. It stays a single click: it is the explicit "open the thing",
      // for anyone who would rather not count clicks.
      openTarget: () => {
        const task = State.focusTask;
        if (task) this.openPillTarget(task.id);
      },
      openUrl: (url) => {
        if (url) void Bridge.openUrl(url);
      },
      decide: (d) => {
        const req = State.pendingApproval;
        void Bridge.log(`decide ${d} req=${req?.requestId ?? "none"}`);
        if (!req) return;
        Sound.play(d === "deny" ? "blip" : "approve");
        void Bridge.approvalDecision(req.requestId, d);
        State.pendingApproval = null;
        State.isPinned = false;
        this.fsm.pinned = false;
        State.updateTask("integration_claude", "working");
        State.setPillBadge("integration_claude", null);
        this.setView(State.defaultView());
      },
      toggleSound: () => {
        State.settings.soundEnabled = !State.settings.soundEnabled;
        Sound.setEnabled(State.settings.soundEnabled);
        void Bridge.saveSettings(State.settings);
        State.notify();
      },
      setVolume: (v) => {
        State.settings.soundVolume = v;
        Sound.setVolume(v);
        void Bridge.saveSettings(State.settings);
        State.notify();
      },
      setAutoClose: (s) => {
        State.settings.autoCloseInterval = s;
        this.fsm.notificationHoldDelay = s;
        void Bridge.saveSettings(State.settings);
        State.notify();
      },
      openSettingsWindow: (section) => void Bridge.openSettingsWindow(section),
      // The reply box holds the island open while it has the cursor, the same
      // way an approval waiting for an answer does. Letting go goes through
      // `letFieldGo`: what the click that took the caret does next decides it.
      focusField: (on) => {
        if (on) void Bridge.focusWindow(true);
        else this.letFieldGo();
      },
      setPinned: (on) => {
        // An approval waiting on its card pinned the island itself (hooks.ts),
        // and that pin is not the field's to take: the reply field the card
        // took the place of letting go is not the approval being answered.
        const pinned = on || (State.view === "approval" && State.pendingApproval != null);
        State.isPinned = pinned;
        this.fsm.pinned = pinned;
        this.fieldHeld = on;
        this.fsm.heldOpen = this.holdsOpen();
        if (on) {
          this.fsm.cancelTimers();
          this.homeCollapseAt = null;
        } else {
          State.lastActivity = performance.now();
          // Nothing else restarts the close timer once the cursor has already
          // left: without this the island would simply stay open for good.
          // Not for a field let go because its card went: the card that took
          // its place keeps its own terms, as on the Mac, where the reply card
          // going lets go of `isReplying` and starts nothing.
          if (!this.wasInIsland && !this.fieldLeftWithView) this.fsm.mouseLeft();
        }
        State.notify();
      },
      blip: () => Sound.play("blip"),
    };

    this.wakeStrip = h("div", { id: "wake-strip" });
    this.botGlow = h("div", { id: "bot-glow" });
    this.botCanvas = h("canvas", { id: "bot-canvas" });
    this.greetingCanvas = h("canvas", { id: "greeting-canvas" });
    this.miniGrid = h("div", { id: "mini-grid" });
    this.compactTimer = h("div", { id: "compact-timer" });
    this.countdown = h("div", { id: "countdown" });

    this.header = buildHeader(actions);
    this.viewActions = actions;
    this.views = buildViews(actions, () => this.animateGeometry(false));
    this.viewsEl = h("div", { id: "views" });
    for (const v of this.views.values()) this.viewsEl.append(v.el);
    this.contentEl = h("div", { id: "content" }, this.header.el, this.viewsEl);

    // The drop sequence draws the card, the bar and its own Mochi. It sits under
    // the header, which stays visible on top of it exactly as on macOS.
    this.uploadCanvas = new UploadCanvas({
      ask: () => {
        State.promptContext = State.droppedFile
          ? { kind: "file", name: State.droppedFile.name, path: State.droppedFile.path }
          : null;
        this.setView("prompt");
      },
      cancel: () => this.setView(State.defaultView()),
    });

    this.clipEl = h(
      "div",
      { id: "island-clip" },
      // First, so everything else in the island draws over it.
      this.snow.el,
      this.greetingCanvas,
      this.uploadCanvas.el,
      this.contentEl,
      // Last, over the cards: faint, and white, so it can only lighten.
      this.snow.fall,
    );
    this.grabGlow = h("div", { id: "grab-glow" });
    this.islandEl = h(
      "div",
      { id: "island" },
      this.grabGlow,
      this.clipEl,
      this.botGlow,
      this.botCanvas,
      this.miniGrid,
      this.compactTimer,
      this.compactSip.el,
      this.countdown,
    );

    const dpr = Math.min(2, window.devicePixelRatio || 1);
    this.greetingCanvas.width = Math.round(EXPANDED_W * dpr);
    this.greetingCanvas.height = Math.round(150 * dpr);
    this.greetingCanvas.style.width = `${EXPANDED_W}px`;
    this.greetingCanvas.style.height = "150px";

    // A sibling of the island rather than a child of it: the island clips its
    // own content and these sit outside it. They take their place from the
    // island's animated size, so one spring moves the shape and the ring
    // together — which is what makes them read as one object instead of two
    // that happen to agree.
    this.ringEl = h("div", { id: "edge-ring" });
    this.root.append(this.wakeStrip, this.ringEl, this.islandEl);
    // Before the first paint: boot() has not answered yet, so this is the
    // default until applySettings() says otherwise a moment later.
    this.applyPosition(this.position);
  }

  // ── FSM ─────────────────────────────────────────────────────────────────────

  private wireFsm() {
    this.fsm.notificationHoldDelay = State.settings.autoCloseInterval;
    this.fsm.onTransition = (from, to) => {
      switch (to) {
        case "hidden":
          this.setMode("hidden");
          break;
        case "petit":
          if (from === "coucou") this.greeting.interrupt();
          else if (from === "hidden") Sound.play("peek");
          this.setMode("compact");
          if (from === "coucou") State.view = State.defaultView();
          // `fsm.pointerInside`, never `wasInIsland`: this runs synchronously
          // inside the transition, and `wasInIsland` is only updated at the end
          // of the poll tick — so during a hover-open it still reads false and
          // this would schedule a collapse under a pointer that never moved.
          if (!this.fsm.pointerInside) this.fsm.mouseLeft();
          // A card that waited for the greeting. It goes out after the canvas
          // has folded — delivered any sooner it would be fighting the collapse
          // animation for the same island.
          if (from === "coucou" && this.pendingAlertView != null) {
            const pending = this.pendingAlertView;
            this.pendingAlertView = null;
            window.setTimeout(() => this.alert(pending), GREETING_COLLAPSE_MS);
          }
          break;
        case "home":
          // No leave-collapse here. An island opened with nobody on it folds
          // away on the hold `forceHome()` armed, which is the whole point of
          // the hold; scheduling the 0.12 s grace as well closed it instantly.
          this.expand(this.restingView());
          break;
        case "coucou":
          // In season, the Christmas music starts with the hello — with or
          // without a character to say it. Once per run, and only with its
          // setting on; the player checks both.
          ChristmasMusic.startWithGreeting();
          // The greeting is nothing but Mochi saying hello, so with the
          // characters off there is no hello to play. Report it finished
          // instead of expanding onto an empty island: the machine then folds
          // to `petit` on its own timer, exactly as it would have once the
          // animation ended.
          if (State.settings.hideCharacters) {
            this.fsm.greetComplete();
          } else {
            this.expand("greeting");
            this.greeting.start(this.greetingLine());
          }
          break;
      }
      State.notify();
    };
  }

  /**
   * "Good afternoon, Ana!" — the line under Mochi as it says hello, in the
   * island's language. The name typed under Your name, or else the account's
   * first name, or else no name at all; the hour decides the rest.
   */
  private greetingLine(): string {
    const name = greetingName(State.settings.userName, State.accountName);
    const keys = GREETING_KEYS[dayPeriod(new Date().getHours())];
    return name ? t(keys.named, name) : t(keys.bare);
  }

  /**
   * Everything the island listens to once it is running, without the hello.
   *
   * Once per run. `launch()` comes back through here every time the greeting
   * plays — after the welcome, and again after "Show the welcome again…" —
   * and the store and the timer would otherwise call it twice, then three
   * times. On its own while the welcome is up, so the island is alive
   * underneath it even though it has not said hello yet.
   */
  start() {
    if (this.started) return;
    this.started = true;
    // A focus or break ran out: open on the timer so the end is visible, not
    // just audible. `alert` gives it the same hold every notification gets.
    FocusTimer.onFinished = () => this.alert("timer");
    // Starting, pausing or stopping repaints at once rather than waiting for
    // the next half-second tick.
    FocusTimer.subscribe(() => {
      this.dirty = true;
      this.ensureRunning();
    });
    // A glass logged, the day turned, a reminder came due: repaint, and let
    // Mochi answer a glass the way he answers a file — happy for an ordinary
    // one, proud for the one that reaches the goal, for as long as the
    // celebration runs. Compared against what was last seen rather than taken
    // from the store as events, because the store only says "something changed".
    let pulse = Hydration.pulse;
    let celebrating = Hydration.celebrating;
    Hydration.subscribe(() => {
      if (Hydration.celebrating && !celebrating) this.emote("proud", 2.6);
      else if (Hydration.pulse !== pulse && !Hydration.celebrating) this.emote("happy");
      pulse = Hydration.pulse;
      celebrating = Hydration.celebrating;
      this.dirty = true;
      this.ensureRunning();
    });
  }

  /** Starts the island if it has not been yet, and plays the launch greeting. */
  launch() {
    this.start();
    this.fsm.launch();
  }

  /**
   * Where the island opens when nothing asked for a view: the reminder, while
   * one is still waiting for an answer, and otherwise what it always was. An
   * approval or a question never comes through here — those pin the island on
   * their own card — so water only ever takes the place of Home.
   */
  private restingView(): IslandViewName {
    return Hydration.enabled && Hydration.awaiting ? "sip" : State.defaultView();
  }

  // ── Mode / view ─────────────────────────────────────────────────────────────

  private setMode(mode: IslandMode) {
    const prev = State.mode;
    if (mode === prev) return;
    State.mode = mode;
    // Nothing keeps a page behind a folded island. Every screen, not only the
    // site: a folded island still saying `webchat` would go on holding itself
    // open while showing nothing at all. Before anything is animated, so the
    // island shrinks once rather than twice.
    if (modeOrder(mode) < modeOrder(prev) && isScreen(State.view)) {
      State.view = State.defaultView();
    }
    this.syncSnow();
    if (mode === "expanded") Sound.play("open");
    if (prev === "expanded") {
      Sound.play("close");
      State.isPinned = false;
      void Bridge.focusWindow(false);
      // The pages lie over the island's cards, so they go before it starts to
      // fold. Here rather than in `collapse()` because this covers every route
      // out of expanded.
      this.pages.hideAll();
      // "Logged", "back in 30 min": said, and over once the card has folded.
      Hydration.clearPrompt();
    }
    this.screenChanged();
    if (mode !== "expanded") {
      // The island went, so the click that opened it is spent. The ring only
      // exists while the island is open, which is what bounds the memory now
      // that no clock does: the next click on that pill is a first click.
      this.lastPillClick = null;
      this.engine.resetMorph();
      // Nothing can be seen of the sequence once the island is shut, and leaving
      // it running would keep the frame loop awake — the island must cost
      // nothing while hidden.
      UploadSeq.deactivate();
    }
    this.updateWindowCollapsed();
    this.animateGeometry(modeOrder(mode) < modeOrder(prev));
    State.notify();
  }

  /** True while the drop sequence owns the island body. */
  private get uploadActive(): boolean {
    return State.mode === "expanded" && UploadSeq.isActive && UPLOAD_VIEWS.has(State.view);
  }

  /**
   * The characters are off, and this is one of the places that loses one.
   *
   * Two keep theirs and so are excluded here: the drop, where Mochi *is* the
   * progress, and the compact bar, where he is the only thing on it.
   */
  private get charactersOff(): boolean {
    return State.settings.hideCharacters
      && State.mode === "expanded"
      && !UPLOAD_VIEWS.has(State.view);
  }

  /** Navigating out of the drop flow ends the sequence, as on macOS. */
  private stopSequenceIfLeaving(view: IslandViewName) {
    if (UploadSeq.isActive && !UPLOAD_VIEWS.has(view)) UploadSeq.deactivate();
  }

  expand(view: IslandViewName) {
    this.stopSequenceIfLeaving(view);
    State.view = view;
    if (State.mode !== "expanded") this.setMode("expanded");
    else this.animateGeometry(false);
    this.screenChanged();
    State.lastActivity = performance.now();
    this.homeCollapseAt = null;
    State.notify();
  }

  setView(view: IslandViewName) {
    this.stopSequenceIfLeaving(view);
    if (State.mode !== "expanded") {
      this.fsm.forceHome();
      State.view = view;
      this.screenChanged();
      this.animateGeometry(false);
      State.notify();
      return;
    }
    // A tab pressed again keeps its view. A screen in particular: going round
    // the motion again would take the page off it and put it back.
    if (view === State.view && isScreen(view)) return;
    // Through `targetSize` rather than the table, because a message card is
    // not its table height: a long one shrinking back to the overview would
    // otherwise animate as though it were growing.
    const before = this.targetSize().h;
    State.view = view;
    // Before the motion starts, so a page leaving is off the card before the
    // card moves.
    this.screenChanged();
    State.lastActivity = performance.now();
    this.animateGeometry(this.targetSize().h < before);
    State.notify();
  }

  /**
   * True while what is on the island is a screen rather than a card —
   * `AppState.viewHoldsIslandOpen`.
   *
   * A card is something that happened: it arrives, it is read, it folds away
   * on its own. A screen is somewhere the user went, so nothing but the user
   * may take it away — no timer, no pointer leaving, no alert landing on it.
   * `closeScreen()` is the way out. Only while the island is open: a view left
   * behind by a fold must not hold a closed island.
   */
  get viewHoldsIslandOpen(): boolean {
    return State.mode === "expanded" && isScreen(State.view);
  }

  /** Everything that can hold the island open — `fsm.isHeldOpen` on the Mac. */
  private holdsOpen(): boolean {
    // Staged files and an open picker hold the card for the same reason a
    // half-written sentence does. The picker is the sharper case: it takes
    // focus, so the field lets go the instant it opens, and without the other
    // two the card would fold away behind it. Recording belongs here for the
    // picker's reason exactly: the microphone is a click, not a focus, so
    // nothing else holds the card while someone talks into it. Listening to a
    // voice message, for the same reason: a click, not a focus, and the card
    // folding would cut it off. And a screen, which is somewhere the user went.
    return this.fieldHeld || State.pickingFile
      || State.replyAttachments.length > 0
      || State.recordingSince !== null
      || VoicePlayer.busy()
      || this.viewHoldsIslandOpen;
  }

  /**
   * The island is open on a view that has the keyboard while it is up: the
   * chat, whose field takes it as it appears, or a screen, whose page does.
   * A field let go on the way to one of these hands nothing back — the Mac's
   * panel stays key from a card to the chat, ChatGPT or the site, and only
   * a fold or Escape resigns it (`collapse`, the Escape monitor). Handing it
   * back here would send it to the app the user came from and have the page
   * take it straight back, or, for the site, give it away with the island
   * still in use.
   */
  private get viewKeepsKeyboard(): boolean {
    return State.mode === "expanded" && (State.view === "prompt" || isScreen(State.view));
  }

  /**
   * The reply field let go of the caret: the keyboard goes back to where the
   * user was, unless the island has somewhere else to keep it.
   *
   * Not at once. A press elsewhere in the island takes the caret on its way
   * down, before the click has done anything — a tab above all, since
   * Chromium focuses a button as it is pressed — so this waits for the press
   * to be over and the click to have run, and then asks what it left: a view
   * that keeps the keyboard, or a field with the caret again, keeps it.
   *
   * A field with the caret in a document that has the keyboard, that is. The
   * window losing the keyboard — Alt+Tab, a click in another app — blurs the
   * field and leaves it the active element all the same, and nothing is typed
   * into it then. Kept, the island stayed a window a click activates: the
   * next click on any of its controls took the keyboard from the app the user
   * went to, and Chromium put the caret back in the field, pinning its card.
   */
  private letFieldGo() {
    this.afterPress(() => {
      if (this.viewKeepsKeyboard) return;
      const focused = document.activeElement;
      if (document.hasFocus()
          && (focused instanceof HTMLInputElement || focused instanceof HTMLTextAreaElement)
          && this.viewsEl.contains(focused)) return;
      void Bridge.focusWindow(false);
    });
  }

  /** `then` once no press is down in this window — now, if none is. */
  private afterPress(then: () => void) {
    if (this.pressing) this.afterPressQueue.push(then);
    else then();
  }

  /**
   * The caret goes with the view it was in, whatever comes next.
   *
   * A view that is not on is only transparent, so a field in one keeps the
   * caret, and the island keeps the keyboard from card to card: what is typed
   * on the view that replaced it went into a field nobody could see — Enter
   * sending its draft, Escape, which the chat and the reply field keep to
   * themselves, never reaching the island. A click on a tab has taken the
   * caret already, on its way down; a card put up over a field — an approval,
   * a timer running out — has not. On the Mac the field goes with its view.
   *
   * The reply field lets go as it always does when it loses the caret, of its
   * hold and of the keyboard, except that the card in its place keeps its own
   * terms (`fieldLeftWithView`).
   */
  private dropCaret(view: IslandViewName) {
    const focused = document.activeElement;
    if (!(focused instanceof HTMLElement) || !this.views.get(view)?.el.contains(focused)) return;
    this.fieldLeftWithView = true;
    try {
      focused.blur();
    } finally {
      this.fieldLeftWithView = false;
    }
  }

  /**
   * The view or the mode changed: the page goes with a screen that is leaving,
   * and a screen coming on holds the island open from now on.
   */
  private screenChanged() {
    this.screenView = State.view;
    this.pages.sync(State.mode === "expanded" ? pageForView(State.view) : null);
    this.fsm.heldOpen = this.holdsOpen();
    if (this.viewHoldsIslandOpen) {
      // Whatever was counting down — a notification's hold, the pointer's
      // leave — is not the user asking to leave.
      this.fsm.cancelTimers();
      this.homeCollapseAt = null;
    }
  }

  /**
   * Puts the screen on the island away — the site, ChatGPT. `collapse()` cannot:
   * a screen holds the island open, which is exactly what that refuses to
   * override.
   *
   * Back to the resting bar, from where it folds on the same terms as any other
   * view. Unless something is waiting to be answered: an approval that arrived
   * while the page had the island was deliberately not shown then, and folding
   * now would bury it, so its card takes the screen's place instead.
   */
  closeScreen() {
    if (State.mode !== "expanded" || !isScreen(State.view)) return;
    this.pages.hideAll();
    if (State.pendingApproval) {
      this.fsm.pinned = State.isPinned;
      this.expand("approval");
      return;
    }
    this.fsm.forcePetit();
    // The machine was not where it thought it was; the island still folds.
    if (State.mode === "expanded") this.setMode("compact");
  }

  /**
   * The header's X and the close shortcut: the user asked for the island to go,
   * now. A screen goes the way its own X takes it.
   */
  dismiss() {
    if (State.mode !== "expanded") return;
    if (this.viewHoldsIslandOpen) {
      this.closeScreen();
      return;
    }
    this.collapse();
  }

  /**
   * `NOTCHY_SMOKE_VIEW` in a debug build: open a view the way its own control
   * would — ChatGPT as its tab does, the site as its tab and its disc do.
   * ChatGPT whatever the chat tab is set to: the run is there to look at it.
   */
  openForSmoke(name: string) {
    const view = name === "site" ? "web" : name;
    if (!(view in VIEW_LAYOUTS)) return;
    void Bridge.log(`smoke: opening ${view}`);
    // Nothing can be pressed while the greeting plays, so it waits for the
    // greeting the way a card does, and opens once the island has settled.
    if (this.fsm.state === "coucou") {
      this.alert(view as IslandViewName);
      return;
    }
    this.setView(view as IslandViewName);
  }

  collapse() {
    // Whatever list was open is finished with. Without this, the next message
    // to arrive would be answered back into a stale one.
    State.closeMessageList();
    State.isPinned = false;
    this.fsm.pinned = false;
    // Drive the state machine rather than the mode: setting the mode behind its
    // back left it thinking the island was still open, and a click on the compact
    // island then did nothing — the island could never be reopened.
    this.fsm.forcePetit();
  }

  /**
   * Alert from the hook server: open on this view and hold it open for the
   * auto-close interval, then fold away on its own. Pinned alerts — one waiting
   * on an answer — never auto-close.
   *
   * Safe to call again while one is already up: `notify()` replaces the running
   * hold rather than adding a second one.
   */
  alert(view: IslandViewName) {
    // Never over a screen. A card arriving there replaced the page somebody
    // was working in, and then folded the island on its own hold. Nothing is
    // lost by waiting: the callers have already played the sound, the pill
    // carries the badge, and a pending approval is what `closeScreen()` hands
    // over on the way out.
    if (this.viewHoldsIslandOpen) return;
    // The greeting plays to the end. A card arriving mid-animation used to
    // replace it on the spot — `expand()` below swaps the island's view out
    // from under it — so it waits for the island to settle instead. The
    // `coucou` → `petit` arm of `wireFsm` delivers it.
    if (this.fsm.state === "coucou") {
      this.pendingAlertView = view;
      return;
    }
    this.fsm.pinned = State.isPinned;
    // The user's setting, read fresh: a card is held for as long as the field
    // in Settings says, not for whatever the machine was last told.
    this.fsm.notificationHoldDelay = State.settings.autoCloseInterval;
    this.fsm.forceHome();
    this.expand(view);
    // expand() clears the countdown; re-arm it to mirror the FSM's hold.
    if (this.fsm.holdRunning) {
      this.homeCollapseAt = performance.now() + this.fsm.holdDurationMs;
    }
  }

  reveal() {
    this.fsm.reveal();
  }

  /** An alert stopped waiting for an answer: let the island auto-close again. */
  dropPin() {
    this.fsm.pinned = false;
  }

  // ── File drop ───────────────────────────────────────────────────────────────

  private onDragDrop(e: { type: string; paths?: string[] }) {
    if (e.type !== "over") void Bridge.log(`drag ${e.type} ${e.paths?.length ?? 0} file(s)`);
    if (State.paused) return;
    // Over a screen the island's own drop stands down, as the Mac's drop view
    // does for ChatGPT: a file let go on the page is the page's to take, and
    // one let go on the row above it has nowhere to go — the bin would be a
    // card, and no card replaces a screen. A leave still tidies up after a
    // drag that started before the screen came up.
    if (this.viewHoldsIslandOpen && e.type !== "leave") return;
    switch (e.type) {
      case "enter":
      case "over": {
        // A reply box that can take the file catches it instead: no bin morph,
        // no view switch, because the card being written in must stay put.
        if (ReplyAttachments.replyIsCatching()) {
          if (State.replyDragOver) return;
          State.replyDragOver = true;
          State.notify();
          return;
        }
        if (State.fileDragOver) return;
        State.fileDragOver = true;
        this.engine.animateMorph(1);
        // enterZone must run before the island expands, so the sequence is
        // already active by the time the view becomes `upload`.
        UploadSeq.enterZone(State.mouseInIsland.x, State.mouseInIsland.y);
        this.alert("upload");
        break;
      }
      case "leave": {
        if (State.replyDragOver) {
          State.replyDragOver = false;
          State.notify();
          return;
        }
        if (!State.fileDragOver) return;
        State.fileDragOver = false;
        this.engine.animateMorph(0);
        // The island deliberately stays open: the drag session is still alive.
        UploadSeq.exitZone();
        State.notify();
        break;
      }
      case "drop": {
        const paths = e.paths ?? [];
        if (State.replyDragOver || ReplyAttachments.replyIsCatching()) {
          State.replyDragOver = false;
          State.fileDragOver = false;
          void ReplyAttachments.attachPaths(paths);
          State.notify();
          return;
        }
        State.fileDragOver = false;
        const path = paths[0];
        if (!path) {
          this.engine.animateMorph(0);
          this.setView(State.defaultView());
          return;
        }
        // All of them are copied and counted; the flow still asks its question
        // about the first, the way the Mac does.
        this.swallow(path, paths);
        break;
      }
    }
  }

  /**
   * Mochi eats the file. Nothing here waits on the file system: the copy into
   * the inbox runs in the background and swaps the path in when it lands, so a
   * slow disk can never stall the animation — same as FileDropHandler on macOS.
   */
  private swallow(path: string, all: string[] = [path]) {
    const name = path.split(/[\\/]/).pop() || "file";
    State.droppedFile = { name, path };
    // `droppedFile` stays the first of them, because everything downstream —
    // the prompt's context pill, the canvas icon — asks one question about one
    // file. What the extra files change is the label and what lands in the
    // inbox, which is what SPEC.md §Files means by "3 fichiers".
    State.droppedFiles = all.map((p) => ({
      name: p.split(/[\\/]/).pop() || "file",
      path: p,
    }));
    State.promptContext = { kind: "file", name, path };
    State.chatHistory = [];
    void Bridge.chatReset();

    UploadSeq.performDrop(State.uploadDuration);
    this.uploadTens = 0;
    this.uploadDone = false;

    this.engine.gulp();
    Sound.play("approve");
    this.emote("happy");
    this.engine.animateMorph(0);

    State.uploadProgress = 0;
    this.setView("uploading");
    this.ensureRunning();

    void Promise.all(all.map((p) => Bridge.ingestFile(p)))
      .then((files) => {
        const first = files[0]!;
        State.droppedFile = { name: first.name, path: first.path };
        State.droppedFiles = files.map((f) => ({ name: f.name, path: f.path }));
        State.promptContext = { kind: "file", name: first.name, path: first.path };
        State.notify();
      })
      .catch((err) => {
        UploadSeq.deactivate();
        State.noteMessage = String(err).replace(/^Error:\s*/, "");
        this.engine.animateMorph(0);
        Sound.play("error");
        // A screen the user went to while the file was being copied stays: no
        // card replaces one. The sound has said it, as it does for an alert.
        if (this.viewHoldsIslandOpen) return;
        this.setView("note");
        // Its own note, still on screen. Anything the user has moved to since
        // — a tab, a screen, a folded island — is theirs, and a fold left
        // alone: `setView` on a closed island opens it.
        window.setTimeout(() => {
          if (State.mode === "expanded" && State.view === "note") this.setView(State.defaultView());
        }, 2400);
      });
  }

  /**
   * Sounds and view changes hung off the canvas timeline: a `tick` every 10 %,
   * the ✓ chime when the bar completes, then `choose` once Mochi has grown back.
   */
  private stepSequence() {
    const since = UploadSeq.sinceDrop();
    if (since == null) return;
    const dur = State.uploadDuration;
    const p = Math.max(0, Math.min(1, (since - PRE_PROGRESS) / dur));

    const tens = Math.floor(p * 10);
    if (tens > this.uploadTens && tens < 10) {
      this.uploadTens = tens;
      Sound.play("tick");
    }

    if (!this.uploadDone && since >= PRE_PROGRESS + dur) {
      this.uploadDone = true;
      Sound.play("approve");
      this.emote("happy");
    }
    // The extra second is the grow-back, after which the choose card is up.
    if (since >= PRE_PROGRESS + dur + 1 && State.view === "uploading") {
      this.setView("choose");
    }
  }

  // ── Geometry ────────────────────────────────────────────────────────────────

  /** The mode the island draws as — see `drawModeFor` in core/fold.ts. */
  private drawMode(): IslandMode {
    return drawModeFor(State.mode, this.anchorGeom.hug);
  }

  /**
   * The window this island wants — see `foldFor` in core/fold.ts.
   *
   * Wants, not has. Rust is only asked once the island has finished settling,
   * and then takes an IPC round trip to do it; `windowIsBar` is what the window
   * actually is by the time anything is drawn.
   */
  private fold(): Fold {
    return foldFor(
      State.mode,
      State.settings.alwaysVisible,
      this.anchorGeom.hug,
      this.anchorGeom.free != null,
    );
  }

  /**
   * Where the island is drawn inside the window — see `islandOrigin`.
   *
   * `windowIsBar` rather than `fold()`, so this follows the window the island
   * is in and not the one it has asked for: through a shrink it goes on using
   * the panel's offsets, which is the only pair that is right while the panel
   * is still up.
   */
  private origin(w: number, h: number): { x: number; y: number } {
    return islandOrigin(this.anchorGeom, this.windowIsBar, w, h);
  }

  private targetSize(): { w: number; h: number; r: number } {
    const { w, h } = islandSize(this.drawMode(), State.view, State.chatHistory.length,
                                State.settings.homeContent,
                                State.replyAttachments.length, State.replyNotice != null,
                                State.homeShowsPlayer, this.bodyOverflow());
    const r = State.mode === "expanded" ? EXPANDED_CORNER : ROUNDED_CORNER;
    return { w, h, r };
  }

  /** The work area a dropped point is a fraction of, as Rust last reported it. */
  setScreen(info: { workWidth: number; workHeight: number }) {
    this.area = { w: info.workWidth, h: info.workHeight };
    // Re-resolve: the same fraction on a different work area is a different
    // pixel, which is the whole point of keeping it as a fraction.
    this.applyPosition(this.position);
    // Another display can mean another scale, and a page is placed in pixels.
    this.pages.refresh();
  }

  /**
   * Aims every animated dimension at the current target. Called again whenever
   * the target changes, mid-flight included: `Tracked` carries position and
   * velocity across the switch, so a close interrupted by the pointer coming
   * back turns around instead of finishing and replaying.
   */
  private animateGeometry(shrinking: boolean) {
    const { w, h, r } = this.targetSize();
    const now = performance.now();
    if (shrinking) {
      this.width.curveTowards(w, CLOSE_MS, now);
      this.height.curveTowards(h, CLOSE_MS, now);
      this.radius.curveTowards(r, CLOSE_MS, now);
    } else {
      this.width.springTo(w, OPEN_RESPONSE, OPEN_DAMPING, now);
      this.height.springTo(h, OPEN_RESPONSE, OPEN_DAMPING, now);
      this.radius.springTo(r, OPEN_RESPONSE, OPEN_DAMPING, now);
    }
    this.ensureRunning();
  }

  private applyGeometry() {
    const rect = this.islandRect();
    const { w, h: hh } = rect;
    const r = this.radius.value;
    this.islandEl.style.width = `${w}px`;
    this.islandEl.style.height = `${hh}px`;
    // Written here rather than in the stylesheet because an inline style set
    // every frame would win over any CSS rule anyway. At the bottom, rewriting
    // `top` as the height animates is what makes the island grow up out of the
    // edge and retract back into it.
    this.islandEl.style.left = `${rect.x}px`;
    this.islandEl.style.top = `${rect.y}px`;
    this.islandEl.style.transform = "none";
    this.islandEl.style.borderRadius = radiusCss(this.anchorGeom, r);
    this.snow.resize(w, hh);
    // These follow the island as it resizes, so they belong here rather than in
    // the state-driven DOM sync.
    this.miniGrid.style.left = `${w - 40 - 14.5}px`;
    this.miniGrid.style.top = `${hh / 2 - 14.5}px`;
    this.compactTimer.style.left = `${w - 62}px`;
    this.compactTimer.style.top = `${hh / 2 - 7}px`;
    // The glass is 12 × 14.4 and takes the mini grid's seat: its centre 40 px
    // in from the right, where Mochi's is 40 px in from the left.
    this.compactSip.el.style.left = `${w - 40 - 6}px`;
    this.compactSip.el.style.top = `${hh / 2 - 7.2}px`;
    this.greetingCanvas.style.left = `${(w - EXPANDED_W) / 2}px`;
    this.uploadCanvas.el.style.left = `${(w - EXPANDED_W) / 2}px`;
    // The ring hangs off the island's edge, so it moves with it rather than
    // with the state that decides what is on it.
    this.syncRing();

    const want = this.targetRect();
    const p = this.pushedRect;
    // `y` belongs in this comparison: moving the island to another edge changes
    // it without touching the size, and Rust would keep hit-testing the old spot.
    if (
      Math.abs(p.x - want.x) > 0.5 ||
      Math.abs(p.y - want.y) > 0.5 ||
      Math.abs(p.w - want.w) > 0.5 ||
      Math.abs(p.h - want.h) > 0.5
    ) {
      this.pushedRect = want;
      void Bridge.setIslandRect(want.x, want.y, want.w, want.h);
    }
  }

  /**
   * Focuses a pill and opens what it stands for — the island's pills and the
   * ring's discs are the same click.
   */
  private openPill(id: string) {
    State.setFocus(id);
    // A click opens the island; clicking the same pill again, while the island
    // it opened is still up, also opens the service behind it. Read before the
    // memory is updated, and the island half runs either way, so two clicks
    // are "the island, then the service". The pointer goes into the memory
    // with it, for the second click that misses the button because opening a
    // view moved the ring out from under it.
    const second = opensTarget(id, this.lastPillClick);
    this.lastPillClick = second ? null : { pill: id, pointer: { ...this.pointer } };

    // The message pills exist to be answered, so they open everything still
    // waiting rather than a card about a socket. Notifications stands for both
    // services at once, so it opens the one queue instead of picking a service
    // to be first.
    if (id === NOTIFICATIONS_PILL) {
      State.openAllMessageLists();
      this.setView("messages");
      return;
    }
    const source = sourceForPill(id);
    if (source) {
      State.openMessageList(source);
      this.setView("messages");
      if (second) this.openPillTarget(id);
      return;
    }
    // Every other pill lands on Home with itself in focus, which for Now
    // Playing is the player. The Mac has done this since the pill was
    // unreachable any other way.
    this.setView("overview");
    if (second) this.openPillTarget(id);
  }

  /** The pill clicked last and where — the memory `opensTarget` reads. */
  private lastPillClick: PillClick | null = null;

  /** Where the pointer was when it last went down, in screen coordinates. */
  private pointer = { x: 0, y: 0 };
  /** A press inside this window has gone down and not yet come up. */
  private pressing = false;
  /** What waits for that press to be over — `afterPress`. */
  private afterPressQueue: (() => void)[] = [];

  /**
   * Every click, before the thing under it gets a say.
   *
   * Two jobs: remember where the pointer is, so a pill click can record it,
   * and catch the second click of a pair that missed its button because
   * opening a view resized the island and the ring moved with it. A pointer
   * that has not moved since the first click is what makes it the same pair —
   * `clickCount` would be asking for a double click at the system's pace all
   * over again, which is the thing that made this unreliable. And a third:
   * knowing whether a press is still down, which `letFieldGo` waits out.
   */
  private watchPointer() {
    // Whether a press is still down, for `afterPress`. Over when it comes up,
    // is cancelled, or the window loses the focus under it — a press that
    // ends somewhere this window never hears about.
    const released = () => {
      this.pressing = false;
      const waiting = this.afterPressQueue.splice(0);
      // The click a release makes is dispatched in the same task as the
      // release itself, so a timer started here runs once that click's
      // handler has.
      if (waiting.length > 0) window.setTimeout(() => { for (const then of waiting) then(); }, 0);
    };
    window.addEventListener("pointerup", released, true);
    window.addEventListener("pointercancel", released, true);
    window.addEventListener("blur", released);
    window.addEventListener(
      "pointerdown",
      (e) => {
        this.pressing = true;
        this.pointer = { x: e.screenX, y: e.screenY };
        const last = this.lastPillClick;
        if (last && opensTargetAt(this.pointer, last)) {
          // Cleared first, so the button's own handler cannot open the same
          // thing again off the same pair of clicks.
          this.lastPillClick = null;
          this.openPillTarget(last.pill);
        }
      },
      true,
    );
  }

  /**
   * The app or page behind a pill — the second click, and the ↗ button.
   *
   * Port of `openPillTarget` in PillActions.swift. The message services are
   * resolved in Rust, which is where their address is kept.
   */
  private openPillTarget(id: string) {
    if (id === ALWAYS_LOADED_PILL) {
      void Bridge.openInVSCode(State.focusTask?.sessionCwd ?? null);
      return;
    }
    const source = sourceForPill(id);
    if (source) void Bridge.openMessageService(source);
  }

  /** Where the island is, which is what decides where a side can be. */
  private anchor(): IslandAnchor {
    return this.anchorGeom;
  }

  /**
   * Rebuilds the ring when what it holds changes, and places it every time the
   * island moves or resizes.
   *
   * Cheap to call: the key is what the buttons are, so an animating island
   * re-places the discs it already has rather than making them again.
   */
  private syncRing() {
    const buttons = ringVisible(ringDrawn(State.edgeButtons, State.settings.agendaEnabled), State.mode === "expanded");
    // The site's disc is named after its address, so that is part of what the
    // ring is built from.
    const key = buttons.map((b) => `${b.side}:${b.action}`).join("|")
      + (buttons.some((b) => b.action === "site") ? `|${State.settings.siteUrl}` : "");
    if (key !== this.ringKey) {
      this.ringKey = key;
      clear(this.ringEl);
      this.ring = buttons.map((button) => {
        const el = this.buildRingButton(button);
        this.ringEl.append(el);
        return { el, button };
      });
      // Just behind the shape, so the ring unfurls from the island rather than
      // arriving with it.
      requestAnimationFrame(() => {
        for (const { el } of this.ring) el.classList.add("on");
      });
    }
    this.placeRing();
  }

  private placeRing() {
    if (this.ring.length === 0) return;
    const rect = this.islandRect();
    const placed = ringLayout(this.ring.map((b) => b.button), this.anchor(), rect.w, rect.h);
    for (const { button, x, y } of placed) {
      const slot = this.ring.find((b) => b.button === button);
      if (!slot) continue;
      slot.el.style.left = `${rect.x + x - RING_D / 2}px`;
      slot.el.style.top = `${rect.y + y - RING_D / 2}px`;
    }
  }

  /** One disc: a pill's colour and its mark on the island's own black. */
  private buildRingButton(button: EdgeButton): HTMLElement {
    const task = State.tasks.find((t) => t.id === button.action)
      ?? INTEGRATION_AGENTS.find((t) => t.id === button.action);
    const built = edgeAction(button.action);
    const tint = task?.color ?? built?.color ?? "#8E939C";
    const label = t(task?.name ?? built?.title ?? button.action);

    // A drawn mark keeps its own colours and gets the Mac's 16 px; a symbol is
    // tinted by the disc and sits a hair smaller, the way it does there.
    //
    // The site draws its own mark, sized against the whole disc as the Mac's
    // is — the rings reach under half the tile they were measured on, so the
    // disc is the tile — in the disc's tint. It is named by where it goes.
    const logo = PILL_LOGOS[button.action];
    const site = button.action === "site" && !task;
    const mark = site
      ? siteGlyph(RING_D)
      : logo
        ? logo(16)
        : svg(RING_MARKS[button.action] ?? ICONS.ellipsis, 15);
    // As wide as the disc, so wider than the room inside its border: it must
    // not be shrunk to fit, or the mark comes out 6 % small.
    if (site) mark.style.flex = "none";

    const el = h("button", {
      class: "ring-btn",
      title: site ? siteHost(State.settings.siteUrl) : label,
      onclick: () => this.pressRingButton(button.action),
    }, mark);
    el.style.setProperty("--tint", tint);
    el.style.width = `${RING_D}px`;
    el.style.height = `${RING_D}px`;
    return el;
  }

  private pressRingButton(action: string) {
    // The built-ins are silent, as IslandEdgeAction.perform() is on the Mac;
    // only a pill blips, the way its openPill does.
    //
    // The site opens as a notification would — `hookExpand` on the Mac — so it
    // waits out the greeting, and does nothing over a screen that is already
    // up: one screen at a time, and only the user takes one away.
    if (action === "site") {
      this.alert("web");
      return;
    }
    switch (action) {
      case "clipboard":
        void Bridge.toggleClipboardWindow();
        return;
      case "timer":
        this.setView("timer");
        return;
      case "settings":
        // The ring's gear opens on Dynamic Island, where the ring is set up.
        void Bridge.openSettingsWindow("island");
        return;
      case "hydration":
        // What the header tab did: opening it by hand ends whatever the
        // reminder card had moved on to say.
        Hydration.clearPrompt();
        this.setView("hydration");
        return;
      case "agenda":
        this.setView("agenda");
        return;
      default:
        // A pill: the same thing clicking it in the island does, so the
        // message pills open what is waiting rather than a card about a socket.
        Sound.play("blip");
        this.openPill(action);
    }
  }

  /**
   * Island rect in window coordinates (origin top-left of the 720×320 window),
   * as currently drawn — the animated size, mid-flight included.
   */
  private islandRect(): { x: number; y: number; w: number; h: number } {
    const w = this.width.value;
    const hh = this.height.value;
    return { ...this.origin(w, hh), w, h: hh };
  }

  /** What the last body measurement was for, so a card does not re-wrap a
   *  paragraph on every frame of its own spring. */
  private bodyOverflowMemo: { key: string; value: number } | null = null;

  /**
   * How much taller than its two reserved lines the message on screen needs
   * the card to be — the twin of `AppState.messageBodyOverflow`.
   *
   * Zero with the preference off, which is what keeps the geometry identical
   * to the card that ships. Every consumer of `islandSize` is handed the same
   * number: the window rect and Mochi's placement are worked out separately,
   * and they have to agree or he floats outside the card.
   */
  private bodyOverflow(): number {
    const full = State.settings.messageFullBody;
    const message = State.view === "message"
      ? State.activeMessage
      : State.view === "overview" ? State.homeMessage : null;
    const hidden = State.settings.hideCharacters;
    const voice = message?.audio != null;
    // The body is in the key because a voice message keeps its id while its
    // transcript arrives and grows it.
    const key = `${message?.id ?? "-"}|${message?.body.length ?? 0}|${voice}|${full}|${hidden}`;
    if (this.bodyOverflowMemo?.key === key) return this.bodyOverflowMemo.value;
    let value: number;
    if (voice) {
      // The player always takes its own row above the two lines; the
      // transcript scrolls in those, and grows past them only when the
      // preference lets the card grow.
      const words = full && message?.body
        ? Math.max(MESSAGE_BODY_TWO_LINES,
                   measureBodyHeight(message.body, messageBodyWidth(hidden) - VOICE_SCROLLER_ROOM))
        : MESSAGE_BODY_TWO_LINES;
      value = VOICE_PLAYER_HEIGHT + VOICE_GAP + words - MESSAGE_BODY_TWO_LINES;
    } else {
      const body = full ? message?.body : null;
      const tall = body ? measureBodyHeight(body, messageBodyWidth(hidden)) : 0;
      value = Math.max(0, tall - MESSAGE_BODY_TWO_LINES);
    }
    this.bodyOverflowMemo = { key, value };
    return value;
  }

  /**
   * Where the island is headed for the current mode and view.
   *
   * Everything that asks "is the pointer on the island?" uses this rather than
   * the animated rect, so the answer changes when the mode changes and not
   * sixty times on the way there. It is also what Rust hit-tests for
   * click-through, so the window takes the mouse over the whole island from the
   * first frame of the open instead of chasing it.
   */
  private targetRect(): { x: number; y: number; w: number; h: number } {
    const { w, h } = islandSize(this.drawMode(), State.view, State.chatHistory.length,
                                State.settings.homeContent,
                                State.replyAttachments.length, State.replyNotice != null,
                                State.homeShowsPlayer, this.bodyOverflow());
    const { x, y } = this.origin(w, h);
    // The ring is part of the island as far as the mouse is concerned: a disc
    // outside this rect would be drawn over a window that lets clicks through,
    // and leaving the island to reach one would fold it away mid-reach.
    const chrome = chromeBounds(
      ringVisible(ringDrawn(State.edgeButtons, State.settings.agendaEnabled), State.mode === "expanded"), this.anchor(), w, h,
    );
    return { x: x + chrome.x, y: y + chrome.y, w: chrome.w, h: chrome.h };
  }

  /**
   * The wake strip sits where the island will appear. While the window is
   * collapsed it *is* the window, so it fills the viewport; while the window is
   * the full panel it is the only thing near the cursor in the frames between
   * `setCollapsed(false)` and the island animating open.
   */
  private positionWakeStrip() {
    const st = this.wakeStrip.style;
    if (this.collapsed) {
      st.inset = "0";
      st.width = "";
      st.height = "";
      return;
    }
    st.inset = "";
    st.width = `${WAKE_STRIP_W}px`;
    st.height = `${WAKE_STRIP_H}px`;
    st.left = `${islandX(this.anchorGeom, WAKE_STRIP_W)}px`;
    st.top = `${islandY(this.anchorGeom, WAKE_STRIP_H)}px`;
  }

  // ── Recovery ────────────────────────────────────────────────────────────────

  /**
   * Says, once and quietly, that the last run died and the OS brought Coucou
   * back. Instrumentation while the crash is still unexplained: `coucou.log`
   * keeps the permanent record, this is so the person at the keyboard is not
   * the last to know.
   */
  noteRecovered() {
    const note = h(
      "div",
      { id: "recovered-note" },
      h("span", { class: "rec-dot" }),
      h("span", { text: t("Notchy closed unexpectedly and started again.") }),
    );
    let timer: number | null = null;
    const dismiss = () => {
      if (timer != null) window.clearTimeout(timer);
      timer = null;
      note.remove();
    };
    note.addEventListener("click", dismiss);
    this.contentEl.append(note);
    // Same dwell a notification gets, so it reads like everything else here.
    timer = window.setTimeout(dismiss, State.settings.autoCloseInterval * 1000);
    this.alert(State.defaultView());
  }

  // ── Window collapse (nothing open → a tiny window, zero polling) ────────────
  //
  // Two windows are small enough to park the cursor poll: the invisible wake
  // strip the island retracts into, and the compact bar it rests as when it
  // never folds away. `foldFor` picks between them; here we only care that it
  // is not the panel, because that is what the poll costs.

  private updateWindowCollapsed() {
    const wantsCollapse = () => this.fold() !== "panel";
    if (wantsCollapse()) {
      // Collapsed already, but into the other of the two: see `refoldNeeded`.
      // Asking again is the same round trip as the collapse below — Rust puts
      // the window to the fold it should now be, hands it the mouse and
      // settles the poll — with the same tail once it lands.
      if (this.collapseTimer == null && !this.refolding
          && refoldNeeded(this.collapsed, this.windowIsBar, this.fold())) {
        this.refolding = true;
        void Bridge.setCollapsed(true)
          .then(() => {
            // Opened while it was in flight: the window is the panel again.
            if (!this.collapsed) return;
            this.windowIsBar = this.fold() === "bar";
            this.positionWakeStrip();
            this.applyGeometry();
          })
          .finally(() => {
            this.refolding = false;
          });
        return;
      }
      // Already there, or already on its way. Every `settings-changed` comes
      // through here too and a volume drag emits a stream of them: clearing and
      // re-arming on each would push the collapse out for the length of the
      // drag, and then re-issue one that had already happened — a round of
      // apply_geometry, refresh_click_through and set_active per event.
      if (this.collapsed || this.collapseTimer != null) return;
      // Let the island finish settling into its resting size, then drop the
      // window to it: from there the OS delivers no cursor events, so nothing
      // polls at all and hovering is the DOM's job — `wakeFromDom`.
      this.collapseTimer = window.setTimeout(() => {
        this.collapseTimer = null;
        if (!wantsCollapse()) return;
        // The window first, then what is drawn inside it.
        //
        // The two move in opposite directions. The bar's 0,0 is the very screen
        // pixel the panel's own offsets land the island on, so the island
        // holding the bar's offsets inside a window that is still the panel is
        // Mochi painted a panel's width and height away from where it belongs
        // — and `setCollapsed` is an IPC round trip, not a frame. Holding the
        // panel's offsets until the resize lands costs at worst an island
        // clipped out of its own window for that round trip, which is nothing
        // where there was already nothing; the other way round is a teleport
        // and a snap back. It also keeps `setIslandRect`, which `applyGeometry`
        // pushes, from handing Rust a rectangle in a window that does not exist
        // yet: hit-tested against the real one, the bar would be click-through
        // and a click on Mochi would land on whatever is behind it.
        this.collapsed = true;
        void Bridge.setCollapsed(true).then(() => {
          // Overtaken: the pointer arrived while this was in flight and the
          // island is already on its way open, which has asked for the panel
          // back. Drawing the bar's offsets now would be the teleport again.
          if (!this.collapsed) return;
          this.windowIsBar = this.fold() === "bar";
          this.positionWakeStrip();
          this.applyGeometry();
        });
      }, 420);
      return;
    }
    if (this.collapseTimer != null) {
      window.clearTimeout(this.collapseTimer);
      this.collapseTimer = null;
    }
    if (this.collapsed) {
      // Growing, so the order is the other way about for the same reason: the
      // island takes the panel's offsets first and is clipped out of the bar
      // for the round trip, rather than sitting at the bar's 0,0 inside a
      // window that has already become the panel.
      this.collapsed = false;
      this.windowIsBar = false;
      this.positionWakeStrip();
      this.applyGeometry();
      void Bridge.setCollapsed(false);
    }
  }

  // ── Picking the island up ───────────────────────────────────────────────────
  //
  // Settings can put the island in one of six places; holding it puts it
  // anywhere. A press on the resting island that lasts `HOLD_MS` without
  // wandering unsticks it, and from there the window follows the pointer —
  // across displays and all — until the button comes back up.
  //
  // Rust does the moving where it can (see `begin_drag` in island.rs): it reads
  // the cursor and the button sixty times a second already, and asking the page
  // for every frame would show as the island trailing the hand.

  /** A press on the resting island may become a drag. Nothing happens yet. */
  private armGrab(e: MouseEvent) {
    this.clearGrab();
    this.grab = {
      x: e.clientX,
      y: e.clientY,
      screenX: e.screenX,
      screenY: e.screenY,
      timer: window.setTimeout(() => this.liftOff(), HOLD_MS),
    };
    // Two seconds of nothing reads as a hang: the ring fills over exactly that
    // long, so the wait looks like a thing being done rather than a thing stuck.
    this.grabGlow.classList.add("filling");
  }

  /** Lets a press go: anything short of a lift is the click it always was. */
  private clearGrab() {
    if (this.grab != null) {
      window.clearTimeout(this.grab.timer);
      this.grab = null;
    }
    this.grabGlow.classList.remove("filling");
  }

  /**
   * The pointer wandered while a press was being held.
   *
   * A hold is a hold: past `HOLD_SLOP` this was a hand moving, not waiting, and
   * the press goes back to being an ordinary click. `x`/`y` are window-logical,
   * the same coordinates `onCursor` works in.
   */
  private checkGrabSlop(x: number, y: number) {
    const g = this.grab;
    if (g == null) return;
    if (Math.abs(x - g.x) > HOLD_SLOP || Math.abs(y - g.y) > HOLD_SLOP) this.clearGrab();
  }

  /** Held long enough: the island comes unstuck and takes the pointer with it. */
  private liftOff() {
    const g = this.grab;
    if (g == null) return;
    this.grab = null;
    this.grabGlow.classList.remove("filling");
    if (!this.canBeMoved()) return;

    this.dragging = true;
    this.liftFrom = { x: g.screenX, y: g.screenY };
    this.grabGlow.classList.add("lifted");
    document.documentElement.dataset.dragging = "1";
    Sound.play("peek");

    // The resting footprint, not whatever is drawn right now: the stored point
    // is the resting island's centre, so that is what has to be handed over.
    //
    // Through `origin`, because the window it is a centre *of* is not always
    // the panel: picked up from the resting bar, the window is that bar and the
    // island is at 0,0 inside it. Measured against the panel from there, the
    // island would jump by most of its own width the moment it came unstuck.
    const { restW, restH } = METRICS;
    const rest = this.origin(restW, restH);
    const centreX = rest.x + restW / 2;
    const centreY = rest.y + restH / 2;
    void Bridge.startIslandDrag(centreX, centreY, g.x, g.y);
    if (this.pageCursor) window.addEventListener("pointermove", this.onDragMove);
  }

  /**
   * Only the resting island is picked up.
   *
   * An open card is full of things to press, and the stored point is the
   * resting island's centre anyway — dragging a card by one of its corners
   * would put Mochi somewhere nobody asked for.
   */
  private canBeMoved(): boolean {
    return State.settings.enabled && State.mode !== "expanded";
  }

  /**
   * Wayland only: no global cursor for Rust to read, so the page says how far
   * the hand has gone. A delta off the press, because the window keeps moving
   * out from under the pointer and its own coordinates stop meaning anything.
   */
  private onDragMove = (e: PointerEvent) => {
    if (!this.dragging) return;
    void Bridge.dragIsland(e.screenX - this.liftFrom.x, e.screenY - this.liftFrom.y);
  };

  /**
   * The button came up.
   *
   * A press that never lifted is the click that opens the island. One that did
   * is a drop: Rust works out where it landed, writes it to the settings and
   * sends everything back through `settings-changed`, so there is nothing to
   * apply here.
   */
  private releaseGrab() {
    if (this.dragging) {
      this.dragging = false;
      this.grabGlow.classList.remove("lifted");
      delete document.documentElement.dataset.dragging;
      window.removeEventListener("pointermove", this.onDragMove);
      void Bridge.endIslandDrag();
      return;
    }
    const held = this.grab != null;
    this.clearGrab();
    if (held && State.mode !== "expanded") this.fsm.click();
  }

  /**
   * The pointer arrived while the window is collapsed.
   *
   * The only ear the island has there: a collapsed window has parked the cursor
   * poll, which is where every other hover comes from, so without this a
   * resting Mochi could be pointed at all day and never answer.
   */
  private wakeFromDom() {
    // Off, the window is hidden and none of this is on screen at all. The guard
    // is for the compositor that ignores hide() anyway — this listener firing
    // is precisely how the old Pause was undone by a stray mouse.
    if (!State.settings.enabled) return;
    // In standby the window is there but deaf: only a message reopens the
    // island. Rust stops handing it the mouse at all (refresh_click_through);
    // this is the half that holds where the window still delivers events — and
    // `asleepFor` is where the two agree on what standby even applies to.
    if (asleepFor(State.settings.standby, State.settings.alwaysVisible)) return;
    // Not collapsed means the poll is awake and owns this; it reads the cursor
    // against the island's real shape, which inside the panel is most of what
    // this element is not.
    if (!this.collapsed) return;
    Sound.resume();
    if (State.mode === "expanded") return;
    // At the top the island is in a dead corner of the screen, so a touch of it
    // is a request. At the bottom it lies across the route to the clock and the
    // tray, so down there the pointer has to mean it.
    if (this.anchorGeom.edge === "top") {
      this.fsm.mouseEntered();
      return;
    }
    // Already counting: `mousemove` comes here as well as `mouseenter`, and
    // re-arming on every move would turn "rest the pointer here" into "stop
    // dead here", which is not what the strip has always asked for.
    if (this.wakeDwell != null) return;
    this.wakeDwell = window.setTimeout(() => {
      this.wakeDwell = null;
      if (State.settings.enabled
          && !asleepFor(State.settings.standby, State.settings.alwaysVisible)
          && this.collapsed && State.mode !== "expanded") {
        this.fsm.mouseEntered();
      }
    }, WAKE_DWELL_MS);
  }

  private clearWakeDwell() {
    if (this.wakeDwell != null) {
      window.clearTimeout(this.wakeDwell);
      this.wakeDwell = null;
    }
  }

  // ── Input ───────────────────────────────────────────────────────────────────

  private wireInput() {
    // Two things can be hit while the window is collapsed, and only ever one of
    // them at a time: the wake strip, where the island has retracted into the
    // screen edge and left six invisible pixels, and the island itself, where
    // it rests as the compact bar and fills the window it is in — covering the
    // strip, so the strip never hears a thing. Same answer from either.
    // `mousemove` beside `mouseenter` because `mouseenter` is an edge, and the
    // window can arrive under a pointer that is already there: switch Coucou
    // off with the pointer in that corner and back on again, or let the panel
    // shrink to the bar under a hand that has not moved. No enter is fired for
    // either, the poll is parked, and `onCursor` stands down while collapsed —
    // so without this there is no way back in at all.
    for (const el of [this.wakeStrip, this.islandEl]) {
      el.addEventListener("mouseenter", () => this.wakeFromDom());
      el.addEventListener("mousemove", () => this.wakeFromDom());
      el.addEventListener("mouseleave", () => this.clearWakeDwell());
    }

    // The snow parts for the pointer. From the island's own events rather than
    // the cursor poll: the poll is parked while the window is the resting bar,
    // and these fire in every state, through whatever card is on top.
    this.islandEl.addEventListener("mousemove", (e) => {
      const rect = this.islandRect();
      this.snow.setPointer({ x: e.clientX - rect.x, above: rect.y + rect.h - e.clientY });
    });
    this.islandEl.addEventListener("mouseleave", () => this.snow.setPointer(null));

    this.islandEl.addEventListener("mousedown", (e) => {
      Sound.resume();
      State.lastActivity = performance.now();
      if (State.mode !== "expanded") {
        // Not opened here: a press that stays down is how the island is picked
        // up, so which of the two this was is only known when it comes back up.
        this.armGrab(e);
        return;
      }
      if (this.isBotHit(e.clientX, e.clientY)) {
        this.cancelBotHover();
        this.engine.slap();
      }
    });

    // On the window, not the island: a drag ends wherever the hand stopped, and
    // by then the pointer is usually nowhere near where it started.
    window.addEventListener("mouseup", () => this.releaseGrab());

    window.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        // A screen first: it holds the island open, so `collapse` would
        // refuse it, and Escape is one of the ways the user takes it away.
        // While the page itself has the keyboard, Rust sends "page-escape".
        if (this.viewHoldsIslandOpen) this.closeScreen();
        else if (State.mode === "expanded" && !State.isPinned) this.collapse();
      }
      State.lastActivity = performance.now();
    });

    void onDragDrop((e) => this.onDragDrop(e));

    // Outside Tauri (plain browser) drive the cursor from DOM events so the
    // island can be inspected with `npm run dev`.
    if (!IS_TAURI) this.followPageCursor();
  }

  /**
   * Takes the cursor from the page's own mouse events instead of Rust's poll.
   * Used where the OS has no global cursor position (Wayland): the events only
   * fire while the pointer is over the island, so leaving the window is
   * reported as a cursor far away, which is what the poll would have said.
   */
  followPageCursor() {
    this.pageCursor = true;
    window.addEventListener("mousemove", (e) => this.onCursor(e.clientX, e.clientY));
    window.addEventListener("mouseout", (e) => {
      if (e.relatedTarget == null) this.onCursor(-10_000, -10_000);
    });
  }

  /** Cursor in window-logical coordinates. */
  onCursor(x: number, y: number) {
    State.mouse = { x, y };
    const rect = this.islandRect();
    State.mouseInIsland = { x: x - rect.x, y: y - rect.y };

    // A hold is a hold: a hand that is moving was never waiting.
    this.checkGrabSlop(x, y);

    // A picked-up island is carried by the pointer, so the pointer is on it in
    // every frame. Letting the rest of this run would be the island telling
    // itself it is being hovered all the way across the screen, which is how a
    // drag would end with the card open under the hand that was moving it.
    if (this.dragging) return;

    // Windows sends no cursor position with an OLE drag, so the drop sequence is
    // fed from the Win32 cursor poll instead — it runs throughout the drag.
    if (UploadSeq.isActive && !UploadSeq.dropped) {
      UploadSeq.updateCursor(State.mouseInIsland.x, State.mouseInIsland.y);
    }

    // Tested against where the island is *going*, not where the animation has
    // got to: a rect that grows and shrinks past a stationary cursor hands the
    // state machine enter/leave edges that the pointer never produced, and the
    // animation ends up driving the state that drives the animation.
    const hit = this.targetRect();
    const m = State.mode === "expanded" ? STAY_MARGIN : ENTER_MARGIN;
    const inIsland =
      x >= hit.x - m && x <= hit.x + hit.w + m &&
      y >= hit.y - m && y <= hit.y + hit.h + m;

    // Not while the window is collapsed. The resting bar fills its own window,
    // so on Wayland — where this runs off the page's own mousemove — every
    // pointer crossing it reads as a hover and would open the island on
    // contact. `wakeFromDom` owns the enter edge down there, dwell and all,
    // because at a bottom corner the pointer is as often only on its way to the
    // clock. Where the cursor poll exists it is parked by then and none of this
    // runs at all; the guard is what makes the two platforms agree.
    if (inIsland && !this.wasInIsland && !this.collapsed) {
      if (this.fsm.state === "coucou") this.greeting.hover();
      // The pointer is here: whatever countdown was running is off, and the
      // island stays open until it leaves.
      this.homeCollapseAt = null;
      this.fsm.mouseEntered();
    }
    if (!inIsland && this.wasInIsland) {
      // Leaving no longer starts a countdown worth drawing — the island is on
      // its way out within the grace period.
      this.homeCollapseAt = null;
      this.fsm.mouseLeft();
    }
    this.wasInIsland = inIsland;

    // Bot hover → love
    const overBot = State.mode === "expanded" && State.stateOverride == null && this.isBotHit(x, y);
    if (overBot && !this.botHovering) this.botHoverIn(x, y);
    if (!overBot && this.botHovering) this.cancelBotHover();
    this.botHovering = overBot;
    if (this.botHovering) {
      const d = Math.hypot(x - this.botHoverStart.x, y - this.botHoverStart.y);
      if (d > 40) {
        this.botHoverStart = { x, y };
        this.scheduleLove();
      }
    }

    this.ensureRunning();
  }

  private isBotHit(x: number, y: number): boolean {
    // Nothing to slap or hover where nothing is drawn. The drop keeps its
    // Mochi and so goes on answering here.
    if (this.charactersOff) return false;
    // On a screen Mochi is a face in the header row — the Mac's there takes no
    // clicks — and the site has none at all.
    if (this.viewHoldsIslandOpen) return false;
    const rect = this.islandRect();
    const cx = rect.x + this.botCx.value;
    const cy = rect.y + this.botCy.value;
    const radius = this.botSize.value / 2;
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius;
  }

  private botHoverIn(x: number, y: number) {
    if (performance.now() / 1000 - this.lastLoveTime < 6) return;
    this.botHoverStart = { x, y };
    this.engine.blink();
    this.engine.tgEs = 1.08;
    Sound.play("hover");
    this.scheduleLove();
  }

  private scheduleLove() {
    if (this.botHoverTimer != null) window.clearTimeout(this.botHoverTimer);
    this.botHoverTimer = window.setTimeout(() => {
      this.botHoverTimer = null;
      if (!this.botHovering || State.stateOverride != null) return;
      if (performance.now() / 1000 - this.lastLoveTime < 6) return;
      this.lastLoveTime = performance.now() / 1000;
      this.emote("love");
      Sound.play("love");
    }, 1900);
  }

  private cancelBotHover() {
    if (this.botHoverTimer != null) window.clearTimeout(this.botHoverTimer);
    this.botHoverTimer = null;
    this.engine.tgEs = 1;
  }

  /** Three slaps → dizzy + confused view for 3.3 s, then back. */
  private handleDizzy() {
    this.prevViewBeforeConfused = State.view;
    State.stateOverride = "dizzy";
    this.engine.setState("dizzy");
    Sound.play("dizzy");
    this.alert("confused");
    if (this.confusedRecovery != null) window.clearTimeout(this.confusedRecovery);
    this.confusedRecovery = window.setTimeout(() => {
      this.confusedRecovery = null;
      State.stateOverride = null;
      this.engine.setState(State.effectiveState);
      if (State.view === "confused") {
        const fallback = State.defaultView();
        this.setView(this.prevViewBeforeConfused === "confused" ? fallback : this.prevViewBeforeConfused);
      }
      this.emote("happy");
    }, 3300);
  }

  // ── Frame loop ──────────────────────────────────────────────────────────────

  ensureRunning() {
    if (this.running) return;
    this.running = true;
    this.lastFrame = performance.now();
    requestAnimationFrame(this.frame);
  }

  private frame = (nowMs: number) => {
    const dt = Math.min(0.05, (nowMs - this.lastFrame) / 1000);
    this.lastFrame = nowMs;

    // A view written straight into `State.view`, round `setView`: caught before
    // this frame moves anything, so a page still goes before its card does and
    // a hold the old screen took is let go. Nothing in the app does this any
    // more; this is so the next one cannot leave a page or a hold behind.
    if (this.screenView !== State.view) this.screenChanged();

    this.width.step(dt, nowMs);
    this.height.step(dt, nowMs);
    this.radius.step(dt, nowMs);
    this.applyGeometry();

    // A running clock has to redraw without anything else happening, and twice
    // a second is enough to move a `m:ss` display. Not every frame: syncDom
    // touches the whole panel.
    if (FocusTimer.isActive && nowMs - this.lastTimerSync > 500) {
      this.lastTimerSync = nowMs;
      this.dirty = true;
    }

    if (this.dirty) {
      this.dirty = false;
      this.syncDom();
    }

    this.updateBotTargets();
    this.botCx.step(dt);
    this.botCy.step(dt);
    this.botSize.step(dt);

    const greetingActive = State.mode === "expanded" && State.view === "greeting";
    if (greetingActive) {
      const gctx = this.greetingCanvas.getContext("2d");
      if (gctx) {
        const dpr = Math.min(2, window.devicePixelRatio || 1);
        gctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        this.greeting.draw(gctx);
      }
    } else if (!this.charactersOff) {
      // Kept running even while the drop canvas is up, so the island's own Mochi
      // is already in the right place the moment the canvas fades out. Not kept
      // running behind an opacity of zero, though: a canvas nobody can see must
      // not cost a frame every 16 ms.
      this.drawBot(dt);
    }
    // ChatGPT's own Mochi, in his row: drawn while the view is up and through
    // the 0.16 s it takes to fade out, and the rest of the time run on out of
    // sight for as long as he exists — the Mac's TimelineView runs his
    // unless the island is hidden. An emote or a spark that started on another
    // card plays out there and then, rather than waiting for the row to come
    // up and going off on it all at once.
    const row = this.liveRow();
    const rowUp = row != null && this.rowMochiOn;
    if (this.rowWasUp && !rowUp) this.rowLeftAt = nowMs;
    this.rowWasUp = rowUp;
    // A fold takes him too, but his view still fades: he goes on moving in it.
    const rowFading = !rowUp && !State.settings.hideCharacters
      && nowMs - this.rowLeftAt < VIEW_FADE_OUT_MS;
    if (rowUp || rowFading) this.drawRowBot(dt);
    else if (row) this.stepRowBot(dt);

    const uploadActive = this.uploadActive;
    if (uploadActive) this.uploadCanvas.draw(UploadSeq.frame(), nowMs / 1000);
    this.uploadCanvas.el.classList.toggle("on", uploadActive);
    this.viewsEl.classList.toggle("hidden-by-upload", uploadActive);

    tickMiniBots(dt);
    this.views.get(State.view)?.tick?.(nowMs);
    if (UploadSeq.isActive) this.stepSequence();
    this.updateCountdown(nowMs);

    // Nothing is drawn while the island is hidden, so nothing may keep the loop
    // alive either. This used to read `... || this.engine.busy || State.mode !==
    // "hidden"`, and engine.busy is permanently true for any state with a
    // looping animation — breathing, ratelimit sweat, sleeping z's, the search
    // sweep — so a hidden island went on burning frames in exactly the states it
    // spends most of its life in. Geometry still has to finish retracting.
    //
    // `drawMode`, so hidden means nothing on screen rather than nothing open.
    // One rule, deliberately: if Mochi is on screen, Mochi is alive. A still
    // character in the corner is what this app looks like when it has died, and
    // freezing one would need a wake-up for every state change, the countdown
    // and the mini bots included — more ways to leave a stuck frame than a
    // 20 px canvas is worth. What a resting island was costing is the native
    // cursor poll and a transparent 760x620 always-on-top window, and both are
    // gone by the time this runs.
    //
    // That rule also covers the island dropped out in the open with the
    // preference off, which rests as the bar because there is no edge to
    // retract into. That one used to stop dead — because it was drawing an
    // empty bar, which is the bug above. A visible Mochi has to be drawn, so
    // showing it and parking the loop are not both available.
    const settling =
      this.width.animating || this.height.animating || this.radius.animating;
    // A page goes over its card once the island is still — and is moved, or
    // taken off, if the island goes anywhere while it is up.
    this.pages.frame(this.islandRect(), settling);
    const busy = this.drawMode() === "hidden"
      ? settling
      : settling ||
        !this.botCx.settled || !this.botCy.settled || !this.botSize.settled ||
        greetingActive || this.engine.busy || UploadSeq.isActive || this.pages.pending ||
        rowFading || (row != null && row.busy);

    if (busy) {
      requestAnimationFrame(this.frame);
    } else {
      this.running = false;
      Sound.idle();
    }
  };

  private updateBotTargets() {
    // `drawMode`, not `State.mode`: a resting island is hidden as far as the
    // machine is concerned and a compact bar as far as the screen is, and this
    // is the screen's question. Asked the machine, it answers opacity 0 — which
    // is an empty black bar in the corner, Mochi and all left out of it.
    const p = botPosition(this.drawMode(), State.view, this.height.value, State.uploadProgress, State.settings.homeContent, State.homeShowsPlayer);
    this.botCx.target = p.cx;
    this.botCy.target = p.cy;
    this.botSize.target = p.diameter / 0.6;

    const greetingActive = State.mode === "expanded" && State.view === "greeting";
    // The site draws over the whole island, and on the Mac it covers him as he
    // goes. ChatGPT does not: there he stays in sight while he shrinks away on
    // his springs, and the row's own Mochi arrives with the view.
    const screen = State.mode === "expanded" && isScreen(State.view);
    const covered = State.mode === "expanded" && State.view === "web";
    // Under a pixel there is nothing of him left to draw. The size spring goes
    // through zero on its way down, and a canvas kept at its 1 px floor would
    // still put a speck where he was heading.
    const gone = this.botSize.value < 1;
    // The drop canvas draws its own Mochi; two of them would overlap.
    const visible = p.opacity > 0 && !greetingActive && !this.uploadActive && !this.charactersOff
      && !covered && !gone;
    this.botCanvas.style.opacity = visible ? "1" : "0";

    // No glow on a screen: the island's Mochi has stepped out of both, his glow
    // going with his diameter as the Mac's does, and the row's is drawn
    // without one.
    if (State.mode === "expanded" && State.view !== "uploading" && !greetingActive
        && !this.uploadActive && !this.charactersOff && !screen) {
      const d = p.diameter;
      const color = botGlowColor(State.effectiveState);
      this.botGlow.style.display = "block";
      this.botGlow.style.width = `${d * 2.2}px`;
      this.botGlow.style.height = `${d * 2.2}px`;
      this.botGlow.style.left = `${this.botCx.value - d * 1.1}px`;
      this.botGlow.style.top = `${this.botCy.value - d * 1.1}px`;
      this.botGlow.style.background = `radial-gradient(circle, ${color} 0%, transparent 62%)`;
      this.botGlow.style.opacity = String(botGlowOpacity(State.effectiveState));
    } else {
      this.botGlow.style.display = "none";
    }
  }

  private drawBot(dt: number) {
    const size = this.botSize.value;
    const w = Math.max(1, Math.round(size));
    const hCss = w + BOT_OVERHANG;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    if (this.canvasPx !== w) {
      this.canvasPx = w;
      this.botCanvas.width = Math.round(w * dpr);
      this.botCanvas.height = Math.round(hCss * dpr);
      this.botCanvas.style.width = `${w}px`;
      this.botCanvas.style.height = `${hCss}px`;
    }
    this.botCanvas.style.left = `${this.botCx.value - w / 2}px`;
    this.botCanvas.style.top = `${this.botCy.value - BOT_OVERHANG / 2 - hCss / 2}px`;

    const ctx = this.botCanvas.getContext("2d");
    if (!ctx) return;
    this.paintMochi(this.engine, this.ato, ctx, dpr, w, hCss, BOT_OVERHANG, dt);
  }

  /**
   * Whether ChatGPT's row has its Mochi to draw: the view up, the characters
   * on. The Mac's row leaves its `BotCanvasView` out with them off.
   */
  private get rowMochiOn(): boolean {
    return State.mode === "expanded" && State.view === "webchat" && !State.settings.hideCharacters;
  }

  /**
   * Whether ChatGPT's row has a Mochi at all, on screen or not. The Mac builds
   * every view's content at once, the row's `BotCanvasView` among them, inside
   * `IslandContentView` — which is there while the island is open on its cards
   * and nowhere else: the greeting and the drop canvas take its place, a fold
   * takes it away. With the characters off the row leaves him out.
   */
  private get rowExists(): boolean {
    return State.mode === "expanded" && State.view !== "greeting" && !this.uploadActive
      && !State.settings.hideCharacters;
  }

  /**
   * The row's Mochi, or null while there is none — and a new one the first
   * time he is asked for after there was none, as SwiftUI builds the view
   * again: a fresh engine and orb, put in the island's state at once
   * (`.onAppear { setState(force: true) }`). Nothing is said to him while he
   * does not exist, and nothing said to an earlier one is kept, so there is no
   * store of hearts and sparks to go off on him when ChatGPT next opens.
   */
  private liveRow(): BotEngine | null {
    const exists = this.rowExists;
    if (exists && !this.rowLive) {
      this.rowEngine = new BotEngine();
      this.rowAto = new AtoDriver(true);
      this.rowEngine.setState(State.effectiveState, true);
    }
    this.rowLive = exists;
    return exists ? this.rowEngine : null;
  }

  /**
   * ChatGPT's row Mochi — `BotCanvasView(state:)` in `.frame(width: 34,
   * height: 34)`, no room kept for hearts — into the canvas the row holds for
   * him. Everything else is the island's Mochi's: the same owner, character,
   * colour, state and gaze, drawn by the same code.
   */
  private drawRowBot(dt: number) {
    if (!this.rowCanvas?.isConnected) {
      this.rowCanvas = this.views.get("webchat")?.el.querySelector<HTMLCanvasElement>(".wc-mochi canvas") ?? null;
    }
    const canvas = this.rowCanvas;
    if (!canvas) return;
    const side = ROW_MOCHI;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const px = Math.round(side * dpr);
    if (canvas.width !== px || canvas.height !== px) {
      canvas.width = px;
      canvas.height = px;
    }
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    this.paintMochi(this.rowEngine, this.rowAto, ctx, dpr, side, side, 0, dt);
  }

  /** The row's Mochi with his view off screen: run on, as `drawRowBot` would, and not drawn. */
  private stepRowBot(dt: number) {
    this.paintMochi(this.rowEngine, this.rowAto, null, 1, ROW_MOCHI, ROW_MOCHI, 0, dt);
  }

  /**
   * One Mochi, dressed and drawn: what BotCanvasView pushes into its engine
   * every frame, for whichever canvas is asking — the island's own, or the one
   * in ChatGPT's row. `w` × `h` is the canvas in CSS px, `overhang` the room
   * it keeps above him for hearts. No `ctx`: dressed and run, but not drawn.
   */
  private paintMochi(
    engine: BotEngine, ato: AtoDriver, ctx: CanvasRenderingContext2D | null,
    dpr: number, w: number, h: number, overhang: number, dt: number,
  ) {
    // The owner of the *view*, not whoever holds focus — `characterOwnerId`.
    // An Ato card is Ato's whichever pill was clicked last, as on the Mac.
    const owner = State.characterOwnerId;
    const ownerColor = State.characterOwnerColor;
    engine.bodyColor = ownerColor ? hexToRGB(ownerColor) : null;
    // Pushed every frame, like bodyColor above: the user can change characters
    // in Settings while the island is open, and a value read once would go stale.
    engine.character = State.characterFor(owner);
    engine.particleOverhang = overhang;
    // Where the island's Mochi is, as BotCanvasView reads it off `botPosition`
    // for every canvas — the row's included, which on the Mac looks from the
    // view's (0, 0) too.
    engine.lookX = this.lookX();
    engine.lookY = this.lookY();
    // A glass on the two hydration cards and nowhere else: every other view
    // draws him exactly as before. Pushed every frame, like the rest.
    const glass = State.mode === "expanded" && WATER_VIEWS.has(State.view) && Hydration.enabled;
    engine.waterLevel = glass ? Hydration.level : null;
    engine.waterColor = Hydration.paused ? WATER_PAUSED : WATER_COLOR;
    if (engine.morph > 0.3) {
      engine.slotHTarget = State.fileDragOver ? 0.2 : 0;
    } else {
      engine.slotHTarget = 0;
      if (engine.morph < 0.05) {
        engine.slotH = 0;
        engine.slotHVel = 0;
      }
    }
    // Dancing to music, on the same conditions as BotCanvasView: something
    // playing, the Now Playing pill on, a calm state, and the island either
    // folded or showing the player.
    const calm: BotStateName[] = ["idle", "working", "thinking", "searching", "finished"];
    engine.setDancing(State.media.isPlaying
      && State.settings.activeIntegrations.includes("integration_music")
      && calm.includes(State.effectiveState)
      && (State.mode === "compact"
        || (State.mode === "expanded" && State.view === "overview" && State.focusId === "integration_music")));
    engine.update(dt);
    // Ato wears its own mascot. Not mid-gulp: the mailbox a file drops into
    // is Mochi's, whoever is in focus.
    // Nor on the hydration cards: the glass that fills is Mochi, and an orb
    // has no body to fill.
    if (owner === ATO_PILL && engine.morph < 0.05 && !glass) {
      // Ato's own state, as on the Mac: the pill's, unless something overrides
      // the island (a dizzy spell), whatever else holds focus.
      const pill = State.tasks.find((t) => t.id === ATO_PILL)?.state ?? "idle";
      const asked = atoStateFor(State.stateOverride ?? pill, State.messageStatus.ato?.state);
      // Reacting as Mochi would: the engine above has run every hover, slap and emote.
      const nowS = performance.now() / 1000;
      // Asked even when nothing is drawn: the orb keeps its own clock, and one
      // run out of sight is in step when its view comes up.
      const frame = ato.frame(nowS, asked, reactionFrom(engine));
      if (!ctx) return;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      engine.applyDance(ctx, w, h);
      // `engine.character` is Ato's here — set from the same owner above.
      drawAtoInBotFrame(ctx, frame, w, h, overhang, atoFestiveFrom(engine, nowS));
      engine.drawParticlesOnly(ctx, w, h);
      return;
    }
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    engine.applyDance(ctx, w, h);
    engine.draw(ctx, w, h);
  }

  /**
   * An emote, for every Mochi the island has. The Mac posts `.triggerEmote`
   * and each `BotCanvasView` there is takes it — ChatGPT's row's as much as
   * the island's — so a glass logged while ChatGPT is up still makes him
   * happy. The row's only while it has a Mochi: with the island folded there
   * is no view to hear it.
   */
  private emote(name: BotEmoteName, duration?: number) {
    this.engine.triggerEmote(name, duration);
    this.liveRow()?.triggerEmote(name, duration);
  }

  /** BotCanvasView.lookX / lookY — tanh of the distance to the bot. */
  private lookX(): number {
    const rect = this.islandRect();
    const botScreenX = rect.x + this.botCx.value;
    return Math.tanh((State.mouse.x - botScreenX) / 260);
  }

  private lookY(): number {
    return -Math.tanh((State.mouse.y - this.botCy.value) / 200);
  }

  /** The hairline that drains while a notification is holding itself open. */
  private updateCountdown(nowMs: number) {
    const px = this.countdownWidth(nowMs);
    this.countdown.style.width = `${px}px`;
    // The snow lies on the same edge, and a white hairline on white snow is no
    // hairline: it steps aside for as long as this is showing.
    this.snow.setCounting(px > 0);
  }

  private countdownWidth(nowMs: number): number {
    // Drawn for a pinned alert too: it is counting down like everything else.
    if (State.mode !== "expanded" || this.fsm.heldOpen || this.homeCollapseAt == null) {
      return 0;
    }
    const total = this.fsm.holdDurationMs / 1000;
    const windowS = Math.min(10, total * 0.6);
    const remaining = (this.homeCollapseAt - nowMs) / 1000;
    if (remaining <= 0) {
      this.homeCollapseAt = null;
      return 0;
    }
    return remaining < windowS ? Math.max(0, clamp(remaining / windowS, 0, 1) * 160) : 0;
  }

  /**
   * Whether there is snow, and whether the island is open under it.
   *
   * The season is asked again on every change rather than once at boot: an
   * island left running over the sixth of January should not still be snowed
   * on in February.
   */
  private syncSnow() {
    this.snow.setEnabled(State.settings.islandSnow
      && (import.meta.env.DEV || isFestiveSeason()));
    this.snow.setExpanded(State.mode === "expanded");
    this.snow.setVisible(State.mode !== "hidden");
  }

  // ── DOM sync ────────────────────────────────────────────────────────────────

  private syncDom() {
    const expanded = State.mode === "expanded";
    const greetingActive = expanded && State.view === "greeting";

    const contentShown = expanded && !greetingActive;
    this.contentEl.style.opacity = contentShown ? "1" : "0";
    this.contentEl.style.pointerEvents = contentShown ? "auto" : "none";
    // Out of sight, its looping animations stop (style.css, `#content.resting`).
    this.contentEl.classList.toggle("resting", !contentShown);
    this.greetingCanvas.style.display = greetingActive ? "block" : "none";

    this.header.sync();
    for (const [name, view] of this.views) {
      const on = name === State.view;
      view.el.classList.toggle("on", on);
      if (on) view.sync();
    }

    // The chat is opened by clicking the chat tab, so taking the keyboard when
    // it appears is answering a request. Nothing else may.
    //
    // This used to fire for every view with a field, which included the message
    // card — and that card appears because somebody else sent you something.
    // The island took the keyboard mid-sentence and the next keystrokes went to
    // it instead of to whatever was being typed in. That is the freeze: not the
    // machine stalling, the keys going elsewhere.
    if (this.lastSyncedView !== State.view) {
      const left = this.lastSyncedView;
      const wasField = left != null && FIELD_VIEWS.has(left);
      this.lastSyncedView = State.view;
      if (left != null) this.dropCaret(left);
      if (State.view === "prompt") {
        void Bridge.focusWindow(true);
        // Only if the chat is still what is on screen: a card that took its
        // place in the meantime has already dropped the caret (`dropCaret`),
        // and this would put it back in a field nobody can see.
        window.setTimeout(() => {
          if (State.mode === "expanded" && State.view === "prompt") this.views.get("prompt")?.focus?.();
        }, 120);
      } else if (wasField && !this.viewKeepsKeyboard) {
        // A card. Not for a screen: its page takes the keyboard once it is
        // placed, and closing the screen or folding the island hands it back
        // (`viewKeepsKeyboard`).
        void Bridge.focusWindow(false);
      }
    }

    // Compact mini grid — and the countdown, which takes its slot.
    //
    // Both sides of the compact bar are spoken for: Mochi on the left, this on
    // the right. A running timer is the more urgent of the two.
    const counting = FocusTimer.isActive;
    // Four little faces and nothing else, so with the characters off this side
    // of the bar simply goes quiet. Mochi keeps the left.
    // `drawMode` for the same reason Mochi uses it: a bar resting out in the
    // open is drawn as a compact bar and has the same two sides to fill.
    const compact = this.drawMode() === "compact";
    // A reminder nobody has answered puts a little glass in that slot. The
    // clock keeps it — a running timer is still the more urgent — and the
    // faces give it up until the reminder is answered.
    const sipping = compact && !counting && Hydration.enabled && Hydration.awaiting;
    this.compactSip.sync(sipping);
    const showGrid = compact && !counting && !sipping && !State.settings.hideCharacters;
    this.compactTimer.style.opacity = compact && counting ? "1" : "0";
    if (compact && counting) {
      this.compactTimer.textContent = FocusTimer.clock;
      this.compactTimer.style.color = FocusTimer.isPaused ? "#9398a1" : TIMER_COLOR[FocusTimer.kind];
    }
    this.miniGrid.style.opacity = showGrid ? "1" : "0";
    if (showGrid) {
      const others = State.otherTasks.slice(0, 4);
      const key = others.map((t) => t.id).join("|");
      if (this.miniGrid.dataset.key !== key) {
        this.miniGrid.dataset.key = key;
        this.miniGrid.replaceChildren();
        for (const t of others) {
          this.miniGrid.append(createMiniBot(t, 13));
        }
        pruneMiniBots();
      }
    }

    syncMiniBotStates(State.tasks);
    this.engine.setState(State.effectiveState);
    // The row's Mochi follows the same state for as long as he exists, as the
    // Mac's `BotCanvasView` does from the moment the island builds its views —
    // a "finished" while folded is no spark kept for later.
    this.liveRow()?.setState(State.effectiveState);
  }

  /**
   * Builds every view again, in whatever language is now in force.
   *
   * A view holds the words it was built with, so there is no retranslating a
   * card in place: the cheapest correct answer is to make them again. Only the
   * language row calls this, so the cost never shows.
   */
  rebuildViews() {
    this.header = buildHeader(this.viewActions);
    this.views = buildViews(this.viewActions, () => this.animateGeometry(false));
    clear(this.viewsEl);
    for (const v of this.views.values()) this.viewsEl.append(v.el);
    clear(this.contentEl);
    this.contentEl.append(this.header.el, this.viewsEl);
    this.syncDom();
  }

  /** Applies settings coming from Rust, at boot and on every change. */
  applySettings() {
    // Switched back on, Rust puts the window back to the full panel whatever
    // the island was resting in when it went off (`apply_enabled`), and the
    // page is never told the island went away at all. Match it: left thinking
    // the window is still the bar, the island would be drawn at that bar's
    // origin inside a window the size of the screen — Mochi in the middle of
    // the display — until the collapse below caught up.
    if (State.settings.enabled && !this.wasEnabled) {
      this.collapsed = false;
      this.windowIsBar = false;
    }
    this.wasEnabled = State.settings.enabled;
    // One line covers all 28 sounds, at every call site.
    Sound.setEnabled(State.settings.soundEnabled && State.settings.enabled);
    Sound.setVolume(State.settings.soundVolume);
    this.fsm.notificationHoldDelay = State.settings.autoCloseInterval;
    // The fold-away delay, which was a minute written into the machine and a
    // preference nobody read. Moot while `alwaysVisible` is on — the timer it
    // feeds is the one that flag switches off — but it has to be right for the
    // moment the flag goes off, which is the line below.
    this.fsm.petitToHiddenDelay = State.settings.absenceInterval;
    // A setter, and it settles the island that is already on screen: turning
    // this on while Mochi has folded away brings it straight back, turning it
    // off starts the fold it had been holding off.
    this.fsm.alwaysVisible = State.settings.alwaysVisible;
    // The window the island lives in follows the same preference: on, it
    // shrinks to the bar once Mochi has settled into its corner; off, it grows
    // back to the panel and waits out the minute before folding. The setter
    // above only moves the machine, and the machine may already be where it
    // needs to be — turned off while resting, nothing transitions at all.
    this.updateWindowCollapsed();
    // Closes every card's Mochi gutter, and puts away the faces inside views
    // that were built before the switch was thrown.
    document.body.classList.toggle("no-mochi", State.settings.hideCharacters);
    this.syncSnow();
    // "No Christmas music" means now, not from the next launch; and nothing
    // plays while Notchy is switched off. On the change only: with the setting
    // off the folder still plays it, and saving some other setting must not
    // cut that short.
    const christmasOn = State.settings.christmasMusic && State.settings.enabled;
    if (this.christmasWasOn && !christmasOn) ChristmasMusic.stop();
    this.christmasWasOn = christmasOn;
    this.applyPosition(State.settings.position);
    State.notify();
  }

  /**
   * Moves the island to another corner. Rust moves the window on the same
   * event, so the two land together and the user sees one jump, not two.
   */
  private applyPosition(position: string) {
    this.position = position;
    this.anchorGeom = anchorFor(position, this.area.w, this.area.h);
    // The stylesheet reads these: anything whose place depends on which edge is
    // the screen edge — the auto-close hairline — keys off them. `free` is the
    // third state: out in the open there is no screen edge to key off, so the
    // rules that press the island into one have to stand down.
    const root = document.documentElement;
    root.dataset.edge = this.anchorGeom.edge;
    root.dataset.align = this.anchorGeom.align;
    root.dataset.hug = this.anchorGeom.hug ?? "free";
    this.clearWakeDwell();
    this.positionWakeStrip();
    this.applyGeometry();
  }

  get panelSize() {
    return { w: PANEL_W, h: PANEL_H };
  }

  get chatHeight() {
    return chatPromptHeight(State.chatHistory.length);
  }
}
