package com.cauarati.notchy.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.cauarati.notchy.R
import com.cauarati.notchy.core.BarFit
import com.cauarati.notchy.core.IconKind
import com.cauarati.notchy.core.Spacing
import com.cauarati.notchy.core.Tab
import com.cauarati.notchy.core.TypeScale

private fun Tab.icon() = when (this) {
    Tab.HOME -> IconKind.HOME
    Tab.CHAT -> IconKind.CHAT
    Tab.SETTINGS -> IconKind.SLIDERS
}

private fun Tab.label() = when (this) {
    Tab.HOME -> R.string.tab_home
    Tab.CHAT -> R.string.tab_chat
    Tab.SETTINGS -> R.string.tab_settings
}

/**
 * The floating bar: a black pill with Home, Chat and Settings. Labels are always shown; the open tab has a
 * lighter pill behind it. Every item is at least 48 dp high and announces itself as a tab.
 */
@Composable
fun BottomBar(tabs: List<Tab>, selected: Tab?, onSelect: (Tab) -> Unit, modifier: Modifier = Modifier) {
    val t = tokens()
    Row(
        // At least 64 dp, taller when the font is large, so labels are never cut.
        modifier.fillMaxWidth().padding(horizontal = 24.dp).height(IntrinsicSize.Min).heightIn(min = 64.dp)
            .clip(CircleShape).background(t.panel.c()).border(1.dp, t.line.c(), CircleShape).padding(6.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        for (tab in tabs) {
            val on = tab == selected
            val label = stringResource(tab.label())
            Box(
                Modifier.weight(1f).fillMaxHeight().heightIn(min = Spacing.MIN_TOUCH.dp).clip(CircleShape).background(if (on) t.panel2.c() else Color.Transparent)
                    .selectable(selected = on, role = Role.Tab, onClick = { onSelect(tab) })
                    .semantics { contentDescription = label },
                contentAlignment = Alignment.Center,
            ) {
                Column(Modifier.padding(horizontal = BarFit.ITEM_SIDE_PADDING_DP.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    NotchyIcon(tab.icon(), tint = if (on) t.text.c() else t.textDim.c(), size = 22.dp)
                    Text(label, style = TypeScale.LABEL.style(if (on) t.text.c() else t.textDim.c()), maxLines = 1, softWrap = false)
                }
            }
        }
    }
}
