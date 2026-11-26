package com.cauarati.notchy

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.foundation.lazy.rememberLazyListState
import kotlinx.coroutines.launch
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.runtime.SideEffect
import androidx.core.view.WindowCompat
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cauarati.notchy.app.AppModel
import com.cauarati.notchy.app.BiometricGate
import com.cauarati.notchy.app.NotchyApp
import com.cauarati.notchy.app.Mode
import com.cauarati.notchy.app.Notifications
import com.cauarati.notchy.core.ApprovalSheetPlan
import com.cauarati.notchy.core.HomeText
import com.cauarati.notchy.core.Nav
import com.cauarati.notchy.core.Pills
import com.cauarati.notchy.core.Screen
import com.cauarati.notchy.core.SecureScreens
import com.cauarati.notchy.link.ApprovalRequest
import com.cauarati.notchy.link.QuestionRequest
import com.cauarati.notchy.link.LinkState
import com.cauarati.notchy.link.PairingPayload
import com.cauarati.notchy.mochi.BotEmote
import com.cauarati.notchy.mochi.BotState
import com.cauarati.notchy.mochi.MochiEngine
import com.cauarati.notchy.mochi.MochiView
import com.cauarati.notchy.ui.Panel
import com.cauarati.notchy.ui.c
import com.cauarati.notchy.ui.style
import com.cauarati.notchy.ui.tokens
import com.cauarati.notchy.core.TypeScale
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.heightIn
import androidx.compose.ui.semantics.Role
import com.cauarati.notchy.ui.NotchyTheme
import com.cauarati.notchy.core.HomePanel
import com.cauarati.notchy.link.DiscoveryState
import com.cauarati.notchy.ui.AddressSheet
import com.cauarati.notchy.ui.BatteryCard
import com.cauarati.notchy.ui.DiagnosticsScreen
import com.cauarati.notchy.ui.LicencesScreen
import com.cauarati.notchy.ui.LinkHealthPanel
import com.cauarati.notchy.ui.DiscoveryHint
import com.cauarati.notchy.ui.ApprovalSheet
import com.cauarati.notchy.ui.MessagePanel
import com.cauarati.notchy.ui.PairingScreen
import com.cauarati.notchy.ui.DiffSheet
import com.cauarati.notchy.ui.QuestionSheet
import com.cauarati.notchy.ui.LaunchRow
import com.cauarati.notchy.ui.LaunchSheet
import com.cauarati.notchy.ui.ServicesPanel
import com.cauarati.notchy.ui.UsagePanel
import com.cauarati.notchy.ui.RecapPanel
import com.cauarati.notchy.ui.WardrobeScreen
import com.cauarati.notchy.ui.HomeScreen
import com.cauarati.notchy.ui.IslandColors
import com.cauarati.notchy.ui.PairConfirm
import com.cauarati.notchy.ui.ScanScreen
import com.cauarati.notchy.ui.SessionScreen
import com.cauarati.notchy.ui.ChatScreen
import com.cauarati.notchy.ui.MochiTouch
import com.cauarati.notchy.ui.HistoryScreen
import com.cauarati.notchy.ui.SettingsScreen
import com.cauarati.notchy.ui.StatusColors
import com.cauarati.notchy.ui.Gap
import com.cauarati.notchy.ui.Gutter
import com.cauarati.notchy.ui.ScreenTitle
import com.cauarati.notchy.ui.SectionTitle
import com.cauarati.notchy.ui.linkDotColor
import com.cauarati.notchy.ui.linkStatusText

class MainActivity : ComponentActivity() {
    private val model get() = (application as NotchyApp).model
    private var screen by mutableStateOf(Screen.HOME)
    /** The session whose details are open. */
    private var detailPill by mutableStateOf<String?>(null)
    /** The approval and the question the user closed without deciding, off Home (the sheet stays down for them; Home's island still shows them). */
    private var closedApproval by mutableStateOf<String?>(null)
    private var closedQuestion by mutableStateOf<String?>(null)
    /** The "New Claude Code session" sheet is open. */
    private var launchOpen by mutableStateOf(false)
    private var confirming = false
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(com.cauarati.notchy.app.AppLanguage.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        model.languageChanged(com.cauarati.notchy.app.AppLanguage.current(this))
        enableEdgeToEdge()
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        model.resume()
        setContent {
            NotchyTheme(model.settings.theme, model.settings.dynamicColour) {
                // Dark icons on a light page; the camera screen and the island's screens are black in both themes, so their icons are light.
                val lightPage = !tokens().isDark && !Nav.isIsland(screen) && screen != Screen.SCAN && screen != Screen.HOME
                SideEffect {
                    val bars = WindowCompat.getInsetsController(window, window.decorView)
                    bars.isAppearanceLightStatusBars = lightPage
                    bars.isAppearanceLightNavigationBars = lightPage
                }
                // The island's screens sit on its near-black page, down to the bottom edge (under the gesture bar too).
                val islandPage = Nav.isIsland(screen) || screen == Screen.HOME
                val page = when {
                    screen == Screen.SESSION -> IslandColors.card // the session is black to the edges, like the iPhone's sheet
                    islandPage -> IslandColors.page
                    else -> MaterialTheme.colorScheme.background
                }
                Surface(Modifier.fillMaxSize(), color = page) {
                    // The island's screens hang from the top edge (the status bar is inside the island); the others keep clear of it.
                    val edgeToEdge = Nav.isIsland(screen) || screen == Screen.SCAN || screen == Screen.HOME
                    Box(Modifier.fillMaxSize().windowInsetsPadding(if (edgeToEdge) WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom) else WindowInsets.safeDrawing)) {
                        BackHandler(enabled = Nav.back(screen) != null) { Nav.back(screen)?.let { screen = it } }
                        when (screen) {
                            Screen.SCAN -> ScanScreen(
                                onBack = { screen = Screen.HOME },
                                // True if it was a pairing code: the camera is released and the user is asked to confirm.
                                onText = { text -> model.requestPairing(text).also { if (it) screen = Screen.HOME } },
                            )
                            Screen.CHAT -> ChatScreen(
                                model, onTab = { screen = Nav.screenOf(it) }, onHome = { screen = Screen.HOME }, onSettings = { screen = Screen.SETTINGS },
                            )
                            Screen.SESSION -> SessionScreen(model, detailPill.orEmpty(), onBack = { screen = Screen.HOME })
                            Screen.GALLERY -> Gallery(onBack = { screen = Screen.SETTINGS })
                            Screen.SETTINGS -> SettingsScreen(
                                model, onBack = { screen = Screen.HOME }, onHistory = { screen = Screen.HISTORY },
                                onGallery = { screen = Screen.GALLERY }, onWardrobe = { screen = Screen.WARDROBE }, onOverlay = ::setOverlay,
                                onDiagnostics = { screen = Screen.DIAGNOSTICS }, onLicences = { screen = Screen.LICENCES },
                            )
                            Screen.LICENCES -> LicencesScreen(onBack = { screen = Screen.SETTINGS })
                            Screen.WARDROBE -> WardrobeScreen(model, onBack = { screen = Screen.SETTINGS })
                            Screen.DIAGNOSTICS -> DiagnosticsScreen(model, onBack = { screen = Screen.SETTINGS })
                            Screen.HISTORY -> HistoryScreen(model, onBack = { screen = Screen.SETTINGS })
                            Screen.HOME -> if (model.mode == Mode.NONE) PairingScreen(model, onScan = { screen = Screen.SCAN }, onAbout = { screen = Screen.SETTINGS }) else HomeScreen(
                                model, onApprove = ::approve, onAnswer = ::sendAnswer,
                                onSession = { detailPill = it; screen = Screen.SESSION },
                                onTab = { screen = Nav.screenOf(it) }, onSettings = { screen = Screen.SETTINGS },
                                onScan = { screen = Screen.SCAN }, onHistory = { screen = Screen.HISTORY }, onDiagnostics = { screen = Screen.DIAGNOSTICS },
                                onLaunch = { model.launchReset(); launchOpen = true }, onOverlay = ::setOverlay,
                                overlayHint = { OverlayHint(::setOverlay) },
                            )
                        }
                        // A request for permission rises over whatever is on screen until it is decided or closed.
                        // On Home the island itself holds the request (and the question); anywhere else the same card rises in a sheet.
                        val onHome = screen == Screen.HOME && model.mode != Mode.NONE
                        val pending = ApprovalSheetPlan.next(model.approvals, closedApproval)
                        if (pending != null && screen != Screen.SCAN && !onHome) ApprovalSheet(model, pending, onAllow = ::approve, onDismiss = { closedApproval = pending.fingerprint })
                        if (screen != Screen.HOME) model.questions.firstOrNull()?.takeIf { it.fingerprint != closedQuestion }?.let { q ->
                            QuestionSheet(model, q.pillId, onDismiss = { closedQuestion = q.fingerprint }, onSend = ::sendAnswer)
                        }
                        DiffSheet(model)
                        if (launchOpen && screen == Screen.HOME && model.mode == Mode.PAIRED) {
                            LaunchSheet(model, onDismiss = { launchOpen = false; model.launchReset() }, onSend = ::sendLaunch)
                        }
                        // Pairing, chat, an approval and a question never show in screenshots or in the recent-apps card.
                        val secure = SecureScreens.needed(
                            screen, pairing = model.mode == Mode.NONE, approvalSheetShown = (pending != null || model.approvals.isNotEmpty() && onHome) && screen != Screen.SCAN,
                            questionSheetShown = model.questions.isNotEmpty(), pairConfirmShown = model.pairRequest != null,
                            launchSheetShown = launchOpen && screen == Screen.HOME && model.mode == Mode.PAIRED,
                        )
                        SideEffect {
                            // A debuggable build may be told to let screenshots through, for checking these screens in an
                            // emulator: `adb shell settings put global notchy_debug_capture 1`. A release build is never
                            // debuggable (isDebuggable = false), so it always hides them.
                            val capture = (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0 &&
                                android.provider.Settings.Global.getInt(contentResolver, "notchy_debug_capture", 0) == 1
                            if (secure && !capture) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE) else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            window.decorView.filterTouchesWhenObscured = secure
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) window.setHideOverlayWindows(secure)
                        }
                        // A scanned code or a link from the camera app: the user decides before anything is paired.
                        model.pairRequest?.let { PairConfirm(model, it) }
                    }
                }
            }
        }
        handle(intent)
    }

    override fun onStart() {
        super.onStart()
        model.inForeground = true
        model.refreshOverlayPermission() // maybe granted meanwhile, from this app's switch or Android's settings
        model.refreshBattery() // the battery setting may have been changed in Android's screen
    }

    override fun onStop() {
        model.inForeground = false
        super.onStop()
    }

    /**
     * The pill over other apps needs a one-time system permission. The choice is saved first: even if
     * Android recreates the app while the user is in Settings, it is remembered, and the pill works as
     * soon as the permission is there.
     */
    private fun setOverlay(on: Boolean) {
        model.useOverlay(on)
        if (on && !model.overlayPermitted()) {
            model.message = getString(R.string.msg_overlay_permission)
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    /** A notchy://pair link (from the camera app or a browser) or a tap on an approval notification. */
    private fun handle(i: Intent?) {
        i ?: return
        Log.d("NotchyLaunch", "MainActivity intent: action=${i.action} data=${i.data != null}")
        i.data?.let { uri ->
            if (uri.scheme == "notchy") {
                // Opened from the camera app or a browser: never paired without the user's OK.
                if (!model.requestPairing(uri.toString())) model.message = getString(R.string.msg_bad_link)
                i.data = null // handled once: a rotation must not ask again
            }
        }
        // Never read from the intent: this activity is exported, any app could send these extras. The requests come
        // from LaunchActivity (ours, not exported) through the model, once.
        model.launch.takeSession()?.let { pill ->
            // A tap on a widget row. The session screen says so itself if it has ended, and fills in when the link is back.
            if (model.isPaired || model.mode != Mode.NONE) { detailPill = pill; screen = Screen.SESSION }
        }
        // A tap on a widget button: a screen of the closed list ([LaunchScreen]), even when the app is locked, not connected or not paired.
        model.launch.takeScreen()?.let { screen = it.screen }
        // Text shared to Notchy from another app (ShareActivity, which only keeps cleaned text): it waits in the model for the chat box.
        if (model.shareDraft.pending()) screen = Screen.CHAT
        val launch = model.launch.take() ?: return
        val fp = launch.fingerprint
        if (launch.allow) {
            val request = model.approvals.firstOrNull { it.fingerprint == fp }
            when {
                request != null -> approve(request)
                // The app was closed: the desktop offers the request again once the link is back.
                model.linkState != LinkState.CONNECTED -> model.wantAllow = fp
                else -> model.message = getString(R.string.msg_not_pending)
            }
        }
    }

    /**
     * An answer to a question: only after the same screen-lock check as Allow. The lock prompt shows what is about to be
     * sent (the labels picked); nothing about it is logged or stored.
     */
    private fun sendAnswer(request: QuestionRequest, picks: List<List<String>>) {
        if (confirming) return
        confirming = true
        BiometricGate.confirm(
            this, getString(R.string.question_confirm_title), picks.joinToString("; ") { it.joinToString(", ") }, getString(R.string.msg_need_lock),
            onSuccess = {
                confirming = false
                model.message = getString(if (model.answerQuestion(request.fingerprint, picks)) R.string.question_sent else R.string.question_not_sent)
            },
            onFail = { confirming = false; if (it.isNotBlank()) model.message = it },
        )
    }

    /**
     * A new Claude Code session on the computer: only after the same screen-lock check as Allow. The lock prompt shows the project and
     * the start of the words; nothing about them is logged or stored.
     */
    private fun sendLaunch(project: com.cauarati.notchy.link.LaunchProject, prompt: String) {
        if (confirming) return
        confirming = true
        BiometricGate.confirm(
            this, getString(R.string.launch_confirm_title), com.cauarati.notchy.core.LaunchFlow.summary(project, prompt), getString(R.string.msg_need_lock),
            onSuccess = { confirming = false; model.launchSend(project.id, prompt) },
            onFail = { confirming = false; if (it.isNotBlank()) model.message = it },
        )
    }

    /** Allow: only after the biometric / screen-lock check. */
    private fun approve(r: ApprovalRequest) {
        if (confirming) return // a second tap must not open a second prompt
        if (!ApprovalSheetPlan.canAllowHere(r)) { model.message = getString(R.string.approval_on_computer); return }
        confirming = true
        BiometricGate.confirm(
            this, getString(R.string.action_allow), "${r.tool}: ${r.command}", getString(R.string.msg_need_lock),
            onSuccess = { confirming = false; model.decide(r.fingerprint, allow = true) },
            onFail = { confirming = false; if (it.isNotBlank()) model.message = it },
        )
    }
}

@Composable
private fun OverlayHint(onOverlay: (Boolean) -> Unit) {
    Panel {
        Row(Modifier.padding(start = Gutter), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.overlay_missing), Modifier.weight(1f).padding(vertical = 12.dp), style = TypeScale.SECONDARY.style(tokens().textDim.c()))
            Text(
                stringResource(R.string.overlay_allow),
                Modifier.heightIn(min = 48.dp).clickable(role = Role.Button) { onOverlay(true) }.padding(horizontal = 16.dp, vertical = 14.dp),
                style = TypeScale.LABEL.style(tokens().text.c()), maxLines = 1,
            )
        }
    }
}

/** Every state and emote, drawn live. Handy to check the port by eye. */
@Composable
private fun Gallery(onBack: () -> Unit) {
    val clock = remember { { SystemClock.elapsedRealtimeNanos() / 1e6 } }
    val states = remember { BotState.entries.map { s -> s to MochiEngine(clock).apply { setState(s, force = true) } } }
    val emotes = remember { BotEmote.entries.map { e -> e to MochiEngine(clock).apply { setPermanentEmote(e) } } }
    Column(Modifier.padding(horizontal = Gutter)) {
        ScreenTitle(stringResource(R.string.gallery), onBack)
        Spacer(Modifier.height(Gap))
        LazyVerticalGrid(GridCells.Fixed(3), horizontalArrangement = Arrangement.spacedBy(Gap), verticalArrangement = Arrangement.spacedBy(Gap)) {
            gridItems(states) { (s, e) -> GalleryCell(s.key, e) }
            gridItems(emotes) { (m, e) -> GalleryCell(m.key, e) }
        }
    }
}

@Composable
private fun GalleryCell(label: String, engine: MochiEngine) {
    Box(Modifier.fillMaxWidth()) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            MochiView(engine, Modifier.fillMaxWidth().aspectRatio(1f))
            Text(label, style = MaterialTheme.typography.labelSmall)
        }
    }
}
