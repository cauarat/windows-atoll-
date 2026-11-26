package com.cauarati.notchy

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.runtime.SideEffect
import androidx.core.view.WindowCompat
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.cauarati.notchy.app.AppModel
import com.cauarati.notchy.app.NotchyApp
import com.cauarati.notchy.app.Mode
import com.cauarati.notchy.core.Nav
import com.cauarati.notchy.core.Screen
import com.cauarati.notchy.core.SecureScreens
import com.cauarati.notchy.link.LinkState
import com.cauarati.notchy.mochi.BotEmote
import com.cauarati.notchy.mochi.BotState
import com.cauarati.notchy.mochi.MochiEngine
import com.cauarati.notchy.mochi.MochiView
import com.cauarati.notchy.ui.tokens
import com.cauarati.notchy.ui.NotchyTheme
import com.cauarati.notchy.link.DiscoveryState
import com.cauarati.notchy.ui.AddressSheet
import com.cauarati.notchy.ui.DiagnosticsScreen
import com.cauarati.notchy.ui.LicencesScreen
import com.cauarati.notchy.ui.LinkHealthPanel
import com.cauarati.notchy.ui.DiscoveryHint
import com.cauarati.notchy.ui.MessagePanel
import com.cauarati.notchy.ui.PairingScreen
import com.cauarati.notchy.ui.WardrobeScreen
import com.cauarati.notchy.ui.HeroCard
import com.cauarati.notchy.ui.BarClearance
import com.cauarati.notchy.ui.BottomBar
import com.cauarati.notchy.ui.PairConfirm
import com.cauarati.notchy.ui.ScanScreen
import com.cauarati.notchy.ui.ChatScreen
import com.cauarati.notchy.ui.MochiTouch
import com.cauarati.notchy.ui.SettingsScreen
import com.cauarati.notchy.ui.Gap
import com.cauarati.notchy.ui.Gutter
import com.cauarati.notchy.ui.ScreenTitle
import com.cauarati.notchy.ui.linkDotColor
import com.cauarati.notchy.ui.linkStatusText

class MainActivity : ComponentActivity() {
    private val model get() = (application as NotchyApp).model
    private var screen by mutableStateOf(Screen.HOME)
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(com.cauarati.notchy.app.AppLanguage.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        model.resume()
        setContent {
            NotchyTheme(model.settings.theme, model.settings.dynamicColour) {
                // Dark icons on a light page; the camera screen is black in both themes, so its icons are light.
                val lightPage = !tokens().isDark && screen != Screen.SCAN
                SideEffect {
                    val bars = WindowCompat.getInsetsController(window, window.decorView)
                    bars.isAppearanceLightStatusBars = lightPage
                    bars.isAppearanceLightNavigationBars = lightPage
                }
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    Box(Modifier.fillMaxSize().windowInsetsPadding(if (screen == Screen.HOME || screen == Screen.SCAN) WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom) else WindowInsets.safeDrawing)) {
                        val tabs = Nav.tabs()
                        val keyboardOpen = WindowInsets.ime.getBottom(LocalDensity.current) > 0
                        val barVisible = Nav.barVisible(screen, keyboardOpen)
                        BackHandler(enabled = Nav.back(screen) != null) { Nav.back(screen)?.let { screen = it } }
                        // Chat keeps its message box above the bar; Home and Settings scroll under it (their own bottom padding).
                        Box(Modifier.fillMaxSize().padding(bottom = if (barVisible && screen == Screen.CHAT) BarClearance else 0.dp)) {
                        when (screen) {
                            Screen.SCAN -> ScanScreen(
                                onBack = { screen = Screen.HOME },
                                // True if it was a pairing code: the camera is released and the user is asked to confirm.
                                onText = { text -> model.requestPairing(text).also { if (it) screen = Screen.HOME } },
                            )
                            Screen.CHAT -> ChatScreen(model, onHome = { screen = Screen.HOME }, onSettings = { screen = Screen.SETTINGS })
                            Screen.GALLERY -> Gallery(onBack = { screen = Screen.SETTINGS })
                            Screen.SETTINGS -> SettingsScreen(
                                model, onGallery = { screen = Screen.GALLERY }, onWardrobe = { screen = Screen.WARDROBE },
                                onDiagnostics = { screen = Screen.DIAGNOSTICS }, onLicences = { screen = Screen.LICENCES },
                            )
                            Screen.LICENCES -> LicencesScreen(onBack = { screen = Screen.SETTINGS })
                            Screen.WARDROBE -> WardrobeScreen(model, onBack = { screen = Screen.SETTINGS })
                            Screen.DIAGNOSTICS -> DiagnosticsScreen(model, onBack = { screen = Screen.SETTINGS })
                            Screen.HOME -> if (model.mode == Mode.NONE) PairingScreen(model, onScan = { screen = Screen.SCAN }, onAbout = { screen = Screen.SETTINGS }) else Home(
                                model, onScan = { screen = Screen.SCAN }, onDiagnostics = { screen = Screen.DIAGNOSTICS },
                            )
                        }
                        }
                        if (barVisible) {
                            BottomBar(
                                tabs, Nav.tabOf(screen), onSelect = { screen = Nav.screenOf(it) },
                                modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 16.dp),
                            )
                        }
                        // Pairing and chat never show in screenshots or in the recent-apps card.
                        val secure = SecureScreens.needed(screen, pairing = model.mode == Mode.NONE, pairConfirmShown = model.pairRequest != null)
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    /** A notchy://pair link (from the camera app or a browser), a shortcut, or text shared to Notchy. */
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
        // Never read from the intent: this activity is exported, any app could send extras. A shortcut's screen comes from
        // LaunchActivity (ours, not exported) through the model, once: a screen of the closed list ([LaunchScreen]).
        model.launch.takeScreen()?.let { screen = it.screen }
        // Text shared to Notchy from another app (ShareActivity, which only keeps cleaned text): it waits in the model for the chat box.
        if (model.shareDraft.pending()) screen = Screen.CHAT
    }
}

@Composable
private fun Home(model: AppModel, onScan: () -> Unit, onDiagnostics: () -> Unit) {
    val clock = remember { { SystemClock.elapsedRealtimeNanos() / 1e6 } }
    val engine = remember { MochiEngine(clock, sound = model.sounds) }
    val touch = remember { MochiTouch(engine, model.sounds) { homeState(model) } }
    var addressOpen by rememberSaveable { mutableStateOf(false) }

    // Mochi is awake while the computer is there, asleep while it is not.
    val state = homeState(model)
    if (engine.state != state && !touch.dizzy) engine.setState(state)

    // Mochi wears what the user picked (a new engine starts dressed, a change animates).
    val dressed = remember { HashSet<MochiEngine>() }
    model.dress().let { outfit -> if (dressed.add(engine)) engine.setOutfit(outfit, animated = false) else engine.setOutfit(outfit) }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = BarClearance),
        verticalArrangement = Arrangement.spacedBy(Gap),
    ) {
        item {
            HeroCard(
                engine, touch.modifier, connected = model.linkState == LinkState.CONNECTED, desktopName = model.desktopName.orEmpty(),
                linkDot = linkDotColor(model), linkText = linkStatusText(model),
            )
        }
        // The link had worked and ended: what happened and how long ago, instead of a silent state.
        if (model.mode == Mode.PAIRED && model.linkState != LinkState.CONNECTED) {
            item { Box(Modifier.padding(horizontal = Gutter)) { LinkHealthPanel(model, onDiagnostics) } }
        }
        // The saved address failed and a search found nothing: a calm hint with two ways out.
        if (model.mode == Mode.PAIRED && model.linkState != LinkState.CONNECTED && model.discovery == DiscoveryState.NOT_FOUND) {
            item { Box(Modifier.padding(horizontal = Gutter)) { DiscoveryHint(onPairAgain = onScan, onEnterAddress = { addressOpen = true }) } }
        }
        model.message?.let { msg ->
            item { Box(Modifier.padding(horizontal = Gutter)) { MessagePanel(msg) { model.message = null } } }
        }
        item { Spacer(Modifier.height(Gutter)) }
    }
    // After the list, so it draws over it.
    if (addressOpen) AddressSheet(model) { addressOpen = false }
}

/** Idle while the computer is connected, sleeping while it is not. */
private fun homeState(model: AppModel): BotState =
    if (model.mode == Mode.PAIRED && model.linkState == LinkState.CONNECTED) BotState.IDLE else BotState.SLEEPING

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
