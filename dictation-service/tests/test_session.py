import asyncio
import unittest

from notchy_dictation.languages import PT_BR
from notchy_dictation.session import DictationSession, SessionFailed

from fakes import FakeProvider, pcm_bytes, settings


class SessionTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.sent = []

        async def send(msg):
            self.sent.append(msg)

        self.send = send

    async def make(self, provider, **changes):
        session = DictationSession(provider, settings(**changes), PT_BR, self.send)
        await session.open()
        return session

    def partials(self):
        return [m for m in self.sent if m["type"] == "partial"]

    async def test_streaming_partials_grow_and_the_tail_reaches_the_final(self):
        provider = FakeProvider(streaming=True, chunk_samples=1600)  # a word per 100 ms
        session = await self.make(provider)
        for _ in range(5):
            await session.feed(pcm_bytes(0.1))
            await asyncio.sleep(0.01)
        await session.feed(pcm_bytes(0.05))  # half a word: only finish can hear it
        final = await session.finish()

        texts = [m["text"] for m in self.partials()]
        self.assertTrue(texts)
        self.assertEqual(len(texts), len(set(texts)), "a partial was sent twice")
        for earlier, later in zip(texts, texts[1:]):
            self.assertTrue(later.startswith(earlier), "each partial is the whole text so far")
        seqs = [m["seq"] for m in self.partials()]
        self.assertEqual(seqs, sorted(set(seqs)))
        self.assertEqual(final["text"], "Olá este é um teste do.")
        self.assertEqual(final["audio_ms"], 550)
        self.assertFalse(final["truncated"])
        self.assertTrue(provider.streams[0].closed)
        self.assertEqual(self.sent[-1]["type"], "partial")  # the session returns the final; the server sends it

    async def test_offline_sends_no_partial_and_hears_everything(self):
        provider = FakeProvider(streaming=False)
        session = await self.make(provider)
        for _ in range(10):
            await session.feed(pcm_bytes(0.1))
        final = await session.finish()
        self.assertEqual(self.partials(), [])
        self.assertEqual(final["text"], "Ouvi 16000 amostras")

    async def test_frames_split_on_an_odd_byte_are_joined(self):
        provider = FakeProvider(streaming=False)
        session = await self.make(provider)
        data = pcm_bytes(0.1)
        await session.feed(data[:1001])
        await session.feed(data[1001:])
        self.assertEqual((await session.finish())["text"], "Ouvi 1600 amostras")

    async def test_the_cap_truncates_and_says_so(self):
        provider = FakeProvider(streaming=False)
        session = await self.make(provider, max_seconds=0.25)
        self.assertTrue(await session.feed(pcm_bytes(0.2)))
        self.assertFalse(await session.feed(pcm_bytes(0.2)))
        final = await session.finish()
        self.assertTrue(final["truncated"])
        self.assertEqual(final["audio_ms"], 250)
        self.assertEqual(final["text"], "Ouvi 4000 amostras")

    async def test_a_failure_while_streaming_is_reported_once(self):
        provider = FakeProvider(streaming=True, fail_on_feed=1)
        session = await self.make(provider)
        await session.feed(pcm_bytes(0.1))
        for _ in range(100):
            if session.failure:
                break
            await asyncio.sleep(0.01)
        self.assertIsNotNone(session.failure)
        self.assertEqual(session.failure.code, "internal")
        self.assertEqual([m["type"] for m in self.sent], ["error"])
        with self.assertRaises(SessionFailed):
            await session.finish()

    async def test_cancel_drops_everything(self):
        provider = FakeProvider(streaming=True)
        session = await self.make(provider)
        await session.feed(pcm_bytes(0.3))
        await session.cancel()
        self.assertTrue(provider.streams[0].closed)
        self.assertFalse(provider.streams[0].finished)
        self.assertNotIn("final", [m["type"] for m in self.sent])


if __name__ == "__main__":
    unittest.main()
