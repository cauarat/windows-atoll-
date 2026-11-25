import SwiftUI
import AppKit

/// Copy, on a message card: what the sender sent, on the clipboard, ready to
/// paste anywhere — their words, their photo whole, their voice message as a
/// file. Beside Open, and drawn the way Open is.
///
/// Absent when there is nothing to copy: a card that only says a file came
/// has no file to hand on.
struct CopyMessageButton: View {
    let message: InboxMessage

    @ObservedObject private var copier = MessageCopier.shared

    var body: some View {
        let busy = copier.copyingID == message.id
        let done = copier.copiedID == message.id
        Button { copier.copy(message) } label: {
            ZStack {
                // Sized by the wider of its two faces, so the reply bar beside
                // it does not twitch when "Copy" turns into "Copied".
                copied.hidden()
                Text("Copy").hidden()
                if busy {
                    ProgressView().controlSize(.mini)
                } else if done {
                    copied
                } else {
                    Text("Copy")
                }
            }
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Color.white.opacity(0.09))
            .foregroundColor(Color(hex: "#F1F2F4"))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .help(L("Copy exactly what was sent, to paste anywhere"))
    }

    private var copied: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
            Text("Copied")
        }
    }
}

// MARK: - Putting it on the clipboard

/// The one place a message goes onto the clipboard, and what the button
/// shows meanwhile.
///
/// Shared, so the pop-up and Home — which can show the same message — agree
/// on whether it was just copied. Only the newest copy lands: a photo still
/// downloading when something else is copied does not then overwrite it.
@MainActor
final class MessageCopier: ObservableObject {
    static let shared = MessageCopier()

    /// The message whose photo or audio is being fetched to be copied.
    @Published private(set) var copyingID: String?
    /// The message just copied — the button says so for a moment.
    @Published private(set) var copiedID: String?
    /// Why the last copy failed, for the card to say in the body's place the
    /// way it says a reply failed.
    @Published private(set) var failure: (id: String, reason: String)?

    private var generation = 0
    private var settle: Task<Void, Never>?
    /// Kept for as long as the clipboard may still ask it for the photo as
    /// TIFF or PNG. Replaced by the next copy, which empties the clipboard.
    private var provider: PhotoPasteProvider?

    private init() {}

    func failure(for id: String) -> String? {
        failure?.id == id ? failure?.reason : nil
    }

    func copy(_ message: InboxMessage) {
        guard let content = message.copyContent else { return }
        generation += 1
        let mine = generation
        settle?.cancel()
        copiedID = nil
        failure = nil

        switch content {
        case .text(let text):
            MessagePasteboard.writeText(text)
            provider = nil
            finish(message.id, generation: mine, error: nil)

        case .photo(let photo):
            copyingID = message.id
            Task {
                do {
                    let file = try await InboxPhotoStore.shared.originalFile(photo, from: message.source)
                    guard mine == generation else { return }
                    provider = try MessagePasteboard.writePhoto(file, caption: photo.caption)
                    finish(message.id, generation: mine, error: nil)
                } catch {
                    finish(message.id, generation: mine, error: L("Couldn't copy the photo"))
                }
            }

        case .voice(let audio):
            copyingID = message.id
            Task {
                do {
                    let file = try await voiceFile(audio, from: message.source)
                    guard mine == generation else { return }
                    MessagePasteboard.writeFile(file, text: audio.transcript.text)
                    provider = nil
                    finish(message.id, generation: mine, error: nil)
                } catch {
                    finish(message.id, generation: mine, error: L("Couldn't copy the audio"))
                }
            }
        }
    }

    private func finish(_ id: String, generation mine: Int, error: String?) {
        guard mine == generation else { return }
        copyingID = nil
        if let error {
            failure = (id, error)
        } else {
            copiedID = id
            SoundEngine.shared.play("blip")
        }
        settle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(error == nil ? 1.6 : 4))
            guard !Task.isCancelled, let self, self.generation == mine else { return }
            self.copiedID = nil
            self.failure = nil
        }
    }

    // MARK: The voice message

    /// The audio, fetched the way the card's player fetches it, written to the
    /// temporary folder under the name it was sent with — corrected to what
    /// it really is.
    private func voiceFile(_ audio: InboxAudio, from source: MessageSource) async throws -> URL {
        let data: Data
        switch source {
        case .ato:
            data = try await AtoClient.shared.voiceNoteData(audio)
        case .mattermost, .whatsapp:
            // Nothing else hands the card a voice message yet.
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let name = MessageCopy.audioFileName(audio.fileName, data: data)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("Notchy Audio", isDirectory: true)
            .appendingPathComponent("\(MessageCopy.safeFileName(String(audio.storageFileID.prefix(8))))-\(name)")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        return file
    }
}
