package com.cauarati.notchy.core

/**
 * Which screens hide from screenshots, screen recording and the recent-apps card (FLAG_SECURE): the ones that show the
 * pairing code or link, and the chat with the user's AI.
 * Pure, so the list is a unit test; MainActivity sets or clears the flag from it as the screen changes.
 */
object SecureScreens {
    fun needed(
        screen: Screen,
        /** Not paired yet: Home is the pairing screen (link, scan, paste). */
        pairing: Boolean,
        /** "Pair with this computer?" after a scan or a link. */
        pairConfirmShown: Boolean,
    ): Boolean = screen == Screen.CHAT || screen == Screen.SCAN || (screen == Screen.HOME && pairing) || pairConfirmShown
}
