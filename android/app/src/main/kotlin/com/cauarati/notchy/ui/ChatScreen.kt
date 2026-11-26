package com.cauarati.notchy.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import com.cauarati.notchy.core.Spacing
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.foundation.layout.PaddingValues
import com.cauarati.notchy.core.Tab
import com.cauarati.notchy.core.Tokens
import com.cauarati.notchy.R
import com.cauarati.notchy.app.AppModel
import com.cauarati.notchy.core.ChatMessage
import com.cauarati.notchy.core.ChatReasons
import com.cauarati.notchy.core.ChatTab
import com.cauarati.notchy.core.ChatTabState
import com.cauarati.notchy.core.Screen
import com.cauarati.notchy.core.ShareDraft
import com.cauarati.notchy.mochi.BotState
import com.cauarati.notchy.mochi.MochiEngine
import com.cauarati.notchy.mochi.MochiView
import com.cauarati.notchy.core.ChatRole
import com.cauarati.notchy.core.ChatSession
import com.cauarati.notchy.core.ChatStatus
import com.cauarati.notchy.core.MarkdownLite
import com.cauarati.notchy.core.MdBlock
import com.cauarati.notchy.core.MdSpan
import com.cauarati.notchy.link.Protocol

/** The words for a code the computer (or this app) gives when an answer did not complete. */
@Composable
private fun reasonText(code: String?): String = stringResource(
    when (ChatReasons.key(code)) {
        "off" -> R.string.chat_err_off
        "not_allowed" -> R.string.chat_err_not_allowed
        "busy" -> R.string.chat_err_busy
        "rate" -> R.string.chat_err_rate
        "too_long" -> R.string.chat_err_too_long
        "empty" -> R.string.chat_err_empty
        "no_key" -> R.string.chat_err_no_key
        "unreachable" -> R.string.chat_err_unreachable
        "auth" -> R.string.chat_err_auth
        "provider" -> R.string.chat_err_provider
        "canceled" -> R.string.chat_err_canceled
        "connection" -> R.string.chat_err_connection
        "interrupted" -> R.string.chat_err_interrupted
        else -> R.string.chat_err_internal
    },
)

internal fun chatStateTitle(state: ChatTabState): Int = when (state) {
    ChatTabState.NOT_PAIRED -> R.string.chat_off_not_paired_title
    ChatTabState.NOT_CONNECTED -> R.string.chat_off_offline_title
    ChatTabState.CHAT_OFF -> R.string.chat_off_title
    ChatTabState.NO_MODELS -> R.string.chat_nomodel_title
    ChatTabState.READY -> R.string.chat_title
}

internal fun chatStateBody(state: ChatTabState): Int = when (state) {
    ChatTabState.NOT_PAIRED -> R.string.chat_off_not_paired_body
    ChatTabState.NOT_CONNECTED -> R.string.chat_off_offline_body
    ChatTabState.CHAT_OFF, ChatTabState.NO_MODELS -> R.string.chat_off_hint
    ChatTabState.READY -> R.string.chat_title
}

/** The Chat tab with nothing to chat with: a sleeping Mochi, what is wrong in plain words, and the one button that helps (if any). */
@Composable
private fun ChatEmpty(state: ChatTabState, onHome: () -> Unit, onSettings: () -> Unit) {
    val engine = remember { MochiEngine({ android.os.SystemClock.elapsedRealtimeNanos() / 1e6 }).apply { isMini = true; setState(BotState.SLEEPING, force = true) } }
    Column(
        Modifier.fillMaxSize().padding(horizontal = 30.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically),
    ) {
        MochiView(engine, Modifier.size(54.dp))
        Text(stringResource(chatStateTitle(state)), style = islandText(15.sp, IslandColors.text, FontWeight.SemiBold), textAlign = TextAlign.Center)
        Text(stringResource(chatStateBody(state)), style = islandText(12.5.sp, IslandColors.body), textAlign = TextAlign.Center)
        when (ChatTab.action(state)) {
            Screen.HOME -> IslandButton(stringResource(R.string.chat_go_pair), onHome, primary = true)
            Screen.SETTINGS -> IslandButton(stringResource(R.string.chat_go_settings), onSettings, primary = true)
            else -> {}
        }
    }
}

/**
 * Chat with the computer's AI providers, inside the island as on the Mac and the iPhone (PromptView): your messages on
 * the right, the answers as light Markdown, three dots while waiting, the model above the box. The computer's API key is
 * used on the computer; this screen only ever has text.
 */
@Composable
fun ChatScreen(model: AppModel, onTab: (Tab) -> Unit, onHome: () -> Unit, onSettings: () -> Unit) {
    var text by rememberSaveable { mutableStateOf("") }
    var refusal by remember { mutableStateOf<ChatSession.Refusal?>(null) }
    var confirmClear by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    val messages = model.chatMessages

    LaunchedEffect(Unit) { model.chatRefreshModels() }
    // Follow the answer as it grows.
    val lastLength = messages.lastOrNull()?.text?.length ?: 0
    LaunchedEffect(messages.size, lastLength) {
        if (messages.isNotEmpty()) listState.scrollToItem(messages.size - 1)
    }

    val tabState = model.chatTabState
    // Text shared from another app waits for a chat that can take it: it goes in the box (never sent), or is dropped with a word if the
    // computer does not offer chat. While the computer is not reachable yet it stays, for a couple of minutes.
    val sharedChatOff = stringResource(R.string.share_chat_off)
    LaunchedEffect(tabState, model.shareVersion) {
        when (tabState) {
            ChatTabState.READY -> model.shareDraft.take()?.let { text = ShareDraft.into(text, it) }
            ChatTabState.CHAT_OFF, ChatTabState.NO_MODELS -> if (model.shareDraft.take() != null) model.message = sharedChatOff
            else -> {}
        }
    }

    CompositionLocalProvider(LocalTokens provides Tokens.ISLAND) {
        Box(Modifier.fillMaxSize().background(IslandColors.page)) {
            IslandFrame(model, Tab.CHAT, onTab, onSettings, wash = null, fill = true) {
                // Nothing to chat with and nothing to read: say why, calmly, with the one thing to do about it.
                if (tabState != ChatTabState.READY && messages.isEmpty()) {
                    ChatEmpty(tabState, onHome, onSettings)
                    return@IslandFrame
                }
                if (!model.chatAvailable) {
                    // The conversation stays readable; the reason sits above it.
                    Column(Modifier.padding(horizontal = 18.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(stringResource(chatStateTitle(tabState)), style = islandText(13.sp, IslandColors.text, FontWeight.SemiBold))
                        Text(stringResource(chatStateBody(tabState)), style = islandText(11.5.sp, IslandColors.tertiary))
                    }
                }
                Box(Modifier.weight(1f).fillMaxWidth()) {
                    if (messages.isEmpty()) {
                        val idle = remember { MochiEngine({ android.os.SystemClock.elapsedRealtimeNanos() / 1e6 }).apply { isMini = true; setState(BotState.IDLE, force = true) } }
                        Column(
                            Modifier.fillMaxWidth().padding(top = 40.dp, start = 30.dp, end = 30.dp),
                            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            MochiView(idle, Modifier.size(54.dp))
                            Text(stringResource(R.string.island_ask_anything), style = islandText(13.sp, IslandColors.secondary), textAlign = TextAlign.Center)
                            Text(stringResource(R.string.chat_note), style = islandText(11.sp, IslandColors.tertiary), textAlign = TextAlign.Center)
                        }
                    } else {
                        LazyColumn(
                            state = listState, modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            items(messages, key = { it.id }) { m -> Bubble(m) }
                        }
                    }
                }
                Composer(
                    model, text, refusal,
                    onText = { text = it; refusal = null },
                    onSend = {
                        val r = model.chatSend(text)
                        if (r == null) { text = ""; refusal = null } else refusal = r
                    },
                    onNew = { confirmClear = true },
                )
            }
        }
    }

    if (confirmClear) {
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            title = { Text(stringResource(R.string.chat_clear_title)) },
            text = { Text(stringResource(R.string.chat_clear_body)) },
            confirmButton = {
                TextButton(onClick = { confirmClear = false; model.chatClear() }) {
                    Text(stringResource(R.string.chat_clear), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmClear = false }) { Text(stringResource(R.string.action_cancel)) } },
        )
    }
}

@Composable
private fun Bubble(m: ChatMessage) {
    if (m.role == ChatRole.USER) {
        Row(Modifier.fillMaxWidth().padding(start = 40.dp), horizontalArrangement = Arrangement.End) {
            SelectionContainer {
                Text(
                    m.text,
                    Modifier.clip(RoundedCornerShape(14.dp)).background(Color.White.copy(alpha = 0.13f)).padding(horizontal = 12.dp, vertical = 8.dp),
                    style = islandText(14.sp, Color(0xFFF1F2F4)),
                )
            }
        }
        return
    }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (m.text.isEmpty() && m.status == ChatStatus.STREAMING) TypingDots()
        else if (m.text.isNotEmpty()) SelectionContainer { MarkdownText(m.text) }
        if (m.status == ChatStatus.FAILED) {
            Text(reasonText(m.reason), style = islandText(12.5.sp, Color(0xFFFF8D97)))
        }
    }
}

@Composable
private fun MarkdownText(text: String) {
    val blocks = remember(text) { MarkdownLite.parse(text) }
    val code = Color.White.copy(alpha = 0.07f)
    val body = islandText(14.sp, Color(0xFFDCDEE2)).copy(lineHeight = 20.sp)
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        for (b in blocks) {
            when (b) {
                is MdBlock.Para -> Text(styled(b.spans, code), style = body)
                is MdBlock.Bullet -> Row {
                    Text("•  ", style = body.copy(color = IslandColors.tertiary))
                    Text(styled(b.spans, code), Modifier.weight(1f), style = body)
                }
                is MdBlock.Code -> Text(
                    b.text,
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(code)
                        .border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(10.dp)).padding(10.dp),
                    style = islandText(12.sp, Color(0xFFE8E9EC), mono = true),
                )
            }
        }
    }
}

private fun styled(spans: List<MdSpan>, codeBackground: Color): AnnotatedString = buildAnnotatedString {
    for (s in spans) {
        val style = SpanStyle(
            fontWeight = if (s.bold) FontWeight.SemiBold else null,
            color = if (s.bold) Color(0xFFF5F6F8) else Color.Unspecified,
            fontFamily = if (s.code) FontFamily.Monospace else null,
            background = if (s.code) codeBackground else Color.Unspecified,
        )
        withStyle(style) { append(s.text) }
    }
}

@Composable
private fun Composer(model: AppModel, text: String, refusal: ChatSession.Refusal?, onText: (String) -> Unit, onSend: () -> Unit, onNew: () -> Unit) {
    val limit = Protocol.CHAT_MAX_TEXT
    val length = text.trim().length
    Column(Modifier.fillMaxWidth().padding(bottom = 14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ModelMenu(model, onNew)
        Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            BasicTextField(
                value = text, onValueChange = { onText(it.take(limit + 200)) }, enabled = model.chatAvailable,
                textStyle = islandText(14.sp, IslandColors.text), cursorBrush = SolidColor(IslandColors.text), maxLines = 5,
                modifier = Modifier.weight(1f).heightIn(min = 38.dp).clip(RoundedCornerShape(18.dp)).background(Color.White.copy(alpha = 0.07f))
                    .padding(horizontal = 12.dp, vertical = 9.dp),
                decorationBox = { field ->
                    Box(contentAlignment = Alignment.CenterStart) {
                        if (text.isEmpty()) Text(stringResource(R.string.island_ask_mochi), style = islandText(14.sp, IslandColors.tertiary))
                        field()
                    }
                },
            )
            if (model.chatBusy) {
                RoundButton(stringResource(R.string.chat_stop), true, { model.chatCancel() }) {
                    Box(Modifier.size(11.dp).clip(RoundedCornerShape(2.dp)).background(IslandColors.onLight))
                }
            } else {
                RoundButton(stringResource(R.string.chat_send), enabled = model.chatAvailable && length in 1..limit, onSend) {
                    Glyph(ICON_ARROW_UP, IslandColors.onLight, 18.dp)
                }
            }
        }
        val note = when {
            refusal == ChatSession.Refusal.TOO_LONG || length > limit -> stringResource(R.string.chat_ref_too_long)
            refusal == ChatSession.Refusal.NO_MODEL -> stringResource(R.string.chat_ref_no_model)
            refusal == ChatSession.Refusal.BUSY -> stringResource(R.string.chat_ref_busy)
            refusal == ChatSession.Refusal.OFFLINE -> stringResource(R.string.chat_ref_offline)
            else -> null
        }
        if (note != null) Text(note, Modifier.padding(horizontal = 18.dp), style = islandText(11.5.sp, Color(0xFFFF8D97)))
        else if (length > limit * 9 / 10) {
            Text(stringResource(R.string.chat_count, length, limit), Modifier.padding(horizontal = 18.dp), style = islandText(11.5.sp, IslandColors.tertiary))
        }
    }
}

/** The light round button beside the box: send, or stop while an answer is written. 34 drawn, 48 to hit. */
@Composable
private fun RoundButton(label: String, enabled: Boolean, onClick: () -> Unit, mark: @Composable () -> Unit) {
    Box(
        Modifier.size(Spacing.MIN_TOUCH.dp).clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label }.alpha(if (enabled) 1f else 0.4f),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(34.dp).clip(CircleShape).background(IslandColors.light), contentAlignment = Alignment.Center) { mark() }
    }
}

/** The model above the box, as on the iPhone: its name and a chevron; the menu picks another, or starts a new chat. */
@Composable
private fun ModelMenu(model: AppModel, onNew: () -> Unit) {
    var open by remember { mutableStateOf(false) }
    val models = model.chatModels
    val current = models.firstOrNull { it.id == model.chatModel }
    Box(Modifier.padding(start = 12.dp)) {
        Row(
            Modifier.heightIn(min = Spacing.MIN_TOUCH.dp).clickable(enabled = model.chatAvailable || model.chatMessages.isNotEmpty(), role = Role.Button) { open = true }
                .padding(horizontal = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(current?.label ?: "—", style = islandText(11.sp, IslandColors.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
            StrokeGlyph(ICON_CHEVRON, IslandColors.secondary, 10.dp, 2.6f, Modifier.rotate(90f))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for (m in models) {
                DropdownMenuItem(
                    text = { Text(m.label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    onClick = { model.chatSelect(m.id); open = false },
                )
            }
            if (model.chatMessages.isNotEmpty()) {
                DropdownMenuItem(text = { Text(stringResource(R.string.island_new_chat)) }, onClick = { open = false; onNew() })
            }
        }
    }
}
