package com.cauarati.notchy

import com.cauarati.notchy.core.Nav
import com.cauarati.notchy.core.Screen
import com.cauarati.notchy.core.Tab
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NavigationTest {
    @Test fun theIslandHasHomeAndChatAndSettingsIsItsGear() {
        // As on the Mac and the iPhone: the island's header holds the two tabs; there is no bottom bar.
        assertEquals(listOf(Tab.HOME, Tab.CHAT), Nav.tabs())
        val main = java.io.File("src/main/kotlin/com/cauarati/notchy/MainActivity.kt").readText()
        assertTrue(main.contains("onSettings = { screen = Screen.SETTINGS }"))
        assertFalse(java.io.File("src/main/kotlin/com/cauarati/notchy/ui/BottomBar.kt").exists())
    }

    @Test fun chatAndASessionAreDrawnAsTheIsland() {
        assertTrue(Nav.isIsland(Screen.CHAT) && Nav.isIsland(Screen.SESSION))
        for (s in listOf(Screen.SETTINGS, Screen.HISTORY, Screen.GALLERY, Screen.DIAGNOSTICS, Screen.LICENCES, Screen.SCAN)) assertFalse("$s", Nav.isIsland(s))
    }

    @Test fun backGoesUpOneLevelAndLeavesFromHome() {
        assertNull(Nav.back(Screen.HOME))
        assertEquals(Screen.HOME, Nav.back(Screen.CHAT))
        assertEquals(Screen.HOME, Nav.back(Screen.SETTINGS))
        assertEquals(Screen.HOME, Nav.back(Screen.SESSION))
        assertEquals(Screen.HOME, Nav.back(Screen.SCAN))
        assertEquals(Screen.SETTINGS, Nav.back(Screen.HISTORY))
        assertEquals(Screen.SETTINGS, Nav.back(Screen.GALLERY))
        assertEquals(Screen.SETTINGS, Nav.back(Screen.DIAGNOSTICS))
    }

    @Test fun backAlwaysReachesHomeAndNeverLoops() {
        for (start in Screen.entries) {
            var s = start
            var steps = 0
            while (true) {
                s = Nav.back(s) ?: break
                assertTrue("loop from $start", ++steps < 10)
            }
            assertEquals("from $start", Screen.HOME, s)
        }
    }

    @Test fun pagesBelowSettingsKeepSettingsHighlighted() {
        for (s in listOf(Screen.SETTINGS, Screen.HISTORY, Screen.GALLERY, Screen.DIAGNOSTICS)) assertEquals(Tab.SETTINGS, Nav.tabOf(s))
        assertNull(Nav.tabOf(Screen.SCAN))
        assertNull(Nav.tabOf(Screen.SESSION))
    }

    @Test fun everyTabLeadsToItsOwnScreen() {
        for (t in Tab.entries) assertEquals(t, Nav.tabOf(Nav.screenOf(t)))
    }
}
