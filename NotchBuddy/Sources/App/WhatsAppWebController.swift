import AppKit
import Combine
import WebKit

// MARK: - Settings

/// The non-secret half of the WhatsApp configuration. There is no server and
/// no password: the session is WhatsApp Web's own, in its own data store.
enum WhatsAppSettings {
    /// What a second click on the pill opens: `PillOpen.websiteSetting`, or an
    /// application's bundle identifier.
    static var openTarget: String {
        get {
            let stored = UserDefaults.standard.string(forKey: "whatsAppOpenTarget") ?? ""
            return stored.isEmpty ? PillOpen.websiteSetting : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: "whatsAppOpenTarget") }
    }

    /// WhatsApp's own Mac app, offered as the "open with" suggestion.
    static let defaultAppBundleID = "net.whatsapp.WhatsApp"

    /// Whether this Mac has been linked to a phone at least once. Without it a
    /// pill switched on does not load web.whatsapp.com by itself: nobody who
    /// has not asked to connect should have a page open to it.
    static var isLinked: Bool {
        get { UserDefaults.standard.bool(forKey: "whatsAppLinked") }
        set { UserDefaults.standard.set(newValue, forKey: "whatsAppLinked") }
    }
}

// MARK: - Controller

/// Keeps WhatsApp Web running out of sight and turns what it announces into
/// inbox messages.
///
/// WhatsApp has no API for a personal account, so this is the page itself, in
/// a `WKWebView` that belongs to no window most of the time. The bridge script
/// (`shared/whatsapp-bridge.js`) is what makes that work: it takes the page's
/// notifications instead of letting them draw, tells the page it is in a
/// background tab so nothing is marked read, and types replies into the page
/// the way a person would.
///
/// Unlike ``WebChatController`` it does not go cold on a timer or on memory
/// pressure: a page that is not running is messages that never arrive. It
/// runs exactly while the WhatsApp pill is on, and costs one WebContent
/// process for as long as it does.
@MainActor
final class WhatsAppWebController: NSObject, ObservableObject {
    static let shared = WhatsAppWebController()

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        /// The page is asking for the QR code: the phone has not linked this
        /// Mac yet, or unlinked it.
        case needsQR
        case connected
        case failed(String)

        var isConnected: Bool { self == .connected }
    }

    @Published private(set) var state: ConnectionState = .disconnected

    /// True while the sign-in window is on screen.
    @Published private(set) var isShowingLogin = false

    private var webView: WKWebView?
    private var loginWindow: NSWindow?
    private var storeID: UUID?
    private var loadDeadline: DispatchWorkItem?
    private var retry: DispatchWorkItem?
    private var retryDelay: TimeInterval = 5

    private static let storeIDKey = "whatsAppStoreID"
    private static let handlerName = "notchy"
    private static let loadTimeout: TimeInterval = 60

    /// Safari's own UA. WhatsApp Web turns unsupported browsers away, and the
    /// WKWebView default lacks the `Version/… Safari/…` tail it looks for.
    private static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private override init() { super.init() }

    // MARK: - Lifecycle

    /// Starts the page if this Mac has been linked before. Called whenever
    /// the pill is on; does nothing for someone who never asked to connect.
    func connectIfConfigured() {
        guard WhatsAppSettings.isLinked else { return }
        connect()
    }

    /// Starts the page, or leaves it running.
    func connect() {
        retry?.cancel()
        retry = nil
        if webView == nil {
            _ = makeWebView()
        }
        if state != .connected && state != .needsQR {
            state = .connecting
        }
    }

    /// Opens the sign-in window with the page in it, starting the page first
    /// if it is not running. The window closes by itself once the phone has
    /// scanned the code.
    func showLogin() {
        let view = webView ?? makeWebView()
        if state != .connected && state != .needsQR { state = .connecting }

        let window = loginWindow ?? makeLoginWindow()
        if view.superview !== window.contentView {
            view.removeFromSuperview()
            if let content = window.contentView {
                view.frame = content.bounds
                view.autoresizingMask = [.width, .height]
                content.addSubview(view)
            }
        }
        setShown(true)
        isShowingLogin = true
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Stops the page and keeps the session: turning the pill back on picks
    /// up where it left off, without a new QR code.
    func disconnect() {
        closeLogin()
        tearDown()
        state = .disconnected
    }

    /// Unlinks this Mac: the page goes, and the store holding WhatsApp's
    /// session goes with it. The phone lists the device until it notices.
    func signOut() async {
        disconnect()
        WhatsAppSettings.isLinked = false
        if let id = storeID ?? UserDefaults.standard.string(forKey: Self.storeIDKey).flatMap(UUID.init(uuidString:)) {
            try? await WKWebsiteDataStore.remove(forIdentifier: id)
        }
        UserDefaults.standard.removeObject(forKey: Self.storeIDKey)
        storeID = nil
        log("signed out")
    }

    // MARK: - Sending

    struct SendError: LocalizedError {
        let text: String
        var errorDescription: String? { text }
    }

    /// Replies in a conversation by driving the page: open it, type, send,
    /// then attach each file and send that.
    ///
    /// - Parameters:
    ///   - chat: the conversation's name, as the notification gave it.
    ///   - key: the bridge's handle for the notification being answered, which
    ///     opens that exact conversation. Without it the chat is found by name.
    func sendMessage(chat: String, key: String?, text: String, attachments: [URL]) async throws {
        guard let webView, state == .connected else {
            throw SendError(text: L("WhatsApp is not connected"))
        }

        var files: [[String: Any]] = []
        for url in attachments {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw SendError(text: L("Could not read \(url.lastPathComponent)"))
            }
            files.append([
                "name": url.lastPathComponent,
                "mime": AttachmentKind.mimeType(forExtension: url.pathExtension),
                "base64": data.base64EncodedString(),
            ])
        }

        let request: [String: Any] = [
            "requestId": UUID().uuidString,
            "chat": chat,
            "key": key ?? "",
            "text": text,
            "files": files,
        ]

        let result: Any?
        do {
            result = try await webView.callAsyncJavaScript(
                "return await window.__notchy.send(request);",
                arguments: ["request": request],
                in: nil,
                contentWorld: .page
            )
        } catch {
            log("send failed to run: \(error.localizedDescription)")
            throw SendError(text: L("WhatsApp did not take the reply"))
        }

        let answer = result as? [String: Any]
        if (answer?["ok"] as? Bool) == true { return }
        let reason = answer?["reason"] as? String ?? "unknown"
        log("send failed: \(reason)")
        throw SendError(text: L("WhatsApp did not take the reply"))
    }

    // MARK: - Internals

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore()
        // Out of every window most of the time, and must keep its socket all
        // the same: the default policy suspends a page nobody can see.
        config.preferences.inactiveSchedulingPolicy = .none

        let controller = WKUserContentController()
        if let script = Self.bridgeSource() {
            controller.addUserScript(WKUserScript(source: script,
                                                  injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true,
                                                  in: .page))
        } else {
            log("bridge script missing from the bundle")
        }
        controller.add(self, contentWorld: .page, name: Self.handlerName)
        config.userContentController = controller

        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 720), configuration: config)
        view.customUserAgent = Self.safariUserAgent
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = false
        view.allowsMagnification = false

        webView = view
        view.load(URLRequest(url: WhatsAppRules.webURL))
        armLoadDeadline()
        log("page started")
        return view
    }

    private func tearDown() {
        loadDeadline?.cancel()
        loadDeadline = nil
        retry?.cancel()
        retry = nil
        guard let view = webView else { return }
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: Self.handlerName,
                                                                            contentWorld: .page)
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.removeFromSuperview()
        webView = nil
        log("page stopped")
    }

    private static func bridgeSource() -> String? {
        guard let url = Bundle.main.url(forResource: "whatsapp-bridge", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// A named store, so signing out is one call and "where does the WhatsApp
    /// session live" has a one-line answer.
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

    private func makeLoginWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = L("Connect WhatsApp")
        window.isReleasedWhenClosed = false
        window.delegate = self
        loginWindow = window
        return window
    }

    private func closeLogin() {
        guard let window = loginWindow else { return }
        webView?.removeFromSuperview()
        window.orderOut(nil)
        setShown(false)
        isShowingLogin = false
    }

    /// Tells the bridge whether a person can see the page. Hidden is what keeps
    /// it announcing messages and not marking them read.
    private func setShown(_ shown: Bool) {
        webView?.evaluateJavaScript("window.__notchy && window.__notchy.setShown(\(shown))",
                                    in: nil, in: .page, completionHandler: nil)
    }

    private func armLoadDeadline() {
        loadDeadline?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .connecting else { return }
            self.fail(L("WhatsApp Web did not load"))
        }
        loadDeadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.loadTimeout, execute: work)
    }

    private func fail(_ reason: String) {
        state = .failed(reason)
        log("failed: \(reason)")
        scheduleRetry()
    }

    /// Reloads after a failure, backing off up to five minutes, for as long as
    /// the page is meant to be running.
    private func scheduleRetry() {
        retry?.cancel()
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 300)
        let work = DispatchWorkItem { [weak self] in
            guard let self, let view = self.webView else { return }
            self.state = .connecting
            view.load(URLRequest(url: WhatsAppRules.webURL))
            self.armLoadDeadline()
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func handle(_ event: WhatsAppRules.Event) {
        switch event {
        case .state(let page):
            loadDeadline?.cancel()
            switch page {
            case .connected:
                retryDelay = 5
                if state != .connected { log("connected") }
                state = .connected
                WhatsAppSettings.isLinked = true
                if isShowingLogin {
                    // Long enough to see it work; then out of the way.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        guard let self, self.state == .connected else { return }
                        self.loginWindow?.close()
                    }
                }
            case .qr:
                if state != .needsQR { log("needs QR") }
                state = .needsQR
            case .loading:
                if state != .connected && state != .needsQR { state = .connecting }
            }
        case .message(let incoming):
            ingest(incoming)
        case .sent, .sendFailed:
            // The reply's own promise answers `sendMessage`; these are for the
            // Windows host, which has no promise to wait on.
            break
        }
    }

    private func ingest(_ incoming: WhatsAppRules.Incoming) {
        let sender = WhatsAppRules.displayName(incoming.chat) ?? "WhatsApp"
        let summary = WhatsAppRules.isSummary(chat: incoming.chat)
        let message = InboxMessage(
            id: WhatsAppRules.messageID(key: incoming.key),
            source: .whatsapp,
            kind: .directMessage,
            sender: sender,
            channel: nil,
            conversationID: summary ? nil : incoming.chat,
            body: WhatsAppRules.body(incoming.body) ?? L("📎 Sent a file"),
            timestamp: incoming.timestamp,
            link: WhatsAppRules.webURL
        )
        MessageInbox.shared.ingest(message)
    }

    private func log(_ line: String) {
        appendAppLog("whatsapp.log", line)
    }
}

// MARK: - Bridge

extension WhatsAppWebController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        // Only the top page of WhatsApp Web speaks for it; a frame does not.
        guard message.frameInfo.isMainFrame,
              WhatsAppRules.keepsInWebView(message.frameInfo.request.url),
              let event = WhatsAppRules.event(from: message.body)
        else { return }
        handle(event)
    }
}

// MARK: - Navigation

extension WhatsAppWebController: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame == true else {
            decisionHandler(.allow)
            return
        }
        let url = navigationAction.request.url
        if WhatsAppRules.keepsInWebView(url) {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if let safe = safeWebURL(url?.absoluteString) { NSWorkspace.shared.open(safe) }
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // A document clicked in a message is a download; the browser has it.
        guard navigationResponse.canShowMIMEType else {
            decisionHandler(.cancel)
            if let safe = safeWebURL(navigationResponse.response.url?.absoluteString) {
                NSWorkspace.shared.open(safe)
            }
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error.localizedDescription)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        fail(error.localizedDescription)
    }

    /// The WebContent process died — memory, a crash. The page is messages
    /// arriving, so it comes back.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log("web content process terminated")
        state = .connecting
        webView.load(URLRequest(url: WhatsAppRules.webURL))
        armLoadDeadline()
    }
}

// MARK: - UI

extension WhatsAppWebController: WKUIDelegate {
    /// Never a second web view: links in messages are the browser's.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let safe = safeWebURL(navigationAction.request.url?.absoluteString) {
            NSWorkspace.shared.open(safe)
        }
        return nil
    }

    /// No microphone or camera usage strings for a page: a TCC prompt for one
    /// would be WhatsApp's call screen asking from a window nobody sees.
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }
}

// MARK: - Sign-in window

extension WhatsAppWebController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // The page stays; only the window goes. Closing it before scanning is
        // "not now", not "stop".
        webView?.removeFromSuperview()
        setShown(false)
        isShowingLogin = false
    }
}
