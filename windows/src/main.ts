// Entry point: boot the bridge, wire the island, start the greeting.

import "./style.css";
import { Bridge, IS_TAURI, onEvent, type ScreenInfo } from "./core/bridge";
import { Sound } from "./core/sound";
import { State, type Settings } from "./core/state";
import { Island } from "./island/island";
import { registerHookHandlers } from "./island/hooks";
import { refreshConfigured } from "./island/integrations";
import { registerMediaHandlers } from "./island/media";
import { registerMessageHandlers } from "./island/messages";
import { resolve, setLanguage } from "./core/i18n";

async function main() {
  const root = document.getElementById("root");
  if (!root) return;

  void Sound.preload();

  const island = new Island(root);

  const boot = await Bridge.boot();
  if (boot) {
    State.settings = { ...State.settings, ...boot.settings };
    State.mediaAvailable = boot.media;
    // Before applySettings: a dropped position is a fraction of the work area,
    // so the island cannot place itself until it knows what that area is.
    island.setScreen(boot.screen);
  }
  // Before the first paint, so no card is drawn in English and corrected a
  // frame later. Rust is told too: its tray cannot read the system language on
  // Windows, and navigator.language can.
  setLanguage(State.settings.language);
  void Bridge.setLanguage(resolve(State.settings.language));
  island.applySettings();
  State.loadIntegrationTasks();
  if (boot && !boot.cursorPoll) island.followPageCursor();

  await onEvent<{ x: number; y: number }>("cursor", ({ x, y }) => island.onCursor(x, y));

  // The master switch is handled entirely in Rust — it has to work while this
  // window is hidden, which is exactly when an event sent here would be heard
  // by nobody. Only "open" still reaches the island.
  await onEvent<string>("tray", (what) => {
    if (what === "open") island.alert(State.defaultView());
  });

  await onEvent<ScreenInfo>("screen-changed", (screen) => {
    island.setScreen(screen);
    void Bridge.reposition();
  });

  // The settings window writes preferences; apply them here without a restart.
  await onEvent<Settings>("settings-changed", (s) => {
    const was = State.settings.enabled;
    State.settings = { ...State.settings, ...s };
    // A view already on screen keeps the words it was built with, so the
    // language has to take effect before the island is asked to redraw.
    if (setLanguage(State.settings.language)) {
      void Bridge.setLanguage(resolve(State.settings.language));
      island.rebuildViews();
    }
    island.applySettings();
    if (was !== State.settings.enabled) {
      // reveal(), not launch(): a compact peek says it is back without
      // replaying the ten-second greeting on every flip.
      if (State.settings.enabled) island.reveal();
      else island.fsm.forceHidden();
    }
    State.loadIntegrationTasks();
    void refreshConfigured();
  });

  registerHookHandlers(island);
  void refreshConfigured();
  registerMessageHandlers(island);
  registerMediaHandlers(island);

  island.launch();

  // After launch(), not before: launch() puts the island in its greeting state,
  // which would have overridden the notice and folded it away half a second
  // later. Cutting the greeting short on a run that follows a crash is the right
  // way round anyway — Mochi has something to say first.
  if (boot?.recovered) island.noteRecovered();

  // In a plain browser there is no wake strip behind the cursor: make the whole
  // page wake the island so the visuals can be checked with `npm run dev`.
  if (!IS_TAURI) {
    document.addEventListener("click", () => Sound.resume(), { once: true });
  }
}

void main();
