package com.cauarati.notchy

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Source-level guards for the session detail screen (Compose cannot be rendered in a JVM test). */
class SessionScreenTest {
    private fun src(name: String) = File("src/main/kotlin/com/cauarati/notchy/$name").readText()
    private val strings get() = File("src/main/res/values/strings.xml").readText()

    @Test fun aPillAndTheFocusCardOpenTheSession() {
        // As on the iPhone: a tap on a pill, or on the session in the island, opens it; what is missing says where to turn it on.
        assertTrue(src("MainActivity.kt").contains("Screen.SESSION -> SessionScreen("))
        val home = src("ui/HomePanel.kt")
        assertTrue(home.contains("FocusCard(focus) { onSession(focus.pillId) }"))
        assertTrue(home.contains("selected = s.pillId\n                            onSession(s.pillId)"))
    }

    @Test fun stepsAreShownAsTheComputerSentThemAndTheProjectIsOnlyAName() {
        val ui = src("ui/SessionScreen.kt")
        // One line each, as the Mac's island lists them (the Mac already cut a path to its file name).
        assertTrue(ui.contains("TickerRow(islandStep(step)"))
        assertTrue(src("ui/IslandKit.kt").contains("fun islandStep(raw: String): String = raw.map { if (it.isISOControl()) ' ' else it }"))
        assertTrue(ui.contains("R.string.session_project"))
        // the screen never draws a path or the raw step text
        assertFalse(ui.contains("Environment") || ui.contains("filesDir") || ui.contains("File("))
    }

    @Test fun withoutTheSwitchTheScreenSaysWhereToTurnItOn() {
        assertTrue(src("ui/SessionScreen.kt").contains("R.string.session_hint"))
        assertTrue(strings.contains("Show session details on the phone"))
        assertTrue(src("app/AppModel.kt").contains("detailsOffered = Protocol.CAP_DETAILS in caps"))
    }

}
