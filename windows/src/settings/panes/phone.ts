// Settings › General › Phone — the Mac's PhoneLinkSettingsBox (PhoneLink/PhoneLinkSettings.swift),
// row for row: the switch that starts the link, its note, the status line and the pairing code
// behind a click, a divider, then the four switches, each with its note and greyed while the
// link is off. Notchy for iPhone and Android pair with this computer as they do with a Mac
// (docs/PHONE_LINK.md).
//
// Rust owns every value here (phone_link/mod.rs): the switches are its commands', not fields
// `save()` writes, because the first one starts a network server. So the box reads the link's
// status and draws it, and redraws when any window changes a setting.
//
// Where the Mac says "this Mac", the same sentence says "this computer" — the same rule as
// "Launch at Windows startup" in the Startup box.

import "./phone.css";
import { Bridge, type PhoneLinkFeature, type PhoneLinkPairing, type PhoneLinkStatus } from "../../core/bridge";
import { t } from "../../core/i18n";
import { h } from "../../views/dom";
import { checkbox, divider, groupBox, hint, inlineRow, pushButton, type Checkbox } from "../controls";
import { setStatus } from "../store";

const OFF: PhoneLinkStatus = {
  enabled: false, running: false, port: 0, phones: 0, error: null,
  details: false, diffs: false, answers: false, chat: false,
};

/** How often the box asks for the number of phones, while it is on screen and the link runs. */
const PHONES_POLL_MS = 3000;

/** The four switches under the first, with their notes, in the Mac's order. */
const FEATURES: { feature: PhoneLinkFeature; label: string; note: string }[] = [
  {
    feature: "details",
    label: "Show session details on the phone",
    note: "The steps of each session, its folder name and its last line. Never a path, a prompt or a command's output.",
  },
  {
    feature: "diffs",
    label: "Show the files an agent changed on the phone",
    note: "File names and the lines that changed, read from the island when the phone asks. Nothing is stored on the phone.",
  },
  {
    feature: "answers",
    label: "Let the phone answer Claude Code's questions",
    note: "The choices of a question show up on the phone, which asks for Face ID or its screen lock before it answers.",
  },
  {
    feature: "chat",
    label: "Let the phone chat with my AI providers",
    note: "Your phone sends text and gets Mochi's answer back. Your computer calls the providers set up in Chat, with its own keys: no key ever leaves this computer.",
  },
];

function failed(err: unknown) {
  setStatus(`❌ ${t("The phone link could not start: %@", String(err))}`);
}

/** The box, and what redraws it from Rust's status. */
export function phoneGroup(): { el: HTMLElement; sync(): void } {
  let status: PhoneLinkStatus = OFF;
  /** The pairing code is shown only after a click: whoever holds it can pair. */
  let showCode = false;
  let pairing: PhoneLinkPairing | null = null;

  const master = checkbox(t("Show my agent sessions on my phone"), false, (on) => {
    showCode = false;
    pairing = null;
    Bridge.phoneLinkSetEnabled(on).then(apply, (err) => {
      failed(err);
      void refresh();
    });
  });

  // The status line, the code's button and the code itself: rebuilt as the link changes.
  const live = h("div", { class: "phone-live" });

  const switches = new Map<PhoneLinkFeature, Checkbox>();
  const rows: HTMLElement[] = [];
  for (const { feature, label, note } of FEATURES) {
    const box = checkbox(t(label), false, (on) => {
      Bridge.phoneLinkSetFeature(feature, on).then(apply, (err) => {
        setStatus(`❌ ${String(err)}`);
        void refresh();
      });
    });
    switches.set(feature, box);
    rows.push(box, hint(t(note)));
  }

  const rule = divider();
  rule.classList.add("phone-divider");

  const el = groupBox(t("Phone"),
    master,
    hint(t("Notchy for iPhone and Android connects to this computer over your local network, nothing in between. "
      + "Your phone sees your agents' state and can allow or deny a permission request. "
      + "Off, nothing listens and nothing is announced on the network.")),
    live,
    rule,
    ...rows,
  );

  function statusLine(): HTMLElement | null {
    if (status.error) return hint(t("The phone link could not start: %@", status.error));
    if (!status.running) return null;
    return hint(status.phones === 0
      ? t("Listening on port %lld. No phone connected.", status.port)
      : t("Listening on port %lld. Phones connected: %lld.", status.port, status.phones));
  }

  function pairingCode(): HTMLElement[] {
    const link = pairing?.link;
    if (!pairing || !link) {
      return [hint(t("This computer has no address on a local network right now. Join a Wi-Fi or plug in a cable, then try again."))];
    }
    const qr = h("div", { class: "phone-qr", role: "img" });
    qr.setAttribute("aria-label", t("Pairing code"));
    // Rust's own drawing of the link (qrcode crate): a path, no script, nothing from the network.
    qr.innerHTML = pairing.qrSvg;
    const text = h("div", { class: "phone-link", text: link });
    const copy = pushButton(t("Copy the link"), () => {
      Bridge.phoneLinkCopyPairing().catch((err) => setStatus(`❌ ${String(err)}`));
    });
    const again = pushButton(t("Pair again"), () => {
      Bridge.phoneLinkNewPairing().then((next) => {
        pairing = next;
        paint();
      }, (err) => setStatus(`❌ ${String(err)}`));
    });
    return [
      hint(t("Open Notchy on your phone and scan this code, or paste the link. Your phone and this computer must be on the same Wi-Fi.")),
      qr,
      text,
      inlineRow(copy, again),
      hint(t("Pair again makes a new code: the phone paired with the old one is disconnected and has to scan again.")),
    ];
  }

  function paint() {
    master.set(status.enabled);
    for (const [feature, box] of switches) {
      box.set(status[feature]);
      box.setDisabled(!status.enabled);
    }
    const parts: HTMLElement[] = [];
    if (status.enabled) {
      const line = statusLine();
      if (line) parts.push(line);
      if (status.running) {
        parts.push(pushButton(t(showCode ? "Hide the pairing code" : "Show the pairing code"), () => void toggleCode()));
        if (showCode) parts.push(...pairingCode());
      }
    }
    live.replaceChildren(...parts);
    live.hidden = parts.length === 0;
  }

  async function toggleCode() {
    showCode = !showCode;
    pairing = null;
    if (showCode) {
      try {
        pairing = await Bridge.phoneLinkPairing();
      } catch (err) {
        showCode = false;
        setStatus(`❌ ${String(err)}`);
      }
    }
    paint();
  }

  function apply(next: PhoneLinkStatus) {
    status = next;
    if (!status.running) {
      showCode = false;
      pairing = null;
    }
    paint();
  }

  async function refresh() {
    const next = await Bridge.phoneLinkStatus();
    if (next) apply(next);
  }

  // The number of phones changes without any setting changing: read again while the box is on screen and the link
  // runs, as the Mac's view follows its published count. Stops when the pane is left.
  const poll = window.setInterval(() => {
    if (!el.isConnected) {
      window.clearInterval(poll);
      return;
    }
    if (!status.running || document.visibilityState !== "visible") return;
    void Bridge.phoneLinkStatus().then((next) => {
      if (next && (next.phones !== status.phones || next.running !== status.running || next.error !== status.error)) apply(next);
    });
  }, PHONES_POLL_MS);

  paint();
  void refresh();
  return { el, sync: () => void refresh() };
}
