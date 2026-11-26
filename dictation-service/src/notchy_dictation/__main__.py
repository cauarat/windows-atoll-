"""`python -m notchy_dictation` — start the service, or `--check` this machine."""

from __future__ import annotations

import argparse
import ipaddress
import json
import logging
import sys
import time
from pathlib import Path

from . import __version__
from .config import ConfigError, Settings

log = logging.getLogger("notchy_dictation")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="notchy-dictation",
        description="Serviço local de ditado do Notchy (Qwen3-ASR por padrão).",
    )
    parser.add_argument("--host", help="endereço de escuta (padrão 127.0.0.1)")
    parser.add_argument("--port", type=int, help="porta (padrão 8765)")
    parser.add_argument("--provider", help="qwen3-asr ou voxtral-realtime")
    parser.add_argument("--backend", help="auto, vllm ou transformers (Qwen3-ASR)")
    parser.add_argument("--model", help="id do modelo no Hugging Face ou pasta local")
    parser.add_argument("--device", help="auto, cuda:0, mps ou cpu (backend transformers)")
    parser.add_argument("--env-file", default=".env", help="arquivo de configuração (padrão .env)")
    parser.add_argument(
        "--check",
        nargs="?",
        const="",
        metavar="WAV",
        help="carrega o modelo, transcreve um WAV (ou 1 s de silêncio) e sai",
    )
    parser.add_argument("--version", action="version", version=f"notchy-dictation {__version__}")
    args = parser.parse_args(argv)

    try:
        settings = Settings.from_env(env_file=Path(args.env_file)).with_overrides(
            host=args.host,
            port=args.port,
            provider=args.provider,
            backend=args.backend,
            model=args.model,
            device=args.device,
        )
    except ConfigError as exc:
        print(f"Configuração inválida: {exc}", file=sys.stderr)
        return 2

    logging.basicConfig(
        level=getattr(logging, settings.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    from .providers import create_provider

    provider = create_provider(settings)
    if args.check is not None:
        return _check(settings, provider, args.check)
    return _serve(settings, provider)


def _serve(settings: Settings, provider) -> int:
    import uvicorn

    from .server import create_app, load_provider

    if not _is_loopback(settings.host):
        log.warning(
            "O serviço vai aceitar conexões de outras máquinas em %s. Ele não tem senha: "
            "use só numa rede em que você confia.",
            settings.host,
        )
    if getattr(provider, "loads_on_main_thread", False):
        # vLLM: built on the main thread before serving, as the official
        # streaming demo does. /health only answers once this is over.
        log.info("carregando o modelo com o vLLM antes de abrir a porta…")
        app = create_app(settings, provider, preload=False)
        load_provider(app.state.service)
    else:
        app = create_app(settings, provider)
    log.info("ouvindo em http://%s:%d (WebSocket /v1/dictation)", settings.host, settings.port)
    uvicorn.run(app, host=settings.host, port=settings.port, log_level=settings.log_level, ws_ping_interval=20)
    return 0


def _check(settings: Settings, provider, wav_path: str) -> int:
    import numpy as np

    from . import languages
    from .audio import read_wav, samples_to_ms
    from .postprocess import format_transcript
    from .server import ServiceState, load_provider

    state = ServiceState(settings, provider)
    load_provider(state)
    print(json.dumps(state.health(), ensure_ascii=False, indent=2))
    if not state.ready:
        return 1
    if wav_path:
        samples = read_wav(Path(wav_path).read_bytes())
    else:
        samples = np.zeros(16_000, dtype=np.float32)
    lang = languages.resolve(settings.language)
    started = time.monotonic()
    text = format_transcript(provider.transcribe(samples, lang))
    elapsed = time.monotonic() - started
    print(f"áudio: {samples_to_ms(samples.size)} ms · processamento: {elapsed * 1000:.0f} ms")
    print(f"texto: {text!r}")
    return 0


def _is_loopback(host: str) -> bool:
    if host in ("localhost", ""):
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


if __name__ == "__main__":
    sys.exit(main())
