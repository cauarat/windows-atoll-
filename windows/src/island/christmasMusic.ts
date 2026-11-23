// Notchy's own Christmas music — the twin of `ChristmasMusicPlayer.swift`.
//
// One long YouTube compilation, played by the island itself in a hidden
// iframe. It starts with the greeting at launch in season, and the Christmas
// folder on the player starts it again after anything else has played. While
// it is the source the card shows it like any other track: `island/media.ts`
// swaps it in for what GSMTC reports.
//
// The iframe speaks YouTube's embed protocol (`enablejsapi=1`): JSON over
// `postMessage`, `listening` to subscribe, `command` to drive it,
// `infoDelivery` back. No script of YouTube's runs in the island.
//
// Nothing exists until the first `play()`, and a player that steps aside for
// another app is removed, not paused: the island owes 0 % CPU when it is
// hidden, and a parked YouTube page is not that. One left paused for five
// minutes is removed as well, keeping its place for the next play.

import { Bridge, type MediaAction, type MediaState } from "../core/bridge";
import { t } from "../core/i18n";
import { State } from "../core/state";
import { isFestiveSeason } from "../mochi/character";

/**
 * "Vintage Christmas Songs 50s 60s 70s" from Silent Christmas — the link the
 * Christmas music was asked to be. Its `list=RD…` radio mix is generated per
 * viewer and cannot be embedded, so the one video loops.
 */
export const CHRISTMAS_VIDEO_ID = "asv5QPt2UQM";

const EMBED_ORIGIN = "https://www.youtube-nocookie.com";

/** The video's own thumbnail, 16:9 and cropped square by the card. */
export const CHRISTMAS_ARTWORK = `https://i.ytimg.com/vi/${CHRISTMAS_VIDEO_ID}/mqdefault.jpg`;

/** What the card says it is playing from. */
const SOURCE_NAME = "Notchy";
const SOURCE_ID = "notchy.christmas";

/** The app the folder just paused goes on reporting itself playing for a
 *  moment; that is not the user choosing it over the Christmas music. */
const YIELD_GRACE_MS = 3000;

/** How often a playing video's position is taken, between state changes. The
 *  card extrapolates in between, as it does for every other player. */
const REPORT_EVERY_MS = 5000;

/** How long a paused player is kept loaded. A YouTube page sitting paused
 *  still runs its scripts and holds a renderer; past this it is removed, and
 *  play loads it again from where it stopped — a second or two later than an
 *  instant resume, after a pause long enough not to be a quick one. */
const RELEASE_PAUSED_AFTER_MS = 5 * 60_000;

let frame: HTMLIFrameElement | null = null;
let listenTimer: number | null = null;
/** Counting down to removing a paused player (`RELEASE_PAUSED_AFTER_MS`). */
let releaseTimer: number | null = null;
let active = false;
let playing = false;
let title = "";
let author = "";
let duration = 0;
/** Position at `anchorAt`, so the clock advances without a message a frame. */
let anchorTime = 0;
let anchorAt = performance.now();
let lastReport = 0;
let activatedAt = 0;
/** Where to pick up after the iframe was removed. */
let resumeAt = 0;
let startedWithGreeting = false;
/** Whether another app was playing, as GSMTC last said. */
let otherPlaying = false;

/** Called whenever what the card should show has changed. */
let changed: () => void = () => {};

function elapsedNow(): number {
  if (!playing) return anchorTime;
  const at = anchorTime + (performance.now() - anchorAt) / 1000;
  return duration > 0 ? Math.min(at, duration) : at;
}

function command(func: string, args: unknown[] = []) {
  frame?.contentWindow?.postMessage(JSON.stringify({ event: "command", func, args }), EMBED_ORIGIN);
}

function embedURL(start: number): string {
  const params = new URLSearchParams({
    autoplay: "1",
    loop: "1",
    playlist: CHRISTMAS_VIDEO_ID,
    start: String(Math.floor(start)),
    enablejsapi: "1",
    origin: location.origin,
  });
  return `${EMBED_ORIGIN}/embed/${CHRISTMAS_VIDEO_ID}?${params}`;
}

function load() {
  const el = document.createElement("iframe");
  el.className = "christmas-player";
  el.src = embedURL(resumeAt);
  el.allow = "autoplay; encrypted-media";
  // The embed refuses a page that sends no Referer.
  el.referrerPolicy = "strict-origin-when-cross-origin";
  el.title = "Christmas music";
  el.tabIndex = -1;
  el.setAttribute("aria-hidden", "true");
  el.addEventListener("load", () => subscribe());
  document.body.append(el);
  frame = el;
}

/** Ask the embed to report. Repeated until it answers: it ignores a request
 *  that lands before its player is ready. */
function subscribe() {
  if (listenTimer != null) window.clearInterval(listenTimer);
  let tries = 0;
  const ask = () => {
    frame?.contentWindow?.postMessage(JSON.stringify({ event: "listening", id: 1, channel: "widget" }), EMBED_ORIGIN);
    if (++tries > 20 && listenTimer != null) {
      window.clearInterval(listenTimer);
      listenTimer = null;
    }
  };
  ask();
  listenTimer = window.setInterval(ask, 500);
}

function tearDown() {
  resumeAt = elapsedNow();
  anchorTime = resumeAt;
  playing = false;
  if (listenTimer != null) window.clearInterval(listenTimer);
  listenTimer = null;
  cancelRelease();
  frame?.remove();
  frame = null;
}

function cancelRelease() {
  if (releaseTimer != null) window.clearTimeout(releaseTimer);
  releaseTimer = null;
}

/** Paused, the player goes after a while; playing again, it stays. Only the
 *  page goes: the music is still the card's, paused where it was, and its
 *  play button loads the page again from there (`play`, `load`). */
function scheduleRelease() {
  cancelRelease();
  releaseTimer = window.setTimeout(() => {
    releaseTimer = null;
    if (frame && !playing) tearDown();
  }, RELEASE_PAUSED_AFTER_MS);
}

window.addEventListener("message", (event) => {
  if (event.origin !== EMBED_ORIGIN || !frame || event.source !== frame.contentWindow) return;
  let data: { event?: string; info?: unknown };
  try {
    data = typeof event.data === "string" ? JSON.parse(event.data) : event.data;
  } catch {
    return;
  }
  // It answered; no need to keep asking.
  if (listenTimer != null) {
    window.clearInterval(listenTimer);
    listenTimer = null;
  }

  let moved = false;
  if (data.event === "onStateChange" && typeof data.info === "number") {
    moved = applyState(data.info) || moved;
  } else if (data.event === "infoDelivery" && data.info && typeof data.info === "object") {
    const info = data.info as {
      currentTime?: number;
      duration?: number;
      playerState?: number;
      videoData?: { title?: string; author?: string; errorCode?: string | null };
    };
    if (typeof info.playerState === "number") moved = applyState(info.playerState) || moved;
    if (typeof info.duration === "number" && info.duration > 0 && info.duration !== duration) {
      duration = info.duration;
      moved = true;
    }
    if (info.videoData?.title && info.videoData.title !== title) {
      title = info.videoData.title;
      moved = true;
    }
    if (info.videoData?.author && info.videoData.author !== author) {
      author = info.videoData.author;
      moved = true;
    }
    if (info.videoData?.errorCode) console.warn("christmas music:", info.videoData.errorCode);
    if (typeof info.currentTime === "number") {
      const now = performance.now();
      if (moved || now - lastReport > REPORT_EVERY_MS) {
        anchorTime = info.currentTime;
        anchorAt = now;
        lastReport = now;
        moved = true;
      }
    }
  }
  if (moved) changed();
});

/** YouTube's player states: 1 playing, 2 paused, 0 ended, 3 buffering. */
function applyState(state: number): boolean {
  if (state === 0) {
    // In case the embed's own loop does not.
    command("seekTo", [0, true]);
    command("playVideo");
  }
  // Buffering is still playing, as far as anyone listening can tell.
  const now = state === 1 || state === 3;
  if (now === playing) return false;
  anchorTime = elapsedNow();
  anchorAt = performance.now();
  playing = now;
  if (playing) cancelRelease();
  else scheduleRelease();
  return true;
}

/** In season — always in a dev build, the way the snow is. */
export function christmasSeasonOpen(): boolean {
  return import.meta.env.DEV || isFestiveSeason();
}

export const ChristmasMusic = {
  /** The Christmas music is what the player card shows — paused included. */
  get active(): boolean {
    return active;
  },

  get playing(): boolean {
    return playing;
  },

  set onChange(fn: () => void) {
    changed = fn;
  },

  /** The launch greeting: in season, with the setting on, once per run. */
  startWithGreeting() {
    if (startedWithGreeting || !christmasSeasonOpen()) return;
    if (!State.settings.christmasMusic || !State.settings.enabled) return;
    startedWithGreeting = true;
    this.play();
  },

  /**
   * The Christmas music becomes what is playing. Whatever else was playing is
   * paused first — two songs at once is never what a click on the folder
   * meant.
   */
  play() {
    if (!State.settings.enabled) return;
    if (otherPlaying) {
      otherPlaying = false;
      void Bridge.mediaCommand("pause");
    }
    activatedAt = performance.now();
    active = true;
    if (!frame) load();
    else command("playVideo");
    changed();
  },

  pause() {
    command("pauseVideo");
  },

  toggle() {
    if (playing) this.pause();
    else this.play();
  },

  seek(to: number) {
    const target = Math.max(0, duration > 0 ? Math.min(to, duration - 1) : to);
    anchorTime = target;
    anchorAt = performance.now();
    command("seekTo", [target, true]);
    changed();
  },

  /** Off entirely: the setting, or the master switch. */
  stop() {
    if (!active && !frame) return;
    tearDown();
    active = false;
    changed();
  },

  /**
   * What GSMTC reported. Another app starting to play is the user choosing it
   * over the Christmas music, which then steps aside — after the grace, since
   * the app the folder just paused takes a moment to say so.
   */
  observeSystem(media: MediaState) {
    otherPlaying = media.isPlaying && !this.isOwn(media);
    if (!active || !media.isPlaying || this.isOwn(media)) return;
    if (performance.now() - activatedAt < YIELD_GRACE_MS) return;
    tearDown();
    active = false;
    changed();
  },

  /**
   * The island's own WebView2, if GSMTC reports it: our iframe, not somebody
   * else's song.
   */
  isOwn(media: MediaState): boolean {
    const id = media.sourceId.toLowerCase();
    return id.includes("msedgewebview2")
      || id.includes("coucou")
      || id.includes("notchy")
      || (title !== "" && media.title === title);
  },

  /** The card's commands, while the card is showing this. */
  command(action: MediaAction, value?: number) {
    switch (action) {
      case "play": this.play(); break;
      case "pause": this.pause(); break;
      case "playpause": this.toggle(); break;
      // One long compilation: there is no next, and previous is its start.
      case "next": break;
      case "previous": this.seek(0); break;
      case "seek": this.seek(value ?? 0); break;
    }
  },

  /** The track as the card draws it. */
  media(): MediaState {
    return {
      hasTrack: true,
      isPlaying: playing,
      title: title || t("Notchy's Christmas music"),
      artist: author,
      album: "",
      elapsed: elapsedNow(),
      duration,
      sourceName: SOURCE_NAME,
      sourceId: SOURCE_ID,
      artwork: CHRISTMAS_ARTWORK,
    };
  },
};

/**
 * The card's transport, wherever the track is coming from: the Christmas
 * music while it is the source, the system's player otherwise.
 */
export function mediaCommand(action: MediaAction, value?: number): void {
  if (active) ChristmasMusic.command(action, value);
  else void Bridge.mediaCommand(action, value);
}
