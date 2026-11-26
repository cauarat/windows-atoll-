// Dictation's protocol, the Windows and Linux app's side — the twin of
// NotchBuddy/Sources/App/DictationProtocol.swift.
//
// The speech model runs in dictation-service/ (Qwen3-ASR on open weights by
// default), at the address set in Settings. The island captures the microphone
// as 16 kHz mono PCM16 and Rust carries it to `WS /v1/dictation`; what comes
// back is `ready`, `partial`, `final` and `error`, read here into what the card
// shows. tests/fixtures/dictation.json holds this file, the Mac and the service
// to the same messages (tests/dictation.ts).
//
// Pure data and functions: no DOM, no Tauri, so Node can run the tests.

export const DICTATION = {
  version: 1,
  path: "/v1/dictation",
  healthPath: "/health",
  defaultServiceURL: "http://127.0.0.1:8765",
  sampleRate: 16000,
  encoding: "pcm_s16le",
  frameMs: 100,
  /** Kept recording after the key is let go: people let go on the last syllable. */
  tailMs: 250,
  /** Named, never translated: it says what the model was asked for. */
  language: "pt-BR",
  languageLabel: "Português (Brasil)",
} as const;

export const ERROR_CODES = [
  "bad_request", "unsupported_audio", "unsupported_language", "model_loading",
  "model_failed", "provider_unavailable", "forbidden_origin", "internal",
] as const;

/** Bytes in one frame: 100 ms of 16 kHz mono 16-bit audio. */
export const FRAME_BYTES = (DICTATION.sampleRate * DICTATION.frameMs / 1000) * 2;

export function startMessage(language: string = DICTATION.language): string {
  return JSON.stringify({
    type: "start", language, sample_rate: DICTATION.sampleRate, encoding: DICTATION.encoding, channels: 1,
  });
}

export const STOP_MESSAGE = '{"type":"stop"}';
export const CANCEL_MESSAGE = '{"type":"cancel"}';

/**
 * The socket for a service address as typed in Settings: `http://host:port`
 * becomes `ws://host:port/v1/dictation` (https → wss), a bare `host:port` is
 * taken as http, and anything that is not an address is null.
 */
export function socketURL(service: string): string | null {
  return endpoint(service, DICTATION.path, true);
}

export function healthURL(service: string): string | null {
  return endpoint(service, DICTATION.healthPath, false);
}

function endpoint(service: string, path: string, websocket: boolean): string | null {
  let text = service.trim();
  if (!text) return null;
  if (!text.includes("://")) text = `http://${text}`;
  const scheme = text.slice(0, text.indexOf("://")).toLowerCase();
  const secure = scheme === "https" || scheme === "wss";
  if (!secure && scheme !== "http" && scheme !== "ws") return null;
  let url: URL;
  try {
    // Parsed as http(s) so the URL class knows the default ports; the scheme
    // is put back as asked for below.
    url = new URL(`${secure ? "https" : "http"}${text.slice(scheme.length)}`);
  } catch {
    return null;
  }
  if (!url.hostname) return null;
  const host = url.port ? `${url.hostname}:${url.port}` : url.hostname;
  const proto = websocket ? (secure ? "wss" : "ws") : (secure ? "https" : "http");
  return `${proto}://${host}${path}`;
}

export interface ServiceInfo {
  provider: string;
  model: string;
  backend: string;
  /** Whether partials come while the person speaks; false: one final at the end. */
  streaming: boolean;
  device: string;
}

/** "Qwen3-ASR-1.7B" out of "Qwen/Qwen3-ASR-1.7B". */
export function modelName(info: ServiceInfo): string {
  const parts = info.model.split("/");
  return parts[parts.length - 1] || info.model;
}

export type ServerMessage =
  | { type: "ready"; info: ServiceInfo }
  | { type: "partial"; text: string; seq: number }
  | { type: "final"; text: string; audioMs: number; processingMs: number; truncated: boolean }
  | { type: "error"; code: string; message: string };

function serviceInfo(o: Record<string, unknown>): ServiceInfo | null {
  if (typeof o.provider !== "string" || typeof o.model !== "string") return null;
  return {
    provider: o.provider,
    model: o.model,
    backend: typeof o.backend === "string" ? o.backend : "",
    streaming: o.streaming === true,
    device: typeof o.device === "string" ? o.device : "",
  };
}

export function decodeServerMessage(raw: string | unknown): ServerMessage | null {
  let o: unknown = raw;
  if (typeof raw === "string") {
    try { o = JSON.parse(raw); } catch { return null; }
  }
  if (!o || typeof o !== "object") return null;
  const m = o as Record<string, unknown>;
  switch (m.type) {
    case "ready": {
      const info = serviceInfo(m);
      return info ? { type: "ready", info } : null;
    }
    case "partial":
      return typeof m.text === "string"
        ? { type: "partial", text: m.text, seq: typeof m.seq === "number" ? m.seq : 0 }
        : null;
    case "final":
      return typeof m.text === "string"
        ? {
          type: "final", text: m.text,
          audioMs: typeof m.audio_ms === "number" ? m.audio_ms : 0,
          processingMs: typeof m.processing_ms === "number" ? m.processing_ms : 0,
          truncated: m.truncated === true,
        }
        : null;
    case "error":
      return {
        type: "error",
        code: typeof m.code === "string" ? m.code : "internal",
        message: typeof m.message === "string" ? m.message : "",
      };
    default:
      return null;
  }
}

export interface Transcript {
  phase: "waiting" | "listening" | "done" | "error";
  text: string;
  service: ServiceInfo | null;
  errorCode: string | null;
  errorMessage: string | null;
  audioMs: number;
  processingMs: number;
  truncated: boolean;
}

export function emptyTranscript(): Transcript {
  return {
    phase: "waiting", text: "", service: null, errorCode: null, errorMessage: null,
    audioMs: 0, processingMs: 0, truncated: false,
  };
}

/**
 * What the card shows once `m` has arrived. A partial replaces the text, never
 * adds to it, so nothing is shown twice; the final replaces everything; an
 * error keeps what was already heard. `DictationTranscript.apply`, line for line.
 */
export function applyMessage(t: Transcript, m: ServerMessage): Transcript {
  const finished = t.phase === "done" || t.phase === "error";
  switch (m.type) {
    case "ready":
      return finished ? t : { ...t, service: m.info, phase: "listening" };
    case "partial":
      return finished ? t : { ...t, text: m.text };
    case "final":
      return t.phase === "done"
        ? t
        : { ...t, text: m.text, audioMs: m.audioMs, processingMs: m.processingMs, truncated: m.truncated, phase: "done" };
    case "error":
      return finished ? t : { ...t, errorCode: m.code, errorMessage: m.message, phase: "error" };
  }
}

/** The service's `/health` answer. */
export interface Health {
  status: string;
  ready: boolean;
  protocol: number;
  info: ServiceInfo;
  language: string;
  languageLabel: string;
  error: string | null;
}

export function decodeHealth(raw: string): Health | null {
  let o: unknown;
  try { o = JSON.parse(raw); } catch { return null; }
  if (!o || typeof o !== "object") return null;
  const m = o as Record<string, unknown>;
  const info = serviceInfo(m);
  if (typeof m.status !== "string" || !info) return null;
  return {
    status: m.status,
    ready: m.ready === true,
    protocol: typeof m.protocol === "number" ? m.protocol : 0,
    info,
    language: typeof m.language === "string" ? m.language : DICTATION.language,
    languageLabel: typeof m.language_label === "string" ? m.language_label : DICTATION.languageLabel,
    error: typeof m.error === "string" ? m.error : null,
  };
}

// ── Settings values ─────────────────────────────────────────────────────────
//
// What `dictationHoldKey` and `dictationInsert` store. The spellings are the
// Mac's (DictationHoldKey, DictationInsertMode) for the keys both have; fn is
// the Mac's alone. Titles are English — the catalogue key, translated where
// they are drawn.

export const HOLD_KEYS = [
  { id: "rightCtrl", title: "Right Ctrl" },
  { id: "rightAlt", title: "Right Alt" },
  { id: "off", title: "No key — only the button" },
] as const;

export const INSERT_MODES = [
  { id: "paste", title: "Paste where the cursor is" },
  { id: "copy", title: "Only copy to the clipboard" },
] as const;

// ── Microphone arithmetic ───────────────────────────────────────────────────

/** float samples in [-1, 1] → PCM16 little-endian. */
export function toPCM16(samples: Float32Array): Uint8Array {
  const out = new Uint8Array(samples.length * 2);
  const view = new DataView(out.buffer);
  for (let i = 0; i < samples.length; i++) {
    const x = Math.max(-1, Math.min(1, samples[i]));
    view.setInt16(i * 2, Math.round(x < 0 ? x * 32768 : x * 32767), true);
  }
  return out;
}

/** 0…1 for the meter, the Mac's mapping: -50 dBFS and quieter at 0, 0 dB at 1. */
export function level(samples: Float32Array): number {
  if (!samples.length) return 0;
  let sum = 0;
  for (const x of samples) sum += x * x;
  const rms = Math.sqrt(sum / samples.length);
  if (rms <= 0) return 0;
  const db = 20 * Math.log10(rms);
  return Math.min(1, Math.max(0, (db + 50) / 50));
}

/** Collects bytes and hands them back in whole 100 ms frames, in order. */
export class Framer {
  private pending = new Uint8Array(0);

  push(bytes: Uint8Array): Uint8Array[] {
    const all = new Uint8Array(this.pending.length + bytes.length);
    all.set(this.pending);
    all.set(bytes, this.pending.length);
    const frames: Uint8Array[] = [];
    let offset = 0;
    while (all.length - offset >= FRAME_BYTES) {
      frames.push(all.slice(offset, offset + FRAME_BYTES));
      offset += FRAME_BYTES;
    }
    this.pending = all.slice(offset);
    return frames;
  }

  /** The tail, shorter than a frame: the end of the last word. */
  flush(): Uint8Array | null {
    if (!this.pending.length) return null;
    const rest = this.pending;
    this.pending = new Uint8Array(0);
    return rest;
  }
}

/**
 * Linear resampling to 16 kHz, kept between calls so consecutive buffers join
 * without a seam. Only for a webview whose AudioContext would not run at
 * 16 kHz itself (WebView2 and WebKitGTK normally do).
 */
export class Resampler {
  /** Where the next output sample falls, in input samples from this buffer's
   *  start: -1 is the previous buffer's last sample. */
  private t = 0;
  private prev = 0;
  private readonly step: number;

  constructor(from: number, to: number = DICTATION.sampleRate) {
    this.step = from / to;
  }

  process(input: Float32Array): Float32Array {
    if (this.step === 1 || input.length === 0) return input;
    const out: number[] = [];
    while (this.t < input.length - 1) {
      const i = Math.floor(this.t);
      const frac = this.t - i;
      const a = i < 0 ? this.prev : input[i];
      const b = input[i + 1];
      out.push(a + (b - a) * frac);
      this.t += this.step;
    }
    this.t -= input.length;
    this.prev = input[input.length - 1];
    return Float32Array.from(out);
  }
}
