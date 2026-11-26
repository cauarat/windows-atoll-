"""What a speech provider has to offer the service.

A provider loads its model once and opens one stream per dictation. Every
method here is blocking and is called on the provider's own executor, never on
the event loop: a model call can take seconds, and the server must keep
answering /health and other sockets meanwhile.
"""

from __future__ import annotations

import threading
from abc import ABC, abstractmethod
from concurrent.futures import Executor, ThreadPoolExecutor
from dataclasses import asdict, dataclass

import numpy as np

from ..languages import Language


class ProviderUnavailable(RuntimeError):
    """The provider cannot run here: a package, a GPU or a server is missing.
    The message says what to do, in Portuguese, and is shown to the person."""


@dataclass(frozen=True)
class ProviderInfo:
    provider: str
    model: str
    backend: str
    streaming: bool
    device: str

    def as_dict(self) -> dict[str, object]:
        return asdict(self)


class TranscriptionStream(ABC):
    """One dictation, from the first sample to the final text."""

    @abstractmethod
    def feed(self, samples: np.ndarray) -> str | None:
        """Take more audio (16 kHz mono float32). Return the whole hypothesis
        when it changed, else None. Offline streams only buffer."""

    @abstractmethod
    def finish(self) -> str:
        """No more audio is coming: process what is left and return the text."""

    def close(self) -> None:
        """Free whatever the stream holds. Called once, after finish or on cancel."""


class Provider(ABC):
    name: str = "provider"

    def __init__(self) -> None:
        self._executor: Executor | None = None
        self._executor_lock = threading.Lock()

    @property
    def executor(self) -> Executor:
        """Where this provider's blocking calls run. One thread by default, so a
        local model is never entered twice at once; a provider whose work is
        remote can widen it."""
        with self._executor_lock:
            if self._executor is None:
                self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix=self.name)
            return self._executor

    @abstractmethod
    def load(self) -> None:
        """Get ready to transcribe: load weights or reach the remote server.
        Raises ProviderUnavailable with a readable message when it cannot."""

    @abstractmethod
    def info(self) -> ProviderInfo:
        ...

    @abstractmethod
    def open_stream(self, language: Language) -> TranscriptionStream:
        ...

    @property
    def wants_warm_up(self) -> bool:
        """Whether `warm_up` does anything: a local model that goes cold when idle."""
        return False

    def warm_up(self) -> None:
        """Run the model once on nothing, so the next real call is fast."""

    def transcribe(self, samples: np.ndarray, language: Language) -> str:
        """A whole recording at once. The default runs it through a stream."""
        stream = self.open_stream(language)
        try:
            stream.feed(samples)
            return stream.finish()
        finally:
            stream.close()

    def shutdown(self) -> None:
        if self._executor is not None:
            self._executor.shutdown(wait=False, cancel_futures=True)
