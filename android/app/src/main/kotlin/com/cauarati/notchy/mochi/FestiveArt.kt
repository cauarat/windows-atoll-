package com.cauarati.notchy.mochi

import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.PI
import kotlin.math.cos

/**
 * What a Mochi wears at Christmas: the artwork scripts/generate-mochi-festive.mjs works out per body, read from
 * assets/festive.json (the same document the Mac and windows/src/mochi/festive.ts draw from), and the rules that
 * colour and light it. The painter (MochiPainter) decides where each layer goes.
 *
 * Pure JVM, so the unit tests read the asset straight from the source tree.
 */
object FestiveArt {
    /** Where the document comes from: the app installs a reader of its asset; nothing is read until a Mochi dresses up. */
    @Volatile var source: (() -> String)? = null

    @Volatile private var loaded: FestiveData? = null
    @Volatile private var failed = false

    /** The document, parsed on first use (318 KB nobody pays for in July); null when it cannot be read. */
    fun data(): FestiveData? {
        loaded?.let { return it }
        if (failed) return null
        synchronized(this) {
            loaded?.let { return it }
            val text = try { source?.invoke() } catch (_: Exception) { null }
            val parsed = text?.let { runCatching { parse(it) }.getOrNull() }
            if (parsed == null) failed = text != null else loaded = parsed
            return parsed
        }
    }

    /** One body's parts: a shape key, or `classic` (also for an unknown key). */
    fun body(key: String): FestiveBody? = data()?.let { it.bodies[key] ?: it.bodies["classic"] }

    @Volatile private var loading = false

    /**
     * The same, for a frame: never parses on the caller's thread. The first Mochi to dress up starts the read in the
     * background and goes without its Christmas parts until it is done, a frame or two later.
     */
    fun bodyIfReady(key: String): FestiveBody? {
        loaded?.let { return it.bodies[key] ?: it.bodies["classic"] }
        if (!loading && !failed && source != null) {
            loading = true
            Thread({ data() }, "notchy-festive").apply { isDaemon = true }.start()
        }
        return null
    }

    fun parse(json: String): FestiveData {
        val o = JSONObject(json)
        val bodies = o.getJSONObject("bodies")
        val out = HashMap<String, FestiveBody>()
        for (k in bodies.keys()) out[k] = body(bodies.getJSONObject(k))
        return FestiveData(o.optInt("version", 0), out)
    }

    private fun body(o: JSONObject): FestiveBody {
        val eye = o.getJSONObject("eye")
        return FestiveBody(
            restX = eye.getDouble("x"), restY = eye.getDouble("y"),
            heads = map(o.optJSONObject("heads")) { FestiveHead(prims(it.optJSONArray("b")), prims(it.optJSONArray("f"))) },
            eyes = map(o.optJSONObject("eyes")) { FestiveEyes(prims(it.optJSONArray("l")), prims(it.optJSONArray("r")), prims(it.optJSONArray("over"))) },
            textures = HashMap<String, List<FestivePrim>>().also { m ->
                val t = o.optJSONObject("textures") ?: return@also
                for (k in t.keys()) m[k] = prims(t.optJSONArray(k))
            },
            extras = map(o.optJSONObject("extras")) { FestiveExtra(prims(it.optJSONArray("a")), prims(it.optJSONArray("z"))) },
        )
    }

    private fun <T> map(o: JSONObject?, f: (JSONObject) -> T): Map<String, T> {
        val m = HashMap<String, T>()
        if (o != null) for (k in o.keys()) o.optJSONObject(k)?.let { m[k] = f(it) }
        return m
    }

    private fun prims(a: JSONArray?): List<FestivePrim> {
        if (a == null) return emptyList()
        return (0 until a.length()).mapNotNull { i ->
            val p = a.optJSONObject(i) ?: return@mapNotNull null
            FestivePrim(
                d = p.getString("d"),
                fill = p.optString("f", "").ifEmpty { null },
                stroke = p.optString("s", "").ifEmpty { null },
                width = p.optDouble("w", 1.0),
                opacity = p.optDouble("o", 1.0),
                clipped = p.optInt("c", 0) == 1,
                light = p.optString("k", "").ifEmpty { null },
            )
        }
    }

    // ── Light ─────────────────────────────────────────────────────────────────

    private fun smooth(x: Double) = x * x * (3 - 2 * x)

    /**
     * The opacity of a lit prim at [t] seconds (festive.ts `festiveLight`): the string lights are two sets taking
     * turns on a 2.2 s cycle, the star's three layers breathe together on 1.8 s.
     */
    fun light(k: String, t: Double): Double = when (k) {
        "bulbA", "bulbB", "glowA", "glowB" -> {
            val u = (((t % 2.2) + 2.2) % 2.2) / 2.2
            val a = when {
                u < 0.42 -> 1.0
                u < 0.5 -> 1 - smooth((u - 0.42) / 0.08)
                u < 0.92 -> 0.0
                else -> smooth((u - 0.92) / 0.08)
            }
            when (k) {
                "bulbA" -> 0.3 + 0.7 * a
                "bulbB" -> 0.3 + 0.7 * (1 - a)
                "glowA" -> 0.3 * a
                else -> 0.3 * (1 - a)
            }
        }
        "lit", "shineA", "shineB" -> {
            val c = 0.5 - 0.5 * cos((2 * PI * t) / 1.8)
            when (k) {
                "lit" -> 0.6 + 0.4 * c
                "shineA" -> 0.08 + 0.32 * c
                else -> 0.28 + 0.52 * c
            }
        }
        else -> 1.0
    }

    // ── Colour ────────────────────────────────────────────────────────────────

    private val GINGER = Rgb(0xB5 / 255.0, 0x74 / 255.0, 0x3A / 255.0)

    /** The paint for a Mochi (festive.ts `mochiPaint`): [body] is the colour it is filled with, [ink] its eye ink. */
    fun mochiPaint(body: Rgb, texture: String?, ink: String, time: Double?): FestivePaint {
        // A snowflake has to show against what it is drawn on: blue on a pale body, unless frost or gingerbread repaints it.
        val pale = 0.299 * body.r + 0.587 * body.g + 0.114 * body.b >= 0.75
        return FestivePaint(
            skin = if (texture == "gingerbread") GINGER else body,
            ink = ink,
            glint = "#FFFFFF",
            flake = if (pale && texture != "frost" && texture != "gingerbread") "#3FA9F5" else "#FFFFFF",
            flakeEdge = if (pale && texture == "frost") "#5FAEE6" else null,
            time = time,
        )
    }

    /** A prim's colour token for one wearer, this frame; null skips the prim (a token from a later generator is never guessed). */
    fun resolve(token: String, paint: FestivePaint): String? {
        if (!token.startsWith("@")) return token
        if (token.startsWith("@skin:")) {
            val k = (token.substring(6).toDoubleOrNull() ?: return null) * 255
            val c = paint.skin
            return "rgb(${Math.round(c.r * k)},${Math.round(c.g * k)},${Math.round(c.b * k)})"
        }
        return when (token) {
            "@ink" -> paint.ink
            "@glint" -> paint.glint
            "@flake" -> paint.flake
            "@flakeEdge" -> paint.flakeEdge
            else -> null
        }
    }

    // ── Paths ─────────────────────────────────────────────────────────────────

    /** One command of a prim's outline, in absolute coordinates. */
    sealed interface Op {
        data class Move(val x: Double, val y: Double) : Op
        data class Line(val x: Double, val y: Double) : Op
        data class Quad(val x1: Double, val y1: Double, val x: Double, val y: Double) : Op
        data class Cubic(val x1: Double, val y1: Double, val x2: Double, val y2: Double, val x: Double, val y: Double) : Op
        data object Close : Op
    }

    private val TOKEN = Regex("[MLQCZmlqcz]|[-+]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?")

    /**
     * The generator writes absolute M, L, Q, C and Z only (checked over the whole document by FestiveArtTest); a
     * relative or unknown command ends the outline there rather than drawing something wrong.
     */
    fun ops(d: String): List<Op> {
        val tokens = TOKEN.findAll(d).map { it.value }.toList()
        val out = ArrayList<Op>()
        var i = 0
        var cmd = ' '
        fun num(): Double? = tokens.getOrNull(i)?.toDoubleOrNull()?.also { i++ }
        while (i < tokens.size) {
            val t = tokens[i]
            if (t[0].isLetter()) { cmd = t[0]; i++ }
            when (cmd) {
                'M' -> { val x = num() ?: break; val y = num() ?: break; out.add(Op.Move(x, y)); cmd = 'L' }
                'L' -> { val x = num() ?: break; val y = num() ?: break; out.add(Op.Line(x, y)) }
                'Q' -> {
                    val x1 = num() ?: break; val y1 = num() ?: break; val x = num() ?: break; val y = num() ?: break
                    out.add(Op.Quad(x1, y1, x, y))
                }
                'C' -> {
                    val x1 = num() ?: break; val y1 = num() ?: break; val x2 = num() ?: break; val y2 = num() ?: break
                    val x = num() ?: break; val y = num() ?: break
                    out.add(Op.Cubic(x1, y1, x2, y2, x, y))
                }
                'Z' -> { out.add(Op.Close); cmd = ' ' } // a number after Z is malformed: it ends the outline
                else -> return out
            }
        }
        return out
    }
}

data class FestiveData(val version: Int, val bodies: Map<String, FestiveBody>)

class FestivePrim(
    val d: String, val fill: String?, val stroke: String?, val width: Double, val opacity: Double,
    /** Clipped to the wearer's body. */
    val clipped: Boolean,
    /** A lit part: its opacity follows [FestiveArt.light]. */
    val light: String?,
) {
    /** The outline, built once by the painter (an android.graphics path; kept here so it lives as long as the prim). */
    @Volatile var path: Any? = null
}

class FestiveHead(val behind: List<FestivePrim>, val front: List<FestivePrim>)
class FestiveEyes(val left: List<FestivePrim>, val right: List<FestivePrim>, val over: List<FestivePrim>)
class FestiveExtra(val back: List<FestivePrim>, val front: List<FestivePrim>)

class FestiveBody(
    /** Where the eye artwork rests, in the data's units (R = 100). */
    val restX: Double, val restY: Double,
    val heads: Map<String, FestiveHead>,
    val eyes: Map<String, FestiveEyes>,
    val textures: Map<String, List<FestivePrim>>,
    val extras: Map<String, FestiveExtra>,
)

class FestivePaint(
    /** `@skin:K` is this times K. */
    val skin: Rgb,
    val ink: String,
    val glint: String,
    val flake: String,
    /** Null where there is no edge to draw: the prim is skipped. */
    val flakeEdge: String?,
    /** Seconds, for the lit parts; null draws each at its own resting opacity. */
    val time: Double?,
)
