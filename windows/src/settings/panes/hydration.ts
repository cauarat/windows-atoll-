// Settings › Hydration — HydrationSettingsView.swift, screen for screen.
//
// The main screen: the "Hydration reminders" box, then — switched on — the
// "Your goal", "Reminders" and "When not to notify" groups, or — off — the way
// into the questions and where the numbers come from. The four screens a goal
// comes from (the questions, the estimate they give, a number of one's own,
// the sources) replace the pane, each under a "‹ Back" link, the way
// HydrationRoute swaps them on the Mac rather than adding sidebar rows.
//
// None of it is in `settings`: hydration keeps its own state in localStorage
// (core/hydrationStore.ts), which this window shares with the island, so a
// change here reaches the island without `save()` and without Rust.

import "./hydration.css";
import { Bridge } from "../../core/bridge";
import { h, clear } from "../../views/dom";
import { t } from "../../core/i18n";
import {
  HYDRATION, hydrationBlock, hydrationClock, hydrationEstimate, hydrationInterval, hydrationTimeline,
  hydrationWindowLength,
  type HydrationAfterGoal, type HydrationAnswers, type HydrationBlock, type HydrationLine, type HydrationPart,
  type HydrationSettings,
} from "../../core/hydration";
import { Hydration } from "../../core/hydrationStore";
import { amountText, durationText, reducedMotion } from "../../core/hydrationText";
import {
  checkbox, divider, groupBox, hint, inlineRow, label, pushButton, segmented, slider, smallSwitch, spacer,
  stack, textField, type Child,
} from "../controls";
import { rerenderPane } from "../shell";

// ── Where the pane is ─────────────────────────────────────────────────────────

type Screen = "main" | "questions" | "estimate" | "manual" | "sources";

/** HydrationRoute.screen: which of the five the pane shows. Kept across
 *  re-renders and pane changes, as the Mac's route singleton is. */
let screen: Screen = "main";

// What each sub-screen keeps in @State on the Mac: fresh whenever the screen
// is opened, and again when the pane comes back after another one was shown.
/** 0 is the introduction; 1…8 are the questions. */
let step = 0;
/** The answers so far. Stored only once the last question is answered, or
 *  as soon as one rules an estimate out. */
let draft: HydrationAnswers = {};
/** The estimate slider's own value, 0 until it is moved. */
let chosen = 0;
/** The manual screen's field and choice. */
let manualText = "";
let manualLimit = false;

/** The pane's root from the last render, and whether it has been off screen
 *  since: leaving the pane drops the sub-screens' state, as the Mac does. */
let root: HTMLElement | null = null;
let away = false;
let watching = false;
const watcher = new MutationObserver(() => {
  if (root && !root.isConnected) away = true;
});

/** The screen's `.keyboardShortcut(.defaultAction)` button: Return presses it. */
let defaultButton: HTMLButtonElement | null = null;
/** Refreshes the main screen in place when the store speaks. */
let refreshMain: (() => void) | null = null;
let unsubscribeStore: (() => void) | null = null;

const LABEL_WIDTH = 150;
const QUESTIONS = 8;

/** Fresh sub-screen state for `next`, as the Mac's views start when they appear. */
function prepare(next: Screen): void {
  if (next === "questions") {
    step = 0;
    draft = {};
  } else if (next === "estimate") {
    chosen = 0;
  } else if (next === "manual") {
    // HydrationManualView.onAppear: somebody's own number is what the field holds.
    const goal = Hydration.goal;
    const own = goal.kind === "target" || goal.kind === "limit";
    manualText = own ? String(goal.ml) : "";
    manualLimit = goal.kind === "limit";
  }
}

/** Puts `next` up, from its first state. */
function go(next: Screen): void {
  screen = next;
  prepare(next);
  redraw();
}

/** Draws the pane again from the top, and gives the keyboard to the new screen. */
function redraw(): void {
  rerenderPane(true);
  const first = root?.querySelector<HTMLElement>(".hyd-option")
    ?? root?.querySelector<HTMLElement>("button:not(:disabled), input:not(:disabled)");
  first?.focus({ preventScroll: true });
}

function show(el: HTMLElement, on: boolean): void {
  el.style.display = on ? "" : "none";
}

/** Writes `value` into a field unless somebody is typing in it. */
function settle(el: HTMLInputElement, value: string): void {
  if (document.activeElement !== el && el.value !== value) el.value = value;
}

// ── Small pieces ──────────────────────────────────────────────────────────────

const SVG_NS = "http://www.w3.org/2000/svg";

/** An SF Symbol the shared set does not have, drawn in currentColor. */
function glyph(markup: string, width: number, height: number, viewBox: string): SVGSVGElement {
  const el = document.createElementNS(SVG_NS, "svg");
  el.setAttribute("viewBox", viewBox);
  el.setAttribute("width", String(width));
  el.setAttribute("height", String(height));
  el.setAttribute("aria-hidden", "true");
  el.setAttribute("class", "sym");
  el.innerHTML = markup;
  return el;
}

const STROKE = 'fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"';
/** chevron.left, 10pt semibold. */
const chevronLeft = () => glyph(`<path ${STROKE} stroke-width="1.5" d="M5 1 L1.5 4.5 L5 8"/>`, 6, 9, "0 0 6 9");
/** minus and plus, as the stepper buttons draw them at body size. */
const minusGlyph = () => glyph(`<path ${STROKE} stroke-width="1" d="M0.5 1h10"/>`, 11, 2, "0 0 11 2");
const plusGlyph = () => glyph(`<path ${STROKE} stroke-width="1" d="M5.5 0.5v10M0.5 5.5h10"/>`, 11, 11, "0 0 11 11");
/** cross.case: a case with its handle and a cross on it. */
const crossCase = () => glyph(
  `<rect ${STROKE} stroke-width="1.1" x="0.75" y="3.25" width="12.5" height="9" rx="2"/>`
  + `<path ${STROKE} stroke-width="1.1" d="M4.75 3.25V2.1q0-1.1 1.1-1.1h2.3q1.1 0 1.1 1.1v1.15"/>`
  + `<path fill="currentColor" d="M6.3 5.3h1.4v1.55h1.55v1.4H7.7v1.55H6.3V8.25H4.75v-1.4H6.3z"/>`,
  14, 13, "0 0 14 13");
/** lock: the shackle over a rounded body. */
const lockGlyph = () => glyph(
  `<rect ${STROKE} stroke-width="1.1" x="0.75" y="5.25" width="8.5" height="7" rx="1.6"/>`
  + `<path ${STROKE} stroke-width="1.1" d="M2.5 5.25V3.7a2.5 2.5 0 0 1 5 0v1.55"/>`,
  10, 13, "0 0 10 13");

/** BackRow: a link-style "‹ Back" on a line of its own. */
function backRow(onBack: () => void): HTMLElement {
  return h("button", { class: "mc-btn link hyd-back", type: "button", onclick: onBack },
    chevronLeft(), h("span", { text: t("Back") }));
}

function text(cls: string, value: string): HTMLElement {
  return h("div", { class: cls, text: value });
}

/** A row of the main screen: the 150px label, then the controls. */
function row(name: string, ...controls: Child[]): HTMLElement {
  return inlineRow(label(name, LABEL_WIDTH), ...controls);
}

/**
 * Controls beside a label that may not all fit on one line. The Mac widens its
 * window to fit them; this window keeps its size, so they wrap — under each
 * other, still in the column right of the label.
 */
function flow(...children: Child[]): HTMLElement {
  const el = inlineRow(...children);
  el.classList.add("hyd-flow");
  return el;
}

/**
 * `.frame(maxWidth: n)`: the control centred in as much of the row as there
 * is, up to `n` px. A row too narrow for the control puts it on the next line
 * rather than squeeze it (the Mac would widen its window instead).
 */
function slotRow(name: string, labelWidth: number, width: number, child: HTMLElement): HTMLElement {
  const el = inlineRow(label(name, labelWidth),
    h("div", { class: "hyd-slot", style: `max-width:${width}px` }, child));
  el.classList.add("hyd-wrap");
  return el;
}

const muted = (value: string) => h("span", { class: "hyd-muted", text: value });

const minutesOf = (clock: string): number | null => {
  const match = /^(\d{1,2}):(\d{2})/.exec(clock);
  return match ? Number(match[1]) * 60 + Number(match[2]) : null;
};

/** DatePicker(.field) for a time of day: the field centred in its 78px frame. */
function timeField(get: () => number, set: (minute: number) => void, aria: string) {
  const input = h("input", { type: "time", class: "hyd-time-input", "aria-label": aria });
  input.value = hydrationClock(get());
  input.addEventListener("change", () => {
    const minute = minutesOf(input.value);
    if (minute !== null) set(minute);
  });
  // A time left half-typed goes back to the one in force.
  input.addEventListener("blur", () => { input.value = hydrationClock(get()); });
  return { el: h("span", { class: "hyd-time" }, input), input };
}

// ── The day, as a row of dots (HydrationTimeline) ─────────────────────────────

function timeline(): { el: HTMLElement; paint(): void } {
  const track = h("div", { class: "hyd-tl-track", role: "img" });
  const start = h("span");
  const summary = h("span");
  const end = h("span");
  const legend = (mark: string, key: string) =>
    h("span", { class: "hyd-tl-key" }, h("i", { class: mark }), t(key));
  const el = h("div", { class: "hyd-tl" },
    track,
    h("div", { class: "hyd-tl-ends" }, start, spacer(), summary, spacer(), end),
    h("div", { class: "hyd-tl-legend" },
      legend("dot", "reminder, if you do not log before"),
      legend("quiet", "quiet"),
      legend("tail", "last hour, no reminders")),
  );

  function paint(): void {
    const s: HydrationSettings = Hydration.settings;
    const hot = Hydration.hot;
    const times = hydrationTimeline(s, hot);
    const first = s.windowStart;
    const length = Math.max(1, hydrationWindowLength(s));
    const every = hydrationInterval(s, hot, 0, false) ?? s.intervalMinutes;
    const pct = (v: number) => `${(v * 100).toFixed(3)}%`;

    clear(track);
    track.append(h("i", { class: "line" }));
    // The quiet hours as a share of the row, clipped to the window.
    if (s.quietEnabled && s.quietStart !== s.quietEnd) {
      let a = s.quietStart;
      let b = s.quietEnd;
      if (b <= a) b += 1440;
      if (b <= first) { a += 1440; b += 1440; }
      const lo = Math.max(first, a);
      const hi = Math.min(first + length, b);
      if (hi > lo) {
        track.append(h("i", {
          class: "quiet",
          style: `left:${pct((lo - first) / length)};width:max(2px, ${pct((hi - lo) / length)})`,
        }));
      }
    }
    track.append(h("i", { class: "tail", style: `width:${pct(Math.min(1, HYDRATION.tailMinutes / length))}` }));
    for (const at of times) track.append(h("i", { class: "dot", style: `left:${pct((at - first) / length)}` }));

    const words = times.length === 0 ? t("No reminder fits in this window")
      : times.length === 1 ? t("1 reminder in the day")
      : t("%lld reminders in the day, one every %@", times.length, durationText(every));
    track.setAttribute("aria-label", words);
    start.textContent = hydrationClock(s.windowStart);
    summary.textContent = words;
    end.textContent = hydrationClock(s.windowEnd);
  }

  paint();
  return { el, paint };
}

// ── Main ──────────────────────────────────────────────────────────────────────

function mainScreen(): Node[] {
  const enabled = checkbox(t("Hydration reminders"), Hydration.enabled, (on) => Hydration.setEnabled(on));
  const top = groupBox({ title: null, gap: 8 },
    enabled,
    hint(t("Mochi reminds you to drink through the day. Nothing leaves this computer.")));

  // Off: the way in.
  const off = inlineRow(
    pushButton(t("Answer the questions"), () => go("questions")),
    pushButton(t("Where the numbers come from"), () => go("sources"), { kind: "link" }),
  );

  // ── Your goal ──
  const noGoal = muted(t("no goal, just logging"));
  const goalValue = h("span", { class: "hyd-goal-value" });
  const goalCaption = h("span", { class: "hyd-goal-caption" });
  const stepGoal = (delta: number) => {
    const goal = Hydration.goal;
    Hydration.setGoal({ kind: goal.kind, ml: Math.min(4000, Math.max(500, goal.ml + delta)) });
  };
  const minus = h("button", {
    class: "hyd-step minus", type: "button", "aria-label": t("Decrease by 100 ml"), onclick: () => stepGoal(-100),
  }, minusGlyph());
  const plus = h("button", {
    class: "hyd-step plus", type: "button", "aria-label": t("Increase by 100 ml"), onclick: () => stepGoal(100),
  }, plusGlyph());
  const stepper = h("span", { class: "hyd-stepper" }, minus, goalValue, plus, goalCaption);
  const questions = pushButton("", () => go("questions"));
  const streak = smallSwitch(Hydration.settings.streakEnabled, (on) => Hydration.setSettings({ streakEnabled: on }),
    { ariaLabel: t("Day streak") });
  const streakRow = row(t("Day streak"), streak,
    hint(t("A missed day spends a rest day; you earn one a week.")));
  streakRow.classList.add("hyd-baseline");
  const name = textField(Hydration.name, (v) => Hydration.setName(v), {
    width: 160, ariaLabel: t("Your name, for the reminder"), onInput: (v) => Hydration.setName(v),
  });

  // On a line of its own, in the controls' column: beside the two buttons it
  // squeezed them.
  const sourcesLink = pushButton(t("Where the numbers come from"), () => go("sources"), { kind: "link" });
  sourcesLink.classList.add("hyd-indent");

  const goalBox = groupBox({ title: t("Your goal"), gap: 10 },
    row(t("Daily goal"), noGoal, stepper),
    row(t("Your answers"), flow(questions, pushButton(t("Set my own number"), () => go("manual")))),
    sourcesLink,
    divider(),
    streakRow,
    row(t("Your name, for the reminder"), name),
  );

  // ── Reminders ──
  const from = timeField(() => Hydration.settings.windowStart, (m) => Hydration.setSettings({ windowStart: m }),
    t("I'm online"));
  const until = timeField(() => Hydration.settings.windowEnd, (m) => Hydration.setSettings({ windowEnd: m }),
    `${t("I'm online")} ${t("until")}`);
  const every = segmented(
    HYDRATION.intervals.map((m) => ({ value: String(m), label: durationText(m) })),
    String(Hydration.settings.intervalMinutes),
    (v) => Hydration.setSettings({ intervalMinutes: Number(v) }),
    { ariaLabel: t("Remind every") });
  const quiet = smallSwitch(Hydration.settings.quietEnabled, (on) => Hydration.setSettings({ quietEnabled: on }),
    { ariaLabel: t("Quiet hours") });
  const quietFrom = timeField(() => Hydration.settings.quietStart, (m) => Hydration.setSettings({ quietStart: m }),
    `${t("Quiet hours")} ${t("from")}`);
  const quietTo = timeField(() => Hydration.settings.quietEnd, (m) => Hydration.setSettings({ quietEnd: m }),
    `${t("Quiet hours")} ${t("to")}`);
  const hot = smallSwitch(Hydration.hot, (on) => Hydration.setHot(on), { ariaLabel: t("Today is hot or I moved more") });
  const hotRow = inlineRow(h("span", { class: "mc-label", text: t("Today is hot or I moved more") }), hot);
  const hotHint = hint(t("Just for today, reminders come a little closer. The suggested portion does not change, and tomorrow it is back to normal."));
  const day = timeline();

  const remindersBox = groupBox({ title: t("Reminders"), gap: 10 },
    row(t("I'm online"), from.el, muted(t("until")), until.el),
    slotRow(t("Remind every"), LABEL_WIDTH, 280, every),
    row(t("Quiet hours"), quiet, muted(t("from")), quietFrom.el, muted(t("to")), quietTo.el),
    hotRow,
    hotHint,
    day.el,
    hint(t("Every log restarts the interval, so nobody who is already drinking gets interrupted. After three unanswered reminders the interval widens by itself.")),
  );

  // ── When not to notify ──
  const focus = checkbox(t("During a focus timer"), Hydration.settings.holdDuringFocus,
    (on) => Hydration.setSettings({ holdDuringFocus: on }));
  const pauses = flow(
    pushButton(t("1 hour"), () => Hydration.pause("hour")),
    pushButton(t("Until tomorrow"), () => Hydration.pause("tomorrow")),
    pushButton(t("Until I turn them back on"), () => Hydration.pause("indefinitely")),
  );
  const paused = flow(
    pushButton(t("Resume reminders"), () => Hydration.resume()),
    h("span", { class: "hyd-note", text: t("Paused. Logging still works.") }),
  );
  const after = segmented<HydrationAfterGoal>(
    [{ value: "stop", label: t("Stop until tomorrow") }, { value: "light", label: t("A light nudge every 3 h") }],
    Hydration.settings.afterGoal,
    (v) => Hydration.setSettings({ afterGoal: v }),
    { ariaLabel: t("When the goal is reached") });

  const quietBox = groupBox({ title: t("When not to notify"), gap: 10 },
    focus,
    row(t("Pause reminders"), pauses, paused),
    slotRow(t("When the goal is reached"), LABEL_WIDTH, 340, after),
  );

  const refresh = () => {
    const s = Hydration.settings;
    const goal = Hydration.goal;
    const on = Hydration.enabled;
    enabled.set(on);
    show(off, !on);
    for (const box of [goalBox, remindersBox, quietBox]) show(box, on);

    show(noGoal, goal.kind === "none");
    show(stepper, goal.kind !== "none");
    goalValue.textContent = amountText(goal.ml);
    goalCaption.textContent = goal.kind === "estimated" ? t("starting estimate, yours to adjust")
      : goal.kind === "target" ? t("your own number")
      : t("a limit not to pass");
    questions.setText(Hydration.answers ? t("Redo the questions") : t("Answer the questions"));
    streak.set(s.streakEnabled);
    settle(name, Hydration.name);

    settle(from.input, hydrationClock(s.windowStart));
    settle(until.input, hydrationClock(s.windowEnd));
    every.set(String(s.intervalMinutes));
    quiet.set(s.quietEnabled);
    settle(quietFrom.input, hydrationClock(s.quietStart));
    settle(quietTo.input, hydrationClock(s.quietEnd));
    // "Today is hot" has no place beside a number that may be a limit.
    show(hotRow, goal.kind !== "limit");
    show(hotHint, goal.kind !== "limit");
    hot.set(Hydration.hot);
    day.paint();

    focus.set(s.holdDuringFocus);
    show(pauses, !Hydration.paused);
    show(paused, Hydration.paused);
    after.set(s.afterGoal);
  };
  refresh();
  refreshMain = refresh;

  return [top, off, goalBox, remindersBox, quietBox];
}

// ── The questions ─────────────────────────────────────────────────────────────

/**
 * The eight questions, in the order they are asked — HydrationWords and
 * HydrationQuestionsView.question(_:). English, translated where drawn.
 */
const QUESTION_TABLE: {
  key: keyof HydrationAnswers; title: string; hint: string; options: [value: string, label: string][];
}[] = [
  {
    key: "age", title: "How old are you?",
    hint: "In ranges, to ask no more than needed. The estimate was made for adults.",
    options: [["under18", "Under 18"], ["from18to39", "18 to 39"], ["from40to64", "40 to 64"],
              ["over65", "65 or older"], ["skipped", "I'd rather not say"]],
  },
  {
    key: "reference", title: "Which reference should I use?",
    hint: "EFSA, the US National Academies and NHMRC publish separate values by sex. With no answer, I use a point between the two.",
    options: [["female", "Female"], ["male", "Male"], ["skipped", "I'd rather not say"]],
  },
  {
    key: "weight", title: "What is your weight?",
    hint: "Also in ranges. It is a small adjustment, not a millilitres-per-kilo sum.",
    options: [["under55", "Under 55 kg"], ["from55to85", "55 to 85 kg"], ["over85", "Over 85 kg"],
              ["skipped", "I'd rather not say"]],
  },
  {
    key: "activity", title: "How would you describe your physical activity?",
    hint: "Think of an ordinary week.",
    options: [["still", "I spend most of the day without moving much"], ["light", "I walk or move a little every day"],
              ["moderate", "I train a few times a week"], ["intense", "I train hard almost every day"]],
  },
  {
    key: "sweat", title: "Do you sweat a lot, exercising or day to day?",
    hint: "Sweat varies a lot from person to person.",
    options: [["little", "A little"], ["some", "Somewhat"], ["lots", "A lot"]],
  },
  {
    key: "climate", title: "What is the weather like where you spend most of the day?",
    hint: "You answer for yourself: Notchy does not look up any weather service.",
    options: [["mild", "Mild, or air-conditioned"], ["hot", "Hot"], ["intenseHeat", "Frequent spells of intense heat"]],
  },
  {
    key: "pregnancy", title: "Are you pregnant or breastfeeding?",
    hint: "In these phases the need for fluids changes and deserves its own guidance.",
    options: [["no", "No"], ["pregnant", "I am pregnant"], ["breastfeeding", "I am breastfeeding"],
              ["skipped", "I'd rather not say"]],
  },
  {
    key: "health", title: "Any health condition or medical guidance about fluids?",
    hint: "If any option applies, the goal is up to you and the professional who looks after you.",
    options: [["none", "None of these"], ["organs", "Kidney, heart or liver disease"],
              ["medication", "I take medicine that affects fluids, such as a diuretic"],
              ["guidance", "I was told to limit or increase fluids"], ["other", "Another health condition"],
              ["skipped", "I don't know, or I'd rather not say"]],
  },
];

const FOOTNOTE = "An estimate for healthy adults. Not medical advice.";

function introScreen(): Node[] {
  const begin = pushButton(t("Begin"), () => {
    draft = {};
    step = 1;
    redraw();
  }, { kind: "prominent" });
  defaultButton = begin;
  const buttons = inlineRow(begin, pushButton(t("I already have a goal"), () => {
    Hydration.setAnswers(null);
    go("manual");
  }));
  buttons.classList.add("hyd-push-down");
  return [
    backRow(() => go("main")),
    text("hyd-title", t("Let's find a starting point")),
    text("hyd-text", t("Eight quick questions. With them I suggest a daily fluid goal to start from. It is an estimate, not a prescription: needs change from person to person and from one day to the next, and you can adjust the number whenever you like.")),
    h("div", { class: "hyd-labels" },
      h("div", { class: "hyd-labelled" }, h("span", { class: "hyd-icon case" }, crossCase()),
        h("span", { text: t("Notchy is not a medical tool and does not replace professional advice.") })),
      h("div", { class: "hyd-labelled" }, h("span", { class: "hyd-icon lock" }, lockGlyph()),
        h("span", { text: t("Your answers stay on this computer. Every question can be skipped.") }))),
    buttons,
  ];
}

function questionScreen(): Node[] {
  const q = QUESTION_TABLE[step - 1];
  const picked = (draft as Record<string, string | undefined>)[q.key];
  const choose = (value: string) => {
    (draft as Record<string, string>)[q.key] = value;
    if (hydrationBlock(draft)) {
      // An answer that rules an estimate out ends the questions there.
      Hydration.setAnswers(draft);
      // An estimate accepted earlier does not survive it.
      if (Hydration.goal.kind === "estimated") Hydration.setGoal({ kind: "none", ml: 0 });
      go("manual");
      return;
    }
    if (step < QUESTIONS) {
      step += 1;
      redraw();
    } else {
      Hydration.setAnswers(draft);
      go("estimate");
    }
  };
  const progress = t("%lld of %lld", step, QUESTIONS);
  return [
    h("div", { class: "hyd-progress-row" },
      backRow(() => { step -= 1; redraw(); }),
      h("div", {
        class: "hyd-progress", role: "progressbar", "aria-label": progress,
        "aria-valuemin": "0", "aria-valuemax": String(QUESTIONS), "aria-valuenow": String(step),
      }, h("i", { style: `width:${(step / QUESTIONS) * 100}%` })),
      h("span", { class: "hyd-count", text: progress })),
    stack(4,
      text("hyd-question", t(q.title)),
      text("hyd-sub", t(q.hint))),
    h("div", { class: "hyd-options", role: "group", "aria-label": t(q.title) },
      ...q.options.map(([value, words]) => h("button", {
        class: picked === value ? "hyd-option selected" : "hyd-option", type: "button",
        "aria-pressed": String(picked === value), text: t(words), onclick: () => choose(value),
      }))),
    text("hyd-foot", t(FOOTNOTE)),
  ];
}

// ── The estimate ──────────────────────────────────────────────────────────────

function partLabel(part: HydrationPart): string {
  switch (part.kind) {
    case "base":
      return part.value === "female" ? t("Starting point, female reference")
        : part.value === "male" ? t("Starting point, male reference")
        : t("Starting point, between the two references");
    case "weight":
      return part.value === "under55" ? t("Weight under 55 kg") : t("Weight over 85 kg");
    case "activity":
      return part.value === "light" ? t("Light movement every day")
        : part.value === "moderate" ? t("Training a few times a week")
        : t("Hard training almost every day");
    case "sweat":
      return part.value === "some" ? t("Sweats somewhat") : t("Sweats a lot");
    case "climate":
      return part.value === "hot" ? t("Hot weather") : t("Frequent intense heat");
    case "cap":
      return t("Ceiling on the activity, sweat and weather adjustments");
    case "over65":
      return t("65 or older: does not change the number");
  }
}

/** HydrationWords.value: "1.8 L" where the sum starts, "+300 ml" / "−200 ml" / "0 ml" for what moves it. */
function lineValue(line: HydrationLine): string {
  if (line.part.kind === "base") return amountText(line.ml);
  if (line.ml === 0) return "0 ml";
  return `${line.ml > 0 ? "+" : "−"}${Math.abs(line.ml)} ml`;
}

/** The liquid's surface when the glass is empty, and how far it rises when full. */
const LEVEL_EMPTY = 107.6;
const LEVEL_TRAVEL = 93.6;
const CAVITY = "M12.6 8 L87.4 8 L77.9 104.6 Q77.2 111.6 70 111.6 L30 111.6 Q22.8 111.6 22.1 104.6 Z";
let glassSerial = 0;

/**
 * HydrationGlass at 60px, as the island draws it (views/hydration.ts): the
 * tumbler, the liquid clipped to its cavity, a wave that stands up when the
 * level moves and lies down again.
 */
function glass(): { el: HTMLElement; set(level: number): void } {
  const id = `hyd-glass-${++glassSerial}`;
  const wave = (cls: string, opacity: string, d: string) =>
    `<g class="${cls}"><path fill="#22D3EE" fill-opacity="${opacity}" d="${d}"/></g>`;
  const el = h("div", { class: "hyd-glass still", "aria-hidden": "true" });
  el.innerHTML = `
<svg viewBox="0 0 100 120" width="100%" height="100%">
  <defs>
    <clipPath id="${id}-c"><path d="${CAVITY}"/></clipPath>
    <linearGradient id="${id}-g" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#22D3EE" stop-opacity=".95"/>
      <stop offset="1" stop-color="#22D3EE" stop-opacity=".6"/>
    </linearGradient>
  </defs>
  <path d="${CAVITY}" fill="#fff" fill-opacity=".05"/>
  <g clip-path="url(#${id}-c)">
    <g class="hyd-glass-level">
      <rect x="-10" y="4" width="120" height="150" fill="url(#${id}-g)"/>
      <rect x="-10" y="4" width="120" height="1.3" fill="#fff" fill-opacity=".3"/>
      <g transform="translate(0 4)">
        <g class="hyd-glass-amp">
          ${wave("hyd-glass-wave back", ".45", "M-50 -6.5 q12.5 -3.4 25 0 t25 0 t25 0 t25 0 t25 0 t25 0 t25 0 t25 0 t25 0 V0.5 H-50 Z")}
          ${wave("hyd-glass-wave", ".96", "M-50 -4 q12.5 -3.2 25 0 t25 0 t25 0 t25 0 t25 0 t25 0 t25 0 t25 0 t25 0 V0.5 H-50 Z")}
        </g>
      </g>
    </g>
  </g>
  <path d="M9 6 L19.6 105.5 Q20.7 115 30.5 115 L69.5 115 Q79.3 115 80.4 105.5 L91 6" fill="none" stroke="#fff" stroke-opacity=".36" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M9 6 L91 6" fill="none" stroke="#fff" stroke-opacity=".16" stroke-width="2.4" stroke-linecap="round"/>
  <path d="M19.5 18 L25.8 82" fill="none" stroke="#fff" stroke-opacity=".24" stroke-width="3.2" stroke-linecap="round"/>
  <path d="M83.2 15 L81.6 31" fill="none" stroke="#fff" stroke-opacity=".14" stroke-width="2.4" stroke-linecap="round"/>
</svg>`;

  let shown: number | null = null;
  let stirring: number | undefined;
  let settling: number | undefined;
  return {
    el,
    set(level: number) {
      const next = Math.min(1, Math.max(0, level));
      el.style.setProperty("--hyd-y", `${(LEVEL_EMPTY - LEVEL_TRAVEL * next).toFixed(2)}px`);
      if (shown === null) {
        // Where the glass starts is not a change: no pour on the way in.
        shown = next;
        requestAnimationFrame(() => el.classList.remove("still"));
        return;
      }
      if (next === shown) return;
      shown = next;
      if (reducedMotion()) return;
      window.clearTimeout(stirring);
      window.clearTimeout(settling);
      el.classList.add("agitated", "settling");
      stirring = window.setTimeout(() => el.classList.remove("agitated"), 1500);
      settling = window.setTimeout(() => el.classList.remove("settling"), 3300);
    },
  };
}

function estimateScreen(): Node[] {
  const estimate = hydrationEstimate(Hydration.answers ?? {});
  const ml = () => (chosen > 0 ? chosen : estimate.totalML);
  const tumbler = glass();
  const about = text("hyd-big", "");
  const start = pushButton("", () => {
    Hydration.setGoal({ kind: "estimated", ml: ml() });
    Hydration.setEnabled(true);
    go("main");
  }, { kind: "prominent" });
  defaultButton = start;
  const write = () => {
    tumbler.set(0.25 + ((ml() - HYDRATION.minimumML) / 1800) * 0.6);
    about.textContent = t("about %@", amountText(ml()));
    start.setText(t("Start with %@", amountText(ml())));
  };
  const adjust = slider(ml(), {
    min: HYDRATION.minimumML, max: HYDRATION.maximumML, step: 100, ticks: true, ariaLabel: t("Adjust, if you prefer"),
  }, (v) => {
    chosen = v;
    write();
  });
  write();

  const buttons = inlineRow(start, pushButton(t("Redo"), () => go("questions")), spacer(),
    pushButton(t("Where the numbers come from"), () => go("sources"), { kind: "link" }));
  return [
    backRow(() => go("questions")),
    h("div", { class: "hyd-estimate" },
      h("div", { class: "hyd-glass-tile" }, tumbler.el),
      stack(2,
        text("hyd-sub", t("Your starting estimate")),
        about,
        text("hyd-sub", t("of fluids a day, counting everything you drink")))),
    inlineRow(
      h("span", { class: "hyd-sub", text: t("Adjust, if you prefer") }),
      h("span", { class: "hyd-range-end", text: amountText(HYDRATION.minimumML) }),
      adjust,
      h("span", { class: "hyd-range-end", text: amountText(HYDRATION.maximumML) })),
    groupBox({ title: t("How I got to this number"), gap: 6 },
      ...estimate.lines.map((line) => h("div", { class: "hyd-line" },
        h("span", { text: partLabel(line.part) }), spacer(), h("span", { class: "n", text: lineValue(line) })))),
    text("hyd-sub", t("It is a starting point, not a rule. Other drinks and food count too, and there is no reason to force fluids or to go past the goal. Day to day, thirst and pale-yellow urine are good general signs, but they do not replace medical advice.")),
    buttons,
    text("hyd-foot", t(FOOTNOTE)),
  ];
}

// ── A number of one's own ─────────────────────────────────────────────────────

/** What "You marked" shows for each answer that rules an estimate out. */
const BLOCK_REASON: Record<HydrationBlock, string> = {
  minor: "Under 18",
  pregnant: "I am pregnant",
  breastfeeding: "I am breastfeeding",
  pregnancySkipped: "Preferred not to answer about pregnancy or breastfeeding",
  organs: "Kidney, heart or liver disease",
  medication: "I take medicine that affects fluids, such as a diuretic",
  guidance: "I was told to limit or increase fluids",
  otherCondition: "Another health condition",
  healthSkipped: "Not sure, or preferred not to answer about health",
};

function manualScreen(): Node[] {
  const answers = Hydration.answers;
  const block = answers ? hydrationBlock(answers) : null;
  const minor = block === "minor";
  // `Int(text.filter(\.isNumber)) ?? 0`: the digits typed, whatever is around them.
  const typed = () => {
    const digits = manualText.replace(/\D/g, "");
    return digits.length > 0 && digits.length <= 15 ? Number(digits) : 0;
  };

  const saveButton = pushButton(t("Save reference"), () => {
    if (typed() < 100) return;
    Hydration.setGoal({ kind: manualLimit ? "limit" : "target", ml: Math.min(6000, Math.max(100, typed())) });
    Hydration.setEnabled(true);
    go("main");
  }, { kind: "prominent" });
  defaultButton = saveButton;
  const field = textField(manualText, () => {}, {
    width: 90, ariaLabel: t("Your reference for the day"),
    onInput: (v) => {
      manualText = v;
      saveButton.setDisabled(typed() < 100);
    },
  });
  field.inputMode = "numeric";
  saveButton.setDisabled(typed() < 100);
  const kind = segmented<"target" | "limit">(
    [{ value: "target", label: t("a target to reach") }, { value: "limit", label: t("a limit not to pass") }],
    manualLimit ? "limit" : "target",
    (v) => { manualLimit = v === "limit"; },
    { ariaLabel: t("This number is") });

  const nodes: Node[] = [
    backRow(() => go("main")),
    text("hyd-title", minor ? t("This estimate was made for adults") : t("Here, you set the number")),
  ];
  if (block) {
    nodes.push(text("hyd-text", minor
      ? t("For anyone under 18 the need for fluids is different, so I do not suggest a number. You can still use the glass and the reminders with a goal agreed with a guardian or a health professional.")
      : t("From your answers, it is better not to use an automatic estimate. The right amount of fluids, in your case, is the one recommended by the health professional who looks after you.")));
    nodes.push(inlineRow(
      h("span", { class: "hyd-sub", text: t("You marked") }),
      h("span", { class: "hyd-chip", text: t(BLOCK_REASON[block]) })));
  }
  nodes.push(
    groupBox({ title: null, gap: 10 },
      inlineRow(label(t("Your reference for the day"), 170), field, muted("ml")),
      slotRow(t("This number is"), 170, 320, kind),
      hint(t("With a limit, the glass shows how much still fits in the day and reminders stop before you reach it. You can change the number whenever you like."))),
    text("hyd-sub", t("No celebration for volume: the streak counts the days you logged, not how much you drank.")),
    inlineRow(saveButton, pushButton(t("Just log, no goal"), () => {
      Hydration.setGoal({ kind: "none", ml: 0 });
      Hydration.setEnabled(true);
      go("main");
    })),
    text("hyd-foot", t("Notchy is not a medical tool and does not replace professional advice.")),
  );
  return nodes;
}

// ── Where the numbers come from ───────────────────────────────────────────────

/** The five references, with what each measures. Millilitres, so `amountText`
 *  writes them with the reader's decimal separator. */
const SOURCES: {
  name: string; url: string; note: string; measures: string; women?: number; men?: number; both?: string;
}[] = [
  {
    name: "EFSA, Europe", url: "https://www.efsa.europa.eu/sites/default/files/2017_09_DRVs_summary_report.pdf",
    note: "2010 opinion, read in the 2017 summary report. For mild weather and moderate activity.",
    measures: "Total water: drinks and food", women: 2000, men: 2500,
  },
  {
    name: "National Academies, USA", url: "https://www.nationalacademies.org/read/10925/chapter/6",
    note: "Dietary Reference Intakes, 2005. Total water is 2.7 L and 3.7 L.",
    measures: "Drinks only, within total water", women: 2200, men: 3000,
  },
  {
    name: "NHMRC, Australia and New Zealand", url: "https://www.healthdirect.gov.au/drinking-water-and-your-health",
    note: "2006 values, checked in two secondary sources; the original page did not open.",
    measures: "Fluids, without food", women: 2100, men: 2600,
  },
  {
    name: "NHS, United Kingdom",
    url: "https://www.nhs.uk/live-well/eat-well/food-guidelines-and-food-labels/water-drinks-nutrition/",
    note: "Reviewed in 2023. The page itself calls the number “just a guide”.",
    measures: "Drinks: water, milk, tea, coffee", both: "6 to 8 glasses",
  },
  {
    name: "Guia Alimentar, Brazil's Ministry of Health",
    url: "https://bvsms.saude.gov.br/bvs/publicacoes/guia_alimentar_populacao_brasileira_2ed.pdf",
    note: "2014. It says the need varies a lot and asks you to heed the first signs of thirst.",
    measures: "Water, with no fixed recommendation", both: "2 L for some; 3 to 4 L or more for others",
  },
];

/** A GroupBox of short points, each after a small grey dot. */
function bullets(title: string, items: string[]): HTMLElement {
  return groupBox({ title: t(title), gap: 7 },
    ...items.map((item) => h("div", { class: "hyd-bullet" }, h("i"), h("span", { text: t(item) }))));
}

function sourcesScreen(): Node[] {
  const table = groupBox({ title: null, gap: 9 },
    h("div", { class: "hyd-src head" },
      h("span", { text: t("Reference") }), h("span", { class: "what", text: t("What it measures") }),
      h("span", { class: "n", text: t("Women") }), h("span", { class: "n", text: t("Men") })));
  for (const source of SOURCES) {
    const link = h("a", { href: source.url, text: t(source.name) });
    // The page belongs in the browser, as every link out of Settings goes.
    link.addEventListener("click", (e) => {
      e.preventDefault();
      void Bridge.openUrl(source.url);
    });
    const entry = h("div", { class: "hyd-src" },
      h("span", { class: "who" }, link, h("span", { class: "note", text: t(source.note) })),
      h("span", { class: "what", text: t(source.measures) }));
    if (source.both) entry.append(h("span", { class: "both", text: t(source.both) }));
    else entry.append(h("span", { class: "n", text: amountText(source.women ?? 0) }),
                      h("span", { class: "n", text: amountText(source.men ?? 0) }));
    table.box.append(divider(), entry);
  }

  return [
    backRow(() => go("main")),
    text("hyd-title", t("Where the numbers come from")),
    text("hyd-text", t("There is no single number of water per day. These are the public references behind the estimate, with what each one measures: some also count the water in food, others only what you drink.")),
    table,
    bullets("Where they agree", [
      "The need varies from person to person, and heat, activity, pregnancy and breastfeeding raise it.",
      "The “8 glasses” rule has no study behind it for healthy, sedentary adults in mild weather (Valtin, 2002).",
      "Pale-yellow urine is the everyday sign (NHS), with limits: medicines, supplements and food change the colour, and older people may feel less thirst.",
      "Too much is harmful too. EFSA and the National Academies point to risk when intake goes past what the kidneys clear, about 0.7 to 1 L an hour.",
    ]),
    bullets("How Notchy uses this", [
      "The starting point is for drinks: 1.8 L on the female reference, 2.3 L on the male one and 2.0 L with no answer. With training a few times a week the estimate reaches 2.1 L and 2.6 L, where NHMRC and the National Academies place fluids.",
      "The additions for activity, sweat and weather (up to 800 ml together) are a product heuristic. The sources say the need rises, but give no table for day-to-day life.",
      "The largest portion is 500 ml and reminders are never less than 30 minutes apart, far below the limit of 0.7 to 1 L an hour. There is no “catching up”.",
      "No automatic estimate for kidney, heart or liver disease or for diuretics, cases where healthdirect, the NHS and the American Heart Association say to talk to a professional. The same goes for pregnancy and breastfeeding, where each reference gives a different addition.",
    ]),
    bullets("Limits of this review", [
      "The WHO was left out. The text usually cited (Grandjean, 2004) is a background draft marked “not for citation”, not a recommendation by the organisation.",
      "On exercise, the 2017 NATA position was read (do not drink more than you lose in training) and only the summary of the 2007 ACSM position.",
      "These numbers are a product heuristic and have not been reviewed by a health professional.",
    ]),
  ];
}

// ── The pane ──────────────────────────────────────────────────────────────────

/** Return presses the screen's default button, as `.keyboardShortcut(.defaultAction)` does. */
function onKey(e: KeyboardEvent): void {
  if (e.key !== "Enter" || e.defaultPrevented || e.isComposing || e.repeat) return;
  const button = defaultButton;
  if (!button || !button.isConnected || button.disabled) return;
  // A focused button, link or choice answers Return itself.
  const target = e.target as Element | null;
  if (target?.closest?.("button, a, select, textarea, [role=radio], [role=switch]")) return;
  e.preventDefault();
  button.click();
}

/**
 * "Answer the questions" on the island: puts the questions' first screen up.
 * main.ts calls this from `Hydration.onSetupAsked` and then selects this pane.
 */
export function askHydrationSetup(): void {
  screen = "questions";
  prepare("questions");
}

/** The Hydration pane. */
export function render(): Node[] {
  if (!watching) {
    watching = true;
    watcher.observe(document.body, { childList: true, subtree: true });
    document.addEventListener("keydown", onKey);
  }
  // Back after another pane: the sub-screen starts over, the screen stays.
  if (away) prepare(screen);
  away = false;
  defaultButton = null;
  refreshMain = null;

  let nodes: Node[] = [];
  let gap = 12;
  switch (screen) {
    case "main": nodes = mainScreen(); gap = 14; break;
    case "questions":
      if (step > 0) { nodes = questionScreen(); gap = 14; } else nodes = introScreen();
      break;
    case "estimate": nodes = estimateScreen(); break;
    case "manual": nodes = manualScreen(); break;
    case "sources": nodes = sourcesScreen(); break;
  }
  root = stack(gap, ...nodes);
  root.classList.add("hyd");

  // One subscription, however many times the pane is drawn. Only the main
  // screen shows the store; the others hold a draft of their own.
  unsubscribeStore?.();
  unsubscribeStore = Hydration.subscribe(() => {
    if (root?.isConnected) refreshMain?.();
  });
  return [root];
}
