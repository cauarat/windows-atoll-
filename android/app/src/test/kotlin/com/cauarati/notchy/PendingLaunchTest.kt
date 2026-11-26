package com.cauarati.notchy

import com.cauarati.notchy.core.LaunchScreen
import com.cauarati.notchy.core.PendingLaunch
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingLaunchTest {
    private var now = 1_000L
    private val launch = PendingLaunch { now }

    private val main = "src/main/kotlin/com/cauarati/notchy/"
    private fun manifest() = File("src/main/AndroidManifest.xml").readText()

    @Test fun onlyTheNonExportedEntryActivityCanMakeARequest() {
        val callers = File(main).walkTopDown().filter { it.extension == "kt" }
            .filter { it.readText().contains("launch.requestScreen(") }.map { it.name }.toList()
        assertEquals(listOf("LaunchActivity.kt"), callers)
        val m = manifest()
        val entry = m.substringAfter("""android:name=".app.LaunchActivity"""").substringBefore("/>")
        assertTrue(entry.contains("""android:exported="false""""))
        assertTrue("it is the only way the request reaches the app", m.contains(".app.LaunchActivity"))
    }

    @Test fun everyOtherComponentWithAnIntentFilterIsTheLauncherOrTheShareTarget() {
        val m = manifest()
        val exported = Regex("""android:name="([^"]+)"[^>]*android:exported="true"""").findAll(m).map { it.groupValues[1] }.toSet()
        assertEquals(setOf(".MainActivity", ".app.ShareActivity"), exported)
    }

    // ── The screen slot (a shortcut) ───────────────────────────────────────────────────────────

    @Test fun aShortcutAsksForAScreenOnce() {
        launch.requestScreen(LaunchScreen.CHAT)
        assertEquals(LaunchScreen.CHAT, launch.takeScreen())
        assertNull("only once, and the slot is cleared", launch.takeScreen())
    }

    @Test fun nothingAskedMeansNoScreen() = assertNull(launch.takeScreen())

    @Test fun aStaleScreenRequestIsDropped() {
        launch.requestScreen(LaunchScreen.CHAT)
        now += PendingLaunch.TTL_MS + 1
        assertNull(launch.takeScreen())
        launch.requestScreen(LaunchScreen.PAIR)
        now += PendingLaunch.TTL_MS
        assertEquals(LaunchScreen.PAIR, launch.takeScreen())
    }

    @Test fun aNewerScreenRequestReplacesTheOlderOneAndNullClearsIt() {
        launch.requestScreen(LaunchScreen.CHAT)
        launch.requestScreen(LaunchScreen.PAIR)
        assertEquals(LaunchScreen.PAIR, launch.takeScreen())
        launch.requestScreen(LaunchScreen.CHAT)
        launch.requestScreen(null)
        assertNull(launch.takeScreen())
    }

    @Test fun theScreenSlotOnlyHoldsAValueOfTheClosedList() {
        val src = File("src/main/kotlin/com/cauarati/notchy/core/PendingLaunch.kt").readText()
        assertTrue(src.contains("fun requestScreen(which: LaunchScreen?)"))
        assertTrue(src.contains("fun takeScreen(): LaunchScreen?"))
        assertTrue(src.contains("private var screen: LaunchScreen?"))
    }

    @Test fun theExportedActivityOnlyAsksTheModelForTheScreenToOpen() {
        val src = File(main + "MainActivity.kt").readText()
        assertTrue(src.contains("model.launch.takeScreen()"))
        for (bad in listOf("EXTRA_SCREEN", "getStringExtra", "getBooleanExtra", "getExtras", "intent.extras", "hasExtra")) assertFalse("MainActivity reads $bad", src.contains(bad))
    }
}
