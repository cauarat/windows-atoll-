package com.cauarati.notchy.ui

import android.os.SystemClock
import android.text.format.DateUtils
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cauarati.notchy.R
import com.cauarati.notchy.app.AppModel
import com.cauarati.notchy.core.HomePanel
import com.cauarati.notchy.core.Pills
import com.cauarati.notchy.core.Spacing
import com.cauarati.notchy.core.Tokens
import com.cauarati.notchy.mochi.MochiEngine
import com.cauarati.notchy.mochi.MochiView

/**
 * One session, up close (the island's session view, the iPhone's SessionSheet): Mochi in the pill's colour and
 * character, every step the computer sent (the current one shimmering), the agent's last line once it stopped, and the
 * files it changed; a file opens its diff, read from the computer on request. Without the switches on the computer, the
 * screen says where to turn them on.
 */
@Composable
fun SessionScreen(model: AppModel, pillId: String, onBack: () -> Unit) {
    val s = model.sessions.firstOrNull { it.pillId == pillId }
    val clock = remember { { SystemClock.elapsedRealtimeNanos() / 1e6 } }
    val engine = remember(pillId) { MochiEngine(clock) }
    CompositionLocalProvider(LocalTokens provides Tokens.ISLAND) {
        Column(Modifier.fillMaxSize().background(IslandColors.card)) {
            Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
            BackRow(onBack)
            if (s == null) {
                Text(stringResource(R.string.session_ended), Modifier.padding(20.dp), style = islandText(13.sp, IslandColors.secondary))
                return@Column
            }
            if (engine.state != s.state) engine.setState(s.state)
            engine.wear(s, botColor(s))
            val name = s.agent.ifBlank { Pills.byId(s.pillId)?.name.orEmpty() }
            val spokenTitle = s.project?.let { "$name, " + projectLabel(it) }
            val working = stringResource(R.string.session_step_working)
            val done = stringResource(R.string.session_step_done)
            LazyColumn(
                Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 20.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                item {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        Box(Modifier.size(90.dp), contentAlignment = Alignment.Center) { MochiView(engine, Modifier.size(90.dp)) }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            val project = s.project
                            Text(
                                project ?: name,
                                Modifier.semantics { if (spokenTitle != null) contentDescription = spokenTitle },
                                style = islandText(18.sp, IslandColors.text, FontWeight.SemiBold), maxLines = 2, overflow = TextOverflow.Ellipsis,
                            )
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Box(Modifier.size(7.dp).clip(CircleShape).background(hexColor(HomePanel.colorHex(s)) ?: Color(0xFFC0C4CC)))
                                Text(name, style = islandText(12.5.sp, IslandColors.secondary), maxLines = 1)
                                Text(stringResource(islandStateWord(s.state)), style = islandText(12.5.sp, IslandColors.tertiary), maxLines = 1)
                            }
                            if (s.updatedAtMs > 0) {
                                Text(
                                    DateUtils.getRelativeTimeSpanString(s.updatedAtMs, System.currentTimeMillis(), DateUtils.SECOND_IN_MILLIS).toString(),
                                    style = islandText(11.sp, IslandColors.faint), maxLines = 1,
                                )
                            }
                        }
                    }
                }

                val last = s.finalLine?.trim()?.takeIf { it.isNotBlank() }
                if (last != null) {
                    item {
                        Section(stringResource(R.string.island_last_line)) {
                            SelectionContainer { Text(last, style = islandText(13.5.sp, IslandColors.text, FontWeight.Medium)) }
                        }
                    }
                }

                // Every step as the computer sent it, as the island lists them; an empty one gets a neutral word.
                val steps = s.steps.ifEmpty { listOfNotNull(s.statusText.takeIf { it.isNotBlank() }) }
                if (steps.isNotEmpty()) {
                    item {
                        Section(stringResource(R.string.session_steps)) {
                            steps.forEachIndexed { i, step ->
                                val current = i == steps.lastIndex && s.state.isBusy
                                TickerRow(islandStep(step).ifEmpty { if (current) working else done }, current)
                            }
                        }
                    }
                } else if (!model.detailsOffered) {
                    item { Hint(stringResource(R.string.session_hint)) }
                }

                if (s.files.isNotEmpty()) {
                    item {
                        Section(stringResource(R.string.files_heading)) {
                            // Newest change first.
                            for (f in s.files.asReversed()) {
                                Row(
                                    Modifier.fillMaxWidth().heightIn(min = Spacing.MIN_TOUCH.dp).clickable(role = Role.Button) { model.openDiff(s.pillId, f) },
                                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    FileMark(f.isNew)
                                    Text(f.name, Modifier.weight(1f), style = islandText(13.sp, Color(0xFFC9CDD4), FontWeight.Medium), maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    if (f.isNew) Text(stringResource(R.string.files_new), style = islandText(10.sp, IslandColors.tertiary), maxLines = 1)
                                    LineCounts(f.added, f.removed)
                                    StrokeGlyph(ICON_CHEVRON, IslandColors.faint, 11.dp, 2.4f)
                                }
                            }
                        }
                    }
                } else if (!model.diffsOffered) {
                    item { Hint(stringResource(R.string.files_hint)) }
                }
            }
        }
    }
}

@Composable
private fun projectLabel(project: String) = stringResource(R.string.session_project, project)

/** Back, as the island's own chevron, top left. */
@Composable
private fun BackRow(onBack: () -> Unit) {
    val back = stringResource(R.string.action_back)
    Box(
        Modifier.padding(start = 8.dp).size(Spacing.MIN_TOUCH.dp).clickable(role = Role.Button, onClick = onBack).semantics { contentDescription = back },
        contentAlignment = Alignment.Center,
    ) { StrokeGlyph(ICON_CHEVRON, IslandColors.secondary, 16.dp, 2.4f, Modifier.rotate(180f)) }
}

/** A section of the session (CardBackground, rounded 20, 14 inside), its title in small capitals. */
@Composable
private fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    IslandCard(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title.uppercase(), style = islandText(11.sp, IslandColors.tertiary, FontWeight.SemiBold).copy(letterSpacing = 0.4.sp))
            Column(content = content)
        }
    }
}

@Composable
private fun Hint(text: String) = Text(text, style = islandText(11.5.sp, IslandColors.tertiary))

/** A file's mark: a page, with a plus when it is new. */
@Composable
private fun FileMark(new: Boolean) {
    Box(Modifier.width(18.dp), contentAlignment = Alignment.Center) {
        androidx.compose.foundation.Canvas(Modifier.size(width = 11.dp, height = 13.dp)) {
            val w = size.width
            val h = size.height
            val stroke = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.2.dp.toPx())
            drawRoundRect(IslandColors.secondary, style = stroke, cornerRadius = androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()), size = androidx.compose.ui.geometry.Size(w, h))
            if (new) {
                drawLine(IslandColors.secondary, androidx.compose.ui.geometry.Offset(w / 2, h * 0.3f), androidx.compose.ui.geometry.Offset(w / 2, h * 0.7f), 1.2.dp.toPx())
                drawLine(IslandColors.secondary, androidx.compose.ui.geometry.Offset(w * 0.3f, h / 2), androidx.compose.ui.geometry.Offset(w * 0.7f, h / 2), 1.2.dp.toPx())
            } else {
                for (k in 1..3) drawLine(IslandColors.secondary, androidx.compose.ui.geometry.Offset(w * 0.28f, h * k / 4.4f + h * 0.08f), androidx.compose.ui.geometry.Offset(w * 0.72f, h * k / 4.4f + h * 0.08f), 1.dp.toPx())
            }
        }
    }
}
