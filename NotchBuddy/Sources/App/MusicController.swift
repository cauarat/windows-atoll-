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

    private var isPillActive: Bool {
        AppState.shared.activeIntegrations.contains("integration_music")
    }

    /// The application currently playing, for Open and for the accent.
    private(set) var sourceBundleIdentifier: String = ""

    private init() {
        nowPlaying.$playbackState
            .sink { [weak self] state in self?.apply(state) }
            .store(in: &cancellables)

        nowPlaying.$unavailableReason
            .assign(to: &$unavailableReason)

        // Starting and stopping with the pill keeps a perl process off the
        // machine for anyone not using media, which is what the old controller
        // achieved by only reading when the pill was on.
        AppState.shared.$activeIntegrations
            .sink { [weak self] integrations in
                guard let self else { return }
                if integrations.contains("integration_music") {
                    self.nowPlaying.start()
                } else {
                    self.nowPlaying.stop()
                    self.clearState()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Applying state

    private func apply(_ state: PlaybackState) {
        guard isPillActive else { return }

        let wasPlaying = AppState.shared.musicPlaying

        trackTitle = state.title.isEmpty ? nil : Self.shortTitle(state.title)
        artist = state.artist.isEmpty ? nil : Self.shortArtist(state.artist)
        album = state.album.isEmpty ? nil : state.album
        sourceBundleIdentifier = state.bundleIdentifier

        if state.artwork != lastArtworkData {
            lastArtworkData = state.artwork
            artwork = state.artwork.flatMap(NSImage.init(data:))
        }

        AppState.shared.musicPlaying = state.isPlaying
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
        AppState.shared.musicPlaying = false
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
