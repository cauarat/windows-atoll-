// The Now Playing card — port of NowPlayingCardView.swift.
//
// Artwork, what is playing, where it has got to, and transport. The two corners
// of the artwork are the point: Mochi sits on the bottom right, listening to it
// with you, and the bottom left says which application it is coming from.
//
// Reached two ways, exactly as on the Mac: Home on automatic while something is
// loaded, or the Now Playing pill in focus. Both show this one card.

import { MUSIC_COLOR, State } from "../core/state";
import { Bridge, type MediaAction } from "../core/bridge";
import { createMiniBot } from "../mochi/minibots";
import { clear, h, svg } from "./dom";
import { ICONS } from "./icons";
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
 * the bar — the same job `PlaybackState.estimatedTime(at:)` does on the Mac.
 */
export function estimatedElapsed(
  elapsed: number,
  duration: number,
  isPlaying: boolean,
  sinceSeconds: number,
): number {
  const advanced = isPlaying ? elapsed + Math.max(0, sinceSeconds) : elapsed;
  if (duration <= 0) return Math.max(0, advanced);
  return Math.min(Math.max(advanced, 0), duration);
}

/**
 * The colour behind the source mark.
 *
 * Windows reports an AUMID, not an icon, so the Mac's "draw the application's
 * real icon" is not available here. A brand colour under the application's own
 * initial is the next most honest thing: both come from what the system said,
 * and neither claims to know which website a browser is on.
 */
export function sourceTint(sourceId: string, sourceName: string): string {
  const key = `${sourceId} ${sourceName}`.toLowerCase();
  for (const [needle, colour] of [
    ["spotify", "#1DB954"],
    ["chrome", "#4285F4"],
    ["edge", "#0F7EBF"],
    ["firefox", "#FF7139"],
    ["brave", "#FB542B"],
    ["opera", "#FF1B2D"],
    ["vlc", "#FF8800"],
    ["itunes", "#FA2D48"],
    ["apple music", "#FA2D48"],
    ["media player", "#0078D4"],
    ["mattermost", "#1B6FF3"],
    ["clickmassa", "#41BFEF"],
  ] as const) {
    if (key.includes(needle)) return colour;
  }
  return "#2A2E35";
}

export function buildNowPlaying(): ViewHost {
  // Empty state. Deliberately the same shape as the message card's — one line
  // in the gutter Mochi keeps, because with nothing loaded he is back at his
  // usual size on the left.
  const empty = h("div", { class: "np-empty" });

  const art = h("div", { class: "np-art" });
  const artImg = h("img", { class: "np-img", alt: "" }) as HTMLImageElement;
  const artFallback = h("div", { class: "np-img np-img-none" }, svg(ICONS.musicNote, 20));

  const sourceBadge = h("div", { class: "np-badge np-source" });
  // Built once and kept: `createMiniBot` registers a canvas the island's own
  // loop ticks, and making a new one on every sync would leave the old ones
  // drawing until something pruned them.
  // Not built at all when the characters are off: the corner of the artwork is
  // the only thing it was ever for.
  const badges: Node[] = [];
  if (!State.settings.hideCharacters) {
    const mochi = createMiniBot(
      { id: "integration_music", name: "Now Playing", color: MUSIC_COLOR, state: "idle", stepIndex: 0, steps: [], source: "n8n", isIntegration: true },
      23,
    );
    badges.push(h("div", { class: "np-badge np-mochi" }, mochi));
  }
  art.append(artImg, artFallback, sourceBadge, ...badges);

  const title = h("div", { class: "np-title" });
  const sub = h("div", { class: "np-sub" });

  const fill = h("div", { class: "np-fill" });
  const bar = h("div", { class: "np-bar" }, fill);
  const nowText = h("span", {});
  const totalText = h("span", {});
  const times = h("div", { class: "np-times" }, nowText, totalText);

  // Outside the track buttons, not between them: back and forward move
  // within one thing, previous and next move between things, and the pair
  // that leaves the track belongs on the outside. Same order every video
  // player uses. Rebuilt on sync, because the number on them is a setting.
  const skipBack = h("button", { class: "np-btn", onclick: () => skip(false) });
  const prev = transportButton(ICONS.backward, 13, "Previous", () => send("previous"));
  const playPause = transportButton(ICONS.play, 17, "Play", () => send("playpause"));
  const next = transportButton(ICONS.forward, 13, "Next", () => send("next"));
  const skipFwd = h("button", { class: "np-btn", onclick: () => skip(true) });
  const transport = h("div", { class: "np-transport" },
                      skipBack, prev, playPause, next, skipFwd);

  /** Jump by the configured number of seconds, clamped to the track. */
  function skip(forward: boolean): void {
    const media = State.media;
    if (!media.hasTrack) return;
    const by = forward ? State.settings.skipForwardSeconds : -State.settings.skipBackSeconds;
    // The same extrapolation the bar is drawn from, or a jump taken between
    // two Rust events would be measured from a stale anchor.
    const since = (performance.now() - sampledAt) / 1000;
    const now = estimatedElapsed(media.elapsed, media.duration, media.isPlaying, since);
    const total = media.duration;
    // A second short of the end rather than the end itself: some players read
    // a seek to the duration as "the track finished" and move on.
    const target = total > 0
      ? Math.min(Math.max(now + by, 0), total - 1)
      : Math.max(now + by, 0);
    void Bridge.mediaCommand("seek", target);
  }

  const main = h("div", { class: "np-main" }, title, sub, bar, times, transport);
  const player = h("div", { class: "np" }, art, main);
  const body = card(null, empty, player);
  const el = h("div", { class: "view np-view" }, body);

  // Dragging the bar: the thumb follows the pointer, and playback is only told
  // where to go on release. The dragged position is then held briefly, because
  // the player takes a moment to report the new one and letting go sooner makes
  // the bar jump back to where the song was before the drag.
  let scrubbing: number | null = null;
  let holdUntil = 0;

  function fractionAt(event: PointerEvent): number {
    const box = bar.getBoundingClientRect();
    if (box.width <= 0) return 0;
    return Math.min(Math.max((event.clientX - box.left) / box.width, 0), 1);
  }

  bar.addEventListener("pointerdown", (event) => {
    // Capture so a drag that leaves the bar keeps arriving. It throws when the
    // pointer is not active, which must not be allowed to abort the drag the
    // way it would if this were the first statement unguarded.
    try {
      bar.setPointerCapture(event.pointerId);
    } catch {
      /* not capturable — dragging still works while the pointer is over it */
    }
    scrubbing = fractionAt(event) * Math.max(State.media.duration, 0.01);
    paintClock();
  });
  bar.addEventListener("pointermove", (event) => {
    if (scrubbing == null) return;
    scrubbing = fractionAt(event) * Math.max(State.media.duration, 0.01);
    paintClock();
  });
  const release = (event: PointerEvent) => {
    if (scrubbing == null) return;
    const target = fractionAt(event) * Math.max(State.media.duration, 0.01);
    void Bridge.mediaCommand("seek", target);
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

  /** When the state on screen was sampled, so the clock can advance from it. */
  let sampledAt = performance.now();
  let lastSignature = "";

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
      return;
    }

    title.textContent = media.title;

    clear(sub);
    if (media.artist) sub.append(h("span", { text: media.artist }));
    // Which application it is coming from. Reading the system rather than one
    // music app is only worth anything if the card can say so.
    if (media.sourceName) {
      if (media.artist) sub.append(h("span", { class: "np-dot", text: "·" }));
      sub.append(h("span", { class: "np-source-name", text: media.sourceName }));
    }

    const hasArt = media.artwork.length > 0;
    artImg.classList.toggle("on", hasArt);
    artFallback.classList.toggle("on", !hasArt);
    if (hasArt && artImg.src !== media.artwork) artImg.src = media.artwork;

    // The source mark: the application's own initial over its colour.
    clear(sourceBadge);
    const mark = h("i", { class: "np-source-mark" });
    if (media.sourceName) {
      mark.style.background = sourceTint(media.sourceId, media.sourceName);
      mark.textContent = media.sourceName.slice(0, 1).toUpperCase();
    } else {
      mark.style.background = sourceTint("", "");
      mark.append(svg(ICONS.musicNote, 9));
    }
    sourceBadge.append(mark);
    sourceBadge.title = media.sourceName ? `Playing from ${media.sourceName}` : "";

    clear(playPause);
    playPause.append(svg(media.isPlaying ? ICONS.pause : ICONS.play, 17));
    playPause.title = media.isPlaying ? "Pause" : "Play";

    // Redrawn here and not once at build time: the number on them is a
    // setting, and Settings is a window of its own that can change it while
    // the island is open.
    const back = State.settings.skipBackSeconds;
    const fwd = State.settings.skipForwardSeconds;
    clear(skipBack);
    skipBack.append(skipIcon(back, false));
    skipBack.title = `Back ${back}s`;
    clear(skipFwd);
    skipFwd.append(skipIcon(fwd, true));
    skipFwd.title = `Forward ${fwd}s`;

    totalText.textContent = clock(media.duration);
  }

  /** The bar and the left-hand time: the only two things a frame can move. */
  function paintClock() {
    const media = State.media;
    if (!media.hasTrack) return;

    const since = (performance.now() - sampledAt) / 1000;
    const elapsed =
      scrubbing ?? estimatedElapsed(media.elapsed, media.duration, media.isPlaying, since);

    const total = Math.max(media.duration, 0.01);
    fill.style.width = `${Math.min(Math.max(elapsed / total, 0), 1) * 100}%`;
    nowText.textContent = clock(elapsed);
  }

  return {
    el,
    sync() {
      // A new sample resets the clock this card advances from. Everything else
      // is repainted every frame by `tick`, so this only has to notice.
      const media = State.media;
      const signature = [
        media.hasTrack, media.isPlaying, media.title, media.artist,
        media.duration, media.elapsed, media.sourceId, media.artwork.length,
      ].join("~");
      if (signature !== lastSignature) {
        lastSignature = signature;
        sampledAt = performance.now();
        paintTrack();
      }
      paintClock();
    },
    tick() {
      paintClock();
    },
  };
}

function send(action: MediaAction) {
  void Bridge.mediaCommand(action);
}

function transportButton(
  icon: string,
  size: number,
  title: string,
  onclick: () => void,
): HTMLElement {
  return h("button", { class: "np-btn", title, onclick }, svg(icon, size));
}

/**
 * The jump-by-N dial, with N written inside it.
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
function skipIcon(seconds: number, forward: boolean, size = 15): SVGSVGElement {
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
