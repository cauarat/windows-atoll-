package com.cauarati.notchy.core

/**
 * The screens a shortcut (long-press the app icon) may open: a closed list, never a free string. A shortcut carries the [key] of one
 * of these to LaunchActivity (ours, not exported), which turns it into a [LaunchScreen] with [parse] and hands it to the app inside
 * the process ([PendingLaunch]). Anything that is not in the list is rejected, so a shortcut can only ever open a screen; none
 * changes or sends anything.
 */
enum class LaunchScreen(val key: String, val screen: Screen) {
    CHAT("chat", Screen.CHAT),

    /** "Pair again": the pairing scan. It always asks to confirm before anything is paired. */
    PAIR("pair", Screen.SCAN),
    ;

    companion object {
        /** The screen called exactly [key]; null for anything else (another case, spaces, an unknown name, null). */
        fun parse(key: String?): LaunchScreen? = values().firstOrNull { it.key == key }
    }
}
