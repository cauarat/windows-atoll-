package com.cauarati.notchy

import com.cauarati.notchy.mochi.MochiShape
import com.cauarati.notchy.mochi.anchorRadius
import com.cauarati.notchy.mochi.furHash
import com.cauarati.notchy.mochi.furSample
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The computed half of Notchy's body tables (mochi/MochiShape.kt), run against values the TypeScript twin gives.
 * The tabulated half is compared with the Swift tables by scripts/test-mochi-character.sh
 * (tests/mochi-shape-parity-android.ts), which also checks that the numbers written here are TypeScript's.
 */
class MochiShapeTest {
    private fun hash(i: Int, seed: Int, expected: Double) = assertEquals("furHash($i, $seed)", expected, furHash(i, seed), 1e-9)
    private fun sample(x: Int, y: Int, expected: Int) = assertEquals("furSample($x, $y)", expected, furSample(x, y))
    private fun anchor(shape: MochiShape, theta: Double, expected: Double) =
        assertEquals("anchorRadius(${shape.key}, $theta)", expected, anchorRadius(theta, shape.geometry), 1e-9)

    @Test fun furHashIsTheSameBitsAsTypeScript() {
        hash(0, 1592594996, 0.946800696884)
        hash(1, 1592594996, 0.860544063584)
        hash(7, 1, 0.972367682255)
        hash(1000, 2, 0.855195590960)
        hash(65535, 1592594996, 0.407821317997)
        hash(123456, -559038737, 0.571050882938)
    }

    @Test fun plushTileIsTheSameAsTypeScript() {
        sample(0, 0, 234)
        sample(1, 1, 233)
        sample(50, 50, 192)
        sample(95, 13, 223)
        sample(13, 77, 195)
        sample(44, 95, 223)
    }

    @Test fun anchorLookupIsTheSameAsTypeScript() {
        anchor(MochiShape.ROUND, 0.0, 1.145699000000)
        anchor(MochiShape.FROG, 1.3, 0.997499278382)
        anchor(MochiShape.HEART, -1.5707963, 0.880631009946)
        anchor(MochiShape.POINTY, 4.71238898, 1.132178999934)
        anchor(MochiShape.FLUFFY, 2.5, 1.193840745432)
    }

    @Test fun everyBodyHasThreeSizesAndOnlyTheFrogHasSockets() {
        for (s in MochiShape.entries) {
            val g = s.geometry
            assertEquals(72, g.outline(72).size)
            assertEquals(36, g.outline(36).size)
            assertEquals(24, g.outline(24).size)
            assertEquals(24, g.outline(8).size)
            assertEquals(24, g.anchor24.size)
            assertEquals(s == MochiShape.FROG, g.hasSockets)
        }
        assertEquals(listOf("round", "boxy", "fluffy", "pointy", "heart", "frog"), MochiShape.entries.map { it.key })
        assertTrue(MochiShape.of("classic") == null && MochiShape.of(null) == null)
    }
}
