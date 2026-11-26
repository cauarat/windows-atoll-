package com.cauarati.notchy

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * How a link that died quietly is noticed, checked where a unit test can see it: the wiring and the permissions. Nothing keeps the link
 * up in the background any more (no foreground service, no alarm, no wake lock): it lives while the app does.
 */
class LinkWatchSourceTest {
    private fun src(path: String) = File("src/main/kotlin/com/cauarati/notchy/$path").readText()
    private val manifest get() = File("src/main/AndroidManifest.xml").readText()
    private val all get() = File("src/main/kotlin").walkTopDown().filter { it.extension == "kt" }.joinToString("\n") { it.readText() }

    @Test fun nothingRunsInTheBackground() {
        for (p in listOf("FOREGROUND_SERVICE", "WAKE_LOCK", "POST_NOTIFICATIONS", "SYSTEM_ALERT_WINDOW", "RECEIVE_BOOT_COMPLETED", "SCHEDULE_EXACT_ALARM")) {
            assertFalse("the manifest asks for $p", manifest.contains("android.permission.$p\""))
        }
        assertFalse("no service", manifest.contains("<service"))
        assertFalse("no receiver", manifest.contains("<receiver"))
        assertFalse("no wake lock", all.contains("newWakeLock("))
        assertFalse("no alarm", all.contains("AlarmManager"))
        assertFalse("no foreground service", all.contains("startForeground"))
    }

    @Test fun theWatchersLiveExactlyAsLongAsThePairing() {
        val model = src("app/AppModel.kt")
        val connect = model.substringAfter("private fun connect(p: PairingPayload)").substringBefore("/** The saved address")
        assertTrue(connect.contains("screenWatch.start()") && connect.contains("netWatch.start()"))
        val stop = model.substringAfter("private fun stopLink()").substringBefore("// ── LinkListener")
        assertTrue(stop.contains("screenWatch.stop()") && stop.contains("netWatch.stop()"))
    }

    @Test fun everyWakeUpGoesThroughThePolicy() {
        val model = src("app/AppModel.kt")
        assertTrue(model.contains("ReconnectPolicy.decide("))
        assertTrue(model.contains("onWake(Wake.NEW_NETWORK)") && model.contains("onWake(Wake.SCREEN_ON)"))
        assertTrue("a network that appears is looked at, not only Wi-Fi", src("app/NetworkWatch.kt").contains("onAvailable(network: Network) { changed(); onNewNetwork() }"))
    }

    @Test fun theLinkAsksForAPongAtEveryCheckAndKeepsTheSystemsOwnProbeToo() {
        val client = src("link/LinkClient.kt")
        assertTrue(client.contains("override fun checkNow()"))
        assertTrue(client.contains("s.keepAlive = true"))
    }

    @Test fun cantConnectIsInTheComputerPanelOnlyWhenPaired() {
        val settings = src("ui/SettingsScreens.kt")
        val paired = settings.substringAfter("Mode.PAIRED -> {").substringBefore("Mode.NONE ->")
        assertTrue(paired.contains("LinkRow(stringResource(R.string.diag_title), onDiagnostics)"))
        assertFalse(settings.substringAfter("Mode.NONE ->").substringBefore("SectionHeading").contains("diag_title"))
    }

    @Test fun theDiagnosticsScreenIsNotSecretButTheReportMasksTheAddress() {
        assertTrue(src("app/AppModel.kt").contains("Diagnostics.maskHost(it.host)"))
        assertFalse(src("ui/DiagnosticsScreen.kt").contains("p.token") || src("ui/DiagnosticsScreen.kt").contains("certSha256"))
    }
}
