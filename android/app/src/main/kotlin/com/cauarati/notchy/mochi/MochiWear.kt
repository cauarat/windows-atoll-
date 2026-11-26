package com.cauarati.notchy.mochi

import android.graphics.Bitmap
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Canvas
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.LinearGradientShader
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.PaintingStyle
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import com.cauarati.notchy.core.lerp
import com.cauarati.notchy.mochi.outfit.Css
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * What a Mochi wears and is shaped like, drawn: the shaped body, its plush grain, the eight accessories and the
 * Christmas artwork. A port of the matching parts of windows/src/mochi/engine.ts and festive.ts (themselves ports
 * of the Mac's BotEngine, MochiFur and MochiFestive), number for number. Units are those of the caller's canvas:
 * MochiPainter draws in dp, the Mac's points, so the size thresholds below mean what they mean on the Mac.
 */
internal object MochiWear {
    // ── Paint ─────────────────────────────────────────────────────────────────

    fun css(s: String): Color = Css.parse(s).let { Color((it.r / 255).toFloat(), (it.g / 255).toFloat(), (it.b / 255).toFloat(), it.a.toFloat()) }

    fun fill(c: Color, alpha: Double = 1.0) = Paint().apply {
        color = c.copy(alpha = (c.alpha * alpha).toFloat().coerceIn(0f, 1f)); isAntiAlias = true
    }

    fun stroke(c: Color, width: Double, alpha: Double = 1.0, cap: StrokeCap = StrokeCap.Round, join: StrokeJoin = StrokeJoin.Miter) = Paint().apply {
        color = c.copy(alpha = (c.alpha * alpha).toFloat().coerceIn(0f, 1f)); isAntiAlias = true
        style = PaintingStyle.Stroke; strokeWidth = width.toFloat(); strokeCap = cap; strokeJoin = join
    }

    fun rgb(c: Rgb) = Color(c.r.toFloat().coerceIn(0f, 1f), c.g.toFloat().coerceIn(0f, 1f), c.b.toFloat().coerceIn(0f, 1f))

    fun roundRect(x: Double, y: Double, w: Double, h: Double, r: Double) = Path().apply {
        val rr = max(0.0, min(r, min(w / 2, h / 2))).toFloat()
        addRoundRect(RoundRect(x.toFloat(), y.toFloat(), (x + w).toFloat(), (y + h).toFloat(), CornerRadius(rr, rr)))
    }

    fun oval(cx: Double, cy: Double, rx: Double, ry: Double) = Path().apply {
        addOval(Rect((cx - rx).toFloat(), (cy - ry).toFloat(), (cx + rx).toFloat(), (cy + ry).toFloat()))
    }

    private fun Path.m(x: Double, y: Double) = moveTo(x.toFloat(), y.toFloat())
    private fun Path.l(x: Double, y: Double) = lineTo(x.toFloat(), y.toFloat())
    private fun Path.q(cx: Double, cy: Double, x: Double, y: Double) = quadraticBezierTo(cx.toFloat(), cy.toFloat(), x.toFloat(), y.toFloat())

    private fun Canvas.rot(rad: Double) = rotate((rad * 180 / PI).toFloat())
    private fun Canvas.tr(x: Double, y: Double) = translate(x.toFloat(), y.toFloat())

    // ── The shaped body ───────────────────────────────────────────────────────

    /** How many samples this body is worth at this size (R in dp). */
    fun bodyLod(r: Double): Int = if (r > 16) 72 else if (r > 10) 36 else 24

    /** How ragged the silhouette is here, in fractions of its radius. */
    fun furAmount(e: MochiEngine, r: Double): Double {
        if (e.geo == null || r <= 13) return 0.0
        return 0.016 * ((r - 13) / 6).coerceIn(0.0, 1.0) * (1 - e.morph)
    }

    /**
     * The body, for a Mochi that has a shape: the same direction-indexed loop as the classic body, so the mailbox
     * morph drops straight in. The frog's eyeballs are added as their own circles, shrinking away over the morph.
     */
    fun shapedPath(e: MochiEngine, g: MochiShapeGeometry, r: Double): Path {
        val table = g.outline(bodyLod(r))
        val n = table.size
        val fur = furAmount(e, r)
        val tw = r * 1.0
        val th = r * 0.94
        val tr = r * 0.42
        val m = e.morph
        val p = Path()
        for (i in 0..n) {
            val k = i % n
            val a = k.toDouble() / n * PI * 2
            val ca = cos(a)
            val sa = sin(a)
            var rad = table[k] * r
            if (fur > 0) rad *= 1 + fur * (furHash(k, e.furSeed) - 0.5)
            var px = ca * rad
            var py = sa * rad
            if (m >= 0.005) {
                val rr = MochiGeometry.rrPoint(ca, sa, tw, th, tr)
                px = lerp(px, rr.x, m)
                py = lerp(py, rr.y, m)
            }
            if (i == 0) p.m(px, py) else p.l(px, py)
        }
        p.close()
        val socketScale = (1 - m * 1.6).coerceIn(0.0, 1.0)
        if (socketScale > 0.01) {
            // Clockwise like the outline, so the non-zero fill unions them (addOval would wind the other way and cut holes).
            for (s in g.sockets) {
                p.arcTo(Rect(Offset((s.x * r).toFloat(), (s.y * r).toFloat()), (s.r * socketScale * r).toFloat()), 0f, 359.9f, true)
                p.close()
            }
        }
        return p
    }

    private val furTile: ImageBitmap by lazy {
        val n = FUR_TILE_SIZE
        val px = IntArray(n * n) { i -> val v = furSample(i % n, i / n); (0xFF shl 24) or (v shl 16) or (v shl 8) or v }
        Bitmap.createBitmap(px, n, n, Bitmap.Config.ARGB_8888).asImageBitmap()
    }

    /** Multiplies the plush tile inside the body; below R = 18 the grain is finer than the pixels and only greys it. */
    fun drawFur(c: Canvas, e: MochiEngine, body: Path, r: Double, rx: Double, ry: Double) {
        if (e.geo == null || r <= 18 || e.morph >= 0.5) return
        val alpha = 0.55 * ((r - 18) / 8).coerceIn(0.0, 1.0) * (1 - e.morph * 2)
        if (alpha <= 0.01) return
        c.save()
        c.clipPath(body)
        val p = Paint().apply { blendMode = BlendMode.Multiply; this.alpha = alpha.toFloat(); isAntiAlias = true; filterQuality = androidx.compose.ui.graphics.FilterQuality.Low }
        val step = r * 0.62
        var y = -ry * 1.1
        while (y < ry * 1.1) {
            var x = -rx * 1.1
            while (x < rx * 1.1) {
                c.save()
                c.tr(x, y)
                c.scale((step / FUR_TILE_SIZE).toFloat(), (step / FUR_TILE_SIZE).toFloat())
                c.drawImageRect(furTile, IntOffset.Zero, IntSize(FUR_TILE_SIZE, FUR_TILE_SIZE), IntOffset.Zero, IntSize(FUR_TILE_SIZE, FUR_TILE_SIZE), p)
                c.restore()
                x += step
            }
            y += step
        }
        c.restore()
    }

    // ── Accessories ───────────────────────────────────────────────────────────

    class HeadPoint(val x: Double, val y: Double, val fx: Double, val fy: Double, val alpha: Double)

    /** A point on the head, projected the way the eyes are, and pulled out onto a shaped body's silhouette. */
    fun headPoint(e: MochiEngine, a0: Double, e0: Double, rx: Double, ry: Double, cullAt: Double): HeadPoint? {
        val az = a0 + e.yaw
        var el = e0 + e.pitch + e.roll
        el = (((el + PI) % (PI * 2)) + PI * 2) % (PI * 2) - PI
        val ce = cos(el)
        val depth = cos(az) * ce
        if (depth <= cullAt) return null
        fun clamp(v: Double) = v.coerceIn(0.2, 1.6)
        val restX = max(0.12, cos(a0))
        val restY = max(0.12, abs(cos(e0)))
        var hx = sin(az) * ce * rx
        var hy = -sin(el) * ry
        val g = e.geo
        if (g != null) {
            val th = atan2(hy, hx)
            val onEllipse = hypot(cos(th) * rx, sin(th) * ry)
            if (onEllipse > 0.0001) {
                val k = anchorRadius(th, g) * (rx / g.rxK) / onEllipse
                hx *= k; hy *= k
            }
        }
        return HeadPoint(
            hx, hy,
            clamp(max(0.18, cos(az)) / restX),
            clamp(max(0.18, abs(ce)) / restY),
            ((depth - cullAt) / 0.25).coerceIn(0.0, 1.0),
        )
    }

    private enum class Detail { FULL, SIMPLE, SILHOUETTE }

    /** Degrades rather than disappears: the accessory is the user's identity choice, a 12 px crown still reads. */
    private fun detail(r: Double) = if (r > 16) Detail.FULL else if (r > 11) Detail.SIMPLE else Detail.SILHOUETTE

    /** The creature's own material, for the parts made of Mochi. */
    private fun bodyMaterial(e: MochiEngine, darken: Double): Color {
        val c = e.bodyColor ?: MochiConst.BASE_TOP
        val k = 1 - darken
        return Color((c.r * k).toFloat().coerceIn(0f, 1f), (c.g * k).toFloat().coerceIn(0f, 1f), (c.b * k).toFloat().coerceIn(0f, 1f))
    }

    /** Places an accessory's own frame on the head (the caller restores) and returns its alpha, or null when out of sight. */
    private fun anchor(
        c: Canvas, e: MochiEngine, a0: Double, e0: Double, rx: Double, ry: Double, cullAt: Double, fade: Double, lift: Double, rotate: Double = 0.0,
    ): Double? {
        val p = headPoint(e, a0, e0, rx, ry, cullAt) ?: return null
        c.save()
        c.tr(p.x, p.y - lift)
        c.scale(p.fx.toFloat(), p.fy.toFloat())
        if (rotate != 0.0) c.rot(rotate)
        return p.alpha * fade
    }

    /** Ears, horns, antenna and sprout go before the body ([behind]); crown, bow, beret and sparkles after it. */
    fun drawAccessory(c: Canvas, e: MochiEngine, behind: Boolean, r: Double, rx: Double, ry: Double, body: Path, now: Double) {
        val item = e.character.accessory ?: return
        if (item.isBehind != behind || r <= 4) return
        val fade = (1 - e.morph * 1.6).coerceIn(0.0, 1.0) // a mailbox wears nothing
        if (fade <= 0.02) return
        val d = detail(r)
        val lift = ry * 0.06 * e.morph
        c.save()
        when (item) {
            MochiAccessory.CAT_EARS -> catEars(c, e, r, rx, ry, fade, lift, d)
            MochiAccessory.HORNS -> horns(c, e, r, rx, ry, fade, lift, d)
            MochiAccessory.ANTENNA -> antenna(c, e, r, rx, ry, fade, lift, d)
            MochiAccessory.SPROUT -> sprout(c, e, r, rx, ry, fade, lift, d, now)
            MochiAccessory.SPARKLES -> sparkles(c, e, r, rx, ry, fade, lift, d, now)
            MochiAccessory.BOW -> bow(c, e, r, rx, ry, fade, lift, d)
            MochiAccessory.CROWN -> crown(c, e, r, rx, ry, fade, lift, d)
            MochiAccessory.BERET -> beret(c, e, r, rx, ry, fade, lift, d, body)
        }
        c.restore()
    }

    private fun catEars(c: Canvas, e: MochiEngine, r: Double, rx: Double, ry: Double, fade: Double, lift: Double, d: Detail) {
        for (sd in intArrayOf(-1, 1)) {
            val alpha = anchor(c, e, sd * 0.62, 1.02, rx, ry, -0.20, fade, lift, sd * 0.38 + sin(sd * 0.62 + e.yaw) * 0.25) ?: continue
            // Bulged rather than straight, or it is a tortilla chip. The inner ear is the same shape at 0.52, 0.10 R lower.
            fun ear(k: Double, dy: Double) = Path().apply {
                m(-r * 0.32 * k, r * 0.18 * k + dy)
                q(-r * 0.28 * k, -r * 0.38 * k + dy, 0.0, -r * 0.80 * k + dy)
                q(r * 0.28 * k, -r * 0.38 * k + dy, r * 0.32 * k, r * 0.18 * k + dy)
                close()
            }
            c.drawPath(ear(1.0, 0.0), fill(bodyMaterial(e, 0.14), alpha))
            if (d != Detail.SILHOUETTE) c.drawPath(ear(0.52, r * 0.10), fill(Color(255, 120, 150), 0.5 * alpha))
            c.restore()
        }
    }

    private fun horns(c: Canvas, e: MochiEngine, r: Double, rx: Double, ry: Double, fade: Double, lift: Double, d: Detail) {
        for (sd in intArrayOf(-1, 1)) {
            val alpha = anchor(c, e, sd * 0.50, 1.12, rx, ry, -0.20, fade, lift) ?: continue
            val horn = Path().apply {
                m(-sd * r * 0.13, r * 0.10)
                q(sd * r * 0.015, -r * 0.30, sd * r * 0.17, -r * 0.62)
                q(sd * r * 0.26, -r * 0.26, sd * r * 0.15, r * 0.10)
                close()
            }
            c.drawPath(horn, fill(css("#F3E3C4"), alpha))
            if (d == Detail.FULL) {
                val p = stroke(Color(26, 20, 18), max(r * 0.035, 0.75), 0.16 * alpha)
                for (t in doubleArrayOf(0.32, 0.52, 0.72)) {
                    val y = lerp(r * 0.06, -r * 0.50, t)
                    val half = lerp(r * 0.12, r * 0.045, t)
                    c.drawLine(Offset((-half * 0.6 + sd * r * 0.02).toFloat(), y.toFloat()), Offset((half + sd * r * 0.02).toFloat(), (y - r * 0.02).toFloat()), p)
                }
            }
            c.restore()
        }
    }

    private fun antenna(c: Canvas, e: MochiEngine, r: Double, rx: Double, ry: Double, fade: Double, lift: Double, d: Detail) {
        val alpha = anchor(c, e, 0.0, 1.30, rx, ry, -0.60, fade, lift) ?: return
        // The gap between yaw and its target is the head's speed: free, and nothing to fall out of sync.
        val sway = (e.yaw - e.tgYaw) * r * 0.9
        val bob = (e.pitch - e.tgPitch) * r * 0.5
        val tipX = sway
        val tipY = -r * 0.62 + bob
        if (d != Detail.SILHOUETTE) {
            val stalk = Path().apply { m(0.0, 0.0); q(sway * 0.35, -r * 0.34, tipX, tipY) }
            c.drawPath(stalk, stroke(bodyMaterial(e, 0.22), max(r * 0.085, 0.9), alpha))
        }
        val bx = if (d == Detail.SILHOUETTE) 0.0 else tipX
        val by = if (d == Detail.SILHOUETTE) -r * 0.42 else tipY
        val br = r * (if (d == Detail.SILHOUETTE) 0.182 else 0.135)
        c.drawPath(oval(bx, by, br, br), fill(css("#FF4D6D"), alpha))
        if (d == Detail.FULL) c.drawPath(oval(bx - br * 0.26, by - br * 0.41, br * 0.26, br * 0.19), fill(Color.White, 0.75 * alpha))
        c.restore()
    }

    private fun sprout(c: Canvas, e: MochiEngine, r: Double, rx: Double, ry: Double, fade: Double, lift: Double, d: Detail, t: Double) {
        val alpha = anchor(c, e, 0.10, 1.33, rx, ry, -0.60, fade, lift) ?: return
        val green = css("#34D399")
        val stem = Path().apply { m(0.0, 0.0); q(-r * 0.02, -r * 0.14, r * 0.01, -r * 0.26) }
        c.drawPath(stem, stroke(green, max(r * 0.07, 0.9), alpha))
        val leaves = if (d == Detail.SILHOUETTE) listOf(1.0 to -1.35) else listOf(0.92 to -1.35, 1.0 to -0.15)
        leaves.forEachIndexed { i, (at, rot) ->
            c.save()
            c.tr(r * 0.01 * at, -r * 0.26 * at)
            c.rot(rot + sin(t * 1.6 + i) * 0.07)
            val len = r * (if (d == Detail.SILHOUETTE) 0.40 else 0.36)
            val half = r * 0.13
            val blade = Path().apply { m(0.0, 0.0); q(len * 0.5, -half, len, 0.0); q(len * 0.5, half, 0.0, 0.0); close() }
            c.drawPath(blade, fill(green, alpha))
            if (d == Detail.FULL) {
                c.drawLine(Offset.Zero, Offset((len * 0.9).toFloat(), 0f), stroke(Color.Black, max(r * 0.012, 0.5), 0.12 * alpha))
            }
            c.restore()
        }
        c.restore()
    }

    /** A four-point twinkle with concave sides: the shape of a glint, not of a star in the sky. */
    private fun sparklePath(r: Double): Path {
        val w = r * 0.17
        return Path().apply { m(0.0, -r); q(w, -w, r, 0.0); q(w, w, 0.0, r); q(-w, w, -r, 0.0); q(-w, -w, 0.0, -r); close() }
    }

    private fun sparkles(c: Canvas, e: MochiEngine, r: Double, rx: Double, ry: Double, fade: Double, lift: Double, d: Detail, t: Double) {
        // Quieter while the bot throws its own sparks, so the state signal stays louder than the decoration.
        val busy = if (e.particles.any { it.type == ParticleType.SPARK }) 0.4 else 1.0
        val spec = listOf(Triple(-1.05, 0.80, 0.21), Triple(0.95, 1.02, 0.16), Triple(-0.45, 1.34, 0.12), Triple(1.20, 0.48, 0.17))
        val shown = if (d == Detail.SILHOUETTE) spec.take(2) else spec
        shown.forEachIndexed { i, (a0, e0, size) ->
            val p = headPoint(e, a0, e0, rx, ry, -0.35) ?: return@forEachIndexed
            val twinkle = 0.35 + 0.65 * max(0.0, sin(t * 2.1 + i * 1.7))
            c.save()
            c.tr(p.x * 1.26, p.y * 1.26 - lift)
            c.rot(t * 0.6 + i)
            c.drawPath(sparklePath(r * size * (0.75 + 0.35 * twinkle)), fill(css("#F7B32B"), p.alpha * fade * twinkle * busy))
            c.restore()
        }
    }

    private fun bow(c: Canvas, e: MochiEngine, r: Double, rx: Double, ry: Double, fade: Double, lift: Double, d: Detail) {
        val alpha = anchor(c, e, -0.72, 0.88, rx, ry, 0.0, fade, lift, 0.22 + sin(e.yaw) * 0.18) ?: return
        val pink = css("#FF4D6D")
        if (d != Detail.SILHOUETTE) {
            val tails = stroke(pink, max(r * 0.07, 0.8), alpha)
            for (sd in intArrayOf(-1, 1)) c.drawPath(Path().apply { m(0.0, 0.0); q(sd * r * 0.02, r * 0.16, sd * r * 0.18, r * 0.28) }, tails)
        }
        for (sd in intArrayOf(-1, 1)) {
            val loop = Path().apply {
                m(0.0, 0.0)
                q(sd * r * 0.20, -r * 0.24, sd * r * 0.40, -sd * r * 0.02)
                q(sd * r * 0.22, r * 0.20, 0.0, 0.0)
                close()
            }
            c.drawPath(loop, fill(pink, alpha))
        }
        c.drawPath(roundRect(-r * 0.065, -r * 0.055, r * 0.13, r * 0.11, r * 0.05), fill(css("#D43B57"), alpha))
        c.restore()
    }

    private fun crown(c: Canvas, e: MochiEngine, r: Double, rx: Double, ry: Double, fade: Double, lift: Double, d: Detail) {
        val alpha = anchor(c, e, 0.0, 1.17, rx, ry, -0.35, fade, lift, sin(e.yaw) * 0.16) ?: return // a crown tips
        val points = Path().apply {
            m(-r * 0.40, -r * 0.02); l(-r * 0.26, -r * 0.34); l(-r * 0.13, -r * 0.08); l(0.0, -r * 0.40)
            l(r * 0.13, -r * 0.08); l(r * 0.26, -r * 0.34); l(r * 0.40, -r * 0.02); close()
        }
        if (d == Detail.SILHOUETTE) {
            c.drawPath(points, fill(css("#F7B32B"), alpha))
            c.restore()
            return
        }
        val g = Paint().apply {
            isAntiAlias = true; this.alpha = alpha.toFloat().coerceIn(0f, 1f)
            shader = LinearGradientShader(Offset(0f, (-r * 0.40).toFloat()), Offset(0f, (r * 0.14).toFloat()), listOf(css("#F7B32B"), css("#D99415")))
        }
        c.drawPath(points, g)
        c.drawPath(roundRect(-r * 0.40, -r * 0.04, r * 0.80, r * 0.18, r * 0.05), fill(css("#E8A520"), alpha))
        if (d == Detail.FULL) {
            for ((jx, hex) in listOf(-0.26 to "#FF4D6D", 0.0 to "#7CC7FF", 0.26 to "#FF4D6D")) {
                c.drawPath(oval(r * jx, -r * 0.27, r * 0.045, r * 0.045), fill(css(hex), alpha))
            }
        }
        c.restore()
    }

    private fun beret(c: Canvas, e: MochiEngine, r: Double, rx: Double, ry: Double, fade: Double, lift: Double, d: Detail, body: Path) {
        // The contact shadow is what makes it sit *on* the head; clipped, or it smears off the side.
        if (d != Detail.SILHOUETTE) {
            c.save()
            c.clipPath(body)
            c.drawPath(oval(-r * 0.10, -ry * 0.72, r * 0.23, r * 0.05), fill(Color.Black, fade * 0.18))
            c.restore()
        }
        // Pulled down over the head, lower than the other hats.
        val alpha = anchor(c, e, -0.34, 1.02, rx, ry, -0.30, fade, lift, -0.24 + sin(e.yaw) * 0.14) ?: return
        val dome = Path().apply {
            arcTo(Rect((-r * 0.62).toFloat(), (r * 0.05 - r * 0.34).toFloat(), (r * 0.62).toFloat(), (r * 0.05 + r * 0.34).toFloat()), 180f, 180f, true)
            close()
        }
        c.drawPath(dome, fill(css("#1F2228"), alpha))
        c.drawPath(roundRect(-r * 0.64, r * 0.01, r * 1.28, r * 0.095, r * 0.047), fill(css("#0E1013"), alpha))
        if (d != Detail.SILHOUETTE) c.drawPath(oval(-r * 0.14, -r * 0.26, r * 0.065, r * 0.065), fill(css("#333842"), alpha))
        c.restore()
    }

    // ── Christmas ─────────────────────────────────────────────────────────────

    /** How much bigger a Christmas eye is drawn on a mini: less than the 1.9x of plain eyes, or two baubles meet. */
    const val FESTIVE_MINI_EYE = 1.5

    class Frame(
        val head: FestiveHead?,
        val eyes: FestiveEyes?,
        val eyewear: Boolean,
        val texture: List<FestivePrim>?,
        val extra: FestiveExtra?,
        val restX: Double, val restY: Double,
        val paint: FestivePaint,
        /** A mailbox wears nothing: the fade the accessories get. */
        val fade: Double,
        /** Data units (R = 100) to the canvas's. */
        val k: Double,
    )

    /** What this Mochi has on for Christmas, looked up for its body, or null: every Mochi that never dressed up. */
    fun frame(e: MochiEngine, r: Double, now: Double, ink: String): Frame? {
        val f = e.character.festive ?: return null
        if (f.isEmpty || r <= 4) return null
        val parts = FestiveArt.body(e.character.shape?.key ?: "classic") ?: return null
        return Frame(
            head = f.head?.let { parts.heads[it] },
            eyes = f.eyes?.let { parts.eyes[it] },
            eyewear = f.isEyewear,
            texture = f.texture?.let { parts.textures[it] },
            extra = f.extra?.let { parts.extras[it] },
            restX = parts.restX, restY = parts.restY,
            paint = FestiveArt.mochiPaint(e.bodyColor ?: MochiConst.BASE_TOP, f.texture, ink, now),
            fade = (1 - e.morph * 1.6).coerceIn(0.0, 1.0),
            k = r / 100,
        )
    }

    /** A hat behind or in front of the body, leaning a quarter as far as the face travels so it does not look glued. */
    fun drawFestiveHead(c: Canvas, e: MochiEngine, f: Frame, prims: List<FestivePrim>, rx: Double, ry: Double, body: Path) {
        if (f.fade <= 0.02) return
        val dx = sin(e.yaw) * rx * 0.25
        val dy = -sin(e.pitch) * ry * 0.12 - ry * 0.06 * e.morph
        drawFestive(c, prims, f.paint, f.fade, body, dx, dy, f.k)
    }

    private fun pathOf(prim: FestivePrim): Path {
        (prim.path as? Path)?.let { return it }
        val p = Path()
        for (op in FestiveArt.ops(prim.d)) when (op) {
            is FestiveArt.Op.Move -> p.m(op.x, op.y)
            is FestiveArt.Op.Line -> p.l(op.x, op.y)
            is FestiveArt.Op.Quad -> p.q(op.x1, op.y1, op.x, op.y)
            is FestiveArt.Op.Cubic -> p.cubicTo(op.x1.toFloat(), op.y1.toFloat(), op.x2.toFloat(), op.y2.toFloat(), op.x.toFloat(), op.y.toFloat())
            FestiveArt.Op.Close -> p.close()
        }
        prim.path = p
        return p
    }

    /**
     * Draws a list of prims (festive.ts `drawFestive`). The canvas arrives with its origin at the body centre; [tx]/[ty]
     * move the data and [scale] takes it to the canvas's units, both inside the clip, never before it. Only prims marked
     * clipped are clipped to [clip]; consecutive ones share one clip.
     */
    fun drawFestive(c: Canvas, prims: List<FestivePrim>, paint: FestivePaint, alpha: Double, clip: Path?, tx: Double = 0.0, ty: Double = 0.0, scale: Double = 1.0) {
        if (prims.isEmpty() || alpha <= 0.004) return
        c.save()
        var open = -1 // -1 nothing open, 0 an unclipped group, 1 a clipped one
        for (prim in prims) {
            val fill = prim.fill?.let { FestiveArt.resolve(it, paint) }
            val stroke = prim.stroke?.let { FestiveArt.resolve(it, paint) }
            if (fill == null && stroke == null) continue
            val o = if (prim.light != null && paint.time != null) FestiveArt.light(prim.light, paint.time) else prim.opacity
            if (o <= 0.004) continue
            val want = if (prim.clipped && clip != null) 1 else 0
            if (want != open) {
                if (open != -1) c.restore()
                c.save()
                if (want == 1) c.clipPath(clip!!)
                if (tx != 0.0 || ty != 0.0) c.tr(tx, ty)
                if (scale != 1.0) c.scale(scale.toFloat(), scale.toFloat())
                open = want
            }
            val path = pathOf(prim)
            val a = alpha * o
            val f = fill?.let { runCatching { css(it) }.getOrNull() }
            val s = stroke?.let { runCatching { css(it) }.getOrNull() }
            if (f != null) c.drawPath(path, fill(f, a))
            if (s != null) c.drawPath(path, stroke(s, prim.width, a, StrokeCap.Round, StrokeJoin.Round))
        }
        if (open != -1) c.restore()
        c.restore()
    }
}
