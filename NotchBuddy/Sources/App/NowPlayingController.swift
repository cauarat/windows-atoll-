/*
 * Notchy
 *
 * Adapted from Atoll (DynamicIsland), which is GPL v3. See NOTICE.
 *
 * Changed here: favouriting is gone (it reached into four player-specific
 * Atoll helpers), the protocol it conformed to is gone (there is one
 * implementation), the framework is resolved from Contents/Frameworks rather
 * than Resources, failures report themselves instead of trapping, and the
 * whole class is main-actor isolated for Swift 6 strict concurrency.
 *
 * Copyright (C) 2024-2026 Atoll Contributors
 * Copyright (C) 2026 Notchy Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Combine
import Foundation

/// Now-playing state for whatever application is playing, via MediaRemote.
///
/// Two halves with different rules. *Reading* has been gated to entitled
/// processes since macOS 15.4, so it happens in Apple-signed `/usr/bin/perl`,
/// which loads the vendored adapter framework and streams newline-delimited
/// JSON back here. *Writing* — play, pause, seek — needs none of that and
/// calls the private framework directly.
@MainActor
final class NowPlayingController: ObservableObject {
    static let shared = NowPlayingController()

    /// How recent a sender's timestamp has to be for the position beside it to
    /// count as a reading of now rather than a record of something earlier.
    ///
    /// Generous on purpose: it only has to separate a sample taken this moment
    /// from one a sender has been repeating since it paused, and those are
    /// minutes apart, not seconds.
    private static let currentSampleWindow: TimeInterval = 2

    // MARK: - Published state

    @Published private(set) var playbackState = PlaybackState(bundleIdentifier: "")

    /// Nil while media is working. Set when the stream cannot be started, so
    /// the UI can say so.
    ///
    /// Upstream used `assertionFailure` here, which traps in Debug. That is the
    /// wrong failure for something that depends on `/usr/bin/perl`, a runtime
    /// Apple has said it will eventually remove: the app should go quiet about
    /// media and carry on, not die.
    @Published private(set) var unavailableReason: String?

    var isRunning: Bool { process?.isRunning == true }

    // MARK: - MediaRemote command functions

    // Optional rather than a failable init: a missing symbol should disable
    // media, not prevent the singleton from existing.
    private let sendCommand: (@convention(c) (Int, AnyObject?) -> Void)?
    private let setElapsedTime: (@convention(c) (Double) -> Void)?
    private let setShuffleMode: (@convention(c) (Int) -> Void)?
    private let setRepeatMode: (@convention(c) (Int) -> Void)?

    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?

    // MARK: - Init

    private init() {
        let bundle = CFBundleCreate(
            kCFAllocatorDefault,
            NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        )

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let bundle,
                  let pointer = CFBundleGetFunctionPointerForName(bundle, name as CFString)
            else { return nil }
            return unsafeBitCast(pointer, to: type)
        }

        sendCommand = symbol("MRMediaRemoteSendCommand", as: (@convention(c) (Int, AnyObject?) -> Void).self)
        setElapsedTime = symbol("MRMediaRemoteSetElapsedTime", as: (@convention(c) (Double) -> Void).self)
        setShuffleMode = symbol("MRMediaRemoteSetShuffleMode", as: (@convention(c) (Int) -> Void).self)
        setRepeatMode = symbol("MRMediaRemoteSetRepeatMode", as: (@convention(c) (Int) -> Void).self)
    }

    // MARK: - Lifecycle

    func start() {
        guard process == nil else { return }

        guard let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworksPath = Bundle.main.privateFrameworksPath
        else {
            unavailableReason = "The media adapter is missing from the app bundle."
            return
        }

        let frameworkPath = (frameworksPath as NSString)
            .appendingPathComponent("MediaRemoteAdapter.framework")

        guard FileManager.default.fileExists(atPath: frameworkPath) else {
            unavailableReason = "The media adapter framework is missing from the app bundle."
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // --micros swaps the time keys for microsecond equivalents. The default
        // "timestamp" is an ISO-8601 string truncated to whole seconds, which
        // throws away up to a second of the playback anchor and makes every
        // position estimate drift by that much.
        process.arguments = [scriptURL.path, frameworkPath, "stream", "--micros"]

        let pipeHandler = JSONLinesPipeHandler()
        process.standardOutput = pipeHandler.pipe

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let message = String(data: data, encoding: .utf8)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !message.isEmpty
            else { return }
            appendAppLog("media.log", "adapter stderr: \(message)")
        }

        do {
            try process.run()
        } catch {
            unavailableReason = "Could not start the media adapter: \(error.localizedDescription)"
            return
        }

        self.process = process
        self.pipeHandler = pipeHandler
        unavailableReason = nil

        streamTask = Task { [weak self] in
            await pipeHandler.readJSONLines(as: NowPlayingUpdate.self) { update in
                await self?.handleAdapterUpdate(update)
            }
            // The stream only ends when perl exits, which it should not do on
            // its own. Saying so beats going quiet with no explanation.
            await MainActor.run {
                guard let self, self.process != nil else { return }
                self.unavailableReason = "The media adapter stopped unexpectedly."
            }
        }

        // Children outlive the app otherwise, leaving a perl process per launch.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { NowPlayingController.shared.stop() }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil

        if let process, process.isRunning {
            process.terminate()
        }
        self.process = nil

        let handler = pipeHandler
        pipeHandler = nil
        Task { await handler?.close() }
    }

    // MARK: - Transport

    func play() { sendCommand?(0, nil) }
    func pause() { sendCommand?(1, nil) }
    func togglePlay() { sendCommand?(2, nil) }
    func nextTrack() { sendCommand?(4, nil) }
    func previousTrack() { sendCommand?(5, nil) }
    func seek(to time: Double) { setElapsedTime?(time) }

    func toggleShuffle() {
        setShuffleMode?(playbackState.isShuffled ? 1 : 3)
        playbackState.isShuffled.toggle()
    }

    func toggleRepeat() {
        let next = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: next) ?? .off
        setRepeatMode?(next)
    }

    // MARK: - Stream handling

    private func handleAdapterUpdate(_ update: NowPlayingUpdate) {
        let payload = update.payload
        let diff = update.diff ?? false

        var next = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier)

        next.title = payload.title ?? (diff ? playbackState.title : "")
        next.artist = payload.artist ?? (diff ? playbackState.artist : "")
        next.album = payload.album ?? (diff ? playbackState.album : "")
        next.duration = payload.resolvedDuration ?? (diff ? playbackState.duration : 0)

        // The reported position and the instant it was sampled are a matched pair:
        // elapsedTime is the position *at* timestamp. They have to be adopted or
        // carried forward together -- pairing a fresh position with the previous
        // update's anchor makes every estimate run ahead by the age of that anchor.
        if let elapsed = payload.resolvedElapsedTime {
            next.currentTime = elapsed
            next.lastUpdated = payload.resolvedTimestamp ?? Date()
        } else if payload.clearsElapsedTime {
            // The sender named the position and set it to null, so there is
            // nothing left to extrapolate from. Carrying the old pair forward
            // here would keep advancing a position the sender has disowned.
            next.currentTime = 0
            next.lastUpdated = payload.resolvedTimestamp ?? Date()
        } else if diff {
            next.currentTime = playbackState.currentTime
            next.lastUpdated = playbackState.lastUpdated
        } else {
            next.currentTime = 0
            next.lastUpdated = payload.resolvedTimestamp ?? Date()
        }

        // Senders are not obliged to keep publishing. Spotify anchors once when
        // a track starts and then says nothing for the rest of it. Extrapolating
        // from a stale anchor is fine while the music runs, because wall-clock
        // and playback time advance together.
        //
        // They stop agreeing the moment playback stops. A pause the sender does
        // not follow with a fresh position leaves the anchor where it was, so on
        // resume the extrapolation counts the paused time as played and every
        // pause pushes the estimate further ahead. So the position is re-anchored
        // on the transition itself: frozen where it got to when playback stops,
        // and restarted from there when it resumes.
        let wasPlaying = playbackState.isPlaying
        let isPlayingNow = payload.playing ?? (diff ? wasPlaying : false)

        // Whether the sender sent a position is not the question -- whether it
        // sent a *current* one is. Spotify keeps republishing the exact instant
        // it paused, with a timestamp that keeps ageing. That pair is harmless
        // while paused, because nothing extrapolates a stopped track, and wrong
        // the moment playback resumes.
        let now = Date()
        let hasCurrentSample: Bool = {
            guard payload.resolvedElapsedTime != nil else { return false }
            // No timestamp means it was stamped on arrival, so it is current
            // by construction.
            guard let stamp = payload.resolvedTimestamp else { return true }
            return abs(now.timeIntervalSince(stamp)) <= Self.currentSampleWindow
        }()

        if wasPlaying != isPlayingNow, !hasCurrentSample {
            // The transition is being observed now, so now is when it happened.
            // The payload's own timestamp is only better if it is about now as
            // well -- and the stale one is what caused this.
            let transitionInstant: Date = {
                guard let stamp = payload.resolvedTimestamp,
                      abs(now.timeIntervalSince(stamp)) <= Self.currentSampleWindow
                else { return now }
                return stamp
            }()

            if wasPlaying {
                let playedSince = transitionInstant.timeIntervalSince(playbackState.lastUpdated)
                next.currentTime = max(
                    0,
                    playbackState.currentTime + playedSince * playbackState.playbackRate
                )
            } else {
                // Resuming from wherever it was left. The frozen position is the
                // one this controller worked out when the pause was observed;
                // the payload's is the sample already known to be stale, which
                // for some senders is a repeated zero that would restart the
                // track. A seek while paused publishes a fresh sample, so it
                // never reaches this branch.
                next.currentTime = max(0, playbackState.currentTime)
            }

            next.lastUpdated = transitionInstant
        }

        if let shuffleMode = payload.shuffleMode {
            next.isShuffled = shuffleMode != 1
        } else {
            next.isShuffled = diff ? playbackState.isShuffled : false
        }

        if let repeatModeValue = payload.repeatMode {
            next.repeatMode = RepeatMode(rawValue: repeatModeValue) ?? .off
        } else {
            next.repeatMode = diff ? playbackState.repeatMode : .off
        }

        if let artworkDataString = payload.artworkData {
            next.artwork = Data(
                base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else if diff {
            next.artwork = playbackState.artwork
        }

        next.playbackRate = payload.playbackRate ?? (diff ? playbackState.playbackRate : 1.0)
        next.isPlaying = isPlayingNow
        next.bundleIdentifier =
            payload.parentApplicationBundleIdentifier
            ?? payload.bundleIdentifier
            ?? (diff ? playbackState.bundleIdentifier : "")

        playbackState = next
    }
}

// MARK: - Wire format

struct NowPlayingUpdate: Codable, Sendable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

struct NowPlayingPayload: Codable, Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    /// Microsecond variants, emitted in place of the keys above when the adapter
    /// runs with --micros. Preferred because the plain "timestamp" is truncated
    /// to whole seconds.
    let durationMicros: Double?
    let elapsedTimeMicros: Double?
    let timestampEpochMicros: Double?
    let shuffleMode: Int?
    let repeatMode: Int?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?

    /// Whether the update names a position field and sets it to null.
    ///
    /// A diff omits what has not changed, so an absent position means "carry the
    /// last one forward". A position that is present but null is the sender
    /// saying it no longer has one. Optional decoding renders both as nil, so
    /// the distinction has to be captured while the container is still in hand
    /// -- otherwise a cleared position is mistaken for an unchanged one and the
    /// old position keeps being extrapolated from.
    let clearsElapsedTime: Bool

    private enum CodingKeys: String, CodingKey {
        case title, artist, album, duration, elapsedTime
        case durationMicros, elapsedTimeMicros, timestampEpochMicros
        case shuffleMode, repeatMode, artworkData, timestamp
        case playbackRate, playing
        case parentApplicationBundleIdentifier, bundleIdentifier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        title = try c.decodeIfPresent(String.self, forKey: .title)
        artist = try c.decodeIfPresent(String.self, forKey: .artist)
        album = try c.decodeIfPresent(String.self, forKey: .album)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        elapsedTime = try c.decodeIfPresent(Double.self, forKey: .elapsedTime)
        durationMicros = try c.decodeIfPresent(Double.self, forKey: .durationMicros)
        elapsedTimeMicros = try c.decodeIfPresent(Double.self, forKey: .elapsedTimeMicros)
        timestampEpochMicros = try c.decodeIfPresent(Double.self, forKey: .timestampEpochMicros)
        shuffleMode = try c.decodeIfPresent(Int.self, forKey: .shuffleMode)
        repeatMode = try c.decodeIfPresent(Int.self, forKey: .repeatMode)
        artworkData = try c.decodeIfPresent(String.self, forKey: .artworkData)
        timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp)
        playbackRate = try c.decodeIfPresent(Double.self, forKey: .playbackRate)
        playing = try c.decodeIfPresent(Bool.self, forKey: .playing)
        parentApplicationBundleIdentifier = try c.decodeIfPresent(
            String.self, forKey: .parentApplicationBundleIdentifier
        )
        bundleIdentifier = try c.decodeIfPresent(String.self, forKey: .bundleIdentifier)

        func isExplicitlyNull(_ key: CodingKeys) throws -> Bool {
            try c.contains(key) && c.decodeNil(forKey: key)
        }

        clearsElapsedTime = try isExplicitlyNull(.elapsedTime)
            || isExplicitlyNull(.elapsedTimeMicros)
    }
}

extension NowPlayingPayload {
    private static let isoFormatter = ISO8601DateFormatter()

    var resolvedDuration: Double? {
        if let durationMicros { return durationMicros / 1_000_000 }
        return duration
    }

    var resolvedElapsedTime: Double? {
        if let elapsedTimeMicros { return elapsedTimeMicros / 1_000_000 }
        return elapsedTime
    }

    /// The instant ``resolvedElapsedTime`` was sampled.
    ///
    /// Prefers the microsecond epoch value. The ISO-8601 string is only a
    /// fallback for adapters that do not honour --micros: it is formatted to
    /// whole seconds, so it drops the sub-second part of the anchor and biases
    /// the position estimate forward by up to a second.
    var resolvedTimestamp: Date? {
        if let timestampEpochMicros {
            return Date(timeIntervalSince1970: timestampEpochMicros / 1_000_000)
        }
        guard let timestamp else { return nil }
        return Self.isoFormatter.date(from: timestamp)
    }
}

// MARK: - Pipe

/// Reads newline-delimited JSON off a pipe, one decoded value at a time.
actor JSONLinesPipeHandler {
    nonisolated let pipe = Pipe()
    private var buffer = ""

    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async {
        let handle = pipe.fileHandleForReading
        while !Task.isCancelled {
            let data = await readData(from: handle)
            guard !data.isEmpty else { break }
            guard let chunk = String(data: data, encoding: .utf8) else { continue }

            buffer.append(chunk)
            while let range = buffer.range(of: "\n") {
                let line = String(buffer[..<range.lowerBound])
                buffer = String(buffer[range.upperBound...])
                guard !line.isEmpty, let lineData = line.data(using: .utf8) else { continue }
                // A line that will not decode is skipped rather than fatal: the
                // adapter is free to add fields, and one bad line should not end
                // the stream.
                guard let decoded = try? JSONDecoder().decode(T.self, from: lineData) else { continue }
                await onLine(decoded)
            }
        }
    }

    private func readData(from handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            handle.readabilityHandler = { handle in
                let data = handle.availableData
                handle.readabilityHandler = nil
                continuation.resume(returning: data)
            }
        }
    }

    func close() {
        pipe.fileHandleForReading.readabilityHandler = nil
        try? pipe.fileHandleForReading.close()
        try? pipe.fileHandleForWriting.close()
    }
}
