"""One dictation over the WebSocket.

Audio frames are queued as they arrive and fed to the provider in order, on the
provider's executor. Partials go back as soon as the provider has a new
hypothesis. `stop` puts a marker at the end of the queue, so the final is only
computed once every frame sent before it has been heard: the last words are
never cut, and since each partial is the whole hypothesis, none is repeated.
"""

from __future__ import annotations

import asyncio
import logging
import time
import uuid
from contextlib import suppress
from typing import Any, Awaitable, Callable

from . import protocol
from .audio import SAMPLE_RATE, pcm16le_to_float32, samples_to_ms
from .config import Settings
from .languages import Language
from .postprocess import format_transcript
from .providers.base import Provider, ProviderUnavailable, TranscriptionStream

log = logging.getLogger("notchy_dictation.session")

Send = Callable[[dict[str, Any]], Awaitable[None]]


class SessionFailed(RuntimeError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def error_for(exc: BaseException) -> SessionFailed:
    if isinstance(exc, SessionFailed):
        return exc
    if isinstance(exc, ProviderUnavailable):
        return SessionFailed(protocol.PROVIDER_UNAVAILABLE, str(exc))
    return SessionFailed(protocol.INTERNAL, f"Erro interno no serviço de transcrição ({type(exc).__name__}).")


class DictationSession:
    def __init__(
        self,
        provider: Provider,
        settings: Settings,
        language: Language,
        send: Send,
        *,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.id = uuid.uuid4().hex[:12]
        self._provider = provider
        self._language = language
        self._send = send
        self._clock = clock
        self._stream: TranscriptionStream | None = None
        self._queue: asyncio.Queue[bytes | None] = asyncio.Queue()
        self._consumer: asyncio.Task[None] | None = None
        self._carry = b""
        self._samples = 0
        self._max_samples = int(settings.max_seconds * SAMPLE_RATE)
        self._truncated = False
        self._last_partial = ""
        self._seq = 0
        self._closed = False
        self.failure: SessionFailed | None = None

    @property
    def audio_ms(self) -> int:
        return samples_to_ms(self._samples)

    async def open(self) -> None:
        self._stream = await self._run(self._provider.open_stream, self._language)
        self._consumer = asyncio.create_task(self._consume(), name=f"dictation-{self.id}")

    async def feed(self, data: bytes) -> bool:
        """Queue audio. False once the length cap is reached: finish then."""
        if self._closed or self._truncated:
            return not self._truncated
        data = self._carry + data
        if len(data) % 2:
            self._carry, data = data[-1:], data[:-1]
        else:
            self._carry = b""
        count = len(data) // 2
        room = self._max_samples - self._samples
        if count > room:
            data, count = data[: room * 2], room
            self._truncated = True
        if count:
            self._samples += count
            await self._queue.put(data)
        return not self._truncated

    async def finish(self) -> dict[str, Any]:
        """Everything has been sent: hear the rest, then answer with the final."""
        await self._queue.put(None)
        if self._consumer is not None:
            await self._consumer
        if self.failure is not None:
            raise self.failure
        assert self._stream is not None
        started = self._clock()
        try:
            raw = await self._run(self._stream.finish)
        except Exception as exc:
            raise error_for(exc) from exc
        processing_ms = int(round((self._clock() - started) * 1000))
        await self.close()
        return protocol.final(format_transcript(raw), self.audio_ms, processing_ms, self._truncated)

    async def cancel(self) -> None:
        if self._consumer is not None and not self._consumer.done():
            self._consumer.cancel()
            with suppress(asyncio.CancelledError, Exception):
                await self._consumer
        await self.close()

    async def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        stream, self._stream = self._stream, None
        if stream is not None:
            try:
                await self._run(stream.close)
            except Exception:
                log.debug("stream close failed", exc_info=True)

    async def _consume(self) -> None:
        try:
            done = False
            while not done:
                item = await self._queue.get()
                parts: list[bytes] = []
                if item is None:
                    done = True
                else:
                    parts.append(item)
                # Whatever else is already waiting goes in the same call, in order.
                while not done and not self._queue.empty():
                    nxt = self._queue.get_nowait()
                    if nxt is None:
                        done = True
                    else:
                        parts.append(nxt)
                if not parts:
                    continue
                assert self._stream is not None
                hypothesis = await self._run(self._stream.feed, pcm16le_to_float32(b"".join(parts)))
                if hypothesis is not None:
                    await self._emit_partial(hypothesis)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            self.failure = error_for(exc)
            log.warning("dictation %s failed while streaming: %s", self.id, type(exc).__name__)
            with suppress(Exception):
                await self._send(protocol.error(self.failure.code, self.failure.message))

    async def _emit_partial(self, raw: str) -> None:
        text = format_transcript(raw)
        if not text or text == self._last_partial:
            return
        self._last_partial = text
        self._seq += 1
        await self._send(protocol.partial(text, self._seq))

    def _run(self, fn: Callable[..., Any], *args: Any) -> "asyncio.Future[Any]":
        return asyncio.get_running_loop().run_in_executor(self._provider.executor, fn, *args)
