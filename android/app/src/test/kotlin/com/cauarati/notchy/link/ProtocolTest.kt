package com.cauarati.notchy.link

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProtocolTest {
    private val fp = "0b2944f472c9dda6c1d369e7c161730641be8e67174c8eb67c887a2fe0ccd30d"

    @Test fun encodesClientMessages() {
        assertEquals("ping", JSONObject(Wire.encode(ClientMsg.Ping)).getString("type"))
        assertEquals("bye", JSONObject(Wire.encode(ClientMsg.Bye)).getString("type"))
        val hello = Wire.encode(ClientMsg.Hello(1, "tok", "Pixel"))
        assertTrue(hello.contains(""""type":"hello"""") && hello.contains(""""token":"tok""""))
        assertFalse("an app with no optional features sends the v1 hello unchanged", hello.contains("caps"))
    }

    @Test fun thePhoneOnlyAsksForChat() {
        assertEquals(listOf("chat"), Protocol.CAPABILITIES)
        val hello = JSONObject(Wire.encode(ClientMsg.Hello(1, "tok", "Pixel", Protocol.CAPABILITIES)))
        assertEquals(1, hello.getJSONArray("caps").length())
        assertEquals("chat", hello.getJSONArray("caps").getString(0))
    }

    @Test fun whatAnOlderComputerStillSendsIsIgnored() {
        // A computer from before the agents were removed may still send these: unknown types are dropped, by contract.
        val old = listOf(
            """{"type":"sessions","sessions":[{"pillId":"agent_codex","agent":"Codex","state":"working","statusText":"Editing","stepIndex":2,"stepCount":5,"updatedAt":1700}]}""",
            """{"type":"approval","pillId":"p","fingerprint":"$fp","tool":"Bash","command":"ls","createdAt":5}""",
            """{"type":"approvalResolved","fingerprint":"$fp"}""",
            """{"type":"question","pillId":"p","fingerprint":"$fp","createdAt":5,"questions":[{"question":"Which?","options":[{"label":"A"}]}]}""",
            """{"type":"diff","pillId":"p","fileId":1,"name":"a.kt","part":0,"parts":1,"lines":[["+","x"]]}""",
            """{"type":"usage","claude":{"fiveHour":{"pct":40,"resetsAt":1700}}}""",
            """{"type":"prefs","outfit":"crown"}""",
        )
        for (line in old) assertNull(line, Wire.decodeServer(line))
    }

    @Test fun aWelcomeWithRetiredCapsStillWelcomes() {
        val m = Wire.decodeServer("""{"type":"welcome","v":1,"desktop":"PC","os":"macos","caps":["chat","details","diffs","answers","character"]}""") as ServerMsg.Welcome
        assertEquals("PC", m.desktopName)
        assertTrue("chat" in m.caps)
    }

    @Test fun malformedInputNeverThrows() {
        for (bad in listOf("", "not json", "{}", """{"type":1}""", """{"type":"sessions"}""", """{"type":"welcome"}""", """{"type":"nope"}""", "[]")) {
            assertNull(bad, Wire.decodeServer(bad))
        }
    }

    @Test fun oversizeLineIsRejected() {
        assertNull(Wire.decodeServer("""{"type":"pong","pad":"${"x".repeat(Protocol.MAX_LINE_BYTES)}"}"""))
    }

    @Test fun decodesSimpleMessages() {
        assertEquals(ServerMsg.Pong, Wire.decodeServer("""{"type":"pong"}"""))
        assertEquals(ServerMsg.Welcome(1, "PC", "windows"), Wire.decodeServer("""{"type":"welcome","v":1,"desktop":"PC","os":"windows"}"""))
        assertEquals(ServerMsg.Error("auth", "no"), Wire.decodeServer("""{"type":"error","code":"auth","message":"no"}"""))
    }

    @Test fun aCertificateFingerprintIsSixtyFourLowercaseHex() {
        assertTrue(Wire.isFingerprint(fp))
        assertFalse(Wire.isFingerprint(fp.uppercase()))
        assertFalse(Wire.isFingerprint(fp.dropLast(1)))
        assertFalse(Wire.isFingerprint("nothex"))
    }
}
