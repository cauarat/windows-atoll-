package com.cauarati.notchy.ui

import com.cauarati.notchy.core.Languages
import com.cauarati.notchy.app.AppLanguage
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.material3.AlertDialog
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import com.cauarati.notchy.core.IconKind
import com.cauarati.notchy.core.Spacing
import com.cauarati.notchy.core.TypeScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cauarati.notchy.Attribution
import com.cauarati.notchy.R
import com.cauarati.notchy.app.AppModel
import com.cauarati.notchy.app.Mode
import com.cauarati.notchy.core.MotionChoice
import com.cauarati.notchy.core.ThemeChoice
import com.cauarati.notchy.core.ThemePolicy
import com.cauarati.notchy.sound.SoundVolume

/**
 * The screen's title on one line; a long title is cut with "…". Sub-pages pass [onBack] and get a Back
 * button; the three tab screens pass null (the bar is their navigation) and get the plain title.
 */
@Composable
fun ScreenTitle(title: String, onBack: (() -> Unit)?, trailing: @Composable (() -> Unit)? = null) {
    if (onBack == null) {
        Row(Modifier.padding(top = Spacing.INSIDE.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title, Modifier.weight(1f).padding(start = 4.dp), style = TypeScale.TITLE.style(tokens().text.c()), maxLines = 1, overflow = TextOverflow.Ellipsis)
            trailing?.invoke()
        }
        return
    }
    Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        TextButton(onClick = onBack) { Text(stringResource(R.string.action_back), maxLines = 1) }
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        trailing?.invoke()
    }
}

/** A small heading above a card, the same on every screen. */
@Composable
fun SectionTitle(text: String) {
    Text(
        text, Modifier.padding(start = 4.dp, top = 4.dp),
        style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.SemiBold,
        maxLines = 1,
    )
}

/** A setting with a switch at its end. */
@Composable
fun SettingSwitch(title: String, hint: String?, checked: Boolean, onChange: (Boolean) -> Unit) {
    ListRow(title, hint = hint, trailing = { NotchySwitch(checked, onChange, label = title) })
}

/** A row that opens another page: its title and a chevron. */
@Composable
private fun LinkRow(title: String, onClick: () -> Unit) {
    ListRow(title, onClick = onClick, trailing = { NotchyIcon(IconKind.CHEVRON, tint = tokens().textDim.c(), size = 20.dp) })
}

/** A title over a row of choices, one of them selected (read as radio buttons by TalkBack). */
@Composable
private fun <T> ChoiceRow(title: String, options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit) {
    val t = tokens()
    Column(Modifier.padding(horizontal = Spacing.INSIDE.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = TypeScale.BODY.style(t.text.c()))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((value, label) in options) {
                PillButton(
                    label, { onSelect(value) },
                    Modifier.weight(1f).semantics { this.selected = value == selected; role = Role.RadioButton },
                    if (value == selected) PillKind.PRIMARY else PillKind.SECONDARY,
                    // Three pills share the row (about 90 dp each on a 360 dp phone): the default 22 dp a side cut "Standard" to "Stan…".
                    sidePadding = 8.dp,
                )
            }
        }
    }
}

/** The language of the app: the row shows the one in force; a tap opens the list (the phone's own first, then each language by its own name). */
@Composable
private fun LanguageRow() {
    val context = LocalContext.current
    val t = tokens()
    var open by remember { mutableStateOf(false) }
    val current = AppLanguage.current(context)
    val system = stringResource(R.string.language_system)
    val currentName = Languages.ALL.firstOrNull { it.tag == current }?.name ?: system
    ListRow(
        stringResource(R.string.settings_language), hint = currentName, onClick = { open = true },
        trailing = { NotchyIcon(IconKind.CHEVRON, tint = t.textDim.c(), size = 20.dp) },
    )
    if (open) {
        AlertDialog(
            onDismissRequest = { open = false },
            confirmButton = { TextButton(onClick = { open = false }) { Text(stringResource(R.string.action_cancel)) } },
            title = { Text(stringResource(R.string.settings_language)) },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    Text(stringResource(R.string.language_picker_hint), Modifier.padding(bottom = 8.dp), style = TypeScale.SECONDARY.style(t.textDim.c()))
                    val options = listOf(Languages.SYSTEM to system) + Languages.ALL.map { it.tag to it.name }
                    for ((tag, label) in options) {
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = Spacing.MIN_TOUCH.dp)
                                .selectable(selected = tag == current, role = Role.RadioButton) { open = false; AppLanguage.set(context, tag) }
                                .padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Text(label, Modifier.weight(1f), style = TypeScale.BODY.style(t.text.c()))
                            if (tag == current) NotchyIcon(IconKind.CHECK, tint = t.online.c(), size = 22.dp)
                        }
                    }
                }
            },
        )
    }
}

/** Room under a list so its last row can scroll above the floating bar (64 + 16 gap + 16 margin). */
val BarClearance = 96.dp

/**
 * Settings, a tab. Grouped, each group one panel: your computer (with Disconnect at the bottom, away
 * from the everyday switches), the display, sound, more, and About (Louis Raillé's required notice).
 */
@Composable
fun SettingsScreen(model: AppModel, onGallery: () -> Unit, onWardrobe: () -> Unit, onDiagnostics: () -> Unit, onLicences: () -> Unit) {
    val s = model.settings
    val uri = LocalUriHandler.current
    val t = tokens()
    LazyColumn(
        Modifier.padding(horizontal = Gutter), contentPadding = PaddingValues(bottom = BarClearance),
        verticalArrangement = Arrangement.spacedBy(Gap),
    ) {
        item { ScreenTitle(stringResource(R.string.settings_title), null) }

        item { SectionHeading(stringResource(R.string.settings_section_computer)) }
        item {
            Panel {
                Row(Modifier.padding(Spacing.INSIDE.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.GAP.dp), verticalAlignment = Alignment.CenterVertically) {
                    StateDot(linkDotColor(model))
                    Text(linkStatusText(model), Modifier.weight(1f), style = TypeScale.BODY.style(t.text.c()), maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
                when (model.mode) {
                    Mode.PAIRED -> {
                        RowDivider()
                        LinkRow(stringResource(R.string.diag_title), onDiagnostics)
                        RowDivider()
                        PillButton(stringResource(R.string.action_unpair), { model.unpair() }, Modifier.fillMaxWidth().padding(Spacing.INSIDE.dp), PillKind.DANGER)
                    }
                    Mode.NONE -> Text(
                        stringResource(R.string.settings_computer_none), Modifier.padding(start = Spacing.INSIDE.dp, end = Spacing.INSIDE.dp, bottom = Spacing.INSIDE.dp),
                        style = TypeScale.SECONDARY.style(t.textDim.c()),
                    )
                }
            }
        }

        item { SectionHeading(stringResource(R.string.settings_section_display)) }
        item {
            Panel {
                LanguageRow()
                RowDivider()
                ChoiceRow(
                    stringResource(R.string.settings_theme),
                    listOf(
                        ThemeChoice.SYSTEM to stringResource(R.string.theme_system),
                        ThemeChoice.LIGHT to stringResource(R.string.theme_light),
                        ThemeChoice.DARK to stringResource(R.string.theme_dark),
                    ),
                    s.theme,
                ) { model.updateSettings(s.copy(theme = it)) }
                if (ThemePolicy.dynamicAvailable(android.os.Build.VERSION.SDK_INT)) {
                    RowDivider()
                    SettingSwitch(stringResource(R.string.settings_dynamic), stringResource(R.string.settings_dynamic_hint), s.dynamicColour) {
                        model.updateSettings(s.copy(dynamicColour = it))
                    }
                }
                RowDivider()
                ChoiceRow(
                    stringResource(R.string.settings_motion),
                    listOf(
                        MotionChoice.SYSTEM to stringResource(R.string.motion_system),
                        MotionChoice.REDUCE to stringResource(R.string.motion_on),
                        MotionChoice.FULL to stringResource(R.string.motion_off),
                    ),
                    s.motion,
                ) { model.updateSettings(s.copy(motion = it)) }
                Text(
                    stringResource(R.string.settings_motion_hint),
                    Modifier.padding(horizontal = Spacing.INSIDE.dp).padding(bottom = 12.dp),
                    style = TypeScale.SECONDARY.style(t.textDim.c()),
                )
            }
        }

        item { SectionHeading(stringResource(R.string.settings_section_sound)) }
        item {
            Panel {
                SettingSwitch(stringResource(R.string.settings_sound), null, s.soundOn) { model.updateSettings(s.copy(soundOn = it)) }
                RowDivider()
                Column(Modifier.padding(horizontal = Spacing.INSIDE.dp, vertical = 8.dp)) {
                    Row {
                        Text(stringResource(R.string.settings_volume), Modifier.weight(1f), style = TypeScale.BODY.style(t.text.c()))
                        Text("${(s.volume / SoundVolume.MAX * 100).toInt().coerceIn(0, 100)}%", style = TypeScale.SECONDARY.style(t.textDim.c()))
                    }
                    NotchySlider(
                        value = s.volume, onChange = { model.updateSettings(s.copy(volume = SoundVolume.clamp(it))) },
                        valueRange = 0f..SoundVolume.MAX, enabled = s.soundOn, label = stringResource(R.string.settings_volume),
                    )
                }
            }
        }

        item { SectionHeading(stringResource(R.string.settings_section_more)) }
        item {
            Panel {
                LinkRow(stringResource(R.string.wardrobe_title), onWardrobe)
                RowDivider()
                LinkRow(stringResource(R.string.gallery), onGallery)
            }
        }

        // Required by Louis Raillé's permission: visible, one tap from Home.
        item { SectionHeading(stringResource(R.string.settings_section_about)) }
        item {
            Panel {
                Column(Modifier.padding(Spacing.INSIDE.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.about_credit), style = TypeScale.BODY.style(t.text.c()))
                    Text(
                        stringResource(R.string.about_repo),
                        Modifier.heightIn(min = Spacing.MIN_TOUCH.dp).clickable(role = Role.Button) { runCatching { uri.openUri(Attribution.REPO_URL) } }.padding(vertical = 14.dp),
                        style = TypeScale.BODY.style(t.text.c()).copy(textDecoration = TextDecoration.Underline),
                    )
                    Text(stringResource(R.string.about_assets), style = TypeScale.SECONDARY.style(t.textDim.c()))
                }
                RowDivider()
                LinkRow(stringResource(R.string.licences_title), onLicences)
            }
        }
        item { Spacer(Modifier.height(Gutter)) }
    }
}
