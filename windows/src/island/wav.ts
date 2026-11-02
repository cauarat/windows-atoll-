/**
 * Turning what the webview recorded into something the other person can play.
 *
 * Pure over its arguments apart from the audio engine it is handed, the way
 * `core/attachments.ts` is, so the header can be checked without a microphone.
 *
 * This exists because of one fact about the other end: the panel decides what
 * a file *is* from the name it arrives under, and every MIME table resolves
 * `.webm` to `video/webm`. WebView2's MediaRecorder usually offers nothing but
 * WebM/Opus, so a voice note recorded and sent as-is reaches the customer as a
 * video — and renaming it would be worse, a file labelled `audio/mp4` that is
 * really a WebM container, which players refuse outright. Re-encoding is the
 * honest way out.
 */

/** 16 kHz mono — the smallest shape every phone plays, and what a voice note is. */
export const VOICE_RATE = 16_000;

/**
 * WebM/Opus in, 16 kHz mono 16-bit WAV out.
 *
 * Two contexts, not one: `decodeAudioData` decodes at its own context's rate
 * and cannot be told otherwise, and an `OfflineAudioContext` needs a frame
 * count that is not known until the decode is done.
 */
export async function toVoiceWav(blob: Blob): Promise<Uint8Array> {
  const ctx = new AudioContext();
  let decoded: AudioBuffer;
  try {
    decoded = await ctx.decodeAudioData(await blob.arrayBuffer());
  } finally {
    await ctx.close();
  }

  const frames = Math.max(1, Math.ceil(decoded.duration * VOICE_RATE));
  // One output channel is what down-mixes a stereo capture to mono; the graph
  // does it on the way to the destination, so nothing here has to average.
  const offline = new OfflineAudioContext(1, frames, VOICE_RATE);
  const source = offline.createBufferSource();
  source.buffer = decoded;
  source.connect(offline.destination);
  source.start();
  const rendered = await offline.startRendering();
  return wavFromMono(rendered.getChannelData(0), VOICE_RATE);
}

/**
 * RIFF/WAVE, PCM, one channel, 16 bits: 44 bytes of header, then the samples.
 *
 * Every multi-byte field is little-endian — the `true` on each write. Miss it
 * on one line and the file opens as noise rather than as a wrong number.
 */
export function wavFromMono(samples: Float32Array, rate: number): Uint8Array {
  const out = new Uint8Array(44 + samples.length * 2);
  const view = new DataView(out.buffer);
  const ascii = (at: number, text: string) => {
    for (let i = 0; i < text.length; i++) view.setUint8(at + i, text.charCodeAt(i));
  };

  ascii(0, "RIFF");
  view.setUint32(4, 36 + samples.length * 2, true);
  ascii(8, "WAVEfmt ");
  view.setUint32(16, 16, true);          // fmt chunk size
  view.setUint16(20, 1, true);           // PCM
  view.setUint16(22, 1, true);           // mono
  view.setUint32(24, rate, true);
  view.setUint32(28, rate * 2, true);    // byte rate: rate × channels × 2
  view.setUint16(32, 2, true);           // block align
  view.setUint16(34, 16, true);          // bits per sample
  ascii(36, "data");
  view.setUint32(40, samples.length * 2, true);

  for (let i = 0; i < samples.length; i++) {
    // Clamped before scaling. A sample over 1.0 wraps to full-negative
    // otherwise, which is a click in the recording rather than a quiet clip.
    const s = Math.max(-1, Math.min(1, samples[i] ?? 0));
    view.setInt16(44 + i * 2, s < 0 ? s * 0x8000 : s * 0x7fff, true);
  }
  return out;
}
