// The dictation card — DictationCardView.swift: what is being heard, then the
// text to edit, copy or paste.
//
// The notification cards' shape: the 108 px Mochi gutter, a who line, the
// body, a row of buttons, in hydration's 240 because a dictation is a few
// lines and the editor needs them. The red pill records and stops. The timer
// and the meter move only while this card is the one on screen and recording.

import { h, svg, dot } from "./dom";
import { ICONS } from "./icons";
import { btn, card, type ViewActions, type ViewHost } from "./views";
import { washRGBA, type Wash } from "../core/layout";
import { DICTATION, HOLD_KEYS, modelName, type ServiceInfo } from "../core/dictation";
import { Dictation, type Failure, type Phase } from "../island/dictation";
import { Bridge } from "../core/bridge";
import { State } from "../core/state";
import { t } from "../core/i18n";

const ON_LINUX = /\b(Linux|X11)\b/.test(navigator.userAgent);

const DOT: Record<Phase, string> = {
  idle: "#8E939C", starting: "#F5A524", recording: "#F43F5E", finishing: "#F5A524", done: "#34D399", failed: "#F4505E",
};

function clock(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

function failureTitle(f: Failure | null): string {
  switch (f?.kind) {
    case "microphoneDenied": return t("The microphone is blocked. Check Privacy settings → Microphone.");
    case "microphoneUnavailable": return t("No microphone is available.");
    case "invalidAddress": return t("The service address in Settings is not a valid address.");
    case "serviceOffline": return t("The transcription service is not running at %@.", State.settings.dictationServiceUrl);
    case "connectionLost": return t("The connection to the transcription service dropped. What was heard is kept.");
    case "timedOut": return t("The transcription service took too long to answer.");
    case "service":
      if (f.code === "model_loading") return t("The model is still loading. Try again in a few seconds.");
      if (f.code === "model_failed" || f.code === "provider_unavailable") return t("The transcription service cannot run the model.");
      return t("The transcription service refused the recording.");
    default: return t("Something went wrong.");
  }
}

/** Where the start script is, in this system's own path. */
function startHint(): string {
  return ON_LINUX
    ? t("Start it with dictation-service/scripts/start.sh, then try again.")
    : t("Start it with dictation-service\\scripts\\start.ps1, then try again.");
}

export function buildDictation(actions: ViewActions): ViewHost {
  const whoDot = dot(DOT.idle, 7);
  const status = h("span", { class: "dct-status" });
  const who = h("div", { class: "dct-who" },
    whoDot,
    h("b", { text: t("Dictation") }),
    // The language the model is asked for, as the service names it: not a sentence to translate.
    h("span", { text: `${DICTATION.languageLabel} · ${DICTATION.language}` }),
    h("span", { class: "dct-fill" }),
    status);

  const line = h("div", { class: "dct-line" });
  const sub = h("div", { class: "dct-sub" });
  const kept = h("div", { class: "dct-kept" });
  const editor = h("textarea", { class: "dct-editor", spellcheck: "true", rows: "3" }) as HTMLTextAreaElement;
  // Focus by click only, as the reply field: taking it on arrival would pull
  // the cursor out of the app being dictated into.
  editor.addEventListener("mousedown", () => void actions.focusField(true));
  editor.addEventListener("focus", () => actions.setPinned(true));
  editor.addEventListener("blur", () => {
    actions.setPinned(false);
    void actions.focusField(false);
  });
  editor.addEventListener("input", () => { Dictation.draft = editor.value; });
  const body = h("div", { class: "dct-body" }, line, sub, editor, kept);

  const recordIcon = h("span", { class: "dct-rec-icon" });
  const recordLabel = h("span", {});
  const record = h("button", { class: "btn dct-record", onclick: () => Dictation.toggleRecording() }, recordIcon, recordLabel);
  const meter = h("div", { class: "dct-meter", "aria-hidden": "true" },
    ...Array.from({ length: 5 }, () => h("i", {})));
  const copy = btn(t("Copy"), "primary", () => void Dictation.copyDraft());
  const paste = btn(t("Paste in app"), "secondary", () => {
    // The editor may have the keyboard; the app the text is for gets it back first.
    void actions.focusField(false);
    window.setTimeout(() => void Dictation.pasteDraft(), 150);
  });
  const discard = btn(t("Discard"), "secondary", () => Dictation.discard());
  const copyKept = btn(t("Copy"), "secondary", () => void Dictation.copyDraft());
  const openSettings = btn(t("Open Settings"), "secondary", () => void Bridge.dictationMicrophoneSettings());
  const checkAgain = btn(t("Check again"), "secondary", () => void Dictation.refreshService());
  const model = h("span", { class: "dct-model" });
  const controls = h("div", { class: "dct-controls" },
    record, meter, copy, paste, discard, copyKept, openSettings, checkAgain, h("span", { class: "dct-fill" }), model);

  const wrap = h("div", { class: "dct-wrap" }, who, body, controls);
  const cardEl = card("pink", wrap);
  const el = h("div", { class: "view dictation" }, cardEl);

  const show = (node: HTMLElement, on: boolean) => { node.style.display = on ? "" : "none"; };
  const setWash = (wash: Wash) => {
    cardEl.classList.toggle("wash", wash !== null);
    if (wash) cardEl.style.setProperty("--wash", washRGBA(wash));
  };
  const onScreen = () => State.view === "dictation" && State.mode === "expanded";

  let shownSecond = -1;
  const paintClock = () => {
    const since = Dictation.recordingSince;
    if (since === null) return;
    const second = Math.floor((Date.now() - since) / 1000);
    if (second === shownSecond) return;
    shownSecond = second;
    status.textContent = t("Recording %@", clock(Date.now() - since));
  };

  const paintMeter = () => {
    const bars = meter.children;
    for (let i = 0; i < bars.length; i++) {
      const lit = i < Dictation.level * 5 + 0.2;
      const bar = bars[i] as HTMLElement;
      bar.classList.toggle("lit", lit);
      bar.style.height = `${5 + (i % 3) * 3 + (lit ? Dictation.level * 8 : 0)}px`;
    }
  };

  const serviceInfo = (): ServiceInfo | null => {
    const s = Dictation.service;
    return Dictation.transcript.service ?? ("health" in s ? s.health.info : null);
  };

  const offline = () => {
    const kind = Dictation.service.kind;
    return kind === "offline" || kind === "invalidAddress" || kind === "notTheService";
  };

  function sync() {
    const phase = Dictation.phase;
    whoDot.style.background = phase === "idle" && offline() ? "#F5A524" : DOT[phase];
    setWash(phase === "recording" ? "pink" : phase === "failed" ? "red" : phase === "done" ? "soft" : null);

    // The status on the right of the who line.
    shownSecond = -1;
    switch (phase) {
      case "idle": status.textContent = offline() ? t("Service offline") : t("Ready"); break;
      case "starting": status.textContent = t("Connecting…"); break;
      case "recording": status.textContent = t("Recording"); paintClock(); break;
      case "finishing": status.textContent = t("Transcribing…"); break;
      case "failed": status.textContent = t("Error"); break;
      case "done":
        status.textContent = Dictation.outcome === "pasted" ? t("Pasted where the cursor was")
          : Dictation.outcome === "copied" ? t("Copied — Ctrl+V pastes it")
          : t("Done");
        break;
    }

    // The body.
    const text = Dictation.transcript.text;
    show(editor, false);
    show(kept, false);
    sub.textContent = "";
    line.className = "dct-line";
    switch (phase) {
      case "idle":
        if (offline()) {
          line.textContent = t("The transcription service is not running at %@.", State.settings.dictationServiceUrl);
          line.classList.add("strong");
          sub.textContent = startHint();
        } else {
          line.textContent = t("Click Record and speak, then Stop.");
          line.classList.add("strong");
          const key = HOLD_KEYS.find((k) => k.id === State.settings.dictationHoldKey);
          // No held key on Linux in this version (dictation_keys.rs).
          if (!ON_LINUX && key && key.id !== "off") {
            sub.textContent = t("Or hold %@ in any app, speak, and let go: the text goes where the cursor is.", t(key.title));
          }
        }
        break;
      case "starting":
        line.textContent = t("Connecting to the transcription service…");
        break;
      case "recording":
      case "finishing":
        if (text) {
          // The end of what was heard, as the Mac's head truncation shows it.
          line.textContent = text.length > 220 ? `…${text.slice(-220)}` : text;
          line.classList.add("heard", phase === "finishing" ? "settling" : "live");
        } else if (phase === "finishing") {
          line.textContent = t("Transcribing what you said…");
        } else if (Dictation.transcript.service && !Dictation.transcript.service.streaming) {
          line.textContent = t("Listening… This model writes the text when you stop.");
        } else {
          line.textContent = t("Listening…");
        }
        break;
      case "done":
        if (!Dictation.draft && document.activeElement !== editor) {
          line.textContent = t("Nothing was heard. Check the microphone and try again.");
        } else {
          line.textContent = "";
          show(editor, true);
          if (document.activeElement !== editor && editor.value !== Dictation.draft) editor.value = Dictation.draft;
        }
        break;
      case "failed": {
        const f = Dictation.failure;
        line.textContent = failureTitle(f);
        line.classList.add("strong");
        if (f?.kind === "service" && f.message) sub.textContent = f.message;
        else if (f?.kind === "serviceOffline") sub.textContent = startHint();
        if (Dictation.draft) {
          kept.textContent = Dictation.draft;
          show(kept, true);
        }
        break;
      }
    }
    show(line, line.textContent !== "");

    // The buttons.
    const busy = phase === "starting" || phase === "recording";
    recordIcon.replaceChildren(phase === "finishing"
      ? h("span", { class: "dct-spinner" })
      : svg(busy ? ICONS.stop : ICONS.mic, 13));
    recordLabel.textContent = busy ? t("Stop") : phase === "finishing" ? t("Transcribing…") : t("Record");
    record.classList.toggle("settling", phase === "finishing");
    (record as HTMLButtonElement).disabled = phase === "finishing";
    show(meter, phase === "recording" && onScreen());
    const hasText = !!Dictation.draft.trim();
    show(copy, phase === "done" && hasText);
    show(paste, phase === "done" && hasText && Dictation.trigger === "button" && !ON_LINUX);
    show(discard, phase === "done" && hasText);
    show(copyKept, phase === "failed" && hasText);
    show(openSettings, phase === "failed" && Dictation.failure?.kind === "microphoneDenied" && !ON_LINUX);
    show(checkAgain, phase === "idle" && offline());

    // Which model, and whether text comes while speaking — said plainly, so an
    // offline backend is not mistaken for a broken one.
    const info = serviceInfo();
    model.textContent = info
      ? (info.streaming ? t("%@ · live", modelName(info)) : t("%@ · text at the end", modelName(info)))
      : "";
    paintMeter();
  }

  // The meter and the timer between full repaints, only while on screen.
  Dictation.subscribe(() => {
    if (onScreen() && Dictation.phase === "recording") paintMeter();
  });

  return {
    el,
    sync,
    tick() {
      if (Dictation.phase === "recording" && onScreen()) paintClock();
    },
  };
}
