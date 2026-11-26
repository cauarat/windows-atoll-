package com.cauarati.notchy.ui

import android.os.SystemClock
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.cauarati.notchy.R
import com.cauarati.notchy.app.AppModel
import com.cauarati.notchy.core.IconKind
import com.cauarati.notchy.core.Spacing
import com.cauarati.notchy.core.Tokens
import com.cauarati.notchy.core.TypeScale
import com.cauarati.notchy.link.PairingPayload
import com.cauarati.notchy.mochi.BotState
import com.cauarati.notchy.mochi.MochiEngine
import com.cauarati.notchy.mochi.MochiView

/**
 * The first screen (the iPhone's PairingView): Mochi under the island, one sentence on what this is, the three steps on the
 * computer, then the ways in: scan the code the computer shows (the main capsule), paste its link, or try the demo. Either
 * way the app names the computer and asks before it pairs.
 */
@Composable
fun PairingScreen(model: AppModel, onScan: () -> Unit, onAbout: () -> Unit) {
    var pasteOpen by remember { mutableStateOf(false) }
    val engine = remember { MochiEngine({ SystemClock.elapsedRealtimeNanos() / 1e6 }).apply { setState(BotState.IDLE, force = true) } }
    CompositionLocalProvider(LocalTokens provides Tokens.ISLAND) {
        Column(Modifier.fillMaxSize().background(IslandColors.page).verticalScroll(rememberScrollState())) {
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(bottomStart = 34.dp, bottomEnd = 34.dp)).background(IslandColors.card)
                    .windowInsetsPadding(WindowInsets.statusBars).padding(top = 36.dp, bottom = 26.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                // SizedMochi at 92: the canvas is the body over 0.6.
                MochiView(engine, Modifier.size(153.dp))
                Text(stringResource(R.string.pairing_title), style = islandText(26.sp, IslandColors.text, FontWeight.Bold))
                Text(
                    stringResource(R.string.pairing_tagline), Modifier.padding(start = 30.dp, end = 30.dp, top = 6.dp),
                    style = islandText(14.sp, IslandColors.body), textAlign = TextAlign.Center,
                )
            }
            IslandCard(Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, top = 18.dp)) {
                Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Step(1, stringResource(R.string.pairing_step1))
                    Step(2, stringResource(R.string.pairing_step2))
                    Step(3, stringResource(R.string.pairing_step3))
                }
            }
            model.message?.let { Box(Modifier.padding(start = 14.dp, end = 14.dp, top = Gap)) { MessagePanel(it) { model.message = null } } }
            Spacer(Modifier.weight(1f).heightIn(min = 32.dp))
            Column(Modifier.fillMaxWidth().padding(bottom = 18.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                IslandButton(stringResource(R.string.pairing_scan), onScan, primary = true, icon = { tint -> NotchyIcon(IconKind.SCAN, tint = tint, size = 14.dp) })
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    IslandButton(stringResource(R.string.pair_paste_short), { pasteOpen = true })
                    IslandButton(stringResource(R.string.demo_try), { model.startDemo() })
                }
                Text(
                    stringResource(R.string.pairing_about),
                    Modifier.heightIn(min = Spacing.MIN_TOUCH.dp).clickable(role = Role.Button, onClick = onAbout).padding(horizontal = 16.dp, vertical = 14.dp),
                    style = islandText(12.sp, IslandColors.tertiary).copy(textDecoration = TextDecoration.Underline),
                )
                Text(stringResource(R.string.pairing_credit), Modifier.padding(horizontal = 30.dp), style = islandText(11.sp, IslandColors.faint), textAlign = TextAlign.Center)
            }
        }
        if (pasteOpen) PasteSheet(model, onDismiss = { pasteOpen = false })
    }
}

/** A step on the computer: its number in a light disc, then what to do. */
@Composable
private fun Step(n: Int, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(22.dp).clip(CircleShape).background(IslandColors.light), contentAlignment = Alignment.Center) {
            Text("$n", style = islandText(12.sp, IslandColors.onLight, FontWeight.Bold))
        }
        Text(text, Modifier.weight(1f), style = islandText(13.5.sp, Color(0xFFC9CDD4)))
    }
}

/** The pairing link as text, for people who cannot scan. A link that is not a Notchy one is refused here, with the same words as everywhere. */
@Composable
private fun PasteSheet(model: AppModel, onDismiss: () -> Unit) {
    var text by remember { mutableStateOf("") }
    var bad by remember { mutableStateOf(false) }
    val clipboard = LocalClipboardManager.current
    val white = Color(tokens().heroText)
    val dim = Color(tokens().heroTextDim)
    fun pairWith(link: String) {
        if (PairingPayload.parse(link) != null) { model.pair(link); onDismiss() } else bad = true
    }
    BottomSheetHost(onDismiss) {
        Text(stringResource(R.string.paste_title), style = TypeScale.TITLE.style(white))
        Text(stringResource(R.string.paste_hint), Modifier.padding(top = 4.dp, bottom = 12.dp), style = TypeScale.SECONDARY.style(dim))
        OutlinedTextField(
            text, { text = it; bad = false }, Modifier.fillMaxWidth(), singleLine = true, shape = RoundedCornerShape(14.dp),
            placeholder = { Text("notchy://pair?…", color = Color(Tokens.DARK.textFaint)) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = white, unfocusedTextColor = white, cursorColor = white,
                focusedBorderColor = white, unfocusedBorderColor = Color(tokens().heroText).copy(alpha = 0.25f),
            ),
        )
        if (bad) Text(stringResource(R.string.msg_bad_link), Modifier.padding(top = 8.dp), style = TypeScale.SECONDARY.style(Color(Tokens.DARK.danger)))
        Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            IslandButton(stringResource(R.string.pair_clipboard), { text = clipboard.getText()?.text.orEmpty().trim(); bad = false })
            IslandButton(stringResource(R.string.pair_button), { pairWith(text.trim()) }, primary = true, enabled = text.isNotBlank())
        }
    }
}

/** A short notice with a Close button, in a panel. */
@Composable
fun MessagePanel(text: String, onClose: () -> Unit) {
    val t = tokens()
    Panel {
        Row(Modifier.padding(start = Spacing.INSIDE.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(text, Modifier.weight(1f).padding(vertical = 12.dp), style = TypeScale.BODY.style(t.text.c()))
            Text(
                stringResource(R.string.action_close),
                Modifier.heightIn(min = Spacing.MIN_TOUCH.dp).clickable(role = Role.Button, onClick = onClose).padding(horizontal = 16.dp, vertical = 14.dp),
                style = TypeScale.LABEL.style(t.textDim.c()),
            )
        }
    }
}
