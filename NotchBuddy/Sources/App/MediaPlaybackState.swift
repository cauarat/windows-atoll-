/*
 * Notchy
 *
 * Adapted from Atoll (DynamicIsland), which is GPL v3 and itself derives this
 * file from boring.notch. See NOTICE.
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

import Foundation

enum RepeatMode: Int, Codable, Sendable {
    case off = 1
    case one = 2
    case all = 3
}

/// What is playing, wherever it is playing.
///
/// Upstream ships joke placeholders here ("I'm Handsome" by "Me"). They are
/// empty instead, because this struct is created before anything has played and
/// an empty title is the one thing the views can be trusted to hide.
struct PlaybackState: Equatable, Sendable {
    var bundleIdentifier: String
    var isPlaying: Bool = false
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var currentTime: Double = 0
    var duration: Double = 0
    var playbackRate: Double = 1
    var isShuffled: Bool = false
    var repeatMode: RepeatMode = .off
    /// The instant `currentTime` was sampled. The two are a matched pair; see
    /// the anchoring notes in `NowPlayingController`.
    var lastUpdated: Date = .distantPast
    var artwork: Data?

    var hasTrack: Bool { !title.isEmpty || !artist.isEmpty }

    /// Where playback has got to now, extrapolated from the anchor.
    ///
    /// Only while playing: wall-clock time and playback time stop agreeing the
    /// moment it pauses, and counting paused seconds as played is exactly the
    /// drift the controller works to avoid.
    func estimatedTime(at now: Date = Date()) -> Double {
        guard isPlaying, lastUpdated != .distantPast else { return currentTime }
        let advanced = currentTime + now.timeIntervalSince(lastUpdated) * playbackRate
        guard duration > 0 else { return max(0, advanced) }
        return min(max(0, advanced), duration)
    }
}
