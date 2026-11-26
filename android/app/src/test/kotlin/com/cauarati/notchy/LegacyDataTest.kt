package com.cauarati.notchy

import com.cauarati.notchy.app.LegacyData
import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** What versions with coding agents left on the phone is forgotten, and nothing the app still uses is touched. */
class LegacyDataTest {
    private val main = File("src/main/kotlin/com/cauarati/notchy")
    private val code get() = main.walkTopDown().filter { it.extension == "kt" && it.name != "LegacyData.kt" }.joinToString("\n") { it.readText() }

    @Test fun theDecisionListAndTheNotificationChannelsGo() {
        assertTrue("the list of Allow/Deny decisions kept the start of each command", "decisions" in LegacyData.UI_KEYS)
        val src = File(main, "app/LegacyData.kt").readText()
        assertTrue(src.contains("deleteNotificationChannel(it.id)"))
        assertTrue("it runs at every start", File(main, "app/NotchyApp.kt").readText().contains("LegacyData.forget(this)"))
    }

    @Test fun noKeyTheAppStillUsesIsForgotten() {
        val code = code
        for (k in LegacyData.UI_KEYS) assertFalse("\"$k\" is still used", code.contains("\"$k\""))
        for (f in LegacyData.FILES) assertFalse("\"$f\" is still used", code.contains("\"$f\""))
    }
}
