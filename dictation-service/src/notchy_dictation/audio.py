"""PCM helpers. The wire format is fixed: signed 16-bit little-endian, mono,
16 kHz. Everything the models see is float32 in [-1, 1] at that same rate."""

from __future__ import annotations

import io
import wave

import numpy as np

SAMPLE_RATE = 16_000
BYTES_PER_SAMPLE = 2


class AudioFormatError(ValueError):
    pass


def pcm16le_to_float32(data: bytes) -> np.ndarray:
    if len(data) % BYTES_PER_SAMPLE:
        raise AudioFormatError("PCM16 precisa de um número par de bytes.")
    return np.frombuffer(data, dtype="<i2").astype(np.float32) / 32768.0


def float32_to_pcm16le(samples: np.ndarray) -> bytes:
    clipped = np.clip(np.asarray(samples, dtype=np.float32), -1.0, 1.0)
    return (clipped * 32767.0).round().astype("<i2").tobytes()


def samples_to_ms(count: int) -> int:
    return int(round(count * 1000 / SAMPLE_RATE))


def read_wav(data: bytes) -> np.ndarray:
    """A WAV file as 16 kHz mono float32. Integer PCM only (8/16/24/32-bit),
    which is what `say`, `afconvert -d LEI16` and most recorders write."""
    try:
        with wave.open(io.BytesIO(data), "rb") as w:
            channels = w.getnchannels()
            width = w.getsampwidth()
            rate = w.getframerate()
            frames = w.readframes(w.getnframes())
    except (wave.Error, EOFError) as exc:
        raise AudioFormatError(
            "O arquivo não é um WAV PCM. Converta antes, por exemplo: "
            "afconvert -f WAVE -d LEI16@16000 -c 1 entrada.m4a saida.wav"
        ) from exc
    samples = _decode_pcm(frames, width)
    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)
    if rate != SAMPLE_RATE:
        samples = resample(samples, rate, SAMPLE_RATE)
    return samples.astype(np.float32)


def _decode_pcm(frames: bytes, width: int) -> np.ndarray:
    if width == 1:  # unsigned 8-bit
        return (np.frombuffer(frames, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
    if width == 2:
        return np.frombuffer(frames, dtype="<i2").astype(np.float32) / 32768.0
    if width == 3:
        raw = np.frombuffer(frames, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        value = raw[:, 0] | (raw[:, 1] << 8) | (raw[:, 2] << 16)
        value = np.where(value & 0x800000, value - (1 << 24), value)
        return value.astype(np.float32) / float(1 << 23)
    if width == 4:
        return np.frombuffer(frames, dtype="<i4").astype(np.float32) / float(1 << 31)
    raise AudioFormatError(f"WAV com {width * 8} bits por amostra não é suportado.")


def resample(samples: np.ndarray, rate_from: int, rate_to: int) -> np.ndarray:
    """Band-limited resampling in the frequency domain. Good enough for speech
    and needs nothing beyond numpy; only POST /v1/transcribe uses it, because
    the apps already send 16 kHz."""
    if rate_from == rate_to or samples.size == 0:
        return samples
    n_out = int(round(samples.size * rate_to / rate_from))
    if n_out <= 0:
        return np.zeros(0, dtype=np.float32)
    spectrum = np.fft.rfft(samples)
    keep = n_out // 2 + 1
    if keep <= spectrum.size:
        spectrum = spectrum[:keep]
    else:
        spectrum = np.concatenate([spectrum, np.zeros(keep - spectrum.size, dtype=spectrum.dtype)])
    out = np.fft.irfft(spectrum, n=n_out) * (n_out / samples.size)
    return out.astype(np.float32)


# Below this the loudest 30 ms of a recording is room noise, not a voice: about
# -48 dBFS. Speech into a laptop microphone sits well above -40.
SILENCE_RMS = 0.004
_WINDOW = SAMPLE_RATE * 30 // 1000


def is_silent(samples: np.ndarray) -> bool:
    """Whether a recording holds no speech at all, judged by its loudest 30 ms.

    Speech models hallucinate on silence — Qwen3-ASR turns half a second of
    nothing into "Então" — so silence never reaches them."""
    if samples.size == 0:
        return True
    usable = samples[: samples.size - samples.size % _WINDOW] if samples.size >= _WINDOW else samples
    windows = usable.reshape(-1, min(_WINDOW, usable.size)) if usable.size else usable.reshape(1, -1)
    loudest = float(np.sqrt(np.mean(np.square(windows, dtype=np.float64), axis=1)).max())
    return loudest < SILENCE_RMS
