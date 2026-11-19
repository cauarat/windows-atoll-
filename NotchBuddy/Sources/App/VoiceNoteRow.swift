import SwiftUI

/// A received voice message, as one line of the message card: the control
/// that plays it, that it is a voice message, how long, and how far along.
///
/// Exactly one body line tall, so a voice message keeps the card at the
/// height it has always been — this line and one of transcript are the two
/// lines the body has always had.
struct VoiceNoteRow: View {
    let audio: InboxAudio
    let source: MessageSource

    @ObservedObject private var player = AttachmentPlayer.shared

    private var playing: Bool { player.playingRemoteID == audio.storageFileID }
    private var loading: Bool { player.loadingRemoteID == audio.storageFileID }
    private var failed: Bool { player.failedRemoteID == audio.storageFileID }

    var body: some View {
        HStack(spacing: 6) {
            Button { player.toggleRemote(audio.storageFileID, load: load) } label: {
                ZStack {
                    Circle().fill(Color.white.opacity(playing ? 0.9 : 0.16))
                    if loading {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(Color(hex: playing ? "#0B0C0E" : "#E7E9EC"))
                            // The play triangle sits visually left of centre.
                            .offset(x: playing ? 0 : 0.5)
                    }
                }
                .frame(width: 15, height: 15)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(playing ? L("Pause") : L("Play"))

            Image(systemName: "waveform")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#8E939C"))

            if failed {
                Text("Couldn't load the audio")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#FF8D97"))
                    .lineLimit(1)
            } else {
                Text("Voice message")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#E7E9EC"))
                    .lineLimit(1)
                    .fixedSize()
            }

            if playing {
                // Redrawn only while it plays: nothing ticks for a card at
                // rest, or for one the island is not showing.
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    track(progress: player.progress, label: VoiceNote.durationLabel(seconds: player.elapsed))
                }
            } else {
                track(progress: 0, label: audio.duration.map { VoiceNote.durationLabel(seconds: $0) })
            }
        }
        .frame(height: MessageBodyMetrics.lineHeight)
    }

    private func track(progress: Double, label: String?) -> some View {
        HStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(Color.white.opacity(0.7))
                        .frame(width: max(0, proxy.size.width * progress))
                }
            }
            .frame(height: 3)
            .frame(maxWidth: 120)

            if let label {
                Text(label)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(Color(hex: "#6B7079"))
                    .fixedSize()
            }
            Spacer(minLength: 0)
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
