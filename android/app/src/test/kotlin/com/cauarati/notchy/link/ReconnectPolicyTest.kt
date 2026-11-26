package com.cauarati.notchy.link

import com.cauarati.notchy.link.ReconnectPolicy.Action
import org.junit.Assert.assertEquals
import org.junit.Test

class ReconnectPolicyTest {
    private fun d(e: Wake, paired: Boolean = true, connected: Boolean = false, wifi: Boolean = true) =
        ReconnectPolicy.decide(e, paired, connected, wifi)

    @Test fun nothingHappensWithoutAPairing() {
        for (e in Wake.values()) assertEquals(Action.NONE, d(e, paired = false))
    }

    @Test fun whenConnectedEveryWakeUpAsksForAPongInsteadOfTrustingTheSocket() {
        for (e in listOf(Wake.SCREEN_ON, Wake.NEW_NETWORK)) assertEquals("$e", Action.CHECK_NOW, d(e, connected = true))
    }

    @Test fun whenNotConnectedThoseWakeUpsReconnectAtOnce() {
        for (e in listOf(Wake.SCREEN_ON, Wake.NEW_NETWORK)) assertEquals("$e", Action.RETRY_NOW, d(e, connected = false))
    }

    @Test fun withoutAUsableNetworkTheNetworkWakeUpDoesNotBurnBatteryButTheScreenStillTries() {
        assertEquals(Action.NONE, d(Wake.NEW_NETWORK, wifi = false))
        assertEquals("the user just woke the phone: try", Action.RETRY_NOW, d(Wake.SCREEN_ON, wifi = false))
    }

    @Test fun losingTheNetworkOrTurningTheScreenOffNeedsNothing() {
        for (connected in listOf(true, false)) {
            assertEquals(Action.NONE, d(Wake.NETWORK_LOST, connected = connected))
            assertEquals(Action.NONE, d(Wake.SCREEN_OFF, connected = connected))
        }
    }
}
