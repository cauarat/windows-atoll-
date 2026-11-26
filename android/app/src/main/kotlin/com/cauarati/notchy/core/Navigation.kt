package com.cauarati.notchy.core

/** The island header's two tabs, and Settings behind its gear (also where a widget button may lead). */
enum class Tab { HOME, CHAT, SETTINGS }

/** Every screen of the app. Tabs are the roots; the rest are one level down. */
enum class Screen { HOME, CHAT, SETTINGS, HISTORY, GALLERY, WARDROBE, DIAGNOSTICS, LICENCES, SESSION, SCAN }

/**
 * Where the user is and where Back goes. Pure, so every rule is a unit test:
 * - as on the Mac and the iPhone, the island's header has the tabs, Home and Chat (Chat shows why it cannot chat yet when that is
 *   the case), and Settings is its gear: there is no bottom bar;
 * - Back goes up one level; on Home it is the system's (leave the app).
 */
object Nav {
    /** The island header's tabs: Home and Chat, always. */
    fun tabs(): List<Tab> = listOf(Tab.HOME, Tab.CHAT)

    /** The screens drawn as the island (black in both themes, hanging from the top edge). */
    fun isIsland(screen: Screen): Boolean = screen == Screen.CHAT || screen == Screen.SESSION

    fun screenOf(tab: Tab): Screen = when (tab) {
        Tab.HOME -> Screen.HOME
        Tab.CHAT -> Screen.CHAT
        Tab.SETTINGS -> Screen.SETTINGS
    }

    /** The tab a screen belongs to, so the bar can highlight it; null for full-screen tasks. */
    fun tabOf(screen: Screen): Tab? = when (screen) {
        Screen.HOME -> Tab.HOME
        Screen.CHAT -> Tab.CHAT
        Screen.SETTINGS, Screen.HISTORY, Screen.GALLERY, Screen.WARDROBE, Screen.DIAGNOSTICS, Screen.LICENCES -> Tab.SETTINGS
        Screen.SESSION, Screen.SCAN -> null
    }

    /** One level up, or null when Back should leave the app. */
    fun back(screen: Screen): Screen? = when (screen) {
        Screen.HOME -> null
        Screen.CHAT, Screen.SETTINGS, Screen.SESSION, Screen.SCAN -> Screen.HOME
        Screen.HISTORY, Screen.GALLERY, Screen.WARDROBE, Screen.DIAGNOSTICS, Screen.LICENCES -> Screen.SETTINGS
    }
}
