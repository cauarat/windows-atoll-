package com.cauarati.notchy.mochi

import android.graphics.Typeface
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Canvas
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.LinearGradientShader
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.PaintingStyle
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.RadialGradientShader
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import com.cauarati.notchy.mochi.outfit.ComposeGfx
import com.cauarati.notchy.mochi.outfit.Ctx2D
import com.cauarati.notchy.mochi.outfit.Outfit
import com.cauarati.notchy.mochi.outfit.OutfitState
import com.cauarati.notchy.mochi.outfit.PUMPKIN_BODY
import com.cauarati.notchy.mochi.outfit.Css
import com.cauarati.notchy.mochi.outfit.drawOutfitBehind
import com.cauarati.notchy.mochi.outfit.drawOutfitFront
import com.cauarati.notchy.mochi.outfit.makeHead
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * Compose Canvas port of BotEngine.draw() in windows/src/mochi/engine.ts (the Mac's BotEngine.swift).
 * Draws hands, body, blush, eyes, mouth, badge and particles, Notchy's characters (shapes, eyes, accessories and
 * Christmas parts, MochiWear) and Coucou's outfits (mochi/outfit), which only a classic Mochi wears.
 */
object MochiPainter {
    private val INK = Color(26, 20, 18)
    private val MINI_INK = Color(16, 19, 26)

    private fun Rgb.color(a: Double = 1.0) =
        Color(r.toFloat().coerceIn(0f, 1f), g.toFloat().coerceIn(0f, 1f), b.toFloat().coerceIn(0f, 1f), a.toFloat().coerceIn(0f, 1f))

    private fun cssColor(s: String): Color = Css.parse(s).let { Color((it.r / 255).toFloat(), (it.g / 255).toFloat(), (it.b / 255).toFloat(), it.a.toFloat()) }

    private fun fillPaint(c: Color) = Paint().apply { color = c; isAntiAlias = true }
    private fun strokePaint(c: Color, w: Float) = Paint().apply {
        color = c; isAntiAlias = true; style = PaintingStyle.Stroke; strokeWidth = w; strokeCap = StrokeCap.Round
    }

    fun bodyPath(e: MochiEngine, rx: Double, ry: Double, r: Double): Path {
        val pts = MochiGeometry.bodyPoints(rx, ry, r, e.morph)
        return Path().apply {
            pts.forEachIndexed { i, p -> if (i == 0) moveTo(p.x.toFloat(), p.y.toFloat()) else lineTo(p.x.toFloat(), p.y.toFloat()) }
            close()
        }
    }

    /**
     * Draws Mochi centred in this DrawScope. `nowSec` drives spirals, wave and badge pulses.
     *
     * Everything is drawn in dp, the Mac's points: the size thresholds the characters degrade at (a crown down to its
     * silhouette, the plush grain off below R = 18) then mean what they mean on the island.
     */
    fun DrawScope.drawMochi(e: MochiEngine, nowSec: Double) {
        val k = density.toDouble().coerceAtLeast(0.1)
        val w = size.width / k
        val h = size.height / k
        val r = w * 0.3
        val g = e.geo
        val rx = r * (g?.rxK ?: 1.14)
        val ry = r * (g?.ryK ?: 0.88)
        val overhang = e.particleOverhang / k
        val cx = w / 2 + e.ox * r
        val cy = h / 2 + overhang / 2 + e.oy * r + r * 0.06

        drawIntoCanvas { c ->
            c.save()
            c.scale(k.toFloat(), k.toFloat())
            // With an outfit on, a roll turns the whole character, hat included, as one piece.
            if (e.rigidRoll && abs(e.roll) > 0.001) {
                c.translate(cx.toFloat(), cy.toFloat())
                c.rotate((e.roll * 180 / PI).toFloat())
                c.translate(-cx.toFloat(), -cy.toFloat())
            }
            drawHandsBehind(c, e, nowSec, r, rx, ry, cx, cy)

            c.save()
            c.translate(cx.toFloat(), cy.toFloat())
            if (e.tilt != 0.0) c.rotate((e.tilt * 180 / PI).toFloat())
            // Squash toward the shape's own anchor rather than its middle: a pointy pal scaled about its centre melts.
            val anchorY = ((g?.squashAnchorY ?: 0.0) * r).toFloat()
            if (anchorY != 0f) c.translate(0f, anchorY)
            c.scale(e.sx.toFloat(), e.sy.toFloat())
            if (anchorY != 0f) c.translate(0f, -anchorY)

            val ink = if (e.isMini) "rgb(16,19,26)" else "rgb(26,20,18)"
            val body = if (g != null) MochiWear.shapedPath(e, g, r) else bodyPath(e, rx, ry, r)
            // Christmas, if this Mochi wears any of it; null for everybody else, and every line that mentions it is skipped.
            val fest = MochiWear.frame(e, r, nowSec, ink)
            // One thing on the head at a time: a Santa hat over a crown is a pile.
            val hat = fest?.head
            // Coucou's outfits are the phone's own extra: a pill that wears a Notchy character on the computer wears that instead.
            val dressed = !e.isMini && e.outfit != Outfit.NONE && e.character.isClassic
            val head = if (dressed) makeHead(r, e.yaw, e.pitch, e.physDx, e.physDy) else null
            val outfitState = OutfitState(e.outfitPresence, e.morph)
            val outfitCtx = if (head != null) Ctx2D(ComposeGfx(c, Rect(Offset(-w.toFloat(), -h.toFloat()), Offset(w.toFloat(), h.toFloat())))) else null
            if (head != null && outfitCtx != null) drawOutfitBehind(outfitCtx, e.outfit, head, outfitState)

            // Behind the body, so it swallows their base and they look grown rather than stuck on.
            if (hat != null && fest != null) MochiWear.drawFestiveHead(c, e, fest, hat.behind, rx, ry, body)
            else MochiWear.drawAccessory(c, e, true, r, rx, ry, body, nowSec)
            drawBody(c, e, body, r, rx, ry)
            fest?.texture?.let { MochiWear.drawFestive(c, it, fest.paint, fest.fade, body, 0.0, 0.0, fest.k) }

            val blushVal = max(e.blush, e.tint * 0.5) * (1 - e.morph)
            if (blushVal > 0.01) {
                c.save()
                c.clipPath(body)
                val yOffset = sin(e.yaw) * rx * 0.8
                val p = fillPaint(Color(255, 120, 150, (255 * 0.5 * blushVal).toInt().coerceIn(0, 255)))
                for (sd in intArrayOf(-1, 1)) {
                    c.drawOval(
                        Rect(
                            (sd * rx * 0.55 + yOffset - r * 0.17).toFloat(), (ry * 0.2 - r * 0.1).toFloat(),
                            (sd * rx * 0.55 + yOffset + r * 0.17).toFloat(), (ry * 0.2 + r * 0.1).toFloat(),
                        ), p,
                    )
                }
                c.restore()
            }

            drawEyes(c, e, nowSec, body, r, rx, ry, fest)
            if (e.morph > 0.05) drawMouth(c, e, body, r)
            // Over the face, then whatever is on the head, then what hangs in front of everything: a beard goes under
            // the hat's brim, falling snow over it.
            fest?.extra?.let { MochiWear.drawFestive(c, it.back, fest.paint, fest.fade, body, 0.0, 0.0, fest.k) }
            if (hat != null && fest != null) MochiWear.drawFestiveHead(c, e, fest, hat.front, rx, ry, body)
            else MochiWear.drawAccessory(c, e, false, r, rx, ry, body, nowSec)
            fest?.extra?.let { MochiWear.drawFestive(c, it.front, fest.paint, fest.fade, body, 0.0, 0.0, fest.k) }

            if (head != null && outfitCtx != null) drawOutfitFront(outfitCtx, e.outfit, head, outfitState)
            c.restore()

            val badge = e.badge
            if (badge != null && e.badgeS > 0.01 && e.morph < 0.25) drawBadge(c, e, nowSec, badge, r, cx, cy)
            drawParticles(c, e, r, cx, cy)
            c.restore()
        }
    }

    private fun drawBody(c: Canvas, e: MochiEngine, body: Path, r: Double, rx: Double, ry: Double) {
        val bodyColor = e.bodyColor
        if (bodyColor != null) {
            c.drawPath(body, fillPaint(bodyColor.color()))
            MochiWear.drawFur(c, e, body, r, rx, ry)
            // A pill's colour is a flat fill on the Mac (BotEngine): no gradient, no rim, no highlight. Only Coucou's pumpkin
            // outfit, which the phone keeps for a classic Mochi, shades it.
            if (e.isMini || e.outfit != Outfit.PUMPKIN) return
        } else {
            val p = Paint().apply {
                isAntiAlias = true
                shader = LinearGradientShader(
                    Offset((rx * 0.7).toFloat(), (-ry * 0.85).toFloat()), Offset((-rx * 0.8).toFloat(), (ry * 0.9).toFloat()),
                    listOf(MochiConst.BASE_TOP.color(), MochiConst.BASE_BOTTOM.color()),
                )
            }
            c.drawPath(body, p)
            // Fibres before the rim and the highlight, so the body still reads as lit rather than dusty.
            MochiWear.drawFur(c, e, body, r, rx, ry)
        }

        // The pumpkin's orange comes and goes with the outfit; a flat-coloured body only gets the shading while it is a pumpkin.
        val pumpkin = if (e.isMini || e.outfit != Outfit.PUMPKIN) 0.0 else min(1.0, e.outfitPresence * 2.5) * (1 - e.morph)
        var tail = 1f
        if (pumpkin > 0.001) {
            val pg = Paint().apply {
                isAntiAlias = true
                alpha = pumpkin.toFloat().coerceIn(0f, 1f)
                shader = LinearGradientShader(
                    Offset((rx * 0.7).toFloat(), (-ry * 0.85).toFloat()), Offset((-rx * 0.8).toFloat(), (ry * 0.9).toFloat()),
                    listOf(cssColor(PUMPKIN_BODY.first), cssColor(PUMPKIN_BODY.second)),
                )
            }
            c.drawPath(body, pg)
            if (bodyColor != null) tail = pumpkin.toFloat().coerceIn(0f, 1f)
        }

        val effectiveTint = e.tint * (1 - e.morph)
        if (effectiveTint > 0.01) {
            val tg = Paint().apply {
                isAntiAlias = true
                alpha = tail
                shader = LinearGradientShader(
                    Offset(0f, ry.toFloat()), Offset(0f, (-ry).toFloat()),
                    listOf(e.col.color(0.72 * effectiveTint), e.col.color(0.0)),
                )
            }
            c.drawPath(body, tg)
        }

        // Shade: transparent until 0.6 of the 0.15R..1.25R ramp, then black 20%.
        val outer = r * 1.25
        val shadeStart = ((r * 0.15 + 0.6 * (outer - r * 0.15)) / outer).toFloat()
        val sh = Paint().apply {
            isAntiAlias = true
            alpha = tail
            shader = RadialGradientShader(
                Offset.Zero, outer.toFloat(),
                listOf(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 51)),
                listOf(0f, shadeStart, 1f),
            )
        }
        c.drawPath(body, sh)

        val hc = Offset((rx * 0.34).toFloat(), (-ry * 0.46).toFloat())
        val hl = Paint().apply {
            isAntiAlias = true
            alpha = tail
            shader = RadialGradientShader(hc, (r * 0.42).toFloat(), listOf(Color(255, 255, 255, 140), Color(255, 255, 255, 0)))
        }
        c.drawPath(body, hl)
    }

    private class EyeSlot(val x: Double, val y: Double, val fx: Double, val fy: Double)

    /** Where one eye lands this frame, or null once it has turned behind the head. A frog's pupil slides in its eyeball. */
    private fun eyeSlot(e: MochiEngine, sd: Int, rx: Double, ry: Double, r: Double): EyeSlot? {
        val g = e.geo
        val roll = if (e.rigidRoll) 0.0 else e.roll // rolling with an outfit on, the whole body turns: the eyes must not roll again
        if (g != null && g.hasSockets) {
            val k = g.sockets[if (sd < 0) 0 else 1]
            var p = MochiConst.EYE_P + e.pitch + roll
            p = (((p + PI) % (PI * 2)) + PI * 2) % (PI * 2) - PI
            val travel = k.r * 0.42
            return EyeSlot(
                k.x * r + sin(e.yaw) * travel * r,
                k.y * r - sin(p) * travel * r + (if (e.morph > 0) ry * 0.14 * e.morph else 0.0),
                1.0, 1.0,
            )
        }
        val eyeYaw = sd * (g?.eyeSp ?: MochiConst.EYE_SP) + e.yaw
        var eyePitch = (g?.eyeP ?: MochiConst.EYE_P) + e.pitch + roll
        eyePitch = (((eyePitch + PI) % (PI * 2)) + PI * 2) % (PI * 2) - PI
        val cp = cos(eyePitch)
        if (cos(eyeYaw) * cp <= 0.04) return null
        return EyeSlot(
            sin(eyeYaw) * cp * rx,
            -sin(eyePitch) * ry + (if (e.morph > 0) ry * 0.14 * e.morph else 0.0),
            lerpD(max(0.18, cos(eyeYaw)), 1.0, e.morph * 0.7),
            lerpD(max(0.18, cp), 1.0, e.morph * 0.7),
        )
    }

    /** What an expression is drawn in when it happens behind a lens: the ordinary ink would vanish against the glass. */
    private fun glint(eye: MochiEye) = when (eye) {
        MochiEye.VISOR -> Color(0xFFDFF4FF)
        MochiEye.SHADES -> Color(0xFFFFD9A0)
        else -> Color.White
    }

    private fun drawEyes(c: Canvas, e: MochiEngine, nowSec: Double, body: Path, r: Double, rx: Double, ry: Double, fest: MochiWear.Frame?) {
        var shape = e.eyeOverride ?: e.cfg.eye
        if (e.morph > 0.5) {
            if (e.isChewing) shape = EyeShape.HAPPY
            else if (e.slotHTarget > 0.05 || e.slotH > 0.1) shape = EyeShape.CUP
        }
        // The character has the last word, after every animation above. Christmas eyes stand in for the character's own
        // while nothing is being expressed; glasses keep their frames on throughout. A mailbox wears nothing.
        val worn = if (fest != null && e.morph < 0.62) fest.eyes else null
        val festive = worn != null && MochiCharacter.isNeutral(shape)
        val dressed = if (e.morph < 0.62 && worn == null) e.character.resolve(shape) else EyeResolution.Plain(shape)

        c.save()
        c.clipPath(body)
        val ink = if (e.isMini) MINI_INK else INK
        val slots = listOf(-1 to eyeSlot(e, -1, rx, ry, r), 1 to eyeSlot(e, 1, rx, ry, r))

        // Lenses first, so the glints land inside them.
        val lens = if (dressed is EyeResolution.BehindLens) drawLens(c, e, dressed.eye, slots, r, rx) else null

        for ((sd, slot) in slots) {
            if (slot == null) continue
            // Sunglasses at 1.9x would merge into one blob on a small pill; a socketed body's pupils fill their eyeballs.
            val eyeMult = (if (e.isMini) (if (lens != null) 1.3 else 1.9) else 1.0) * (if (lens != null) 1.0 else e.geo?.eyeScale ?: 1.0)
            val ew = r * MochiConst.EYE_W * e.es * eyeMult
            val eh = r * MochiConst.EYE_H * e.es * eyeMult

            if (festive && fest != null && worn != null) {
                // The artwork is where the eye rests; carry it to where the eye is. The blink squashes it about its centre.
                val wide = shape == EyeShape.WIDE
                val grow = e.es * (if (e.isMini) MochiWear.FESTIVE_MINI_EYE else 1.0)
                c.save()
                c.translate(slot.x.toFloat(), slot.y.toFloat())
                c.scale((fest.k * grow * (if (wide) 1.16 else 1.0)).toFloat(), (fest.k * grow * (if (wide) 1.12 else 1.0) * max(e.open, 0.1)).toFloat())
                c.translate((-sd * fest.restX).toFloat(), (-fest.restY).toFloat())
                MochiWear.drawFestive(c, if (sd < 0) worn.left else worn.right, fest.paint, 1.0, null)
                c.restore()
                continue
            }

            c.save()
            if (lens != null) c.clipPath(lens)
            c.translate(slot.x.toFloat(), slot.y.toFloat())
            c.scale(slot.fx.toFloat(), slot.fy.toFloat())
            when (dressed) {
                is EyeResolution.Plain -> {
                    // Behind a pair of Christmas glasses the expression has a lens to stay inside.
                    val fit = if (worn != null && fest?.eyewear == true) 0.8 else 1.0
                    drawEyeShape(c, e, nowSec, dressed.shape, ew * fit, eh * fit, sd, ink)
                }
                is EyeResolution.Character -> drawCharacterEye(c, e, dressed.eye, ew, eh, dressed.wide, ink)
                // The expression still happens: you watch it through the lens.
                is EyeResolution.BehindLens -> drawEyeShape(c, e, nowSec, dressed.shape, ew * 0.62, eh * 0.62, sd, glint(dressed.eye))
            }
            c.restore()
        }
        c.restore()

        // What goes over both eyes at once (rosy cheeks, the frames of a pair of glasses): moved by the mean of the eyes.
        if (fest != null && worn != null && worn.over.isNotEmpty() && (festive || fest.eyewear)) {
            var mx = 0.0
            var my = 0.0
            var n = 0
            for ((sd, slot) in slots) {
                if (slot == null) continue
                mx += slot.x - sd * fest.restX * fest.k
                my += slot.y - fest.restY * fest.k
                n += 1
            }
            if (n > 0) MochiWear.drawFestive(c, worn.over, fest.paint, 1.0, body, mx / n, my / n, fest.k)
        }
    }

    /** The four eye styles that *are* the eye. Each honours `open`: a character that stopped blinking would stop looking alive. */
    private fun drawCharacterEye(c: Canvas, e: MochiEngine, style: MochiEye, rawW: Double, rawH: Double, wide: Boolean, ink: Color) {
        val w = if (wide) rawW * 1.16 else rawW
        val h = if (wide) rawH * 1.12 else rawH
        when (style) {
            MochiEye.DOT -> {
                val d = w * 0.92
                val hh = max(d * e.open, d * 0.26)
                c.drawPath(MochiWear.oval(0.0, 0.0, d / 2, hh / 2), fillPaint(ink))
            }
            MochiEye.PIXEL -> {
                // Square corners, deliberately: a blinking pixel must not turn back into a pill.
                val hh = max(w * 0.92 * e.open, w * 0.22)
                c.drawRect((-w * 0.46).toFloat(), (-hh / 2).toFloat(), (w * 0.46).toFloat(), (hh / 2).toFloat(), fillPaint(ink))
            }
            MochiEye.GLOSSY -> {
                val d = w * 1.24
                val hh = max(h * 1.22 * e.open, d * 0.26)
                val ball = MochiWear.oval(0.0, 0.0, d / 2, hh / 2)
                c.drawPath(ball, fillPaint(Color(0xFFFBFCFE)))
                c.drawPath(ball, MochiWear.stroke(Color(26, 20, 18), max(d * 0.035, 0.6), 0.22))
                // The pupil looks where the head looks, which is what makes these eyes rather than beads.
                val px = sin(e.yaw) * d * 0.13
                val py = -sin(e.pitch) * hh * 0.13
                val pd = min(d * 0.58, hh * 0.86)
                c.drawPath(MochiWear.oval(px, py, pd / 2, pd / 2), fillPaint(ink))
                if (e.open > 0.35) c.drawPath(MochiWear.oval(px - pd * 0.25, py - pd * 0.30, pd * 0.17, pd * 0.14), fillPaint(Color(1f, 1f, 1f, 0.92f)))
            }
            MochiEye.SLEEPY -> {
                // Already half shut: the lid moving is what you see.
                val hh = max(h * 0.44 * e.open, w * 0.20)
                roundRect(c, -w / 2, -hh / 2, w, hh, min(w / 2, hh / 2), fillPaint(ink))
                val lidY = lerpD(-hh / 2 - w * 0.10, -hh / 2, e.open)
                roundRect(c, -w * 0.60, lidY, w * 1.20, w * 0.17, w * 0.085, fillPaint(ink))
            }
            MochiEye.VISOR, MochiEye.SHADES -> {} // worn, not grown: drawLens
        }
    }

    /**
     * Visor and sunglasses: one piece across both eyes, in body coordinates. Returns the lens so the glints are clipped
     * to it. The lens never squashes with `open` (an opaque object with eyelids looks like melting hardware).
     */
    private fun drawLens(c: Canvas, e: MochiEngine, style: MochiEye, slots: List<Pair<Int, EyeSlot?>>, r: Double, rx: Double): Path? {
        val live = slots.mapNotNull { it.second }
        if (live.isEmpty()) return null // the face is round the back
        // One eye culled: hold the bar between the one we have and the silhouette, so it slides off the edge.
        val a = slots[0].second ?: EyeSlot(-rx * 0.98, live[0].y, 0.18, live[0].fy)
        val b = slots[1].second ?: EyeSlot(rx * 0.98, live[0].y, 0.18, live[0].fy)
        val span = hypot(b.x - a.x, b.y - a.y)
        val angle = atan2(b.y - a.y, b.x - a.x)
        val cx = (a.x + b.x) / 2
        val cy = (a.y + b.y) / 2
        // `es` thickens the lens but must not stretch the span, or a surprised bot's visor detaches from its eyes.
        val ew = r * MochiConst.EYE_W * (if (e.isMini) 1.3 else 1.0)
        val eh = r * MochiConst.EYE_H * e.es * (if (e.isMini) 1.3 else 1.0)

        val local = Path()
        if (style == MochiEye.VISOR) {
            val barW = min(span + ew * 2.7, rx * 1.62)
            val barH = eh * 0.92 * a.fy
            local.addPath(MochiWear.roundRect(-barW / 2, -barH / 2, barW, barH, barH / 2))
        } else {
            val lw = ew * 1.5
            val lh = eh * 1.02 * a.fy
            for (side in intArrayOf(-1, 1)) {
                val f = if (side < 0) a.fx else b.fx
                local.addPath(MochiWear.roundRect(side * span / 2 - (lw * f) / 2, -lh / 2, lw * f, lh, lh * 0.42))
            }
        }
        val m = android.graphics.Matrix().apply { setTranslate(cx.toFloat(), cy.toFloat()); preRotate((angle * 180 / PI).toFloat()) }
        fun place(p: Path): Path = Path().apply { asAndroidPath().set(p.asAndroidPath()); asAndroidPath().transform(m) }
        val placed = place(local)

        val frame = fillPaint(Color(0xFF15171C))
        if (style == MochiEye.SHADES) {
            // Bridge, then the lenses on top so the join disappears under them.
            val lh = eh * 1.02 * a.fy
            c.drawPath(place(MochiWear.roundRect(-span / 2, -lh * 0.16, span, lh * 0.24, lh * 0.12)), frame)
        }
        c.drawPath(placed, frame)
        if (style == MochiEye.VISOR) c.drawPath(placed, MochiWear.stroke(Color.White, max(eh * 0.055, 0.6), 0.14))
        return placed
    }

    private fun roundRect(c: Canvas, x: Double, y: Double, w: Double, h: Double, rad: Double, p: Paint) {
        val rr = max(0.0, min(rad, min(w / 2, h / 2))).toFloat()
        c.drawRoundRect(x.toFloat(), y.toFloat(), (x + w).toFloat(), (y + h).toFloat(), rr, rr, p)
    }

    private fun arcStroke(c: Canvas, cx: Double, cy: Double, rad: Double, startRad: Double, endRad: Double, p: Paint) {
        val path = Path().apply {
            arcTo(
                Rect((cx - rad).toFloat(), (cy - rad).toFloat(), (cx + rad).toFloat(), (cy + rad).toFloat()),
                (startRad * 180 / PI).toFloat(), ((endRad - startRad) * 180 / PI).toFloat(), true,
            )
        }
        c.drawPath(path, p)
    }

    private fun heartPath(s: Double) = Path().apply {
        val f = s.toFloat()
        moveTo(0f, f * 0.38f)
        cubicTo(-f * 1.05f, -f * 0.15f, -f * 0.5f, -f * 0.95f, 0f, -f * 0.38f)
        cubicTo(f * 0.5f, -f * 0.95f, f * 1.05f, -f * 0.15f, 0f, f * 0.38f)
        close()
    }

    private fun starPath(ro: Double, ri: Double) = Path().apply {
        for (i in 0 until 10) {
            val rad = if (i % 2 == 1) ri else ro
            val a = -PI / 2 + i * PI / 5
            val px = (cos(a) * rad).toFloat()
            val py = (sin(a) * rad).toFloat()
            if (i == 0) moveTo(px, py) else lineTo(px, py)
        }
        close()
    }

    private fun drawEyeShape(c: Canvas, e: MochiEngine, nowSec: Double, shape: EyeShape, w: Double, h: Double, sd: Int, ink: Color) {
        val fill = fillPaint(ink)
        when (shape) {
            EyeShape.WIDE -> drawEyeShape(c, e, nowSec, EyeShape.PILL, w * 1.16, h * 1.12, sd, ink)
            EyeShape.PILL -> {
                val hh = max(h * e.open, w * 0.3)
                roundRect(c, -w / 2, -hh / 2, w, hh, min(w / 2, hh / 2), fill)
            }
            EyeShape.DOT -> c.drawCircle(Offset.Zero, (w * 0.45).toFloat(), fill)
            EyeShape.LINE -> {
                c.save()
                c.rotate((-sd * 0.2 * 180 / PI).toFloat())
                roundRect(c, -w * 0.78, -w * 0.21, w * 1.56, w * 0.42, w * 0.21, fill)
                c.restore()
            }
            EyeShape.FLAT -> roundRect(c, -w * 0.72, -w * 0.2, w * 1.44, w * 0.4, w * 0.2, fill)
            EyeShape.HAPPY -> arcStroke(c, 0.0, h * 0.18, w * 0.82, PI * 1.12, PI * 1.88, strokePaint(ink, (w * 0.5).toFloat()))
            EyeShape.CLOSED -> arcStroke(c, 0.0, -h * 0.08, w * 0.78, PI * 0.15, PI * 0.85, strokePaint(ink, (w * 0.36).toFloat()))
            EyeShape.SPIRAL -> {
                val path = Path()
                var a = 0.0
                var first = true
                while (a < 4.4 * PI) {
                    val rad = w * 0.06 + a * w * 0.058
                    val aa = a + nowSec * 9 * sd
                    val px = (cos(aa) * rad).toFloat()
                    val py = (sin(aa) * rad).toFloat()
                    if (first) { path.moveTo(px, py); first = false } else path.lineTo(px, py)
                    a += 0.2
                }
                c.drawPath(path, strokePaint(ink, (w * 0.22).toFloat()))
            }
            EyeShape.HEART -> c.drawPath(heartPath(w * 1.2), fillPaint(Color(0xFF, 0x4D, 0x6D)))
            EyeShape.STAR -> {
                c.save()
                c.rotate((nowSec * 1.5 * sd * 180 / PI).toFloat())
                c.drawPath(starPath(w * 1.05, w * 0.46), fillPaint(Color(0xF7, 0xB3, 0x2B)))
                c.restore()
            }
            EyeShape.TIRED -> {
                roundRect(c, -w / 2, -h * 0.02, w, h * 0.38, w / 2, fill)
                roundRect(c, -w * 0.62, -h * 0.1, w * 1.24, w * 0.22, w * 0.11, fill)
            }
            EyeShape.WINK -> if (sd < 0) {
                val hh = max(h * e.open, w * 0.3)
                roundRect(c, -w / 2, -hh / 2, w, hh, min(w / 2, hh / 2), fill)
            } else {
                arcStroke(c, 0.0, h * 0.18, w * 0.82, PI * 1.12, PI * 1.88, strokePaint(ink, (w * 0.5).toFloat()))
            }
            EyeShape.CUP -> {
                // Flat top, rounded bottom corners (U shape), used while the box is open.
                val hh = max(h * e.open, w * 0.3)
                val cr = min(w / 2, hh / 2)
                val path = Path().apply {
                    moveTo((-w / 2).toFloat(), (-hh / 2).toFloat())
                    lineTo((w / 2).toFloat(), (-hh / 2).toFloat())
                    lineTo((w / 2).toFloat(), (hh / 2 - cr).toFloat())
                    quadraticBezierTo((w / 2).toFloat(), (hh / 2).toFloat(), (w / 2 - cr).toFloat(), (hh / 2).toFloat())
                    lineTo((-w / 2 + cr).toFloat(), (hh / 2).toFloat())
                    quadraticBezierTo((-w / 2).toFloat(), (hh / 2).toFloat(), (-w / 2).toFloat(), (hh / 2 - cr).toFloat())
                    close()
                }
                c.drawPath(path, fill)
            }
        }
    }

    /** Mailbox slot: dark pill cut into the box face, with rim and lip highlights. */
    private fun drawMouth(c: Canvas, e: MochiEngine, body: Path, r: Double) {
        val m = e.morph
        val hW = r * 1.8 * m
        val hH = e.slotH * r * m
        val hX = -hW / 2
        val boxTop = -r * (0.88 + 0.06 * m)
        val hY = boxTop + r * 0.08 * m

        c.save()
        c.clipPath(body)
        val rim = strokePaint(Color(255, 255, 255, (255 * 0.55 * m).toInt().coerceIn(0, 255)), 1f)
        c.drawLine(Offset((-r * 0.9 * m).toFloat(), (boxTop + 1).toFloat()), Offset((r * 0.9 * m).toFloat(), (boxTop + 1).toFloat()), rim)

        if (hH > 0.8) {
            val hR = min(hW / 2, hH / 2)
            val g = Paint().apply {
                isAntiAlias = true
                shader = LinearGradientShader(
                    Offset(0f, hY.toFloat()), Offset(0f, (hY + hH).toFloat()),
                    listOf(Color(7, 8, 10), Color(16, 19, 26)),
                )
            }
            roundRect(c, hX, hY, hW, hH, hR, g)
            if (hH > 4) {
                val lipR = min(hR, (hW - 2) / 2)
                val lip = strokePaint(Color(255, 255, 255, (255 * 0.28 * m).toInt().coerceIn(0, 255)), 1f)
                c.drawLine(
                    Offset((hX + lipR).toFloat(), (hY + hH - 0.5).toFloat()),
                    Offset((hX + hW - lipR).toFloat(), (hY + hH - 0.5).toFloat()), lip,
                )
            }
        }
        c.restore()
    }

    /** Hands sit behind the body, so they are drawn first, in world coordinates. */
    private fun drawHandsBehind(c: Canvas, e: MochiEngine, n: Double, r: Double, rx: Double, ry: Double, cx: Double, cy: Double) {
        if (e.hands <= 0.01 || e.isMini) return
        if (r <= 14) return // meaningless at compact sizes

        val bodyH = 2 * ry
        val hew = 0.3 * ry * e.hands
        val heh = 0.26 * ry * e.hands
        // For a shaped body these come off the outline at hand height, not off the bounding box.
        val hg = e.geo
        val hwB = (if (hg != null) hg.handX * r else rx) * e.sx
        val hhB = (if (hg != null) hg.handY * r else ry) * e.sy
        val isWaving = n >= e.waveStart && e.waveStart > 0 && n < e.waveUntil

        for (sd in intArrayOf(-1, 1)) {
            var localX: Double
            var localY: Double
            var handRot = 0.0

            if (sd > 0 && isWaving) {
                val wt = n - e.waveStart
                val rise = min(1.0, wt / 0.18)
                val riseEased = 1 - (1 - rise).pow(3)
                val restX = hwB * 1.08
                val restY = hhB * 0.7
                val oscX = cos(13 * wt) * 0.06 * bodyH
                val oscY = -sin(13 * wt) * 0.14 * bodyH
                val waveX = hwB * 1.1 + oscX
                val waveY = -hhB * 0.15 + oscY
                localX = restX + (waveX - restX) * riseEased
                localY = restY + (waveY - restY) * riseEased
                handRot = (-0.5 + sin(13 * wt) * 0.35) * riseEased
            } else if (sd < 0 && isWaving) {
                val wt = n - e.waveStart
                localX = -hwB * 1.08
                localY = hhB * 0.7 + sin(6 * wt) * 0.04 * bodyH
            } else {
                localX = sd * hwB * 1.08
                localY = hhB * 0.7
            }

            val cosT = cos(e.tilt)
            val sinT = sin(e.tilt)
            val worldX = cx + cosT * localX - sinT * localY
            val worldY = cy + sinT * localX + cosT * localY

            c.save()
            c.translate(worldX.toFloat(), worldY.toFloat())
            if (handRot != 0.0) c.rotate((handRot * 180 / PI).toFloat())
            val top = e.bodyColor?.mix(Rgb(1.0, 1.0, 1.0), 0.35) ?: MochiConst.BASE_TOP
            val bottom = e.bodyColor ?: MochiConst.BASE_BOTTOM
            val fill = Paint().apply {
                isAntiAlias = true
                shader = LinearGradientShader(
                    Offset((hew * 0.7).toFloat(), (-heh * 0.85).toFloat()), Offset((-hew * 0.8).toFloat(), (heh * 0.9).toFloat()),
                    listOf(top.color(), bottom.color()),
                )
            }
            val oval = Rect((-hew).toFloat(), (-heh).toFloat(), hew.toFloat(), heh.toFloat())
            c.drawOval(oval, fill)
            c.drawOval(oval, strokePaint(Color(0, 0, 0, 20), 1f))
            c.restore()
        }
    }

    private fun drawBadge(c: Canvas, e: MochiEngine, t: Double, badge: Badge, r: Double, cx: Double, cy: Double) {
        val bs = e.badgeS * (if (e.isMini) 1.25 else 1.0)
        val bx = cx - r * 0.72 * e.sx
        val by = cy - r * 0.72 * e.sy
        val col = badge.color.color()
        val black = fillPaint(Color.Black)

        c.save()
        c.translate(bx.toFloat(), by.toFloat())
        c.scale(bs.toFloat(), bs.toFloat())

        when (badge.kind) {
            BadgeKind.DOTS -> if (e.isMini) {
                val phase = (t * 2.4) % 1
                val dotR = r * 0.22 * (1 + 0.25 * sin(phase * PI * 2))
                c.drawCircle(Offset.Zero, (r * 0.2).toFloat(), black)
                c.drawCircle(Offset.Zero, dotR.toFloat(), fillPaint(col))
            } else {
                val pw = r * 0.72
                val ph = r * 0.36
                roundRect(c, -pw / 2, -ph / 2, pw, ph, ph / 2, fillPaint(col))
                for (i in 0 until 3) {
                    val phase = (((t * 2.4 - i * 0.22) % 1) + 1) % 1
                    val dotR = r * 0.055 * (1 + 0.4 * max(0.0, sin(phase * PI * 2)))
                    c.drawCircle(Offset(((i - 1) * r * 0.18).toFloat(), 0f), dotR.toFloat(), fillPaint(Color.White))
                }
            }
            BadgeKind.BANG, BadgeKind.QUESTION -> {
                c.drawCircle(Offset.Zero, (r * 0.3).toFloat(), black)
                c.drawCircle(Offset.Zero, (r * 0.23).toFloat(), fillPaint(col))
                if (!e.isMini) {
                    drawText(c, if (badge.kind == BadgeKind.BANG) "!" else "?", 0f, (r * 0.02).toFloat(), (r * 0.32).toFloat(), android.graphics.Color.WHITE, 1f)
                }
            }
            BadgeKind.DOT -> {
                c.drawCircle(Offset.Zero, (r * 0.2).toFloat(), black)
                c.drawCircle(Offset.Zero, (r * 0.135).toFloat(), fillPaint(col))
            }
        }
        c.restore()
    }

    private fun drawText(c: Canvas, s: String, x: Float, y: Float, size: Float, argb: Int, alpha: Float) {
        val p = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = argb
            textSize = size
            textAlign = android.graphics.Paint.Align.CENTER
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            this.alpha = (255 * alpha).toInt().coerceIn(0, 255)
        }
        val centred = y - (p.ascent() + p.descent()) / 2
        c.nativeCanvas.drawText(s, x, centred, p)
    }

    private fun drawParticles(c: Canvas, e: MochiEngine, r: Double, cx: Double, cy: Double) {
        for (p in e.particles) {
            if (p.age <= 0) continue
            val k = p.age / p.life
            val a = if (k < 0.2) k / 0.2 else 1 - (k - 0.2) / 0.8
            val px = cx + (p.x + p.vx * p.age) * r * 1.3
            val py = cy + (p.y + p.vy * p.age) * r * 1.3
            val sz = r * p.size * (1 + k * 0.4)
            val alpha = a.coerceIn(0.0, 1.0).toFloat()

            c.save()
            c.translate(px.toFloat(), py.toFloat())
            fun tinted(base: Color) = fillPaint(base.copy(alpha = alpha))
            when (p.type) {
                ParticleType.HEART -> {
                    c.rotate((sin(p.age * 6) * 0.3 * 180 / PI).toFloat())
                    c.drawPath(heartPath(sz), tinted(Color(0xFF, 0x4D, 0x6D)))
                }
                ParticleType.STAR -> {
                    c.rotate(((p.rot + p.age * 2) * 180 / PI).toFloat())
                    c.drawPath(starPath(sz, sz * 0.45), tinted(Color(0xF7, 0xB3, 0x2B)))
                }
                ParticleType.SPARK -> {
                    c.rotate((p.rot * 180 / PI).toFloat())
                    c.drawPath(starPath(sz * 0.8, sz * 0.18), tinted(Color.White))
                }
                ParticleType.SWEAT -> {
                    val path = Path().apply {
                        val s = sz.toFloat()
                        moveTo(0f, -s)
                        quadraticBezierTo(s * 0.8f, s * 0.2f, 0f, s * 0.6f)
                        quadraticBezierTo(-s * 0.8f, s * 0.2f, 0f, -s)
                    }
                    c.drawPath(path, tinted(Color(0x7C, 0xC7, 0xFF)))
                }
                ParticleType.Z -> drawText(c, "z", 0f, 0f, (sz * 1.9).toFloat(), android.graphics.Color.rgb(209, 219, 235), alpha)
            }
            c.restore()
        }
    }

    private fun lerpD(a: Double, b: Double, t: Double) = a + (b - a) * t

}
