package com.cauarati.notchy.app

import android.app.Application
import android.content.Context
import com.cauarati.notchy.core.Texts

class NotchyApp : Application() {
    val model: AppModel by lazy { AppModel(this) }

    override fun attachBaseContext(base: Context) {
        // Before Android 13 the language chosen in the app is applied here (from 13 on the system does it).
        super.attachBaseContext(AppLanguage.wrap(base))
    }

    override fun onCreate() {
        super.onCreate()
        // The words of the pure rules follow the app's language like every other text.
        Texts.source = AppLanguage.texts(this)
        // Mochi's Christmas artwork, read only once a pill wears some of it.
        com.cauarati.notchy.mochi.FestiveArt.source = { assets.open("festive.json").bufferedReader().use { it.readText() } }
    }
}
