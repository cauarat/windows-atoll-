// Settings window — the place where anything that writes to disk is confirmed.
// Stage 2 covers the Claude Code hooks and the general preferences; API keys and
// integrations land here too in a later stage.

import "./settings.css";
import {
  Bridge, onEvent,
  type ConnectionStatus, type HookStatus, type MessageSource, type UpdateState,
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
import { POSITIONS, type IslandPosition } from "../core/anchor";
import {
  EDGE_ACTIONS, defaults as ringDefaults, edgeAction, type EdgeButton,
} from "../core/edgeRing";
import { h, clear } from "../views/dom";

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
  const label = h("label", { text: settings.enabled ? "Coucou is on" : "Coucou is off" });
  const notice = h("div", {
    class: "notice warn",
    text: "Coucou is off — Mochi is hidden and nothing is being watched.",
  });
  notice.style.display = settings.enabled ? "none" : "";

  const sw = toggle(settings.enabled, (v) => {
    settings.enabled = v;
    void save();
    paintMaster(v);
  });

  paintMaster = (on: boolean) => {
    dot.style.background = on ? "#22c55e" : "#f4505e";
    label.textContent = on ? "Coucou is on" : "Coucou is off";
    sw.classList.toggle("on", on);
    sw.setAttribute("aria-pressed", String(on));
    notice.style.display = on ? "none" : "";
  };

  return h(
    "section",
    {},
    h("h2", {}, dot, h("span", { text: "Coucou" })),
    h("div", { class: "row" }, label, sw),
    h("div", {
      class: "hint",
      // The sentence about hooks is the support ticket this prevents: turning
      // Coucou off must not read as having broken Claude Code.
      text:
        "Off, Mochi disappears, nothing is polled and no sound plays. Your Claude Code "
        + "hooks stay installed — permission requests simply go back to being asked in "
        + "the terminal. Turn it back on here or from the icon by the clock.",
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
  const saveBtn = h("button", { text: "Save" });
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
    h("label", { style: "min-width:104px", text: field.label }),
    input, saveBtn, dotEl,
  );
}

function renderDiff(text: string): HTMLElement {
  const box = h("div", { class: "diff" });
  for (const line of text.split("\n")) {
    const cls = line.startsWith("+") ? "add" : line.startsWith("-") ? "del" : "ctx";
    box.append(h("div", { class: cls, text: line }));
  }
  return box;
}

// ── Claude Code section ───────────────────────────────────────────────────────

function claudeSection(status: HookStatus): HTMLElement {
  const body = h("div", { style: "display:flex;flex-direction:column;gap:12px" });
  const section = h(
    "section",
    {},
    h("h2", {}, statusDot(status.installed), h("span", { text: "Claude Code" })),
    body,
  );

  const rebuild = async () => {
    const fresh = await Bridge.hooksStatus();
    if (fresh) Object.assign(status, fresh);
    clear(body);
    draw();
    const head = section.querySelector("h2")!;
    clear(head);
    head.append(statusDot(status.installed), h("span", { text: "Claude Code" }));
  };

  function draw() {
    body.append(
      h("div", {
        class: "hint",
        text: status.installed
          ? "Coucou is hooked into your Claude Code sessions. Tool calls, questions and permission requests show up in the island, and you can answer them there."
          : "Install the hooks to see your Claude Code sessions in the island and approve permissions without leaving what you are doing.",
      }),
      h("div", { class: "row" },
        h("label", { text: "settings.json" }),
        h("span", { class: "path", text: status.settingsPath }),
      ),
      h("div", { class: "row" },
        h("label", { text: "Relay" }),
        h("span", { class: "path", text: status.hookPath }),
        statusDot(status.hookReady),
      ),
    );

    if (!status.hookReady) {
      body.append(h("div", {
        class: "notice warn",
        text: "coucou-hook.exe is not in place yet. Restart Coucou; if it still fails, build it with `cargo build -p coucou-hook`.",
      }));
    }

    const actions = h("div", { class: "row" });
    const install = h("button", {
      class: "primary",
      text: status.installed ? "Reinstall hooks…" : "Install hooks…",
      onclick: () => showPreview(true),
    });
    // Writing hook commands that point at a relay which isn't there would give
    // every Claude Code session a broken hook and nothing to show for it.
    if (!status.hookReady) {
      install.disabled = true;
      install.title = "The relay isn't installed yet.";
    }
    actions.append(install);
    if (status.installed) {
      actions.append(h("button", {
        class: "danger",
        text: "Uninstall hooks…",
        onclick: () => showPreview(false),
      }));
    }
    body.append(actions);
  }

  async function showPreview(install: boolean) {
    let preview;
    try {
      preview = await Bridge.hooksPreview(install);
    } catch (err) {
      // An unreadable or invalid settings.json stops here rather than being
      // treated as empty and written over.
      clear(body);
      body.append(
        h("div", { class: "notice err", text: String(err).replace(/^Error:\s*/, "") }),
        h("div", { class: "row" }, h("button", {
          text: "Back",
          onclick: () => { clear(body); draw(); },
        })),
      );
      return;
    }
    if (!preview) return;
    clear(body);
    body.append(
      h("div", {
        class: "hint",
        text: install
          ? "This is exactly what will change in your settings.json. Your own hooks are left untouched."
          : "This removes Coucou's entries only. Your own hooks are left untouched.",
      }),
      renderDiff(preview.diff),
      h("div", { class: "row" },
        h("span", { class: "path", text: `Backup → ${preview.backup}` }),
      ),
    );
    const confirm = h("button", {
      class: install ? "primary" : "danger",
      text: install ? "Back up and write" : "Back up and remove",
    });
    confirm.addEventListener("click", async () => {
      confirm.disabled = true;
      try {
        const backup = await Bridge.hooksApply(install, preview.fingerprint);
        clear(body);
        body.append(h("div", {
          class: "notice ok",
          text: `Done. Previous settings saved as ${backup}. Open a new Claude Code session to pick the hooks up.`,
        }));
        window.setTimeout(() => void rebuild(), 2600);
      } catch (err) {
        confirm.disabled = false;
        body.append(h("div", { class: "notice err", text: `Could not write: ${String(err)}` }));
      }
    });
    body.append(h("div", { class: "row" }, confirm, h("button", {
      text: "Cancel",
      onclick: () => { clear(body); draw(); },
    })));
  }

  draw();
  return section;
}

// ── Claude API section ────────────────────────────────────────────────────────

const MODELS: [string, string][] = [
  ["claude-opus-5", "Claude Opus 5"],
  ["claude-sonnet-5", "Claude Sonnet 5"],
  ["claude-haiku-4-5", "Claude Haiku 4.5"],
];

function apiSection(hasKey: boolean): HTMLElement {
  const dot = statusDot(hasKey);
  const state = h("span", { class: "hint", text: hasKey ? "Key saved in the Windows Credential Manager." : "No key yet — the chat needs one." });

  const field = h("input", {
    type: "password",
    placeholder: hasKey ? "••••••••••••  (stored)" : "sk-ant-...",
    style: "flex:1 1 auto;min-width:0",
    autocomplete: "off",
    spellcheck: "false",
  }) as HTMLInputElement;

  const saveBtn = h("button", { class: "primary", text: "Save key" });
  const clearBtn = h("button", { class: "danger", text: "Remove" });
  const feedback = h("div", {});

  async function refresh() {
    const present = (await Bridge.secretPresent("anthropic-api-key")) ?? false;
    dot.style.background = present ? "#22c55e" : "#f4505e";
    state.textContent = present
      ? "Key saved in the Windows Credential Manager."
      : "No key yet — the chat needs one.";
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
      feedback.append(h("div", { class: "notice ok", text: "Saved. It never touches disk." }));
      await refresh();
    } catch (err) {
      feedback.append(h("div", { class: "notice err", text: `Could not save: ${String(err)}` }));
    }
  });

  clearBtn.addEventListener("click", async () => {
    clear(feedback);
    try {
      await Bridge.secretClear("anthropic-api-key");
      feedback.append(h("div", { class: "notice ok", text: "Key removed." }));
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
    h("h2", {}, dot, h("span", { text: "Claude" })),
    state,
    h("div", { class: "row" }, h("label", { text: "API key" }), field, saveBtn, clearBtn),
    h("div", { class: "row" }, h("label", { text: "Model" }), model),
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
  return h("section", {}, h("h2", {}, h("span", { text: "Integrations" })), note, list);
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
    hint: "Direct messages and mentions open a card in the island, and you can answer from it.",
    tokenKey: "mattermost-token",
    signIn: () => Bridge.mattermostSignIn(),
    fields: [
      { key: "mattermost-url", label: "Server URL", placeholder: "https://chat.example.com", secret: false },
      { key: "mattermost-login", label: "Login", placeholder: "you@example.com", secret: false },
      { key: "mattermost-password", label: "Password", placeholder: "…", secret: true },
    ],
  },
  {
    pill: "integration_clickmassa",
    source: "clickmassa",
    name: "ClickMassa",
    color: "#41BFEF",
    hint: "New customer messages open a card in the island; replying there answers the ticket.",
    tokenKey: "clickmassa-token",
    fields: [
      { key: "clickmassa-url", label: "Panel URL", placeholder: "https://app.clickmassa.com", secret: false },
      { key: "clickmassa-email", label: "Email", placeholder: "you@example.com", secret: false },
      { key: "clickmassa-password", label: "Password", placeholder: "…", secret: true },
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
      const button = h("button", { text: "Sign in" }) as HTMLButtonElement;
      button.addEventListener("click", async () => {
        clear(feedback);
        button.disabled = true;
        try {
          await run();
          feedback.append(h("div", { class: "notice ok", text: "Signing in — the dot above says how it went." }));
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
        stateText.textContent = "Pill switched off — nothing connects to it.";
      } else if (!stored) {
        dotEl.style.background = "#f4505e";
        stateText.textContent = "Fill in the address, the login and the password.";
      } else if (status) {
        dotEl.style.background = CONNECTION_COLOR[status.state];
        stateText.textContent = status.detail
          ? `${CONNECTION_LABEL[status.state]} · ${status.detail}`
          : CONNECTION_LABEL[status.state];
      } else {
        dotEl.style.background = "#f5a524";
        stateText.textContent = "Saved. Coucou signs in shortly, or press Sign in.";
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
    const forget = h("button", { text: "Forget sign-in" });
    forget.addEventListener("click", async () => {
      clear(feedback);
      try {
        await Bridge.secretClear(def.tokenKey);
        feedback.append(h("div", { class: "notice ok", text: "Token removed. Coucou signs in again on the next connection." }));
      } catch (err) {
        feedback.append(h("div", { class: "notice err", text: `Could not remove: ${String(err)}` }));
      }
    });
    const session = h("div", { class: "row" }, h("label", { style: "min-width:104px", text: "Session" }));
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
    h("h2", {}, h("span", { text: "Messages" })),
    h("div", {
      class: "hint",
      text: "Both of these hold a connection open while their pill is on. Nothing is stored on disk and nothing is sent anywhere but your own server.",
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
    error: null, installable: false, releaseUrl: "",
  };

  const dot = statusDot(true);
  const line = h("span", { class: "hint" });
  const action = h("button", { text: "Check for updates" }) as HTMLButtonElement;

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
        line.textContent = "Looking…";
        action.textContent = "Check for updates";
        break;
      case "available":
        dot.style.background = "#22c55e";
        line.textContent = state.installable
          ? `Coucou ${state.version} is out.`
          : `Coucou ${state.version} is out. This copy cannot replace itself.`;
        action.textContent = state.installable
          ? `Update to ${state.version}`
          : "Open the download page";
        break;
      case "downloading":
        dot.style.background = "#f5a524";
        line.textContent = pct > 0 ? `Downloading… ${pct}%` : "Downloading…";
        action.textContent = "Downloading…";
        break;
      case "ready":
        dot.style.background = "#22c55e";
        line.textContent = `Coucou ${state.version} is installed.`;
        action.textContent = "Restart now";
        break;
      case "error":
        dot.style.background = "#f4505e";
        line.textContent = "The check did not go through.";
        action.textContent = "Try again";
        break;
      case "upToDate":
        dot.style.background = "#22c55e";
        line.textContent = "You are on the latest version.";
        action.textContent = "Check for updates";
        break;
      default:
        dot.style.background = "#5b6472";
        line.textContent = "";
        action.textContent = "Check for updates";
    }
  };

  paintUpdates(state);

  return h(
    "section",
    {},
    h("h2", {}, dot, h("span", { text: "Updates" })),
    h("div", { class: "row" },
      h("label", { text: `Coucou ${version}` }),
      action,
      line,
      bar,
    ),
    h("div", { class: "row" },
      h("label", { text: "Check automatically" }),
      toggle(settings.autoUpdate, (v) => { settings.autoUpdate = v; void save(); }),
    ),
    h("div", {
      class: "hint",
      text:
        "Coucou asks GitHub every few hours whether a newer release exists, and "
        + "nothing more: the request carries no identifier and no usage of any kind. "
        + "It never downloads or restarts on its own — that is this button. Every "
        + "package is signed, and one that does not match is refused before it runs.",
    }),
    notes,
    failure,
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
  const addRow = h("div", { class: "row" }, h("label", { text: "Add" }), adder);

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
    return INTEGRATION_AGENTS.find((t) => t.id === action)?.name
      ?? edgeAction(action)?.title
      ?? action;
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
      list.append(h("div", { class: "hint", text: "Nothing on the border." }));
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

      const up = h("button", { text: "↑", title: "Move up" });
      up.addEventListener("click", () => {
        if (index === 0) return;
        const next = [...buttons];
        [next[index - 1], next[index]] = [next[index], next[index - 1]];
        store(next);
      });

      const remove = h("button", { class: "danger", text: "Remove" });
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
    adder.append(h("option", { value: "", text: spare.length ? "Add a button…" : "Nothing left to add" }));
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
    h("h2", {}, h("span", { text: "On the island's border" })),
    list,
    addRow,
    h("div", {
      class: "hint",
      text:
        "These hang off the island when it is open, and go away with it. "
        + "\"Row\" is the side away from the screen edge the island rests on; "
        + "a left or right button moves inward when the island is in a corner, "
        + "so nothing on the border can end up off the screen.",
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
    placeholder: "https://example.com/",
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
      feedback.textContent = "That needs to start with http:// or https://.";
      return;
    }
    feedback.textContent = "Saved. The new page is loaded next time Coucou starts.";
    settings.siteUrl = next;
    void save();
  }

  field.addEventListener("change", store);
  field.addEventListener("blur", store);

  return h(
    "section",
    {},
    h("h2", {}, h("span", { text: "Pages" })),
    h("div", { class: "row" }, h("label", { text: "Site" }), field),
    feedback,
    h("div", { class: "row" },
      h("label", { text: "Chat tab opens ChatGPT" }),
      toggle(settings.webChat, (v) => { settings.webChat = v; void save(); }),
    ),
    h("div", {
      class: "hint",
      text:
        "The globe opens the site; the chat tab opens either ChatGPT's own page "
        + "or the chat built into the island. Each is a window of its own, and a "
        + "link to anywhere else opens in your browser instead.",
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
  who.append(h("option", { value: "", text: "Everyone else (default)" }));
  who.append(...INTEGRATION_AGENTS.map((t) => h("option", { value: t.id, text: t.name })));

  const grid = h("div", { class: "char-grid" });
  const bodyGrid = h("div", { class: "char-grid bodies" });
  // Classic first, then the six.
  const bodies: (MochiShape | null)[] = [null, ...SHAPES];
  const accessory = h("select", {}) as HTMLSelectElement;
  accessory.append(h("option", { value: "", text: "Nothing" }));
  accessory.append(...ACCESSORIES.map((a) => h("option", { value: a, text: ACCESSORY_LABEL[a] })));
  const eyes = h("select", {}) as HTMLSelectElement;
  eyes.append(h("option", { value: "", text: "As they come" }));
  eyes.append(...EYES.map((e) => h("option", { value: e, text: EYE_LABEL[e] })));

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
      const name = shape ? MOCHI_SHAPE_LABEL[shape] : "Classic";
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
      h("label", { text: "Character for" }),
      who,
    ),
    h("div", { class: "hint", text: "Body" }),
    bodyGrid,
    h("div", { class: "hint", text: "Face" }),
    grid,
    h("div", { class: "row" },
      h("label", { text: "Wearing" }),
      accessory,
      h("label", { text: "Eyes", style: "flex:0 0 auto;width:auto;margin-left:10px" }),
      eyes,
    ),
  );

  const dim = () => picker.classList.toggle("off", settings.hideCharacters);

  paint();
  dim();

  return h(
    "section",
    {},
    h("h2", {}, h("span", { text: "Characters" })),
    h("div", { class: "row" },
      h("label", { text: "Hide the characters" }),
      toggle(settings.hideCharacters, (v) => {
        settings.hideCharacters = v;
        void save();
        dim();
      }),
      h("span", { class: "hint",
        text: "every job the island has, it keeps — only the faces go" }),
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

  const screen = h("select", {}) as HTMLSelectElement;
  screen.append(
    h("option", { value: "primary", text: "Main display" }),
    h("option", { value: "cursor", text: "Display under the cursor" }),
  );
  screen.value = settings.screen;
  screen.addEventListener("change", () => {
    settings.screen = screen.value as Settings["screen"];
    void save();
  });

  // What the Home tab holds. The default is that the two messaging integrations
  // take turns, so Home keeps whichever spoke last and the notification is still
  // there after the card has folded away.
  const homeHint = h("span", { class: "hint", text: HOME_HINT[settings.homeContent] });
  const home = h("select", {}) as HTMLSelectElement;
  home.append(...HOME_CONTENTS.map((value) => h("option", { value, text: HOME_LABEL[value] })));
  home.value = settings.homeContent;
  home.addEventListener("change", () => {
    settings.homeContent = home.value as HomeContent;
    homeHint.textContent = HOME_HINT[settings.homeContent];
    void save();
  });

  const position = h("select", {}) as HTMLSelectElement;
  position.append(...POSITIONS.map(([value, text]) => h("option", { value, text })));
  position.value = settings.position;
  position.addEventListener("change", () => {
    settings.position = position.value as IslandPosition;
    void save();
  });

  return h(
    "section",
    {},
    h("h2", {}, h("span", { text: "General" })),
    h("div", { class: "row" },
      h("label", { text: "Sound" }),
      toggle(settings.soundEnabled, (v) => { settings.soundEnabled = v; void save(); }),
      volume,
    ),
    h("div", { class: "row" },
      h("label", { text: "Auto-close" }),
      autoClose,
      h("span", { class: "hint", text: "seconds a notification stays open" }),
    ),
    h("div", { class: "row" },
      h("label", { text: "Skip back" }),
      skipBack,
      h("span", { class: "hint", text: "seconds the player's left round button jumps" }),
    ),
    h("div", { class: "row" },
      h("label", { text: "Skip forward" }),
      skipForward,
      h("span", { class: "hint", text: "seconds the right one jumps" }),
    ),
    h("div", { class: "row" },
      h("label", { text: "Standby" }),
      toggle(settings.standby, (v) => { settings.standby = v; void save(); }),
      h("span", { class: "hint", text: "once folded away, only a message brings Mochi back" }),
    ),
    h("div", { class: "row" },
      h("label", { text: "Home shows" }),
      home,
      homeHint,
    ),
    h("div", { class: "row" },
      h("label", { text: "Island lives on" }),
      screen,
    ),
    h("div", { class: "row" },
      h("label", { text: "Island sits at" }),
      position,
      h("span", { class: "hint", text: "where Mochi peeks out" }),
    ),
    h("div", { class: "row" },
      h("label", { text: "Launch at startup" }),
      toggle(settings.autostart, (v) => { settings.autostart = v; void save(); }),
    ),
  );
}

// ── Boot ──────────────────────────────────────────────────────────────────────

async function main() {
  const boot = await Bridge.boot();
  if (boot) {
    settings = { ...settings, ...boot.settings };
    version = boot.version;
  }
  const status = (await Bridge.hooksStatus()) ?? {
    installed: false, settingsPath: "", hookPath: "", hookReady: false,
  };

  const hasKey = (await Bridge.secretPresent("anthropic-api-key")) ?? false;
  const update = await Bridge.updateState();

  const keys = MESSAGE_SOURCE_DEFS.flatMap((def) => def.fields.map((field) => field.key));
  const present: Record<string, boolean> = {};
  for (const k of keys) present[k] = (await Bridge.secretPresent(k)) ?? false;

  clear(root);
  root.append(
    h("h1", {}, h("span", { text: "Coucou" }), h("span", { class: "version", text: version })),
    masterSection(),
    claudeSection(status),
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
      text: "No telemetry. Network requests only go to the services you configure yourself.",
    }),
  );

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
