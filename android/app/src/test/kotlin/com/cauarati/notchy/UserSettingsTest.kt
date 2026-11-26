package com.cauarati.notchy

import com.cauarati.notchy.core.KeyValueStore
import com.cauarati.notchy.core.UserSettings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UserSettingsTest {
    private class Memory : KeyValueStore {
        val map = HashMap<String, Any>()
        override fun getBoolean(key: String, default: Boolean) = map[key] as? Boolean ?: default
        override fun getInt(key: String, default: Int) = map[key] as? Int ?: default
        override fun getFloat(key: String, default: Float) = map[key] as? Float ?: default
        override fun getString(key: String, default: String) = map[key] as? String ?: default
        override fun put(key: String, value: Any) { map[key] = value }
    }

    @Test fun defaultsKeepTheAppAsItWas() {
        val loaded = UserSettings.load(Memory())
        assertTrue(loaded.soundOn)
        assertEquals(0.12f, loaded.volume, 0f)
    }

    @Test fun settingsSurviveARestart() {
        val disk = Memory()
        UserSettings.save(disk, UserSettings(soundOn = false, volume = 0.05f))
        val back = UserSettings.load(disk)
        assertFalse(back.soundOn)
        assertEquals(0.05f, back.volume, 0f)
    }

    @Test fun volumeNeverExceedsTheSpecMaximum() {
        val disk = Memory()
        UserSettings.save(disk, UserSettings(volume = 9f))
        assertEquals(0.2f, UserSettings.load(disk).volume, 0f)
    }

    @Test fun theOutfitChoiceIsKeptAndDefaultsToAuto() {
        val m = Memory()
        assertEquals("auto", UserSettings.load(m).outfit)
        UserSettings.save(m, UserSettings(outfit = "crown"))
        assertEquals("crown", UserSettings.load(m).outfit)
        UserSettings.save(m, UserSettings(outfit = "none"))
        assertEquals("none", UserSettings.load(m).outfit)
    }

    @Test fun anOutfitChoiceNoBuildKnowsIsAuto() {
        val m = Memory()
        m.map["outfit_choice"] = "topHat"
        assertEquals("auto", UserSettings.load(m).outfit)
        UserSettings.save(m, UserSettings(outfit = "<script>"))
        assertEquals("auto", m.map["outfit_choice"])
    }

    @Test fun theOldSameAsTheComputerChoiceBecomesAuto() {
        // Older builds stored "computer" (wear what the computer says); no computer sends an outfit any more, and it always meant "auto".
        val m = Memory()
        m.map["outfit_choice"] = "computer"
        assertEquals("auto", UserSettings.load(m).outfit)
    }
}
