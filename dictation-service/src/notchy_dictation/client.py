"""Test client: sends a WAV file through /v1/dictation the way the apps do.

    python -m notchy_dictation.client gravacao.wav
    python -m notchy_dictation.client gravacao.wav --fast
    python -m notchy_dictation.client gravacao.wav --url ws://192.168.0.20:8765/v1/dictation

Frames of 100 ms, at the pace of real speech unless --fast, then `stop`. Prints
each partial as it comes and the final. Useful to see the streaming backend
work without the app, or to check a service running on another machine.
"""

from __future__ import annotations

import argparse
import json
import sys
import threading
import time
from pathlib import Path

from .audio import SAMPLE_RATE, float32_to_pcm16le, read_wav

FRAME_SAMPLES = SAMPLE_RATE // 10  # 100 ms, as the apps send


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m notchy_dictation.client")
    parser.add_argument("wav", type=Path)
    parser.add_argument("--url", default="ws://127.0.0.1:8765/v1/dictation")
    parser.add_argument("--language", default="pt-BR")
    parser.add_argument("--fast", action="store_true", help="envia tudo de uma vez, sem esperar o tempo real")
    args = parser.parse_args(argv)

    from websockets.sync.client import connect

    if not args.wav.is_file():
        print(f"arquivo não encontrado: {args.wav}", file=sys.stderr)
        return 2
    samples = read_wav(args.wav.read_bytes())
    pcm = float32_to_pcm16le(samples)
    frame_bytes = FRAME_SAMPLES * 2

    with connect(args.url, open_timeout=10, max_size=None) as ws:
        ws.send(json.dumps({"type": "start", "language": args.language, "sample_rate": SAMPLE_RATE,
                            "encoding": "pcm_s16le", "channels": 1}))
        ready = json.loads(ws.recv(timeout=30))
        if ready.get("type") != "ready":
            print(f"erro: {ready.get('code')}: {ready.get('message')}", file=sys.stderr)
            return 1
        mode = "streaming" if ready.get("streaming") else "offline (só o texto final)"
        print(f"{ready.get('model')} · {ready.get('backend')} · {mode} · {ready.get('language')}")

        started = time.monotonic()
        result: dict = {}

        def reader() -> None:
            while True:
                try:
                    msg = json.loads(ws.recv())
                except Exception:
                    return
                if msg.get("type") == "partial":
                    print(f"  [{time.monotonic() - started:5.1f} s] parcial: {msg['text']}")
                elif msg.get("type") in ("final", "error"):
                    result.update(msg)
                    return

        thread = threading.Thread(target=reader, daemon=True)
        thread.start()
        for offset in range(0, len(pcm), frame_bytes):
            ws.send(pcm[offset: offset + frame_bytes])
            if not args.fast:
                time.sleep(FRAME_SAMPLES / SAMPLE_RATE)
        sent_at = time.monotonic()
        ws.send(json.dumps({"type": "stop"}))
        thread.join(timeout=120)

    if result.get("type") != "final":
        print(f"erro: {result.get('code', 'sem resposta')}: {result.get('message', '')}", file=sys.stderr)
        return 1
    print(f"final ({(time.monotonic() - sent_at) * 1000:.0f} ms depois do stop, "
          f"{result['processing_ms']} ms no modelo): {result['text']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
