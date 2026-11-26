package com.cauarati.notchy.app

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.cauarati.notchy.R
import com.cauarati.notchy.core.ChatTab
import com.cauarati.notchy.core.ChatTabState
import com.cauarati.notchy.core.KeyValueStore
import com.cauarati.notchy.core.UserSettings
import com.cauarati.notchy.link.Protocol
import com.cauarati.notchy.link.ChatModel
import com.cauarati.notchy.core.PairingScan
import com.cauarati.notchy.core.ScanDecision
import com.cauarati.notchy.core.ChatHistory
import com.cauarati.notchy.core.ChatModels
import com.cauarati.notchy.core.ChatSession
import com.cauarati.notchy.link.AddressFinder
import com.cauarati.notchy.link.Cancelable
import com.cauarati.notchy.link.Discovery
import com.cauarati.notchy.link.DiscoveryPolicy
import com.cauarati.notchy.link.DiscoveryState
import com.cauarati.notchy.link.PinnedProbe
import com.cauarati.notchy.link.DesktopLink
import com.cauarati.notchy.link.PinnedTls
import com.cauarati.notchy.link.LinkClient
import com.cauarati.notchy.link.LinkListener
import com.cauarati.notchy.link.LinkState
import com.cauarati.notchy.link.DiagResult
import com.cauarati.notchy.link.DiagStep
import com.cauarati.notchy.link.Diagnostics
import com.cauarati.notchy.link.Found
import com.cauarati.notchy.link.LanDiagnostics
import com.cauarati.notchy.link.LinkHealth
import com.cauarati.notchy.link.LostReason
import com.cauarati.notchy.link.PairingPayload
import com.cauarati.notchy.link.ReconnectPolicy
import com.cauarati.notchy.link.Wake
import com.cauarati.notchy.sound.SoundPlayer

enum class Mode { NONE, PAIRED }

/** The one place the UI and the share target share. Created by [NotchyApp]. */
class AppModel(private val context: Context) : LinkListener {
    private val main = Handler(Looper.getMainLooper())
    private val store = SecureStore(context)
    val sounds = SoundPlayer(context)

    /** Set only by LaunchActivity (not exported), read by MainActivity: see [com.cauarati.notchy.core.PendingLaunch]. */
    val launch = com.cauarati.notchy.core.PendingLaunch()

    /** Text shared to Notchy from another app, waiting to be put in the chat box (see [com.cauarati.notchy.core.ShareDraft]). */
    val shareDraft = com.cauarati.notchy.core.ShareDraft()

    /** Changes with every share, so a chat screen that is already open notices there is a new draft. */
    var shareVersion by mutableStateOf(0); private set

    /** Keeps [text] (cleaned) as the draft for the chat box. Called by the share target only. */
    fun offerShare(text: String?) {
        shareDraft.offer(text)
        shareVersion++
    }

    var mode by mutableStateOf(Mode.NONE); private set
    var linkState by mutableStateOf(LinkState.DISCONNECTED); private set
    var desktopName by mutableStateOf<String?>(null); private set
    var message by mutableStateOf<String?>(null)

    // ── Finding the computer again when its address changed (docs/PHONE_LINK.md, "Finding the computer again") ──
    /** What the search for the computer is doing, for the status line and the hint. */
    var discovery by mutableStateOf(DiscoveryState.IDLE); private set
    /** The pairing the running link uses (with the address in force); the token stays in memory only as long as the link does. */
    @Volatile private var currentPairing: PairingPayload? = null
    private val probeExecutor = java.util.concurrent.Executors.newSingleThreadExecutor { r -> Thread(r, "notchy-probe").apply { isDaemon = true } }

    private val netWatch = NetworkWatch(context, { up -> main.post { onNetworkChanged(up) } }, { main.post { onWake(Wake.NEW_NETWORK) } })
    private val finder = AddressFinder(
        source = NsdDiscovery(context), probe = PinnedProbe,
        pairing = { currentPairing }, allowed = { mayDiscover() },
        onAddress = { host, port -> main.post { onAddressFound(host, port) } },
        onState = { st -> main.post { discovery = st } },
        scheduler = { delay, task -> val r = Runnable { task() }; main.postDelayed(r, delay); Cancelable { main.removeCallbacks(r) } },
        runner = { task -> probeExecutor.execute { task() } },
    )

    private fun mayDiscover() = DiscoveryPolicy.mayDiscover(
        paired = currentPairing != null, wifiUp = netWatch.wifiUp, linkConnected = linkState == LinkState.CONNECTED,
    )

    private val prefs = context.getSharedPreferences("notchy_ui", Context.MODE_PRIVATE)
    private val kv = object : KeyValueStore {
        override fun getBoolean(key: String, default: Boolean) = prefs.getBoolean(key, default)
        override fun getInt(key: String, default: Int) = prefs.getInt(key, default)
        override fun getFloat(key: String, default: Float) = prefs.getFloat(key, default)
        override fun getString(key: String, default: String) = prefs.getString(key, default) ?: default
        override fun put(key: String, value: Any) {
            prefs.edit().apply {
                when (value) {
                    is Boolean -> putBoolean(key, value)
                    is Int -> putInt(key, value)
                    is Float -> putFloat(key, value)
                    is String -> putString(key, value)
                }
            }.apply()
        }
    }

    /** What the user chose in Settings (sound, look, motion). */
    var settings by mutableStateOf(UserSettings.load(kv)); private set

    fun updateSettings(next: UserSettings) {
        settings = next
        UserSettings.save(kv, next)
        applySound()
        com.cauarati.notchy.core.MotionState.choice = settings.motion
    }

    private fun applySound() {
        sounds.enabled = settings.soundOn
        sounds.volume = settings.volume
    }

    init {
        applySound()
        com.cauarati.notchy.core.MotionState.choice = settings.motion
    }

    /** What Mochi wears today: the phone's choice, with "auto" resolved with the phone's calendar. */
    fun dress(today: java.time.LocalDate = java.time.LocalDate.now()): com.cauarati.notchy.mochi.outfit.Outfit =
        com.cauarati.notchy.mochi.outfit.Wardrobe.resolve(settings.outfit, today)

    // ── Chat through the computer (docs/PHONE_LINK.md, "Chat") ──────────

    private val chatHistory = ChatHistory(ChatFile(java.io.File(context.filesDir, "chat-history.json")))
    private val chatSession = ChatSession(chatHistory.load())

    /** What the user reads: this phone's own copy, kept in a private file. */
    var chatMessages by mutableStateOf(chatSession.messages); private set

    /** An answer is being waited for. */
    var chatBusy by mutableStateOf(false); private set

    /** The computer offers chat to this phone right now (its switch is on and we are connected). */
    var chatOffered by mutableStateOf(false); private set

    /** The models the user allowed on the computer; the keys never leave it. */
    var chatModels by mutableStateOf<List<ChatModel>>(emptyList()); private set

    var chatModel by mutableStateOf<String?>(prefs.getString("chat_model", null)); private set

    /** What the Chat tab shows: not paired, not reachable, chat off on the computer, no model allowed, or ready. */
    val chatTabState: ChatTabState get() = ChatTab.state(
        paired = mode == Mode.PAIRED, connected = linkState == LinkState.CONNECTED, offered = chatOffered, modelCount = chatModels.size,
    )

    /** Chat is usable: offered, at least one model allowed, connected. */
    val chatAvailable: Boolean get() = chatOffered && chatModels.isNotEmpty() && linkState == LinkState.CONNECTED

    private fun chatChanged(save: Boolean) {
        chatMessages = chatSession.messages
        chatBusy = chatSession.running != null
        if (save) chatHistory.save(chatSession.messages)
    }

    fun chatSelect(id: String) {
        if (chatModels.any { it.id == id }) {
            chatModel = id
            prefs.edit().putString("chat_model", id).apply()
        }
    }

    /** Asks the computer again which models are allowed (when the Chat screen opens). */
    fun chatRefreshModels() { link?.chatModels() }

    /** Null when sent, else why not (for a message under the box). */
    fun chatSend(text: String): ChatSession.Refusal? {
        val sent = chatSession.send(text, chatModel, connected = chatAvailable)
        return when (sent) {
            is ChatSession.Sent.No -> sent.why
            is ChatSession.Sent.Ok -> {
                chatChanged(save = true)
                if (link?.chatSend(sent.msg.id, sent.msg.model, sent.msg.text) != true) {
                    chatSession.onDisconnected()
                    chatChanged(save = true)
                }
                null
            }
        }
    }

    fun chatCancel() {
        chatSession.cancel()?.let { link?.chatCancel(it) }
        chatChanged(save = true)
    }

    /** Clear: forgets the history here and on the computer. */
    fun chatClear() {
        chatSession.cancel()?.let { link?.chatCancel(it) }
        chatSession.clear()
        chatHistory.clear()
        link?.chatReset()
        chatChanged(save = false)
    }

    private fun chatLinkLost() {
        chatOffered = false
        chatModels = emptyList()
        if (chatSession.running != null) {
            chatSession.onDisconnected()
            chatChanged(save = true)
        }
    }

    private var link: DesktopLink? = null

    val isPaired get() = store.loadPairing() != null

    /** Called at launch: reconnects to the stored desktop, if any. */
    fun resume() {
        if (link != null) return
        val p = store.loadPairing() ?: return
        connect(p)
    }

    /**
     * A pairing link waiting for the user's OK: read from the QR code, or opened from the camera app. Held in
     * memory only while the question is on screen; it is never logged and goes nowhere but into [pair].
     */
    var pairRequest by mutableStateOf<String?>(null); private set

    /** True if [text] is a Notchy pairing link (the user is now asked to confirm); false for any other text. */
    fun requestPairing(text: String?): Boolean {
        val d = PairingScan.decide(text)
        if (d !is ScanDecision.Pairing) return false
        pairRequest = d.link
        return true
    }

    @Volatile private var verifyGeneration = 0

    fun confirmPairing() {
        val link = pairRequest ?: return
        pairRequest = null
        pair(link)
    }

    fun cancelPairing() { pairRequest = null }

    fun pair(text: String): Boolean {
        val p = PairingPayload.parse(text)
        if (p == null) { message = context.getString(R.string.msg_bad_link); return false }
        if (!isPaired) {
            stopLink()
            store.savePairing(p)
            connect(p)
            return true
        }
        val gen = ++verifyGeneration
        val modelName = Build.MODEL ?: "Android"
        probeExecutor.execute {
            val result = com.cauarati.notchy.link.PairingVerifier.verify(p, deviceName = modelName)
            main.post {
                if (gen != verifyGeneration) return@post
                if (result is com.cauarati.notchy.link.PairingVerifier.Result.Verified) {
                    stopLink()
                    store.savePairing(p)
                    connect(p)
                } else {
                    message = context.getString(R.string.msg_pair_verify_failed)
                }
            }
        }
        return true
    }

    private fun connect(p: PairingPayload) {
        mode = Mode.PAIRED
        desktopName = p.desktopName.ifBlank { p.host }
        currentPairing = p
        link = newLink(p).also { it.start() }
        netWatch.start()
        screenWatch.start()
    }

    /** The saved address is replaced; the token and the pinned certificate are the same. The link restarts at once. */
    private fun useAddress(host: String, port: Int) {
        val p = currentPairing ?: return
        val q = Discovery.withAddress(p, host, port)
        store.savePairing(q)
        currentPairing = q
        restartLink(q)
    }

    /** A link for this pairing: the direct connection on the local network (Notchy has no relay). */
    private fun newLink(p: PairingPayload): LinkClient =
        LinkClient(p, Build.MODEL ?: "Android", this, connector = PinnedTls.connector(p))

    private fun restartLink(p: PairingPayload) {
        link?.stop()
        link = newLink(p).also { it.start() }
    }

    /** A computer matching the paired fingerprint answered with the pinned certificate (checked by a bare TLS handshake). */
    private fun onAddressFound(host: String, port: Int) {
        if (mode != Mode.PAIRED || currentPairing == null) return
        Log.d("NotchyDiscovery", "address updated")
        useAddress(host, port)
    }

    // ── What happened to the link, and looking at it again when the screen turns on or the network changes ──

    /** Whether the phone is on Wi-Fi now, for the sentence that names why the link was lost. */
    val wifiUp: Boolean get() = netWatch.wifiUp

    /** When the link was lost and why, so Home can say what happened. */
    var health by mutableStateOf(LinkHealth()); private set
    private val screenWatch = ScreenWatch(context) { main.post { onWake(Wake.SCREEN_ON) } }

    /** The screen turned on or a network appeared: look at the link now (rules in [ReconnectPolicy]). */
    private fun onWake(event: Wake) {
        when (ReconnectPolicy.decide(event, mode == Mode.PAIRED, linkState == LinkState.CONNECTED, netWatch.wifiUp)) {
            ReconnectPolicy.Action.RETRY_NOW -> link?.retryNow()
            ReconnectPolicy.Action.CHECK_NOW -> link?.checkNow()
            ReconnectPolicy.Action.NONE -> {}
        }
    }

    // ── "Can't connect?" ──
    var diagResults by mutableStateOf<List<Pair<DiagStep, DiagResult>>>(emptyList()); private set
    var diagRunning by mutableStateOf(false); private set

    fun runDiagnostics() {
        val p = currentPairing ?: return
        if (diagRunning) return
        diagRunning = true
        diagResults = emptyList()
        probeExecutor.execute {
            val env = LanDiagnostics(
                p, wifiUp = { netWatch.isWifiUp() }, discover = { browse(4_000) },
            )
            Diagnostics.run(env) { step, result -> main.post { diagResults = diagResults + (step to result) } }
            main.post { diagRunning = false }
        }
    }

    /** Listens for the computer's announcement for [ms] on a separate browser, so the link's own search is not disturbed. */
    private fun browse(ms: Long): List<Found> {
        val seen = java.util.concurrent.CopyOnWriteArrayList<Found>()
        val source = NsdDiscovery(context)
        source.start { seen.add(it) }
        try { Thread.sleep(ms) } finally { source.stop() }
        return seen.toList()
    }

    /** The text the user can copy: the checks and what they found, with no code, fingerprint, name or full address. */
    fun diagnosticsReport(): String {
        val p = currentPairing
        val version = runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() ?: "?"
        val via = if (linkState != LinkState.CONNECTED) "not connected" else "the direct link"
        return Diagnostics.report(version, Build.VERSION.RELEASE, "${Build.MANUFACTURER} ${Build.MODEL}", diagResults, p?.let { Diagnostics.maskHost(it.host) } ?: "none", via)
    }

    private fun onNetworkChanged(wifiUp: Boolean) {
        if (mode != Mode.PAIRED) return
        if (!wifiUp) { finder.stop(); return } // no Wi-Fi: nothing to scan
        link?.retryNow() // do not wait out the backoff on a new network
        if (mayDiscover()) finder.networkChanged()
    }

    /**
     * "Enter address manually": a host or host:port typed by the user. The pairing, the token and the pinned
     * certificate are unchanged, so a wrong or hostile address still cannot get past the certificate check.
     */
    fun setAddress(text: String): Boolean {
        val (host, port) = Discovery.parseAddress(text) ?: return false
        if (currentPairing == null) return false
        useAddress(host, port)
        return true
    }

    /** Forgets the desktop: closes the link and deletes the stored secret. */
    fun unpair() {
        stopLink()
        store.clearPairing()
    }

    private fun stopLink() {
        verifyGeneration++
        finder.stop()
        netWatch.stop()
        screenWatch.stop()
        health = health.recovered()
        currentPairing = null
        link?.stop()
        link = null
        mode = Mode.NONE
        linkState = LinkState.DISCONNECTED
        desktopName = null
        chatLinkLost()
    }

    // ── LinkListener (link thread) ───────────────────────────────────────────

    override fun onState(state: LinkState) {
        main.post {
            linkState = state
            if (state == LinkState.CONNECTED) health = health.recovered()
            if (state == LinkState.CONNECTED) finder.connected() // found it (or never lost it): stop looking
            if (state != LinkState.CONNECTED) chatLinkLost()
        }
    }

    override fun onWelcome(desktopName: String, os: String) {
        main.post { if (desktopName.isNotBlank()) this.desktopName = desktopName }
    }

    override fun onCaps(caps: Set<String>) {
        main.post { chatOffered = Protocol.CAP_CHAT in caps }
    }

    override fun onChatModels(models: List<ChatModel>) {
        main.post {
            chatModels = models
            chatModel = ChatModels.pick(models, chatModel)
        }
    }

    override fun onChatDelta(id: String, text: String) {
        main.post { chatSession.onDelta(id, text); chatChanged(save = false) }
    }

    override fun onChatDone(id: String, text: String?) {
        main.post { chatSession.onDone(id, text); chatChanged(save = true) }
    }

    override fun onChatError(id: String, reason: String, message: String) {
        main.post { chatSession.onError(id, reason); chatChanged(save = true) }
    }

    /** A link that had worked ended on its own: remembered with its reason, so Home can say what happened. */
    override fun onLinkLost(reason: LostReason) {
        main.post { health = health.lost(System.currentTimeMillis(), reason) }
    }

    override fun onConnectFailed(consecutive: Int) {
        main.post { health = health.failedAttempt(consecutive) }
        // The saved address failed: now (and only now) look for the computer on the network.
        if (consecutive >= DiscoveryPolicy.FAILURES_BEFORE_DISCOVERY) main.post { if (mayDiscover()) finder.request() }
    }

    override fun onError(code: String, message: String) {
        main.post {
            this.message = if (code == "auth") context.getString(R.string.msg_rejected)
            else "${context.getString(R.string.msg_link_error)}: $message"
        }
    }
}
