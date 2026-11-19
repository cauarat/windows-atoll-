// The welcome's window: seven screens before the island says hello, the twin of
// the Mac's OnboardingWindowController. Rust owns the window — created hidden
// at launch, shown for a first run or for Settings' "Show the welcome again…",
// hidden again at the end (lib.rs) — and this page only puts the screens
// (welcome.ts) up and takes them down when told.
//
// Opened in a plain browser there is no Rust behind it, and it shows itself
// with made-up settings instead — the preview the Mac screenshots are compared
// against: `onboarding.html?step=look&lang=pt-BR&name=Ana`. Also takes
// `character=<stored character>`, `pills=<id,id>`, `account=<full name>`,
// `media=0`, and for the look screen `tab=face|body|christmas` and
// `editing=<pill id>`; `window.welcome.show("tools")` moves it from the
// console.

import "./onboarding.css";
import { Bridge, IS_TAURI, onEvent } from "../core/bridge";
import { DEFAULT_SETTINGS, type Settings } from "../core/state";
import { resolve, setLanguage, type Language } from "../core/i18n";
import { ONBOARDING_STEPS } from "../core/onboarding";
import {
  refreshWelcome, startWelcome, stepWelcomeMochi, stopWelcome, welcomeEngine, welcomeShowing,
  type LookStart, type WelcomeHost,
} from "./welcome";

const root = document.getElementById("onboarding-root")!;

let settings: Settings = { ...DEFAULT_SETTINGS };

/** Puts the language in force here, and tells Rust, whose tray follows it. */
function applyLanguage() {
  setLanguage(settings.language);
  void Bridge.setLanguage(resolve(settings.language));
}

/** Asks Rust where things stand and, if the welcome is up, puts it on screen. */
async function begin() {
  const boot = await Bridge.boot();
  if (!boot) return;
  settings = { ...settings, ...boot.settings };
  applyLanguage();
  if (!boot.welcome) return;
  const host: WelcomeHost = {
    settings: () => settings,
    save: () => void Bridge.saveSettings(settings),
    applyLanguage,
    accountName: boot.accountName ?? null,
    media: boot.media,
    finish: () => void Bridge.finishOnboarding(),
    drag: () => void Bridge.dragOnboardingWindow(),
  };
  startWelcome(root, host, boot.welcome);
}

async function main() {
  if (!IS_TAURI) {
    preview();
    return;
  }
  // Other windows write the settings too; this copy follows them, and the
  // whole of it is what every save sends.
  await onEvent<Settings>("settings-changed", (s) => {
    settings = { ...settings, ...s };
    if (setLanguage(settings.language) && welcomeShowing()) refreshWelcome();
  });
  // "Show the welcome again…": from the first screen, with today's settings.
  await onEvent<null>("onboarding-start", () => void begin());
  // Over — by a button here, or by Alt+F4 — and Rust has hidden the window.
  await onEvent<null>("onboarding-finished", () => stopWelcome());
  // Shown at launch for a first run, possibly before this page had loaded:
  // `boot.welcome` says so either way.
  await begin();
}

/** The page on its own, with made-up settings — see the note at the top. */
function preview() {
  const query = new URLSearchParams(location.search);
  const lang = (query.get("lang") ?? "en") as Language;
  settings = {
    ...DEFAULT_SETTINGS,
    language: lang,
    userName: query.get("name") ?? "",
    defaultCharacter: query.get("character") ?? DEFAULT_SETTINGS.defaultCharacter,
  };
  const pills = query.get("pills");
  if (pills !== null) settings.activeIntegrations = pills.split(",").filter(Boolean);
  setLanguage(lang);

  const host: WelcomeHost = {
    settings: () => settings,
    save: () => {},
    applyLanguage: () => setLanguage(settings.language),
    accountName: query.get("account"),
    media: query.get("media") !== "0",
    // Nothing to hand back to: start over, as a fresh first run would.
    finish: () => startWelcome(root, host, "welcome"),
    drag: () => {},
  };
  // Whose look the look screen opens on, and which of its tabs.
  const look: LookStart = { editing: query.get("editing"), tab: query.get("tab") };
  startWelcome(root, host, query.get("step") ?? "welcome", look);

  // For a pane that gets no animation frames: move between screens and step
  // Mochi by hand — and see what his engine is doing.
  (window as unknown as { welcome: unknown }).welcome = {
    steps: ONBOARDING_STEPS,
    settings: () => settings,
    show: (step: string, again: LookStart = look) => startWelcome(root, host, step, again),
    step: (seconds: number) => stepWelcomeMochi(seconds),
    engine: () => welcomeEngine(),
  };
}

void main();
