// Settings window — the place where anything that writes to disk is confirmed.
// Stage 2 covers the Claude Code hooks and the general preferences; API keys and
// integrations land here too in a later stage.

import "./settings.css";
import {
  Bridge, onEvent,
  type ConnectionStatus, type MessageSource, type UpdateState,
} from "../core/bridge";
import {
  CONNECTION_COLOR, CONNECTION_LABEL, DEFAULT_SETTINGS, HOME_CONTENTS, HOME_HINT, HOME_LABEL,
  ALWAYS_LOADED_PILL, INTEGRATION_AGENTS, NOTIFICATIONS_PILL,
  type HomeContent, type Settings, type SourceStatus,
} from "../core/state";
import {
  ACCESSORIES, ACCESSORY_LABEL, CHARACTER_PRESETS, EYES, EYE_LABEL, SHAPES,
  characterFromStorage, characterToStorage, presetMatching,
  type MochiAccessory, type MochiCharacter, type MochiEye, type MochiShape,
} from "../mochi/character";
import { MOCHI_SHAPE_LABEL } from "../mochi/shape";
import { characterPreview } from "../mochi/preview";
import { POSITIONS, isFree } from "../core/anchor";
import {
  EDGE_ACTIONS, defaults as ringDefaults, edgeAction, type EdgeButton,
} from "../core/edgeRing";
import { h, clear } from "../views/dom";
import {
  LANGUAGES, LANGUAGE_LABEL, resolve, setLanguage, t, type Language,
} from "../core/i18n";

let settings: Settings = { ...DEFAULT_SETTINGS };
let version = "";

const root = document.getElementById("settings-root")!;

async function save() {
  await Bridge.saveSettings(settings);
}

// ── The master switch ─────────────────────────────────────────────────────────

/** Repaints the switch row when the state changes, from here or from the tray. */
let paintMaster: (on: boolean) => void = () => {};

/**
 * One control that turns Coucou off, at the top where it can be found.
 *
 * Everything below it stays usable and undimmed on purpose: installing hooks or
 * pasting a key while off is perfectly reasonable, none of it takes effect until
 * the switch goes back on, and dimming would need a section style that does not
 * exist.
 */
function masterSection(): HTMLElement {
  const dot = statusDot(settings.enabled);
  const label = h("label", { text: settings.enabled ? "Notchy is on" : "Notchy is off" });
  const notice = h("div", {
    class: "notice warn",
    text: t("Notchy is off — Mochi is hidden and nothing is being watched."),
  });
  notice.style.display = settings.enabled ? "none" : "";

  const sw = toggle(settings.enabled, (v) => {
    settings.enabled = v;
    void save();
    paintMaster(v);
  });

  paintMaster = (on: boolean) => {
    dot.style.background = on ? "#22c55e" : "#f4505e";
    label.textContent = on ? "Notchy is on" : "Notchy is off";
    sw.classList.toggle("on", on);
    sw.setAttribute("aria-pressed", String(on));
    notice.style.display = on ? "none" : "";
  };

  return h(
    "section",
    {},
    h("h2", {}, dot, h("span", { text: t("Notchy") })),
    h("div", { class: "row" }, label, sw),
    h("div", {
      class: "hint",
      // The sentence about hooks is the support ticket this prevents: turning
      // Coucou off must not read as having broken Claude Code.
      text: t("Off, Mochi disappears, nothing is polled and no sound plays. Your Claude Code "
        + "hooks stay installed — permission requests simply go back to being asked in "
        + "the terminal. Turn it back on here or from the icon by the clock."),
    }),
    notice,
  );
}

// ── Reusable bits ─────────────────────────────────────────────────────────────

function toggle(on: boolean, onChange: (v: boolean) => void): HTMLElement {
  const el = h("button", { class: on ? "switch on" : "switch", "aria-pressed": on });
  el.addEventListener("click", () => {
    const next = !el.classList.contains("on");
    el.classList.toggle("on", next);
    onChange(next);
  });
  return el;
}

/** Flips a switch from outside, for a pair that cannot both be on. */
function setToggle(el: HTMLElement, on: boolean) {
  el.classList.toggle("on", on);
  el.setAttribute("aria-pressed", String(on));
}

function statusDot(ok: boolean): HTMLElement {
  return h("i", { class: "dot", style: `background:${ok ? "#22c55e" : "#f4505e"}` });
}

/** One Credential Manager key, shown the same way everywhere. */
interface CredentialField {
  key: string;
  label: string;
  placeholder: string;
  secret: boolean;
}

/** Anything that cares when a pill is switched on or off. */
const activeChanged: (() => void)[] = [];

/**
 * The pill switch. Shared, because the message sources are pills like any
 * other and must count against the same four slots.
 */
function pillToggle(id: string): HTMLButtonElement {
  const el = h("button", {
    class: settings.activeIntegrations.includes(id) ? "switch on" : "switch",
  });
  el.addEventListener("click", () => {
    const on = settings.activeIntegrations.includes(id);
    if (on) {
      settings.activeIntegrations = settings.activeIntegrations.filter((x) => x !== id);
    } else {
      if (settings.activeIntegrations.length >= MAX_ACTIVE) return;
      settings.activeIntegrations = [...settings.activeIntegrations, id];
    }
    el.classList.toggle("on", !on);
    for (const fn of activeChanged) fn();
    void save();
  });
  return el;
}

/**
 * Label, field, Save, dot. The value is written straight to the Credential
 * Manager and never read back, so a stored field shows "(stored)" rather than
 * its own contents.
 */
function credentialRow(
  field: CredentialField,
  present: Record<string, boolean>,
  onSaved?: () => void,
): HTMLElement {
  const stored = () =>
    present[field.key] ? (field.secret ? "••••••••  (stored)" : "(stored)") : field.placeholder;

  const input = h("input", {
    type: field.secret ? "password" : "text",
    placeholder: stored(),
    autocomplete: "off",
    spellcheck: "false",
    style: "flex:1 1 auto;min-width:0",
  }) as HTMLInputElement;
  const saveBtn = h("button", { text: t("Save") });
  const dotEl = statusDot(present[field.key] ?? false);

  saveBtn.addEventListener("click", async () => {
    const value = input.value.trim();
    try {
      await Bridge.secretSet(field.key, value);
      present[field.key] = value.length > 0;
      input.value = "";
      input.placeholder = stored();
      dotEl.style.background = value ? "#22c55e" : "#f4505e";
      onSaved?.();
    } catch {
      dotEl.style.background = "#f5a524";
    }
  });

  return h("div", { class: "row" },
    h("label", { style: "min-width:104px", text: t(field.label) }),
    input, saveBtn, dotEl,
  );
}

// ── Claude API section ────────────────────────────────────────────────────────

const MODELS: [string, string][] = [
  ["claude-opus-5", "Claude Opus 5"],
  ["claude-sonnet-5", "Claude Sonnet 5"],
  ["claude-haiku-4-5", "Claude Haiku 4.5"],
];

function apiSection(hasKey: boolean): HTMLElement {
  const dot = statusDot(hasKey);
  const state = h("span", { class: "hint", text: hasKey ? t("Key saved in the Windows Credential Manager.") : t("No key yet — the chat needs one.") });

  const field = h("input", {
    type: "password",
    placeholder: hasKey ? "••••••••••••  (stored)" : "sk-ant-...",
    style: "flex:1 1 auto;min-width:0",
    autocomplete: "off",
    spellcheck: "false",
  }) as HTMLInputElement;

  const saveBtn = h("button", { class: "primary", text: t("Save key") });
  const clearBtn = h("button", { class: "danger", text: t("Remove") });
  const feedback = h("div", {});

  async function refresh() {
    const present = (await Bridge.secretPresent("anthropic-api-key")) ?? false;
    dot.style.background = present ? "#22c55e" : "#f4505e";
    state.textContent = present
      ? t("Key saved in the Windows Credential Manager.")
      : t("No key yet — the chat needs one.");
    field.placeholder = present ? "••••••••••••  (stored)" : "sk-ant-...";
    clearBtn.style.display = present ? "" : "none";
  }

  saveBtn.addEventListener("click", async () => {
    const value = field.value.trim();
    if (!value) return;
    clear(feedback);
    try {
      await Bridge.secretSet("anthropic-api-key", value);
      field.value = "";
      feedback.append(h("div", { class: "notice ok", text: t("Saved. It never touches disk.") }));
      await refresh();
    } catch (err) {
      feedback.append(h("div", { class: "notice err", text: `Could not save: ${String(err)}` }));
    }
  });

  clearBtn.addEventListener("click", async () => {
    clear(feedback);
    try {
      await Bridge.secretClear("anthropic-api-key");
      feedback.append(h("div", { class: "notice ok", text: t("Key removed.") }));
      await refresh();
    } catch (err) {
      feedback.append(h("div", { class: "notice err", text: `Could not remove: ${String(err)}` }));
    }
  });

  const model = h("select", {}) as HTMLSelectElement;
  for (const [id, label] of MODELS) model.append(h("option", { value: id, text: label }));
  if (!MODELS.some(([id]) => id === settings.model)) {
    model.append(h("option", { value: settings.model, text: settings.model }));
  }
  model.value = settings.model;
  model.addEventListener("change", () => {
    settings.model = model.value;
    void save();
  });

  clearBtn.style.display = hasKey ? "" : "none";

  return h(
    "section",
    {},
    h("h2", {}, dot, h("span", { text: t("Claude") })),
    state,
    h("div", { class: "row" }, h("label", { text: t("API key") }), field, saveBtn, clearBtn),
    h("div", { class: "row" }, h("label", { text: t("Model") }), model),
    feedback,
  );
}

// ── Integrations section ──────────────────────────────────────────────────────

interface IntegrationDef {
  id: string;
  name: string;
  color: string;
  /** Credential Manager keys, in the order they are shown. */
  fields: CredentialField[];
}

const INTEGRATIONS: IntegrationDef[] = [
  // One pill over both message services, so it has no credentials of its own:
  // Mattermost and ClickMassa are configured in the Messages section and this
  // reads whichever of them is connected.
  { id: NOTIFICATIONS_PILL, name: "Notifications", color: "#FFFFFF", fields: [] },
  // No credentials of its own either: it reads what this machine is already
  // playing, and talks to nothing. Left out entirely where the build cannot
  // read that — see `BootInfo.media`.
  { id: "integration_music", name: "Now Playing", color: "#FA2D48", fields: [] },
];

const MAX_ACTIVE = 4;

function integrationsSection(present: Record<string, boolean>, media: boolean): HTMLElement {
  const note = h("div", { class: "hint" });
  const list = h("div", { style: "display:flex;flex-direction:column;gap:14px" });

  function updateNote() {
    const used = settings.activeIntegrations.length;
    note.textContent = `Pick up to ${MAX_ACTIVE} pills to show next to Mochi — ${used}/${MAX_ACTIVE} in use. Keys are stored in the Windows Credential Manager, never on disk.`;
  }
  activeChanged.push(updateNote);

  for (const def of INTEGRATIONS) {
    if (def.id === "integration_music" && !media) continue;
    const rows = h("div", { style: "display:flex;flex-direction:column;gap:6px;flex:1 1 auto;min-width:0" });
    for (const field of def.fields) rows.append(credentialRow(field, present));

    list.append(
      h("div", { style: "display:flex;gap:12px;align-items:flex-start" },
        h("div", { style: "display:flex;align-items:center;gap:8px;min-width:132px;padding-top:4px" },
          pillToggle(def.id),
          h("i", { class: "dot", style: `background:${def.color}` }),
          h("span", { style: "font-size:12.5px", text: def.name }),
        ),
        rows,
      ),
    );
  }

  updateNote();
  return h("section", {}, h("h2", {}, h("span", { text: t("Integrations") })), note, list);
}

// ── Messages section ──────────────────────────────────────────────────────────
// Mattermost and ClickMassa. Unlike the pollers these hold a socket open, so
// the dot reports the connection rather than whether a key happens to exist.

interface MessageSourceDef {
  /** Pill id, matching `messages.rs`. */
  pill: string;
  source: MessageSource;
  name: string;
  color: string;
  hint: string;
  /** Written by Rust after it signs in; the user only ever clears it. */
  tokenKey: string;
  /**
   * Signs in now, rather than waiting for the supervisor to look again.
   *
   * Only Mattermost has one. ClickMassa has waited for the credentials to
   * change and gone back out by itself all along, so a button would add a way
   * to press the same password at the server repeatedly and nothing else.
   */
  signIn?: () => Promise<void>;
  fields: CredentialField[];
}

const MESSAGE_SOURCE_DEFS: MessageSourceDef[] = [
  {
    pill: "integration_mattermost",
    source: "mattermost",
    name: "Mattermost",
    color: "#1B6FF3",
    hint: t("Direct messages and mentions open a card in the island, and you can answer from it."),
    tokenKey: "mattermost-token",
    signIn: () => Bridge.mattermostSignIn(),
    fields: [
      { key: "mattermost-url", label: t("Server URL"), placeholder: t("https://chat.example.com"), secret: false },
      { key: "mattermost-login", label: t("Login"), placeholder: t("you@example.com"), secret: false },
      { key: "mattermost-password", label: t("Password"), placeholder: "…", secret: true },
    ],
  },
  {
    pill: "integration_clickmassa",
    source: "clickmassa",
    name: "ClickMassa",
    color: "#41BFEF",
    hint: t("New customer messages open a card in the island; replying there answers the ticket."),
    tokenKey: "clickmassa-token",
    fields: [
      { key: "clickmassa-url", label: t("Panel URL"), placeholder: t("https://app.clickmassa.com"), secret: false },
      { key: "clickmassa-email", label: t("Email"), placeholder: t("you@example.com"), secret: false },
      { key: "clickmassa-password", label: t("Password"), placeholder: "…", secret: true },
    ],
  },
];

/** Last reported connection per source, as far as this window has heard. */
const connection: Partial<Record<MessageSource, SourceStatus>> = {};
const connectionPainters: (() => void)[] = [];

function messagesSection(present: Record<string, boolean>): HTMLElement {
  const list = h("div", { style: "display:flex;flex-direction:column;gap:20px" });

  for (const def of MESSAGE_SOURCE_DEFS) {
    const dotEl = statusDot(false);
    const stateText = h("span", { class: "hint" });
    const feedback = h("div", {});
    // A refused sign-in leaves the supervisor waiting for the credentials to
    // change rather than retrying on a timer, and it notices within a few
    // seconds by itself. This is for the person who has just corrected a
    // password and is watching the dot: it throws the stored session away and
    // goes straight back out. Pressing it repeatedly with the same password
    // does not reach the server repeatedly — see `wait_for_login_window`.
    const run = def.signIn;
    let signIn: HTMLButtonElement | null = null;
    if (run) {
      const button = h("button", { text: t("Sign in") }) as HTMLButtonElement;
      button.addEventListener("click", async () => {
        clear(feedback);
        button.disabled = true;
        try {
          await run();
          feedback.append(h("div", { class: "notice ok", text: t("Signing in — the dot above says how it went.") }));
        } catch (err) {
          feedback.append(h("div", { class: "notice err", text: `Could not sign in: ${String(err)}` }));
        } finally {
          paint();
        }
      });
      signIn = button;
    }

    function paint() {
      const stored = def.fields.every((field) => present[field.key] === true);
      const status = connection[def.source];
      if (!settings.activeIntegrations.includes(def.pill)) {
        dotEl.style.background = "#8c8c8c";
        stateText.textContent = t("Pill switched off — nothing connects to it.");
      } else if (!stored) {
        dotEl.style.background = "#f4505e";
        stateText.textContent = t("Fill in the address, the login and the password.");
      } else if (status) {
        dotEl.style.background = CONNECTION_COLOR[status.state];
        stateText.textContent = status.detail
          ? `${t(CONNECTION_LABEL[status.state])} · ${status.detail}`
          : t(CONNECTION_LABEL[status.state]);
      } else {
        dotEl.style.background = "#f5a524";
        stateText.textContent = t("Saved. Notchy signs in shortly, or press Sign in.");
      }
      // Nothing to sign in with until all three are stored.
      if (signIn) signIn.disabled = !stored;
    }
    activeChanged.push(paint);
    connectionPainters.push(paint);

    const rows = h("div", { style: "display:flex;flex-direction:column;gap:6px;flex:1 1 auto;min-width:0" });
    for (const field of def.fields) rows.append(credentialRow(field, present, paint));

    // The sign-in token is Rust's, not the user's: the only useful thing to do
    // with it here is throw it away so the next connection signs in again.
    const forget = h("button", { text: t("Forget sign-in") });
    forget.addEventListener("click", async () => {
      clear(feedback);
      try {
        await Bridge.secretClear(def.tokenKey);
        feedback.append(h("div", { class: "notice ok", text: t("Token removed. Notchy signs in again on the next connection.") }));
      } catch (err) {
        feedback.append(h("div", { class: "notice err", text: `Could not remove: ${String(err)}` }));
      }
    });
    const session = h("div", { class: "row" }, h("label", { style: "min-width:104px", text: t("Session") }));
    if (signIn) session.append(signIn);
    session.append(forget);
    rows.append(session, feedback);

    paint();
    list.append(
      h("div", {},
        h("div", { style: "display:flex;align-items:center;gap:8px;margin-bottom:6px" },
          pillToggle(def.pill),
          h("i", { class: "dot", style: `background:${def.color}` }),
          h("span", { style: "font-size:12.5px", text: def.name }),
          dotEl,
          stateText,
        ),
        h("div", { class: "hint", style: "margin-bottom:8px", text: def.hint }),
        rows,
      ),
    );
  }

  return h(
    "section",
    {},
    h("h2", {}, h("span", { text: t("Messages") })),
    h("div", {
      class: "hint",
      text: t("Both of these hold a connection open while their pill is on. Nothing is stored on disk and nothing is sent anywhere but your own server."),
    }),
    list,
  );
}

// ── Updates ───────────────────────────────────────────────────────────────────

/** Repainted from the "update-state" event, so the tray and this agree. */
let paintUpdates: (next: UpdateState) => void = () => {};

/**
 * Nothing on this row downloads or restarts by itself.
 *
 * Coucou answers Claude Code permission requests over a named pipe, and a
 * restart nobody asked for drops whichever request is waiting in it — so the
 * look at GitHub happens in the background and the install waits for a click.
 */
function updatesSection(initial: UpdateState | null): HTMLElement {
  let state: UpdateState = initial ?? {
    phase: "idle", version: null, notes: null, progress: 0,
    error: null, installable: false, keyMismatch: false, releaseUrl: "",
  };

  const dot = statusDot(true);
  const line = h("span", { class: "hint" });
  const action = h("button", { text: t("Check for updates") }) as HTMLButtonElement;

  const fill = h("i");
  const bar = h("div", { class: "progress" }, fill);

  // The notes come off the release manifest, so they are set as text and never
  // as markup: nothing arriving over the network gets to write into this window.
  const notes = h("div", { class: "notice ok" });
  const failure = h("div", { class: "notice err" });

  action.addEventListener("click", () => {
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

  paintUpdates = (next: UpdateState) => {
    state = next;
    const pct = Math.round(state.progress * 100);

    bar.style.display = state.phase === "downloading" ? "" : "none";
    fill.style.width = `${pct}%`;
    notes.style.display = state.phase === "available" && state.notes ? "" : "none";
    notes.textContent = state.notes ?? "";
    failure.style.display = state.phase === "error" ? "" : "none";
    failure.textContent = state.error ?? "";

    action.disabled = state.phase === "checking" || state.phase === "downloading";
    action.classList.toggle(
      "primary",
      state.phase === "available" || state.phase === "ready",
    );

    switch (state.phase) {
      case "checking":
        dot.style.background = "#f5a524";
        line.textContent = t("Looking…");
        action.textContent = t("Check for updates");
        break;
      case "available":
        dot.style.background = "#22c55e";
        // Three sentences, not two: a copy that cannot verify the package is
        // not the same case as the portable .zip that cannot replace itself,
        // and the difference is what somebody has to do about it.
        line.textContent = state.keyMismatch
          ? t("Notchy %@ is out. This copy was built with a signing key that has "
              + "since been replaced, so it cannot install it — install by hand "
              + "once and updates work again after that.", state.version ?? "")
          : state.installable
            ? t("Notchy %@ is out.", state.version ?? "")
            : t("Notchy %@ is out. This copy cannot replace itself.", state.version ?? "");
        action.textContent = state.installable
          ? t("Update to %@", state.version ?? "")
          : t("Open the download page");
        break;
      case "downloading":
        dot.style.background = "#f5a524";
        line.textContent = pct > 0 ? t("Downloading… %lld%", pct) : t("Downloading…");
        action.textContent = t("Downloading…");
        break;
      case "ready":
        dot.style.background = "#22c55e";
        line.textContent = t("Notchy %@ is installed.", state.version ?? "");
        action.textContent = t("Restart now");
        break;
      case "error":
        dot.style.background = "#f4505e";
        line.textContent = t("The check did not go through.");
        action.textContent = t("Try again");
        break;
      case "upToDate":
        dot.style.background = "#22c55e";
        line.textContent = t("You are on the latest version.");
        action.textContent = t("Check for updates");
        break;
      default:
        dot.style.background = "#5b6472";
        line.textContent = "";
        action.textContent = t("Check for updates");
    }
  };

  paintUpdates(state);

  return h(
    "section",
    {},
    h("h2", {}, dot, h("span", { text: t("Updates") })),
    h("div", { class: "row" },
      h("label", { text: `Notchy ${version}` }),
      action,
      line,
      bar,
    ),
    // Directly under the line that announces the failure, not at the end of the
    // section. It used to sit after the paragraph below, which put the one
    // sentence saying *why* the check failed under the fold of a window this
    // size — so "The check did not go through." read as the whole answer, and
    // the reason went unread.
    failure,
    h("div", { class: "row" },
      h("label", { text: t("Check automatically") }),
      toggle(settings.autoUpdate, (v) => { settings.autoUpdate = v; void save(); }),
    ),
    h("div", {
      class: "hint",
      text: t("Notchy asks GitHub every few hours whether a newer release exists, and "
        + "nothing more: the request carries no identifier and no usage of any kind. "
        + "It never downloads or restarts on its own — that is this button. Every "
        + "package is signed, and one that does not match is refused before it runs."),
    }),
    notes,
  );
}

// ── The ring on the island's border ───────────────────────────────────────────

/**
 * Arranging the buttons that hang off the island.
 *
 * A list rather than a drag-and-drop miniature, for the reason the Mac's is
 * one: it is keyboard-reachable, it is what a drag would have to fall back to
 * anyway, and it makes the feature usable without a gesture to get wrong.
 *
 * "Bottom" is the side away from the screen edge the island rests on, so it is
 * above the island at the bottom of the screen and below it at the top — and a
 * left or right button mirrors inward when the island is flush against that
 * side. Nothing on the border can be off the screen.
 */
function ringSection(): HTMLElement {
  const list = h("div", { style: "display:flex;flex-direction:column;gap:8px" });
  const adder = h("select", { style: "flex:0 0 auto" }) as HTMLSelectElement;
  const addRow = h("div", { class: "row" }, h("label", { text: t("Add") }), adder);

  /** The effective ring: what is stored, or what the active pills deal. */
  function current(): EdgeButton[] {
    const chosen = settings.islandEdgeButtons;
    if (chosen) return chosen;
    const active = settings.activeIntegrations;
    return ringDefaults(
      INTEGRATION_AGENTS
        .map((task) => task.id)
        .filter((id) => id === ALWAYS_LOADED_PILL || active.includes(id)),
    );
  }

  function nameOf(action: string): string {
    // Every one of these tables is kept in English, because the Swift side is
    // compared against it value for value -- see tests/*-parity.ts. The English
    // is the key, so translating happens here, where it is drawn.
    return t(
      INTEGRATION_AGENTS.find((a) => a.id === action)?.name
        ?? edgeAction(action)?.title
        ?? action,
    );
  }

  function colorOf(action: string): string {
    return INTEGRATION_AGENTS.find((t) => t.id === action)?.color
      ?? edgeAction(action)?.color
      ?? "#8E939C";
  }

  function store(next: EdgeButton[]) {
    settings.islandEdgeButtons = next;
    void save();
    paint();
  }

  function paint() {
    const buttons = current();
    clear(list);
    if (buttons.length === 0) {
      list.append(h("div", { class: "hint", text: t("Nothing on the border.") }));
    }
    buttons.forEach((button, index) => {
      const side = h("select", {}) as HTMLSelectElement;
      for (const [value, label] of [["bottom", "Row"], ["left", "Left"], ["right", "Right"]]) {
        side.append(h("option", { value, text: label }));
      }
      side.value = button.side;
      side.addEventListener("change", () => {
        const next = buttons.map((b, i) =>
          i === index ? { ...b, side: side.value as EdgeButton["side"] } : b);
        store(next);
      });

      const up = h("button", { text: "↑", title: t("Move up") });
      up.addEventListener("click", () => {
        if (index === 0) return;
        const next = [...buttons];
        [next[index - 1], next[index]] = [next[index], next[index - 1]];
        store(next);
      });

      const remove = h("button", { class: "danger", text: t("Remove") });
      remove.addEventListener("click", () => store(buttons.filter((_, i) => i !== index)));

      list.append(h("div", { class: "row" },
        h("i", { class: "dot", style: `background:${colorOf(button.action)}` }),
        h("label", { text: nameOf(button.action) }),
        side, up, remove,
      ));
    });

    // Everything not on the border yet: the built-ins first, then the pills.
    const taken = new Set(buttons.map((b) => b.action));
    const spare = [
      ...EDGE_ACTIONS.map((a) => a.id),
      ...INTEGRATION_AGENTS.map((t) => t.id),
    ].filter((id) => !taken.has(id));
    clear(adder);
    adder.append(h("option", { value: "", text: spare.length ? t("Add a button…") : t("Nothing left to add") }));
    for (const id of spare) adder.append(h("option", { value: id, text: nameOf(id) }));
    adder.disabled = spare.length === 0;
    addRow.style.display = spare.length === 0 ? "none" : "";
  }

  adder.addEventListener("change", () => {
    const action = adder.value;
    if (!action) return;
    store([...current(), { action, side: "bottom" }]);
  });

  paint();

  return h(
    "section",
    {},
    h("h2", {}, h("span", { text: t("On the island's border") })),
    list,
    addRow,
    h("div", {
      class: "hint",
      text: t("These hang off the island when it is open, and go away with it. "
        + "\"Row\" is the side away from the screen edge the island rests on; "
        + "a left or right button moves inward when the island is in a corner, "
        + "so nothing on the border can end up off the screen."),
    }),
  );
}

// ── Pages the island opens ────────────────────────────────────────────────────

/**
 * The site behind the globe, and whether the chat tab opens ChatGPT.
 *
 * Both open a window of their own on this platform rather than being drawn
 * inside the island, which is the one place the two platforms differ here: a
 * second webview inside the island's own window is not something Tauri does
 * without its unstable multiwebview feature.
 */
function pagesSection(): HTMLElement {
  const field = h("input", {
    type: "url",
    placeholder: t("https://example.com/"),
    value: settings.siteUrl,
    style: "flex:1 1 auto;min-width:0",
    spellcheck: "false",
  }) as HTMLInputElement;
  const feedback = h("div", { class: "hint" });

  function store() {
    const next = field.value.trim();
    if (next === settings.siteUrl) return;
    // Anything that is not a URL would build a window with nothing in it, and
    // the failure would show up as a globe that does nothing.
    if (next !== "" && !/^https?:\/\//i.test(next)) {
      feedback.textContent = t("That needs to start with http:// or https://.");
      return;
    }
    feedback.textContent = t("Saved. The new page is loaded next time Notchy starts.");
    settings.siteUrl = next;
    void save();
  }

  field.addEventListener("change", store);
  field.addEventListener("blur", store);

  return h(
    "section",
    {},
    h("h2", {}, h("span", { text: t("Pages") })),
    h("div", { class: "row" }, h("label", { text: t("Site") }), field),
    feedback,
    h("div", { class: "row" },
      h("label", { text: t("Chat tab opens ChatGPT") }),
      toggle(settings.webChat, (v) => { settings.webChat = v; void save(); }),
    ),
    h("div", {
      class: "hint",
      text: t("The globe opens the site; the chat tab opens either ChatGPT's own page "
        + "or the chat built into the island. Each is a window of its own, and a "
        + "link to anywhere else opens in your browser instead."),
    }),
  );
}

// ── General section ───────────────────────────────────────────────────────────

// ── Characters ────────────────────────────────────────────────────────────────

/**
 * Who each pill is.
 *
 * Pick whose character you are changing, click one of the eighteen, or set the
 * accessory and the eyes yourself. The colour is not here on purpose: it comes
 * from the pill, so the ClickMassa bot keeps ClickMassa's colour whatever it
 * wears and the pill border still matches the creature inside it.
 */
function charactersSection(): HTMLElement {
  // "" means the default, which covers every pill that has no character of its
  // own — and Mochi itself when nobody in particular is speaking.
  let editing = "";

  const who = h("select", {}) as HTMLSelectElement;
  who.append(h("option", { value: "", text: t("Everyone else (default)") }));
  who.append(...INTEGRATION_AGENTS.map((t) => h("option", { value: t.id, text: t.name })));

  const grid = h("div", { class: "char-grid" });
  const bodyGrid = h("div", { class: "char-grid bodies" });
  // Classic first, then the six.
  const bodies: (MochiShape | null)[] = [null, ...SHAPES];
  const accessory = h("select", {}) as HTMLSelectElement;
  accessory.append(h("option", { value: "", text: t("Nothing") }));
  accessory.append(...ACCESSORIES.map((a) => h("option", { value: a, text: t(ACCESSORY_LABEL[a]) })));
  const eyes = h("select", {}) as HTMLSelectElement;
  eyes.append(h("option", { value: "", text: t("As they come") }));
  eyes.append(...EYES.map((e) => h("option", { value: e, text: t(EYE_LABEL[e]) })));

  const colorOf = (id: string) =>
    INTEGRATION_AGENTS.find((t) => t.id === id)?.color ?? "#F5F6F8";

  const current = (): MochiCharacter => {
    const stored = editing ? settings.pillCharacters[editing] : undefined;
    return characterFromStorage(stored ?? settings.defaultCharacter);
  };

  function write(character: MochiCharacter) {
    const text = characterToStorage(character);
    if (editing) {
      settings.pillCharacters = { ...settings.pillCharacters, [editing]: text };
    } else {
      settings.defaultCharacter = text;
    }
    void save();
    paint();
  }

  function paint() {
    const character = current();
    const color = colorOf(editing);
    const chosen = presetMatching(character);

    // Body and face are independent axes, so they get a row each. Folding them
    // together would mean 7 x 18 tiles to say the same thing.
    clear(bodyGrid);
    for (const shape of bodies) {
      const worn: MochiCharacter = { ...character, shape };
      const on = (character.shape ?? null) === shape;
      const name = t(shape ? MOCHI_SHAPE_LABEL[shape] : "Classic");
      const tile = h("button", {
        class: on ? "char-tile on" : "char-tile",
        title: name,
        onclick: () => write(worn),
      }, characterPreview(worn, color, 48));
      tile.append(h("span", { text: name }));
      bodyGrid.append(tile);
    }

    clear(grid);
    for (const preset of CHARACTER_PRESETS) {
      // Keep whatever body is chosen: the presets name a face.
      const worn: MochiCharacter = { ...preset.character, shape: character.shape ?? null };
      const tile = h("button", {
        class: chosen?.id === preset.id ? "char-tile on" : "char-tile",
        title: preset.name,
        onclick: () => write(worn),
      }, characterPreview(worn, color, 54));
      tile.append(h("span", { text: preset.name }));
      grid.append(tile);
    }

    accessory.value = character.accessory ?? "";
    eyes.value = character.eye ?? "";
  }

  who.addEventListener("change", () => { editing = who.value; paint(); });
  accessory.addEventListener("change", () => {
    write({ ...current(), accessory: (accessory.value || null) as MochiAccessory | null });
  });
  eyes.addEventListener("change", () => {
    write({ ...current(), eye: (eyes.value || null) as MochiEye | null });
  });

  // Everything below the switch, so it can be dimmed in one go. It stays on
  // screen while the characters are off rather than disappearing: you should
  // be able to see what you have put away.
  const picker = h(
    "div",
    { class: "char-picker" },
    h("div", { class: "hint" },
      "Give each pill its own face. The colour still comes from the pill, so you "
      + "always know who is talking."),
    h("div", { class: "row" },
      h("label", { text: t("Character for") }),
      who,
    ),
    h("div", { class: "hint", text: t("Body") }),
    bodyGrid,
    h("div", { class: "hint", text: t("Face") }),
    grid,
    h("div", { class: "row" },
      h("label", { text: t("Wearing") }),
      accessory,
      h("label", { text: t("Eyes"), style: "flex:0 0 auto;width:auto;margin-left:10px" }),
      eyes,
    ),
  );

  const dim = () => picker.classList.toggle("off", settings.hideCharacters);

  paint();
  dim();

  return h(
    "section",
    {},
    h("h2", {}, h("span", { text: t("Characters") })),
    h("div", { class: "row" },
      h("label", { text: t("Hide the characters") }),
      toggle(settings.hideCharacters, (v) => {
        settings.hideCharacters = v;
        void save();
        dim();
      }),
      h("span", { class: "hint",
        text: t("every job the island has, it keeps — only the faces go") }),
    ),
    picker,
  );
}

function generalSection(): HTMLElement {
  const volume = h("input", {
    type: "range", min: "0", max: "0.2", step: "0.005",
    value: String(settings.soundVolume),
  }) as HTMLInputElement;
  volume.addEventListener("input", () => {
    settings.soundVolume = Number(volume.value);
    void save();
  });

  const autoClose = h("input", {
    type: "number", min: "2", max: "120", step: "1",
    value: String(Math.round(settings.autoCloseInterval)),
    style: "width:72px",
  }) as HTMLInputElement;
  autoClose.addEventListener("change", () => {
    settings.autoCloseInterval = Math.max(2, Math.min(120, Number(autoClose.value) || 5));
    autoClose.value = String(settings.autoCloseInterval);
    void save();
  });

  // How far the player's two round buttons jump. Apart, because they are
  // usually wanted apart — a longer jump forward clears an ad, a shorter one
  // back catches what you missed. The number is drawn on the button, so these
  // are a label as well as a distance.
  function skipInput(get: () => number, set: (v: number) => void): HTMLInputElement {
    const el = h("input", {
      type: "number", min: "1", max: "120", step: "1",
      value: String(get()), style: "width:72px",
    }) as HTMLInputElement;
    el.addEventListener("change", () => {
      // Clamped on the way in, or the button would say where it lands and
      // then land somewhere else.
      set(Math.max(1, Math.min(120, Math.round(Number(el.value) || 10))));
      el.value = String(get());
      void save();
    });
    return el;
  }
  const skipBack = skipInput(
    () => settings.skipBackSeconds, (v) => { settings.skipBackSeconds = v; });
  const skipForward = skipInput(
    () => settings.skipForwardSeconds, (v) => { settings.skipForwardSeconds = v; });

  // What a second click on a message pill opens. One click opens the island
  // either way; this is only the second. A path rather than a picker: there
  // is no app chooser here, and Mattermost's installer puts its exe somewhere
  // the user can paste.
  function openWithRow(
    label: string,
    get: () => string,
    set: (v: string) => void,
  ): HTMLElement {
    const field = h("input", {
      type: "text", placeholder: t("website, or a path to an application"),
      style: "flex:1 1 auto;min-width:0",
      value: get() === "website" ? "" : get(),
    }) as HTMLInputElement;
    field.addEventListener("change", () => {
      const v = field.value.trim();
      set(v === "" ? "website" : v);
      void save();
    });
    return h("div", { class: "row" },
      h("label", { text: label }),
      field,
      h("span", { class: "hint", text: t("empty opens the web page") }),
    );
  }

  const screen = h("select", {}) as HTMLSelectElement;
  screen.append(
    h("option", { value: "primary", text: t("Main display") }),
    h("option", { value: "cursor", text: t("Display under the cursor") }),
  );
  screen.value = settings.screen;
  screen.addEventListener("change", () => {
    settings.screen = screen.value as Settings["screen"];
    void save();
  });

  // What the Home tab holds. The default is that the two messaging integrations
  // take turns, so Home keeps whichever spoke last and the notification is still
  // there after the card has folded away.
  const homeHint = h("span", { class: "hint", text: t(HOME_HINT[settings.homeContent]) });
  const home = h("select", {}) as HTMLSelectElement;
  home.append(...HOME_CONTENTS.map((value) => h("option", { value, text: t(HOME_LABEL[value]) })));
  home.value = settings.homeContent;
  home.addEventListener("change", () => {
    settings.homeContent = home.value as HomeContent;
    homeHint.textContent = t(HOME_HINT[settings.homeContent]);
    void save();
  });

  // The two ends of the same question — fold away and stay folded, or never
  // fold at all — so each one going on puts the other out. Left as two rows
  // rather than one three-way control because the middle setting is "neither",
  // and a switch that is simply off says that better than a third name would.
  const standbySwitch = toggle(settings.standby, (v) => {
    settings.standby = v;
    if (v && settings.alwaysVisible) {
      settings.alwaysVisible = false;
      setToggle(alwaysVisibleSwitch, false);
    }
    void save();
  });
  const alwaysVisibleSwitch = toggle(settings.alwaysVisible, (v) => {
    settings.alwaysVisible = v;
    if (v && settings.standby) {
      settings.standby = false;
      setToggle(standbySwitch, false);
    }
    void save();
  });

  const position = h("select", {}) as HTMLSelectElement;
  // POSITIONS is compared against IslandAnchor.swift by tests/island-anchor-parity.ts,
  // so it keeps its English and is translated here, where it is drawn.
  position.append(...POSITIONS.map(([value, text]) => h("option", { value, text: t(text) })));
  // An island that was dragged somewhere is not one of the six, and a select
  // with no matching option shows blank. It gets an entry of its own, so the
  // row still says where Mochi is — and picking a name from the list is how
  // you put her back on an edge.
  const dropped = h("option", {
    value: settings.position,
    text: t("Where you dropped it"),
  }) as HTMLOptionElement;
  if (isFree(settings.position)) position.append(dropped);
  position.value = settings.position;
  position.addEventListener("change", () => {
    settings.position = position.value;
    if (!isFree(settings.position)) dropped.remove();
    void save();
  });

  // Above Sound, because it decides how every other row in this window reads.
  // Changing it repaints the whole window: half a window in the old language
  // is how a translation looks broken even when it is complete.
  const language = h("select", {}) as HTMLSelectElement;
  language.append(
    ...LANGUAGES.map((value) => h("option", { value, text: LANGUAGE_LABEL[value] })),
  );
  language.value = settings.language;
  language.addEventListener("change", () => {
    settings.language = language.value as Language;
    void save();
    applyLanguage();
    repaint();
  });

  return h(
    "section",
    {},
    h("h2", {}, h("span", { text: t("General") })),
    h("div", { class: "row" },
      h("label", { text: t("Language") }),
      language,
      h("span", { class: "hint", text: t("Mochi speaks this language everywhere.") }),
    ),
    h("div", { class: "row" },
      h("label", { text: t("Sound") }),
      toggle(settings.soundEnabled, (v) => { settings.soundEnabled = v; void save(); }),
      volume,
    ),
    h("div", { class: "row" },
      h("label", { text: t("Auto-close") }),
      autoClose,
      h("span", { class: "hint", text: t("seconds a notification stays open") }),
    ),
    h("div", { class: "row" },
      h("label", { text: t("Skip back") }),
      skipBack,
      h("span", { class: "hint", text: t("seconds the player's left round button jumps") }),
    ),
    h("div", { class: "row" },
      h("label", { text: t("Skip forward") }),
      skipForward,
      h("span", { class: "hint", text: t("seconds the right one jumps") }),
    ),
    openWithRow("Mattermost opens",
      () => settings.mattermostOpenTarget,
      (v) => { settings.mattermostOpenTarget = v; }),
    openWithRow("ClickMassa opens",
      () => settings.clickMassaOpenTarget,
      (v) => { settings.clickMassaOpenTarget = v; }),
    h("div", { class: "row" },
      h("label", { text: t("Always visible") }),
      alwaysVisibleSwitch,
      h("span", { class: "hint", text: t("Mochi stays in its corner instead of folding away") }),
    ),
    h("div", { class: "row" },
      h("label", { text: t("Standby") }),
      standbySwitch,
      h("span", { class: "hint", text: t("once folded away, only a message brings Mochi back") }),
    ),
    h("div", { class: "row" },
      h("label", { text: t("Home shows") }),
      home,
      homeHint,
    ),
    h("div", { class: "row" },
      h("label", { text: t("Island lives on") }),
      screen,
    ),
    h("div", { class: "row" },
      h("label", { text: t("Island sits at") }),
      position,
      h("span", { class: "hint", text: t("where Mochi peeks out") }),
    ),
    h("div", { class: "row" },
      h("label", { text: t("Launch at startup") }),
      toggle(settings.autostart, (v) => { settings.autostart = v; void save(); }),
    ),
  );
}

// ── Boot ──────────────────────────────────────────────────────────────────────

/**
 * Puts the chosen language in force and tells Rust, whose tray cannot read the
 * system language on Windows without a crate for it.
 */
function applyLanguage() {
  setLanguage(settings.language);
  void Bridge.setLanguage(resolve(settings.language));
}

/** Set by main(); redraws the window in the current language. */
let repaint: () => void = () => {};

async function main() {
  const boot = await Bridge.boot();
  if (boot) {
    settings = { ...settings, ...boot.settings };
    version = boot.version;
  }
  // Before the first section is built, so nothing is drawn in English and then
  // corrected a frame later.
  applyLanguage();
  const hasKey = (await Bridge.secretPresent("anthropic-api-key")) ?? false;
  const update = await Bridge.updateState();

  const keys = MESSAGE_SOURCE_DEFS.flatMap((def) => def.fields.map((field) => field.key));
  const present: Record<string, boolean> = {};
  for (const k of keys) present[k] = (await Bridge.secretPresent(k)) ?? false;

  // Named so the language row can call it again. Everything it needs was read
  // once, above, so a repaint costs no round trip.
  repaint = () => {
    connectionPainters.length = 0;
    // The webview's document title is what Windows draws in the title bar, so
    // it has to be set here rather than left to the builder's title in Rust —
    // and it has to move with the language, like every other string in the
    // window.
    document.title = t("Settings — Notchy");
    clear(root);
    root.append(
      h("h1", {}, h("span", { text: t("Notchy") }), h("span", { class: "version", text: version })),
      masterSection(),
      apiSection(hasKey),
      integrationsSection(present, boot?.media ?? false),
      messagesSection(present),
      ringSection(),
      pagesSection(),
      charactersSection(),
      generalSection(),
      updatesSection(update),
      h("div", {
        class: "hint",
        text: t("No telemetry. Network requests only go to the services you configure yourself."),
      }),
    );
  };
  repaint();

  void onEvent<Settings>("settings-changed", (s) => {
    const was = settings.enabled;
    settings = { ...settings, ...s };
    // Repaint the one row that changed, never the window: a re-render would
    // throw away a hook diff somebody is halfway through reading.
    if (was !== settings.enabled) paintMaster(settings.enabled);
    for (const paint of connectionPainters) paint();
  });

  void onEvent<UpdateState>("update-state", (next) => paintUpdates(next));

  // Rust used to address this at the island alone, so it never reached this
  // window: the dots fell back to what is stored, and a failure latched once
  // stayed on screen however the credentials changed. It is sent here too now.
  void onEvent<ConnectionStatus>("message-status", (status) => {
    connection[status.source] = { state: status.state, detail: status.detail };
    for (const paint of connectionPainters) paint();
  });
}

void main();
