#if !APPSTORE
import AppKit
import WebKit

// MARK: - Christmas music

/// Notchy's own Christmas music: one long YouTube compilation, played by
/// Notchy itself rather than by a browser.
///
/// It starts with the greeting at launch during the season, and the Christmas
/// folder on the left of the player starts it again after something else has
/// played. While it is the source, ``MusicController`` shows it on the card
/// exactly as it would any other app's track.
///
/// Three things here were found out the hard way, in a spike before any of it
/// was written:
///
/// - **The page needs a window.** A `WKWebView` that has never been in one
///   loads the page and never starts its media: `readyState` stays 0 forever.
///   So it lives in a borderless window parked far off every screen, fully
///   transparent and ignoring the mouse.
/// - **The embed needs a Referer.** Without one YouTube refuses with
///   `embedder.identity.missing.referrer`. The app's own public site is the
///   identity it gives.
/// - **macOS does not report it.** MediaRemote shows nothing at all while this
///   plays, so the card cannot learn about it from the system the way it does
///   for Spotify. That is why the card asks this object directly.
///
/// Nothing runs until the first `play()`, and a player that steps aside for
/// another app is torn down, not paused: the island owes 0 % CPU when hidden,
/// and a parked YouTube page is not that.
@MainActor
final class ChristmasMusicPlayer: NSObject, ObservableObject {
    static let shared = ChristmasMusicPlayer()

    /// "Vintage Christmas Songs 50s 60s 70s" from Silent Christmas — the link
    /// the island's Christmas music was asked to be. Its `list=RD…` radio mix is
    /// generated per viewer and cannot be embedded, so the one video loops.
    static let videoID = "asv5QPt2UQM"

    /// Who is embedding, for YouTube's embedder check.
    private static let referer = "https://louis-cfm.github.io/coucou/"

    /// The name of the bridge's message handler.
    private static let handlerName = "notchyChristmas"

    private static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// The Christmas music is what the player card is showing. True from a
    /// `play()` until another app starts playing or the player is stopped —
    /// paused included, so pausing it does not hand the card back to whatever
    /// played last week.
    @Published private(set) var isActive = false
    @Published private(set) var isPlaying = false
    @Published private(set) var title = ""
    @Published private(set) var author = ""
    @Published private(set) var duration: Double = 0
    @Published private(set) var artwork: NSImage?

    /// When it last became the source. Another app still reports itself as
    /// playing for a moment after it was told to pause, and that is not the
    /// user choosing it over the Christmas music.
    private(set) var activatedAt = Date.distantPast

    /// Where playback was at `anchorDate`, so the scrubber can move without a
    /// message from the page every frame.
    private var anchorTime: Double = 0
    private var anchorDate = Date()

    /// Where to pick up after the page was torn down.
    private var resumeAt: Double = 0

    /// The launch greeting starts it once per run, however often the greeting
    /// is replayed from the debug menu.
    private var startedWithGreeting = false

    private var window: NSWindow?
    private var webView: WKWebView?
    private var artworkTask: Task<Void, Never>?

    private override init() { super.init() }

    /// Where playback has got to, extrapolated from the last report.
    var elapsed: Double {
        guard isPlaying else { return anchorTime }
        let t = anchorTime + Date().timeIntervalSince(anchorDate)
        return duration > 0 ? min(t, duration) : t
    }

    // MARK: - Starting

    /// Called as the launch greeting begins. Plays only in season, with the
    /// setting on, and once per run.
    func startWithGreeting() {
        let state = AppState.shared
        guard !startedWithGreeting,
              IslandSnowLayer.seasonOpen(),
              state.christmasMusic,
              state.isEnabled
        else { return }
        startedWithGreeting = true
        play()
    }

    /// The Christmas music becomes what is playing.
    ///
    /// Whatever else was playing is paused first — two songs at once is never
    /// what a click on the folder meant.
    func play() {
        guard AppState.shared.isEnabled else { return }
        let other = NowPlayingController.shared.playbackState
        if other.isPlaying, !Self.isOwn(other.bundleIdentifier) {
            NowPlayingController.shared.pause()
        }
        activatedAt = Date()
        isActive = true
        if webView == nil {
            load()
        } else {
            run("window.__notchyChristmas && window.__notchyChristmas.play()")
        }
        loadArtwork()
    }

    func pause() {
        run("window.__notchyChristmas && window.__notchyChristmas.pause()")
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func seek(to time: Double) {
        let t = max(0, duration > 0 ? min(time, duration - 1) : time)
        anchorTime = t
        anchorDate = Date()
        run("window.__notchyChristmas && window.__notchyChristmas.seek(\(t))")
    }

    /// Another app started playing: the Christmas music steps aside, and its
    /// page goes with it. The folder brings it back from where it was.
    func yield() {
        guard isActive else { return }
        tearDown()
        isActive = false
        log("yielded to another player at \(Int(resumeAt)) s")
    }

    /// Off entirely: the setting, or Notchy's master switch.
    func stop() {
        guard isActive || webView != nil else { return }
        tearDown()
        isActive = false
    }

    /// Notchy's own bundle — what MediaRemote would name if it ever did report
    /// this player.
    static func isOwn(_ bundleIdentifier: String) -> Bool {
        !bundleIdentifier.isEmpty && bundleIdentifier == Bundle.main.bundleIdentifier
    }

    // MARK: - The page

    private func load() {
        let config = WKWebViewConfiguration()
        // Nothing to remember between runs, and nothing of anyone's to share.
        config.websiteDataStore = .nonPersistent()
        // Starting without a click is the whole point.
        config.mediaTypesRequiringUserActionForPlayback = []
        // Off every screen, and must keep playing all the same.
        config.preferences.inactiveSchedulingPolicy = .none

        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Self.bridge,
                                              injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true,
                                              in: .page))
        controller.add(self, contentWorld: .page, name: Self.handlerName)
        config.userContentController = controller

        let frame = NSRect(x: 0, y: 0, width: 480, height: 270)
        let view = WKWebView(frame: frame, configuration: config)
        view.customUserAgent = Self.safariUserAgent

        // A web view that was never in a window never starts its media.
        let host = NSWindow(contentRect: frame.offsetBy(dx: -20000, dy: -20000),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.alphaValue = 0
        host.ignoresMouseEvents = true
        host.hasShadow = false
        host.isExcludedFromWindowsMenu = true
        host.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
        host.contentView = view
        host.orderBack(nil)

        window = host
        webView = view

        var request = URLRequest(url: Self.embedURL(startingAt: resumeAt))
        request.setValue(Self.referer, forHTTPHeaderField: "Referer")
        view.load(request)
        log("page started at \(Int(resumeAt)) s")
    }

    private static func embedURL(startingAt seconds: Double) -> URL {
        var parts = URLComponents(string: "https://www.youtube-nocookie.com/embed/\(videoID)")!
        parts.queryItems = [
            URLQueryItem(name: "autoplay", value: "1"),
            URLQueryItem(name: "loop", value: "1"),
            URLQueryItem(name: "playlist", value: videoID),
            URLQueryItem(name: "start", value: String(Int(seconds))),
        ]
        return parts.url!
    }

    private func tearDown() {
        resumeAt = elapsed
        isPlaying = false
        anchorTime = resumeAt
        guard let view = webView else { return }
        view.stopLoading()
        // Unloading the page is what actually stops the sound; a web view kept
        // alive by anything at all would otherwise carry on singing.
        view.loadHTMLString("", baseURL: nil)
        view.configuration.userContentController.removeScriptMessageHandler(forName: Self.handlerName,
                                                                            contentWorld: .page)
        window?.contentView = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        webView = nil
        log("page stopped")
    }

    private func run(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    /// The video's own thumbnail, from the same service the music comes from.
    /// The 16:9 frame is cropped square by the card, which is what every
    /// player's art does.
    private func loadArtwork() {
        guard artwork == nil, artworkTask == nil else { return }
        let id = Self.videoID
        artworkTask = Task { [weak self] in
            for name in ["maxresdefault", "mqdefault"] {
                guard let url = URL(string: "https://i.ytimg.com/vi/\(id)/\(name).jpg"),
                      let (data, response) = try? await URLSession.shared.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let image = NSImage(data: data)
                else { continue }
                self?.artwork = image
                break
            }
            self?.artworkTask = nil
        }
    }

    // MARK: - Reports from the page

    fileprivate func handle(_ body: Any) {
        guard let report = body as? [String: Any] else { return }
        if let error = report["error"] as? String, !error.isEmpty {
            log("page error: \(error)")
        }
        if let t = report["t"] as? Double {
            anchorTime = t
            anchorDate = Date()
        }
        if let d = report["d"] as? Double, d.isFinite, d > 0, d != duration { duration = d }
        if let playing = report["playing"] as? Bool, playing != isPlaying { isPlaying = playing }
        if let t = report["title"] as? String, !t.isEmpty, t != title { title = t }
        if let a = report["author"] as? String, !a.isEmpty, a != author { author = a }
    }

    private func log(_ line: String) {
        appendAppLog("media.log", "christmas: \(line)")
    }

    /// Watches the page's `<video>` and reports on it: at once for play, pause
    /// and seek, and every five seconds otherwise — the card extrapolates in
    /// between. `ended` restarts it, in case the embed's own loop does not.
    private static let bridge = #"""
    (() => {
      if (window.__notchyChristmas) return;
      const post = (m) => { try { window.webkit.messageHandlers.notchyChristmas.postMessage(m); } catch (_) {} };
      const player = () => document.querySelector('#movie_player');
      let video = null, last = 0;
      const report = (now) => {
        if (!video) return;
        const at = Date.now();
        if (!now && at - last < 5000) return;
        last = at;
        let data = {};
        try { data = (player() && player().getVideoData && player().getVideoData()) || {}; } catch (_) {}
        post({
          playing: !video.paused && !video.ended,
          t: video.currentTime || 0,
          d: isFinite(video.duration) ? video.duration : 0,
          title: data.title || '',
          author: data.author || '',
          error: data.errorCode || ''
        });
      };
      const attach = (v) => {
        video = v;
        ['play', 'playing', 'pause', 'seeked', 'durationchange', 'loadedmetadata'].forEach((e) =>
          v.addEventListener(e, () => report(true)));
        v.addEventListener('timeupdate', () => report(false));
        v.addEventListener('ended', () => { v.currentTime = 0; v.play().catch(() => {}); });
        report(true);
      };
      window.__notchyChristmas = {
        play: () => { if (video) video.play().catch(() => {}); },
        pause: () => { if (video) video.pause(); },
        seek: (t) => { if (video) { video.currentTime = t; report(true); } }
      };
      const find = () => {
        const v = document.querySelector('video');
        if (v) { attach(v); return true; }
        return false;
      };
      if (!find()) {
        const poll = setInterval(() => { if (find()) clearInterval(poll); }, 250);
        setTimeout(() => {
          clearInterval(poll);
          if (!video) {
            let code = 'no video';
            try { code = (player() && player().getVideoData && player().getVideoData().errorCode) || code; } catch (_) {}
            post({ error: code });
          }
        }, 20000);
      }
    })();
    """#
}

extension ChristmasMusicPlayer: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        handle(message.body)
    }
}
#endif
