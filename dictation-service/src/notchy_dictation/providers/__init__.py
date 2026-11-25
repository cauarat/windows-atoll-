"""Speech providers, picked by DICTATION_PROVIDER.

To add one: subclass `Provider` (providers/base.py), register a factory below,
and add its name to config.PROVIDERS. Nothing else in the service, and nothing
in the apps, depends on which provider is running.
"""

from __future__ import annotations

from typing import Callable

from ..config import ConfigError, Settings
from .base import Provider, ProviderInfo, ProviderUnavailable, TranscriptionStream


def _qwen(settings: Settings) -> Provider:
    from .qwen3_asr import Qwen3AsrProvider

    return Qwen3AsrProvider(settings)


def _voxtral(settings: Settings) -> Provider:
    from .voxtral_realtime import VoxtralRealtimeProvider

    return VoxtralRealtimeProvider(settings)


FACTORIES: dict[str, Callable[[Settings], Provider]] = {
    "qwen3-asr": _qwen,
    "voxtral-realtime": _voxtral,
}


def create_provider(settings: Settings) -> Provider:
    factory = FACTORIES.get(settings.provider)
    if factory is None:
        raise ConfigError(f"Provedor desconhecido: {settings.provider!r}.")
    return factory(settings)


__all__ = [
    "FACTORIES",
    "Provider",
    "ProviderInfo",
    "ProviderUnavailable",
    "TranscriptionStream",
    "create_provider",
]
