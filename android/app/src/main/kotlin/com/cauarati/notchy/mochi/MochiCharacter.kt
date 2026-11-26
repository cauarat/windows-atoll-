package com.cauarati.notchy.mochi

/**
 * Who a Mochi is: what sits on its head, what kind of eyes it has, what it is shaped like and what it wears
 * at Christmas. A port of the Mac's MochiCharacter.swift by way of windows/src/mochi/character.ts, for the
 * characters the computer sends per session (cap `character`). The phone has no picker: it draws what the
 * pill wears on the computer, and anything this build does not know is left off rather than guessed.
 *
 * The colour is deliberately not here: it comes from the pill, as on the Mac.
 */
enum class MochiAccessory(val key: String) {
    CAT_EARS("catEars"), HORNS("horns"), ANTENNA("antenna"), SPROUT("sprout"),
    SPARKLES("sparkles"), BOW("bow"), CROWN("crown"), BERET("beret");

    /** Drawn before the body, so the silhouette swallows the base and it looks grown rather than stuck on. */
    val isBehind: Boolean get() = this == CAT_EARS || this == HORNS || this == ANTENNA || this == SPROUT

    companion object {
        fun of(key: String?): MochiAccessory? = entries.firstOrNull { it.key == key }
    }
}

enum class MochiEye(val key: String) {
    DOT("dot"), GLOSSY("glossy"), PIXEL("pixel"), SLEEPY("sleepy"), VISOR("visor"), SHADES("shades");

    /** Worn rather than grown: one piece across both sockets, always on, never replaced by an expression. */
    val isSpanning: Boolean get() = this == VISOR || this == SHADES

    companion object {
        fun of(key: String?): MochiEye? = entries.firstOrNull { it.key == key }
    }
}

/** What a Mochi puts on for Christmas, one id per layer; ids are the generated artwork's (assets/festive.json). */
data class MochiFestive(val head: String? = null, val eyes: String? = null, val texture: String? = null, val extra: String? = null) {
    val isEmpty: Boolean get() = head == null && eyes == null && texture == null && extra == null

    /** The glasses: frames worn over the eyes, so they stay on through every expression. */
    val isEyewear: Boolean get() = eyes == "treeGlasses" || eyes == "wreathGlasses"

    /** `"head.eyes.texture.extra"`, `-` for a layer with nothing on it. */
    val storage: String get() = listOf(head, eyes, texture, extra).joinToString(".") { it ?: "-" }

    companion object {
        /** Tolerant like the Mac's: short, long or empty all parse; an id must look like one or it is dropped. */
        fun parse(storage: String?): MochiFestive? {
            if (storage.isNullOrEmpty()) return null
            val parts = storage.split(".")
            fun part(i: Int) = parts.getOrNull(i)?.takeIf { it.isNotEmpty() && it != "-" && ID.matches(it) }
            return MochiFestive(part(0), part(1), part(2), part(3)).takeUnless { it.isEmpty }
        }

        private val ID = Regex("[A-Za-z][A-Za-z0-9]{0,31}")
    }
}

data class MochiCharacter(
    val accessory: MochiAccessory? = null,
    val eye: MochiEye? = null,
    /** Absent is classic Mochi. */
    val shape: MochiShape? = null,
    val festive: MochiFestive? = null,
) {
    val isClassic: Boolean get() = accessory == null && eye == null && shape == null && (festive?.isEmpty ?: true)

    /**
     * What a character does with the eye shape the animation asked for. `dot`, `glossy`, `pixel` and `sleepy`
     * *are* the eye, so they only apply while nothing is being expressed; `visor` and `shades` are worn over the
     * eyes, always drawn, with the expression inside the lens as a glint.
     */
    fun resolve(shape: EyeShape): EyeResolution {
        val eye = eye ?: return EyeResolution.Plain(shape)
        if (eye.isSpanning) return EyeResolution.BehindLens(shape, eye)
        return if (isNeutral(shape)) EyeResolution.Character(eye, wide = shape == EyeShape.WIDE) else EyeResolution.Plain(shape)
    }

    companion object {
        val CLASSIC = MochiCharacter()

        /** The two shapes that mean "nothing in particular is happening": calm, or calm and looking at you. */
        fun isNeutral(shape: EyeShape) = shape == EyeShape.PILL || shape == EyeShape.WIDE

        /** A session's `character` object, as the Mac sends it (keys `accessory`, `eye`, `shape`, `festive`). */
        fun fromWire(values: Map<String, String>): MochiCharacter = MochiCharacter(
            accessory = MochiAccessory.of(values["accessory"]),
            eye = MochiEye.of(values["eye"]),
            shape = MochiShape.of(values["shape"]),
            festive = MochiFestive.parse(values["festive"]),
        )
    }
}

sealed interface EyeResolution {
    /** Draw the shape as the engine always has. */
    data class Plain(val shape: EyeShape) : EyeResolution
    /** Draw the character's own eyes; [wide] carries approval's enlargement. */
    data class Character(val eye: MochiEye, val wide: Boolean) : EyeResolution
    /** Draw the lens, with [shape] inside it as a glint. */
    data class BehindLens(val shape: EyeShape, val eye: MochiEye) : EyeResolution
}
