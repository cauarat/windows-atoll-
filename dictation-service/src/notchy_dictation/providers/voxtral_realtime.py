"""Voxtral Mini 4B Realtime 2602, as a comparison provider for live dictation.

The model is not loaded here. It runs in its own vLLM server, the way Mistral's
model card says to start it:

    VLLM_DISABLE_COMPILE_CACHE=1 vllm serve mistralai/Voxtral-Mini-4B-Realtime-2602 \
        --compilation_config '{"cudagraph_mode": "PIECEWISE"}'

and this provider relays each dictation to that server's Realtime WebSocket
(`/v1/realtime`), in the order of vLLM's own client
(examples/speech_to_text/realtime/openai_realtime_client.py):

    ← session.created
    → session.update {model}
    → input_audio_buffer.commit            start generating
    → input_audio_buffer.append {audio}    base64 PCM16, 16 kHz mono, repeated
    ← transcription.delta {delta}          appended here into the whole text
    → input_audio_buffer.commit {final: true}
    ← transcription.done {text}

The model card asks for one GPU with at least 16 GB; neither CPU nor Apple
silicon is supported by that path.
"""

from __future__ import annotations

import base64
import json
import time
from concurrent.futures import Executor, ThreadPoolExecutor
from typing import Any, Callable
from urllib.parse import urlparse

import numpy as np

from ..audio import float32_to_pcm16le
from ..config import Settings
from ..languages import Language
from .base import Provider, ProviderInfo, ProviderUnavailable, TranscriptionStream

SERVE_COMMAND = (
    "VLLM_DISABLE_COMPILE_CACHE=1 vllm serve mistralai/Voxtral-Mini-4B-Realtime-2602 "
    "--compilation_config '{\"cudagraph_mode\": \"PIECEWISE\"}'"
)

Connect = Callable[[str], Any]


def default_connect(url: str) -> Any:
    from websockets.sync.client import connect

    # One dictation spans several calls, so the connection outlives any `with`
    # block. Entering it by hand is what websockets 17 asks of a connection
    # used that way (else a DeprecationWarning), and returns the same
    # connection on 13 to 16. close() ends it.
    return connect(url, open_timeout=10, max_size=None).__enter__()


class VoxtralRealtimeProvider(Provider):
    name = "voxtral-realtime"

    def __init__(self, settings: Settings, *, connect: Connect = default_connect, final_timeout: float = 30.0):
        super().__init__()
        self.settings = settings
        self._connect = connect
        self._final_timeout = final_timeout
        self._pool: Executor | None = None

    @property
    def executor(self) -> Executor:
        # The work happens on the vLLM server; here a thread only waits on a
        # socket, so several dictations may wait at once.
        with self._executor_lock:
            if self._pool is None:
                self._pool = ThreadPoolExecutor(max_workers=8, thread_name_prefix=self.name)
            return self._pool

    def load(self) -> None:
        url = self.settings.voxtral_url
        try:
            ws = self._connect(url)
        except Exception as exc:  # refused, unreachable, bad URL
            raise ProviderUnavailable(
                f"Não consegui falar com o vLLM Realtime em {url}. Inicie o Voxtral numa GPU "
                f"com 16 GB ou mais: {SERVE_COMMAND}"
            ) from exc
        try:
            first = _recv_json(ws, timeout=10)
            if first.get("type") != "session.created":
                raise ProviderUnavailable(f"Resposta inesperada do vLLM Realtime: {first!r:.120}")
            ws.send(json.dumps({"type": "session.update", "model": self.settings.voxtral_model}))
            try:
                answer = _recv_json(ws, timeout=1.0)
            except TimeoutError:
                answer = {}  # no complaint about the model: it is served
            if answer.get("type") == "error":
                raise ProviderUnavailable(f"O vLLM recusou o modelo: {answer.get('error')}")
        finally:
            _close_quietly(ws)

    def info(self) -> ProviderInfo:
        host = urlparse(self.settings.voxtral_url).netloc or self.settings.voxtral_url
        return ProviderInfo(
            provider=self.name,
            model=self.settings.voxtral_model,
            backend="vllm-realtime",
            streaming=True,
            device=host,
        )

    def open_stream(self, language: Language) -> TranscriptionStream:
        # Voxtral Realtime finds the language itself; the card documents no
        # language parameter for the realtime session.
        try:
            ws = self._connect(self.settings.voxtral_url)
        except Exception as exc:
            raise ProviderUnavailable(
                f"O vLLM Realtime não responde em {self.settings.voxtral_url}."
            ) from exc
        return VoxtralStream(ws, self.settings.voxtral_model, self._final_timeout)

    def shutdown(self) -> None:
        if self._pool is not None:
            self._pool.shutdown(wait=False, cancel_futures=True)


class VoxtralStream(TranscriptionStream):
    def __init__(self, ws: Any, model: str, final_timeout: float) -> None:
        self._ws = ws
        self._final_timeout = final_timeout
        self._text = ""
        self._done: str | None = None
        try:
            first = _recv_json(ws, timeout=10)
            if first.get("type") != "session.created":
                raise ProviderUnavailable(f"Resposta inesperada do vLLM Realtime: {first!r:.120}")
            ws.send(json.dumps({"type": "session.update", "model": model}))
            ws.send(json.dumps({"type": "input_audio_buffer.commit"}))
        except Exception:
            _close_quietly(ws)
            raise

    def feed(self, samples: np.ndarray) -> str | None:
        if samples.size:
            audio = base64.b64encode(float32_to_pcm16le(samples)).decode("ascii")
            self._ws.send(json.dumps({"type": "input_audio_buffer.append", "audio": audio}))
        return self._text if self._drain(timeout=0) else None

    def finish(self) -> str:
        self._ws.send(json.dumps({"type": "input_audio_buffer.commit", "final": True}))
        deadline = time.monotonic() + self._final_timeout
        while self._done is None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ProviderUnavailable("O vLLM Realtime não terminou a transcrição a tempo.")
            self._drain(timeout=remaining)
        return self._done

    def close(self) -> None:
        _close_quietly(self._ws)

    def _drain(self, timeout: float) -> bool:
        """Read every event already waiting (and, with a timeout, wait for the
        first one). Return whether the text changed."""
        changed = False
        while self._done is None:
            try:
                msg = _recv_json(self._ws, timeout=timeout)
            except TimeoutError:
                break
            changed |= self._handle(msg)
            timeout = 0
        return changed

    def _handle(self, msg: dict[str, Any]) -> bool:
        kind = msg.get("type")
        if kind == "transcription.delta":
            delta = msg.get("delta") or ""
            self._text += delta
            return bool(delta)
        if kind == "transcription.done":
            self._done = msg.get("text") if msg.get("text") is not None else self._text
            changed = self._done != self._text
            self._text = self._done
            return changed
        if kind == "error":
            raise ProviderUnavailable(f"vLLM Realtime: {msg.get('error')}")
        return False


def _recv_json(ws: Any, timeout: float) -> dict[str, Any]:
    raw = ws.recv(timeout=timeout)
    if isinstance(raw, (bytes, bytearray)):
        raw = raw.decode("utf-8")
    msg = json.loads(raw)
    return msg if isinstance(msg, dict) else {}


def _close_quietly(ws: Any) -> None:
    try:
        ws.close()
    except Exception:
        pass
