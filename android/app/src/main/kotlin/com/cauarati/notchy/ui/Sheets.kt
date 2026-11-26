package com.cauarati.notchy.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cauarati.notchy.R
import com.cauarati.notchy.app.AppModel
import com.cauarati.notchy.core.ApprovalSheetPlan
import com.cauarati.notchy.core.HomePanel
import com.cauarati.notchy.core.IconKind
import com.cauarati.notchy.core.MotionSpec
import com.cauarati.notchy.core.QuestionFlow
import com.cauarati.notchy.core.Spacing
import com.cauarati.notchy.core.SpokenLabels
import com.cauarati.notchy.core.Tokens
import com.cauarati.notchy.link.ApprovalRequest
import com.cauarati.notchy.link.QuestionRequest
import kotlinx.coroutines.delay

// A request for permission and a question, drawn as the island draws them on the Mac and the iPhone: AgentWho, the
// command in a CodeBlock, Deny and Allow; the question with its options as chips. On Home they sit in the island
// itself (HomePanel.kt); on any other screen the same card rises in a sheet, so a request is never missed.

/**
 * A panel that rises from the bottom over whatever is on screen, with a dim scrim behind it: black, rounded, with the
 * card's wash, like the island it comes from. Tapping the scrim or pressing Back closes it; taps on the panel itself
 * never reach the scrim.
 */
@Composable
fun BottomSheetHost(onDismiss: () -> Unit, wash: Wash? = null, announce: String? = null, content: @Composable ColumnScope.() -> Unit) {
    BackHandler(onBack = onDismiss)
    val closeLabel = stringResource(R.string.action_close)
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val shape = RoundedCornerShape(topStart = 34.dp, topEnd = 34.dp)
    CompositionLocalProvider(LocalTokens provides Tokens.ISLAND) {
        Box(Modifier.fillMaxSize()) {
            Box(
                Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f))
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onDismiss)
                    .semantics { contentDescription = closeLabel; role = Role.Button },
            )
            AnimatedVisibility(
                visible = shown, modifier = Modifier.align(Alignment.BottomCenter),
                enter = if (reducedMotion()) fadeIn(tween(MotionSpec.REDUCED_MS)) else slideInVertically(spring(dampingRatio = 0.72f, stiffness = 400f)) { it } + fadeIn(),
            ) {
                Column(
                    Modifier.fillMaxWidth().clip(shape).background(IslandColors.card).islandWash(animatedWash(wash), 320.dp)
                        .border(1.dp, Color.White.copy(alpha = 0.06f), shape)
                        .pointerInput(Unit) { detectTapGestures { } }
                        // A large font can make the sheet taller than the screen: it scrolls, so Deny and Allow are always reachable.
                        .verticalScroll(rememberScrollState())
                        // TalkBack announces the sheet when it rises, so a request is heard without searching for it.
                        .semantics { if (announce != null) paneTitle = announce }
                        .padding(start = 20.dp, end = 20.dp, top = 10.dp, bottom = 24.dp),
                    content = {
                        Box(Modifier.align(Alignment.CenterHorizontally).size(width = 36.dp, height = 4.dp).clip(RoundedCornerShape(2.dp)).background(IslandColors.faint))
                        Spacer(Modifier.size(14.dp))
                        content()
                    },
                )
            }
        }
    }
}

/** Allow's mark: the screen lock it goes through (the iPhone shows Face ID's). */
private val lockIcon: @Composable (Color) -> Unit = { tint -> NotchyIcon(IconKind.LOCK, tint = tint, size = 13.dp) }

/**
 * The approval card (the island's ApprovalCard): who and "needs permission", the command as it was sent, Deny, and Allow
 * behind the screen lock. A command the computer had to cut is said in amber, and then only Deny is offered here. Both
 * buttons ignore taps for the first moments, so a tap meant for something else never decides.
 */
@Composable
fun ApprovalCard(model: AppModel, r: ApprovalRequest, onAllow: (ApprovalRequest) -> Unit) {
    var armed by remember(r.fingerprint) { mutableStateOf(false) }
    LaunchedEffect(r.fingerprint) { delay(ApprovalSheetPlan.GUARD_MS); armed = true }
    val colour = model.sessions.firstOrNull { it.pillId == r.pillId }?.let { HomePanel.colorHex(it) }
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        AgentWho(model.agentName(r.pillId), colour, stringResource(R.string.island_needs_permission))
        // The whole command that was sent, scrollable: never cut by a line limit. The lock prompt repeats it.
        CodeBlock(r.command.ifBlank { r.tool }, ApprovalSheetPlan.COMMAND_BOX_MAX_DP.dp)
        val canAllow = ApprovalSheetPlan.canAllowHere(r)
        if (!canAllow) Text(stringResource(R.string.island_cut), style = islandText(10.5.sp, IslandColors.amber))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            IslandButton(stringResource(R.string.action_deny), { model.decide(r.fingerprint, allow = false) }, enabled = armed)
            if (canAllow) IslandButton(stringResource(R.string.action_allow), { onAllow(r) }, primary = true, enabled = armed, icon = lockIcon)
        }
    }
}

/** A request for permission over any screen but Home, where the island itself holds it. */
@Composable
fun ApprovalSheet(model: AppModel, r: ApprovalRequest, onAllow: (ApprovalRequest) -> Unit, onDismiss: () -> Unit) {
    val announce = SpokenLabels.approval(stringResource(R.string.approval_title), model.agentName(r.pillId), stringResource(R.string.approval_wants, ApprovalSheetPlan.action(r.tool)))
    BottomSheetHost(onDismiss, Wash.AMBER, announce) {
        ApprovalCard(model, r, onAllow)
        Text(stringResource(R.string.approval_hint), Modifier.padding(top = 10.dp), style = islandText(11.5.sp, IslandColors.tertiary))
        Text(
            stringResource(R.string.approval_later),
            Modifier.heightIn(min = Spacing.MIN_TOUCH.dp).clickable(role = Role.Button, onClick = onDismiss).padding(vertical = 14.dp),
            style = islandText(12.5.sp, IslandColors.secondary),
        )
    }
}

/**
 * The question card (the island's QuestionCard): "X is asking", the question, its options as chips. A single choice is
 * answered with one tap; a multi-select is picked, then sent. The answer goes through [onSend], which asks for the
 * screen lock first; the labels are the computer's exact ones. Without the `answers` capability it says where to answer.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun QuestionCard(model: AppModel, pillId: String, onSend: (QuestionRequest, List<List<String>>) -> Unit) {
    val request = model.questionFor(pillId)
    val asking = stringResource(R.string.island_is_asking, model.agentName(pillId))
    if (request == null) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            AgentWho(null, null, asking)
            Text(stringResource(R.string.question_body), style = islandText(12.5.sp, IslandColors.body))
        }
        return
    }
    var st by remember(request.fingerprint) { mutableStateOf(QuestionFlow.start(request.questions)) }
    var armed by remember(request.fingerprint) { mutableStateOf(false) }
    LaunchedEffect(request.fingerprint) { delay(ApprovalSheetPlan.GUARD_MS); armed = true }
    val q = request.questions[st.index.coerceIn(0, request.questions.lastIndex)]
    val last = QuestionFlow.isLast(request.questions, st)
    fun proceed(next: com.cauarati.notchy.core.QuestionState) {
        if (QuestionFlow.isLast(request.questions, next)) QuestionFlow.picks(request.questions, next)?.let { onSend(request, it) }
        else st = QuestionFlow.next(request.questions, next)
    }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            AgentWho(null, null, asking, Modifier.weight(1f))
            QuestionFlow.position(request.questions, st)?.let { (n, total) ->
                Text("$n/$total", style = islandText(10.sp, IslandColors.tertiary))
            }
        }
        Text(q.question, style = islandText(13.sp, IslandColors.text, FontWeight.SemiBold), maxLines = 4)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (o in q.options) {
                if (q.multiSelect) {
                    IslandChip(o.label, o.label in st.picks[st.index]) { st = QuestionFlow.toggle(request.questions, st, o.label) }
                } else {
                    // One tap answers a single choice, after the same guard as Allow.
                    IslandButton(o.label, { proceed(QuestionFlow.toggle(request.questions, st, o.label)) }, enabled = armed)
                }
            }
        }
        if (q.multiSelect) {
            IslandButton(
                stringResource(if (last) R.string.question_send else R.string.question_next), { proceed(st) }, primary = true,
                enabled = armed && QuestionFlow.canAdvance(request.questions, st), icon = if (last) lockIcon else null,
            )
        }
    }
}

/** A question over any screen but Home. */
@Composable
fun QuestionSheet(model: AppModel, pillId: String, onDismiss: () -> Unit, onSend: (QuestionRequest, List<List<String>>) -> Unit) {
    BottomSheetHost(onDismiss, Wash.CYAN, stringResource(R.string.question_title, model.agentName(pillId))) {
        QuestionCard(model, pillId, onSend)
        Text(
            stringResource(R.string.approval_later),
            Modifier.heightIn(min = Spacing.MIN_TOUCH.dp).clickable(role = Role.Button, onClick = onDismiss).padding(vertical = 14.dp),
            style = islandText(12.5.sp, IslandColors.secondary),
        )
    }
}

