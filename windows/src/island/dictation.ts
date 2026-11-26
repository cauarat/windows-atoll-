// Dictation, start to end, on the island — DictationController.swift for
// Windows and Linux.
//
// Two ways in, one session:
// - The held key (Windows: the right Ctrl by default). Rust's keyboard hook
//   runs the gesture (dictation_keys.rs) and sends `arm`, `show`, `commit` or
//   `cancel` here. The microphone starts on the press, the card opens if the
//   key is still held after 0.3 s, and on release the text is pasted where the
//   cursor is. The island window never takes the keyboard for it.
// - The card's button, from the tray's Dictation: record, stop, then edit,
//   copy or paste.
//
// The microphone is captured here (getUserMedia, an AudioContext at 16 kHz,
// PCM16 in 100 ms frames) and handed to Rust, which holds the WebSocket to the
// transcription service (dictation.rs). The model itself is not here: it runs
// in dictation-service/, at the address in Settings, and when it is not
// running the card says so and says how to start it.

import { Bridge, type DictationSocketEvent } from "../core/bridge";
import {
  DICTATION, Framer, Resampler, applyMessage, decodeHealth, decodeServerMessage, emptyTranscript,
  healthURL, level as levelOf, socketURL, startMessage, toPCM16, type Health, type ServiceInfo, type Transcript,
} from "../core/dictation";
import { Sound } from "../core/sound";
import { State } from "../core/state";

export type Phase = "idle" | "starting" | "recording" | "finishing" | "done" | "failed";
export type Trigger = "button" | "holdKey";
export type Failure =
  | { kind: "microphoneDenied" }
  | { kind: "microphoneUnavailable" }
  | { kind: "invalidAddress" }
  | { kind: "serviceOffline" }
  | { kind: "connectionLost" }
  | { kind: "timedOut" }
  | { kind: "service"; code: string; message: string };
export type ServiceStatus =
  | { kind: "unknown" }
  | { kind: "checking" }
  | { kind: "ready" | "loading" | "broken"; health: Health }
  | { kind: "offline" | "invalidAddress" | "notTheService" };
export type Outcome = "pasted" | "copied" | null;

/** How long the service may take to answer once all the audio is sent. */
const FINAL_TIMEOUT_MS = 90_000;
/** About twelve level updates a second: enough for the meter, not a repaint per buffer. */
const LEVEL_EVERY_MS = 80;

interface Microphone {
  stream: MediaStream;
  ctx: AudioContext;
  source: MediaStreamAudioSourceNode;
  node: ScriptProcessorNode;
  sink: GainNode;
  framer: Framer;
}

let phase: Phase = "idle";
let trigger: Trigger = "button";
let transcript: Transcript = emptyTranscript();
let failure: Failure | null = null;
let level = 0;
let recordingSince: number | null = null;
let outcome: Outcome = null;
let service: ServiceStatus = { kind: "unknown" };
let draft = "";
/** Bumped by every dictation and every cancel: late events from an older one are dropped. */
let session = 0;
/** The id Rust gave the connection; its events carry it. */
let socketId: number | null = null;
let mic: Microphone | null = null;
let deadline: number | null = null;
const listeners = new Set<() => void>();

function changed() {
  for (const fn of listeners) fn();
}

/**
 * Opens the microphone and builds the graph, silent: no frame goes anywhere
 * until `startFrames`, once Rust has a connection to send them on.
 */
async function openMicrophone(): Promise<Microphone> {
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true },
  });
  let ctx: AudioContext;
  try {
    // The webview resamples the microphone itself; Resampler is for one that will not.
    ctx = new AudioContext({ sampleRate: DICTATION.sampleRate });
  } catch {
    ctx = new AudioContext();
  }
  const source = ctx.createMediaStreamSource(stream);
  // ScriptProcessor rather than an AudioWorklet: a worklet module would need a
  // script URL the island's CSP does not allow, and this runs 2048 samples at
  // a time — eight times a second — only while dictating.
  const node = ctx.createScriptProcessor(2048, 1, 1);
  const sink = ctx.createGain();
  sink.gain.value = 0; // connected so it runs, silent so nothing is heard back
  source.connect(node);
  node.connect(sink);
  sink.connect(ctx.destination);
  return { stream, ctx, source, node, sink, framer: new Framer() };
}

/** Frames start flowing to the connection, and the meter starts moving. */
async function startFrames(m: Microphone): Promise<void> {
  const resampler = m.ctx.sampleRate === DICTATION.sampleRate ? null : new Resampler(m.ctx.sampleRate);
  let levelAt = 0;
  m.node.onaudioprocess = (event) => {
    const raw = event.inputBuffer.getChannelData(0);
    const samples = resampler ? resampler.process(raw) : Float32Array.from(raw);
    for (const frame of m.framer.push(toPCM16(samples))) Bridge.dictationAudio(frame);
    const now = performance.now();
    if (now - levelAt >= LEVEL_EVERY_MS) {
      levelAt = now;
      level = levelOf(samples);
      changed();
    }
  };
  if (m.ctx.state === "suspended") await m.ctx.resume();
}

/** Stops the microphone; the last, shorter frame goes out first — the end of the last word. */
function closeMicrophone(send: boolean) {
  const m = mic;
  mic = null;
  if (!m) return;
  m.node.onaudioprocess = null;
  if (send) {
    const tail = m.framer.flush();
    if (tail) Bridge.dictationAudio(tail);
  }
  try { m.source.disconnect(); m.node.disconnect(); m.sink.disconnect(); } catch { /* already gone */ }
  for (const track of m.stream.getTracks()) track.stop();
  void m.ctx.close().catch(() => {});
}

function refusal(err: unknown): Failure {
  const name = (err as { name?: string } | null)?.name ?? "";
  return name === "NotAllowedError" || name === "SecurityError"
    ? { kind: "microphoneDenied" }
    : { kind: "microphoneUnavailable" };
}

function clearState() {
  transcript = emptyTranscript();
  failure = null;
  outcome = null;
  draft = "";
  level = 0;
  recordingSince = null;
}

function teardown(cancelSocket: boolean) {
  if (deadline !== null) {
    clearTimeout(deadline);
    deadline = null;
  }
  closeMicrophone(false);
  if (cancelSocket && socketId !== null) void Bridge.dictationCancel();
  socketId = null;
  level = 0;
  recordingSince = null;
}

function fail(f: Failure) {
  teardown(true);
  failure = f;
  phase = "failed";
  // What was heard before it broke is still the person's.
  draft = transcript.text;
  Dictation.showCard(true);
  changed();
}

function finished() {
  teardown(false);
  phase = "done";
  draft = transcript.text;
  if (trigger === "holdKey") void deliver();
  // The result is a notification whichever way the dictation started: on
  // screen for as long as one stays, then folded — unless the pointer is on it
  // or the text is being edited.
  Dictation.showCard(true);
  changed();
}

async function deliver() {
  const text = draft.trim();
  if (!text) return;
  // Linux answers "copied" for "paste" too: Wayland lets no app type into another.
  outcome = await Bridge.dictationInsert(text, State.settings.dictationInsert);
  changed();
}

export const Dictation = {
  /** Set by main.ts: open the card as a notification (true) or like a tab (false). */
  showCard: (_asNotification: boolean): void => {},
  /** Set by main.ts: fold the card away if it is the one showing. */
  hideCard: (): void => {},

  get phase(): Phase { return phase; },
  get trigger(): Trigger { return trigger; },
  get transcript(): Transcript { return transcript; },
  get failure(): Failure | null { return failure; },
  get level(): number { return level; },
  get recordingSince(): number | null { return recordingSince; },
  get outcome(): Outcome { return outcome; },
  get service(): ServiceStatus { return service; },
  get draft(): string { return draft; },
  set draft(text: string) { draft = text; },

  /** Held open by the island while true: a dictation is a key or a click, not a focus. */
  isBusy(): boolean {
    return phase === "starting" || phase === "recording" || phase === "finishing";
  },

  subscribe(fn: () => void): () => void {
    listeners.add(fn);
    return () => listeners.delete(fn);
  },

  begin(from: Trigger) {
    if (Dictation.isBusy()) return;
    clearState();
    trigger = from;
    phase = "starting";
    const mine = ++session;
    changed();
    void (async () => {
      const url = socketURL(State.settings.dictationServiceUrl);
      if (!url) return fail({ kind: "invalidAddress" });
      let opened: Microphone;
      try {
        opened = await openMicrophone();
      } catch (err) {
        if (mine === session) fail(refusal(err));
        return;
      }
      mic = opened;
      if (mine !== session || phase !== "starting") return closeMicrophone(false); // let go meanwhile
      const id = await Bridge.dictationStart(url, startMessage());
      if (id === null) return fail({ kind: "invalidAddress" });
      if (mine !== session || phase !== "starting") {
        void Bridge.dictationCancel();
        return;
      }
      socketId = id;
      await startFrames(opened);
      phase = "recording";
      recordingSince = Date.now();
      Sound.play("blip");
      changed();
    })();
  },

  /** The key let go, or Stop: a little more audio, then the final. */
  stop() {
    if (phase === "starting") return Dictation.cancel();
    if (phase !== "recording") return;
    phase = "finishing";
    level = 0;
    changed();
    const mine = session;
    window.setTimeout(() => {
      if (mine !== session || phase !== "finishing") return;
      closeMicrophone(true);
      void Bridge.dictationStop();
      deadline = window.setTimeout(() => {
        if (mine === session && phase === "finishing") fail({ kind: "timedOut" });
      }, FINAL_TIMEOUT_MS);
    }, DICTATION.tailMs);
  },

  cancel(hideCard = true) {
    const wasHeld = trigger === "holdKey";
    session++;
    teardown(true);
    clearState();
    phase = "idle";
    if (hideCard && wasHeld) Dictation.hideCard();
    changed();
  },

  toggleRecording() {
    if (phase === "starting" || phase === "recording") Dictation.stop();
    else if (phase !== "finishing") Dictation.begin("button");
  },

  /** From the tray: the card, opened like a tab rather than a notification. */
  openCard() {
    Dictation.showCard(false);
    void Dictation.refreshService();
  },

  async copyDraft() {
    const text = draft.trim();
    if (!text) return;
    outcome = (await Bridge.dictationInsert(text, "copy")) ?? null;
    changed();
  },

  /** Into the app in front. The card's view hands the keyboard back first. */
  async pasteDraft() {
    const text = draft.trim();
    if (!text) return;
    outcome = (await Bridge.dictationInsert(text, State.settings.dictationInsert)) ?? null;
    changed();
  },

  discard() {
    Dictation.cancel(false);
  },

  async refreshService() {
    const url = healthURL(State.settings.dictationServiceUrl);
    if (!url) {
      service = { kind: "invalidAddress" };
      return changed();
    }
    service = { kind: "checking" };
    changed();
    const answer = await Bridge.dictationHealth(url);
    const health = answer?.body ? decodeHealth(answer.body) : null;
    if (health) {
      service = { kind: health.ready ? "ready" : health.status === "error" ? "broken" : "loading", health };
    } else {
      service = { kind: answer?.problem === "notTheService" ? "notTheService" : "offline" };
    }
    changed();
  },

  /** What the service said, or the end of the connection (dictation.rs's `dictation-socket`). */
  onSocketEvent(event: DictationSocketEvent) {
    if (event.session !== socketId) return;
    if (event.message !== null) {
      const message = decodeServerMessage(event.message);
      if (!message) return;
      transcript = applyMessage(transcript, message);
      if (message.type === "final") return finished();
      if (message.type === "error") return fail({ kind: "service", code: message.code, message: message.message });
      return changed();
    }
    if (event.closed && Dictation.isBusy()) {
      fail({ kind: event.closed === "refused" ? "serviceOffline" : "connectionLost" });
    }
  },

  /**
   * windows/dev/dictation-preview.ts only: the card in one of its states, with
   * made-up words and no microphone, connection or service behind it.
   */
  seedForPreview(scene: string) {
    session++;
    teardown(false);
    clearState();
    trigger = "button";
    const info = (streaming: boolean): ServiceInfo => ({
      provider: "qwen3-asr", model: "Qwen/Qwen3-ASR-1.7B",
      backend: streaming ? "vllm" : "transformers", streaming, device: streaming ? "cuda" : "mps",
    });
    const health = (streaming: boolean): Health => ({
      status: "ready", ready: true, protocol: 1, info: info(streaming),
      language: DICTATION.language, languageLabel: DICTATION.languageLabel, error: null,
    });
    const said = "Amanhã às nove horas vamos revisar o relatório com a equipe. Depois, eu envio um resumo por e-mail para todos.";
    const heard = (streaming: boolean, text = "") => {
      transcript = applyMessage(emptyTranscript(), { type: "ready", info: info(streaming) });
      if (text) transcript = applyMessage(transcript, { type: "partial", text, seq: 1 });
    };
    switch (scene) {
      case "idle": phase = "idle"; service = { kind: "ready", health: health(false) }; break;
      case "offline": phase = "idle"; service = { kind: "offline" }; break;
      case "recording": phase = "recording"; heard(false); recordingSince = Date.now() - 4200; level = 0.62; break;
      case "streaming":
        phase = "recording"; heard(true, "Amanhã às nove horas vamos revisar o relatório");
        recordingSince = Date.now() - 3100; level = 0.45; break;
      case "finishing": phase = "finishing"; heard(false); break;
      case "done":
        phase = "done"; heard(false);
        transcript = applyMessage(transcript, { type: "final", text: said, audioMs: 7500, processingMs: 2100, truncated: false });
        draft = said; break;
      case "pasted":
        phase = "done"; trigger = "holdKey"; heard(false);
        transcript = applyMessage(transcript, { type: "final", text: said, audioMs: 7500, processingMs: 2100, truncated: false });
        draft = said; outcome = "pasted"; break;
      case "failed-offline": phase = "failed"; failure = { kind: "serviceOffline" }; break;
      case "failed-model":
        phase = "failed"; heard(true, "Amanhã às nove");
        failure = { kind: "service", code: "provider_unavailable", message: "O streaming do Qwen3-ASR usa o vLLM, que precisa de uma GPU NVIDIA com CUDA." };
        draft = "Amanhã às nove"; break;
    }
    changed();
  },

  /** The held key, from dictation_keys.rs. */
  onHoldAction(action: "arm" | "show" | "commit" | "cancel") {
    if (!State.settings.enabled || !State.settings.dictationEnabled) return;
    // Recording from the button: the key neither stops it nor starts another.
    if (trigger === "button" && Dictation.isBusy()) return;
    switch (action) {
      case "arm": return Dictation.begin("holdKey");
      case "show": return Dictation.showCard(true);
      case "commit": return Dictation.stop();
      case "cancel": return Dictation.cancel();
    }
  },
};
