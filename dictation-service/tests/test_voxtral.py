"""The Voxtral provider against a stand-in for vLLM's /v1/realtime, speaking
the protocol of vllm/entrypoints/speech_to_text/realtime/protocol.py."""

import base64
import json
import threading
import unittest

import numpy as np

try:
    from websockets.sync.server import serve
except ImportError:
    serve = None

from notchy_dictation.languages import PT_BR
from notchy_dictation.providers.base import ProviderUnavailable
from notchy_dictation.providers.voxtral_realtime import VoxtralRealtimeProvider

from fakes import settings

MODEL = "mistralai/Voxtral-Mini-4B-Realtime-2602"


def realtime_handler(ws):
    ws.send(json.dumps({"type": "session.created", "id": "sess-1", "created": 0}))
    started = False
    heard = 0
    for raw in ws:
        msg = json.loads(raw)
        kind = msg["type"]
        if kind == "session.update":
            if msg.get("model") != MODEL:
                ws.send(json.dumps({"type": "error", "error": "model not found", "code": "model_not_found"}))
        elif kind == "input_audio_buffer.commit" and not msg.get("final"):
            started = True
        elif kind == "input_audio_buffer.append":
            if not started:
                ws.send(json.dumps({"type": "error", "error": "not started"}))
                continue
            heard += len(base64.b64decode(msg["audio"])) // 2
            ws.send(json.dumps({"type": "transcription.delta", "delta": " palavra"}))
        elif kind == "input_audio_buffer.commit":
            ws.send(json.dumps({"type": "transcription.done", "text": f"ouvi {heard} amostras", "usage": None}))


@unittest.skipIf(serve is None, "websockets não instalado")
class VoxtralTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = serve(realtime_handler, "127.0.0.1", 0)
        cls.port = cls.server.socket.getsockname()[1]
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def provider(self, **changes):
        url = f"ws://127.0.0.1:{self.port}/v1/realtime"
        return VoxtralRealtimeProvider(settings(provider="voxtral-realtime", voxtral_url=url, **changes))

    def test_load_and_info(self):
        p = self.provider()
        p.load()
        info = p.info()
        self.assertEqual((info.provider, info.model, info.streaming), ("voxtral-realtime", MODEL, True))

    def test_a_model_the_server_does_not_serve(self):
        with self.assertRaises(ProviderUnavailable):
            self.provider(voxtral_model="mistralai/other").load()

    def test_nothing_listening_says_how_to_start_it(self):
        p = VoxtralRealtimeProvider(settings(provider="voxtral-realtime", voxtral_url="ws://127.0.0.1:9/v1/realtime"))
        with self.assertRaises(ProviderUnavailable) as ctx:
            p.load()
        self.assertIn("vllm serve mistralai/Voxtral-Mini-4B-Realtime-2602", str(ctx.exception))

    def test_a_dictation(self):
        stream = self.provider().open_stream(PT_BR)
        partials = []
        for _ in range(3):
            text = stream.feed(np.zeros(1600, dtype=np.float32))
            if text is not None:
                partials.append(text)
        final = stream.finish()
        stream.close()
        self.assertEqual(final, "ouvi 4800 amostras")
        for earlier, later in zip(partials, partials[1:]):
            self.assertTrue(later.startswith(earlier))


if __name__ == "__main__":
    unittest.main()
