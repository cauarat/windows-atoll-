// Dev harness: an Ato voice message on the message card — waiting for its
// transcript, with a short one, and with one long enough to scroll — built
// twice, at rest and with "Show the whole message" on.
//
// Each stage is the height the island would ask for, worked out the way
// `island.bodyOverflow` does it. The clip is a tone made here, standing in for
// what `ato_voice_note` hands the card; the first card starts playing two
// thirds of the way in, so the playing state can be seen without a click.

import "../src/style.css";
import { buildMessage } from "../src/views/message";
import type { ViewActions } from "../src/views/views";
import { State, type InboxMessage } from "../src/core/state";
import { Bridge, type AtoAudio } from "../src/core/bridge";
import * as VoicePlayer from "../src/island/voicePlayer";
import {
  MESSAGE_BODY_TWO_LINES, MESSAGE_EXPANDED_CAP, VOICE_GAP, VOICE_PLAYER_HEIGHT,
  VOICE_SCROLLER_ROOM, botPosition, islandSize, messageBodyWidth,
} from "../src/core/layout";
import { measureBodyHeight } from "../src/views/dom";

const noop = () => {};
const actions: ViewActions = {
  setView: noop, collapse: noop, setFocus: noop, openUrl: noop, toggleSound: noop,
  setVolume: noop, setAutoClose: noop, openSettingsWindow: noop,
  setPinned: noop, focusField: noop, closeScreen: noop, blip: noop,
};

/** Thirty seconds of a quiet tone, as a WAV — what `ato_voice_note` would answer. */
function tone(seconds: number): ArrayBuffer {
  const rate = 8000;
  const n = rate * seconds;
  const buf = new ArrayBuffer(44 + n * 2);
  const v = new DataView(buf);
  const str = (o: number, s: string) => [...s].forEach((c, i) => v.setUint8(o + i, c.charCodeAt(0)));
  str(0, "RIFF"); v.setUint32(4, 36 + n * 2, true); str(8, "WAVE"); str(12, "fmt ");
  v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);
  v.setUint32(24, rate, true); v.setUint32(28, rate * 2, true); v.setUint16(32, 2, true);
  v.setUint16(34, 16, true); str(36, "data"); v.setUint32(40, n * 2, true);
  for (let i = 0; i < n; i++) v.setInt16(44 + i * 2, Math.sin(i / 12) * 600, true);
  return buf;
}
(Bridge as { atoVoiceNote: (id: string) => Promise<ArrayBuffer> }).atoVoiceNote =
  async () => tone(31);

const LONG = "Isso, é porque eu acho que eu configurei errado o plano anual, né? Aqui na "
  + "academia a gente tem cross-train, crossfit, musculação, hitbox e o treinamento "
  + "funcional. Todos com parcela mensal, plano trimestral, plano semestral e plano anual. "
  + "Aí a gente sempre vende mais o plano anual, né, o mais atrativo para o cliente. E daí, "
  + "eu vendi esse plano, né, quando foi agora 30 dias, ontem, aí eu precisei renovar. Aí eu "
  + "fiquei, os cara, da outra vez eu não precisava ficar renovando, não é? Aqui, essa "
  + "cliente só faz anual. Ela já está com a gente já bastante tempo.";

function audio(id: string, status: AtoAudio["transcriptStatus"], text: string | null): AtoAudio {
  return {
    attachmentId: `a-${id}`, storageFileId: id, fileName: "audio.ogg",
    contentType: "audio/ogg; codecs=opus", durationSeconds: 31,
    transcriptStatus: status, transcript: text,
  };
}

const FIXTURES: { label: string; audio: AtoAudio }[] = [
  { label: "a long transcript — scrolls under the player", audio: audio("s-long", "ready", LONG) },
  { label: "a short transcript", audio: audio("s-short", "ready", "Pode me ligar quando puder?") },
  { label: "still transcribing", audio: audio("s-pending", "pending", null) },
];

function message(fixture: { audio: AtoAudio }): InboxMessage {
  return {
    id: `m-${fixture.audio.storageFileId}`, source: "ato", kind: "directMessage",
    sender: "Teste áudio", channel: null, conversationId: "c1",
    body: fixture.audio.transcript ?? "🎤 Voice message",
    timestampMs: Date.now() - 40_000, link: "https://example.invalid/", read: false,
    audio: fixture.audio,
  };
}

/** `island.bodyOverflow` for a voice message. */
function overflow(body: string, full: boolean): number {
  const words = full
    ? Math.max(MESSAGE_BODY_TWO_LINES, measureBodyHeight(body, messageBodyWidth(false) - VOICE_SCROLLER_ROOM))
    : MESSAGE_BODY_TWO_LINES;
  return VOICE_PLAYER_HEIGHT + VOICE_GAP + words - MESSAGE_BODY_TWO_LINES;
}

const built: { sync(): void; tick?(n: number): void }[] = [];

function column(id: string, full: boolean) {
  const host = document.getElementById(id)!;
  for (const fixture of FIXTURES) {
    State.settings = { ...State.settings, messageFullBody: full };
    const view = buildMessage(actions);
    const msg = message(fixture);
    State.messages = [msg];
    State.activeMessageId = msg.id;

    const { h } = islandSize("expanded", "message", 0, "automatic", 0, false, false,
                             overflow(msg.body, full));
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
    // Each card keeps its own message: a later sync would draw the last one.
    const keep = msg;
    const keepFull = full;
    built.push({
      sync: () => {
        State.messages = [keep];
        State.activeMessageId = keep.id;
        State.settings = { ...State.settings, messageFullBody: keepFull };
        view.sync();
      },
      tick: (n) => view.tick?.(n),
    });
  }
}

column("clamped", false);
column("full", true);

// The player notifies State on every change; repaint every card when it does.
const notify = State.notify.bind(State);
State.notify = () => {
  notify();
  for (const view of built) view.sync();
};
VoicePlayer.seek("s-long", 0.66);
(window as unknown as { step: () => void }).step = () => {
  for (const view of built) view.tick?.(performance.now());
};
