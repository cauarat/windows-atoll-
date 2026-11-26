"""The messages between the apps and the service, one place for both sides.

Session on `WS /v1/dictation`:

    app → {"type": "start", "language": "pt-BR", "sample_rate": 16000,
           "encoding": "pcm_s16le", "channels": 1}
    app → binary frames: PCM16 little-endian, mono, 16 kHz (any length)
    app → {"type": "stop"}      all audio is sent: finish and answer
       or {"type": "cancel"}    throw it away, no answer

    service → {"type": "ready", ...provider info}
    service → {"type": "partial", "text": "...", "seq": n}
              The whole hypothesis so far. It REPLACES the previous one, it is
              never appended, so nothing is shown twice. Only streaming
              backends send these.
    service → {"type": "final", "text": "...", "audio_ms": n,
               "processing_ms": n, "truncated": bool}
    service → {"type": "error", "code": "...", "message": "..."}

The service closes the socket after `final` or `error`. The codes are stable
so the apps can translate them; the message is a detail in Portuguese.
"""

from __future__ import annotations

import json
from typing import Any

from . import PROTOCOL_VERSION
from .audio import SAMPLE_RATE

ENCODING = "pcm_s16le"

# Error codes. Also listed in tests/fixtures/dictation-protocol.json, which the
# Mac and Windows clients are checked against.
BAD_REQUEST = "bad_request"
UNSUPPORTED_AUDIO = "unsupported_audio"
UNSUPPORTED_LANGUAGE = "unsupported_language"
MODEL_LOADING = "model_loading"
MODEL_FAILED = "model_failed"
PROVIDER_UNAVAILABLE = "provider_unavailable"
FORBIDDEN_ORIGIN = "forbidden_origin"
INTERNAL = "internal"

ERROR_CODES = (
    BAD_REQUEST,
    UNSUPPORTED_AUDIO,
    UNSUPPORTED_LANGUAGE,
    MODEL_LOADING,
    MODEL_FAILED,
    PROVIDER_UNAVAILABLE,
    FORBIDDEN_ORIGIN,
    INTERNAL,
)

CLIENT_TYPES = ("start", "stop", "cancel")


class ProtocolError(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def parse_client_message(text: str) -> dict[str, Any]:
    try:
        msg = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ProtocolError(BAD_REQUEST, "Mensagem não é JSON válido.") from exc
    if not isinstance(msg, dict) or msg.get("type") not in CLIENT_TYPES:
        raise ProtocolError(BAD_REQUEST, f"Tipo de mensagem desconhecido: {msg!r:.80}")
    if msg["type"] == "start":
        rate = msg.get("sample_rate", SAMPLE_RATE)
        encoding = msg.get("encoding", ENCODING)
        channels = msg.get("channels", 1)
        if rate != SAMPLE_RATE or encoding != ENCODING or channels != 1:
            raise ProtocolError(
                UNSUPPORTED_AUDIO,
                f"Áudio precisa ser {ENCODING}, mono, {SAMPLE_RATE} Hz "
                f"(recebido: {encoding}, {channels} canal(is), {rate} Hz).",
            )
    return msg


def ready(session_id: str, info: dict[str, Any], language: str, label: str) -> dict[str, Any]:
    return {
        "type": "ready",
        "protocol": PROTOCOL_VERSION,
        "session": session_id,
        **info,
        "language": language,
        "language_label": label,
    }


def partial(text: str, seq: int) -> dict[str, Any]:
    return {"type": "partial", "text": text, "seq": seq}


def final(text: str, audio_ms: int, processing_ms: int, truncated: bool) -> dict[str, Any]:
    return {
        "type": "final",
        "text": text,
        "audio_ms": audio_ms,
        "processing_ms": processing_ms,
        "truncated": truncated,
    }


def error(code: str, message: str) -> dict[str, Any]:
    return {"type": "error", "code": code, "message": message}


def dumps(msg: dict[str, Any]) -> str:
    return json.dumps(msg, ensure_ascii=False, separators=(",", ":"))
