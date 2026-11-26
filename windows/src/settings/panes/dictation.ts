// Dictation — DictationSettingsView.swift, group for group: the switch and
// what it does, the transcription service (address, Test connection, what
// answered, the language, how to start it), the key held to talk, and what
// becomes of the text.
//
// Where a PC differs it says so in the pane itself: no fn key (the right Ctrl
// is held instead), the microphone is Windows' to allow rather than a prompt
// of this app's, and on Linux there is no held key and no pasting into other
// apps (dictation_keys.rs, dictation.rs).

import { Bridge } from "../../core/bridge";
import { DICTATION, HOLD_KEYS, INSERT_MODES, decodeHealth, healthURL, modelName } from "../../core/dictation";
import { t } from "../../core/i18n";
import {
  checkbox, colorDot, groupBox, hint, inlineRow, label, popup, pushButton, spacer, spinner, textField,
  type PopupOption,
} from "../controls";
import { save, settings, subscribe } from "../store";

const ON_LINUX = /\b(Linux|X11)\b/.test(navigator.userAgent);

/** Run from the Notchy source folder; dictation-service/README.md has the rest. */
const START_COMMAND = ON_LINUX
  ? "cd dictation-service && ./scripts/start.sh"
  : "cd dictation-service; .\\scripts\\start.ps1";

/** Green, red, or amber for "not yet". */
const DOT = { ok: "#34D399", bad: "#F4505E", wait: "#F5A524" } as const;

function switchGroup(): HTMLElement {
  const use = checkbox(t("Use dictation"), settings.dictationEnabled, (on) => {
    settings.dictationEnabled = on;
    void save();
  });
  subscribe("settings", () => use.set(settings.dictationEnabled));
  return groupBox({ title: null, gap: 10 },
    use,
    hint(ON_LINUX
      ? t("Open Dictation from the tray menu, use its Record button, then copy the text. On Linux the held key and "
        + "pasting into other apps are not available in this version.")
      : t("Hold a key in any app, speak, and let go: the text is typed where the cursor is. Or open Dictation from "
        + "the tray menu and use its Record button.")),
    hint(t("The speech model runs on your own computer, in Notchy's transcription service. The audio goes only to "
      + "the address below, and is never saved.")),
    hint(ON_LINUX
      ? t("The microphone is asked for the first time you record.")
      : t("The microphone is asked for the first time you dictate. If Windows blocks it, allow desktop apps under "
        + "Settings › Privacy & security › Microphone.")),
  );
}

function serviceGroup(): HTMLElement {
  const statusDot = colorDot(DOT.wait, 8);
  const statusText = hint("");
  const busy = spinner();
  const statusRow = inlineRow(statusDot, busy, statusText);

  const show = (node: HTMLElement, on: boolean) => { node.style.display = on ? "" : "none"; };

  async function test() {
    const url = healthURL(settings.dictationServiceUrl);
    show(statusRow, true);
    if (!url) {
      show(busy, false);
      show(statusDot, true);
      statusDot.style.background = DOT.bad;
      statusText.textContent = t("That is not a valid address.");
      return;
    }
    show(busy, true);
    show(statusDot, false);
    statusText.textContent = t("Checking…");
    const answer = await Bridge.dictationHealth(url);
    const health = answer?.body ? decodeHealth(answer.body) : null;
    show(busy, false);
    show(statusDot, true);
    if (health?.ready) {
      statusDot.style.background = DOT.ok;
      const name = modelName(health.info);
      statusText.textContent = health.info.streaming
        ? t("Connected — %@, %@ on %@: text while you speak.", name, health.info.backend, health.info.device)
        : t("Connected — %@, %@ on %@: text when you stop.", name, health.info.backend, health.info.device);
    } else if (health && health.status === "error") {
      statusDot.style.background = DOT.bad;
      statusText.textContent = t("The service cannot run the model: %@", health.error ?? "");
    } else if (health) {
      statusDot.style.background = DOT.wait;
      statusText.textContent = t("The service is loading %@…", modelName(health.info));
    } else if (answer?.problem === "notTheService") {
      statusDot.style.background = DOT.bad;
      statusText.textContent = t("Something answered, but it is not Notchy's transcription service.");
    } else {
      statusDot.style.background = DOT.bad;
      statusText.textContent = t("Nothing is answering at %@. Start the service, then test again.",
        settings.dictationServiceUrl);
    }
  }

  const address = textField(settings.dictationServiceUrl, (typed) => {
    const value = typed.trim();
    settings.dictationServiceUrl = value || DICTATION.defaultServiceURL;
    address.value = settings.dictationServiceUrl;
    void save();
  }, { placeholder: DICTATION.defaultServiceURL, ariaLabel: t("Address") });
  subscribe("settings", () => {
    if (document.activeElement !== address) address.value = settings.dictationServiceUrl;
  });
  const testButton = pushButton(t("Test connection"), () => {
    const value = address.value.trim();
    if (value !== settings.dictationServiceUrl) {
      settings.dictationServiceUrl = value || DICTATION.defaultServiceURL;
      void save();
    }
    void test();
  });

  const command = hint(START_COMMAND, 11);
  command.style.fontFamily = "ui-monospace, \"Cascadia Mono\", Consolas, monospace";
  command.style.userSelect = "text";
  const copy = pushButton(t("Copy"), () => void Bridge.dictationInsert(START_COMMAND, "copy"), { small: true });

  show(statusRow, false);
  // As the Mac's pane does on appear: what is there right now.
  void test();

  return groupBox({ title: t("Transcription service"), gap: 8 },
    inlineRow(label(t("Address"), 70), address, testButton),
    statusRow,
    inlineRow(label(t("Language"), 70), label(`${DICTATION.languageLabel} · ${DICTATION.language}`)),
    hint(t("To start it on this computer, from the Notchy source folder:")),
    inlineRow(command, spacer(), copy),
    hint(t("The first start downloads the Qwen3-ASR-1.7B model (about 4.7 GB). Without an NVIDIA GPU the text "
      + "appears when you stop speaking; with one, while you speak. dictation-service/README.md has the details.")),
  );
}

function holdGroup(): HTMLElement {
  const options: PopupOption[] = HOLD_KEYS.map((k) => ({ value: k.id, label: t(k.title) }));
  const key = popup(options, settings.dictationHoldKey, (id) => {
    settings.dictationHoldKey = id;
    void save();
  }, { label: t("Key"), width: 240 });
  subscribe("settings", () => key.set(settings.dictationHoldKey));
  if (ON_LINUX) key.setDisabled(true);
  return groupBox({ title: t("Hold to talk"), gap: 8 },
    key,
    hint(ON_LINUX
      ? t("Not available on Linux in this version: Wayland lets no app see keys meant for another.")
      : t("A quick tap, or another key pressed while holding, does nothing — shortcuts keep working. Escape cancels.")),
  );
}

function insertGroup(): HTMLElement {
  const options: PopupOption[] = INSERT_MODES.map((m) => ({ value: m.id, label: t(m.title) }));
  const mode = popup(options, settings.dictationInsert, (id) => {
    settings.dictationInsert = id;
    void save();
  }, { label: t("After dictating"), width: 240 });
  subscribe("settings", () => mode.set(settings.dictationInsert));
  if (ON_LINUX) mode.setDisabled(true);
  return groupBox({ title: t("When the text is ready"), gap: 8 },
    mode,
    hint(ON_LINUX
      ? t("On Linux the text is copied; paste it with Ctrl+V.")
      : t("Pasting puts the text on the clipboard for a moment, presses Ctrl+V for you, and gives back what the "
        + "clipboard held.")),
  );
}

/** The Dictation pane. */
export function render(): Node[] {
  return [switchGroup(), serviceGroup(), holdGroup(), insertGroup()];
}
