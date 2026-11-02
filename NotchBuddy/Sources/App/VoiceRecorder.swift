import AVFoundation
import Foundation

/// Recording a voice note for a reply.
///
/// The clip is not a special kind of message: it is written to the same inbox
/// a pasted screenshot goes to, staged as an ordinary `ReplyAttachment`, and
/// sent by the send path that was already there. Nothing downstream of
/// `stop()` knows a microphone was involved — which is why this file is the
/// whole feature on the Mac and no send path was added anywhere.
///
/// The rules that have to match the Tauri build — the duration cap, the clock
/// format — live in `ReplyAttachment.swift`, which the test runners compile.
/// This is the half that touches the hardware.
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    static let shared = VoiceRecorder()

    /// Whether the bar is showing the recorder rather than the text field.
    @Published private(set) var isRecording = false
    /// Seconds so far, for the clock. Updated a few times a second, not per frame.
    @Published private(set) var elapsed: TimeInterval = 0
    /// 0…1, for the dot. Smoothed, because raw metering flickers.
    @Published private(set) var level: Double = 0
    /// Why there is no recording, in words the card shows unchanged — the same
    /// bargain `AttachmentRejection` and `MessageInbox.ReplyError` make.
    @Published var problem: String?

    private var recorder: AVAudioRecorder?
    private var ticker: Timer?
    private var url: URL?

    private override init() { super.init() }

    // MARK: - Starting

    /// Asks for the microphone, then starts. Returns false if it could not.
    ///
    /// The permission prompt is the reason this is async: the first call puts
    /// a system dialog in front of the user, and the card has to keep its
    /// draft and stay open across it.
    @discardableResult
    func start() async -> Bool {
        guard !isRecording else { return true }
        problem = nil

        guard await Self.hasMicrophonePermission() else {
            problem = L("Notchy needs permission to use the microphone.")
            return false
        }

        guard let destination = Self.newClipURL() else {
            problem = L("Could not make a file for the recording.")
            return false
        }

        do {
            let recorder = try AVAudioRecorder(url: destination, settings: Self.settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            // The cap is the recorder's own, not a timer's: a stop that depends
            // on this process staying responsive is a stop that does not happen
            // when it matters.
            guard recorder.record(forDuration: Double(AttachmentLimits.maxRecordingSeconds)) else {
                problem = L("The microphone would not start.")
                return false
            }
            self.recorder = recorder
            self.url = destination
            isRecording = true
            elapsed = 0
            level = 0
            startTicking()
            SoundEngine.shared.play("blip")
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    // MARK: - Finishing

    /// Stops and hands back the finished clip, or nil if there is nothing worth
    /// sending.
    ///
    /// A clip under half a second is a mis-click, not a message. Returning nil
    /// for it — and deleting the file — is what stops a stray tap on the mic
    /// from putting a quarter-second of room tone in front of a customer.
    @discardableResult
    func stop() -> URL? {
        guard let recorder, isRecording else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        finish()

        guard let url else { return nil }
        guard duration >= 0.5 else {
            try? FileManager.default.removeItem(at: url)
            self.url = nil
            return nil
        }
        self.url = nil
        return url
    }

    /// Throws the recording away. The file goes with it: an abandoned clip that
    /// stays on disk is a voice note nobody meant to keep.
    func cancel() {
        recorder?.stop()
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
        finish()
    }

    private func finish() {
        ticker?.invalidate()
        ticker = nil
        recorder = nil
        isRecording = false
        level = 0
    }

    // MARK: - The clock and the dot

    /// Twice a second, on the main run loop.
    ///
    /// Deliberately not a display link and deliberately not 60 Hz: the island
    /// claims no CPU at rest and is already drawing Mochi, and what this moves
    /// is one digit and one dot.
    private func startTicking() {
        let ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            // `Timer` fires on the run loop it is added to — the main one, just
            // below — so this is already where it must be. The hop is what says
            // so to the compiler, and what keeps the check honest if the
            // scheduling above is ever changed.
            Task { @MainActor [weak self] in self?.sample() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    private func sample() {
        guard let recorder, recorder.isRecording else {
            // `record(forDuration:)` ran out. The clip is finished and good;
            // the card picks it up through `isRecording` going false.
            if isRecording { stopAtCap() }
            return
        }
        recorder.updateMeters()
        elapsed = recorder.currentTime
        // dBFS, roughly -160…0. Anything under -50 is a quiet room, so the bar
        // starts there rather than showing a permanent flicker.
        let db = Double(recorder.averagePower(forChannel: 0))
        let normalised = max(0, min(1, (db + 50) / 50))
        // Eased towards the new value: the dot should breathe, not strobe.
        level += (normalised - level) * 0.4
    }

    /// The five-minute cap ran out while recording. The clip is kept — it is a
    /// real recording, just a long one — and the card stages it like any other.
    private func stopAtCap() {
        finish()
        guard let url else { return }
        self.url = nil
        NotificationCenter.default.post(name: .voiceNoteFinished, object: url)
    }

    // MARK: - Permission

    /// Whether the microphone is ours to use, asking once if nobody has.
    ///
    /// Under the hardened runtime this needs both halves to be in place —
    /// `NSMicrophoneUsageDescription` in the Info.plist and
    /// `com.apple.security.device.audio-input` in the entitlements — or the
    /// request is refused before the user ever sees a dialog.
    static func hasMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    /// The Privacy pane, for the case where the answer was no and the only way
    /// back is System Settings.
    static var microphoneSettingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    // MARK: - The file

    /// AAC in an `.m4a`.
    ///
    /// The one format AVFoundation writes natively that also carries an
    /// unambiguous audio MIME — `audio/mp4`, which matters because the panel
    /// decides what a file is from its name. macOS has no MP3 or Ogg encoder,
    /// and adding one would be a dependency this app does not take.
    ///
    /// Mono at 64 kbps: a voice note, not a recording session. Five minutes is
    /// about 2.4 MB, well inside `AttachmentLimits.maxBytesPerFile`.
    private static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]

    /// Beside the pasted screenshots, under the same stamped name, for the same
    /// reason: nothing downstream should have to care where a file came from.
    /// Seconds are in the stamp so two clips in a minute are two files.
    private static func newClipURL() -> URL? {
        let inbox = HookServer.supportDir.appendingPathComponent("inbox")
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let stamp = stampFormatter.string(from: Date())
        return inbox.appendingPathComponent("\(L("Voice message")) \(stamp).m4a")
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()
}

// MARK: - Delegate

/// `nonisolated` and hopping, because these arrive on whatever queue
/// AVFoundation feels like using. A closure written inside a `@MainActor` type
/// inherits that isolation and traps at runtime when it runs anywhere else —
/// which in this app looks like the island vanishing, not like a crash.
extension VoiceRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder,
                                                      error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor [weak self] in
            self?.problem = message ?? L("The recording failed.")
            self?.cancel()
        }
    }
}

extension Notification.Name {
    /// A recording stopped on its own, having run to the cap. Posted so the
    /// card can stage the clip without having been the one to press stop.
    static let voiceNoteFinished = Notification.Name("notchy.voiceNoteFinished")
}
