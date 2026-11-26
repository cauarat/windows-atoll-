package com.cauarati.notchy.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cauarati.notchy.R
import com.cauarati.notchy.core.Spacing
import com.cauarati.notchy.mochi.BotState

// The island's building blocks on Android: the Mac draws them in IslandViewContent.swift, the iPhone in
// ios/Notchy/UI/IslandStyle.swift, and these are the same views with the same values (sizes, colours, radii, washes).
// A change to one of them on the Mac belongs here too. Where a finger needs more room than a pointer, the hit area
// grows to 48 dp, never the drawing. Sizes are sp, so the phone's font size still applies.

/** IslandPalette (IslandStyle.swift). */
object IslandColors {
    val card = Color(0xFF000000)
    val page = Color(0xFF0E0F11)
    val text = Color(0xFFF5F6F8)
    val secondary = Color(0xFF8E939C)
    val tertiary = Color(0xFF6B7079)
    val faint = Color(0xFF454850)
    val tabOn = Color(0xFF1D1F23)
    val added = Color(0xFF22C55E)
    val removed = Color(0xFFF4505E)
    /** The empty and connecting cards' second line. */
    val body = Color(0xFF9398A1)
    /** The primary capsule and the label on it. */
    val light = Color(0xFFF5F6F8)
    val onLight = Color(0xFF0B0C0E)
    val amber = Color(0xFFF5A524)
}

/** CardBackground.Wash: the colour rising from below a card, at the Mac's own alpha. */
enum class Wash(val color: Color) {
    RED(Color(0xFFF4505E).copy(alpha = 0.55f)),
    GREEN(Color(0xFF34D399).copy(alpha = 0.5f)),
    PINK(Color(0xFFF472B6).copy(alpha = 0.55f)),
    AMBER(Color(0xFFF5A524).copy(alpha = 0.42f)),
    CYAN(Color(0xFF22D3EE).copy(alpha = 0.38f)),
    INDIGO(Color(0xFF6366F1).copy(alpha = 0.5f)),
    SOFT(Color.White.copy(alpha = 0.08f)),
}

/** The wash a session's card wears: amber while it waits for you, cyan for a question, red for an error, green when done. */
fun washFor(state: BotState): Wash? = when (state) {
    BotState.APPROVAL -> Wash.AMBER
    BotState.QUESTION -> Wash.CYAN
    BotState.ERROR -> Wash.RED
    BotState.FINISHED -> Wash.GREEN
    else -> null
}

/** The glow: centred at (0.5, 1.3) of the box, [radius] wide, clear by 70 % of the way out (RadialGradient on the Mac). */
fun Modifier.islandWash(color: Color, radius: Dp = 280.dp): Modifier = drawBehind {
    if (color.alpha <= 0.001f) return@drawBehind
    drawRect(Brush.radialGradient(0f to color, 0.7f to Color.Transparent, center = Offset(size.width * 0.5f, size.height * 1.3f), radius = radius.toPx()))
}

/** The wash, eased when it changes (0.3 s on the Mac). */
@Composable
fun animatedWash(wash: Wash?): Color = animateColorAsState(wash?.color ?: Color.Transparent, tween(300), label = "wash").value

private val CARD = RoundedCornerShape(20.dp)
private val HAIRLINE = Color.White.copy(alpha = 0.035f)

/** CardBackground: black, rounded 20, a coloured wash rising from below, a hairline edge; [focused] brightens the edge. */
@Composable
fun IslandCard(modifier: Modifier = Modifier, wash: Wash? = null, focused: Boolean = false, content: @Composable BoxScope.() -> Unit) {
    Box(
        modifier.clip(CARD).background(IslandColors.card).islandWash(animatedWash(wash))
            .border(1.dp, if (focused) Color.White.copy(alpha = 0.12f) else HAIRLINE, CARD),
        content = content,
    )
}

fun islandText(size: TextUnit, color: Color, weight: FontWeight = FontWeight.Normal, mono: Boolean = false) =
    TextStyle(fontSize = size, color = color, fontWeight = weight, fontFamily = if (mono) FontFamily.Monospace else FontFamily.Default)

/** AgentWho: the pill's dot, its name, and what it is doing. */
@Composable
fun AgentWho(name: String?, colorHex: String?, label: String, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        if (name != null) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(hexColor(colorHex) ?: Color(0xFFC0C4CC)))
            Text(name, style = islandText(12.sp, IslandColors.text, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(label, style = islandText(12.sp, IslandColors.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** CodeBlock: the command, monospaced, in a faint rounded box; scrolls past [maxHeight], never cut. */
@Composable
fun CodeBlock(text: String, maxHeight: Dp = 64.dp) {
    val shape = RoundedCornerShape(10.dp)
    Box(
        Modifier.heightIn(max = maxHeight).clip(shape).background(Color.White.copy(alpha = 0.07f)).border(1.dp, Color.White.copy(alpha = 0.06f), shape)
            .verticalScroll(rememberScrollState()).padding(horizontal = 10.dp, vertical = 5.dp),
    ) {
        Text(text, style = islandText(12.sp, Color(0xFFE8E9EC), mono = true))
    }
}

/**
 * PrimaryButton (Allow, Send) and SecondaryButton (Deny, an option): the light and the dark capsule, 12.5 sp medium,
 * padded 13 × 7. The finger's area is 48 dp tall around the drawing.
 */
@Composable
fun IslandButton(
    text: String, onClick: () -> Unit, modifier: Modifier = Modifier, primary: Boolean = false, enabled: Boolean = true,
    icon: (@Composable (Color) -> Unit)? = null,
) {
    val fg = if (primary) IslandColors.onLight else Color(0xFFF1F2F4)
    Box(
        modifier.heightIn(min = Spacing.MIN_TOUCH.dp).clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .alpha(if (enabled) 1f else 0.4f),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            Modifier.clip(CircleShape).background(if (primary) IslandColors.light else Color.White.copy(alpha = 0.09f))
                .padding(horizontal = 13.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            icon?.invoke(fg)
            Text(text, style = islandText(12.5.sp, fg, FontWeight.Medium), maxLines = 1)
        }
    }
}

/** A multi-select option: a rounded chip, cyan once picked (the question card). */
@Composable
fun IslandChip(text: String, selected: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(7.dp)
    Box(Modifier.heightIn(min = Spacing.MIN_TOUCH.dp).clickable(role = Role.Checkbox, onClick = onClick), contentAlignment = Alignment.Center) {
        Text(
            text,
            Modifier.clip(shape).background(if (selected) Color(0xFF22D3EE).copy(alpha = 0.22f) else Color.White.copy(alpha = 0.07f))
                .border(1.dp, if (selected) Color(0xFF22D3EE).copy(alpha = 0.55f) else Color.White.copy(alpha = 0.1f), shape)
                .padding(horizontal = 8.dp, vertical = 4.dp),
            style = islandText(12.sp, if (selected) Color(0xFF67E8F9) else Color(0xFFC5C8CD), FontWeight.Medium),
        )
    }
}

/** TabButton: the header's capsule tabs, 30 × 22, lit when on. */
@Composable
fun IslandTab(on: Boolean, label: String, onClick: () -> Unit, mark: @Composable (Color) -> Unit) {
    Box(
        Modifier.sizeIn(minWidth = 38.dp, minHeight = Spacing.MIN_TOUCH.dp).clickable(role = Role.Tab, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(width = 30.dp, height = 22.dp).clip(CircleShape).background(if (on) IslandColors.tabOn else Color.Transparent), contentAlignment = Alignment.Center) {
            mark(if (on) IslandColors.text else IslandColors.secondary)
        }
    }
}

/** A header icon button: 36 dp on the Mac and the iPhone, 48 dp to hit here. */
@Composable
fun IslandIconButton(label: String, onClick: () -> Unit, mark: @Composable (Color) -> Unit) {
    Box(
        Modifier.size(Spacing.MIN_TOUCH.dp).clickable(role = Role.Button, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { mark(IslandColors.secondary) }
}

/** TickerShimmerText: the current step, with the island's light sweeping across it every 2.2 s. */
@Composable
fun TickerShimmerText(text: String, modifier: Modifier = Modifier) {
    val base = islandText(13.sp, IslandColors.text, FontWeight.Medium)
    if (reducedMotion()) {
        Text(text, modifier, style = base, maxLines = 1, overflow = TextOverflow.Ellipsis)
        return
    }
    val t = rememberInfiniteTransition(label = "ticker")
    val p by t.animateFloat(0f, 1f, infiniteRepeatable(tween(2200, easing = LinearEasing), RepeatMode.Restart), label = "sweep")
    val phase = p * 1.2f - 0.1f
    val grey = Color(0xFF7C818A)
    val lit = Color(0xFFF2F3F5)
    val stops = arrayOf(
        (phase - 0.3f).coerceIn(0f, 1f) to grey,
        phase.coerceIn(0f, 1f) to lit,
        (phase + 0.3f).coerceIn(0f, 1f) to grey,
    )
    Text(text, modifier, style = base.copy(brush = Brush.horizontalGradient(colorStops = stops)), maxLines = 1, overflow = TextOverflow.Ellipsis)
}

/** TickerRowView: a step: a chevron and a shimmer while it runs, a check once it is done. 22 tall. */
@Composable
fun TickerRow(text: String, current: Boolean) {
    Row(Modifier.fillMaxWidth().height(22.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.width(12.dp), contentAlignment = Alignment.Center) {
            if (current) StrokeGlyph(ICON_CHEVRON, IslandColors.secondary, 9.dp, 2.2f)
            else StrokeGlyph(ICON_CHECK, IslandColors.faint, 9.dp, 1.8f)
        }
        if (current) TickerShimmerText(text, Modifier.weight(1f))
        else Text(text, Modifier.weight(1f), style = islandText(13.sp, IslandColors.tertiary, FontWeight.Medium), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** The +N −M of a file, in the island's colours. */
@Composable
fun LineCounts(added: Int, removed: Int, size: TextUnit = 10.sp) {
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        if (added > 0) Text("+$added", style = islandText(size, IslandColors.added, FontWeight.Medium, mono = true), maxLines = 1)
        if (removed > 0) Text("−$removed", style = islandText(size, IslandColors.removed, FontWeight.Medium, mono = true), maxLines = 1)
    }
}

/** TypingDotsView: Mochi is writing. */
@Composable
fun TypingDots() {
    val t = rememberInfiniteTransition(label = "typing")
    Row(Modifier.padding(horizontal = 2.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for (i in 0 until 3) {
            val s by t.animateFloat(
                0.6f, 1.2f,
                infiniteRepeatable(tween(450, delayMillis = i * 140), RepeatMode.Reverse), label = "dot$i",
            )
            Box(Modifier.size(5.dp).scale(if (reducedMotion()) 1f else s).clip(CircleShape).background(IslandColors.tertiary))
        }
    }
}

/** What a pill is doing, in the island's words. */
fun islandStateWord(state: BotState): Int = when (state) {
    BotState.IDLE -> R.string.island_state_idle
    BotState.WORKING -> R.string.island_state_working
    BotState.THINKING -> R.string.island_state_thinking
    BotState.SEARCHING -> R.string.island_state_searching
    BotState.APPROVAL -> R.string.island_needs_permission
    BotState.QUESTION -> R.string.island_state_asking
    BotState.ERROR -> R.string.island_state_error
    BotState.FINISHED -> R.string.island_state_finished
    BotState.RATELIMIT -> R.string.island_state_ratelimit
    BotState.SLEEPING -> R.string.island_state_sleeping
    BotState.DIZZY -> R.string.island_state_dizzy
}

/** The colour of that word on a pill's card. */
fun islandStateColor(state: BotState): Color = when (state) {
    BotState.WORKING -> Color(0xFF7CC0FF)
    BotState.THINKING -> Color(0xFFC4B5FD)
    BotState.SEARCHING -> Color(0xFFA5B4FC)
    BotState.APPROVAL -> Color(0xFFF5A524)
    BotState.QUESTION -> Color(0xFF67E8F9)
    BotState.ERROR -> Color(0xFFFF8D97)
    BotState.FINISHED -> Color(0xFF6EE7B7)
    else -> IslandColors.tertiary
}

/**
 * A step or a status as the island shows it: as the computer sent it ("Runs · npm test", "Reads · README.md"), on one
 * line. The Mac has already cut a path to its file name and a command to one line. Only the island's own screens show
 * it; the notifications, the widgets and the island over other apps, which are seen without opening the app, keep
 * their plain words (ToolLabels).
 */
fun islandStep(raw: String): String = raw.map { if (it.isISOControl()) ' ' else it }.joinToString("").replace(Regex("\\s+"), " ").trim()

val BotState.isBusy: Boolean get() = this == BotState.WORKING || this == BotState.THINKING || this == BotState.SEARCHING

/** "#RRGGBB" to a colour; anything else is null. */
fun hexColor(hex: String?): Color? {
    val h = hex?.trim()?.removePrefix("#") ?: return null
    if (h.length != 6) return null
    val v = h.toLongOrNull(16) ?: return null
    return Color(0xFF000000 or v)
}

// ── The header's symbols ─────────────────────────────────────────────────────
//
// The Mac's SF Symbols as the Windows twin draws them (windows/src/views/icons.ts): measured off the Mac's own render
// on a 24 grid, filled under the non-zero rule. IslandGlyphsTest keeps these strings equal to the TypeScript ones.

const val ICON_HOUSE = "M12.76 2.78l9.48 7.92a.76.76 0 0 1 .1 1.06a.76.76 0 0 1-1.07.1L11.79 3.94a.05.05 0 0 0-.06 0L2.24 11.86a.76.76 0 0 1-1.06-.1a.76.76 0 0 1 .09-1.06l9.49-7.92a1.57 1.57 0 0 1 2 0zM19.88 5.06v4.65l-2.27-1.9V5.06a.61.61 0 0 1 .61-.61h1.05a.61.61 0 0 1 .61.61zM19.71 12.38v7.14a1.85 1.85 0 0 1-1.85 1.85H5.66a1.85 1.85 0 0 1-1.85-1.85v-7.14a.43.43 0 0 1 .15-.32l7.25-6.05a.85.85 0 0 1 1.09 0l7.25 6.05a.43.43 0 0 1 .16.32zM14.19 19.69v-5.33a.43.43 0 0 0-.43-.43H9.74a.43.43 0 0 0-.42.43v5.33a.21.21 0 0 0 .21.22h4.44a.21.21 0 0 0 .22-.22z"
const val ICON_CHAT_SPARKLE = "M15.98 4.29C15.82 4.35 15.65 4.39 15.5 4.39C14.64 4.39 14.04 5.06 14.04 5.85C14.04 6.59 14.56 7.23 15.34 7.3L15.5 7.31C16.51 7.31 17.98 8.78 17.98 9.79C17.98 10.65 18.65 11.25 19.44 11.25C19.83 11.25 20.19 11.1 20.46 10.85L20.46 14.64C20.46 16.01 20.46 16.7 20.23 17.44C19.93 18.25 19.3 18.88 18.49 19.18C17.75 19.41 17.06 19.41 15.69 19.41L9.78 19.41L6.32 22.53C6.17 22.67 5.97 22.74 5.76 22.74C5.3 22.74 4.92 22.37 4.92 21.9L4.92 19.41L4.77 19.41C3.4 19.41 2.71 19.41 1.97 19.18C1.16 18.88 0.53 18.25 0.23 17.44C0 16.7 0 16.01 0 14.64L0 9.06C0 7.69 0 7 0.23 6.26C0.53 5.45 1.16 4.82 1.97 4.52C2.71 4.29 3.4 4.29 4.77 4.29L15.69 4.29C15.79 4.29 15.89 4.29 15.98 4.29ZM9.73 8.3C9.73 9.56 8.15 11.14 6.89 11.14C6.26 11.14 6.26 12.08 6.89 12.08C8.15 12.08 9.73 13.66 9.73 14.92C9.73 15.55 10.67 15.55 10.67 14.92C10.67 13.66 12.25 12.08 13.51 12.08C14.14 12.08 14.14 11.14 13.51 11.14C12.25 11.14 10.67 9.56 10.67 8.3C10.67 7.67 9.73 7.67 9.73 8.3ZM20 1.91C20 3.41 21.88 5.29 23.38 5.29C24.13 5.29 24.13 6.41 23.38 6.41C21.88 6.41 20 8.29 20 9.79C20 10.54 18.88 10.54 18.88 9.79C18.88 8.29 17 6.41 15.5 6.41C14.75 6.41 14.75 5.29 15.5 5.29C17 5.29 18.88 3.41 18.88 1.91C18.88 1.16 20 1.16 20 1.91Z"
const val ICON_GEAR = "M8.92 4.23l.44-1.98a1.58 1.58 0 0 1 1.55-1.24h2.18a1.58 1.58 0 0 1 1.55 1.24l.44 1.98a8.36 8.36 0 0 1 .24.1l1.71-1.09A1.58 1.58 0 0 1 19 3.45L20.55 5a1.58 1.58 0 0 1 .21 1.97L19.67 8.68a8.36 8.36 0 0 1 .1.24l1.98.44a1.58 1.58 0 0 1 1.24 1.55v2.18a1.58 1.58 0 0 1-1.24 1.55l-1.98.44a8.36 8.36 0 0 1-.1.24l1.09 1.71A1.58 1.58 0 0 1 20.55 19L19 20.55a1.58 1.58 0 0 1-1.97.21l-1.71-1.09a8.36 8.36 0 0 1-.24.1l-.44 1.98a1.58 1.58 0 0 1-1.55 1.24h-2.18a1.58 1.58 0 0 1-1.55-1.24l-.44-1.98a8.36 8.36 0 0 1-.24-.1L6.97 20.76A1.58 1.58 0 0 1 5 20.55L3.45 19a1.58 1.58 0 0 1-.21-1.97l1.09-1.71a8.36 8.36 0 0 1-.1-.24l-1.98-.44a1.58 1.58 0 0 1-1.24-1.55v-2.18A1.58 1.58 0 0 1 2.25 9.36l1.98-.44a8.36 8.36 0 0 1 .1-.24L3.24 6.97A1.58 1.58 0 0 1 3.45 5L5 3.45a1.58 1.58 0 0 1 1.97-.21L8.68 4.33a8.36 8.36 0 0 1 .24-.1zM9.31 5.78a1.58 1.58 0 0 1-1.48-.12L6.12 4.57L4.57 6.12L5.66 7.83a1.58 1.58 0 0 1 .12 1.48a6.78 6.78 0 0 0-.08.2a1.58 1.58 0 0 1-1.13.96l-1.98.44v2.18l1.98.44a1.58 1.58 0 0 1 1.13.96a6.78 6.78 0 0 0 .08.2a1.58 1.58 0 0 1-.12 1.48L4.57 17.88l1.55 1.55l1.71-1.09a1.58 1.58 0 0 1 1.48-.12a6.78 6.78 0 0 0 .2.08a1.58 1.58 0 0 1 .96 1.13l.44 1.98h2.18l.44-1.98a1.58 1.58 0 0 1 .96-1.13a6.78 6.78 0 0 0 .2-.08a1.58 1.58 0 0 1 1.48.12l1.71 1.09l1.55-1.55l-1.09-1.71a1.58 1.58 0 0 1-.12-1.48a6.78 6.78 0 0 0 .08-.2a1.58 1.58 0 0 1 1.13-.96l1.98-.44v-2.18l-1.98-.44a1.58 1.58 0 0 1-1.13-.96a6.78 6.78 0 0 0-.08-.2a1.58 1.58 0 0 1 .12-1.48l1.09-1.71L17.88 4.57L16.17 5.66a1.58 1.58 0 0 1-1.48.12a6.78 6.78 0 0 0-.2-.08a1.58 1.58 0 0 1-.96-1.13l-.44-1.98h-2.18l-.44 1.98A1.58 1.58 0 0 1 9.51 5.7a6.78 6.78 0 0 0-.2.08zM12 8.11A3.89 3.89 0 0 1 15.89 12A3.89 3.89 0 0 1 12 15.89A3.89 3.89 0 0 1 8.11 12A3.89 3.89 0 0 1 12 8.11zM12 9.69A2.31 2.31 0 0 0 9.69 12A2.31 2.31 0 0 0 12 14.31A2.31 2.31 0 0 0 14.31 12A2.31 2.31 0 0 0 12 9.69z"
const val ICON_SPEAKER_ON = "M2.86 8.02h3.16L10.8 3.69a1.28 1.28 0 0 1 1.37-.22a1.28 1.28 0 0 1 .76 1.17v14.83a1.28 1.28 0 0 1-.76 1.17a1.28 1.28 0 0 1-1.37-.22L6.02 16.09H2.86a1.83 1.83 0 0 1-1.83-1.83V9.85A1.83 1.83 0 0 1 2.86 8.02zM6.99 14.92l4.42 4.01V5.18l-4.42 4a1.37 1.37 0 0 1-.91.36H2.86a.31.31 0 0 0-.31.31v4.41a.31.31 0 0 0 .31.31h3.22a1.37 1.37 0 0 1 .91.35zM17.44 8.06a8.04 8.04 0 0 1 0 7.97a.76.76 0 0 1-1.04.28a.76.76 0 0 1-.29-1.04a6.51 6.51 0 0 0 0-6.45a.76.76 0 0 1 .29-1.05a.76.76 0 0 1 1.04.29zM21.07 5.44a12.5 12.5 0 0 1 0 13.21a.76.76 0 0 1-1.05.25a.76.76 0 0 1-.25-1.06a10.98 10.98 0 0 0 0-11.6a.76.76 0 0 1 .25-1.05a.76.76 0 0 1 1.05.25z"
const val ICON_SPEAKER_OFF = "M9.85 6.4l5.42-4.9a1.49 1.49 0 0 1 1.6-.26a1.49 1.49 0 0 1 .89 1.36v11.71zM15.99 12.54V3.23L11.1 7.66zM17.58 20.54a1.49 1.49 0 0 1-1.05.78a1.49 1.49 0 0 1-1.26-.37L9.71 15.92H6.04a2.13 2.13 0 0 1-2.13-2.13V8.66a2.13 2.13 0 0 1 .46-1.33zM10.85 14.56l5.14 4.66v-.28L5.68 8.63a.36.36 0 0 0-.01.03v5.13a.36.36 0 0 0 .37.36h3.74a1.59 1.59 0 0 1 1.07.41zM3.09 1.62L22.68 21.24a.87.87 0 0 1 0 1.23a.87.87 0 0 1-1.24 0L1.86 2.85a.87.87 0 0 1 0-1.23a.87.87 0 0 1 1.23 0z"
const val ICON_ARROW_UP_RIGHT = "M8.5 7h8.5v8.5h-2V10.4l-7.1 7.1-1.4-1.4 7.1-7.1H8.5V7z"
const val ICON_ARROW_UP = "M12 4.5 5.5 11l1.5 1.5 4-4V19.5h2V8.5l4 4L18.5 11 12 4.5z"
/** Drawn as strokes. */
const val ICON_CHEVRON = "M9 5.5 15.5 12 9 18.5"
const val ICON_CHECK = "M5 12.5 9.5 17 19 7.5"

/**
 * The size of the 24-unit box that shows each header glyph as large as the Mac's symbol in its header
 * (HEADER_PX in windows/src/views/icons.ts), in dp.
 */
object GlyphBox {
    val house = 16.91.dp
    val chatSparkle = 16.dp
    val gear = 15.95.dp
    val speakerOn = 16.65.dp
    val speakerOff = 14.31.dp
}

private val glyphCache = HashMap<String, Path>()

private fun glyph(d: String): Path = glyphCache.getOrPut(d) { PathParser().parsePathString(d).toPath().apply { fillType = PathFillType.NonZero } }

/** A filled symbol from a 24-grid path, in a [box] dp square. */
@Composable
fun Glyph(d: String, tint: Color, box: Dp, modifier: Modifier = Modifier) {
    val path = remember(d) { glyph(d) }
    Canvas(modifier.size(box)) {
        val k = size.minDimension / 24f
        scale(k, k, pivot = Offset.Zero) { drawPath(path, tint) }
    }
}

/** A stroked symbol (chevron, check) from a 24-grid path, [weight] in grid units. */
@Composable
fun StrokeGlyph(d: String, tint: Color, box: Dp, weight: Float = 2f, modifier: Modifier = Modifier) {
    val path = remember(d) { glyph(d) }
    Canvas(modifier.size(box)) {
        val k = size.minDimension / 24f
        translate(0f, 0f) { scale(k, k, pivot = Offset.Zero) { drawPath(path, tint, style = Stroke(weight, cap = StrokeCap.Round, join = StrokeJoin.Round)) } }
    }
}
