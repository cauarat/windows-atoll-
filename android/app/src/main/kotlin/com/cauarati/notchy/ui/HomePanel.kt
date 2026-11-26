package com.cauarati.notchy.ui

import android.os.SystemClock
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cauarati.notchy.R
import com.cauarati.notchy.app.AppModel
import com.cauarati.notchy.app.Mode
import com.cauarati.notchy.core.Decision
import com.cauarati.notchy.core.HistoryDays
import com.cauarati.notchy.core.HomePanel
import com.cauarati.notchy.core.HomeText
import com.cauarati.notchy.core.Pills
import com.cauarati.notchy.core.Spacing
import com.cauarati.notchy.core.SpokenLabels
import com.cauarati.notchy.core.Tab
import com.cauarati.notchy.core.Tokens
import com.cauarati.notchy.core.TypeScale
import com.cauarati.notchy.link.ApprovalRequest
import com.cauarati.notchy.link.LinkState
import com.cauarati.notchy.link.QuestionRequest
import com.cauarati.notchy.link.SessionInfo
import com.cauarati.notchy.mochi.BotState
import com.cauarati.notchy.mochi.MochiConst
import com.cauarati.notchy.mochi.MochiEngine
import com.cauarati.notchy.mochi.MochiView
import com.cauarati.notchy.mochi.Rgb
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.delay
import kotlin.math.min

internal fun stateLabel(state: BotState): Int = when (state) {
    BotState.IDLE -> R.string.state_ready
    BotState.WORKING -> R.string.state_working
    BotState.THINKING -> R.string.state_thinking
    BotState.SEARCHING -> R.string.state_searching
    BotState.APPROVAL -> R.string.state_approval
    BotState.QUESTION -> R.string.state_question
    BotState.ERROR -> R.string.state_error
    BotState.FINISHED -> R.string.state_finished
    BotState.RATELIMIT -> R.string.state_ratelimit
    BotState.SLEEPING -> R.string.state_sleeping
    BotState.DIZZY -> R.string.state_dizzy
}

internal fun rgbColor(c: Rgb) = Color(c.r.toFloat(), c.g.toFloat(), c.b.toFloat())

/** The colour of an agent's state (Louis's state colours), for dots and glows. */
internal fun stateColor(state: BotState): Color =
    if (state == BotState.IDLE) StatusColors.online else MochiConst.STATES[state]?.color?.let(::rgbColor) ?: StatusColors.offline

/**
 * The colour a pill's Mochi wears: Claude Code wears the state's colours (working blue, thinking purple…), a pill with
 * a brand colour of its own wears that, as on the island (MainView.botColor on the iPhone).
 */
internal fun botColor(s: SessionInfo?): Rgb? {
    s ?: return null
    val hex = HomePanel.colorHex(s) ?: return null
    if (s.pillId == "integration_claude" || hex.equals("#F5F6F8", ignoreCase = true)) return null
    return HomePanel.rgb(hex)
}

/** Keeps an engine dressed as its pill is on the computer, every frame the session changes. */
internal fun MochiEngine.wear(s: SessionInfo?, color: Rgb?) {
    bodyColor = color
    character = s?.character ?: com.cauarati.notchy.mochi.MochiCharacter.CLASSIC
}

// ── The island ───────────────────────────────────────────────────────────────

private val ISLAND_SHAPE = RoundedCornerShape(bottomStart = 34.dp, bottomEnd = 34.dp)

/**
 * The island, hanging from the top of the screen the way it hangs from the notch on the Mac: black, flat across the top,
 * rounded 34 below, a wash rising from below, the header's tabs (Home and Chat, then sound and Settings) and [body].
 * [fill] grows it to the screen's height (Chat), otherwise it is as tall as what it holds.
 */
@Composable
fun IslandFrame(
    model: AppModel, tab: Tab, onTab: (Tab) -> Unit, onSettings: () -> Unit, wash: Wash?, fill: Boolean,
    modifier: Modifier = Modifier, body: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier.padding(horizontal = 4.dp).fillMaxWidth()
            .then(if (fill) Modifier.fillMaxSize().padding(bottom = 12.dp) else Modifier)
            .shadow(16.dp, ISLAND_SHAPE, ambientColor = Color.Black.copy(alpha = 0.5f), spotColor = Color.Black.copy(alpha = 0.5f))
            .clip(ISLAND_SHAPE).background(IslandColors.card).islandWash(animatedWash(wash), 320.dp)
            .animateContentSize(spring(dampingRatio = 0.78f, stiffness = Spring.StiffnessMediumLow)),
    ) {
        Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        IslandHeader(model, tab, onTab, onSettings)
        body()
    }
}

@Composable
private fun IslandHeader(model: AppModel, tab: Tab, onTab: (Tab) -> Unit, onSettings: () -> Unit) {
    val sound = model.settings.soundOn
    Row(Modifier.fillMaxWidth().height(44.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.padding(start = 10.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            val alert = model.approvals.isNotEmpty()
            IslandTab(tab == Tab.HOME, SpokenLabels.tab(stringResource(R.string.tab_home), alert, stringResource(R.string.tab_home_alert)), { onTab(Tab.HOME) }) {
                Glyph(ICON_HOUSE, it, GlyphBox.house)
            }
            IslandTab(tab == Tab.CHAT, stringResource(R.string.tab_chat), { onTab(Tab.CHAT) }) { Glyph(ICON_CHAT_SPARKLE, it, GlyphBox.chatSparkle) }
        }
        Spacer(Modifier.weight(1f))
        // The link, as a dot: green when the computer answers, amber while it is looked for.
        val connected = model.mode == Mode.DEMO || (model.mode == Mode.PAIRED && model.linkState == LinkState.CONNECTED)
        val said = linkStatusTextPlain(connected)
        Box(
            Modifier.padding(end = 2.dp).size(6.dp).clip(CircleShape).background(if (connected) IslandColors.added else IslandColors.amber)
                .semantics { contentDescription = said },
        )
        Row(Modifier.padding(end = 6.dp)) {
            IslandIconButton(
                stringResource(if (sound) R.string.island_sound_on else R.string.island_sound_off),
                { model.updateSettings(model.settings.copy(soundOn = !sound)) },
            ) { if (sound) Glyph(ICON_SPEAKER_ON, it, GlyphBox.speakerOn) else Glyph(ICON_SPEAKER_OFF, it, GlyphBox.speakerOff) }
            IslandIconButton(stringResource(R.string.tab_settings), onSettings) { Glyph(ICON_GEAR, it, GlyphBox.gear) }
        }
    }
}

@Composable
private fun linkStatusTextPlain(connected: Boolean) = stringResource(if (connected) R.string.status_connected else R.string.status_not_connected)

/** The soft light behind Mochi on the island (BotPlacement), by state. */
@Composable
private fun BotGlow(state: BotState, diameter: Dp) {
    val c = when (state) {
        BotState.WORKING -> Color(0xFF3B9EFF)
        BotState.THINKING -> Color(0xFFA78BFA)
        BotState.SEARCHING -> Color(0xFF6366F1)
        BotState.APPROVAL -> Color(0xFFF5A524)
        BotState.ERROR -> Color(0xFFF4505E)
        BotState.FINISHED -> Color(0xFF34D399)
        BotState.RATELIMIT -> Color(0xFFF59E0B)
        else -> Color.White
    }
    val alpha = when (state) { BotState.IDLE, BotState.SLEEPING -> 0.15f; BotState.DIZZY -> 0f; else -> 0.65f }
    Canvas(Modifier.size(diameter * 2.2f)) {
        val r = diameter.toPx() * 1.1f
        drawCircle(Brush.radialGradient(0f to c.copy(alpha = alpha * 0.8f), 0.62f to Color.Transparent, center = center, radius = r), radius = r)
    }
}

// ── Home ─────────────────────────────────────────────────────────────────────

/**
 * Home: the island on top (Mochi on the left; on the right the request waiting, the question, or the session in focus
 * with its ticker), the agents under it, one card per pill, then what only the phone has (the link's health, plan
 * usage, recent decisions…). Everything in the island's colours, in both themes, as on the Mac.
 */
@Composable
fun HomeScreen(
    model: AppModel, onApprove: (ApprovalRequest) -> Unit, onAnswer: (QuestionRequest, List<List<String>>) -> Unit,
    onSession: (String) -> Unit, onTab: (Tab) -> Unit, onSettings: () -> Unit, onScan: () -> Unit, onHistory: () -> Unit,
    onDiagnostics: () -> Unit, onLaunch: () -> Unit, onOverlay: (Boolean) -> Unit, overlayHint: @Composable () -> Unit,
) {
    val clock = remember { { SystemClock.elapsedRealtimeNanos() / 1e6 } }
    val engines = remember { HashMap<String, MochiEngine>() }
    val miniEngines = remember { HashMap<String, MochiEngine>() }
    val touches = remember { HashMap<String, MochiTouch>() }
    var selected by rememberSaveable { mutableStateOf<String?>(null) }
    var addressOpen by rememberSaveable { mutableStateOf(false) }
    var islandPx by remember { mutableIntStateOf(0) }
    val density = LocalDensity.current

    // Allow tapped on a notification before the link was back: open the prompt once the request is here.
    LaunchedEffect(model.approvals, model.wantAllow) {
        val fp = model.wantAllow ?: return@LaunchedEffect
        model.approvals.firstOrNull { it.fingerprint == fp }?.let {
            model.wantAllow = null
            onApprove(it)
        }
    }

    val focus = HomePanel.focus(model.sessions, selected)
    val approval = model.approvals.firstOrNull()
    val question = model.questions.firstOrNull()
    val connected = model.mode == Mode.DEMO || (model.mode == Mode.PAIRED && model.linkState == LinkState.CONNECTED)
    val key = approval?.pillId ?: question?.pillId ?: focus?.pillId ?: HOME_KEY
    val pill = model.sessions.firstOrNull { it.pillId == key }
    val engine = engines.getOrPut(key) { MochiEngine(clock, sound = model.sounds) }
    val touch = touches.getOrPut(key) { MochiTouch(engine, model.sounds) { model.sessions.firstOrNull { it.pillId == key }?.state ?: BotState.IDLE } }
    val state = when {
        approval != null -> BotState.APPROVAL
        question != null -> BotState.QUESTION
        !connected -> BotState.SLEEPING
        else -> focus?.state ?: BotState.IDLE
    }
    if (engine.state != state && !touch.dizzy) engine.setState(state)
    // The hero wears what the computer says (a new engine starts dressed, a change animates).
    val dressed = remember { HashSet<MochiEngine>() }
    model.dress().let { outfit -> if (dressed.add(engine)) engine.setOutfit(outfit, animated = false) else engine.setOutfit(outfit) }
    engine.wear(pill, botColor(pill))

    val wash = when {
        approval != null -> Wash.AMBER
        question != null -> Wash.CYAN
        focus?.state == BotState.FINISHED -> Wash.GREEN
        focus?.state == BotState.ERROR -> Wash.RED
        else -> null
    }

    CompositionLocalProvider(LocalTokens provides Tokens.ISLAND) {
        Box(Modifier.fillMaxSize().background(IslandColors.page)) {
            val top = with(density) { islandPx.toDp() } + 6.dp
            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 12.dp, end = 12.dp, top = top, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                // The link had worked and ended: what happened and how long ago. And, only if it would help, the battery setting.
                if (model.mode == Mode.PAIRED && model.linkState != LinkState.CONNECTED) item { LinkHealthPanel(model, onDiagnostics) }
                if (model.batteryHintVisible) item { BatteryCard(model) }
                if (model.mode == Mode.PAIRED && model.linkState != LinkState.CONNECTED && model.discovery == com.cauarati.notchy.link.DiscoveryState.NOT_FOUND) {
                    item { DiscoveryHint(onPairAgain = onScan, onEnterAddress = { addressOpen = true }) }
                }
                if (model.sessions.isNotEmpty()) {
                    item {
                        Row(Modifier.fillMaxWidth().padding(start = 6.dp, end = 6.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(stringResource(R.string.island_agents), Modifier.weight(1f), style = islandText(12.sp, IslandColors.secondary, FontWeight.SemiBold))
                            model.desktopName?.takeIf { it.isNotBlank() }?.let {
                                Text(it, style = islandText(11.sp, IslandColors.tertiary), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                    items(model.sessions, key = { it.pillId }) { s ->
                        val mini = miniEngines.getOrPut(s.pillId) { MochiEngine(clock).apply { isMini = true } }
                        mini.wear(s, HomePanel.colorHex(s)?.let { HomePanel.rgb(it) })
                        if (mini.state != s.state) mini.setState(s.state)
                        AgentCard(s, mini, focused = s.pillId == focus?.pillId) {
                            selected = s.pillId
                            onSession(s.pillId)
                        }
                    }
                } else if (connected) {
                    item {
                        Text(
                            stringResource(R.string.island_no_agents), Modifier.fillMaxWidth().padding(start = 30.dp, end = 30.dp, top = 30.dp),
                            style = islandText(12.5.sp, IslandColors.tertiary), textAlign = TextAlign.Center,
                        )
                    }
                }
                // A paired computer that offers it: start a Claude Code session there (Notchy's Mac never does).
                if (model.mode == Mode.PAIRED && model.launchOffered) item { LaunchRow(onLaunch) }
                if (model.recap != null) item { RecapPanel(model.recap) }
                if (model.usage != null) item { UsagePanel(model.usage) }
                if (model.services.isNotEmpty()) item { ServicesPanel(model.services) }
                item { RecentPanel(model.decisions, onHistory) }
                if (model.overlayWished && !model.overlayPermission) item { overlayHint() }
            }

            IslandFrame(
                model, Tab.HOME, onTab, onSettings, wash, fill = false,
                Modifier.align(Alignment.TopCenter).onSizeChanged { islandPx = it.height },
            ) {
                Row(Modifier.fillMaxWidth().heightIn(min = 122.dp).padding(top = 6.dp, bottom = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.width(104.dp), contentAlignment = Alignment.Center) {
                        BotGlow(state, 62.dp)
                        MochiView(engine, Modifier.size(103.dp).then(touch.modifier))
                    }
                    Box(Modifier.weight(1f).padding(end = 14.dp)) {
                        val card = when {
                            approval != null -> "a:" + approval.fingerprint
                            question != null -> "q:" + question.fingerprint
                            !connected -> "c"
                            focus != null -> "f:" + focus.pillId
                            else -> "e"
                        }
                        AnimatedContent(card, transitionSpec = { fadeIn(tween(200)) togetherWith fadeOut(tween(200)) }, label = "card") { which ->
                            when {
                                which.startsWith("a:") && approval != null -> ApprovalCard(model, approval, onApprove)
                                which.startsWith("q:") && question != null -> QuestionCard(model, question.pillId, onAnswer)
                                which == "c" -> ConnectingCard(model, onScan, onDiagnostics)
                                which.startsWith("f:") && focus != null -> FocusCard(focus) { onSession(focus.pillId) }
                                else -> EmptyCard()
                            }
                        }
                    }
                }
            }

            // What the app has to say (an answer sent, a request no longer pending), as a capsule under the island.
            model.message?.let { msg ->
                LaunchedEffect(msg) { delay(4_000); if (model.message == msg) model.message = null }
                Text(
                    msg,
                    Modifier.align(Alignment.TopCenter).offset(y = top + 6.dp).padding(horizontal = 24.dp)
                        .heightIn(min = Spacing.MIN_TOUCH.dp).clickable(role = Role.Button) { model.message = null }
                        .clip(CircleShape).background(IslandColors.tabOn).border(1.dp, Color.White.copy(alpha = 0.06f), CircleShape)
                        .padding(horizontal = 14.dp, vertical = 9.dp),
                    style = islandText(12.5.sp, IslandColors.text, FontWeight.Medium), textAlign = TextAlign.Center,
                )
            }
        }
        if (addressOpen) AddressSheet(model) { addressOpen = false }
    }
}

private const val HOME_KEY = "home"

/** The session in focus (FocusCard): its dot, its project and agent, how far it got, and the last steps as the ticker. */
@Composable
private fun FocusCard(s: SessionInfo, open: () -> Unit) {
    val name = s.agent.ifBlank { Pills.byId(s.pillId)?.name.orEmpty() }
    val spoken = SpokenLabels.agent(name, stringResource(stateLabel(s.state)), HomeText.line(s))
    val waiting = stringResource(R.string.island_waiting_prompt)
    val steps = s.steps.map(::islandStep).filter { it.isNotBlank() }
        .ifEmpty { listOfNotNull(islandStep(s.statusText).takeIf { it.isNotBlank() }) }
        .ifEmpty { listOf(waiting) }
    val lines = steps.takeLast(if (s.state == BotState.FINISHED) 1 else 2)
    Column(Modifier.heightIn(min = Spacing.MIN_TOUCH.dp).clickable(role = Role.Button, onClick = open).semantics(mergeDescendants = true) { contentDescription = spoken }) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.size(7.dp).clip(CircleShape).background(hexColor(HomePanel.colorHex(s)) ?: Color(0xFFC0C4CC)))
            Text(s.project ?: name, style = islandText(12.sp, IslandColors.text, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (s.project != null) Text(name, Modifier.weight(1f, fill = false), style = islandText(11.sp, IslandColors.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.weight(1f))
            if (s.stepCount > 1) Text("${min(s.stepIndex + 1, s.stepCount)}/${s.stepCount}", style = islandText(11.sp, IslandColors.tertiary), maxLines = 1)
            Box(Modifier.size(20.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.07f)), contentAlignment = Alignment.Center) {
                Glyph(ICON_ARROW_UP_RIGHT, Color(0xFF5F646D), 13.dp)
            }
        }
        Column(Modifier.padding(top = 2.dp)) {
            lines.forEachIndexed { i, line -> TickerRow(line, current = i == lines.lastIndex && s.state.isBusy) }
        }
        if (s.state == BotState.FINISHED) {
            s.finalLine?.let(::islandStep)?.takeIf { it.isNotBlank() }?.let {
                Text(it, Modifier.padding(top = 4.dp), style = islandText(12.5.sp, IslandColors.text, FontWeight.SemiBold), maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun EmptyCard() {
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(stringResource(R.string.island_empty_title), style = islandText(15.sp, IslandColors.text, FontWeight.SemiBold))
        Text(stringResource(R.string.island_empty_hint), style = islandText(13.sp, IslandColors.body))
    }
}

/** The computer cannot be reached: where the link stands, and the way to find out why. */
@Composable
private fun ConnectingCard(model: AppModel, onScan: () -> Unit, onDiagnostics: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(linkStatusText(model), style = islandText(15.sp, IslandColors.text, FontWeight.SemiBold), maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(stringResource(R.string.chat_off_offline_body), style = islandText(12.5.sp, IslandColors.body))
        if (model.mode == Mode.PAIRED) IslandButton(stringResource(R.string.diag_title), onDiagnostics)
        else IslandButton(stringResource(R.string.link_pair), onScan)
    }
}

/** A pill (AgentRow): its little Mochi, project and agent, the state in its colour, the lines it changed. */
@Composable
private fun AgentCard(s: SessionInfo, engine: MochiEngine, focused: Boolean, onClick: () -> Unit) {
    val name = s.agent.ifBlank { Pills.byId(s.pillId)?.name.orEmpty() }
    val state = stringResource(islandStateWord(s.state))
    val line = HomeText.line(s)
    // The dot is only a colour: the state is said in words, with the line when it adds something.
    val spoken = SpokenLabels.agent(name, state, line)
    IslandCard(Modifier.fillMaxWidth(), wash = washFor(s.state), focused = focused) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 58.dp).clickable(role = Role.Button, onClick = onClick)
                .semantics(mergeDescendants = true) { contentDescription = spoken }
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            MochiView(engine, Modifier.size(34.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(s.project ?: name, style = islandText(14.sp, IslandColors.text, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (s.project != null) Text(name, style = islandText(12.sp, IslandColors.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(state, style = islandText(12.sp, islandStateColor(s.state)))
                    val doing = islandStep(s.statusText)
                    if (doing.isNotBlank() && s.state.isBusy) {
                        Text("· $doing", style = islandText(12.sp, IslandColors.tertiary), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            if (s.files.isNotEmpty()) LineCounts(s.files.sumOf { it.added }, s.files.sumOf { it.removed })
            StrokeGlyph(ICON_CHEVRON, IslandColors.faint, 12.dp, 2.4f)
        }
    }
}

/** The last few things you allowed or denied, in plain words, with "See all" to the full list. */
@Composable
fun RecentPanel(decisions: List<Decision>, onAll: () -> Unit) {
    if (decisions.isEmpty()) return
    val t = tokens()
    val zone = remember { ZoneId.systemDefault() }
    val timeFormat = remember { DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT) }
    val dateFormat = remember { DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT) }
    val now = System.currentTimeMillis()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.recent_title), Modifier.weight(1f), style = islandText(12.sp, IslandColors.secondary, FontWeight.SemiBold))
            Text(
                stringResource(R.string.recent_all),
                Modifier.heightIn(min = Spacing.MIN_TOUCH.dp).clickable(role = Role.Button, onClick = onAll).padding(horizontal = 4.dp, vertical = 12.dp),
                style = islandText(11.sp, IslandColors.tertiary),
            )
        }
        Panel {
            decisions.take(2).forEachIndexed { i, d ->
                if (i > 0) RowDivider()
                val (day, date) = HistoryDays.classify(d.atMs, now, zone)
                val whenText = when (day) {
                    HistoryDays.Day.TODAY -> timeFormat.format(Instant.ofEpochMilli(d.atMs).atZone(zone).toLocalTime())
                    HistoryDays.Day.YESTERDAY -> stringResource(R.string.history_yesterday)
                    HistoryDays.Day.OTHER -> dateFormat.format(date)
                }
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.Button, onClick = onAll).padding(horizontal = Spacing.INSIDE.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.GAP.dp), verticalAlignment = Alignment.CenterVertically,
                ) {
                    StateDot(if (d.allowed) IslandColors.added else t.danger.c())
                    Text(HomeText.recent(d.allowed, d.tool), Modifier.weight(1f), style = TypeScale.SECONDARY.style(t.text.c()), maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text(whenText, style = islandText(11.sp, IslandColors.tertiary), maxLines = 1)
                }
            }
        }
    }
}
