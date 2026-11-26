"""Settings, read from the environment and an optional `.env` file.

Everything here is a plain value that is safe to show: an address, a model id,
a few tuning numbers. The service has no secret to keep, and `.env.example`
lists exactly these keys. Precedence: the real environment, then `.env`, then
the defaults below.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, fields, replace
from pathlib import Path
from typing import Mapping

PROVIDERS = ("qwen3-asr", "voxtral-realtime")
BACKENDS = ("auto", "vllm", "transformers")
DTYPES = ("auto", "bfloat16", "float16", "float32")


class ConfigError(ValueError):
    """A setting has a value the service cannot run with."""


@dataclass(frozen=True)
class Settings:
    host: str = "127.0.0.1"
    port: int = 8765
    provider: str = "qwen3-asr"
    model: str = "Qwen/Qwen3-ASR-1.7B"
    backend: str = "auto"
    device: str = "auto"
    dtype: str = "auto"
    language: str = "pt-BR"
    # Qwen3ASRModel.init_streaming_state, with the values of the official
    # live-microphone demo (qwen-asr-demo-streaming): the model re-decodes
    # everything heard so far each time this much new audio arrives, so it is
    # also how often a partial can change.
    chunk_seconds: float = 1.0
    unfixed_chunks: int = 4
    unfixed_tokens: int = 5
    # Per streaming step, as in that demo: each step only has to write past
    # the prefix it was given.
    stream_max_new_tokens: int = 32
    # A whole recording at once (offline backend, POST /v1/transcribe).
    max_new_tokens: int = 1024
    gpu_memory_utilization: float = 0.8
    # Five minutes, the same cap the Mac puts on a voice note.
    max_seconds: float = 300.0
    # Optional words the model should expect (names, jargon). Not a secret.
    context: str = ""
    # Seconds between keep-warm runs (half a second of silence through the
    # model) while nobody dictates. Left idle, the model goes cold: on Apple
    # silicon the first transcription after two idle minutes took 24 s instead
    # of 2. -1 = automatic (30 on MPS, off elsewhere), 0 = off.
    keep_warm_seconds: float = -1
    # Origins allowed to open a session. Empty: refuse every request that
    # carries an Origin header, which is to say every web page. The Notchy apps
    # send none.
    allowed_origins: tuple[str, ...] = ()
    voxtral_url: str = "ws://127.0.0.1:8000/v1/realtime"
    voxtral_model: str = "mistralai/Voxtral-Mini-4B-Realtime-2602"
    log_level: str = "info"

    @classmethod
    def from_env(
        cls,
        environ: Mapping[str, str] | None = None,
        env_file: Path | None = None,
    ) -> "Settings":
        env = dict(read_env_file(env_file)) if env_file else {}
        env.update(os.environ if environ is None else environ)
        values: dict[str, object] = {}
        for f in fields(cls):
            raw = env.get(_env_name(f.name))
            if raw is None or raw.strip() == "":
                continue
            values[f.name] = _coerce(f.name, f.type, raw.strip())
        return cls(**values).validated()

    def validated(self) -> "Settings":
        if self.provider not in PROVIDERS:
            raise ConfigError(
                f"DICTATION_PROVIDER={self.provider!r} não existe. Use um de: {', '.join(PROVIDERS)}."
            )
        if self.backend not in BACKENDS:
            raise ConfigError(
                f"DICTATION_BACKEND={self.backend!r} não existe. Use um de: {', '.join(BACKENDS)}."
            )
        if self.dtype not in DTYPES:
            raise ConfigError(f"DICTATION_DTYPE={self.dtype!r} não existe. Use um de: {', '.join(DTYPES)}.")
        if not 0 < self.port < 65536:
            raise ConfigError(f"DICTATION_PORT={self.port} fora do intervalo 1–65535.")
        if self.chunk_seconds <= 0:
            raise ConfigError("DICTATION_CHUNK_SECONDS precisa ser maior que zero.")
        if not 0 < self.gpu_memory_utilization <= 1:
            raise ConfigError("DICTATION_GPU_MEMORY_UTILIZATION precisa estar entre 0 e 1.")
        if self.max_seconds <= 0:
            raise ConfigError("DICTATION_MAX_SECONDS precisa ser maior que zero.")
        return self

    def with_overrides(self, **changes: object) -> "Settings":
        clean = {k: v for k, v in changes.items() if v is not None}
        return replace(self, **clean).validated()


def _env_name(field_name: str) -> str:
    # The two Voxtral settings read as VOXTRAL_URL / VOXTRAL_MODEL rather than
    # DICTATION_VOXTRAL_*: they configure the other server, not this one.
    if field_name.startswith("voxtral_"):
        return "VOXTRAL_" + field_name[len("voxtral_"):].upper()
    return "DICTATION_" + field_name.upper()


def _coerce(name: str, annotation: object, raw: str) -> object:
    kind = str(annotation)
    try:
        if kind == "int":
            return int(raw)
        if kind == "float":
            return float(raw.replace(",", "."))
        if kind.startswith("tuple"):
            return tuple(part.strip() for part in raw.split(",") if part.strip())
    except ValueError as exc:
        raise ConfigError(f"{_env_name(name)}={raw!r} não é um número válido.") from exc
    return raw


def read_env_file(path: Path) -> dict[str, str]:
    """`KEY=value` lines; `#` comments and blank lines ignored; quotes stripped."""
    if not path or not path.is_file():
        return {}
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        if key.startswith("export "):
            key = key[len("export "):].strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        out[key] = value
    return out
