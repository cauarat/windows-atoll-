import SwiftUI
import AppKit

/// Copy, on a message card: what the sender sent, on the clipboard, ready to
/// paste anywhere — their words, their photo whole, their voice message and
/// their PDF as files. Beside Open, and drawn the way Open is.
///
/// Absent when there is nothing to copy: a card whose service has not said
/// what its file is has nothing to hand on.
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

    /// The message whose photo, audio or files are being fetched to be copied.
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

    /// Where copying this message stands, for the status drawn beside what
    /// was clicked: fetching it, just copied, or nothing to say.
    func status(for id: String) -> CopyStatus? {
        if copyingID == id { return .copying }
        if copiedID == id { return .copied }
        return nil
    }

    /// What a click on the message itself does — its words, its photo, its
    /// voice message: copy it, the same as Copy. Nil when there is nothing to
    /// copy, and while the body is saying what went wrong (`problem`), which
    /// is not the message.
    func clickToCopy(_ message: InboxMessage, unless problem: String?) -> (() -> Void)? {
        guard problem == nil, message.copyContent != nil else { return nil }
        return { [weak self] in self?.copy(message) }
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

        case .photo(let photo, let alongside):
            copyingID = message.id
            Task {
                do {
                    let file = try await InboxPhotoStore.shared.originalFile(photo, from: message.source)
                    var others: [URL] = []
                    for other in alongside {
                        others.append(try await localFile(other, from: message.source))
                    }
                    guard mine == generation else { return }
                    provider = try MessagePasteboard.writePhoto(file, caption: photo.caption, alongside: others)
                    finish(message.id, generation: mine, error: nil)
                } catch {
                    finish(message.id, generation: mine,
                           error: alongside.isEmpty ? L("Couldn't copy the photo") : L("Couldn't copy the files"))
                }
            }

        case .files(let files, let text):
            copyingID = message.id
            Task {
                do {
                    var urls: [URL] = []
                    for file in files {
                        urls.append(try await localFile(file, from: message.source))
                    }
                    guard mine == generation else { return }
                    MessagePasteboard.writeFiles(urls, text: text)
                    provider = nil
                    finish(message.id, generation: mine, error: nil)
                } catch {
                    finish(message.id, generation: mine,
                           error: files.count == 1 ? L("Couldn't copy the file") : L("Couldn't copy the files"))
                }
            }

        case .voice(let audio):
            copyingID = message.id
            Task {
                do {
                    let file = try await voiceFile(audio, from: message.source)
                    guard mine == generation else { return }
                    MessagePasteboard.writeFiles([file], text: audio.transcript.text)
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
        let file = MessageCopy.localFile(
            id: audio.storageFileID,
            name: MessageCopy.audioFileName(audio.fileName, data: data),
            in: FileManager.default.temporaryDirectory.appendingPathComponent("Notchy Audio", isDirectory: true)
        )
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        return file
    }

    // MARK: Files

    /// A file off the message, on disk under the name it was sent with —
    /// fetched the first time it is copied, and the same file after that: a
    /// service's file never changes under its id.
    private func localFile(_ file: InboxFile, from source: MessageSource) async throws -> URL {
        let local = MessageCopy.localFile(
            id: file.fileID, name: file.name,
            in: FileManager.default.temporaryDirectory.appendingPathComponent("Notchy Files", isDirectory: true)
        )
        if FileManager.default.fileExists(atPath: local.path) { return local }
        let data: Data
        switch source {
        case .mattermost:
            data = try await MattermostClient.shared.fileData(file)
        case .ato:
            data = try await AtoClient.shared.fileData(file)
        case .whatsapp:
            // WhatsApp hands the card no files.
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        try FileManager.default.createDirectory(at: local.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: local, options: .atomic)
        return local
    }
}

// MARK: - Click to copy

/// Where a copy stands, for the status beside the message.
enum CopyStatus: Equatable {
    /// The photo, audio or file is on its way down to be copied.
    case copying
    case copied
}

/// "✓ Copied", at the right of what was clicked — the words, the photo, the
/// voice message — for a moment after a copy; a spinner while the photo or
/// the audio is still coming. Copy beside Open says the same, further off.
struct CopyStatusBadge: View {
    let status: CopyStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .copying {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(hex: "#22C55E"))
                Text("Copied")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 20, minHeight: 20)
        .background(Capsule().fill(Color(hex: "#0B0C0E").opacity(0.88)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .allowsHitTesting(false)
    }
}

extension View {
    /// `CopyStatusBadge` over this view's top right corner, faded in and out.
    /// `lift` raises it by half of what it is taller than a line of 12-point
    /// text, so beside words it sits level with the first line.
    func copyStatus(_ status: CopyStatus?, inset: CGFloat = 0, lift: CGFloat = 0) -> some View {
        overlay(alignment: .topTrailing) {
            if let status {
                CopyStatusBadge(status: status)
                    .padding(inset)
                    .offset(y: -lift)
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: status)
    }
}

extension View {
    /// Clicking this copies the message — "clicou, copiou". The words
    /// brighten under the pointer so the click has somewhere to land; Copy
    /// beside Open turns to "Copied" to say it did.
    ///
    /// Does nothing when `action` is nil, so the same body draws the same
    /// for a message with nothing to copy.
    @ViewBuilder
    func copiesOnClick(_ action: (() -> Void)?) -> some View {
        if let action {
            modifier(CopiesOnClick(action: action))
        } else {
            self
        }
    }

    /// Selectable text, unless a click on it copies the whole message
    /// instead — a click cannot both start a selection and copy.
    @ViewBuilder
    func selectableUnless(_ copies: Bool) -> some View {
        if copies {
            self
        } else {
            textSelection(.enabled)
        }
    }
}

private struct CopiesOnClick: ViewModifier {
    let action: () -> Void
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { hovering = $0 }
            .brightness(hovering ? 0.22 : 0)
            .help(L("Click to copy"))
    }
}
