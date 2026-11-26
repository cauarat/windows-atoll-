package com.cauarati.notchy

import com.cauarati.notchy.core.LaunchScreen
import com.cauarati.notchy.core.Nav
import com.cauarati.notchy.core.Screen
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The closed list of screens a shortcut may open: nothing else can be asked for. */
class LaunchScreenTest {
    @Test fun theListIsExactlyTheTwoShortcuts() {
        assertEquals(listOf("chat", "pair"), LaunchScreen.values().map { it.key })
        assertEquals(listOf(LaunchScreen.CHAT, LaunchScreen.PAIR), LaunchScreen.values().toList())
        assertEquals("a key is used once", 2, LaunchScreen.values().map { it.key }.toSet().size)
    }

    @Test fun everyValueParsesBackFromItsOwnKey() {
        for (s in LaunchScreen.values()) assertEquals(s, LaunchScreen.parse(s.key))
    }

    @Test fun anythingElseIsRejected() {
        val bad = listOf(
            null, "", " ", "CHAT", "Chat", " chat", "chat ", "ch at", "chat\n", "home", "settings", "recent", "session", "history", "scan",
            "diagnostics", "licences", "wardrobe", "approve", "allow", "deny", "send", "unpair", "../chat", "chat;pair", "0", "-1", "CHAT,PAIR",
            "com.cauarati.notchy.MainActivity",
        )
        for (k in bad) assertNull("'$k' must not open anything", LaunchScreen.parse(k))
        // The enum name is not the key: only the key is accepted.
        for (s in LaunchScreen.values()) assertNull(s.name, LaunchScreen.parse(s.name).takeIf { it != s })
    }

    @Test fun everyValueIsAScreenThatExistsInTheApp() {
        for (s in LaunchScreen.values()) assertTrue(s.name, s.screen in Screen.values())
        // Chat is a tab of the bottom bar; "Pair again" is the pairing scan, and Back from it goes Home.
        assertEquals(Nav.screenOf(com.cauarati.notchy.core.Tab.CHAT), LaunchScreen.CHAT.screen)
        assertEquals(Screen.SCAN, LaunchScreen.PAIR.screen)
        assertEquals(Screen.HOME, Nav.back(Screen.SCAN))
    }

    @Test fun onlyTheKeyTravelsAndOnlyTheNonExportedActivityParsesIt() {
        val main = "src/main/kotlin/com/cauarati/notchy/"
        val launch = File(main + "app/LaunchActivity.kt").readText()
        assertTrue(launch.contains("LaunchScreen.parse(intent.getStringExtra(EXTRA_SCREEN))"))
        assertFalse(File(main + "MainActivity.kt").readText().contains("EXTRA_SCREEN"))
        assertFalse(File(main + "MainActivity.kt").readText().contains("LaunchScreen.parse"))
        val manifest = File("src/main/AndroidManifest.xml").readText()
        assertTrue(manifest.substringAfter(""".app.LaunchActivity"""").substringBefore("/>").contains("""android:exported="false""""))
    }
}
