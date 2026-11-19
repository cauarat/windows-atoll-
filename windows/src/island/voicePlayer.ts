// Playback for received voice messages — the twin of the remote half of
// `AttachmentPlayer` in VoiceRecordButton.swift.
//
// One clip at a time for the whole island. The bytes come from Rust (Actuar's
// storage answers a short-lived address that only Rust fetches), become a
// blob, and play in an <audio> element: WebView2 decodes WhatsApp's Ogg/Opus
// itself, and sniffs the MP3s Ato sometimes names `.ogg`, because the blob is
// given no type to trust.
//
// Pause keeps the position, and the end of a clip leaves it loaded at its
// start, so play hears it again — the Now Playing card's behaviour.

import { Bridge } from "../core/bridge";
import { State } from "../core/state";

let audio: HTMLAudioElement | null = null;
let url: string | null = null;
/** The storage id of the clip in `audio`, playing or paused. */
let loadedId: string | null = null;
let loadingId: string | null = null;
let failedId: string | null = null;
/** Bumped on every start, so a load that lost the race does nothing. */
let generation = 0;

export function loaded(id: string): boolean {
  return loadedId === id && audio != null;
}
export function playing(id: string): boolean {
  return loaded(id) && !audio!.paused;
}
export function loading(id: string): boolean {
  return loadingId === id;
}
export function failed(id: string): boolean {
  return failedId === id;
}
/** Whether anything is coming out of the speakers, or about to — what holds the card open. */
export function busy(): boolean {
  return (audio != null && !audio.paused) || loadingId != null;
}
export function position(): number {
  return audio?.currentTime ?? 0;
}
/** The clip's own length once it is here; NaN before. */
export function length(): number {
  const d = audio?.duration ?? NaN;
  return Number.isFinite(d) ? d : NaN;
}

/** Play, pause, or carry on — the one button. */
export function toggle(id: string): void {
  if (loadingId === id) {
    stop();
    return;
  }
  if (loaded(id)) {
    if (audio!.paused) void audio!.play().catch(() => fail(id));
    else audio!.pause();
    State.notify();
    return;
  }
  void start(id, () => 0);
}

/**
 * Puts the clip at a fraction of its length — a click or a drag on the bar.
 * On one not loaded yet it loads and starts from there, since a click on the
 * bar is asking to hear that part.
 */
export function seek(id: string, fraction: number): void {
  const f = Math.min(Math.max(fraction, 0), 1);
  if (loaded(id)) {
    const total = length();
    if (Number.isFinite(total)) audio!.currentTime = f * total;
    State.notify();
    return;
  }
  void start(id, (total) => f * total);
}

/** Back or forward by a few seconds, within the clip. */
export function skip(id: string, seconds: number): void {
  if (loaded(id)) {
    const total = length();
    const next = audio!.currentTime + seconds;
    audio!.currentTime = Math.max(0, Number.isFinite(total) ? Math.min(next, total) : next);
    State.notify();
    return;
  }
  void start(id, (total) => Math.min(Math.max(seconds, 0), total));
}

export function stop(): void {
  generation += 1;
  if (audio) {
    audio.pause();
    audio.removeAttribute("src");
    audio.load();
  }
  if (url) URL.revokeObjectURL(url);
  audio = null;
  url = null;
  loadedId = null;
  loadingId = null;
  State.notify();
}

async function start(id: string, at: (total: number) => number): Promise<void> {
  stop();
  const mine = generation;
  failedId = null;
  loadingId = id;
  State.notify();

  let bytes: ArrayBuffer;
  try {
    bytes = await Bridge.atoVoiceNote(id);
  } catch {
    if (mine === generation) fail(id);
    return;
  }
  if (mine !== generation) return;

  const element = new Audio();
  const blobUrl = URL.createObjectURL(new Blob([bytes]));
  element.src = blobUrl;
  element.preload = "auto";
  try {
    await new Promise<void>((resolve, reject) => {
      element.addEventListener("loadedmetadata", () => resolve(), { once: true });
      element.addEventListener("error", () => reject(new Error("decode")), { once: true });
    });
    if (mine !== generation) {
      URL.revokeObjectURL(blobUrl);
      return;
    }
    const total = Number.isFinite(element.duration) ? element.duration : 0;
    element.currentTime = Math.min(Math.max(at(total), 0), total || 0);
    audio = element;
    url = blobUrl;
    loadedId = id;
    loadingId = null;
    // The end leaves it loaded at its start, paused.
    element.addEventListener("ended", () => {
      element.currentTime = 0;
      State.notify();
    });
    element.addEventListener("pause", () => State.notify());
    element.addEventListener("play", () => State.notify());
    await element.play();
    State.notify();
  } catch {
    URL.revokeObjectURL(blobUrl);
    if (mine === generation) fail(id);
  }
}

function fail(id: string): void {
  stop();
  failedId = id;
  State.notify();
}
