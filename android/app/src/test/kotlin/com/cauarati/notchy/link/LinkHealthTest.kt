package com.cauarati.notchy.link

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LinkHealthTest {
    private val min = 60_000L

    @Test fun theTimeAgoIsInPlainWords() {
        assertEquals("less than a minute", LinkHealthText.ago(0))
        assertEquals("less than a minute", LinkHealthText.ago(59_999))
        assertEquals("1 min", LinkHealthText.ago(min))
        assertEquals("2 min", LinkHealthText.ago(2 * min + 5_000))
        assertEquals("59 min", LinkHealthText.ago(59 * min))
        assertEquals("1 h", LinkHealthText.ago(60 * min))
        assertEquals("1 h 5 min", LinkHealthText.ago(65 * min))
        assertEquals("3 h", LinkHealthText.ago(180 * min))
        assertEquals("less than a minute", LinkHealthText.ago(-5))
    }

    @Test fun homeSaysWhatHappenedAndHowLongAgo() {
        val h = LinkHealth().lost(atMs = 1_000_000, why = LostReason.SILENT)
        val (head, why) = LinkHealthText.lines(connected = false, health = h, nowMs = 1_000_000 + 2 * min)!!
        assertEquals("Connection lost 2 min ago, reconnecting", head)
        assertTrue(why.contains("phone slept"))
        assertTrue(LinkHealthText.lines(false, h.copy(reason = LostReason.CLOSED), 1_000_000)!!.second.contains("closed"))
        assertTrue(LinkHealthText.lines(false, h.copy(reason = LostReason.NETWORK), 1_000_000)!!.second.contains("cannot reach the computer"))
    }

    @Test fun theCauseIsNamedFromWhatThePhoneKnows() {
        // Not on Wi-Fi: say that, not "the network dropped".
        assertTrue(LinkHealthText.why(LostReason.NETWORK, wifiUp = false).contains("not on Wi-Fi"))
        // On Wi-Fi but unreachable: the computer's side is a short list of what to look at.
        val reach = LinkHealthText.why(LostReason.NETWORK, wifiUp = true)
        assertTrue(reach.contains("closed there") && reach.contains("phone link may be off") && reach.contains("another network"))
        assertTrue(LinkHealthText.why(LostReason.CLOSED).contains("closed or restarted"))
        assertEquals("", LinkHealthText.why(null))
        assertFalse(LinkHealthText.why(LostReason.NETWORK, true).contains("dropped"))
        assertTrue(LinkHealthText.lines(false, LinkHealth().lost(0, LostReason.NETWORK), 0, wifiUp = false)!!.second.contains("not on Wi-Fi"))
    }

    @Test fun nothingIsSaidWhenConnectedOrWhenNothingWasLost() {
        val h = LinkHealth().lost(1_000, LostReason.NETWORK)
        assertNull(LinkHealthText.lines(connected = true, health = h, nowMs = 5_000))
        assertNull(LinkHealthText.lines(connected = false, health = LinkHealth(), nowMs = 5_000))
        assertNull(LinkHealthText.lines(connected = false, health = h.recovered(), nowMs = 5_000))
    }

    @Test fun repeatedFailuresAreCountedAfterTheThird() {
        val h = LinkHealth().lost(0, LostReason.NETWORK)
        assertFalse(LinkHealthText.lines(false, h.failedAttempt(2), 0)!!.first.contains("tries"))
        assertTrue(LinkHealthText.lines(false, h.failedAttempt(5), 0)!!.first.endsWith("(5 tries)"))
    }

    @Test fun aRecoveryEndsTheStory() {
        val h = LinkHealth().lost(2, LostReason.SILENT).failedAttempt(4).recovered()
        assertNull(h.lostAtMs)
        assertNull(h.reason)
        assertEquals(0, h.attempts)
    }
}
