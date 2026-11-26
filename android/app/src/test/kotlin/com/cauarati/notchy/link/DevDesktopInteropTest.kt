package com.cauarati.notchy.link

import com.cauarati.notchy.ReferenceFiles
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * The real [LinkClient] against android/tools/dev-desktop.mjs, a separate implementation of the
 * protocol (Node's TLS stack, its own certificate). Skipped when node or openssl is missing.
 */
class DevDesktopInteropTest {
    private var proc: Process? = null
    private val lines = LinkedBlockingQueue<String>()

    @After fun cleanup() { proc?.destroyForcibly() }

    // `openssl --version` is not a command (it is `openssl version`): the old check made these tests skip everywhere.
    private fun have(cmd: String, versionArg: String = "--version") = try {
        ProcessBuilder(cmd, versionArg).redirectErrorStream(true).start().also { it.inputStream.readBytes() }.waitFor() == 0
    } catch (_: Exception) { false }

    private fun startDesktop(vararg extra: String): JSONObject {
        assumeTrue("node not available", have("node"))
        assumeTrue("openssl not available", have("openssl", "version"))
        val script = ReferenceFiles.file("android/tools/dev-desktop.mjs").absolutePath
        proc = ProcessBuilder(listOf("node", script, "--host", "127.0.0.1", "--port", "0", "--quiet") + extra)
            .redirectErrorStream(true).start()
        Thread {
            BufferedReader(InputStreamReader(proc!!.inputStream)).forEachLine { lines.add(it) }
        }.apply { isDaemon = true; start() }
        val first = lines.poll(20, TimeUnit.SECONDS)
        assertNotNull("dev desktop did not start", first)
        return JSONObject(first!!)
    }

    /** The desktop's log lines until one matches (it is returned), or null after [seconds]. */
    private fun desktopLogs(seconds: Long = 10, match: (String) -> Boolean): String? {
        val deadline = System.currentTimeMillis() + seconds * 1000
        while (System.currentTimeMillis() < deadline) {
            val l = lines.poll(200, TimeUnit.MILLISECONDS) ?: continue
            if (match(l)) return l
        }
        return null
    }

    /** SIGSTOP / SIGCONT: a desktop that is still there but answers nothing, like a computer that went to sleep. */
    // The pid comes from the script: android.jar, which these tests compile against, has no Process.pid().
    private fun signal(info: JSONObject, sig: String) = try {
        ProcessBuilder("kill", "-$sig", info.getLong("pid").toString()).redirectErrorStream(true).start().waitFor() == 0
    } catch (_: Exception) { false }

    private class Rec : LinkListener {
        val welcome = LinkedBlockingQueue<String>()
        val errors = LinkedBlockingQueue<String>()
        val lost = LinkedBlockingQueue<LostReason>()
        override fun onWelcome(desktopName: String, os: String) { welcome.add(desktopName) }
        override fun onError(code: String, message: String) { errors.add(code) }
        override fun onLinkLost(reason: LostReason) { lost.add(reason) }
        val caps = LinkedBlockingQueue<Set<String>>()
        val chat = LinkedBlockingQueue<String>()
        override fun onCaps(caps: Set<String>) { this.caps.add(caps) }
        override fun onChatModels(models: List<ChatModel>) { chat.add("models:" + models.joinToString(",") { it.id }) }
        override fun onChatDelta(id: String, text: String) { chat.add("delta:$id:$text") }
        override fun onChatDone(id: String, text: String?) { chat.add("done:$id:${text ?: "-"}") }
        override fun onChatError(id: String, reason: String, message: String) { chat.add("error:$id:$reason") }

        /** Everything of one answer until its end. */
        fun answer(id: String, seconds: Long = 10): Pair<String, String> {
            val text = StringBuilder()
            val deadline = System.currentTimeMillis() + seconds * 1000
            while (System.currentTimeMillis() < deadline) {
                val e = chat.poll(200, TimeUnit.MILLISECONDS) ?: continue
                when {
                    e.startsWith("delta:$id:") -> text.append(e.removePrefix("delta:$id:"))
                    e.startsWith("done:$id:") -> return text.toString() to ("done:" + e.removePrefix("done:$id:"))
                    e.startsWith("error:$id:") -> return text.toString() to e
                }
            }
            error("no end of answer for $id")
        }
    }

    // The Node desktop sends nothing of its own between answers, so the pings (and their pongs) keep the 5 s read timeout away.
    private fun chatClient(info: JSONObject, rec: Rec, caps: List<String> = Protocol.CAPABILITIES): LinkClient =
        LinkClient(PairingPayload.parse(info.getString("link"))!!, "Interop Pixel", rec, readTimeoutMs = 5_000, pingEveryMs = 1_000, caps = caps)

    @Test fun pairsIsWelcomedAndSaysByeToTheNodeDesktop() {
        val info = startDesktop("--name", "Dev Mac")
        val pairing = PairingPayload.parse(info.getString("link"))
        assertNotNull("pairing link not parsed: ${info.getString("link")}", pairing)
        assertEquals(info.getString("fp"), pairing!!.certSha256)
        val rec = Rec()
        val client = LinkClient(pairing, "Interop Pixel", rec, readTimeoutMs = 5_000)
        try {
            client.start()
            assertEquals("Dev Mac", rec.welcome.poll(10, TimeUnit.SECONDS))
            assertEquals(emptySet<String>(), rec.caps.poll(10, TimeUnit.SECONDS))
            assertNotNull("desktop never logged the hello", desktopLogs { it == "HELLO ok device=\"Interop Pixel\"" })
        } finally {
            client.stop()
        }
        assertNotNull("desktop never got the bye", desktopLogs { it == "BYE" })
        assertNull(rec.lost.poll(1, TimeUnit.SECONDS))
    }

    @Test fun wrongTokenIsRejectedByTheNodeDesktop() {
        val info = startDesktop()
        val good = PairingPayload.parse(info.getString("link"))!!
        val rec = Rec()
        val client = LinkClient(good.copy(token = "x".repeat(24)), "Interop Pixel", rec, readTimeoutMs = 5_000)
        try {
            client.start()
            assertEquals("auth", rec.errors.poll(10, TimeUnit.SECONDS))
            assertTrue(rec.welcome.isEmpty())
            // `auth` is final: the first retry would come after 1 s, and the desktop never sees one.
            assertNotNull(desktopLogs { it == "AUTH rejected" })
            assertNull("the phone tried the wrong token again", desktopLogs(3) { it == "AUTH rejected" })
        } finally {
            client.stop()
        }
    }

    // ── liveness, against the Node desktop's pong ───────────────────────────────────

    @Test fun aLiveNodeDesktopAnswersTheCheckAndTheLinkStays() {
        val info = startDesktop()
        val rec = Rec()
        // No ping of its own and a long read timeout: only the check's pong can prove the link is alive.
        val client = LinkClient(PairingPayload.parse(info.getString("link"))!!, "Interop Pixel", rec,
            readTimeoutMs = 30_000, pingEveryMs = 60_000, pongWaitMs = 1_000)
        try {
            client.start()
            assertNotNull(rec.welcome.poll(10, TimeUnit.SECONDS))
            Thread.sleep(100) // the check must ask after the welcome came in
            client.checkNow()
            assertNull("the link was given up although the desktop answered", rec.lost.poll(3, TimeUnit.SECONDS))
            assertNull(rec.welcome.poll(1, TimeUnit.SECONDS))
        } finally {
            client.stop()
        }
    }

    @Test fun aFrozenNodeDesktopFailsTheCheckAndTheLinkComesBack() {
        val info = startDesktop()
        val rec = Rec()
        val client = LinkClient(PairingPayload.parse(info.getString("link"))!!, "Interop Pixel", rec,
            readTimeoutMs = 30_000, pingEveryMs = 60_000, pongWaitMs = 1_000)
        try {
            client.start()
            assertNotNull(rec.welcome.poll(10, TimeUnit.SECONDS))
            assumeTrue("kill -STOP not available", signal(info, "STOP"))
            try {
                Thread.sleep(100)
                client.checkNow()
                assertEquals(LostReason.SILENT, rec.lost.poll(10, TimeUnit.SECONDS))
            } finally {
                signal(info, "CONT")
            }
            assertNotNull("the phone never came back", rec.welcome.poll(15, TimeUnit.SECONDS))
        } finally {
            client.stop()
        }
    }

    // ── chat, against the fake provider of the Node desktop ─────────────────────────

    @Test fun chatWorksAgainstTheFakeProvider() {
        val info = startDesktop("--fake-chat")
        val rec = Rec()
        val client = chatClient(info, rec)
        try {
            client.start()
            assertEquals(setOf("chat"), rec.caps.poll(10, TimeUnit.SECONDS))
            assertEquals("models:fake/echo,fake/other", rec.chat.poll(10, TimeUnit.SECONDS))
            assertTrue(client.chatSend("c1", "fake/echo", "hello there"))
            val (text, end) = rec.answer("c1")
            assertEquals("Fake answer to: hello there", text)
            assertEquals("done:-", end)

            // the desktop's own refusals arrive as codes
            client.chatSend("c2", "fake/echo", "/error")
            assertEquals("error:c2:provider", rec.answer("c2").second)
            client.chatSend("c3", "fake/echo", "/auth")
            assertEquals("error:c3:auth", rec.answer("c3").second)
            client.chatSend("c4", "not/allowed", "hi")
            assertEquals("error:c4:not_allowed", rec.answer("c4").second)
            client.chatSend("c5", "fake/echo", "x".repeat(Protocol.CHAT_MAX_TEXT + 1))
            assertEquals("error:c5:too_long", rec.answer("c5").second)

            // a long answer arrives in pieces that add up
            client.chatSend("c6", "fake/echo", "/long")
            val (long, longEnd) = rec.answer("c6")
            assertEquals("done:-", longEnd)
            assertEquals(750 * "Lorem ipsum dolor sit amet. ".length, long.length)

            // a rewritten answer is replaced by the final one
            client.chatSend("c7", "fake/echo", "/rewrite")
            assertEquals("done:Answer", rec.answer("c7").second)
        } finally {
            client.stop()
        }
    }

    @Test fun oneAnswerAtATimeAndCancelStopsIt() {
        val info = startDesktop("--fake-chat")
        val rec = Rec()
        val client = chatClient(info, rec)
        try {
            client.start()
            assertNotNull(rec.caps.poll(10, TimeUnit.SECONDS))
            client.chatSend("s1", "fake/echo", "/slow")
            assertTrue("never started", generateSequence { rec.chat.poll(5, TimeUnit.SECONDS) }.take(20).any { it.startsWith("delta:s1:") })
            client.chatSend("s2", "fake/echo", "second")
            assertEquals("error:s2:busy", rec.answer("s2").second)
            client.chatCancel("s1")
            assertEquals("error:s1:canceled", rec.answer("s1").second)
            client.chatSend("s3", "fake/echo", "after")
            assertEquals("Fake answer to: after", rec.answer("s3").first)
        } finally {
            client.stop()
        }
    }

    @Test fun anOlderAppOrAnOlderComputerSeesNoChat() {
        // The desktop has chat but the app asks for nothing (an older app): not offered, nothing sent.
        val info = startDesktop("--fake-chat")
        val rec = Rec()
        val client = chatClient(info, rec, caps = emptyList())
        try {
            client.start()
            assertEquals(emptySet<String>(), rec.caps.poll(10, TimeUnit.SECONDS))
            client.chatSend("o1", "fake/echo", "hi")
            assertNull(rec.chat.poll(1, TimeUnit.SECONDS))
        } finally {
            client.stop()
        }
    }

    @Test fun aDesktopWithoutTheFakeProviderOffersNoChat() {
        val info = startDesktop()
        val rec = Rec()
        val client = chatClient(info, rec)
        try {
            client.start()
            assertEquals(emptySet<String>(), rec.caps.poll(10, TimeUnit.SECONDS))
            assertNull(rec.chat.poll(1, TimeUnit.SECONDS))
        } finally {
            client.stop()
        }
    }
}
