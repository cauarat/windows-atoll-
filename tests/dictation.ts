// The Windows and Linux front end's corner of tests/fixtures/dictation.json:
// the protocol constants, the transcript the card shows as messages arrive,
// the address typed in Settings, and the microphone arithmetic.
// tests/DictationTests.swift holds the Mac to the same file, and
// dictation-service/tests the service.
//
// Run by scripts/test-dictation.sh.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  CANCEL_MESSAGE, DICTATION, ERROR_CODES, FRAME_BYTES, Framer, Resampler, STOP_MESSAGE,
  applyMessage, decodeHealth, decodeServerMessage, emptyTranscript, healthURL, level, modelName,
  socketURL, startMessage, toPCM16,
} from "../windows/src/core/dictation.ts";

let failures = 0;
const check = (ok: boolean, what: string, detail = "") => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}${ok || !detail ? "" : ` — ${detail}`}`);
  if (!ok) failures++;
};
const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);
const sorted = (o: Record<string, unknown>) =>
  Object.fromEntries(Object.entries(o).sort(([a], [b]) => a.localeCompare(b)));

interface Session {
  name: string;
  messages: Record<string, unknown>[];
  shown: string[];
  phase: string;
  errorCode?: string;
  streaming: boolean;
}
const fixture = JSON.parse(readFileSync(join(import.meta.dirname, "fixtures/dictation.json"), "utf8")) as {
  protocol: Record<string, unknown>;
  addresses: [string, string | null][];
  sessions: Session[];
};
const p = fixture.protocol;

console.log("\nDictation — the protocol, as the service speaks it");
check(p.version === DICTATION.version, "version");
check(p.path === DICTATION.path, "path");
check(p.healthPath === DICTATION.healthPath, "health path");
check(p.defaultServiceURL === DICTATION.defaultServiceURL, "default address");
check(p.sampleRate === DICTATION.sampleRate, "16 kHz");
check(p.encoding === DICTATION.encoding, "PCM16");
check(p.frameMs === DICTATION.frameMs, "100 ms frames");
check(p.tailMs === DICTATION.tailMs, "250 ms tail");
check(p.language === DICTATION.language, "pt-BR");
check(p.languageLabel === DICTATION.languageLabel, "its label");
check(same(p.errorCodes, ERROR_CODES), "error codes, in order");
check(same(sorted(JSON.parse(startMessage())), sorted(p.start as Record<string, unknown>)), "start message", startMessage());
check(same(JSON.parse(STOP_MESSAGE), p.stop), "stop message");
check(same(JSON.parse(CANCEL_MESSAGE), p.cancel), "cancel message");

console.log("\nDictation — what the card shows as the messages arrive");
for (const s of fixture.sessions) {
  let t = emptyTranscript();
  const shown: string[] = [];
  let decoded = true;
  for (const raw of s.messages) {
    const m = decodeServerMessage(JSON.stringify(raw));
    if (!m) { decoded = false; continue; }
    t = applyMessage(t, m);
    shown.push(t.text);
  }
  check(decoded, `${s.name}: every message decodes`);
  check(same(shown, s.shown), `${s.name}: text after each message`, JSON.stringify(shown));
  check(t.phase === s.phase, `${s.name}: ends ${s.phase}`, t.phase);
  check((t.service?.streaming ?? false) === s.streaming, `${s.name}: streaming ${s.streaming}`);
  if (s.errorCode) check(t.errorCode === s.errorCode, `${s.name}: error ${s.errorCode}`, String(t.errorCode));
}
{
  let t = applyMessage(emptyTranscript(), { type: "final", text: "Pronto.", audioMs: 1000, processingMs: 10, truncated: false });
  t = applyMessage(t, { type: "partial", text: "Pron", seq: 9 });
  check(t.text === "Pronto.", "a late partial does not undo the final");
  const ready = decodeServerMessage(fixture.sessions[0].messages[0]);
  check(ready?.type === "ready" && modelName(ready.info) === "Qwen3-ASR-1.7B", "the model's short name");
  const health = decodeHealth(JSON.stringify({
    status: "ready", ready: true, protocol: 1, provider: "qwen3-asr", model: "Qwen/Qwen3-ASR-1.7B",
    backend: "transformers", streaming: false, device: "mps", language: "pt-BR",
    language_label: "Português (Brasil)", error: null,
  }));
  check(health?.ready === true && health.info.backend === "transformers", "a /health answer");
  check(decodeHealth("<html>") === null, "anything else is not the service");
}

console.log("\nDictation — the address typed in Settings");
check(fixture.addresses.length > 0, "the fixture lists addresses");
for (const [typed, want] of fixture.addresses) {
  const got = socketURL(typed);
  check(got === want, `“${typed}” → ${want ?? "nothing"}`, String(got));
}
check(healthURL("http://127.0.0.1:8765") === "http://127.0.0.1:8765/health", "health");

console.log("\nDictation — 100 ms frames, nothing dropped");
check(FRAME_BYTES === 3200, "a frame is 3200 bytes");
{
  const framer = new Framer();
  const frames = [...framer.push(new Uint8Array(1000)), ...framer.push(new Uint8Array(6000))];
  const tail = framer.flush();
  check(same(frames.map((f) => f.length), [3200, 3200]), "whole frames come out in order");
  check(tail?.length === 600, "the tail is kept, not dropped", String(tail?.length));
  check(framer.flush() === null, "and only once");
}
{
  const pcm = toPCM16(Float32Array.from([0, 1, -1, 0.5]));
  const view = new DataView(pcm.buffer);
  check(same([0, 1, 2, 3].map((i) => view.getInt16(i * 2, true)), [0, 32767, -32768, 16384]), "PCM16, little-endian");
  check(level(new Float32Array(160)) === 0, "silence is level 0");
  check(Math.abs(level(new Float32Array(160).fill(1)) - 1) < 1e-6, "full scale is level 1");
  check(level(new Float32Array(160).fill(100 / 32768)) === 0, "-50 dBFS and below is 0");
}
{
  // 48 kHz → 16 kHz, in uneven buffers: the length comes out a third, and a
  // slow ramp stays a ramp across the seams.
  const r = new Resampler(48000);
  const ramp = Float32Array.from({ length: 4800 }, (_, i) => i / 4800);
  const out = [
    ...r.process(ramp.subarray(0, 1000)), ...r.process(ramp.subarray(1000, 1001)), ...r.process(ramp.subarray(1001)),
  ];
  check(Math.abs(out.length - 1600) <= 1, "a third as many samples", String(out.length));
  const steady = out.every((x, i) => i === 0 || Math.abs(x - out[i - 1] - 3 / 4800) < 1e-6);
  check(steady, "no seam between buffers");
  check(new Resampler(16000).process(ramp) === ramp, "16 kHz goes through untouched");
}

if (failures > 0) {
  console.log(`\n${failures} failed`);
  process.exit(1);
}
console.log("\nAll dictation checks passed");
