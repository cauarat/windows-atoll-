#!/usr/bin/env bash
# The dictation service's unit tests. No model, no GPU, no download of weights:
# the providers are driven by test doubles that follow qwen-asr's own contract
# (dictation-service/tests/fakes.py), and the protocol cases come from
# tests/fixtures/dictation.json, which the Mac and Windows clients read too.
set -euo pipefail
cd "$(dirname "$0")/../dictation-service"

# A Python with the service's dependencies: DICTATION_TEST_PYTHON if set, else
# the service's own .venv (scripts/start.sh makes it), else a throwaway
# .venv-test holding only what the tests import (fastapi, httpx, numpy,
# websockets — a few MB, no PyTorch).
PY="${DICTATION_TEST_PYTHON:-}"
if [ -z "$PY" ] && [ -x .venv/bin/python ] \
    && .venv/bin/python -c 'import fastapi, httpx, numpy, websockets' 2>/dev/null; then
    PY=.venv/bin/python
fi
if [ -z "$PY" ]; then
    if [ ! -x .venv-test/bin/python ]; then
        BASE=""
        for candidate in python3.12 python3.13 python3.11 python3.10 python3; do
            if command -v "$candidate" >/dev/null 2>&1 \
                && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
                BASE="$candidate"
                break
            fi
        done
        if [ -z "$BASE" ]; then
            echo "The dictation service tests need Python 3.10 or newer." >&2
            exit 1
        fi
        "$BASE" -m venv .venv-test
        .venv-test/bin/python -m pip install --quiet --upgrade pip
        .venv-test/bin/python -m pip install --quiet -e ".[test]"
    fi
    PY=.venv-test/bin/python
fi

PYTHONPATH=src "$PY" -m unittest discover -s tests -t tests
