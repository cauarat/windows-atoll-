package com.cauarati.notchy.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.cauarati.notchy.R
import com.cauarati.notchy.app.AppModel
import com.cauarati.notchy.core.IconKind
import com.cauarati.notchy.core.Spacing
import com.cauarati.notchy.core.TypeScale
import com.cauarati.notchy.link.LinkHealthText
import com.cauarati.notchy.link.LinkState
import kotlinx.coroutines.delay

/**
 * Shown on Home while the link is down after having worked: what happened and how long ago ("Connection lost 2 min ago,
 * reconnecting"), why in one sentence, and the way to "Can't connect?". The time is refreshed while this is on screen, never in the background.
 */
@Composable
fun LinkHealthPanel(model: AppModel, onHelp: () -> Unit) {
    val now by produceState(System.currentTimeMillis()) {
        while (true) {
            delay(15_000)
            value = System.currentTimeMillis()
        }
    }
    val lines = LinkHealthText.lines(model.linkState == LinkState.CONNECTED, model.health, now, model.wifiUp) ?: return
    val t = tokens()
    Panel {
        Column(Modifier.padding(Spacing.INSIDE.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(lines.first, style = TypeScale.BODY.style(t.text.c()))
            if (lines.second.isNotEmpty()) Text(lines.second, style = TypeScale.SECONDARY.style(t.textDim.c()))
        }
        RowDivider()
        ListRow(stringResource(R.string.diag_title), onClick = onHelp, trailing = { NotchyIcon(IconKind.CHEVRON, tint = t.textDim.c(), size = 20.dp) })
    }
}
