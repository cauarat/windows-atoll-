package com.cauarati.notchy

import com.cauarati.notchy.mochi.EyeResolution
import com.cauarati.notchy.mochi.EyeShape
import com.cauarati.notchy.mochi.FestiveArt
import com.cauarati.notchy.mochi.MochiAccessory
import com.cauarati.notchy.mochi.MochiCharacter
import com.cauarati.notchy.mochi.MochiEye
import com.cauarati.notchy.mochi.MochiFestive
import com.cauarati.notchy.mochi.MochiShape
import com.cauarati.notchy.mochi.Rgb
import com.cauarati.notchy.mochi.outfit.Css
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Notchy's characters on Android (mochi/MochiCharacter.kt, mochi/FestiveArt.kt): the same rules as the Mac's
 * MochiCharacter.swift and windows/src/mochi/character.ts, and the Christmas document the generator writes for all three.
 */
class MochiCharacterTest {
    private val expressive = listOf(
        EyeShape.DOT, EyeShape.LINE, EyeShape.FLAT, EyeShape.HAPPY, EyeShape.CLOSED, EyeShape.SPIRAL,
        EyeShape.HEART, EyeShape.STAR, EyeShape.TIRED, EyeShape.WINK, EyeShape.CUP,
    )

    @Test fun theListsAreTheMacsInTheMacsOrder() {
        val swift = ReferenceFiles.read("NotchBuddy/Sources/App/MochiCharacter.swift")
        // `case a, b, c` lines, before the enum's first `var`.
        fun cases(enum: String) = Regex("""enum $enum: String[^{]*\{(.*?)\n\s*var """, RegexOption.DOT_MATCHES_ALL).find(swift)!!.groupValues[1]
            .let { body -> Regex("""case ([\w, ]+)""").findAll(body).flatMap { it.groupValues[1].split(",").map(String::trim) }.toList() }
        assertEquals(cases("MochiAccessory"), MochiAccessory.entries.map { it.key })
        assertEquals(cases("MochiEye"), MochiEye.entries.map { it.key })
    }

    @Test fun classicDrawsEveryShapeAsItAlwaysHas() {
        for (s in EyeShape.entries) assertEquals(EyeResolution.Plain(s), MochiCharacter.CLASSIC.resolve(s))
        assertTrue(MochiCharacter.CLASSIC.isClassic)
    }

    @Test fun grownEyesOnlyReplaceTheCalmShapes() {
        for (eye in listOf(MochiEye.DOT, MochiEye.GLOSSY, MochiEye.PIXEL, MochiEye.SLEEPY)) {
            val c = MochiCharacter(eye = eye)
            assertEquals(EyeResolution.Character(eye, wide = false), c.resolve(EyeShape.PILL))
            assertEquals(EyeResolution.Character(eye, wide = true), c.resolve(EyeShape.WIDE))
            for (s in expressive) assertEquals(EyeResolution.Plain(s), c.resolve(s))
        }
    }

    @Test fun eyewearStaysOnThroughEveryExpression() {
        for (eye in listOf(MochiEye.VISOR, MochiEye.SHADES)) {
            for (s in EyeShape.entries) assertEquals(EyeResolution.BehindLens(s, eye), MochiCharacter(eye = eye).resolve(s))
        }
    }

    @Test fun onlyTheGrowingAccessoriesGoBehindTheBody() {
        assertEquals(
            setOf(MochiAccessory.CAT_EARS, MochiAccessory.HORNS, MochiAccessory.ANTENNA, MochiAccessory.SPROUT),
            MochiAccessory.entries.filter { it.isBehind }.toSet(),
        )
    }

    @Test fun theWireIsReadTolerantly() {
        val c = MochiCharacter.fromWire(mapOf("accessory" to "crown", "eye" to "glossy", "shape" to "frog", "festive" to "santaHat.-.-.scarf"))
        assertEquals(MochiAccessory.CROWN, c.accessory)
        assertEquals(MochiEye.GLOSSY, c.eye)
        assertEquals(MochiShape.FROG, c.shape)
        assertEquals(MochiFestive(head = "santaHat", extra = "scarf"), c.festive)
        assertEquals("santaHat.-.-.scarf", c.festive!!.storage)
        // Unknown values from a later Mac are left off, never guessed.
        val later = MochiCharacter.fromWire(mapOf("accessory" to "jetpack", "eye" to "laser", "shape" to "star", "festive" to "-.-.-.-"))
        assertTrue(later.isClassic)
        assertNull(MochiFestive.parse(""))
        assertNull(MochiFestive.parse("..."))
        assertEquals(MochiFestive(head = "elfHat"), MochiFestive.parse("elfHat"))
        assertNull(MochiFestive.parse("<script>"))
        assertTrue(MochiFestive(eyes = "treeGlasses").isEyewear)
        assertFalse(MochiFestive(eyes = "starEye").isEyewear)
    }

    // ── Christmas ────────────────────────────────────────────────────────────

    private val doc by lazy { FestiveArt.parse(File("src/main/assets/festive.json").readText()) }

    @Test fun theAssetIsTheGeneratorsDocument() {
        // The same JSON the Mac embeds: the generator writes all three, and its --check (scripts/test-mochi-festive.sh) fails a stale one.
        val ts = ReferenceFiles.file("android/../windows/src/mochi/festive.generated.ts").readText()
        val embedded = Regex("FESTIVE_JSON = '(.*)';", RegexOption.DOT_MATCHES_ALL).find(ts)!!.groupValues[1]
        assertEquals(embedded.replace("\\'", "'").replace("\\\\", "\\"), File("src/main/assets/festive.json").readText().trimEnd())
        assertEquals(setOf("classic", "round", "boxy", "fluffy", "pointy", "heart", "frog", "ato"), doc.bodies.keys)
    }

    @Test fun everyOutlineIsCommandsTheParserKnows() {
        var prims = 0
        for (body in doc.bodies.values) {
            val all = body.heads.values.flatMap { it.behind + it.front } + body.eyes.values.flatMap { it.left + it.right + it.over } +
                body.textures.values.flatten() + body.extras.values.flatMap { it.back + it.front }
            for (p in all) {
                prims++
                assertTrue(p.d.take(40), Regex("""[MLQCZ0-9.,\s+-eE]+""").matches(p.d))
                val ops = FestiveArt.ops(p.d)
                assertTrue(p.d.take(40), ops.isNotEmpty() && ops.first() is FestiveArt.Op.Move)
                // Every number was read: a command short of its numbers would end the outline early.
                val numbers = Regex("""[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?""").findAll(p.d).count()
                val read = ops.sumOf { op ->
                    when (op) { is FestiveArt.Op.Move, is FestiveArt.Op.Line -> 2; is FestiveArt.Op.Quad -> 4; is FestiveArt.Op.Cubic -> 6; else -> 0 }.toInt()
                }
                assertEquals(p.d.take(40), numbers, read)
            }
        }
        assertTrue("prims: $prims", prims > 1000)
    }

    @Test fun everyColourResolvesForEveryWearer() {
        val paints = listOf(
            FestiveArt.mochiPaint(Rgb(0.929, 0.929, 0.937), null, "rgb(26,20,18)", 0.0),
            FestiveArt.mochiPaint(Rgb(0.2, 0.4, 0.9), "gingerbread", "rgb(16,19,26)", null),
            FestiveArt.mochiPaint(Rgb(0.95, 0.95, 0.95), "frost", "rgb(26,20,18)", 1.0),
        )
        for (body in doc.bodies.values) {
            val all = body.heads.values.flatMap { it.behind + it.front } + body.eyes.values.flatMap { it.left + it.right + it.over } +
                body.textures.values.flatten() + body.extras.values.flatMap { it.back + it.front }
            for (p in all) for (paint in paints) for (token in listOfNotNull(p.fill, p.stroke)) {
                val css = FestiveArt.resolve(token, paint) ?: continue // @flakeEdge is null off a frosted body: skipped, as on the Mac
                assertNotNull(token, runCatching { Css.parse(css) }.getOrNull())
            }
        }
    }

    @Test fun snowflakesShowAgainstWhatTheyAreDrawnOn() {
        val pale = Rgb(0.929, 0.929, 0.937)
        assertEquals("#3FA9F5", FestiveArt.mochiPaint(pale, null, "#000", null).flake)
        assertEquals("#FFFFFF", FestiveArt.mochiPaint(Rgb(0.1, 0.2, 0.6), null, "#000", null).flake)
        assertEquals("#5FAEE6", FestiveArt.mochiPaint(pale, "frost", "#000", null).flakeEdge)
        assertEquals("rgb(181,116,58)", FestiveArt.resolve("@skin:1", FestiveArt.mochiPaint(pale, "gingerbread", "#000", null)))
        assertNull(FestiveArt.resolve("@later", FestiveArt.mochiPaint(pale, null, "#000", null)))
    }

    @Test fun theLightsTakeTurnsAndTheStarBreathes() {
        assertEquals(1.0, FestiveArt.light("bulbA", 0.0), 1e-9)
        assertEquals(0.3, FestiveArt.light("bulbB", 0.0), 1e-9)
        assertEquals(0.3, FestiveArt.light("bulbA", 1.5), 1e-9)
        assertEquals(1.0, FestiveArt.light("bulbB", 1.5), 1e-9)
        assertEquals(0.6, FestiveArt.light("lit", 0.0), 1e-9)
        assertEquals(1.0, FestiveArt.light("lit", 0.9), 1e-9)
        assertEquals(1.0, FestiveArt.light("unknown", 3.0), 1e-9)
    }
}
