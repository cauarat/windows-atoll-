"""The recognition languages the apps can ask for.

The apps name a language by its BCP 47 tag and show the label; each provider
gets the spelling it wants. Only Brazilian Portuguese for now. Qwen3-ASR has a
single "Portuguese" and does not tell Brazil from Portugal, so the tag is what
the person chose, and the model hint is the closest one it has.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Language:
    code: str  # BCP 47, what the apps send and show
    label: str  # shown next to the code
    qwen: str  # Qwen3-ASR's canonical name (qwen_asr.inference.utils.SUPPORTED_LANGUAGES)


PT_BR = Language(code="pt-BR", label="Português (Brasil)", qwen="Portuguese")

_BY_CODE = {PT_BR.code.lower(): PT_BR}
_ALIASES = {"pt": PT_BR, "pt_br": PT_BR, "pt-br": PT_BR, "portuguese": PT_BR, "português": PT_BR}


class UnsupportedLanguage(ValueError):
    pass


def resolve(code: str | None, default: str = PT_BR.code) -> Language:
    key = (code or default).strip().lower()
    lang = _BY_CODE.get(key) or _ALIASES.get(key)
    if lang is None:
        raise UnsupportedLanguage(
            f"Idioma {code!r} não é suportado. Disponível: {', '.join(l.code for l in _BY_CODE.values())}."
        )
    return lang


def supported() -> list[Language]:
    return list(_BY_CODE.values())
