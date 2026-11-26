package com.cauarati.notchy

import com.cauarati.notchy.core.Screen
import com.cauarati.notchy.core.SecureScreens
import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SecureScreensTest {
    private fun needed(screen: Screen, pairing: Boolean = false, confirm: Boolean = false) = SecureScreens.needed(screen, pairing, confirm)

    @Test fun pairingAndChatAreHidden() {
        assertTrue("pairing screen", needed(Screen.HOME, pairing = true))
        assertTrue("scanning the code", needed(Screen.SCAN))
        assertTrue("chat", needed(Screen.CHAT))
        assertTrue("pair confirmation", needed(Screen.HOME, confirm = true))
        assertTrue("pair confirmation over Settings", needed(Screen.SETTINGS, confirm = true))
    }

    @Test fun otherScreensAreNotHidden() {
        for (s in listOf(Screen.HOME, Screen.SETTINGS, Screen.GALLERY, Screen.WARDROBE, Screen.DIAGNOSTICS, Screen.LICENCES)) {
            assertFalse("$s", needed(s))
        }
    }

    @Test fun theActivityAppliesAndClearsTheFlagFromThatDecision() {
        val src = File("src/main/kotlin/com/cauarati/notchy/MainActivity.kt").readText()
        assertTrue(src.contains("SecureScreens.needed("))
        assertTrue(src.contains("window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)"))
        assertTrue("cleared when the screen is no longer sensitive", src.contains("window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)"))
        // The decision sees every sheet that exists: a new sheet must be added to it.
        assertTrue(src.contains("pairConfirmShown = model.pairRequest != null"))
        assertTrue(src.contains("PairConfirm("))
    }
}
