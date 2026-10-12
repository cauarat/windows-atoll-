#if !APPSTORE
import Foundation
import AppKit
import Combine

// MARK: - Music Controller

/// Now-playing state and transport for whatever application is playing.
///
/// Was Apple Music only: it listened for `com.apple.Music.playerInfo`
/// distributed notifications and drove playback through AppleScript, so
/// Spotify, Chrome, Safari and VLC were invisible and controlling Music needed
/// an automation grant. It is now a thin adapter over ``NowPlayingController``,
/// which reads MediaRemote through the vendored adapter and sends transport
/// commands straight to the private framework — no automation permission, and
/// every player.
///
/// The public surface is unchanged on purpose. The pill and the card already
/// call it in ten places; keeping the shape meant they gained every player
/// without being touched.
@MainActor
final class MusicController: ObservableObject {
    static let shared = MusicController()

    @Published var trackTitle: String?
    @Published var artist: String?
    @Published var album: String?

    /// Cover art, decoded once per track rather than per frame.
    @Published private(set) var artwork: NSImage?

    /// Set when media is unavailable — the adapter missing, or perl gone. Nil
    /// while it works.
    @Published private(set) var unavailableReason: String?

    private let nowPlaying = NowPlayingController.shared
    private var cancellables = Set<AnyCancellable>()

    /// So artwork is only re-decoded when the bytes actually change.
    private var lastArtworkData: Data?

    /// Whether media has a pill of its own. No longer decides whether the
    /// player runs — see the master-switch subscription below.
    private var isPillActive: Bool {
        AppState.shared.activeIntegrations.contains("integration_music")
    }

    /// Whether anything is playing anywhere on the Mac.
    var isPlaying: Bool { nowPlaying.playbackState.isPlaying }

    /// Which application it is coming from, in words.
    var sourceName: String {
        let id = sourceBundleIdentifier
        guard !id.isEmpty else { return "" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        // Fall back to the last part of the bundle id, which is usually the
        // name anyway, rather than showing the whole reverse-DNS string.
        return id.split(separator: ".").last.map(String.init) ?? id
    }

    /// That application's icon, or nil when the id names nothing installed.
    private static func icon(forBundleIdentifier id: String) -> NSImage? {
        guard !id.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// The application currently playing, for Open and for the accent.
    ///
    /// Published, unlike before: the card draws this app's icon on the artwork,
    /// and a plain `var` would leave yesterday's icon there when the song moved
    /// from Spotify to a browser.
    @Published private(set) var sourceBundleIdentifier: String = ""

    /// That application's icon, resolved once per app rather than per frame.
    ///
    /// `icon(forFile:)` reads the bundle off disk, which is far too expensive
    /// for a view body that redraws twice a second while the scrubber moves —
    /// so it is kept here the way `artwork` is, behind a guard on the id.
    @Published private(set) var sourceIcon: NSImage?

    private init() {
        nowPlaying.$playbackState
            .sink { [weak self] state in self?.apply(state) }
            .store(in: &cancellables)

        nowPlaying.$unavailableReason
            .assign(to: &$unavailableReason)

        // Follows the master switch, not the pill.
        //
        // It used to follow the pill, to keep a perl process off the machine
        // for anyone not using media. But the adapter reports whatever the Mac
        // is playing — a video in a browser, a voice note, Spotify — and "show
        // me what is playing" is not a thing you should have to go and switch
        // on first. The pill still decides whether media gets a card of its
        // own; it no longer decides whether the player works at all.
        //
        // The cost is one perl process while Notchy is running, and none when
        // it is off.
        AppState.shared.$isEnabled
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.nowPlaying.start() }
                else { self.nowPlaying.stop(); self.clearState() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Applying state

    private func apply(_ state: PlaybackState) {
        let wasPlaying = AppState.shared.musicPlaying

        trackTitle = state.title.isEmpty ? nil : Self.shortTitle(state.title)
        artist = state.artist.isEmpty ? nil : Self.shortArtist(state.artist)
        album = state.album.isEmpty ? nil : state.album
        if state.bundleIdentifier != sourceBundleIdentifier {
            sourceBundleIdentifier = state.bundleIdentifier
            sourceIcon = Self.icon(forBundleIdentifier: state.bundleIdentifier)
        }

        if state.artwork != lastArtworkData {
            lastArtworkData = state.artwork
            artwork = state.artwork.flatMap(NSImage.init(data:))
        }

        AppState.shared.musicPlaying = state.isPlaying
        AppState.shared.musicHasTrack = trackTitle != nil
        // Nothing goes through AppleScript any more, so there is no automation
        // grant left to be refused.
        AppState.shared.musicAutomationDenied = false
        syncTaskName()

        // Reveal only on transition from not-playing to playing.
        if state.isPlaying && !wasPlaying {
            NotificationCenter.default.post(name: .musicReveal, object: nil)
        }
    }

    private func clearState() {
        trackTitle = nil
        artist = nil
        album = nil
        artwork = nil
        lastArtworkData = nil
        sourceBundleIdentifier = ""
        sourceIcon = nil
        AppState.shared.musicPlaying = false
        AppState.shared.musicHasTrack = false
        syncTaskName()
    }

    private func syncTaskName() {
        guard let idx = AppState.shared.tasks.firstIndex(where: { $0.id == "integration_music" }) else { return }
        let title = trackTitle ?? ""
        AppState.shared.tasks[idx].name = title.isEmpty
            ? (PillCatalog.definition(for: "integration_music")?.name ?? "Now Playing")
            : title
    }

    // MARK: - Position

    /// Where playback has got to, extrapolated from the last anchor. Safe to
    /// call every frame.
    var elapsed: Double { nowPlaying.playbackState.estimatedTime() }
    var duration: Double { nowPlaying.playbackState.duration }

    var progress: Double {
        let total = duration
        guard total > 0 else { return 0 }
        return min(max(elapsed / total, 0), 1)
    }

    // MARK: - Playback controls

    func playPause() { nowPlaying.togglePlay() }
    func nextTrack() { nowPlaying.nextTrack() }
    func previousTrack() { nowPlaying.previousTrack() }
    func seek(to time: Double) { nowPlaying.seek(to: time) }

    /// Opens whichever app is playing, falling back to Music when nothing is.
    func openMusic() {
        let bundleID = sourceBundleIdentifier.isEmpty ? "com.apple.Music" : sourceBundleIdentifier

        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            app.activate()
            return
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Kept because the card still offers it, though nothing needs an
    /// automation grant now. It opens the pane rather than claiming a problem.
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Metadata cleaners

    private static func shortTitle(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        var s = raw
        // Cut at first " - "
        if let r = s.range(of: " - ") {
            s = String(s[..<r.lowerBound])
        }
        // Strip trailing (...) or [...] groups repeatedly
        var changed = true
        while changed {
            changed = false
            let t = s.trimmingCharacters(in: .whitespaces)
            guard let last = t.last, (last == ")" || last == "]") else { break }
            let open: Character = last == ")" ? "(" : "["
            if let idx = t.lastIndex(of: open) {
                let candidate = String(t[..<idx]).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty { s = candidate; changed = true }
            } else { break }
        }
        let result = s.trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? raw : result
    }

    private static func shortArtist(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        let lower = raw.lowercased()
        for tag in [" feat.", " ft."] {
            if let r = lower.range(of: tag) {
                let result = String(raw[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                return result.isEmpty ? raw : result
            }
        }
        return raw
    }
}
#endif
