package com.cauarati.notchy.sound

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import com.cauarati.notchy.R
import com.cauarati.notchy.mochi.SoundSink

/**
 * Plays Mochi's sounds (the .wav files in res/raw, (c) Louis Raillé, used with permission) through a
 * SoundPool. Short clips, no streaming; a sound that is not found is silently ignored.
 */
class SoundPlayer(private val context: Context) : SoundSink {
    var enabled = true
    var volume = SoundVolume.DEFAULT
        set(v) { field = SoundVolume.clamp(v) }

    private val pool: SoundPool = SoundPool.Builder()
        .setMaxStreams(4)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        .build()
    private val ids = HashMap<String, Int>()
    private val ready = HashSet<Int>()

    init {
        pool.setOnLoadCompleteListener { _, id, status -> if (status == 0) ready.add(id) }
    }

    private fun load(name: String): Int? = ids.getOrPut(name) {
        val res = RAW[name] ?: return null
        pool.load(context, res, 1)
    }

    override fun play(name: String) {
        if (!enabled || volume <= 0f) return
        val id = load(name) ?: return
        if (id in ready) pool.play(id, volume, volume, 1, 0, 1f)
    }

    fun release() = pool.release()

    private companion object {
        /** Every bundled sound, by file name (an explicit table: no resource reflection). */
        val RAW: Map<String, Int> = mapOf(
            "annoyed" to R.raw.annoyed,
            "dizzy" to R.raw.dizzy,
            "greet" to R.raw.greet,
            "love" to R.raw.love,
            "slap" to R.raw.slap,
        )
    }
}
