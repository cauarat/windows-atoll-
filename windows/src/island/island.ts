// The island: DOM shell, sizing animation, Mochi placement, mouse handling.
// Mirrors IslandRootView.swift + IslandWindowController.swift.

import { CLOSE_MS, OPEN_DAMPING, OPEN_RESPONSE, Spring, Tracked, clamp } from "../core/anim";
import {
  DEFAULT_POSITION, alignOf, edgeOf, islandX, islandY, radiusCss,
  type IslandPosition,
} from "../core/anchor";
import { FocusTimer, TIMER_COLOR } from "../core/timer";
import { Bridge, IS_TAURI, onDragDrop } from "../core/bridge";
import {
  EXPANDED_CORNER, EXPANDED_W, NOTCH_W, PANEL_H, PANEL_W,
  ROUNDED_CORNER, VIEW_LAYOUTS, WAKE_STRIP_H, WAKE_STRIP_W,
  botGlowColor, botGlowOpacity, botPosition, chatPromptHeight,
  islandSize,
  type IslandMode, type IslandViewName,
} from "../core/layout";
import { Sound } from "../core/sound";
import {
  ALWAYS_LOADED_PILL, INTEGRATION_AGENTS, NOTIFICATIONS_PILL, State, sourceForPill,
} from "../core/state";
import * as ReplyAttachments from "./replyAttachments";
import { BotEngine, hexToRGB } from "../mochi/engine";
import { Greeting } from "../mochi/greeting";
import { createMiniBot, pruneMiniBots, syncMiniBotStates, tickMiniBots } from "../mochi/minibots";
import { UploadCanvas } from "../upload/canvas";
import { USC, UploadSeq } from "../upload/sequence";
import { buildHeader, buildViews, type ViewActions, type ViewHost } from "../views/views";
import { h, svg, clear } from "../views/dom";
import { ICONS } from "../views/icons";
import { PILL_LOGOS } from "../views/logos";
import {
  DIAMETER as RING_D, chromeBounds, edgeAction, layout as ringLayout, visible as ringVisible,
  type EdgeButton,
} from "../core/edgeRing";
import { IslandStateMachine } from "./fsm";

const BOT_OVERHANG = 40;

/**
 * What each button on the border draws.
 *
 * Mattermost and ClickMassa are missing here because they wear their own marks,
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
  agentsDashboard: ICONS.sparkles,
  clipboard: ICONS.clipboard,
  timer: ICONS.timer,
  settings: ICONS.gear,
  site: ICONS.globe,
};

/**
 * How long the pointer has to stay in a bottom wake strip before Mochi peeks.
 * Long enough that crossing it on the way to the tray does nothing, short
 * enough that aiming for it still feels immediate.
 */
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
  private botGlow!: HTMLElement;
  private greetingCanvas!: HTMLCanvasElement;
  private miniGrid!: HTMLElement;
  private compactTimer!: HTMLElement;
  private lastTimerSync = 0;
  private countdown!: HTMLElement;
  private wakeStrip!: HTMLElement;
  private ringEl!: HTMLElement;
  /** The buttons currently on the border, in the order `State.edgeButtons` gave. */
  private ring: { el: HTMLElement; button: EdgeButton }[] = [];
  /** What the ring was built from, so it is only rebuilt when it changes. */
  private ringKey = "";
  /** Mirrored from the settings so the frame loop never reaches into State. */
  private position: IslandPosition = DEFAULT_POSITION;
  /** Set while the pointer waits out the dwell on a bottom wake strip. */
  private wakeDwell: number | null = null;

  private header!: ViewHost;
  private views!: Map<IslandViewName, ViewHost>;
  private uploadCanvas!: UploadCanvas;

  private width = new Tracked(NOTCH_W);
  private height = new Tracked(0);
  private radius = new Tracked(ROUNDED_CORNER);
  private botCx = new Spring(46);
  private botCy = new Spring(16);
  private botSize = new Spring(10);

  private engine = new BotEngine();
  private greeting = new Greeting();

  private running = false;
  private lastFrame = 0;
  private dirty = true;
  private canvasPx = 0;

  // Rust starts the window at full size so the launch greeting has room.
  private collapsed = false;
  private collapseTimer: number | null = null;
  private wasInIsland = false;
  /** Last shape handed to Rust for the click-through test. */
  private pushedRect = { x: -1, y: -1, w: -1, h: -1 };
  private homeCollapseAt: number | null = null;

  // Bot hover → love (IslandWindowController.botHoverIn)
  private botHovering = false;
  private botHoverTimer: number | null = null;
  private lastLoveTime = 0;
  private botHoverStart = { x: 0, y: 0 };

  private confusedRecovery: number | null = null;
  private prevViewBeforeConfused: IslandViewName = "overview";
  private lastSyncedView: IslandViewName | null = null;

  /** Drop sequence bookkeeping: last tick played, and whether the ✓ has fired. */
  private uploadTens = 0;
  private uploadDone = false;

  constructor(root: HTMLElement) {
    this.root = root;
    this.build();
    this.wireFsm();
    this.wireInput();
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
      collapse: () => this.collapse(),
      setFocus: (id) => {
        Sound.play("blip");
        this.openPill(id);
      },
      openTerminal: () => {
        const cwd = State.focusTask?.sessionCwd ?? null;
        void Bridge.openInVSCode(cwd);
      },
      // The ↗ button — same targets as openPillTarget() on macOS. Claude Code
      // is the only pill left that opens somewhere: the message pills are
      // answered in the island, and Now Playing is the player itself.
      openTarget: () => {
        const task = State.focusTask;
        if (!task) return;
        if (task.id === ALWAYS_LOADED_PILL) void Bridge.openInVSCode(task.sessionCwd ?? null);
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
      openSettingsWindow: () => void Bridge.openSettingsWindow(),
      // The reply box holds the island open while it has the cursor, the same
      // way an approval waiting for an answer does.
      focusField: (on) => void Bridge.focusWindow(on),
      setPinned: (on) => {
        State.isPinned = on;
        this.fsm.pinned = on;
        // Staged files and an open picker hold the card for the same reason a
        // half-written sentence does. The picker is the sharper case: it takes
        // focus, so this runs with `on` false the instant it opens, and
        // without the other two the card would fold away behind it.
        this.fsm.heldOpen = on || State.pickingFile
          || State.replyAttachments.length > 0;
        if (on) {
          this.fsm.cancelTimers();
          this.homeCollapseAt = null;
        } else {
          State.lastActivity = performance.now();
          // Nothing else restarts the close timer once the cursor has already
          // left: without this the island would simply stay open for good.
          if (!this.wasInIsland) this.fsm.mouseLeft();
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
      this.greetingCanvas,
      this.uploadCanvas.el,
      this.contentEl,
    );
    this.islandEl = h(
      "div",
      { id: "island" },
      this.clipEl,
      this.botGlow,
      this.botCanvas,
      this.miniGrid,
      this.compactTimer,
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
          break;
        case "home":
          // No leave-collapse here. An island opened with nobody on it folds
          // away on the hold `forceHome()` armed, which is the whole point of
          // the hold; scheduling the 0.12 s grace as well closed it instantly.
          this.expand(State.defaultView());
          break;
        case "coucou":
          // The greeting is nothing but Mochi saying hello, so with the
          // characters off there is no hello to play. Report it finished
          // instead of expanding onto an empty island: the machine then folds
          // to `petit` on its own timer, exactly as it would have once the
          // animation ended.
          if (State.settings.hideCharacters) {
            this.fsm.greetComplete();
          } else {
            this.expand("greeting");
            this.greeting.start();
          }
          break;
      }
      State.notify();
    };
  }

  launch() {
    // A focus or break ran out: open on the timer so the end is visible, not
    // just audible. `alert` gives it the same hold every notification gets.
    FocusTimer.onFinished = () => this.alert("timer");
    // Starting, pausing or stopping repaints at once rather than waiting for
    // the next half-second tick.
    FocusTimer.subscribe(() => {
      this.dirty = true;
      this.ensureRunning();
    });
    this.fsm.launch();
  }

  // ── Mode / view ─────────────────────────────────────────────────────────────

  private setMode(mode: IslandMode) {
    const prev = State.mode;
    if (mode === prev) return;
    State.mode = mode;
    if (mode === "expanded") Sound.play("open");
    if (prev === "expanded") {
      Sound.play("close");
      State.isPinned = false;
      void Bridge.focusWindow(false);
      // A page is anchored flush against the card, so it goes away with it.
      // Here rather than in `collapse()` because this covers every route out of
      // expanded: `pinned` only stops the idle timer, and an alert arriving can
      // drop the pin out from under a page that is still up.
      void Bridge.hidePages();
    }
    if (mode !== "expanded") {
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
    State.lastActivity = performance.now();
    this.homeCollapseAt = null;
    State.notify();
  }

  setView(view: IslandViewName) {
    this.stopSequenceIfLeaving(view);
    if (State.mode !== "expanded") {
      this.fsm.forceHome();
      State.view = view;
      this.animateGeometry(false);
      State.notify();
      return;
    }
    const grew = VIEW_LAYOUTS[view].height >= VIEW_LAYOUTS[State.view].height;
    State.view = view;
    State.lastActivity = performance.now();
    this.animateGeometry(!grew);
    State.notify();
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
    this.fsm.pinned = State.isPinned;
    this.fsm.forceHome();
    this.expand(view);
    // expand() clears the countdown; re-arm it to mirror the FSM's hold, unless
    // the pointer is already on the island, which cancels the hold outright.
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
    this.engine.triggerEmote("happy");
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
        this.setView("note");
        Sound.play("error");
        window.setTimeout(() => this.setView(State.defaultView()), 2400);
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
      this.engine.triggerEmote("happy");
    }
    // The extra second is the grow-back, after which the choose card is up.
    if (since >= PRE_PROGRESS + dur + 1 && State.view === "uploading") {
      this.setView("choose");
    }
  }

  // ── Geometry ────────────────────────────────────────────────────────────────

  private targetSize(): { w: number; h: number; r: number } {
    const { w, h } = islandSize(State.mode, State.view, State.chatHistory.length,
                                State.settings.homeContent,
                                State.replyAttachments.length, State.replyNotice != null,
                                State.homeShowsPlayer);
    const r = State.mode === "expanded" ? EXPANDED_CORNER : ROUNDED_CORNER;
    return { w, h, r };
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
    this.islandEl.style.borderRadius = radiusCss(this.position, r);
    // These follow the island as it resizes, so they belong here rather than in
    // the state-driven DOM sync.
    this.miniGrid.style.left = `${w - 40 - 14.5}px`;
    this.miniGrid.style.top = `${hh / 2 - 14.5}px`;
    this.compactTimer.style.left = `${w - 62}px`;
    this.compactTimer.style.top = `${hh / 2 - 7}px`;
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
    }
  }

  /** Where the island is, which is what decides where a side can be. */
  private anchor() {
    return { edge: edgeOf(this.position), align: alignOf(this.position) };
  }

  /**
   * Rebuilds the ring when what it holds changes, and places it every time the
   * island moves or resizes.
   *
   * Cheap to call: the key is what the buttons are, so an animating island
   * re-places the discs it already has rather than making them again.
   */
  private syncRing() {
    const buttons = ringVisible(State.edgeButtons, State.mode === "expanded");
    const key = buttons.map((b) => `${b.side}:${b.action}`).join("|");
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
    const label = task?.name ?? built?.title ?? button.action;

    // A drawn mark keeps its own colours and gets the Mac's 16 px; a symbol is
    // tinted by the disc and sits a hair smaller, the way it does there.
    const logo = PILL_LOGOS[button.action];
    const mark = logo
      ? logo(16)
      : svg(RING_MARKS[button.action] ?? ICONS.ellipsis, button.action === "agentsDashboard" ? 16 : 15);

    const el = h("button", {
      class: "ring-btn",
      title: label,
      onclick: () => this.pressRingButton(button.action),
    }, mark);
    el.style.setProperty("--tint", tint);
    el.style.width = `${RING_D}px`;
    el.style.height = `${RING_D}px`;
    return el;
  }

  private pressRingButton(action: string) {
    Sound.play("blip");
    switch (action) {
      case "agentsDashboard":
        this.setView("agents");
        return;
      case "clipboard":
        void Bridge.toggleClipboardWindow();
        return;
      case "timer":
        this.setView("timer");
        return;
      case "settings":
        void Bridge.openSettingsWindow();
        return;
      case "site":
        void Bridge.toggleSiteWindow();
        return;
      default:
        // A pill: the same thing clicking it in the island does, so the
        // message pills open what is waiting rather than a card about a socket.
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
    return { x: islandX(this.position, w), y: islandY(this.position, hh), w, h: hh };
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
    const { w, h } = islandSize(State.mode, State.view, State.chatHistory.length,
                                State.settings.homeContent,
                                State.replyAttachments.length, State.replyNotice != null,
                                State.homeShowsPlayer);
    const x = islandX(this.position, w);
    const y = islandY(this.position, h);
    // The ring is part of the island as far as the mouse is concerned: a disc
    // outside this rect would be drawn over a window that lets clicks through,
    // and leaving the island to reach one would fold it away mid-reach.
    const chrome = chromeBounds(
      ringVisible(State.edgeButtons, State.mode === "expanded"), this.anchor(), w, h,
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
    st.left = `${islandX(this.position, WAKE_STRIP_W)}px`;
    st.top = `${islandY(this.position, WAKE_STRIP_H)}px`;
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
      h("span", { text: "Coucou closed unexpectedly and started again." }),
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

  // ── Window collapse (hidden → tiny wake strip, zero polling) ────────────────

  private updateWindowCollapsed() {
    if (this.collapseTimer != null) {
      window.clearTimeout(this.collapseTimer);
      this.collapseTimer = null;
    }
    if (State.mode === "hidden") {
      // Let the island finish retracting, then drop the window to the wake strip:
      // from there the OS delivers no cursor events, so nothing polls at all.
      this.collapseTimer = window.setTimeout(() => {
        this.collapseTimer = null;
        if (State.mode !== "hidden") return;
        this.collapsed = true;
        this.positionWakeStrip();
        void Bridge.setCollapsed(true);
      }, 420);
    } else if (this.collapsed) {
      // Grow the window back before the island animates open.
      this.collapsed = false;
      this.positionWakeStrip();
      void Bridge.setCollapsed(false);
    }
  }

  private clearWakeDwell() {
    if (this.wakeDwell != null) {
      window.clearTimeout(this.wakeDwell);
      this.wakeDwell = null;
    }
  }

  // ── Input ───────────────────────────────────────────────────────────────────

  private wireInput() {
    // The wake strip is the only thing the OS can hit while the island is hidden.
    this.wakeStrip.addEventListener("mouseenter", () => {
      // Off, the window is hidden and this strip is not on screen at all. The
      // guard is for the compositor that ignores hide() anyway — this listener
      // firing is precisely how the old Pause was undone by a stray mouse.
      if (!State.settings.enabled) return;
      // In standby the strip is there but deaf: only a message reopens the
      // island. Rust stops handing it the mouse at all (refresh_click_through);
      // this is the half that holds where the window still delivers events.
      if (State.settings.standby) return;
      Sound.resume();
      if (State.mode !== "hidden") return;
      // At the top the strip is in a dead corner of the screen, so a touch of it
      // is a request. At the bottom it lies across the route to the clock and
      // the tray, and waking costs a full minute of island (petitToHiddenDelay),
      // so down there the pointer has to mean it.
      if (edgeOf(this.position) === "top") {
        this.fsm.mouseEntered();
        return;
      }
      this.clearWakeDwell();
      this.wakeDwell = window.setTimeout(() => {
        this.wakeDwell = null;
        if (State.settings.enabled && !State.settings.standby && State.mode === "hidden") {
          this.fsm.mouseEntered();
        }
      }, WAKE_DWELL_MS);
    });

    this.wakeStrip.addEventListener("mouseleave", () => this.clearWakeDwell());

    this.islandEl.addEventListener("mousedown", (e) => {
      Sound.resume();
      State.lastActivity = performance.now();
      if (State.mode !== "expanded") {
        this.fsm.click();
        return;
      }
      if (this.isBotHit(e.clientX, e.clientY)) {
        this.cancelBotHover();
        this.engine.slap();
      }
    });

    window.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && State.mode === "expanded" && !State.isPinned) this.collapse();
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

    if (inIsland && !this.wasInIsland) {
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
      this.engine.triggerEmote("love");
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
      this.engine.triggerEmote("happy");
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
    const settling =
      this.width.animating || this.height.animating || this.radius.animating;
    const busy = State.mode === "hidden"
      ? settling
      : settling ||
        !this.botCx.settled || !this.botCy.settled || !this.botSize.settled ||
        greetingActive || this.engine.busy || UploadSeq.isActive;

    if (busy) {
      requestAnimationFrame(this.frame);
    } else {
      this.running = false;
      Sound.idle();
    }
  };

  private updateBotTargets() {
    const p = botPosition(State.mode, State.view, this.height.value, State.uploadProgress, State.settings.homeContent, State.homeShowsPlayer);
    this.botCx.target = p.cx;
    this.botCy.target = p.cy;
    this.botSize.target = p.diameter / 0.6;

    const greetingActive = State.mode === "expanded" && State.view === "greeting";
    // The drop canvas draws its own Mochi; two of them would overlap.
    const visible = p.opacity > 0 && !greetingActive && !this.uploadActive && !this.charactersOff;
    this.botCanvas.style.opacity = visible ? "1" : "0";

    if (State.mode === "expanded" && State.view !== "uploading" && !greetingActive
        && !this.uploadActive && !this.charactersOff) {
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

    const focus = State.focusTask;
    this.engine.bodyColor = focus?.isIntegration ? hexToRGB(focus.color) : null;
    // Pushed every frame, like bodyColor above: the user can change characters
    // in Settings while the island is open, and a value read once would go stale.
    this.engine.character = State.characterFor(focus?.id);
    this.engine.particleOverhang = BOT_OVERHANG;
    this.engine.lookX = this.lookX();
    this.engine.lookY = this.lookY();
    if (this.engine.morph > 0.3) {
      this.engine.slotHTarget = State.fileDragOver ? 0.2 : 0;
    } else {
      this.engine.slotHTarget = 0;
      if (this.engine.morph < 0.05) {
        this.engine.slotH = 0;
        this.engine.slotHVel = 0;
      }
    }
    this.engine.update(dt);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, hCss);
    this.engine.draw(ctx, w, hCss);
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
    // Drawn for a pinned alert too: it is counting down like everything else.
    if (State.mode !== "expanded" || this.fsm.heldOpen || this.homeCollapseAt == null) {
      this.countdown.style.width = "0px";
      return;
    }
    const total = this.fsm.holdDurationMs / 1000;
    const windowS = Math.min(10, total * 0.6);
    const remaining = (this.homeCollapseAt - nowMs) / 1000;
    if (remaining <= 0) {
      this.homeCollapseAt = null;
      this.countdown.style.width = "0px";
      return;
    }
    this.countdown.style.width =
      remaining < windowS ? `${Math.max(0, clamp(remaining / windowS, 0, 1) * 160)}px` : "0px";
  }

  // ── DOM sync ────────────────────────────────────────────────────────────────

  private syncDom() {
    const expanded = State.mode === "expanded";
    const greetingActive = expanded && State.view === "greeting";

    this.contentEl.style.opacity = expanded && !greetingActive ? "1" : "0";
    this.contentEl.style.pointerEvents = expanded && !greetingActive ? "auto" : "none";
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
      const wasField = this.lastSyncedView != null && FIELD_VIEWS.has(this.lastSyncedView);
      this.lastSyncedView = State.view;
      if (State.view === "prompt") {
        void Bridge.focusWindow(true);
        window.setTimeout(() => this.views.get("prompt")?.focus?.(), 120);
      } else if (wasField) {
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
    const showGrid = State.mode === "compact" && !counting && !State.settings.hideCharacters;
    this.compactTimer.style.opacity = State.mode === "compact" && counting ? "1" : "0";
    if (State.mode === "compact" && counting) {
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
  }

  /** Applies settings coming from Rust, at boot and on every change. */
  applySettings() {
    // One line covers all 28 sounds, at every call site.
    Sound.setEnabled(State.settings.soundEnabled && State.settings.enabled);
    Sound.setVolume(State.settings.soundVolume);
    this.fsm.notificationHoldDelay = State.settings.autoCloseInterval;
    // Closes every card's Mochi gutter, and puts away the faces inside views
    // that were built before the switch was thrown.
    document.body.classList.toggle("no-mochi", State.settings.hideCharacters);
    this.applyPosition(State.settings.position);
    State.notify();
  }

  /**
   * Moves the island to another corner. Rust moves the window on the same
   * event, so the two land together and the user sees one jump, not two.
   */
  private applyPosition(position: IslandPosition) {
    this.position = position;
    // The stylesheet reads these: anything whose place depends on which edge is
    // the screen edge — the auto-close hairline — keys off them.
    const root = document.documentElement;
    root.dataset.edge = edgeOf(position);
    root.dataset.align = alignOf(position);
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
