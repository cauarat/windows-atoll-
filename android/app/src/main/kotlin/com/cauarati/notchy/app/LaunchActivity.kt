package com.cauarati.notchy.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.cauarati.notchy.MainActivity
import com.cauarati.notchy.core.LaunchScreen

/**
 * Where our own shortcuts (long-press the app icon) land. It is not exported, so no other app can start it; it passes the screen
 * to the app inside the process ([com.cauarati.notchy.core.PendingLaunch]) and opens MainActivity with a plain intent.
 */
class LaunchActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val model = (application as NotchyApp).model
        // A screen that is not in the closed list is ignored: the app just opens.
        LaunchScreen.parse(intent.getStringExtra(EXTRA_SCREEN))?.let { model.launch.requestScreen(it) }
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        )
        finish()
    }

    companion object {
        /** The key of the [LaunchScreen] a shortcut opens. */
        const val EXTRA_SCREEN = "screen"
    }
}
