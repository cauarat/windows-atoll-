package com.cauarati.notchy.app

import android.app.NotificationManager
import android.content.Context

/**
 * What versions with coding agents left on the phone, forgotten at start. The app no longer posts notifications, so the channels they
 * made would only linger in Android's settings; and the list of Allow/Deny decisions (which kept the start of each command) would stay
 * in the preferences with nothing left in the app to show or clear it. Nothing here is sent anywhere; once it is gone it costs nothing.
 */
object LegacyData {
    /** Keys of the app's preferences ("notchy_ui") that only removed features wrote. */
    val UI_KEYS = listOf(
        "decisions", "overlay", "computer_outfit", "link_drops_off", "battery_snoozed_at",
        "notify_done", "quiet_on", "quiet_from", "quiet_to", "no_wake_screen", "vibration_choice", "muted_agents",
        "island_hide_in_dnd", "spoken_alerts",
    )

    /** Preference files only the widgets used. */
    val FILES = listOf("widget_team", "widget_today")

    fun forget(context: Context) {
        val app = context.applicationContext
        runCatching {
            val nm = app.getSystemService(NotificationManager::class.java)
            nm?.notificationChannels?.forEach { nm.deleteNotificationChannel(it.id) }
        }
        val ui = app.getSharedPreferences("notchy_ui", Context.MODE_PRIVATE)
        if (UI_KEYS.any { ui.contains(it) }) ui.edit().apply { UI_KEYS.forEach { remove(it) } }.apply()
        for (name in FILES) runCatching { app.deleteSharedPreferences(name) }
    }
}
