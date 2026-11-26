#!/usr/bin/env bash
# Starts Notchy's dictation service on macOS or Linux.
#
# First run: creates dictation-service/.venv and installs the service with the
# Qwen3-ASR extra that fits this machine. Linux with an NVIDIA GPU gets
# qwen-vllm (streaming, partial text while you speak); everything else gets
# qwen (Transformers: the text comes when you stop). Force one with
# DICTATION_EXTRA=qwen or DICTATION_EXTRA=qwen-vllm. The model weights
# (Qwen/Qwen3-ASR-1.7B, about 4.7 GB) download on the first start into the
# Hugging Face cache (~/.cache/huggingface).
#
# Arguments go to the service: scripts/start.sh --port 8800, scripts/start.sh --check
set -euo pipefail
cd "$(dirname "$0")/.."

find_python() {
    for candidate in "${PYTHON:-}" python3.12 python3.13 python3.11 python3.10 python3; do
        [ -n "$candidate" ] || continue
        command -v "$candidate" >/dev/null 2>&1 || continue
        if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
            echo "$candidate"
            return
        fi
    done
    echo "Preciso do Python 3.10 ou mais novo (o Qwen3-ASR recomenda o 3.12)." >&2
    exit 1
}

pick_extra() {
    if [ -n "${DICTATION_EXTRA:-}" ]; then
        echo "$DICTATION_EXTRA"
    elif [ "$(uname -s)" = "Linux" ] && command -v nvidia-smi >/dev/null 2>&1 \
        && [ "${DICTATION_BACKEND:-auto}" != "transformers" ]; then
        echo "qwen-vllm"
    else
        echo "qwen"
    fi
}

VENV="${DICTATION_VENV:-.venv}"
EXTRA="$(pick_extra)"

if [ ! -x "$VENV/bin/python" ]; then
    PY="$(find_python)"
    echo "Criando o ambiente em $VENV com $("$PY" --version)…"
    "$PY" -m venv "$VENV"
    "$VENV/bin/python" -m pip install --quiet --upgrade pip
fi

if [ ! -f "$VENV/.installed-$EXTRA" ]; then
    echo "Instalando o serviço com o extra [$EXTRA] (pode levar alguns minutos)…"
    "$VENV/bin/python" -m pip install --upgrade -e ".[$EXTRA]"
    touch "$VENV/.installed-$EXTRA"
fi

[ -f .env ] || echo "Sem .env: usando os padrões (copie .env.example para .env para mudar algo)."

# Apple silicon: some PyTorch operations have no Metal kernel yet; this lets
# them fall back to the CPU instead of failing.
export PYTORCH_ENABLE_MPS_FALLBACK="${PYTORCH_ENABLE_MPS_FALLBACK:-1}"
exec "$VENV/bin/python" -m notchy_dictation "$@"
