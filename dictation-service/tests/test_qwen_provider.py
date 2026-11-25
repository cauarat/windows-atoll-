import sys
import types
import unittest
from unittest import mock

import numpy as np

from notchy_dictation.audio import SAMPLE_RATE
from notchy_dictation.languages import PT_BR
from notchy_dictation.providers.base import ProviderUnavailable
from notchy_dictation.providers.qwen3_asr import (Qwen3AsrProvider, RuntimeProbe, Runtime, choose_runtime)

from fakes import FakeQwenModel, settings

CUDA_VLLM = RuntimeProbe(vllm_installed=True, cuda=True, mps=False)
MAC = RuntimeProbe(vllm_installed=False, cuda=False, mps=True)
CPU = RuntimeProbe(vllm_installed=False, cuda=False, mps=False)
CUDA_ONLY = RuntimeProbe(vllm_installed=False, cuda=True, mps=False)


class ChooseRuntimeTests(unittest.TestCase):
    def test_auto(self):
        self.assertEqual(choose_runtime(settings(), CUDA_VLLM), Runtime("vllm", "cuda", "auto"))
        self.assertEqual(choose_runtime(settings(), MAC), Runtime("transformers", "mps", "float16"))
        self.assertEqual(choose_runtime(settings(), CPU), Runtime("transformers", "cpu", "float32"))
        self.assertEqual(choose_runtime(settings(), CUDA_ONLY), Runtime("transformers", "cuda:0", "bfloat16"))

    def test_vllm_without_cuda_says_why(self):
        with self.assertRaises(ProviderUnavailable) as ctx:
            choose_runtime(settings(backend="vllm"), RuntimeProbe(vllm_installed=True, cuda=False, mps=True))
        self.assertIn("NVIDIA", str(ctx.exception))
        with self.assertRaises(ProviderUnavailable) as ctx:
            choose_runtime(settings(backend="vllm"), MAC)
        self.assertIn("não está instalado", str(ctx.exception))

    def test_explicit_device_and_dtype(self):
        self.assertEqual(choose_runtime(settings(backend="transformers", device="cpu", dtype="bfloat16"), MAC),
                         Runtime("transformers", "cpu", "bfloat16"))
        with self.assertRaises(ProviderUnavailable):
            choose_runtime(settings(device="cuda:1"), MAC)
        with self.assertRaises(ProviderUnavailable):
            choose_runtime(settings(device="mps"), CPU)


def provider(probe, model):
    return Qwen3AsrProvider(settings(), probe=lambda: probe, loader=lambda s, rt: model)


class StreamingTests(unittest.TestCase):
    def setUp(self):
        self.model = FakeQwenModel()
        self.p = provider(CUDA_VLLM, self.model)
        self.p.load()

    def test_info(self):
        info = self.p.info()
        self.assertEqual((info.provider, info.backend, info.streaming, info.device), ("qwen3-asr", "vllm", True, "cuda"))
        self.assertTrue(self.p.loads_on_main_thread)

    def test_official_parameters_and_language(self):
        self.p.open_stream(PT_BR)
        self.assertEqual(self.model.calls, ["init:Portuguese:1.0"])

    def test_partials_are_whole_and_never_repeated(self):
        stream = self.p.open_stream(PT_BR)
        frame = np.zeros(SAMPLE_RATE // 10, dtype=np.float32)  # 100 ms
        partials = [t for t in (stream.feed(frame) for _ in range(25)) if t is not None]
        self.assertEqual(partials, ["olá", "olá este"])  # one per full second, the whole text each time
        # 0.5 s of tail: finish flushes it, the last word is not lost
        self.assertEqual(stream.finish(), "olá este é")

    def test_whole_file_uses_the_long_budget_then_restores(self):
        class SamplingParams:
            def __init__(self, **kw):
                self.kw = kw

        fake_vllm = types.ModuleType("vllm")
        fake_vllm.SamplingParams = SamplingParams
        with mock.patch.dict(sys.modules, {"vllm": fake_vllm}):
            text = self.p.transcribe(np.zeros(SAMPLE_RATE, dtype=np.float32), PT_BR)
        self.assertEqual(text, "ouvi 16000 amostras")
        self.assertEqual(self.model.transcribe_budgets[0].kw, {"temperature": 0.0, "max_tokens": 1024})
        self.assertEqual(self.model.sampling_params, "streaming")  # put back for the next dictation


class OfflineTests(unittest.TestCase):
    def setUp(self):
        self.model = FakeQwenModel()
        self.p = provider(MAC, self.model)
        self.p.load()

    def test_info(self):
        info = self.p.info()
        self.assertEqual((info.backend, info.streaming, info.device), ("transformers", False, "mps"))
        self.assertFalse(self.p.loads_on_main_thread)

    def test_buffers_everything_then_transcribes_once(self):
        stream = self.p.open_stream(PT_BR)
        for _ in range(30):
            self.assertIsNone(stream.feed(np.zeros(1600, dtype=np.float32)))
        self.assertEqual(stream.finish(), "ouvi 48000 amostras")
        self.assertEqual(self.model.calls, ["transcribe:Portuguese:48000:16000"])

    def test_too_short_is_empty_without_a_model_call(self):
        stream = self.p.open_stream(PT_BR)
        stream.feed(np.zeros(800, dtype=np.float32))
        self.assertEqual(stream.finish(), "")
        self.assertEqual(self.model.calls, [])

    def test_whole_file(self):
        self.assertEqual(self.p.transcribe(np.zeros(32000, dtype=np.float32), PT_BR), "ouvi 32000 amostras")

    def test_not_loaded(self):
        fresh = provider(MAC, FakeQwenModel())
        with self.assertRaises(ProviderUnavailable):
            fresh.open_stream(PT_BR)


if __name__ == "__main__":
    unittest.main()
