"""Test doubles for the speech models. They follow qwen-asr's own contract
(Qwen3ASRModel.init_streaming_state / streaming_transcribe /
finish_streaming_transcribe / transcribe) closely enough to drive the real
provider and session code, without a model, a GPU or a download."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np

from notchy_dictation.audio import SAMPLE_RATE
from notchy_dictation.config import Settings
from notchy_dictation.languages import Language
from notchy_dictation.providers.base import Provider, ProviderInfo, TranscriptionStream

FIXTURE = Path(__file__).resolve().parents[2] / "tests" / "fixtures" / "dictation.json"

WORDS = ["olá", "este", "é", "um", "teste", "do", "ditado", "em", "português", "do", "brasil"]


def fixture() -> dict[str, Any]:
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


@dataclass
class FakeState:
    """The fields of qwen_asr's ASRStreamingState the provider reads."""

    chunk_size_samples: int
    language: str
    chunk_id: int = 0
    buffer: np.ndarray = field(default_factory=lambda: np.zeros(0, dtype=np.float32))
    heard: int = 0
    text: str = ""


class FakeQwenModel:
    """One word per full chunk, the whole text every time (as the real model
    re-decodes all audio), and one more word for the tail on finish."""

    def __init__(self) -> None:
        self.calls: list[str] = []
        self.sampling_params = "streaming"
        self.transcribe_budgets: list[Any] = []

    def init_streaming_state(self, context: str, language: str, unfixed_chunk_num: int,
                             unfixed_token_num: int, chunk_size_sec: float) -> FakeState:
        self.calls.append(f"init:{language}:{chunk_size_sec}")
        return FakeState(chunk_size_samples=int(round(chunk_size_sec * SAMPLE_RATE)), language=language)

    def streaming_transcribe(self, pcm: np.ndarray, state: FakeState) -> FakeState:
        state.buffer = np.concatenate([state.buffer, np.asarray(pcm, dtype=np.float32)])
        while state.buffer.size >= state.chunk_size_samples:
            state.buffer = state.buffer[state.chunk_size_samples:]
            state.heard += state.chunk_size_samples
            state.chunk_id += 1
            state.text = " ".join(WORDS[: state.chunk_id])
        return state

    def finish_streaming_transcribe(self, state: FakeState) -> FakeState:
        if state.buffer.size:
            state.heard += state.buffer.size
            state.buffer = np.zeros(0, dtype=np.float32)
            state.chunk_id += 1
            state.text = " ".join(WORDS[: state.chunk_id])
        return state

    def transcribe(self, audio: Any, context: str = "", language: str | None = None) -> list[Any]:
        samples, rate = audio
        self.transcribe_budgets.append(self.sampling_params)
        self.calls.append(f"transcribe:{language}:{len(samples)}:{rate}")

        @dataclass
        class Result:
            text: str
            language: str

        return [Result(text=f"ouvi {len(samples)} amostras", language=language or "")]


class FakeProvider(Provider):
    """A provider whose streams are scripted, for the session and server tests."""

    name = "fake"

    def __init__(self, *, streaming: bool = True, chunk_samples: int = 1600,
                 fail_on_feed: int | None = None, fail_on_load: str | None = None) -> None:
        super().__init__()
        self.streaming = streaming
        self.chunk_samples = chunk_samples
        self.fail_on_feed = fail_on_feed
        self.fail_on_load = fail_on_load
        self.loaded = False
        self.streams: list["FakeStream"] = []
        self.warm_ups = 0
        self.warms = False

    @property
    def wants_warm_up(self) -> bool:
        return self.warms

    def warm_up(self) -> None:
        self.warm_ups += 1

    def load(self) -> None:
        if self.fail_on_load:
            from notchy_dictation.providers.base import ProviderUnavailable

            raise ProviderUnavailable(self.fail_on_load)
        self.loaded = True

    def info(self) -> ProviderInfo:
        return ProviderInfo(provider="fake", model="fake/model",
                            backend="vllm" if self.streaming else "transformers",
                            streaming=self.streaming, device="cpu")

    def open_stream(self, language: Language) -> TranscriptionStream:
        stream = FakeStream(self)
        self.streams.append(stream)
        return stream


class FakeStream(TranscriptionStream):
    def __init__(self, provider: FakeProvider) -> None:
        self.provider = provider
        self.samples = 0
        self.feeds = 0
        self.words = 0
        self.closed = False
        self.finished = False

    def feed(self, samples: np.ndarray) -> str | None:
        self.feeds += 1
        if self.provider.fail_on_feed is not None and self.feeds >= self.provider.fail_on_feed:
            raise RuntimeError("boom")
        self.samples += samples.size
        if not self.provider.streaming:
            return None
        words = self.samples // self.provider.chunk_samples
        if words == self.words:
            return None
        self.words = words
        return " ".join(WORDS[: self.words])

    def finish(self) -> str:
        self.finished = True
        if self.provider.streaming:
            total = -(-self.samples // self.provider.chunk_samples)  # tail counts as a word
            return " ".join(WORDS[:total]) + "."
        return f"ouvi {self.samples} amostras"

    def close(self) -> None:
        self.closed = True


def settings(**changes: Any) -> Settings:
    return Settings().with_overrides(**changes)


def pcm_bytes(seconds: float, value: float = 0.1) -> bytes:
    count = int(round(seconds * SAMPLE_RATE))
    return (np.full(count, value, dtype=np.float32) * 32767).astype("<i2").tobytes()
