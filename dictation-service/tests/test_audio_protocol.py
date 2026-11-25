import io
import unittest
import wave

import numpy as np

from notchy_dictation import PROTOCOL_VERSION, languages, protocol
from notchy_dictation.audio import (AudioFormatError, float32_to_pcm16le, pcm16le_to_float32, read_wav,
                                    resample, samples_to_ms)

from fakes import fixture


def wav_bytes(samples: np.ndarray, rate: int, channels: int = 1, width: int = 2) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(width)
        w.setframerate(rate)
        data = np.repeat(samples, channels) if channels > 1 else samples
        w.writeframes(float32_to_pcm16le(data))
    return buf.getvalue()


class AudioTests(unittest.TestCase):
    def test_pcm_round_trip(self):
        x = np.array([0.0, 0.5, -0.5, 0.999, -1.0], dtype=np.float32)
        y = pcm16le_to_float32(float32_to_pcm16le(x))
        self.assertTrue(np.allclose(x, y, atol=1e-4))

    def test_odd_pcm_is_refused(self):
        with self.assertRaises(AudioFormatError):
            pcm16le_to_float32(b"\x00\x01\x02")

    def test_wav_16k_mono(self):
        x = np.sin(np.linspace(0, 100, 16000)).astype(np.float32) * 0.5
        y = read_wav(wav_bytes(x, 16000))
        self.assertEqual(y.size, 16000)
        self.assertTrue(np.allclose(x, y, atol=1e-3))

    def test_wav_48k_stereo_is_resampled_and_mixed(self):
        t = np.arange(48000) / 48000
        x = (0.3 * np.sin(2 * np.pi * 440 * t)).astype(np.float32)
        y = read_wav(wav_bytes(x, 48000, channels=2))
        self.assertEqual(y.size, 16000)
        # the 440 Hz tone survives at the same level
        self.assertAlmostEqual(float(np.sqrt(np.mean(y ** 2))), 0.3 / np.sqrt(2), delta=0.01)

    def test_not_a_wav(self):
        with self.assertRaises(AudioFormatError):
            read_wav(b"ID3 not a wav")

    def test_resample_identity_and_length(self):
        x = np.ones(1000, dtype=np.float32)
        self.assertIs(resample(x, 16000, 16000), x)
        self.assertEqual(resample(x, 44100, 16000).size, round(1000 * 16000 / 44100))

    def test_samples_to_ms(self):
        self.assertEqual(samples_to_ms(16000), 1000)
        self.assertEqual(samples_to_ms(1600), 100)


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.fx = fixture()["protocol"]

    def test_matches_the_shared_fixture(self):
        self.assertEqual(self.fx["version"], PROTOCOL_VERSION)
        self.assertEqual(list(protocol.ERROR_CODES), self.fx["errorCodes"])
        self.assertEqual(self.fx["sampleRate"], 16000)
        self.assertEqual(self.fx["encoding"], protocol.ENCODING)
        self.assertEqual(self.fx["language"], languages.PT_BR.code)
        self.assertEqual(self.fx["languageLabel"], languages.PT_BR.label)

    def test_fixture_start_message_is_accepted(self):
        msg = protocol.parse_client_message(protocol.dumps(self.fx["start"]))
        self.assertEqual(msg["type"], "start")
        self.assertEqual(protocol.parse_client_message(protocol.dumps(self.fx["stop"]))["type"], "stop")
        self.assertEqual(protocol.parse_client_message(protocol.dumps(self.fx["cancel"]))["type"], "cancel")

    def test_server_messages_have_the_fixture_shapes(self):
        sessions = fixture()["sessions"]
        ready = sessions[0]["messages"][0]
        built = protocol.ready("a1", {"provider": "qwen3-asr", "model": "Qwen/Qwen3-ASR-1.7B", "backend": "vllm",
                                      "streaming": True, "device": "cuda"}, "pt-BR", "Português (Brasil)")
        self.assertEqual(built, ready)
        self.assertEqual(protocol.partial("Olá", 1), sessions[0]["messages"][1])
        self.assertEqual(protocol.final("Olá, este é um teste.", 2300, 140, False), sessions[0]["messages"][-1])
        self.assertEqual(set(protocol.error("model_loading", "x")), {"type", "code", "message"})

    def test_bad_messages(self):
        for text, code in (("not json", "bad_request"), ('{"type": "dance"}', "bad_request"),
                           ('{"type": "start", "sample_rate": 44100}', "unsupported_audio"),
                           ('{"type": "start", "channels": 2}', "unsupported_audio")):
            with self.assertRaises(protocol.ProtocolError) as ctx:
                protocol.parse_client_message(text)
            self.assertEqual(ctx.exception.code, code)

    def test_languages(self):
        for code in ("pt-BR", "pt_BR", "pt", "PT-br", None):
            self.assertIs(languages.resolve(code), languages.PT_BR)
        self.assertEqual(languages.PT_BR.qwen, "Portuguese")
        with self.assertRaises(languages.UnsupportedLanguage):
            languages.resolve("de-DE")


if __name__ == "__main__":
    unittest.main()
