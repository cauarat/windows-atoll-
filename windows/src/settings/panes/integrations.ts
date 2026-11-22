// Integrations — the Mac's integrationsSection (SettingsView.swift): one
// untitled GroupBox. The "Messages" caption and "Show the whole message",
// then a block per service in the Mac's order — Mattermost, Ato, the Agenda,
// WhatsApp — each a header (mark, name, a status chip on the right), its
// fields, its buttons, an "Open with" row and a footer.
//
// Phase 1 of the parity work: the Mac's layout and controls over TODAY's
// flows. A credential is still saved one field at a time, and as Windows
// cannot read one back, a stored field says "(stored)" where the Mac shows
// the value. Sign In and Forget sign-in are the old Session buttons, and
// "Open with" is still a path typed by hand. Still to come: the Mac's single
// Sign In / Sign Out form (W-40, W-41), the Agenda's own sign-in, status and
// buttons (W-42), WhatsApp's linked state (W-43), the popup with Choose…
// (W-44), and "Also show a macOS notification" (W-39).

import "./integrations.css";
import { Bridge, type MessageSource } from "../../core/bridge";
import { DEFAULT_LEAD_MINUTES, LEAD_CHOICES } from "../../core/agendaRules";
import { t } from "../../core/i18n";
import { WEBSITE_SETTING } from "../../core/pillOpen";
import { PILL_FOR_SOURCE, SOURCE_COLOR } from "../../core/state";
import { h } from "../../views/dom";
import { atoMark } from "../../views/logos";
import { boxedSymbol } from "../icons";
import {
  caption, checkbox, colorDot, groupBox, hint, inlineRow, popup, pushButton,
  secureField, spacer, spinner, stack, statusChip, textField,
  type StatusChip,
} from "../controls";
import {
  MAX_ACTIVE, connection, emit, save, secrets, setStatus, settings, subscribe,
} from "../store";

/** The colours the Mac draws its chips in: SwiftUI's system ones. */
const CHIP_COLOR = {
  green: "var(--green)",
  yellow: "var(--yellow)",
  orange: "var(--orange)",
  red: "var(--red)",
  grey: "var(--secondary)",
};

/** AgendaView.accent — the Agenda's calendar, here and on the island. */
const AGENDA_ACCENT = "#38BDF8";

/**
 * What whatsapp.rs reports while WhatsApp Web shows its QR code: a "failed"
 * carrying this sentence. The Mac has a state of its own for it, and an
 * orange chip.
 */
const WHATSAPP_QR = "Scan the QR code in Settings to connect WhatsApp.";

// ── Repainting ───────────────────────────────────────────────────────────────

/**
 * What redraws each block from the store, filled afresh by every render. A
 * save in one block can change another — the Agenda signs in with Ato's
 * account — so a save repaints them all.
 */
let painters: (() => void)[] = [];

function repaint(): void {
  for (const paint of painters) paint();
}

// ── Pieces every block uses ──────────────────────────────────────────────────

/** The Mac's connectionLabel: the chip for where a message source stands. */
function paintChip(chip: StatusChip, source: MessageSource): void {
  const status = connection[source];
  switch (status?.state) {
    case "connected":
      // Mattermost and Ato name the account; WhatsApp has nobody to name.
      chip.set(status.detail ? t("Connected as %@", status.detail) : t("Connected"), CHIP_COLOR.green);
      break;
    case "connecting":
      chip.set(t("Connecting…"), CHIP_COLOR.yellow);
      break;
    case "failed":
      if (status.detail === WHATSAPP_QR) {
        chip.set(t("Waiting for the QR code to be scanned"), CHIP_COLOR.orange);
      } else {
        chip.set(status.detail ? t(status.detail) : t("Connection failed"), CHIP_COLOR.red);
      }
      break;
    default:
      // Also a pill that is switched off, which reports "disconnected": the
      // footer under the block says to turn it on.
      chip.set(t("Not connected"), CHIP_COLOR.grey);
  }
}

/** A logo, or a 12pt symbol, in the 16x16 frame the Mac gives it. */
function mark(content: Node, color?: string): HTMLElement {
  return h("span", { class: "ig-mark", style: color ? `color:${color}` : undefined }, content);
}

/** HStack(spacing: 6): the mark, the name in 12pt semibold, Spacer, the chip. */
function header(markEl: Node, name: string, chip: HTMLElement): HTMLElement {
  const row = inlineRow(markEl, h("span", { class: "ig-name", text: name }), spacer(), chip);
  row.classList.add("ig-head");
  return row;
}

/** "Open with", "Heads-up": 11pt, secondary. */
function smallLabel(text: string): HTMLElement {
  return h("span", { class: "ig-label", text });
}

type OpenTargetKey = "mattermostOpenTarget" | "atoOpenTarget" | "whatsappOpenTarget";

/**
 * What a second click on the service's pill opens — the Mac's openWithRow,
 * HStack(spacing: 6). Still today's path typed by hand, empty for the
 * website: the Mac's popup (Website, or the app) with Choose… needs a file
 * dialog, which is W-44.
 */
function openWithRow(key: OpenTargetKey): HTMLElement {
  const shown = () => (settings[key] === WEBSITE_SETTING ? "" : settings[key]);
  const field = textField(shown(), (raw) => {
    const value = raw.trim();
    settings[key] = value === "" ? WEBSITE_SETTING : value;
    field.value = shown();
    void save();
  }, { placeholder: t("website, or a path to an application"), ariaLabel: t("Open with") });
  // Another window may change it — but not under someone typing in it.
  subscribe("settings", () => {
    if (document.activeElement !== field) field.value = shown();
  });
  const row = inlineRow(smallLabel(t("Open with")), field, smallLabel(t("empty opens the web page")));
  row.style.gap = "6px";
  return row;
}

// ── Mattermost and Ato ───────────────────────────────────────────────────────

/** One Credential Manager key, drawn as one field. */
interface CredentialDef {
  key: string;
  /** The Mac's placeholder. English, the catalogue key: translated where it is drawn. */
  placeholder: string;
  /** What the field holds — for "(stored)", and for a screen reader. */
  label: string;
  secret: boolean;
}

interface ServiceDef {
  source: "mattermost" | "ato";
  name: string;
  mark: () => Node;
  /** The line under the header. Ato's says which account it means. */
  intro?: string;
  fields: CredentialDef[];
  /** Written by Rust once it has signed in; all the user can do is throw it away. */
  tokenKey: string;
  /**
   * Signs in now with what is stored, rather than waiting for the supervisor
   * to look again. Pressing it repeatedly with the same password does not
   * reach the server repeatedly — each client keeps a floor between sign-ins.
   */
  signIn: () => Promise<void>;
  openTarget: OpenTargetKey;
  footer: string;
}

const SERVICES: ServiceDef[] = [
  {
    source: "mattermost",
    name: "Mattermost",
    mark: () => colorDot(SOURCE_COLOR.mattermost, 8),
    fields: [
      { key: "mattermost-url", placeholder: "Server URL  (https://chat.example.com)", label: "Server URL", secret: false },
      { key: "mattermost-login", placeholder: "Username or email", label: "Username or email", secret: false },
      { key: "mattermost-password", placeholder: "Password", label: "Password", secret: true },
    ],
    tokenKey: "mattermost-token",
    signIn: () => Bridge.mattermostSignIn(),
    openTarget: "mattermostOpenTarget",
    footer: "Turn the Mattermost pill on for Notchy to connect. Credentials are kept in the Windows Credential Manager.",
  },
  {
    source: "ato",
    name: "Ato",
    mark: () => mark(atoMark(16)),
    intro: "Sign in with your Actuar account — the one you use on novo.actuar.com.",
    fields: [
      { key: "ato-email", placeholder: "Email", label: "Email", secret: false },
      { key: "ato-password", placeholder: "Password", label: "Password", secret: true },
    ],
    tokenKey: "ato-token",
    signIn: () => Bridge.atoSignIn(),
    openTarget: "atoOpenTarget",
    // The Mac's footer says "reach the notch"; a PC has the island instead.
    footer: "Turn the Ato pill on for Notchy to connect. Only conversations assigned to you, "
      + "and new ones waiting in your queues, reach the island. Listening does not change "
      + "your status in Ato.",
  },
];

/**
 * A field and its own Save, which writes straight to the Credential Manager —
 * an empty field clears the key. Nothing is read back, so the field empties
 * and its placeholder says "(stored)".
 */
function credentialRow(def: CredentialDef, saved: () => void): HTMLElement {
  const placeholder = () => (secrets[def.key] ? `${t(def.label)}  ${t("(stored)")}` : t(def.placeholder));
  const field = (def.secret ? secureField : textField)("", () => {}, {
    placeholder: placeholder(),
    ariaLabel: t(def.label),
  });
  async function store() {
    const value = field.value.trim();
    try {
      await Bridge.secretSet(def.key, value);
      secrets[def.key] = value.length > 0;
      field.value = "";
      field.placeholder = placeholder();
      saved();
    } catch (err) {
      setStatus(`❌ ${t("Could not save: %@", String(err))}`);
    }
  }
  return inlineRow(field, pushButton(t("Save"), () => void store()));
}

/** Mattermost's block or Ato's — VStack(spacing: 5). */
function serviceBlock(def: ServiceDef): HTMLElement {
  const pill = PILL_FOR_SOURCE[def.source];
  const chip = statusChip("", CHIP_COLOR.grey);
  const stored = () => def.fields.every((field) => secrets[field.key] === true);

  // A refused sign-in leaves the supervisor waiting for the credentials to
  // change rather than retrying on a timer. This is for the person who has
  // just corrected a password: it throws the stored session away and goes
  // straight back out.
  const signIn = pushButton(t("Sign In"), () => void signInNow(), { kind: "prominent" });
  // The session token is Rust's, not the user's: the one useful thing to do
  // with it here is throw it away, so the next connection signs in afresh.
  const forget = pushButton(t("Forget sign-in"), () => void forgetSession());
  const busy = spinner();

  async function signInNow() {
    signIn.setDisabled(true);
    try {
      await def.signIn();
      setStatus(t("Signing in — the dot above says how it went."));
    } catch (err) {
      setStatus(`❌ ${t("Could not sign in: %@", String(err))}`);
    } finally {
      paint();
    }
  }

  async function forgetSession() {
    try {
      await Bridge.secretClear(def.tokenKey);
      setStatus(t("Token removed. Notchy signs in again on the next connection."));
    } catch (err) {
      setStatus(`❌ ${t("Could not remove: %@", String(err))}`);
    }
  }

  /** Where a saved field leaves the service — the sentences the old header said. */
  function savedStatus() {
    if (!stored()) {
      setStatus(def.fields.length === 2
        ? t("Fill in the email and the password.")
        : t("Fill in the address, the login and the password."));
    } else if (!settings.activeIntegrations.includes(pill)) {
      setStatus(t("Pill switched off — nothing connects to it."));
    } else {
      setStatus(t("Saved. Notchy signs in shortly, or press Sign in."));
    }
  }

  function paint() {
    const connecting = connection[def.source]?.state === "connecting";
    paintChip(chip, def.source);
    signIn.setText(connecting ? t("Signing in…") : t("Sign In"));
    // Nothing to sign in with until every field is stored.
    signIn.setDisabled(connecting || !stored());
    busy.style.display = connecting ? "" : "none";
  }
  painters.push(paint);
  paint();

  return stack(5,
    header(def.mark(), def.name, chip),
    def.intro ? hint(t(def.intro), 10) : null,
    ...def.fields.map((field) => credentialRow(field, () => {
      savedStatus();
      repaint();
    })),
    // HStack(spacing: 8): the buttons, the spinner while connecting, Spacer.
    inlineRow(signIn, forget, busy),
    openWithRow(def.openTarget),
    hint(t(def.footer), 10),
  );
}

// ── Agenda ───────────────────────────────────────────────────────────────────

/**
 * Today's meetings from Actuar's commercial panel, in a tab of the island, and
 * a heads-up before each one starts.
 *
 * No credentials of its own: the panel signs in with the Actuar account Ato
 * keeps, so its e-mail and password are the ones in the Ato block above. The
 * Mac's chip reads the panel's own status, which does not reach this window
 * yet, so it says only what is known here: Off, or Not signed in.
 */
function agendaBlock(): HTMLElement {
  const chip = statusChip("", CHIP_COLOR.grey);
  const signedIn = () => secrets["ato-email"] === true && secrets["ato-password"] === true;

  const enabled = checkbox(t("Show the Agenda tab"), settings.agendaEnabled, (on) => {
    settings.agendaEnabled = on;
    paint();
    void save();
  });

  const account = hint("", 10);

  // A stored value the list does not offer reads as the default, as
  // AgendaClient reads it on the Mac.
  const leadValue = () => String(LEAD_CHOICES.includes(settings.agendaLeadMinutes)
    ? settings.agendaLeadMinutes
    : DEFAULT_LEAD_MINUTES);
  const lead = popup(
    LEAD_CHOICES.map((minutes) => ({ value: String(minutes), label: t("%lld min before", minutes) })),
    leadValue(),
    (value) => {
      settings.agendaLeadMinutes = Number(value);
      void save();
    },
    { ariaLabel: t("Heads-up") },
  );
  // HStack(spacing: 6): "Heads-up", the popup in .frame(maxWidth: 160), Spacer.
  const leadRow = inlineRow(
    smallLabel(t("Heads-up")),
    h("span", { class: "ig-frame", style: "flex:0 1 160px" }, lead),
    spacer(),
  );
  leadRow.style.gap = "6px";

  const onboarding = checkbox(t("Notify Onboarding meetings"), settings.agendaNotifyOnboarding, (on) => {
    settings.agendaNotifyOnboarding = on;
    void save();
  });
  const backoffice = checkbox(t("Notify Backoffice meetings"), settings.agendaNotifyBackoffice, (on) => {
    settings.agendaNotifyBackoffice = on;
    void save();
  });

  const details = stack(5,
    account,
    leadRow,
    onboarding,
    backoffice,
    hint(t("Both processes are always listed; these switches only choose which ones "
      + "open the island before a meeting."), 10),
  );

  function paint() {
    details.style.display = settings.agendaEnabled ? "" : "none";
    account.textContent = signedIn()
      ? t("Signed in with the Actuar account saved under Ato above.")
      : t("Save your Actuar e-mail and password under Ato above — the Agenda uses the same account.");
    if (!settings.agendaEnabled) {
      chip.set(t("Off"), CHIP_COLOR.grey);
      chip.style.display = "";
    } else if (!signedIn()) {
      chip.set(t("Not signed in"), CHIP_COLOR.grey);
      chip.style.display = "";
    } else {
      chip.style.display = "none";
    }
  }
  painters.push(paint);
  subscribe("settings", () => {
    enabled.set(settings.agendaEnabled);
    lead.set(leadValue());
    onboarding.set(settings.agendaNotifyOnboarding);
    backoffice.set(settings.agendaNotifyBackoffice);
  });
  paint();

  return stack(5,
    header(mark(boxedSymbol("calendar", 12), AGENDA_ACCENT), t("Agenda"), chip),
    hint(t("Today's meetings from the commercial panel, in a tab of the island, and a "
      + "heads-up before each one starts."), 10),
    enabled,
    details,
  );
}

// ── WhatsApp ─────────────────────────────────────────────────────────────────

/**
 * Set when Connect could not switch the pill on because every slot is taken,
 * so there was nothing to connect — said out loud, because otherwise the
 * button looks broken. The Mac's whatsAppNeedsPill.
 */
let whatsAppNeedsPill = false;

/**
 * WhatsApp has nothing to type: a phone links this machine by QR code, the
 * way WhatsApp Web does in a browser. The Mac's labels over today's two calls:
 * Connect (Show, once connected) puts the page up, Unlink signs out.
 */
function whatsappBlock(): HTMLElement {
  const pill = PILL_FOR_SOURCE.whatsapp;
  const chip = statusChip("", CHIP_COLOR.grey);
  const note = hint(t("All 4 pill slots are in use. Turn one off under Active pills, then "
    + "turn WhatsApp on and connect again."), 10);
  note.classList.add("ig-note");

  // Linking is asking for the page, and the pill is what lets it run: it is
  // switched on when a slot is free, and the note says so when none is.
  async function showLogin() {
    if (!settings.activeIntegrations.includes(pill)) {
      if (settings.activeIntegrations.length >= MAX_ACTIVE) {
        whatsAppNeedsPill = true;
        paint();
        return;
      }
      settings.activeIntegrations = [...settings.activeIntegrations, pill];
      emit("active");
      await save();
    }
    whatsAppNeedsPill = false;
    paint();
    try {
      await Bridge.whatsappShowLogin();
    } catch (err) {
      setStatus(`❌ ${String(err)}`);
    }
  }

  async function unlink() {
    try {
      await Bridge.whatsappSignOut();
    } catch (err) {
      setStatus(`❌ ${String(err)}`);
    }
  }

  const connect = pushButton(t("Connect WhatsApp"), () => void showLogin(), { kind: "prominent" });
  const show = pushButton(t("Show WhatsApp"), () => void showLogin());
  const unlinkButton = pushButton(t("Unlink"), () => void unlink());
  const busy = spinner();

  function paint() {
    const state = connection.whatsapp?.state;
    paintChip(chip, "whatsapp");
    connect.style.display = state === "connected" ? "none" : "";
    show.style.display = state === "connected" ? "" : "none";
    busy.style.display = state === "connecting" ? "" : "none";
    note.style.display = whatsAppNeedsPill && !settings.activeIntegrations.includes(pill) ? "" : "none";
  }
  painters.push(paint);
  paint();

  return stack(5,
    header(mark(boxedSymbol("phone.bubble.fill", 12), SOURCE_COLOR.whatsapp), "WhatsApp", chip),
    hint(t("Notchy keeps WhatsApp Web open out of sight. To link it, scan the QR code with "
      + "WhatsApp on your phone: Settings → Linked devices → Link a device."), 10),
    // HStack(spacing: 8): the buttons, the spinner while connecting, Spacer.
    inlineRow(show, connect, unlinkButton, busy),
    note,
    openWithRow("whatsappOpenTarget"),
    // The Mac's sentence says "reach the notch"; a PC has the island instead.
    hint(t("Messages reach the island while the WhatsApp pill is on, and stay unread on your "
      + "phone until you answer. Replies — text, a voice message or a file — are typed into "
      + "WhatsApp Web for you. Notchy is not an official WhatsApp client."), 10),
  );
}

// ── The pane ─────────────────────────────────────────────────────────────────

/** VStack(spacing: 2): the checkbox and its 10pt hint. */
function wholeMessage(): HTMLElement {
  const whole = checkbox(t("Show the whole message"), settings.messageFullBody, (on) => {
    settings.messageFullBody = on;
    void save();
  });
  subscribe("settings", () => whole.set(settings.messageFullBody));
  return stack(2,
    whole,
    hint(t("The card grows to hold what was written, as far as the ChatGPT page already goes; "
      + "past that the text scrolls inside it. Off, the card keeps its two lines and the rest "
      + "is behind Open."), 10),
  );
}

/** The Integrations pane: one GroupBox, VStack(spacing: 14). */
export function render(): Node[] {
  painters = [];
  // The chips follow the connections; "connection" also follows every
  // settings broadcast, since the pills are part of what the blocks say.
  subscribe("connection", repaint);
  subscribe("active", repaint);
  return [groupBox({ gap: 14 },
    caption(t("Messages")),
    wholeMessage(),
    ...SERVICES.map(serviceBlock),
    agendaBlock(),
    whatsappBlock(),
  )];
}
