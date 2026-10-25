// Dev harness: the Now Playing card in a plain browser, with fake playback, so
// the layout can be checked without a media session. Not part of the app bundle.
//
// It imports the stylesheet, which `upload-preview.ts` does not: that view is
// painted on a canvas, and this one is DOM.

import "../src/style.css";
import { buildNowPlaying } from "../src/views/nowplaying";
import { tickMiniBots } from "../src/mochi/minibots";
import { EMPTY_MEDIA, State } from "../src/core/state";
import type { MediaState } from "../src/core/bridge";

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

const PLAYING: MediaState = {
  hasTrack: true,
  isPlaying: true,
  title: "The Future Is Yours",
  artist: "Kraak & Smaak",
  album: "Remixed",
  elapsed: 163,
  duration: 460,
  sourceName: "Spotify",
  sourceId: "Spotify.exe",
  artwork: COVER,
};

// Three cards, each reading the same global State — so they are swapped by
// pointing State at the right value just before each one syncs.
const hosts = {
  playing: { el: document.getElementById("playing")!, host: buildNowPlaying(), media: PLAYING },
  noart: {
    el: document.getElementById("noart")!,
    host: buildNowPlaying(),
    media: { ...PLAYING, artwork: "", title: "Secret Place", artist: "Gabe", sourceName: "Chrome", sourceId: "chrome.exe" },
  },
  idle: { el: document.getElementById("idle")!, host: buildNowPlaying(), media: EMPTY_MEDIA },
};

for (const entry of Object.values(hosts)) {
  entry.host.el.classList.add("on");
  entry.el.append(entry.host.el);
}

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
  for (const entry of Object.values(hosts)) {
    State.media = entry.media;
    entry.host.sync();
    entry.host.tick?.(now);
  }
  tickMiniBots(dt);
  clock.textContent = hosts.playing.media.isPlaying ? "playing" : "paused";
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
