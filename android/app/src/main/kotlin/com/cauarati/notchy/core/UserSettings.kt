package com.cauarati.notchy.core

/** Where settings are kept (SharedPreferences in the app, a plain map in tests). */
interface KeyValueStore {
    fun getBoolean(key: String, default: Boolean): Boolean
    fun getInt(key: String, default: Int): Int
    fun getFloat(key: String, default: Float): Float
    fun getString(key: String, default: String): String
    fun put(key: String, value: Any)
}

/** What the user chose in Settings. Defaults keep the app as it was before the settings existed. */
data class UserSettings(
    val soundOn: Boolean = true,
    val volume: Float = com.cauarati.notchy.sound.SoundVolume.DEFAULT,
    /** Mochi's outfit on this phone: "auto", "none" or an outfit. */
    val outfit: String = com.cauarati.notchy.mochi.outfit.Wardrobe.DEFAULT,
    /** Reduce motion: follow the system (default), always, or never. */
    val motion: MotionChoice = MotionChoice.SYSTEM,
    /** Light, dark or the phone's own. */
    val theme: ThemeChoice = ThemeChoice.SYSTEM,
    /** Use the phone's own colours (Material You, Android 12 and later) for the surfaces and text. Off by default. */
    val dynamicColour: Boolean = false,
) {
    companion object {
        private const val SOUND = "sound_on"
        private const val VOLUME = "sound_volume"
        private const val OUTFIT = "outfit_choice"
        private const val MOTION = "motion_choice"
        private const val THEME = "theme_choice"
        private const val DYNAMIC = "dynamic_colour"

        fun load(store: KeyValueStore): UserSettings {
            val d = UserSettings()
            return UserSettings(
                soundOn = store.getBoolean(SOUND, d.soundOn),
                volume = com.cauarati.notchy.sound.SoundVolume.clamp(store.getFloat(VOLUME, d.volume)),
                outfit = com.cauarati.notchy.mochi.outfit.Wardrobe.parse(store.getString(OUTFIT, d.outfit)),
                motion = MotionChoice.parse(store.getString(MOTION, d.motion.key)),
                theme = ThemeChoice.parse(store.getString(THEME, d.theme.key)),
                dynamicColour = store.getBoolean(DYNAMIC, d.dynamicColour),
            )
        }

        fun save(store: KeyValueStore, s: UserSettings) {
            store.put(SOUND, s.soundOn)
            store.put(VOLUME, com.cauarati.notchy.sound.SoundVolume.clamp(s.volume))
            store.put(OUTFIT, com.cauarati.notchy.mochi.outfit.Wardrobe.parse(s.outfit))
            store.put(MOTION, s.motion.key)
            store.put(THEME, s.theme.key)
            store.put(DYNAMIC, s.dynamicColour)
        }
    }
}
