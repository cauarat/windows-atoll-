"""Light formatting of a transcript, applied to partials and finals alike.

Qwen3-ASR already writes punctuation. This only tidies what is there, and never
adds, drops or reorders a word, so what was said is what comes out:

- runs of spaces, tabs and newlines become one space, and the ends are trimmed;
- no space before , . ; : ! ? … % or a closing bracket, none after an opening one;
- the first letter of the text and of each sentence is upper case.

Numbers keep their separators ("3,5", "1.200"), because nothing here adds a
space after punctuation.
"""

from __future__ import annotations

import re

_SPACES = re.compile(r"\s+")
_SPACE_BEFORE = re.compile(r"\s+([,.;:!?…%)\]}»])")
_SPACE_AFTER = re.compile(r"([(\[{«])\s+")
# A sentence starts after . ! ? or … followed by a space. Lowercase letters
# include the accented ones Portuguese uses.
_SENTENCE_START = re.compile(r"([.!?…]\s+[\"'“«(]?)([a-zà-ÿ])")


def format_transcript(text: str | None) -> str:
    if not text:
        return ""
    out = _SPACES.sub(" ", text).strip()
    out = _SPACE_BEFORE.sub(r"\1", out)
    out = _SPACE_AFTER.sub(r"\1", out)
    out = _capitalize_first(out)
    out = _SENTENCE_START.sub(lambda m: m.group(1) + m.group(2).upper(), out)
    return out


def _capitalize_first(text: str) -> str:
    for i, ch in enumerate(text):
        if ch.isalpha():
            return text[:i] + ch.upper() + text[i + 1:]
        if ch.isdigit():
            return text
    return text
