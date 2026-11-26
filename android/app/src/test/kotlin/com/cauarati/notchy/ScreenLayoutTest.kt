package com.cauarati.notchy

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards for where things live on screen (the Compose code cannot be rendered in a JVM test, so
 * these read the sources). Home is Mochi and the computer it is connected to; Settings holds the rest, including the notice
 * Louis Raillé's permission requires, which must stay reachable and visible.
 */
class ScreenLayoutTest {
    private fun src(name: String) = File("src/main/kotlin/com/cauarati/notchy/$name").readText()
    private val main get() = src("MainActivity.kt")
    private val settings get() = src("ui/SettingsScreens.kt")
    private val homePanel get() = src("ui/HomePanel.kt")

    @Test fun settingsHoldsDisconnectGalleryAndTheRequiredNotice() {
        for (s in listOf(
            "R.string.action_unpair", "R.string.gallery", "R.string.wardrobe_title",
            "R.string.about_credit", "R.string.about_repo", "R.string.about_assets", "R.string.settings_section_about",
        )) assertTrue("Settings must carry $s", settings.contains(s))
    }

    @Test fun theNoticeNamesTheOriginalAuthorAndHisRepository() {
        val xml = File("src/main/res/values/strings.xml").readText()
        assertTrue(xml.contains("Based on Coucou for Android by Rhytam Biswas and Coucou by Louis Raillé"))
        assertTrue(xml.contains("github.com/cauarat/windows-atoll-"))
        assertTrue(xml.contains("© Louis Raillé"))
        assertTrue(xml.contains("MIT License"))
    }

    @Test fun theHeroSaysWhichComputerItIsAndNothingAboutAgents() {
        assertTrue(homePanel.contains("R.string.home_connected_title") && homePanel.contains("R.string.home_connecting_title"))
        for (word in listOf("SessionInfo", "agent", "approval", "statusText")) assertFalse("the hero mentions $word", homePanel.contains(word, ignoreCase = true))
        // Mochi is awake while the computer is there, asleep while it is not.
        assertTrue(main.contains("BotState.IDLE else BotState.SLEEPING"))
    }
}
