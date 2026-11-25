// Dev harness: the Now Playing card in a plain browser, with fake playback, so
// the layout can be checked without a media session. Not part of the app bundle.
//
// It imports the stylesheet, which `upload-preview.ts` does not: that view is
// painted on a canvas, and this one is DOM.

import "../src/style.css";
import { buildNowPlaying, type VolumeSource } from "../src/views/nowplaying";
import { tickMiniBots } from "../src/mochi/minibots";
import { EMPTY_MEDIA, State } from "../src/core/state";
import type { MediaState } from "../src/core/bridge";
import { ChristmasMusic } from "../src/island/christmasMusic";

/** A 1×1 cover, scaled up by `object-fit` — enough to prove the square fills. */
const COVER =
  "data:image/svg+xml;base64," +
  btoa(
    `<svg xmlns="http://www.w3.org/2000/svg" width="300" height="300">
       <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
         <stop offset="0" stop-color="#2b2f3a"/><stop offset="1" stop-color="#6b4250"/>
       </linearGradient></defs>
       <rect width="300" height="300" fill="url(#g)"/>
       <circle cx="150" cy="150" r="54" fill="#0e0f11"/>
       <circle cx="150" cy="150" r="10" fill="#8e939c"/>
     </svg>`,
  );

/** A stand-in app icon: what Rust hands over is a PNG, this is any image. */
const ICON =
  "data:image/svg+xml;base64," +
  btoa(`<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><circle cx="16" cy="16" r="15" fill="#1ed760"/>
    <path d="M8 12c6-2 12-1.5 16 1M9 16.5c5-1.5 10-1 13.5 1M10 21c4-1 8-.7 11 .8" stroke="#000" stroke-width="2.4" fill="none" stroke-linecap="round"/></svg>`);

const PLAYING: MediaState = {
  hasTrack: true,
  isPlaying: true,
  title: "What I Really Wanted",
  artist: "Clinton Shorter",
  album: "The Expanse",
  elapsed: 53,
  duration: 158,
  sourceName: "Spotify",
  sourceId: "Spotify.exe",
  artwork: COVER,
  rate: 1,
  sourceIcon: ICON,
};

/** A volume the harness owns, since a plain browser has no output to ask. */
function fakeVolume(level: number | null, muted = false): VolumeSource {
  let state = level == null ? null : { level, muted };
  return {
    get: async () => state && { ...state },
    set: async (l) => { if (state) state = { level: l, muted: l > 0 ? false : state.muted }; },
    setMuted: async (m) => { if (state) state = { ...state, muted: m }; },
  };
}
const shown = { onScreen: () => true };

// Three cards, each reading the same global State — so they are swapped by
// pointing State at the right value just before each one syncs.
const hosts = {
  mac: { el: document.getElementById("mac")!, host: buildNowPlaying({ ...shown, volume: fakeVolume(0.85) }), media: PLAYING },
  muted: { el: document.getElementById("muted")!, host: buildNowPlaying({ ...shown, volume: fakeVolume(0.4, true) }), media: { ...PLAYING, isPlaying: false } },
  novolume: { el: document.getElementById("novolume")!, host: buildNowPlaying({ ...shown, volume: fakeVolume(null) }), media: { ...PLAYING, sourceIcon: "" } },
  playing: { el: document.getElementById("playing")!, host: buildNowPlaying({ ...shown, volume: fakeVolume(0.6) }), media: PLAYING },
  noart: {
    el: document.getElementById("noart")!,
    host: buildNowPlaying({ ...shown, volume: fakeVolume(0.6) }),
    media: { ...PLAYING, artwork: "", sourceIcon: "", title: "Secret Place", artist: "Gabe", sourceName: "Chrome", sourceId: "chrome.exe" },
  },
  idle: { el: document.getElementById("idle")!, host: buildNowPlaying(shown), media: EMPTY_MEDIA },
  // The real Christmas player, iframe and all: Spotify until the folder (or
  // the button) is clicked, then the Christmas music as the card shows it.
  christmas: { el: document.getElementById("christmas")!, host: buildNowPlaying({ ...shown, volume: fakeVolume(0.6) }), media: PLAYING },
};

for (const entry of Object.values(hosts)) {
  entry.host.el.classList.add("on");
  entry.el.append(entry.host.el);
}

document.getElementById("christmas-play")!.addEventListener("click", () => ChristmasMusic.play());
document.getElementById("christmas-stop")!.addEventListener("click", () => ChristmasMusic.stop());

document.getElementById("toggle")!.addEventListener("click", () => {
  for (const entry of Object.values(hosts)) {
    entry.media = { ...entry.media, isPlaying: !entry.media.isPlaying };
  }
});

const clock = document.getElementById("clock")!;
let last = performance.now();

function loop(now: number) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  for (const [name, entry] of Object.entries(hosts)) {
    State.media = name === "christmas" && ChristmasMusic.active ? ChristmasMusic.media() : entry.media;
    entry.host.sync();
    entry.host.tick?.(now);
  }
  tickMiniBots(dt);
  clock.textContent = hosts.playing.media.isPlaying ? "playing" : "paused";
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
