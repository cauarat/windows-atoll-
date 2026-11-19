// Media events → island state. The Now Playing counterpart of
// src/island/messages.ts, and much the smaller of the two: nothing here badges a
// pill or plays a sound, because a song starting is not someone waiting on you.
//
// What it does do is keep the pill's label on the track, the way
// `MusicController.syncTaskName` does on the Mac, and reveal the island when
// playback starts — once, on the transition, not on every event.

import { onEvent, type MediaState } from "../core/bridge";
import { EMPTY_MEDIA, INTEGRATION_AGENTS, State } from "../core/state";
import { ChristmasMusic } from "./christmasMusic";
import type { Island } from "./island";

const MUSIC_PILL = "integration_music";

/** What the pill is called when nothing is playing. */
const DEFAULT_NAME =
  INTEGRATION_AGENTS.find((agent) => agent.id === MUSIC_PILL)?.name ?? "Now Playing";

/** What GSMTC last reported, kept while the Christmas music has the card. */
let system: MediaState = EMPTY_MEDIA;

export function registerMediaHandlers(island: Island) {
  ChristmasMusic.onChange = () => apply(island);
  void onEvent<MediaState>("media", (media) => {
    system = media;
    ChristmasMusic.observeSystem(media);
    apply(island);
  });
}

/**
 * The card shows the Christmas music while it is the source, and the system's
 * player otherwise — never the island's own WebView2, if GSMTC lists it.
 */
function apply(island: Island) {
  const christmas = ChristmasMusic.active;
  const media = christmas ? ChristmasMusic.media()
    : ChristmasMusic.isOwn(system) ? EMPTY_MEDIA
    : system;
  const wasPlaying = State.media.isPlaying;
  State.setMedia(media);

  // The pill reads as the track while there is one, and as itself when there
  // is not.
  const pill = State.tasks.find((task) => task.id === MUSIC_PILL);
  if (pill) pill.name = media.title || DEFAULT_NAME;

  // Only on the transition into playing. Every other event — a new track while
  // already playing, a seek — is not a reason to take the screen.
  // Not for the Christmas music: it starts with the greeting, or from a click
  // on the open card.
  if (media.isPlaying && !wasPlaying && !christmas) island.reveal();
}
