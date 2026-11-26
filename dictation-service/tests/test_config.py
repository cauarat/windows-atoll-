import tempfile
import unittest
from pathlib import Path

from notchy_dictation.config import ConfigError, Settings, read_env_file


class SettingsTests(unittest.TestCase):
    def test_defaults(self):
        s = Settings.from_env(environ={})
        self.assertEqual((s.host, s.port), ("127.0.0.1", 8765))
        self.assertEqual(s.provider, "qwen3-asr")
        self.assertEqual(s.model, "Qwen/Qwen3-ASR-1.7B")
        self.assertEqual(s.language, "pt-BR")
        self.assertEqual((s.chunk_seconds, s.unfixed_chunks, s.unfixed_tokens), (1.0, 4, 5))
        self.assertEqual(s.allowed_origins, ())

    def test_environment_overrides(self):
        s = Settings.from_env(environ={
            "DICTATION_PORT": "9000",
            "DICTATION_BACKEND": "transformers",
            "DICTATION_CHUNK_SECONDS": "0,5",
            "DICTATION_ALLOWED_ORIGINS": "tauri://localhost, http://tauri.localhost",
            "VOXTRAL_URL": "ws://gpu:8000/v1/realtime",
        })
        self.assertEqual(s.port, 9000)
        self.assertEqual(s.backend, "transformers")
        self.assertEqual(s.chunk_seconds, 0.5)
        self.assertEqual(s.allowed_origins, ("tauri://localhost", "http://tauri.localhost"))
        self.assertEqual(s.voxtral_url, "ws://gpu:8000/v1/realtime")

    def test_env_file_is_below_the_environment(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / ".env"
            path.write_text('# comment\nDICTATION_PORT=7000\nexport DICTATION_MODEL="Qwen/Qwen3-ASR-0.6B"\n\n')
            self.assertEqual(read_env_file(path)["DICTATION_MODEL"], "Qwen/Qwen3-ASR-0.6B")
            s = Settings.from_env(environ={"DICTATION_PORT": "7100"}, env_file=path)
            self.assertEqual(s.port, 7100)
            self.assertEqual(s.model, "Qwen/Qwen3-ASR-0.6B")

    def test_rejects_bad_values(self):
        for env in ({"DICTATION_PROVIDER": "openai"}, {"DICTATION_BACKEND": "metal"},
                    {"DICTATION_PORT": "abc"}, {"DICTATION_PORT": "70000"},
                    {"DICTATION_GPU_MEMORY_UTILIZATION": "1.5"}, {"DICTATION_DTYPE": "int4"}):
            with self.assertRaises(ConfigError, msg=env):
                Settings.from_env(environ=env)

    def test_with_overrides_skips_none(self):
        s = Settings.from_env(environ={}).with_overrides(port=None, backend="vllm")
        self.assertEqual((s.port, s.backend), (8765, "vllm"))


if __name__ == "__main__":
    unittest.main()
