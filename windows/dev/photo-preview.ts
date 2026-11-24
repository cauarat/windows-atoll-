// Dev harness: a received photo on the message card — landscape, portrait
// with a caption, a post holding more than one, and one that could not be
// fetched — built twice, caption clamped and whole.
//
// Each stage is the height `islandSize` asks for with the same overflow
// `island.bodyOverflow` works out, so a photo drawn taller than the card made
// room for pushes the reply bar out of the stage where it can be seen. The
// photos are painted on a canvas: nothing here can reach a Mattermost server.

import "../src/style.css";
import { buildMessage } from "../src/views/message";
import type { ViewActions } from "../src/views/views";
import { State, type InboxMessage } from "../src/core/state";
import { Bridge, type MessagePhoto } from "../src/core/bridge";
import * as InboxPhoto from "../src/island/inboxPhoto";
import {
  MESSAGE_BODY_TWO_LINES, MESSAGE_EXPANDED_CAP, PHOTO_CAPTION_GAP, botPosition, islandSize,
  photoColumnWidth, photoDisplaySize,
} from "../src/core/layout";
import { measureBodyHeight } from "../src/views/dom";

const noop = () => {};
const actions: ViewActions = {
  setView: noop, collapse: noop, setFocus: noop, openTerminal: noop,
  openTarget: noop, openUrl: noop, decide: noop, toggleSound: noop,
  setVolume: noop, setAutoClose: noop, openSettingsWindow: noop,
  setPinned: noop, focusField: noop, closeScreen: noop, blip: noop,
};

const CAPTION = "Olha como ficou o comprovante, confere se o valor está certo antes de "
  + "enviar para o financeiro por favor, preciso disso ainda hoje";

/** A gradient with two circles, `w`×`h`, as the bytes a server would send. */
async function painted(w: number, h: number): Promise<ArrayBuffer> {
  const canvas = document.createElement("canvas");
  canvas.width = w;
  canvas.height = h;
  const g = canvas.getContext("2d")!;
  const fill = g.createLinearGradient(0, 0, w, h);
  fill.addColorStop(0, "#7ac943");
  fill.addColorStop(1, "#4fd1c5");
  g.fillStyle = fill;
  g.fillRect(0, 0, w, h);
  g.fillStyle = "#f5f0b5";
  g.fillRect(w * 0.35, 0, w * 0.3, h);
  g.fillStyle = "#5ad6c4";
  for (const y of [0.2, 0.55]) {
    g.beginPath();
    g.arc(w / 2, h * y, Math.min(w, h) * 0.17, 0, Math.PI * 2);
    g.fill();
  }
  const blob = await new Promise<Blob>((done) => canvas.toBlob((b) => done(b!), "image/jpeg", 0.9));
  return blob.arrayBuffer();
}

const BYTES = new Map<string, Promise<ArrayBuffer>>([
  ["landscape", painted(2400, 1800)],
  ["portrait", painted(1800, 2400)],
]);
Bridge.mattermostPhoto = async (fileId: string) => {
  const bytes = BYTES.get(fileId);
  if (!bytes) throw new Error("not here");
  return bytes;
};

function photo(fileId: string, w: number, h: number, caption: string | null): MessagePhoto {
  return {
    fileId, name: `${fileId}.jpg`, mimeType: "image/jpeg", pixelWidth: w, pixelHeight: h,
    hasPreview: true, byteCount: 2_400_000, miniPreview: null, caption, more: 0,
  };
}

const FIXTURES: { label: string; photo: MessagePhoto }[] = [
  { label: "landscape, alone", photo: photo("landscape", 2400, 1800, null) },
  { label: "portrait, with a caption", photo: photo("portrait", 1800, 2400, CAPTION) },
  { label: "two more on the post", photo: { ...photo("landscape", 2400, 1800, "três fotos"), more: 2 } },
  { label: "could not be fetched", photo: photo("missing", 1920, 1080, null) },
];

function message(p: MessagePhoto): InboxMessage {
  return {
    id: `m-${p.fileId}-${p.caption ?? ""}`, source: "mattermost", kind: "directMessage",
    sender: "maria.eduarda", channel: null, conversationId: "c1",
    body: `📷 ${p.caption ?? "Photo"}`, timestampMs: Date.now() - 40_000,
    link: "https://example.invalid/", read: false, photo: p,
  };
}

/** `island.bodyOverflow`, for a photo. */
function overflow(p: MessagePhoto, full: boolean): number {
  const width = photoColumnWidth(false);
  let words = 0;
  if (p.caption) {
    const tall = measureBodyHeight(p.caption, width);
    words = PHOTO_CAPTION_GAP + (full ? tall : Math.min(tall, MESSAGE_BODY_TWO_LINES));
  }
  return photoDisplaySize(p.pixelWidth, p.pixelHeight, width).h + words - MESSAGE_BODY_TWO_LINES;
}

function column(id: string, full: boolean) {
  const host = document.getElementById(id)!;
  for (const fixture of FIXTURES) {
    State.settings = { ...State.settings, messageFullBody: full };
    const view = buildMessage(actions);
    const msg = message(fixture.photo);
    State.messages = [msg];
    State.activeMessageId = msg.id;

    const { h } = islandSize("expanded", "message", 0, "automatic", 0, false, false,
                             overflow(fixture.photo, full));
    const bot = botPosition("expanded", "message", h);

    host.append(Object.assign(document.createElement("div"),
      { className: "label", textContent: `${fixture.label} — ${h}px` }));
    const stage = document.createElement("div");
    stage.className = "stage";
    stage.style.height = `${h}px`;
    const inner = document.createElement("div");
    inner.className = "inner";
    view.el.classList.add("on");
    inner.append(view.el);
    const cap = document.createElement("div");
    cap.className = "cap";
    cap.style.top = `${MESSAGE_EXPANDED_CAP - 1}px`;
    const face = document.createElement("div");
    face.className = "mochi";
    face.style.left = `${bot.cx - bot.diameter / 2}px`;
    face.style.top = `${bot.cy - bot.diameter / 2}px`;
    face.style.width = `${bot.diameter}px`;
    face.style.height = `${bot.diameter}px`;
    stage.append(inner, cap, face);
    host.append(stage);
    view.sync();
  }
}

// The photos first, so each card is built with its photo already here.
for (const fixture of FIXTURES) InboxPhoto.load(fixture.photo);
setTimeout(() => {
  column("clamped", false);
  column("full", true);
}, 600);
