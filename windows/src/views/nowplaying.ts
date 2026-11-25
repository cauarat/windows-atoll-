// The Now Playing card — port of NowPlayingCardView.swift, with the Christmas
// album of ChristmasAlbumView.swift on its left.
//
// Artwork, what is playing, where it has got to, transport, and the volume. The
// two corners of the artwork are the point: Mochi sits on the bottom right,
// listening to it with you, and the bottom left says which application it is
// coming from.
//
// Reached two ways, exactly as on the Mac: Home on automatic while something is
// loaded, or the Now Playing pill in focus. Both show this one card.
//
// Laid out the way SwiftUI lays the Mac's out, value for value: an HStack(14)
// padded 14 x 12, the artwork centred in it, and a VStack(spacing: 0) that fills
// its height — titles, Spacer(min 6), scrubber, Spacer(min 8), transport, and
// Spacer(min 8) + volume while the output has one. The spacers share what is
// left equally, as SwiftUI's do. Every symbol is drawn in the frame its SF
// Symbol takes there (npGlyphs.ts), so the five buttons sit where the Mac's do.

import { MUSIC_COLOR, State, type AgentTask } from "../core/state";
import { Bridge, type MediaAction, type VolumeState } from "../core/bridge";
import {
  ChristmasMusic, christmasArtwork, christmasSeasonOpen, loadChristmasArtwork, mediaCommand,
} from "../island/christmasMusic";
import { createMiniBot, releaseMiniBot } from "../mochi/minibots";
import { clear, h } from "./dom";
import {
  backwardGlyph, forwardGlyph, glyphSvg, noteGlyph, pauseGlyph, playGlyph, skipGlyph, snowflakeGlyph,
  speakerGlyph, speakerMutedGlyph,
} from "./npGlyphs";
import { card } from "./views";
import type { ViewHost } from "./views";
import { t } from "../core/i18n";

/**
 * `m:ss`, or `h:mm:ss` for anything long enough to need it.
 *
 * Exported because it and `estimatedElapsed` are the only arithmetic on this
 * side rather than markup, and are worth reaching from a harness.
 */
export function clock(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) return "0:00";
  const total = Math.round(seconds);
  const h3 = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = (n: number) => String(n).padStart(2, "0");
  return h3 > 0 ? `${h3}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

/**
 * Where playback has got to now, extrapolated from the last sample.
 *
 * Rust only emits when something changes, so between events this is what moves
 * the bar — the same job `PlaybackState.estimatedTime(at:)` does on the Mac,
 * at the player's own rate: a podcast at 1.5x moves the bar half as fast again.
 */
export function estimatedElapsed(
  elapsed: number,
  duration: number,
  isPlaying: boolean,
  sinceSeconds: number,
  rate = 1,
): number {
  const speed = rate > 0 ? rate : 1;
  const advanced = isPlaying ? elapsed + Math.max(0, sinceSeconds) * speed : elapsed;
  if (duration <= 0) return Math.max(0, advanced);
  return Math.min(Math.max(advanced, 0), duration);
}

/** Where the volume row reads and writes. Rust by default; the dev harness
 *  hands in its own, since a plain browser has no output to ask. */
export interface VolumeSource {
  get(): Promise<VolumeState | null>;
  set(level: number): Promise<unknown>;
  setMuted(muted: boolean): Promise<unknown>;
}

const SYSTEM_VOLUME: VolumeSource = {
  get: () => Bridge.volumeGet(),
  set: (level) => Bridge.volumeSet(level),
  setMuted: (muted) => Bridge.volumeSetMuted(muted),
};

/** How often the volume is asked again while the card is up and playing — the
 *  Mac's card re-reads it on its half-second tick. */
const VOLUME_EVERY_MS = 500;

/** The pill's own task when it is loaded, and something the same colour when
 *  it is not — the card is reachable with the pill switched off. */
function mochiTask(): AgentTask {
  return State.tasks.find((task) => task.id === "integration_music") ?? {
    id: "integration_music", name: "Now Playing", color: MUSIC_COLOR, state: "idle",
    stepIndex: 0, steps: [], source: "n8n", isIntegration: true,
  };
}

export function buildNowPlaying(opts: { volume?: VolumeSource; onScreen?: () => boolean } = {}): ViewHost {
  const volumeSource = opts.volume ?? SYSTEM_VOLUME;
  // The Mac's `onScreen`: expanded, on Home, with the player on it. Mini Mochi
  // and the volume clock only run while that holds.
  const onScreen = opts.onScreen
    ?? (() => State.mode === "expanded" && State.view === "overview" && State.homeShowsPlayer);

  // Empty state. Deliberately the same shape as the message card's — one line
  // in the gutter Mochi keeps, because with nothing loaded he is back at his
  // usual size on the left.
  const empty = h("div", { class: "np-empty" });

  // ── Artwork, and the two corners ──────────────────────────────────────────
  const art = h("div", { class: "np-art" });
  const artImg = h("img", { class: "np-img", alt: "" }) as HTMLImageElement;
  // Not every player sends art; the square must not collapse.
  const artFallback = h("div", { class: "np-img np-img-none" }, glyphSvg(noteGlyph(20)));

  // Bottom left: which application it is coming from — the application's own
  // icon, or the note when there is none to show.
  const sourceIcon = h("img", { class: "np-source-icon", alt: "" }) as HTMLImageElement;
  const sourceNote = h("span", { class: "np-source-note" }, glyphSvg(noteGlyph(9)));
  const sourceBadge = h("div", { class: "np-badge np-source" }, sourceIcon, sourceNote);
  sourceIcon.addEventListener("error", () => {
    sourceIcon.classList.remove("on");
    sourceNote.classList.add("on");
  });

  // Bottom right: Mochi, on the record, listening along. Made when he can be
  // seen and let go when he cannot — `createMiniBot` registers a canvas the
  // island ticks every frame, and the Mac only builds his while he is shown.
  const mochiSlot = h("div", { class: "np-badge np-mochi" });
  let mochi: HTMLElement | null = null;
  function syncMochi(show: boolean) {
    if (show && !mochi) {
      // He dances while it plays, the way he does for the pill.
      mochi = createMiniBot(mochiTask(), 23, { dancing: () => State.media.isPlaying });
      mochiSlot.append(mochi);
    } else if (!show && mochi) {
      const canvas = mochi.querySelector("canvas");
      if (canvas) releaseMiniBot(canvas);
      mochi.remove();
      mochi = null;
    }
    mochiSlot.classList.toggle("on", show);
  }
  art.append(artImg, artFallback, sourceBadge, mochiSlot);

  // ── The Christmas album ───────────────────────────────────────────────────
  // In season, while something else is on the card, the Christmas album waits
  // on the left in a slot of its own; a click opens it into the main view and
  // the Christmas music picks up where it stopped. While it is what plays, it
  // is the main art and the slot folds away. Twin of ChristmasAlbumView.swift.
  // The cover is the video's thumbnail, over a drawn sleeve until it loads.
  const xmasImg = h("img", { class: "np-xmas-img", alt: "" }) as HTMLImageElement;
  xmasImg.addEventListener("load", () => xmasImg.classList.add("on"));
  xmasImg.addEventListener("error", () => xmasImg.classList.remove("on"));
  const sleeveFlake = glyphSvg(snowflakeGlyph(26));
  const badgeFlake = glyphSvg(snowflakeGlyph(8));
  const xmasAlbum = h("div", { class: "np-xmas-album" },
    h("div", { class: "np-xmas-cover" },
      h("div", { class: "np-xmas-sleeve" }, sleeveFlake),
      xmasImg),
    // The same disc the main art's source badge sits on, with a snowflake. On
    // the album, so it tilts with it.
    h("div", { class: "np-xmas-badge" }, h("i"), badgeFlake));
  const xmas = h("button", {
    class: "np-xmas",
    title: t("Play Notchy's Christmas music"),
    onclick: () => ChristmasMusic.play(),
  }, xmasAlbum);
  let xmasShown = false;

  /** In from the left when something else takes the card; out towards the
   *  artwork, growing, when a click opens it there. */
  function showAlbum(show: boolean) {
    if (show === xmasShown) return;
    xmasShown = show;
    if (show) {
      // The insertion starts from the left with no transition, then moves.
      xmas.classList.add("entering");
      void xmas.offsetWidth;
      xmas.classList.remove("entering");
    }
    xmas.classList.toggle("on", show);
  }

  // ── The rows ──────────────────────────────────────────────────────────────
  const title = h("div", { class: "np-title" });
  const sub = h("div", { class: "np-sub" });
  const titles = h("div", { class: "np-titles" }, title, sub);

  const fill = h("div", { class: "np-fill" });
  const bar = h("div", { class: "np-bar" }, fill);
  const nowText = h("span", {});
  const totalText = h("span", {});
  const times = h("div", { class: "np-times" }, nowText, totalText);
  const scrubber = h("div", { class: "np-scrub" }, bar, times);

  // Outside the track buttons, not between them: back and forward move
  // within one thing, previous and next move between things, and the pair
  // that leaves the track belongs on the outside. Same order every video
  // player uses. Rebuilt on sync, because the number on them is a setting.
  // Plain glyphs, as on the Mac: no hover disc, no tooltip on the track
  // buttons — only the jumps say how far they go.
  const skipBack = h("button", { class: "np-btn", onclick: () => skip(false) });
  const prev = h("button", { class: "np-btn", onclick: () => send("previous") }, glyphSvg(backwardGlyph()));
  const playPause = h("button", { class: "np-btn", onclick: () => send("playpause") });
  const next = h("button", { class: "np-btn", onclick: () => send("next") }, glyphSvg(forwardGlyph()));
  const skipFwd = h("button", { class: "np-btn", onclick: () => skip(true) });
  const transport = h("div", { class: "np-transport" }, skipBack, prev, playPause, next, skipFwd);

  // ── Volume ────────────────────────────────────────────────────────────────
  // The output volume, or no row at all when the output has none of its own:
  // no slider is better than one that moves and changes nothing.
  const muteBtn = h("button", { class: "np-mute" });
  const volFill = h("div", { class: "np-vol-fill" });
  const volTrack = h("div", { class: "np-vol-track" }, volFill);
  const volumeRow = h("div", { class: "np-vol" }, muteBtn, volTrack);
  const volumeGap = h("div", { class: "np-space np-space-8 np-vol-gap" });

  const main = h("div", { class: "np-main" },
    titles,
    h("div", { class: "np-space np-space-6" }),
    scrubber,
    h("div", { class: "np-space np-space-8" }),
    transport,
    volumeGap,
    volumeRow);
  const player = h("div", { class: "np" }, xmas, art, main);
  const body = card(null, empty, player);
  const el = h("div", { class: "view np-view" }, body);

  /** Jump by the configured number of seconds, clamped to the track. */
  function skip(forward: boolean): void {
    const media = State.media;
    if (!media.hasTrack) return;
    const by = forward ? State.settings.skipForwardSeconds : -State.settings.skipBackSeconds;
    // The same extrapolation the bar is drawn from, or a jump taken between
    // two Rust events would be measured from a stale anchor.
    const since = (performance.now() - sampledAt) / 1000;
    const now = estimatedElapsed(media.elapsed, media.duration, media.isPlaying, since, media.rate);
    const total = media.duration;
    // A second short of the end rather than the end itself: some players read
    // a seek to the duration as "the track finished" and move on.
    const target = total > 0
      ? Math.min(Math.max(now + by, 0), total - 1)
      : Math.max(now + by, 0);
    mediaCommand("seek", target);
  }

  // ── Scrubbing ─────────────────────────────────────────────────────────────
  // Dragging the bar: the thumb follows the pointer, and playback is only told
  // where to go on release. The dragged position is then held briefly, because
  // the player takes a moment to report the new one and letting go sooner makes
  // the bar jump back to where the song was before the drag.
  let scrubbing: number | null = null;
  let holdUntil = 0;

  function fractionAt(event: PointerEvent, of: HTMLElement): number {
    const box = of.getBoundingClientRect();
    if (box.width <= 0) return 0;
    return Math.min(Math.max((event.clientX - box.left) / box.width, 0), 1);
  }

  /** Capture so a drag that leaves the element keeps arriving. It throws when
   *  the pointer is not active, which must not abort the drag. */
  function capture(of: HTMLElement, event: PointerEvent) {
    try {
      of.setPointerCapture(event.pointerId);
    } catch {
      /* not capturable — dragging still works while the pointer is over it */
    }
  }

  bar.addEventListener("pointerdown", (event) => {
    capture(bar, event);
    scrubbing = fractionAt(event, bar) * Math.max(State.media.duration, 0.01);
    paintClock();
  });
  bar.addEventListener("pointermove", (event) => {
    if (scrubbing == null) return;
    scrubbing = fractionAt(event, bar) * Math.max(State.media.duration, 0.01);
    paintClock();
  });
  const release = (event: PointerEvent) => {
    if (scrubbing == null) return;
    const target = fractionAt(event, bar) * Math.max(State.media.duration, 0.01);
    mediaCommand("seek", target);
    // Deliberately still set: releasing is not the moment to go back to what
    // the player last said, which is where the song was before the drag.
    scrubbing = target;
    holdUntil = performance.now() + 400;
    paintClock();
    window.setTimeout(() => {
      if (performance.now() >= holdUntil) scrubbing = null;
    }, 420);
  };
  bar.addEventListener("pointerup", release);
  bar.addEventListener("pointercancel", release);

  // ── The volume, read and written ──────────────────────────────────────────
  let volume: VolumeState | null = null;
  /** Held while dragging, so the bar follows the pointer rather than waiting
   *  for the audio service to be asked again — the Mac's `draggedVolume`. */
  let draggedVolume: number | null = null;
  let volumeReadAt = -Infinity;
  let reading = false;
  /** One write in flight at a time, the latest level waiting behind it: a drag
   *  sends a pointer event a frame, and the audio service need not see each. */
  let writing = false;
  let pendingLevel: number | null = null;

  async function readVolume() {
    if (reading) return;
    reading = true;
    volumeReadAt = performance.now();
    try {
      volume = await volumeSource.get();
    } finally {
      reading = false;
    }
    paintVolume();
  }

  async function writeLevel(level: number) {
    pendingLevel = level;
    if (writing) return;
    writing = true;
    try {
      while (pendingLevel != null) {
        const next = pendingLevel;
        pendingLevel = null;
        await volumeSource.set(next);
      }
    } finally {
      writing = false;
    }
  }

  function paintVolume() {
    const shown = volume != null;
    volumeRow.classList.toggle("on", shown);
    volumeGap.classList.toggle("on", shown);
    if (!volume) return;
    const level = draggedVolume ?? volume.level;
    volFill.style.width = `${Math.min(Math.max(level, 0), 1) * 100}%`;
    const muted = volume.muted;
    if (muteBtn.dataset.muted !== String(muted)) {
      muteBtn.dataset.muted = String(muted);
      clear(muteBtn);
      muteBtn.append(glyphSvg(muted ? speakerMutedGlyph() : speakerGlyph()));
    }
  }

  muteBtn.addEventListener("click", () => {
    if (!volume) return;
    const muted = !volume.muted;
    volume = { ...volume, muted };
    paintVolume();
    void volumeSource.setMuted(muted).then(() => readVolume());
  });

  volTrack.addEventListener("pointerdown", (event) => {
    if (!volume) return;
    capture(volTrack, event);
    draggedVolume = fractionAt(event, volTrack);
    // Off zero un-mutes, as `SystemVolume.setLevel` does; drawn at once.
    if (draggedVolume > 0) volume = { ...volume, muted: false };
    paintVolume();
    void writeLevel(draggedVolume);
  });
  volTrack.addEventListener("pointermove", (event) => {
    if (draggedVolume == null || !volume) return;
    draggedVolume = fractionAt(event, volTrack);
    if (draggedVolume > 0) volume = { ...volume, muted: false };
    paintVolume();
    void writeLevel(draggedVolume);
  });
  const letGo = () => {
    if (draggedVolume == null) return;
    if (volume) volume = { ...volume, level: draggedVolume };
    draggedVolume = null;
    paintVolume();
    void readVolume();
  };
  volTrack.addEventListener("pointerup", letGo);
  volTrack.addEventListener("pointercancel", letGo);

  /** When the state on screen was sampled, so the clock can advance from it. */
  let sampledAt = performance.now();
  let lastSignature = "";
  let wasOnScreen = false;

  /**
   * Everything that changes once a track, not once a frame.
   *
   * Split from `paintClock` because `tick` runs every frame: rebuilding the
   * artist row, the badge and the transport glyph sixty times a second is a lot
   * of DOM for text that changes when the song does. `sync` calls this only
   * when the signature it computes has moved — the same guard `buildOverview`
   * uses with `cardKey`.
   */
  function paintTrack() {
    const media = State.media;

    empty.classList.toggle("on", !media.hasTrack);
    player.classList.toggle("on", media.hasTrack);
    if (!media.hasTrack) {
      empty.textContent = t("Nothing playing.");
      showAlbum(false);
      return;
    }

    title.textContent = media.title;

    // In season, while something other than the Christmas music is on the
    // card, the Christmas album waits on the left. Its cover is fetched the
    // first time it shows, so it wears it before the first click.
    const album = christmasSeasonOpen() && !ChristmasMusic.active;
    if (album) {
      loadChristmasArtwork();
      const cover = christmasArtwork();
      if (xmasImg.getAttribute("src") !== cover) xmasImg.src = cover;
    }
    showAlbum(album);

    clear(sub);
    if (media.artist) sub.append(h("span", { class: "np-artist", text: media.artist }));
    // Which application it is coming from. Reading the system rather than one
    // music app is only worth anything if the card can say so — this is where
    // Chrome or WhatsApp shows up.
    if (media.sourceName) {
      sub.append(h("span", { class: "np-dot", text: "·" }));
      sub.append(h("span", { class: "np-source-name", text: media.sourceName }));
    }

    const hasArt = media.artwork.length > 0;
    artImg.classList.toggle("on", hasArt);
    artFallback.classList.toggle("on", !hasArt);
    if (hasArt && artImg.getAttribute("src") !== media.artwork) artImg.src = media.artwork;

    const hasIcon = media.sourceIcon.length > 0;
    if (hasIcon && sourceIcon.getAttribute("src") !== media.sourceIcon) sourceIcon.src = media.sourceIcon;
    sourceIcon.classList.toggle("on", hasIcon);
    sourceNote.classList.toggle("on", !hasIcon);
    sourceBadge.title = media.sourceName ? `Playing from ${media.sourceName}` : "";

    clear(playPause);
    playPause.append(glyphSvg(media.isPlaying ? pauseGlyph() : playGlyph()));

    // Redrawn here and not once at build time: the number on them is a
    // setting, and Settings is a window of its own that can change it while
    // the island is open.
    const back = State.settings.skipBackSeconds;
    const fwd = State.settings.skipForwardSeconds;
    clear(skipBack);
    skipBack.append(glyphSvg(skipGlyph(back, false)));
    skipBack.title = `Back ${back}s`;
    clear(skipFwd);
    skipFwd.append(glyphSvg(skipGlyph(fwd, true)));
    skipFwd.title = `Forward ${fwd}s`;

    totalText.textContent = clock(media.duration);
  }

  /** The bar and the left-hand time: the only two things a frame can move. */
  function paintClock() {
    const media = State.media;
    if (!media.hasTrack) return;

    const since = (performance.now() - sampledAt) / 1000;
    const elapsed =
      scrubbing ?? estimatedElapsed(media.elapsed, media.duration, media.isPlaying, since, media.rate);

    const total = Math.max(media.duration, 0.01);
    fill.style.width = `${Math.min(Math.max(elapsed / total, 0), 1) * 100}%`;
    nowText.textContent = clock(elapsed);
  }

  /** What only matters while the card can be seen: Mini Mochi, and keeping the
   *  volume current. Asked again the moment it comes up, and then on the
   *  Mac's half-second clock while something plays. */
  function syncOnScreen(nowMs: number) {
    const shown = onScreen();
    syncMochi(shown && !State.settings.hideCharacters && State.media.hasTrack);
    if (shown && !wasOnScreen) void readVolume();
    else if (shown && State.media.isPlaying && draggedVolume == null && nowMs - volumeReadAt > VOLUME_EVERY_MS) {
      void readVolume();
    }
    wasOnScreen = shown;
  }

  return {
    el,
    sync() {
      // A new sample resets the clock this card advances from. Everything else
      // is repainted every frame by `tick`, so this only has to notice.
      const media = State.media;
      const signature = [
        media.hasTrack, media.isPlaying, media.title, media.artist, media.rate,
        media.duration, media.elapsed, media.sourceId, media.artwork.length, media.sourceIcon.length,
        ChristmasMusic.active, christmasArtwork(), State.settings.skipBackSeconds, State.settings.skipForwardSeconds,
      ].join("~");
      if (signature !== lastSignature) {
        lastSignature = signature;
        sampledAt = performance.now();
        paintTrack();
      }
      syncOnScreen(performance.now());
      paintClock();
    },
    tick(nowMs: number) {
      syncOnScreen(nowMs);
      paintClock();
    },
  };
}

function send(action: MediaAction) {
  mediaCommand(action);
}

/**
 * The jump-by-N dial, with N written inside it — the voice message's player
 * (message.ts) draws its jumps with this; the Now Playing card's own are
 * npGlyphs.ts's `skipGlyph`, measured off the Mac's symbol.
 *
 * Drawn here rather than kept in ICONS because the number is part of the
 * glyph and the number is a setting — the whole point of the button is that
 * it says how far it goes. The Mac gets this from SF Symbols' `goforward.N`
 * for eight values and writes the number onto a plain dial for the rest; here
 * there is only the one drawing, so it always carries its own text.
 *
 * An arc of 320° about (12,12), open at the top, with the arrowhead filling
 * the gap on the side it travels towards.
 */
export function skipIcon(seconds: number, forward: boolean, size = 15): SVGSVGElement {
  const NS = "http://www.w3.org/2000/svg";
  const el = document.createElementNS(NS, "svg");
  el.setAttribute("viewBox", "0 0 24 24");
  el.setAttribute("width", String(size));
  el.setAttribute("height", String(size));
  el.setAttribute("aria-hidden", "true");

  const arc = document.createElementNS(NS, "path");
  // Ends at 110° and 70° about (12,12), which leaves the gap centred on the
  // top. One path for both directions: the arc is symmetric, so only the
  // arrowhead moves — and the sweep flag that would mirror it instead puts
  // the circle's centre on the other side of the chord, which hangs the whole
  // dial above the viewBox and leaves two slivers showing.
  arc.setAttribute("d", "M 9.44 4.95 A 7.5 7.5 0 1 0 14.56 4.95");
  arc.setAttribute("fill", "none");
  arc.setAttribute("stroke", "currentColor");
  arc.setAttribute("stroke-width", "2");
  arc.setAttribute("stroke-linecap", "round");
  el.append(arc);

  const head = document.createElementNS(NS, "path");
  head.setAttribute(
    "d",
    forward
      ? "M 13.0 1.9 L 17.6 4.95 L 13.0 8.0 Z"
      : "M 11.0 1.9 L 6.4 4.95 L 11.0 8.0 Z",
  );
  head.setAttribute("fill", "currentColor");
  el.append(head);

  const text = document.createElementNS(NS, "text");
  text.setAttribute("x", "12");
  text.setAttribute("y", "16.4");
  text.setAttribute("text-anchor", "middle");
  // Three digits would otherwise touch the dial on both sides.
  text.setAttribute("font-size", seconds >= 100 ? "7.5" : "10");
  text.setAttribute("font-weight", "600");
  text.setAttribute("fill", "currentColor");
  text.textContent = String(seconds);
  el.append(text);

  return el;
}
