/**
 * Recording a voice note into a reply, and hearing it back before it goes.
 *
 * Sibling of `replyAttachments.ts`, in the same relationship to it that it has
 * to `core/attachments.ts`: this one talks to hardware, the staging rules stay
 * where they are. Once `stop()` has run the clip is an ordinary attachment and
 * nothing downstream knows a microphone was involved — which is why no send
 * path was added for audio anywhere.
 */

import { AttachmentLimits } from "../core/attachments";
import { Bridge } from "../core/bridge";
import { Sound } from "../core/sound";
import { State } from "../core/state";
import { t } from "../core/i18n";
import * as ReplyAttachments from "./replyAttachments";
import { toVoiceWav } from "./wav";

/**
 * Preferred first because it matches what the Mac records and needs no
 * re-encoding. In most Chromium and WebView2 builds `isTypeSupported` says no
 * to it, so the WebM branch below is the one that usually runs — it is the
 * main path, not an exotic fallback.
 */
const PREFERRED = [
  { mime: "audio/mp4", ext: "m4a" },
  { mime: "audio/webm;codecs=opus", ext: "webm" },
  { mime: "audio/webm", ext: "webm" },
] as const;

let recorder: MediaRecorder | null = null;
let chunks: BlobPart[] = [];
let chosen: (typeof PREFERRED)[number] | null = null;
let tick: number | null = null;
let capTimer: number | null = null;

/** Object URLs for clips recorded this session, keyed by the path on disk. */
const clips = new Map<string, string>();
let audio: HTMLAudioElement | null = null;
let playing: string | null = null;

/** Whether this webview can record at all — the button hides when it cannot. */
export function canRecord(): boolean {
  return typeof MediaRecorder !== "undefined"
    && typeof navigator !== "undefined"
    && !!navigator.mediaDevices?.getUserMedia;
}

export function isRecording(): boolean {
  return State.recordingSince !== null;
}

/** Seconds so far, for the clock. */
export function elapsed(): number {
  return State.recordingSince === null
    ? 0
    : (Date.now() - State.recordingSince) / 1000;
}

// ── Recording ────────────────────────────────────────────────────────────────

export async function start(): Promise<void> {
  if (isRecording() || !canRecord()) return;

  let stream: MediaStream;
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  } catch (err) {
    State.replyNotice = refusal(err);
    State.notify();
    return;
  }

  chosen = PREFERRED.find((c) => MediaRecorder.isTypeSupported(c.mime)) ?? null;
  if (!chosen) {
    stop_tracks(stream);
    State.replyNotice = t("This computer cannot record audio.");
    State.notify();
    return;
  }

  chunks = [];
  recorder = new MediaRecorder(stream, { mimeType: chosen.mime });
  recorder.ondataavailable = (e) => { if (e.data.size > 0) chunks.push(e.data); };
  recorder.onstop = () => stop_tracks(stream);
  recorder.start();

  State.recordingSince = Date.now();
  State.replyNotice = null;
  Sound.play("blip");
  // Twice a second, and only while recording. Not a rAF: what this moves is
  // one digit, on a window whose whole claim is no CPU at rest.
  tick = window.setInterval(() => State.notify(), 500);
  // The cap keeps a forgotten recording inside the per-file limit, so a clip
  // is never refused *after* it is made for a size nobody was shown.
  capTimer = window.setTimeout(() => void stop(), AttachmentLimits.maxRecordingSeconds * 1000);
  State.notify();
}

/** Stops, encodes, and stages the clip as an ordinary attachment. */
export async function stop(): Promise<void> {
  const active = recorder;
  if (!active || !isRecording()) return;
  const format = chosen;
  clearTimers();
  const started = State.recordingSince ?? Date.now();
  State.recordingSince = null;
  State.notify();

  const finished = new Promise<void>((resolve) => {
    active.addEventListener("stop", () => resolve(), { once: true });
  });
  active.stop();
  await finished;
  recorder = null;
  chosen = null;

  // Under half a second is a mis-click, not a message.
  if (Date.now() - started < 500 || chunks.length === 0) {
    chunks = [];
    return;
  }

  const blob = new Blob(chunks, { type: format?.mime ?? "application/octet-stream" });
  chunks = [];

  let bytes: Uint8Array;
  let ext: string;
  try {
    if (format?.ext === "webm") {
      // Never shipped as `.webm`: the server reads the type off the file name
      // and every MIME table calls it video, so the clip would arrive as one.
      bytes = await toVoiceWav(blob);
      ext = "wav";
    } else {
      bytes = new Uint8Array(await blob.arrayBuffer());
      ext = format?.ext ?? "m4a";
    }
  } catch {
    State.replyNotice = t("The recording could not be saved.");
    State.notify();
    return;
  }

  const name = `${t("Voice message")} ${ReplyAttachments.stamp()}.${ext}`;
  try {
    const written = await Bridge.ingestBytes(name, Array.from(bytes));
    // Keyed by path rather than id: the id is minted inside `attach`, and the
    // path is already unique because `ingest_bytes` never overwrites.
    clips.set(written.path, URL.createObjectURL(new Blob([bytes.slice().buffer])));
    ReplyAttachments.attach([{ path: written.path, byteCount: written.size }]);
  } catch (err) {
    State.replyNotice = String(err).replace(/^Error:\s*/, "");
    State.notify();
  }
}

/** Throws the recording away. Nothing is staged and nothing reaches disk. */
export function cancel(): void {
  const active = recorder;
  clearTimers();
  State.recordingSince = null;
  recorder = null;
  chosen = null;
  chunks = [];
  active?.stop();
  State.notify();
}

function clearTimers(): void {
  if (tick !== null) { window.clearInterval(tick); tick = null; }
  if (capTimer !== null) { window.clearTimeout(capTimer); capTimer = null; }
}

function stop_tracks(stream: MediaStream): void {
  for (const track of stream.getTracks()) track.stop();
}

/**
 * Why there is no recording, in words the card shows unchanged.
 *
 * `NotAllowedError` is the one worth spelling out: the permission handler in
 * `lib.rs` answers the webview's own prompt, but underneath it sits an OS
 * switch that no handler overrides, and what reaches JavaScript when the OS
 * refuses is indistinguishable from someone clicking Block. So the sentence
 * names the setting rather than guessing which layer said no.
 */
function refusal(err: unknown): string {
  const name = err instanceof DOMException ? err.name : "";
  switch (name) {
    case "NotAllowedError":
    case "SecurityError":
      return t("The microphone is blocked. Check Privacy settings → Microphone.");
    case "NotFoundError":
    case "OverconstrainedError":
      return t("No microphone found.");
    case "NotReadableError":
      return t("Something else is using the microphone.");
    default:
      return String(err).replace(/^Error:\s*/, "");
  }
}

// ── Hearing it back ──────────────────────────────────────────────────────────

/**
 * Whether this attachment can be played here.
 *
 * Only clips recorded in this session can: the webview cannot read the inbox,
 * so a `.m4a` chosen with the paperclip has no blob behind it and gets no play
 * button. The requirement is hearing back what you just recorded.
 */
export function canPlay(path: string): boolean {
  return clips.has(path);
}

export function playingPath(): string | null {
  return playing;
}

export function toggle(path: string): void {
  if (playing === path) { stopPlayback(); return; }
  const url = clips.get(path);
  if (!url) return;
  stopPlayback();
  audio = new Audio(url);
  audio.addEventListener("ended", () => stopPlayback(), { once: true });
  void audio.play();
  playing = path;
  State.notify();
}

export function stopPlayback(): void {
  audio?.pause();
  audio = null;
  playing = null;
  State.notify();
}

/** Called when the reply is sent or thrown away: the blobs go with it. */
export function releaseClips(): void {
  stopPlayback();
  for (const url of clips.values()) URL.revokeObjectURL(url);
  clips.clear();
}
