package com.cauarati.notchy.core

/**
 * "Open this screen", handed from a tap on one of our shortcuts to the main screen inside the process. MainActivity is
 * exported (it is the launcher and takes notchy:// links), so it must never trust extras on the intent it is started with.
 * Only the non-exported LaunchActivity calls [requestScreen]; MainActivity only calls [takeScreen].
 */
class PendingLaunch(private val clock: () -> Long = System::currentTimeMillis) {
    private var screen: LaunchScreen? = null
    private var screenAt = 0L

    /** A value of the closed [LaunchScreen] list and nothing else. Only the non-exported LaunchActivity calls it. */
    @Synchronized
    fun requestScreen(which: LaunchScreen?) {
        screen = which
        screenAt = clock()
    }

    /** The screen to open, once, if the tap is fresh; null for everything else (nothing asked, already taken, too old). */
    @Synchronized
    fun takeScreen(): LaunchScreen? {
        val s = screen ?: return null
        val fresh = clock() - screenAt <= TTL_MS
        screen = null
        return if (fresh) s else null
    }

    companion object {
        /** The tap and the screen are in the same second; a longer wait means something else is going on. */
        const val TTL_MS = 15_000L
    }
}
