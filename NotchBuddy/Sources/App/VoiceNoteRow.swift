import SwiftUI

/// A received voice message's player, at the top of the message card: back,
/// play and forward, and a bar to click or drag to any point of it — the Now
/// Playing card's controls, at the size of a card row.
///
/// `MessageBodyMetrics.voicePlayerHeight` tall, which is what the card is
/// grown by; the transcript scrolls underneath.
struct VoiceNoteRow: View {
    let audio: InboxAudio
    let source: MessageSource

    @ObservedObject private var player = AttachmentPlayer.shared
    @ObservedObject private var state = AppState.shared

    /// Where the thumb is while being dragged, as a fraction — the bar follows
    /// playback the rest of the time, and would snap back under the pointer.
    @State private var scrubbing: Double?

    private var id: String { audio.storageFileID }
    private var loaded: Bool { player.remoteID == id }
    private var playing: Bool { loaded && player.remotePlaying }
    private var loading: Bool { player.loadingRemoteID == id }
    private var failed: Bool { player.failedRemoteID == id }

    /// Ato's own measure until the clip is here, the clip's after.
    private var total: TimeInterval {
        loaded && player.duration > 0 ? player.duration : (audio.duration ?? 0)
    }

    var body: some View {
        HStack(spacing: 10) {
            skipButton(seconds: state.skipBackSeconds, forward: false)
            playButton
            skipButton(seconds: state.skipForwardSeconds, forward: true)

            if playing {
                // Redrawn only while it plays: nothing ticks for a paused
                // clip, a card at rest, or one the island is not showing.
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    track(position: player.elapsed)
                }
            } else {
                track(position: loaded ? player.remotePosition : 0)
            }
        }
        .frame(height: MessageBodyMetrics.voicePlayerHeight)
        // A seek on a clip not fetched yet holds the thumb where it was let
        // go until the clip is here to take the position.
        .onChange(of: player.loadingRemoteID) { _, now in
            if now == nil { scrubbing = nil }
        }
    }

    // MARK: Controls

    private var playButton: some View {
        Button { player.toggleRemote(id, load: load) } label: {
            ZStack {
                Circle().fill(Color(hex: "#F5F6F8"))
                if loading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .colorScheme(.light)
                } else {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "#0B0C0E"))
                        // The play triangle sits visually left of centre.
                        .offset(x: playing ? 0 : 1)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(playing ? L("Pause") : L("Play"))
    }

    /// The numbers SF Symbols has a dial for — the Now Playing card's set.
    private static let dialSeconds: Set<Int> = [5, 10, 15, 30, 45, 60, 75, 90]

    /// The Now Playing card's jump, with its distance written on it, and the
    /// same two settings deciding how far.
    @ViewBuilder
    private func skipButton(seconds: Int, forward: Bool) -> some View {
        let exact = Self.dialSeconds.contains(seconds)
        let name = exact
            ? (forward ? "goforward.\(seconds)" : "gobackward.\(seconds)")
            : (forward ? "goforward" : "gobackward")
        Button {
            player.skipRemote(id, by: forward ? Double(seconds) : -Double(seconds), load: load)
        } label: {
            ZStack {
                Image(systemName: name)
                    .font(.system(size: 14))
                if !exact {
                    Text("\(seconds)")
                        .font(.system(size: 7, weight: .semibold).monospacedDigit())
                        .offset(y: 1)
                }
            }
            .foregroundColor(Color(hex: "#F1F2F4"))
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(forward ? "Forward \(seconds)s" : "Back \(seconds)s")
    }

    /// The bar, and under it where you are, what this is, and how long.
    private func track(position: TimeInterval) -> some View {
        let length = max(total, 0.01)
        let fraction = scrubbing ?? min(max(position / length, 0), 1)
        return VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(Color(hex: "#F5F6F8"))
                        .frame(width: max(0, geo.size.width * fraction))
                    Circle().fill(Color(hex: "#F5F6F8"))
                        .frame(width: 9, height: 9)
                        .offset(x: max(0, min(geo.size.width - 9, geo.size.width * fraction - 4.5)))
                        .opacity(loaded || scrubbing != nil ? 1 : 0)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            scrubbing = min(max(g.location.x / max(geo.size.width, 1), 0), 1)
                        }
                        .onEnded { g in
                            let f = min(max(g.location.x / max(geo.size.width, 1), 0), 1)
                            let wasLoaded = loaded
                            player.seekRemote(id, toFraction: f, load: load)
                            if wasLoaded { scrubbing = nil }
                        }
                )
            }
            .frame(height: 12)

            HStack(spacing: 6) {
                Text(VoiceNote.durationLabel(seconds: scrubbing.map { $0 * total } ?? position))
                Spacer(minLength: 4)
                if failed {
                    Text("Couldn't load the audio")
                        .foregroundColor(Color(hex: "#FF8D97"))
                        .lineLimit(1)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                        Text("Voice message")
                    }
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(total > 0 ? VoiceNote.durationLabel(seconds: total) : "–:––")
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundColor(Color(hex: "#6B7079"))
        }
    }

    private func load() async throws -> Data {
        switch source {
        case .ato:
            return try await AtoClient.shared.voiceNoteData(audio)
        case .mattermost, .whatsapp:
            // Nothing else hands the card a voice note yet.
            throw CocoaError(.fileReadUnsupportedScheme)
        }
    }
}
