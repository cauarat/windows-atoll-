package com.cauarati.notchy.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cauarati.notchy.R
import com.cauarati.notchy.core.Spacing
import com.cauarati.notchy.core.TypeScale
import com.cauarati.notchy.mochi.BotState
import com.cauarati.notchy.mochi.MochiConst
import com.cauarati.notchy.mochi.MochiEngine
import com.cauarati.notchy.mochi.MochiView
import com.cauarati.notchy.mochi.Rgb

internal fun rgbColor(c: Rgb) = Color(c.r.toFloat(), c.g.toFloat(), c.b.toFloat())

/**
 * The hero of Home: Louis's island grown to full width and hanging from the top edge of the screen. It holds Mochi, awake
 * while the computer is connected and asleep while it is not, and one plain line that says which computer it is. Black,
 * with a soft glow in the colour of Mochi's state.
 */
@Composable
fun HeroCard(engine: MochiEngine, touch: Modifier, connected: Boolean, desktopName: String, linkDot: Color, linkText: String) {
    val state = if (connected) BotState.IDLE else BotState.SLEEPING
    val wash = MochiConst.STATES[state]?.color?.let(::rgbColor)
    val dim = Color(tokens().heroTextDim)
    val white = Color(tokens().heroText)
    HeroPanel(wash = wash) {
        Column(
            Modifier.windowInsetsPadding(WindowInsets.statusBars).padding(start = Spacing.INSIDE.dp, end = Spacing.INSIDE.dp, top = 12.dp, bottom = 18.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                StateDot(linkDot)
                Spacer(Modifier.width(8.dp))
                Text(linkText, Modifier.weight(1f), style = TypeScale.LABEL.style(dim), maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                MochiView(engine, Modifier.size(112.dp).then(touch))
                Text(
                    stringResource(if (connected) R.string.home_connected_title else R.string.home_connecting_title, desktopName),
                    style = TypeScale.TITLE.style(white).copy(textAlign = TextAlign.Center), maxLines = 2, overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}
