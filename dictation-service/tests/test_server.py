import time
import unittest

import numpy as np

try:
    from fastapi.testclient import TestClient
    from starlette.websockets import WebSocketDisconnect
except ImportError:  # httpx missing: pip install -e ".[test]"
    TestClient = None

from notchy_dictation.server import create_app

from fakes import FakeProvider, fixture, pcm_bytes, settings
from test_audio_protocol import wav_bytes

START = fixture()["protocol"]["start"]


def wait_for(client, status, timeout=3.0):
    deadline = time.monotonic() + timeout
    while True:
        health = client.get("/health").json()
        if health["status"] == status or time.monotonic() > deadline:
            return health
        time.sleep(0.02)


def receive_until_done(ws):
    messages = []
    while True:
        msg = ws.receive_json()
        messages.append(msg)
        if msg["type"] in ("final", "error"):
            return messages


@unittest.skipIf(TestClient is None, "httpx não instalado (pip install -e '.[test]')")
class ServerTests(unittest.TestCase):
    def client(self, provider, **changes):
        return TestClient(create_app(settings(**changes), provider))

    def test_health_says_what_runs(self):
        with self.client(FakeProvider(streaming=True)) as c:
            health = wait_for(c, "ready")
        self.assertTrue(health["ready"])
        self.assertEqual(health["protocol"], 1)
        self.assertEqual((health["provider"], health["model"], health["streaming"]), ("fake", "fake/model", True))
        self.assertEqual((health["language"], health["language_label"]), ("pt-BR", "Português (Brasil)"))
        self.assertIsNone(health["error"])

    def test_a_model_that_cannot_load_is_explained(self):
        with self.client(FakeProvider(fail_on_load="Esta máquina não tem CUDA.")) as c:
            health = wait_for(c, "error")
            self.assertEqual(health["error"], "Esta máquina não tem CUDA.")
            with c.websocket_connect("/v1/dictation") as ws:
                ws.send_json(START)
                msg = ws.receive_json()
            self.assertEqual((msg["type"], msg["code"]), ("error", "model_failed"))
            self.assertEqual(c.post("/v1/transcribe", content=b"").status_code, 503)

    def test_web_pages_are_refused(self):
        evil = {"Origin": "https://example.com"}
        with self.client(FakeProvider()) as c:
            self.assertEqual(c.get("/health", headers=evil).status_code, 403)
            with self.assertRaises(WebSocketDisconnect):
                with c.websocket_connect("/v1/dictation", headers=evil) as ws:
                    ws.receive_json()
        with self.client(FakeProvider(), allowed_origins=("tauri://localhost",)) as c:
            self.assertEqual(c.get("/health", headers={"Origin": "tauri://localhost"}).status_code, 200)

    def test_streaming_dictation(self):
        with self.client(FakeProvider(streaming=True, chunk_samples=1600)) as c:
            wait_for(c, "ready")
            with c.websocket_connect("/v1/dictation") as ws:
                ws.send_json(START)
                ready = ws.receive_json()
                for _ in range(3):
                    ws.send_bytes(pcm_bytes(0.1))
                ws.send_bytes(pcm_bytes(0.05))
                ws.send_json({"type": "stop"})
                messages = receive_until_done(ws)
        self.assertEqual((ready["type"], ready["streaming"], ready["language"]), ("ready", True, "pt-BR"))
        self.assertTrue(any(m["type"] == "partial" for m in messages))
        final = messages[-1]
        self.assertEqual((final["type"], final["text"], final["audio_ms"]), ("final", "Olá este é um.", 350))

    def test_offline_dictation(self):
        with self.client(FakeProvider(streaming=False)) as c:
            wait_for(c, "ready")
            with c.websocket_connect("/v1/dictation") as ws:
                ws.send_json(START)
                self.assertFalse(ws.receive_json()["streaming"])
                ws.send_bytes(pcm_bytes(0.5))
                ws.send_json({"type": "stop"})
                messages = receive_until_done(ws)
        self.assertEqual([m["type"] for m in messages], ["final"])
        self.assertEqual(messages[0]["text"], "Ouvi 8000 amostras")

    def test_bad_starts(self):
        cases = [
            (lambda ws: ws.send_bytes(b"\x00\x00"), "bad_request"),
            (lambda ws: ws.send_json({"type": "stop"}), "bad_request"),
            (lambda ws: ws.send_json({**START, "sample_rate": 44100}), "unsupported_audio"),
            (lambda ws: ws.send_json({**START, "language": "de-DE"}), "unsupported_language"),
        ]
        with self.client(FakeProvider()) as c:
            wait_for(c, "ready")
            for send, code in cases:
                with c.websocket_connect("/v1/dictation") as ws:
                    send(ws)
                    self.assertEqual(ws.receive_json()["code"], code)

    def test_a_cold_model_is_warmed_while_the_person_speaks(self):
        provider = FakeProvider(streaming=False)
        provider.warms = True
        app = create_app(settings(), provider)
        with TestClient(app) as c:
            wait_for(c, "ready")
            self.assertEqual(provider.warm_ups, 1)  # once on load, before "ready"
            app.state.service.last_used -= 60  # a minute with nobody dictating
            with c.websocket_connect("/v1/dictation") as ws:
                ws.send_json(START)
                ws.receive_json()
                ws.send_bytes(pcm_bytes(0.2))
                ws.send_json({"type": "stop"})
                receive_until_done(ws)
            self.assertEqual(provider.warm_ups, 2)
            with c.websocket_connect("/v1/dictation") as ws:  # straight after: already warm
                ws.send_json(START)
                ws.receive_json()
                ws.send_json({"type": "stop"})
                receive_until_done(ws)
            self.assertEqual(provider.warm_ups, 2)

    def test_keep_warm_interval(self):
        provider = FakeProvider()
        state = create_app(settings(), provider).state.service
        self.assertEqual(state.keep_warm_interval(), 0)  # nothing to warm
        provider.warms = True
        self.assertEqual(state.keep_warm_interval(), 0)  # automatic: only on Apple silicon (device "cpu" here)
        state = create_app(settings(keep_warm_seconds=12), provider).state.service
        self.assertEqual(state.keep_warm_interval(), 12)

    def test_transcribe_a_wav(self):
        with self.client(FakeProvider(streaming=False)) as c:
            wait_for(c, "ready")
            ok = c.post("/v1/transcribe", content=wav_bytes(np.full(32000, 0.1, dtype=np.float32), 32000),
                        headers={"Content-Type": "audio/wav"})
            bad = c.post("/v1/transcribe", content=b"not audio")
            unknown = c.post("/v1/transcribe?language=fr-FR", content=b"")
        self.assertEqual(ok.status_code, 200)
        self.assertEqual((ok.json()["text"], ok.json()["audio_ms"]), ("Ouvi 16000 amostras", 1000))
        self.assertEqual((bad.status_code, bad.json()["code"]), (415, "unsupported_audio"))
        self.assertEqual(unknown.json()["code"], "unsupported_language")


if __name__ == "__main__":
    unittest.main()
