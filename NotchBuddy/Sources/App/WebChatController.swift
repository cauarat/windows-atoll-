import AppKit
import Combine
import WebKit

// MARK: - Web chat (ChatGPT website inside the island)

/// Owns the `WKWebView` that shows chatgpt.com in the island.
///
/// The web view deliberately lives **outside** the SwiftUI tree. `IslandContentView` only
/// exists while the island is expanded, and it builds every `IslandView` at once in a
/// `ForEach` — so a SwiftUI-owned web view would fetch chatgpt.com every time the island
/// opened for any reason (an approval card, a message, the hotkey), and would be destroyed,
/// losing the conversation, on every collapse.
///
/// Three phases keep that honest:
/// - `cold`  — no web view, no WebContent process. Nothing of ours is running.
/// - `warm`  — web view alive but detached: the page survives between peeks at the notch,
///             while WebKit drops it to hidden (timers throttled, rAF stopped).
/// - `live`  — attached to the island and visible.
@MainActor
final class WebChatController: NSObject, ObservableObject {
    static let shared = WebChatController()

    enum Phase: String { case cold, warm, live }

    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        /// Cloudflare or OpenAI turned the embedded view away.
        case blocked(Int)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .cold
    @Published private(set) var loadState: LoadState = .idle

    /// Only non-nil in `.warm` and `.live`. Never built from a SwiftUI body.
    private var webView: WKWebView?
    /// Back/forward list, URL and scroll position, kept across a cold cycle.
    private var savedInteractionState: Data?
    private var coldTimer: DispatchWorkItem?
    private var memoryPressure: DispatchSourceMemoryPressure?
    private var storeID: UUID?

    /// How long a detached page is kept before it is released. Long enough that closing the
    /// island and reopening it is free; short enough that a forgotten chat does not hold a
    /// WebContent process all day.
    private let coldTTL: TimeInterval = 600

    private static let chatGPTURL = URL(string: "https://chatgpt.com/")!

    /// Safari's own UA. The WKWebView default omits the `Version/… Safari/…` tail, which is
    /// the part that marks a request as coming from an embedded view.
    private static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/27.0 Safari/605.1.15"

    // MARK: Holds read by the island

    var isLive: Bool { phase == .live }

    /// True while the user is actually working in the page, so the 15 s idle collapse does
    /// not fold ChatGPT away mid-sentence. Releases itself: clicking another app makes that
    /// app key, and the timer resumes.
    var holdsIsland: Bool { phase == .live && (webView?.window?.isKeyWindow ?? false) }

    private var mouseHoldUntil: Date = .distantPast

    /// Set by the window controller around a click or drag inside the island, so the 60 Hz
    /// click-through poll cannot cut a gesture off at the island edge.
    var holdsMouse: Bool {
        get { Date() < mouseHoldUntil }
        set { mouseHoldUntil = newValue ? .distantFuture : .distantPast }
    }

    /// Momentum scrolling has no "mouse up" to close the hold, so it gets a deadline that
    /// each further scroll event pushes out.
    func holdMouseBriefly() {
        mouseHoldUntil = max(mouseHoldUntil, Date().addingTimeInterval(0.35))
    }

    // MARK: Lifecycle

    /// The only entry point that may cause a network call to OpenAI.
    func activate(in host: NSView) {
        let s = AppState.shared
        // `viewDidMoveToWindow` also fires for the inactive hosts the ZStack builds, so the
        // state guard — not the call site — is what keeps chatgpt.com from loading unasked.
        guard s.isEnabled, s.webChatEnabled, s.mode == .expanded else { return }
        #if !APPSTORE
        guard s.view == .webchat else { return }
        #endif

        coldTimer?.cancel()
        coldTimer = nil

        let view = webView ?? makeWebView()
        if view.superview !== host {
            view.removeFromSuperview()
            host.addSubview(view)
        }
        view.frame = host.bounds
        view.autoresizingMask = [.width, .height]
        view.setAllMediaPlaybackSuspended(false)

        setPhase(.live, reason: "activate")

        // The panel is non-activating and never becomes key on its own; without this the
        // user types into ChatGPT and nothing happens. Order matters — WebKit only marks the
        // page focused once the window is key.
        host.window?.makeKey()
        host.window?.makeFirstResponder(view)

    }

    /// live → warm. Detaching drops WebKit's `IsInWindow`/`IsVisible` flags, so the page goes
    /// to `visibilityState: "hidden"` and throttles itself.
    func deactivate() {
        guard phase == .live, let view = webView else { return }
        view.removeFromSuperview()
        // Voice playback would otherwise keep going from a closed notch.
        view.setAllMediaPlaybackSuspended(true)
        setPhase(.warm, reason: "deactivate")
        scheduleCold()
    }

    /// Releases the web view and its WebContent process.
    func goCold(reason: String) {
        coldTimer?.cancel()
        coldTimer = nil
        guard let view = webView else {
            if phase != .cold { setPhase(.cold, reason: reason) }
            return
        }
        savedInteractionState = view.interactionState as? Data
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.removeFromSuperview()
        webView = nil
        loadState = .idle
        setPhase(.cold, reason: reason)
    }

    func reload() {
        loadState = .loading
        if let view = webView { view.reload() } else { _ = makeWebView() }
    }

    /// Signs out by removing the whole store. Goes cold first: a live WebContent process
    /// would write its cookies straight back.
    func clearAllData() async {
        goCold(reason: "clear data")
        savedInteractionState = nil
        if let id = storeID {
            try? await WKWebsiteDataStore.remove(forIdentifier: id)
        }
        UserDefaults.standard.removeObject(forKey: Self.storeIDKey)
        storeID = nil
    }

    // MARK: Internals

    private func setPhase(_ new: Phase, reason: String) {
        guard new != phase else { return }
        appendAppLog("webchat.log", "\(phase.rawValue) -> \(new.rawValue) (\(escapedForLog(reason)))")
        phase = new
    }

    private func scheduleCold() {
        coldTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.goCold(reason: "idle \(Int(self?.coldTTL ?? 0))s")
        }
        coldTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + coldTTL, execute: work)
    }

    private static let storeIDKey = "webChatStoreID"

    /// A named store rather than `.default()`: it can be deleted in one call, and it gives a
    /// one-line answer to "where does the ChatGPT cookie live".
    private func dataStore() -> WKWebsiteDataStore {
        if let id = storeID { return WKWebsiteDataStore(forIdentifier: id) }
        let ud = UserDefaults.standard
        let id = ud.string(forKey: Self.storeIDKey).flatMap(UUID.init(uuidString:)) ?? {
            let fresh = UUID()
            ud.set(fresh.uuidString, forKey: Self.storeIDKey)
            return fresh
        }()
        storeID = id
        return WKWebsiteDataStore(forIdentifier: id)
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore()

        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = Self.safariUserAgent
        view.navigationDelegate = self
        view.uiDelegate = self
        // A horizontal two-finger scroll inside a code block would otherwise navigate back
        // and take the conversation with it.
        view.allowsBackForwardNavigationGestures = false
        view.allowsMagnification = false
        view.appearance = NSAppearance(named: .darkAqua)
        view.underPageBackgroundColor = .black

        webView = view
        loadState = .loading

        // Restoring interaction state starts its own navigation; loading as well would
        // double-fetch.
        if let saved = savedInteractionState {
            view.interactionState = saved
            savedInteractionState = nil
        } else {
            view.load(URLRequest(url: Self.chatGPTURL))
        }

        startMemoryPressureWatchIfNeeded()
        return view
    }

    /// A 300–600 MB WebContent process in a menu-bar utility should be the first thing to go
    /// when the machine is short on memory.
    private func startMemoryPressureWatchIfNeeded() {
        guard memoryPressure == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical],
                                                             queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.goCold(reason: "memory pressure") }
        }
        source.resume()
        memoryPressure = source
    }
}

// MARK: - Navigation

extension WebChatController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only the main frame is filtered. Cloudflare's Turnstile and the sign-in iframes
        // live in subframes, and gating those is how you get a challenge that never clears.
        guard navigationAction.targetFrame?.isMainFrame == true else {
            decisionHandler(.allow)
            return
        }
        let url = navigationAction.request.url
        if webChatKeepsInIsland(url) {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if let safe = safeWebURL(url?.absoluteString) { NSWorkspace.shared.open(safe) }
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let http = navigationResponse.response as? HTTPURLResponse,
           navigationResponse.isForMainFrame {
            // 403/503 here is the embedded view being turned away. Surface it, so the failure
            // reads as a message instead of a blank island.
            if http.statusCode == 403 || http.statusCode == 503 {
                loadState = .blocked(http.statusCode)
            }
        }
        // Anything we cannot render is a download; hand it to the browser.
        guard navigationResponse.canShowMIMEType else {
            decisionHandler(.cancel)
            if let safe = safeWebURL(navigationResponse.response.url?.absoluteString) {
                NSWorkspace.shared.open(safe)
            }
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if case .blocked = loadState { return }
        loadState = .ready
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadState = .failed(error.localizedDescription)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        loadState = .failed(error.localizedDescription)
    }
}

// MARK: - UI delegate

extension WebChatController: WKUIDelegate {

    /// Never open a second web view. An allowed target loads in place; anything else is the
    /// browser's job.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        if webChatKeepsInIsland(url) {
            webView.load(navigationAction.request)
        } else if let safe = safeWebURL(url?.absoluteString) {
            NSWorkspace.shared.open(safe)
        }
        return nil
    }

    /// ChatGPT's "+" button is an `<input type=file>`, which does nothing without this.
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        // Not a sheet: a borderless panel above the menu bar is a poor sheet parent.
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            MainActor.assumeIsolated {
                completionHandler(response == .OK ? panel.urls : nil)
                // The open panel stole key; give it back or typing stops working.
                if let view = self.webView, view.superview != nil {
                    view.window?.makeKey()
                    view.window?.makeFirstResponder(view)
                }
            }
        }
    }

    /// There is no camera or microphone usage string in Info.plist, so a TCC prompt would
    /// kill the process. Denying also stops voice mode hanging on a permission that never
    /// resolves.
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }
}
