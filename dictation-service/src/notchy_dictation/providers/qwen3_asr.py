"""Qwen3-ASR (Qwen/Qwen3-ASR-1.7B by default), through the official `qwen-asr`
package, with its two backends:

- vllm: the official streaming path (`init_streaming_state`,
  `streaming_transcribe`, `finish_streaming_transcribe`). Partials while the
  person speaks. Needs vLLM, so an NVIDIA GPU with CUDA on Linux (or WSL2).
- transformers: offline. The audio is kept until the person stops and then
  transcribed at once, so there is only a final. Runs on CUDA, on Apple
  silicon (MPS) or on the CPU.

`auto` takes vllm when it is installed and a CUDA GPU is present, transformers
otherwise. Nothing here pretends: when the asked-for backend cannot run, load()
raises ProviderUnavailable saying why and what to install.
"""

from __future__ import annotations

import importlib.util
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Any, Callable, Iterator

import numpy as np

from ..audio import SAMPLE_RATE, is_silent
from ..config import Settings
from ..languages import Language
from .base import Provider, ProviderInfo, ProviderUnavailable, TranscriptionStream

# Below this there is nothing to transcribe (100 ms); qwen-asr itself pads
# anything shorter than half a second.
_MIN_SAMPLES = SAMPLE_RATE // 10


@dataclass(frozen=True)
class RuntimeProbe:
    vllm_installed: bool
    cuda: bool
    mps: bool


@dataclass(frozen=True)
class Runtime:
    backend: str  # "vllm" | "transformers"
    device: str  # "cuda", "cuda:0", "mps", "cpu"
    dtype: str  # torch dtype name, "auto" for vllm


def probe_runtime() -> RuntimeProbe:
    try:
        import torch
    except ImportError as exc:
        raise ProviderUnavailable(
            "O PyTorch não está instalado neste ambiente. Instale o Qwen3-ASR com "
            "`pip install -e \".[qwen]\"` (ou `.[qwen-vllm]` numa máquina Linux com GPU NVIDIA)."
        ) from exc
    mps_backend = getattr(torch.backends, "mps", None)
    return RuntimeProbe(
        vllm_installed=importlib.util.find_spec("vllm") is not None,
        cuda=bool(torch.cuda.is_available()),
        mps=bool(mps_backend is not None and mps_backend.is_available()),
    )


def choose_runtime(settings: Settings, probe: RuntimeProbe) -> Runtime:
    backend = settings.backend
    if backend == "auto":
        backend = "vllm" if (probe.vllm_installed and probe.cuda) else "transformers"

    if backend == "vllm":
        if not probe.vllm_installed:
            raise ProviderUnavailable(
                "DICTATION_BACKEND=vllm, mas o vLLM não está instalado. Instale com "
                "`pip install -e \".[qwen-vllm]\"` numa máquina Linux com GPU NVIDIA, ou use "
                "DICTATION_BACKEND=transformers (sem texto parcial)."
            )
        if not probe.cuda:
            raise ProviderUnavailable(
                "O streaming do Qwen3-ASR usa o vLLM, que precisa de uma GPU NVIDIA com CUDA "
                "(Linux, ou Windows pelo WSL2). Esta máquina não tem CUDA: use "
                "DICTATION_BACKEND=transformers, que transcreve ao parar de falar."
            )
        return Runtime(backend="vllm", device="cuda", dtype="auto")

    device = settings.device
    if device == "auto":
        device = "cuda:0" if probe.cuda else ("mps" if probe.mps else "cpu")
    if device.startswith("cuda") and not probe.cuda:
        raise ProviderUnavailable(f"DICTATION_DEVICE={device}, mas não há GPU CUDA disponível.")
    if device == "mps" and not probe.mps:
        raise ProviderUnavailable("DICTATION_DEVICE=mps, mas o PyTorch não vê o MPS (Apple silicon).")

    dtype = settings.dtype
    if dtype == "auto":
        if device.startswith("cuda"):
            dtype = "bfloat16"
        elif device == "mps":
            dtype = "float16"
        else:
            dtype = "float32"
    return Runtime(backend="transformers", device=device, dtype=dtype)


def load_qwen_model(settings: Settings, runtime: Runtime) -> Any:
    try:
        from qwen_asr import Qwen3ASRModel
    except ImportError as exc:
        raise ProviderUnavailable(
            "O pacote qwen-asr não está instalado. Rode `pip install -e \".[qwen]\"` dentro de "
            "dictation-service (ou use scripts/start.sh, que faz isso)."
        ) from exc

    if runtime.backend == "vllm":
        return Qwen3ASRModel.LLM(
            model=settings.model,
            gpu_memory_utilization=settings.gpu_memory_utilization,
            max_new_tokens=settings.stream_max_new_tokens,
        )

    import torch

    return Qwen3ASRModel.from_pretrained(
        settings.model,
        dtype=getattr(torch, runtime.dtype),
        device_map=runtime.device,
        max_inference_batch_size=1,
        max_new_tokens=settings.max_new_tokens,
    )


class Qwen3AsrProvider(Provider):
    name = "qwen3-asr"

    def __init__(
        self,
        settings: Settings,
        *,
        probe: Callable[[], RuntimeProbe] = probe_runtime,
        loader: Callable[[Settings, Runtime], Any] = load_qwen_model,
    ) -> None:
        super().__init__()
        self.settings = settings
        self._probe = probe
        self._loader = loader
        self._runtime: Runtime | None = None
        self._model: Any = None

    @property
    def loads_on_main_thread(self) -> bool:
        """The official streaming demo builds the vLLM engine on the main thread,
        before serving; we do the same rather than find out what breaks
        otherwise. The Transformers backend loads on the worker while /health
        already answers "loading"."""
        try:
            return choose_runtime(self.settings, self._probe()).backend == "vllm"
        except ProviderUnavailable:
            return False

    def load(self) -> None:
        runtime = choose_runtime(self.settings, self._probe())
        self._model = self._loader(self.settings, runtime)
        self._runtime = runtime

    def info(self) -> ProviderInfo:
        rt = self._runtime
        return ProviderInfo(
            provider=self.name,
            model=self.settings.model,
            backend=rt.backend if rt else self.settings.backend,
            streaming=bool(rt and rt.backend == "vllm"),
            device=rt.device if rt else self.settings.device,
        )

    def open_stream(self, language: Language) -> TranscriptionStream:
        model = self._require_model()
        if self._runtime and self._runtime.backend == "vllm":
            state = model.init_streaming_state(
                context=self.settings.context,
                language=language.qwen,
                unfixed_chunk_num=self.settings.unfixed_chunks,
                unfixed_token_num=self.settings.unfixed_tokens,
                chunk_size_sec=self.settings.chunk_seconds,
            )
            return QwenStreamingStream(model, state)
        return QwenOfflineStream(model, language.qwen, self.settings.context)

    @property
    def wants_warm_up(self) -> bool:
        # vLLM keeps its engine hot on the GPU; the Transformers backend on
        # MPS or the CPU is the one that goes cold.
        return bool(self._runtime and self._runtime.backend == "transformers")

    def warm_up(self) -> None:
        if not self.wants_warm_up:
            return
        model = self._require_model()
        model.transcribe(audio=(np.zeros(SAMPLE_RATE // 2, dtype=np.float32), SAMPLE_RATE), language="Portuguese")

    def transcribe(self, samples: np.ndarray, language: Language) -> str:
        model = self._require_model()
        if samples.size < _MIN_SAMPLES or is_silent(samples):
            return ""
        with self._whole_file_budget(model):
            results = model.transcribe(
                audio=(samples, SAMPLE_RATE),
                context=self.settings.context,
                language=language.qwen,
            )
        return results[0].text if results else ""

    @contextmanager
    def _whole_file_budget(self, model: Any) -> Iterator[None]:
        """The vLLM model is built with the streaming budget (a few tokens per
        step). A whole file needs the long one for the duration of the call.
        Safe because every call runs on this provider's single worker thread."""
        if not (self._runtime and self._runtime.backend == "vllm"):
            yield
            return
        from vllm import SamplingParams

        saved = model.sampling_params
        model.sampling_params = SamplingParams(temperature=0.0, max_tokens=self.settings.max_new_tokens)
        try:
            yield
        finally:
            model.sampling_params = saved

    def _require_model(self) -> Any:
        if self._model is None:
            raise ProviderUnavailable("O modelo ainda não foi carregado.")
        return self._model


class QwenStreamingStream(TranscriptionStream):
    """The official streaming loop. `state.text` is always the whole
    hypothesis: the model re-reads all the audio each chunk, so passing it on
    as is never repeats a word."""

    def __init__(self, model: Any, state: Any) -> None:
        self._model = model
        self._state = state
        self._last = ""
        # Nothing but room noise so far: the model is not shown it, since it
        # makes words up out of silence.
        self._heard_voice = False

    def feed(self, samples: np.ndarray) -> str | None:
        self._heard_voice = self._heard_voice or not is_silent(samples)
        before = self._state.chunk_id
        self._model.streaming_transcribe(samples, self._state)
        if self._state.chunk_id == before or not self._heard_voice:
            return None
        text = self._state.text or ""
        if text == self._last:
            return None
        self._last = text
        return text

    def finish(self) -> str:
        if not self._heard_voice:
            return ""
        # Flushes the tail shorter than a chunk: the last words are in it.
        self._model.finish_streaming_transcribe(self._state)
        return self._state.text or ""

    def close(self) -> None:
        self._state = None


class QwenOfflineStream(TranscriptionStream):
    def __init__(self, model: Any, language: str, context: str) -> None:
        self._model = model
        self._language = language
        self._context = context
        self._chunks: list[np.ndarray] = []

    def feed(self, samples: np.ndarray) -> str | None:
        if samples.size:
            self._chunks.append(np.asarray(samples, dtype=np.float32))
        return None

    def finish(self) -> str:
        if not self._chunks:
            return ""
        audio = np.concatenate(self._chunks)
        self._chunks = []
        if audio.size < _MIN_SAMPLES or is_silent(audio):
            return ""
        results = self._model.transcribe(
            audio=(audio, SAMPLE_RATE),
            context=self._context,
            language=self._language,
        )
        return results[0].text if results else ""

    def close(self) -> None:
        self._chunks = []
