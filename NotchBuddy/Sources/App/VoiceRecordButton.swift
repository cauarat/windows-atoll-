import AppKit
import AVFoundation
import SwiftUI

/// The microphone in the reply bar, and the recorder it turns the bar into.
///
/// Sits to the right of the field, left of the send arrow — the gap in the
/// card where a voice note belongs, next to the thing that sends it.
///
/// Shown on exactly the same terms as the paperclip: both are "something other
/// than words", and both vanish for a source that cannot carry one. A button
/// that always fails is worse than no button.
struct VoiceRecordButton: View {
    @ObservedObject var state: AppState
    @ObservedObject private var recorder = VoiceRecorder.shared
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colour)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(recorder.isRecording ? L("Stop recording") : L("Record a voice message"))
        // The cap ran out while the card was open: the clip is finished and
        // real, and it should land in the row as if stop had been pressed.
        .onReceive(NotificationCenter.default.publisher(for: .voiceNoteFinished)) { note in
            guard let url = note.object as? URL else { return }
            stage(url)
        }
    }

    private var colour: Color {
        if recorder.isRecording { return Color(hex: "#FF8D97") }
        return Color(hex: hovering ? "#F5F6F8" : "#8E939C")
    }

    private func toggle() {
        if recorder.isRecording {
            if let url = recorder.stop() { stage(url) }
            return
        }
        Task {
            guard await recorder.start() else {
                state.replyNotice = recorder.problem
                // Asked and refused, rather than never asked: the only way
                // back is one pane, and they just clicked expecting to talk.
                if AVCaptureDevice.authorizationStatus(for: .audio) == .denied,
                   let url = VoiceRecorder.microphoneSettingsURL {
                    NSWorkspace.shared.open(url)
                }
                return
            }
            state.replyNotice = nil
        }
    }

    /// A finished clip is an attachment and nothing more special than that —
    /// same staging, same chip, same send.
    private func stage(_ url: URL) {
        ReplyAttachmentStore.attach(urls: [url], state: state)
    }
}

/// What the reply bar shows instead of the text field while recording.
///
/// Inside the bar rather than above it: nothing is staged yet, so the card is
/// still its plain height and there is no row to grow into. The field is what
/// steps aside, which costs nothing — you are not typing while you talk.
struct RecordingStrip: View {
    @ObservedObject var state: AppState
    @ObservedObject private var recorder = VoiceRecorder.shared

    var body: some View {
        HStack(spacing: 8) {
            // One dot, breathing with the room. A real meter would be a 60 Hz
            // redraw on a window whose whole claim is no CPU at rest, and it
            // would say the same thing this does: it is listening.
            Circle()
                .fill(Color(hex: "#FF8D97"))
                .frame(width: 8, height: 8)
                .scaleEffect(0.7 + 0.3 * recorder.level)
                .opacity(0.55 + 0.45 * recorder.level)
                .animation(.easeOut(duration: 0.25), value: recorder.level)

            Text(VoiceNote.durationLabel(seconds: recorder.elapsed))
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(Color(hex: "#E7E9EC"))
                .fixedSize()

            Spacer(minLength: 0)

            Button { recorder.cancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .buttonStyle(.plain)
            .help(L("Discard recording"))
        }
    }
}

// MARK: - Playing one back

/// Playback for a staged clip, so a voice note can be heard before it is sent.
///
/// One player for the whole app, holding which attachment it belongs to: a
/// second press anywhere stops the first, the same one-at-a-time discipline
/// `SoundEngine` keeps for its pool.
@MainActor
final class AttachmentPlayer: NSObject, ObservableObject {
    static let shared = AttachmentPlayer()

    @Published private(set) var playingID: UUID?

    /// A received voice message playing, by its storage id. Kept apart from
    /// `playingID` because the two are named differently — a staged clip by
    /// the UUID it was given here, a received one by the service's id.
    @Published private(set) var playingRemoteID: String?
    /// Downloading before it can play: the press has been heard.
    @Published private(set) var loadingRemoteID: String?
    /// The last one that would not load or play, so its row can say so.
    @Published private(set) var failedRemoteID: String?

    private var player: AVAudioPlayer?
    private var loadTask: Task<Void, Never>?

    private override init() { super.init() }

    /// Whether anything is coming out of the speakers — what holds the card
    /// open, the way recording does: listening is a click, not a focus.
    var isPlaying: Bool { player != nil || loadingRemoteID != nil }

    /// Where the playing clip is, 0…1, for a received one's progress bar.
    var progress: Double {
        guard let player, player.duration > 0 else { return 0 }
        return min(1, player.currentTime / player.duration)
    }

    var elapsed: TimeInterval { player?.currentTime ?? 0 }

    func toggle(_ attachment: ReplyAttachment) {
        if playingID == attachment.id { stop(); return }
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: attachment.url) else { return }
        player.delegate = self
        player.play()
        self.player = player
        playingID = attachment.id
    }

    /// Plays a received voice message, fetching it first; a second press on
    /// the same one stops it, a press on another moves on to that.
    ///
    /// From the bytes rather than a file: Ato has been seen naming MP3s
    /// `.ogg`, and `AVAudioPlayer(contentsOf:)` trusts the extension and
    /// refuses them, where reading the data sniffs what it really is.
    func toggleRemote(_ id: String, load: @escaping @MainActor () async throws -> Data) {
        if playingRemoteID == id || loadingRemoteID == id { stop(); return }
        stop()
        failedRemoteID = nil
        loadingRemoteID = id
        loadTask = Task { @MainActor [weak self] in
            let data = try? await load()
            guard let self, !Task.isCancelled, self.loadingRemoteID == id else { return }
            self.loadingRemoteID = nil
            guard let data, let player = try? AVAudioPlayer(data: data), player.play() else {
                self.failedRemoteID = id
                return
            }
            player.delegate = self
            self.player = player
            self.playingRemoteID = id
        }
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        player?.stop()
        player = nil
        playingID = nil
        playingRemoteID = nil
        loadingRemoteID = nil
    }
}

/// `nonisolated` and hopping, for the reason `VoiceRecorder`'s delegate is:
/// AVFoundation calls back on its own queue, and a `@MainActor` closure run
/// there traps at runtime rather than failing to build.
extension AttachmentPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer,
                                                 successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.stop() }
    }
}
