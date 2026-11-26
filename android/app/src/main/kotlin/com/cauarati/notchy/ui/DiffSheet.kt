package com.cauarati.notchy.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cauarati.notchy.R
import com.cauarati.notchy.app.AppModel
import com.cauarati.notchy.core.DiffState
import com.cauarati.notchy.core.Tokens
import com.cauarati.notchy.link.DiffRow

/** What the file-change sheet draws a row in: the colour of its text and of the tint behind it. */
internal object DiffLook {
    /** DiffLineRowView on the Mac: light green and red text, a hunk header in blue, context dim. */
    fun text(kind: Char, t: Tokens): Color = when (kind) {
        '+' -> Color(0xFF86EFAC)
        '-' -> Color(0xFFFCA5A5)
        '@' -> Color(0xFF7DA2D6)
        else -> Color(t.textFaint)
    }

    fun tint(kind: Char, t: Tokens): Color = when (kind) {
        '+' -> Color(t.diffAdded).copy(alpha = 0.12f)
        '-' -> Color(t.diffRemoved).copy(alpha = 0.12f)
        else -> Color.Transparent
    }

    /** The marker's own colour: the island's green and red. */
    fun mark(kind: Char, t: Tokens): Color = when (kind) {
        '+' -> Color(t.diffAdded)
        '-' -> Color(t.diffRemoved)
        else -> IslandColors.faint
    }

    /** What is said besides the colour, so the change is not carried by colour alone. */
    fun marker(kind: Char): String = when (kind) {
        '+' -> "+"
        '-' -> "−"
        '@' -> ""
        else -> " "
    }
}

/**
 * What an agent changed in one file (DiffCardView), as the computer sent it when asked: up to 200 lines, added and
 * removed lines coloured and also marked with + and −. Held in memory while this is open; nothing is stored.
 */
@Composable
fun DiffSheet(model: AppModel) {
    val state = model.diffState
    if (state is DiffState.Idle) return
    val dim = IslandColors.tertiary
    BottomSheetHost(onDismiss = { model.closeDiff() }) {
        val name = when (state) {
            is DiffState.Loading -> state.name
            is DiffState.Ready -> state.diff.name
            is DiffState.Failed -> state.name
            DiffState.Idle -> ""
        }
        Row(Modifier.fillMaxWidth().padding(bottom = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(name, Modifier.weight(1f), style = islandText(14.sp, IslandColors.text, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (state is DiffState.Ready) LineCounts(state.diff.added, state.diff.removed, 11.sp)
        }
        when (state) {
            is DiffState.Loading -> Text(stringResource(R.string.file_loading), Modifier.padding(vertical = 16.dp), style = islandText(11.5.sp, dim))
            is DiffState.Failed -> Text(stringResource(R.string.file_failed), Modifier.padding(vertical = 16.dp), style = islandText(11.5.sp, dim))
            is DiffState.Ready -> {
                val d = state.diff
                val note = when {
                    d.gone -> R.string.file_gone
                    d.tooLarge -> R.string.file_too_large
                    d.rows.isEmpty() -> R.string.file_empty
                    else -> null
                }
                if (note != null) Text(stringResource(note), Modifier.padding(bottom = 12.dp), style = islandText(11.5.sp, dim))
                else {
                    LazyColumn(Modifier.fillMaxWidth().heightIn(max = 420.dp)) {
                        itemsIndexed(d.rows) { _, row -> DiffLine(row) }
                    }
                    if (d.truncated) Text(stringResource(R.string.file_truncated), Modifier.padding(top = 8.dp), style = islandText(11.5.sp, dim))
                }
            }
            DiffState.Idle -> {}
        }
        IslandButton(stringResource(R.string.file_close), { model.closeDiff() }, Modifier.padding(top = 8.dp))
    }
}

/** DiffLineRowView: one line of a diff, 10.5 sp monospaced, marked + or − as well as coloured. */
@Composable
private fun DiffLine(row: DiffRow) {
    val t = tokens()
    val mono = islandText(10.5.sp, DiffLook.text(row.kind, t), mono = true)
    if (row.kind == '@') {
        Text(row.text, Modifier.fillMaxWidth().padding(vertical = 3.dp), style = mono, maxLines = 1, overflow = TextOverflow.Ellipsis)
        return
    }
    Row(Modifier.fillMaxWidth().background(DiffLook.tint(row.kind, t))) {
        Text(DiffLook.marker(row.kind), Modifier.width(12.dp), style = mono.copy(color = DiffLook.mark(row.kind, t)))
        Text(row.text, Modifier.weight(1f), style = mono, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
