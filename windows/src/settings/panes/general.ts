// General — the Mac's generalSection (SettingsView.swift), GroupBox for
// GroupBox and in its order: Notchy, Your name, Language, Sound, Behavior,
// Displays, Hotkey, Startup, Updates.
//
// Where Windows does not have the Mac's feature yet, the group keeps today's
// Windows behaviour in the Mac's shape:
// - Behavior: "Never" beside "Hide after … s without movement" is the owner's
//   choice, and the Mac is taking the same button in place of its "Always
//   visible" checkbox. Standby is gone (W-15).
// - Displays: the radio group the Mac draws, offering the two choices Windows
//   has (main display, display under the pointer). Per-display checkboxes come
//   with Phase 4, and so does the Notch height group.
// - Hotkey: only the close shortcut. The open shortcut arrives in Phase 2.
// - Updates: the Mac's three rows, plus one line under the first that carries
//   what Sparkle's own window says on the Mac (looking, available, downloading,
//   ready, failed). That window is Phase 2.
// The Mattermost and Ato "opens" rows went to Integrations, and Home shows went
// to Active pills, which is where the Mac keeps them.

import "./general.css";
import { Bridge, type UpdateState } from "../../core/bridge";
import { SETTINGS_RANGES, type Settings } from "../../core/state";
import { h } from "../../views/dom";
import { LANGUAGES, LANGUAGE_LABEL, t, type Language } from "../../core/i18n";
import { firstNameFromFullName } from "../../core/greetingName";
import { applyLanguage, boot, save, setStatus, settings, subscribe } from "../store";
import { rerenderAll } from "../shell";
import {
  checkbox, disable, groupBox, hint, hugBoxes, inlineRow, label, numberField, popup,
  pushButton, shortcutRecorder, slider, spacer, stack, textField,
} from "../controls";

/**
 * Linux shares this window with Windows. The few sentences that name the
 * platform say "Windows" only where it is Windows. Anything that is not Linux
 * counts as Windows, so the Vite preview on a Mac shows the Windows text.
 */
const ON_LINUX = /\b(Linux|X11)\b/.test(navigator.userAgent);

// ── Notchy ────────────────────────────────────────────────────────────────────

/**
 * The master switch: a checkbox that names its own state.
 *
 * Everything below it stays usable and undimmed, as on the Mac: pasting a key
 * or changing a shortcut while off is reasonable, and none of it takes effect
 * until the switch is back on.
 */
function notchyGroup(): { el: HTMLElement; sync(): void } {
  const text = (on: boolean) => (on ? t("Notchy is on") : t("Notchy is off"));
  const master = checkbox(text(settings.enabled), settings.enabled, (on) => {
    settings.enabled = on;
    master.setLabel(text(on));
    void save();
  });
  const el = groupBox(t("Notchy"),
    master,
    // The sentence about hooks is the support question it answers: turning
    // Notchy off must not read as having broken Claude Code. The Mac ends on
    // "the menu bar"; the tray icon by the clock is the same place here.
    hint(t("Off, Mochi disappears, nothing is polled and no sound plays. Your Claude Code "
      + "hooks stay installed — permission requests simply go back to being asked in "
      + "the terminal. Turn it back on here or from the icon by the clock.")),
  );
  // The tray's switch, and the island, can change it while this is open.
  const sync = () => {
    master.set(settings.enabled);
    master.setLabel(text(settings.enabled));
  };
  return { el, sync };
}

// ── Your name ─────────────────────────────────────────────────────────────────

/** Pending save of a name still being typed. */
let nameTimer: number | undefined;

/**
 * What Mochi calls the user, in the launch greeting and in the chat.
 *
 * Empty falls back to the account's own first name, when it has one worth
 * greeting. That name is the placeholder, so an empty field still says what
 * will be used. Trimmed on the way in and cleaned where it is read
 * (core/greetingName.ts), as on the Mac.
 *
 * The Mac saves as you type. This saves half a second after the last key, and
 * at once on Enter or leaving the field, so a name typed just before the
 * window closes is still kept.
 */
function nameGroup(): { el: HTMLElement; sync(): void } {
  const commit = () => {
    window.clearTimeout(nameTimer);
    nameTimer = undefined;
    const name = field.value.trim();
    if (name === settings.userName) return;
    settings.userName = name;
    void save();
  };
  const field = textField(settings.userName, () => {
    commit();
    field.value = settings.userName;
  }, {
    placeholder: firstNameFromFullName(boot.accountName) ?? t("Your first name"),
    maxLength: 80,
    ariaLabel: t("Your name"),
    onInput: () => {
      window.clearTimeout(nameTimer);
      nameTimer = window.setTimeout(commit, 500);
    },
  });

  // The first run's seven screens, in their own window over everything, from
  // the first one. The island keeps running and says hello again at the end,
  // with whatever name was just given.
  const welcome = pushButton(t("Show the welcome again…"), () => void Bridge.showOnboarding());
  welcome.style.marginTop = "2px";

  const el = groupBox(t("Your name"),
    field,
    hint(t("Mochi greets you by this name when Notchy starts, and uses it in the chat.")),
    welcome,
  );
  // The welcome writes the name too. Never under the cursor of someone typing.
  const sync = () => {
    if (document.activeElement !== field && nameTimer === undefined
      && field.value !== settings.userName) {
      field.value = settings.userName;
    }
  };
  return { el, sync };
}

// ── Language ──────────────────────────────────────────────────────────────────

/**
 * Changing it redraws the whole window: half a window in the old language is
 * how a complete translation looks broken.
 */
function languageGroup(): { el: HTMLElement; sync(): void } {
  // Each language names itself and stays in its own words whatever is chosen.
  // Only "Same as system" is a sentence, so only it is translated, as
  // AppLanguage does on the Mac.
  const options = LANGUAGES.map((value) => ({
    value,
    label: value === "system" ? t(LANGUAGE_LABEL[value]) : LANGUAGE_LABEL[value],
  }));
  const picker = popup<Language>(options, settings.language, (v) => {
    settings.language = v;
    void save();
    applyLanguage();
    rerenderAll();
    // The redraw replaced this popup. On Windows an arrow key on a closed
    // popup is a choice already, so the keyboard has to land on the new one
    // for the next arrow to reach the next language.
    document.querySelector<HTMLSelectElement>('select[data-key="language"]')?.focus({ preventScroll: true });
  }, { ariaLabel: t("Language") });
  picker.select.dataset.key = "language";

  const el = groupBox(t("Language"),
    picker,
    // The Mac's sentence names the menu bar and "your Mac". This is its twin:
    // the icon by the clock, and a computer that may be running Linux.
    hint(t("Mochi speaks this language everywhere: the island, Settings, the icon by the "
      + "clock and the notifications. Following the system means Spanish or Portuguese "
      + "if your computer is set to one of them, and English otherwise.")),
  );
  return { el, sync: () => picker.set(settings.language) };
}

// ── Sound ─────────────────────────────────────────────────────────────────────

function soundGroup(): { el: HTMLElement; sync(): void } {
  // 0…0.2, the Mac's range, read as a percentage of it. `Int()` on the Mac
  // truncates, and so does this.
  const [min, max] = SETTINGS_RANGES.soundVolume;
  const volume = slider(settings.soundVolume, {
    min,
    max,
    disabled: !settings.soundEnabled,
    valueText: (v) => `${Math.trunc(v / max * 100)} %`,
    valueWidth: 36,
    ariaLabel: t("Volume"),
    // Written when the knob is let go. Every pixel of a drag was a disk write
    // and a broadcast to every window, and only the last one counts.
    onCommit: (v) => {
      settings.soundVolume = v;
      void save();
    },
  }, (v) => { settings.soundVolume = v; });

  const enabled = checkbox(t("Enable sounds"), settings.soundEnabled, (on) => {
    settings.soundEnabled = on;
    volume.setDisabled(!on);
    void save();
  });

  const el = groupBox({ title: t("Sound"), gap: 10 },
    enabled,
    inlineRow(label(t("Volume"), 56), volume),
  );
  const sync = () => {
    enabled.set(settings.soundEnabled);
    volume.setDisabled(!settings.soundEnabled);
    if (document.activeElement !== volume.input) volume.set(settings.soundVolume);
  };
  return { el, sync };
}

// ── Behavior ──────────────────────────────────────────────────────────────────

function behaviorGroup(): { el: HTMLElement; sync(): void } {
  // How long an opened card stays before the island closes again. 2…120 s,
  // the Mac's SettingsDefaults.autoCloseRange.
  const [closeMin, closeMax] = SETTINGS_RANGES.autoCloseInterval;
  const closeAfter = numberField(settings.autoCloseInterval,
    { min: closeMin, max: closeMax, ariaLabel: t("Close after") },
    (v) => { settings.autoCloseInterval = v; void save(); });
  // The Mac's TextField title, shown while the field is empty.
  closeAfter.placeholder = "5";

  // How long the resting island waits before folding away. 5…3600 s.
  const [hideMin, hideMax] = SETTINGS_RANGES.absenceInterval;
  const hideAfter = numberField(settings.absenceInterval,
    { min: hideMin, max: hideMax, ariaLabel: t("Hide after") },
    (v) => { settings.absenceInterval = v; void save(); });
  hideAfter.placeholder = "180";

  // Greyed rather than hidden while "Never" is on: it still says what happens
  // the moment "Never" goes off. The button itself stays live beside it.
  const hideRow = inlineRow(label(t("Hide after")), hideAfter, label(t("s without movement")));

  // "Never", next to the seconds it overrides, is where anyone looks for
  // "don't fold". Underneath it is `alwaysVisible`: the island rests as the
  // compact bar in its corner instead of folding away.
  const never = pushButton(t("Never"), () => {
    settings.alwaysVisible = !settings.alwaysVisible;
    paintNever();
    void save();
  });
  never.classList.add("gen-toggle");
  const paintNever = () => {
    never.classList.toggle("on", settings.alwaysVisible);
    never.setAttribute("aria-pressed", String(settings.alwaysVisible));
    disable(hideRow, settings.alwaysVisible);
  };
  paintNever();

  const el = groupBox({ title: t("Behavior"), gap: 10 },
    inlineRow(label(t("Close after")), closeAfter, label(t("s inactive"))),
    inlineRow(hideRow, never),
  );
  const sync = () => {
    if (document.activeElement !== closeAfter) closeAfter.set(settings.autoCloseInterval);
    if (document.activeElement !== hideAfter) hideAfter.set(settings.absenceInterval);
    paintNever();
  };
  return { el, sync };
}

// ── Displays ──────────────────────────────────────────────────────────────────

type RadioGroup<T extends string> = HTMLElement & { set(v: T): void };

let radioGroups = 0;

/**
 * A vertical group of macOS radio buttons: `Picker` with `.pickerStyle(.radioGroup)`
 * and its label hidden. Each one is a 14px circle beside its label, filled in
 * the accent with a white dot when chosen. A real radio input sits under each
 * one, so the arrow keys and screen readers work as usual.
 */
function radioGroup<T extends string>(
  options: { value: T; label: string }[], value: T, onChange: (v: T) => void, ariaLabel: string,
): RadioGroup<T> {
  const name = `gen-radio-${++radioGroups}`;
  const el = h("div", {
    class: "gen-radio-group", role: "radiogroup", "aria-label": ariaLabel,
  }) as unknown as RadioGroup<T>;
  const inputs = options.map((o) => {
    const input = h("input", { type: "radio", class: "gen-radio-input", name, value: o.value });
    input.checked = o.value === value;
    input.addEventListener("change", () => { if (input.checked) onChange(o.value); });
    el.append(h("label", { class: "gen-radio" },
      input,
      h("span", { class: "gen-radio-dot" }),
      h("span", { class: "gen-radio-label", text: o.label })));
    return input;
  });
  el.set = (v) => { for (const input of inputs) input.checked = input.value === v; };
  return el;
}

/**
 * Which display the island lives on. The Mac offers "All displays" and "Only
 * selected", with a checkbox per display. Windows has two choices until
 * Phase 4: the main display, or whichever one the pointer is on. Dropping the
 * island on another display switches this to the second (island.rs).
 */
function displaysGroup(): { el: HTMLElement; sync(): void } {
  const choice = radioGroup<Settings["screen"]>([
    { value: "primary", label: t("Main display") },
    { value: "cursor", label: t("Display under the cursor") },
  ], settings.screen, (v) => {
    settings.screen = v;
    void save();
  }, t("Displays"));

  const el = groupBox({ title: t("Displays"), gap: 8 },
    choice,
    hint(t("Mochi rests on the main display, or on whichever display your pointer is on.")),
  );
  return { el, sync: () => choice.set(settings.screen) };
}

// ── Hotkey ────────────────────────────────────────────────────────────────────

/**
 * The shortcut that closes the island: the Mac's checkbox, then the keys and
 * what they do.
 *
 * Rust registers it on every save (src-tauri/src/shortcut.rs) and keeps the
 * reason when the system refuses it: another app holds those keys, or the
 * desktop is Wayland, which lets no app grab one. So the group asks after each
 * save and says so, rather than showing a shortcut that does nothing.
 */
function hotkeyGroup(): { el: HTMLElement; sync(): void } {
  const recorder = shortcutRecorder(settings.closeShortcut, (accelerator) => {
    settings.closeShortcut = accelerator;
    void saveAndPaint();
  });
  const keysRow = inlineRow(
    label(t("Shortcut"), 70),
    recorder,
    hint(t("presses this → island closes")),
  );
  const refused = hint(t("This shortcut is taken or not allowed here."));

  const enabled = checkbox(t("Close island with shortcut"), settings.closeShortcutEnabled, (on) => {
    settings.closeShortcutEnabled = on;
    // A recorder still listening when it disappears would take the next key
    // pressed anywhere in the window.
    if (!on) recorder.blur();
    void saveAndPaint();
  });

  const paint = async () => {
    const on = settings.closeShortcutEnabled;
    keysRow.style.display = on ? "" : "none";
    const error = on ? await Bridge.closeShortcutError() : null;
    refused.style.display = error ? "" : "none";
  };
  const saveAndPaint = async () => {
    await save();
    await paint();
  };
  refused.style.display = "none";
  void paint();

  const el = groupBox({ title: t("Hotkey"), gap: 10 }, enabled, keysRow, refused);
  const sync = () => {
    enabled.set(settings.closeShortcutEnabled);
    recorder.set(settings.closeShortcut);
    void paint();
  };
  return { el, sync };
}

// ── Startup ───────────────────────────────────────────────────────────────────

function startupGroup(): { el: HTMLElement; sync(): void } {
  // The Mac's "Launch at Mac startup", said of this system.
  const text = ON_LINUX ? t("Launch at startup") : t("Launch at Windows startup");
  const launch = checkbox(text, settings.autostart, (on) => {
    settings.autostart = on;
    void save().then(async () => {
      // As on the Mac: a change the system refused goes back — Rust's
      // broadcast redraws the box with what is registered — and the status
      // bar says why.
      const error = await Bridge.autostartError();
      if (error) setStatus(`❌ ${t("Startup: %@", error)}`);
    });
  });
  const el = groupBox(t("Startup"), launch);
  return { el, sync: () => launch.set(settings.autostart) };
}

// ── Updates ───────────────────────────────────────────────────────────────────

const IDLE: UpdateState = {
  phase: "idle", version: null, notes: null, progress: 0,
  error: null, installable: false, keyMismatch: false, releaseUrl: "",
};

/**
 * The Mac's group: "Notchy x.y.z" and "Check for updates" on one row, "Check
 * automatically", and what the check sends.
 *
 * On the Mac, Sparkle's own window takes it from there. Here, until that window
 * exists (Phase 2), one line under the first row says where things stand, and
 * the button does what the moment needs: check, update, open the download page,
 * restart, try again. At rest the line is hidden and the group matches the Mac.
 *
 * Nothing here downloads or restarts by itself. Notchy answers Claude Code
 * permission requests over a named pipe, and a restart nobody asked for drops
 * whichever request is waiting in it, so the install waits for a click.
 */
function updatesGroup(): { el: HTMLElement; paint(next: UpdateState): void; sync(): void } {
  let state: UpdateState = boot.update ?? IDLE;

  const action = pushButton(t("Check for updates"), () => {
    if (state.phase === "available" && !state.installable) {
      void Bridge.openUrl(state.releaseUrl);
      return;
    }
    if (state.phase === "available" || state.phase === "ready") {
      void Bridge.updateInstall();
      return;
    }
    void Bridge.updateCheck();
  });

  const line = hint("");
  const fill = h("i");
  const bar = h("div", { class: "gen-progress", role: "progressbar" }, fill);
  // Right under the line that says the check failed, so the sentence saying
  // why is read with it, not found later under the fold.
  const failure = hint("");
  failure.classList.add("gen-update-error");
  // The notes come off the release manifest: set as text, never as markup, so
  // nothing that arrives over the network writes into this window.
  const notes = hint("");
  notes.classList.add("gen-update-notes");
  const where = stack(6, line, bar, failure, notes);

  const automatic = checkbox(t("Check automatically"), settings.autoUpdate, (on) => {
    settings.autoUpdate = on;
    void save();
  });

  const paint = (next: UpdateState) => {
    state = next;
    const pct = Math.round(state.progress * 100);
    const version = state.version ?? "";

    action.disabled = state.phase === "checking" || state.phase === "downloading";
    // The install is the one button the Mac draws prominent, in Sparkle's window.
    action.classList.toggle("prominent", state.phase === "available" || state.phase === "ready");

    let text = "";
    let button = t("Check for updates");
    switch (state.phase) {
      case "checking":
        text = t("Looking…");
        break;
      case "available":
        // Three sentences, not two: a copy that cannot verify the package is
        // not the same case as the portable .zip that cannot replace itself,
        // and the difference is what somebody has to do about it.
        text = state.keyMismatch
          ? t("Notchy %@ is out. This copy was built with a signing key that has since "
            + "been replaced, so it cannot install it — install by hand once and updates "
            + "work again after that.", version)
          : state.installable
            ? t("Notchy %@ is out.", version)
            : t("Notchy %@ is out. This copy cannot replace itself.", version);
        button = state.installable ? t("Update to %@", version) : t("Open the download page");
        break;
      case "downloading":
        text = pct > 0 ? t("Downloading… %lld%", pct) : t("Downloading…");
        button = t("Downloading…");
        break;
      case "ready":
        text = t("Notchy %@ is installed.", version);
        button = t("Restart now");
        break;
      case "error":
        text = t("The check did not go through.");
        button = t("Try again");
        break;
      case "upToDate":
        text = t("You are on the latest version.");
        break;
      default:
        text = "";
    }
    action.setText(button);

    line.textContent = text;
    line.style.display = text ? "" : "none";
    bar.style.display = state.phase === "downloading" ? "" : "none";
    fill.style.width = `${pct}%`;
    bar.setAttribute("aria-valuenow", String(pct));
    const reason = state.phase === "error" ? state.error ?? "" : "";
    failure.textContent = reason;
    failure.style.display = reason ? "" : "none";
    const shown = state.phase === "available" ? state.notes ?? "" : "";
    notes.textContent = shown;
    notes.style.display = shown ? "" : "none";
    where.style.display = text || reason || shown ? "" : "none";
  };
  paint(state);

  const el = groupBox({ title: t("Updates"), gap: 10 },
    inlineRow(label(`Notchy ${boot.version}`), spacer(), action),
    where,
    automatic,
    // Not the Mac's sentence: there the Install button is in Sparkle's window,
    // here it is this group's own button.
    hint(t("Notchy asks GitHub once an hour whether a newer release exists, and "
      + "nothing more: the request carries no identifier and no usage of any kind. "
      + "When there is one, the notch offers it; nothing downloads or restarts until "
      + "you click Update now. Every package is signed, and one that does not match "
      + "is refused before it runs.")),
  );
  return { el, paint, sync: () => automatic.set(settings.autoUpdate) };
}

// ── The pane ──────────────────────────────────────────────────────────────────

/** The General pane. */
export function render(): Node[] {
  const groups = [
    notchyGroup(),
    nameGroup(),
    languageGroup(),
    soundGroup(),
    behaviorGroup(),
    displaysGroup(),
    hotkeyGroup(),
    startupGroup(),
  ];
  const updates = updatesGroup();

  // Every row follows the stored value, as a SwiftUI binding does: the tray's
  // master switch, the welcome's name, and a drop on another display all
  // change settings while this is open.
  subscribe("settings", () => {
    for (const g of groups) g.sync();
    updates.sync();
  });
  subscribe("update", () => { if (boot.update) updates.paint(boot.update); });

  // The pane's own 18px column, so the boxes have one container to be
  // measured against. Behavior, Hotkey and Startup hold controls of a fixed
  // size and are as wide as those; Language as its widest line.
  const boxes = [...groups.map((g) => g.el), updates.el];
  const body = stack(18, ...boxes);
  hugBoxes(body, boxes);
  return [body];
}
