// Entry point: boot the bridge, wire the island, start the greeting.

import "./style.css";
import { Bridge, IS_TAURI, onEvent, type PageState, type ScreenInfo } from "./core/bridge";
import { setPageState } from "./core/pageState";
import { Sound } from "./core/sound";
import { State, type Settings } from "./core/state";
import { Island } from "./island/island";
import { registerHookHandlers } from "./island/hooks";
import { refreshConfigured } from "./island/integrations";
import { registerMediaHandlers } from "./island/media";
import { registerMessageHandlers } from "./island/messages";
import { Agenda } from "./island/agenda";
import { Hydration } from "./core/hydrationStore";
import { Updates } from "./core/updates";
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
    State.accountName = boot.accountName ?? null;
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

  // The close shortcut, registered by Rust so it works whichever app has the
  // keyboard. The header's X does the same; neither reads the message, and on
  // a screen both put it away as its own X does.
  await onEvent<null>("close-shortcut", () => island.dismiss());

  // ChatGPT and the site: where each page stands, Escape pressed inside one,
  // and — debug builds only — a view to open for the CI screenshot run.
  await onEvent<PageState>("page-state", (state) => setPageState(state));
  await onEvent<{ label: string }>("page-escape", () => island.closeScreen());
  await onEvent<string>("smoke-open-view", (view) => island.openForSmoke(view));

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
    Agenda.settingsChanged();
    // Its own settings travel by `storage` events, not this one; this is for
    // the deadline, re-read on the same occasions the Agenda re-reads its own.
    Hydration.wake();
  });

  registerHookHandlers(island);
  void refreshConfigured();
  registerMessageHandlers(island);
  registerMediaHandlers(island);

  // A meeting is about to start: open on the Agenda with it marked. The sound
  // plays even when the island will not open, so the heads-up is never silent.
  Agenda.onDue = () => {
    Sound.play("approval");
    island.alert("agenda");
  };
  // `?seed-agenda` in a plain browser fills the tab with meetings around now.
  if (!IS_TAURI && new URLSearchParams(location.search).has("seed-agenda")) Agenda.seedForPreview();
  else Agenda.settingsChanged();

  // Time for water: open on the reminder. The store has already held it back
  // for a focus timer or an approval, and `alert` waits out the greeting.
  Hydration.onDue = () => {
    Sound.play("blip");
    island.alert("sip");
  };
  Hydration.load();

  // A new version is out: open on the card that offers it, once per version.
  // Rust's hourly check is what finds it; this only listens.
  Updates.current = boot?.version ?? "";
  Updates.onOffered = () => {
    Sound.play("proud");
    island.alert("update");
  };
  void Updates.load();

  // The crash notice goes out with the first greeting, whenever that is.
  let recoveredNote = boot?.recovered ?? false;
  const launch = () => {
    island.launch();
    // After launch(), not before: launch() puts the island in its greeting
    // state, which would have overridden the notice and folded it away half a
    // second later. The notice no longer cuts the greeting short either —
    // `alert()` holds it back until the animation has played out and delivers
    // it then.
    if (recoveredNote) {
      recoveredNote = false;
      island.noteRecovered();
    }
  };

  // The welcome is over — finished, skipped, or its window closed — so say
  // hello, with the name it just learned. Rust has already brought the window
  // up again if the welcome had it parked. Also how "Show the welcome again…"
  // ends, and the hello is played again then. Not into a switched-off island,
  // which has no window to play it in, and never over a permission request
  // waiting for an answer: the greeting would take its card off the screen.
  await onEvent<null>("onboarding-finished", () => {
    if (State.settings.enabled && !State.pendingApproval) launch();
  });

  // "Show the welcome again…": the island keeps running, but folds out of the
  // way if it was open, as the Mac's does.
  await onEvent<null>("onboarding-start", () => {
    if (State.mode === "expanded" && !State.pendingApproval) island.collapse();
  });

  // A first run opens on the welcome, in a window of its own, with this one
  // parked underneath — Rust decides, and says so in `boot.welcome`. The hello
  // waits for the welcome to end; everything else starts now, so the island
  // is ready under it and has simply not said anything yet.
  if (boot?.welcome) {
    island.start();
  } else {
    launch();
  }

  // In a plain browser there is no wake strip behind the cursor: make the whole
  // page wake the island so the visuals can be checked with `npm run dev`.
  if (!IS_TAURI) {
    document.addEventListener("click", () => Sound.resume(), { once: true });
  }
}

void main();
