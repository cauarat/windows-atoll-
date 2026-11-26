"""HTTP and WebSocket front of the service.

    GET  /health          is the model loaded, which one, can it stream
    WS   /v1/dictation    one dictation per connection (protocol.py)
    POST /v1/transcribe   a WAV file in, its text out (for curl and tests)

Nothing is written to disk: audio lives in memory for the length of one
dictation. The log records how long each one was, never what was said.
"""

from __future__ import annotations

import asyncio
import logging
import time
from contextlib import asynccontextmanager, suppress
from typing import Any, AsyncIterator

from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse

from . import PROTOCOL_VERSION, __version__, languages, protocol
from .audio import AudioFormatError, read_wav, samples_to_ms, SAMPLE_RATE
from .config import Settings
from .postprocess import format_transcript
from .providers import Provider, ProviderUnavailable, create_provider
from .session import DictationSession, SessionFailed, error_for

log = logging.getLogger("notchy_dictation")

# A WAV upload: five minutes of 16-bit 48 kHz stereo is about 55 MB.
MAX_UPLOAD_BYTES = 64 * 1024 * 1024


class ServiceState:
    def __init__(self, settings: Settings, provider: Provider) -> None:
        self.settings = settings
        self.provider = provider
        self.status = "loading"  # loading | ready | error
        self.error: str | None = None
        self.load_seconds: float | None = None
        self.active_sessions = 0
        self.last_used = time.monotonic()

    @property
    def ready(self) -> bool:
        return self.status == "ready"

    def touch(self) -> None:
        self.last_used = time.monotonic()

    def idle_for(self) -> float:
        return time.monotonic() - self.last_used

    def keep_warm_interval(self) -> float:
        """Seconds between keep-warm runs; 0 when off. Automatic means on for
        Apple silicon, where an idle model was measured going cold (24 s for
        the first transcription after two minutes, 2 s after that)."""
        if not self.provider.wants_warm_up:
            return 0.0
        if self.settings.keep_warm_seconds >= 0:
            return self.settings.keep_warm_seconds
        return 30.0 if self.provider.info().device == "mps" else 0.0

    def health(self) -> dict[str, Any]:
        lang = languages.resolve(self.settings.language)
        return {
            "status": self.status,
            "ready": self.ready,
            "protocol": PROTOCOL_VERSION,
            "version": __version__,
            **self.provider.info().as_dict(),
            "language": lang.code,
            "language_label": lang.label,
            "error": self.error,
            "load_seconds": self.load_seconds,
        }

    def not_ready_error(self) -> dict[str, Any]:
        if self.status == "error":
            return protocol.error(protocol.MODEL_FAILED, self.error or "O modelo não carregou.")
        return protocol.error(protocol.MODEL_LOADING, "O modelo ainda está carregando. Tente em alguns segundos.")


def load_provider(state: ServiceState) -> None:
    """Blocking. Leaves the outcome in `state` instead of raising, so the
    service still answers /health and the apps can show why it cannot work."""
    started = time.monotonic()
    try:
        state.provider.load()
    except ProviderUnavailable as exc:
        state.status, state.error = "error", str(exc)
        log.error("provider unavailable: %s", exc)
    except Exception as exc:  # the model's own failure: OOM, bad weights, driver
        state.status, state.error = "error", f"Falha ao carregar o modelo: {type(exc).__name__}: {exc}"
        log.exception("model failed to load")
    else:
        # One run on silence before saying ready: the first real dictation
        # should not be the one that pays for compiling the kernels.
        if state.provider.wants_warm_up:
            try:
                state.provider.warm_up()
            except Exception:
                log.warning("warm-up failed", exc_info=True)
        state.status, state.error = "ready", None
        state.load_seconds = round(time.monotonic() - started, 1)
        state.touch()
        info = state.provider.info()
        log.info(
            "ready: %s (%s, backend %s, %s, %s) in %.1f s",
            info.model, info.provider, info.backend, info.device,
            "streaming" if info.streaming else "offline", state.load_seconds,
        )


def create_app(settings: Settings, provider: Provider | None = None, *, preload: bool = True) -> FastAPI:
    provider = provider or create_provider(settings)
    state = ServiceState(settings, provider)

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        if preload and state.status == "loading":
            asyncio.get_running_loop().run_in_executor(provider.executor, load_provider, state)
        warmer = asyncio.create_task(_keep_warm(state))
        try:
            yield
        finally:
            warmer.cancel()
            provider.shutdown()

    app = FastAPI(title="Notchy Dictation", version=__version__, lifespan=lifespan)
    app.state.service = state

    def origin_allowed(origin: str | None) -> bool:
        # The apps send no Origin. A web page always does, and must not be able
        # to drive a service that hears whatever it is sent.
        return origin is None or origin in settings.allowed_origins

    @app.middleware("http")
    async def refuse_web_pages(request: Request, call_next: Any) -> Any:
        if not origin_allowed(request.headers.get("origin")):
            return JSONResponse(
                protocol.error(protocol.FORBIDDEN_ORIGIN, "Origem não permitida."), status_code=403
            )
        return await call_next(request)

    @app.get("/health")
    async def health() -> dict[str, Any]:
        return state.health()

    @app.post("/v1/transcribe")
    async def transcribe(request: Request, language: str | None = None) -> Any:
        if not state.ready:
            return JSONResponse(state.not_ready_error(), status_code=503)
        body = await request.body()
        if len(body) > MAX_UPLOAD_BYTES:
            return JSONResponse(protocol.error(protocol.UNSUPPORTED_AUDIO, "Arquivo grande demais."), status_code=413)
        try:
            lang = languages.resolve(language, settings.language)
            samples = read_wav(body)
        except languages.UnsupportedLanguage as exc:
            return JSONResponse(protocol.error(protocol.UNSUPPORTED_LANGUAGE, str(exc)), status_code=400)
        except AudioFormatError as exc:
            return JSONResponse(protocol.error(protocol.UNSUPPORTED_AUDIO, str(exc)), status_code=415)
        max_samples = int(settings.max_seconds * SAMPLE_RATE)
        truncated = samples.size > max_samples
        samples = samples[:max_samples]
        started = time.monotonic()
        state.touch()
        try:
            raw = await asyncio.get_running_loop().run_in_executor(
                provider.executor, provider.transcribe, samples, lang
            )
        except Exception as exc:
            failure = error_for(exc)
            log.warning("transcribe failed: %s", type(exc).__name__)
            return JSONResponse(protocol.error(failure.code, failure.message), status_code=500)
        processing_ms = int(round((time.monotonic() - started) * 1000))
        audio_ms = samples_to_ms(samples.size)
        log.info("file: %d ms of audio, %d ms to transcribe", audio_ms, processing_ms)
        return {
            "text": format_transcript(raw),
            "language": lang.code,
            "language_label": lang.label,
            "audio_ms": audio_ms,
            "processing_ms": processing_ms,
            "truncated": truncated,
            **provider.info().as_dict(),
        }

    @app.websocket("/v1/dictation")
    async def dictation(ws: WebSocket) -> None:
        if not origin_allowed(ws.headers.get("origin")):
            await ws.close(code=1008)
            return
        await ws.accept()
        send_lock = asyncio.Lock()

        async def send(msg: dict[str, Any]) -> None:
            async with send_lock:
                await ws.send_text(protocol.dumps(msg))

        session: DictationSession | None = None
        try:
            start = await _receive_start(ws)
            if not state.ready:
                await send(state.not_ready_error())
                return
            lang = languages.resolve(start.get("language"), settings.language)
            # Warm the model while the person is still talking, unless it ran
            # a moment ago: on Apple silicon a cold first call is ten times
            # slower, and this way the speaking pays for it, not the waiting.
            warm = provider.wants_warm_up and state.idle_for() > 20
            session = DictationSession(provider, settings, lang, send, warm_up=warm)
            state.active_sessions += 1
            state.touch()
            await session.open()
            await send(protocol.ready(session.id, provider.info().as_dict(), lang.code, lang.label))
            log.info("dictation %s started", session.id)
            await _run_session(ws, session, send)
        except protocol.ProtocolError as exc:
            await _send_quietly(send, protocol.error(exc.code, exc.message))
        except languages.UnsupportedLanguage as exc:
            await _send_quietly(send, protocol.error(protocol.UNSUPPORTED_LANGUAGE, str(exc)))
        except SessionFailed as exc:
            await _send_quietly(send, protocol.error(exc.code, exc.message))
        except WebSocketDisconnect:
            pass
        except Exception as exc:
            failure = error_for(exc)
            log.exception("dictation failed")
            await _send_quietly(send, protocol.error(failure.code, failure.message))
        finally:
            if session is not None:
                state.active_sessions -= 1
                state.touch()
                await session.cancel()
            with suppress(Exception):
                await ws.close()

    return app


async def _keep_warm(state: ServiceState) -> None:
    """Runs the model on silence after a while with no dictation, so it is
    never cold when someone starts talking. Costs a fraction of a second of
    work per interval; DICTATION_KEEP_WARM_SECONDS=0 turns it off."""
    loop = asyncio.get_running_loop()
    while True:
        await asyncio.sleep(5)
        interval = state.keep_warm_interval() if state.ready else 0.0
        if interval <= 0 or state.active_sessions > 0 or state.idle_for() < interval:
            continue
        state.touch()
        try:
            await loop.run_in_executor(state.provider.executor, state.provider.warm_up)
        except Exception:
            log.debug("keep-warm failed", exc_info=True)


async def _receive_start(ws: WebSocket) -> dict[str, Any]:
    message = await ws.receive()
    if message["type"] == "websocket.disconnect":
        raise WebSocketDisconnect(message.get("code", 1000))
    text = message.get("text")
    if text is None:
        raise protocol.ProtocolError(protocol.BAD_REQUEST, "A primeira mensagem precisa ser {\"type\": \"start\"}.")
    msg = protocol.parse_client_message(text)
    if msg["type"] != "start":
        raise protocol.ProtocolError(protocol.BAD_REQUEST, "A primeira mensagem precisa ser {\"type\": \"start\"}.")
    return msg


async def _run_session(ws: WebSocket, session: DictationSession, send: Any) -> None:
    while True:
        message = await ws.receive()
        if message["type"] == "websocket.disconnect":
            await session.cancel()
            log.info("dictation %s: client left after %d ms", session.id, session.audio_ms)
            return
        data = message.get("bytes")
        if data is not None:
            room = await session.feed(data)
            if session.failure is not None:
                return  # the consumer already sent the error
            if not room:  # length cap: answer with what was heard
                await _finish(session, send)
                return
            continue
        text = message.get("text")
        if text is None:
            continue
        msg = protocol.parse_client_message(text)
        if msg["type"] == "stop":
            await _finish(session, send)
            return
        if msg["type"] == "cancel":
            await session.cancel()
            log.info("dictation %s cancelled", session.id)
            return
        raise protocol.ProtocolError(protocol.BAD_REQUEST, "A sessão já começou.")


async def _finish(session: DictationSession, send: Any) -> None:
    result = await session.finish()
    log.info(
        "dictation %s finished: %d ms of audio, %d ms to finish",
        session.id, result["audio_ms"], result["processing_ms"],
    )
    await send(result)


async def _send_quietly(send: Any, msg: dict[str, Any]) -> None:
    with suppress(Exception):
        await send(msg)
