import SwiftUI
import AppKit
import ImageIO

/// A received photo, on the message card: the picture itself, drawn as large
/// as `InboxPhoto.displaySize` allows, and the original a click away.
///
/// The frame always spans the card's whole width, so its edges line up with
/// the caption and the reply bar under it; a photo narrower than that — any
/// portrait one — sits in the middle over a blurred copy of itself.
///
/// The card has been grown for it before it loads — the size comes with the
/// message — so arriving never moves anything; the blurred thumbnail the
/// server sends with the post stands in until then.
struct InboxPhotoView: View {
    let photo: InboxPhoto
    let source: MessageSource
    /// A reply that failed. Said over the foot of the photo rather than in a
    /// row of its own, so the card does not change height to say it.
    var failure: String? = nil
    let maxWidth: CGFloat

    @ObservedObject private var store = InboxPhotoStore.shared
    @State private var hovering = false

    private static let corner: CGFloat = 10

    var body: some View {
        let size = photo.displaySize(maxWidth: maxWidth)
        Button { store.openFull(photo, from: source) } label: {
            ZStack {
                Color.white.opacity(0.06)
                backdrop(size)
                picture(size)
                corners
                if let foot = failure ?? store.openFailure(photo.fileID) {
                    footNote(foot)
                }
            }
            .frame(width: maxWidth, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(hovering ? 0.22 : 0.08), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(L("Click to see it full size"))
        .frame(maxWidth: .infinity, alignment: .leading)
        // Normally already asked for when the message arrived; this is for a
        // photo the cache has since let go of.
        .task(id: photo.fileID) { store.load(photo, from: source) }
    }

    /// What fills the frame either side of a photo narrower than the card: the
    /// photo itself, or the server's thumbnail until it is here, blown up,
    /// blurred and darkened — so the frame reads as the photo's, not as an
    /// empty box with a picture in one corner.
    @ViewBuilder
    private func backdrop(_ size: CGSize) -> some View {
        let fills = size.width >= maxWidth
        if let image = store.image(photo.fileID), !fills {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: maxWidth, height: size.height)
                .blur(radius: 18, opaque: true)
                .overlay(Color.black.opacity(0.35))
                .clipped()
        } else if store.image(photo.fileID) == nil, let mini = miniPreview {
            Image(nsImage: mini)
                .resizable()
                .scaledToFill()
                .frame(width: maxWidth, height: size.height)
                .blur(radius: 12, opaque: true)
                .overlay(Color.black.opacity(0.2))
                .clipped()
        }
    }

    @ViewBuilder
    private func picture(_ size: CGSize) -> some View {
        if let image = store.image(photo.fileID) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            ZStack {
                if store.failed(photo.fileID) || !photo.canShowInline {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                        Group {
                            if store.failed(photo.fileID) {
                                Text("Couldn't load the photo")
                            } else {
                                Text("Click to see it full size")
                            }
                        }
                        .font(.system(size: 11))
                        .multilineTextAlignment(.center)
                    }
                    .foregroundColor(Color(hex: "#8E939C"))
                    .padding(.horizontal, 10)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    /// The enlarge mark while the pointer is on it — or the spinner while the
    /// original is on its way — and how many more photos the post holds.
    private var corners: some View {
        VStack {
            HStack {
                Spacer()
                if store.isOpening(photo.fileID) {
                    badge { ProgressView().controlSize(.mini) }
                } else if hovering {
                    badge {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
            }
            Spacer()
            if photo.more > 0 {
                HStack {
                    Spacer()
                    badge {
                        Text(verbatim: "+\(photo.more)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
            }
        }
        .padding(6)
    }

    private func badge<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundColor(Color(hex: "#F5F6F8"))
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(Capsule().fill(Color.black.opacity(0.55)))
    }

    private func footNote(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#FF8D97"))
                .lineLimit(2)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.7))
        }
    }

    private var miniPreview: NSImage? {
        photo.miniPreview.flatMap { NSImage(data: $0) }
    }
}

// MARK: - Store

/// The photos the cards are showing, fetched once and kept for the few most
/// recent — a card goes back and forth between messages, and fetching the
/// same preview again each time would be slow and rude to the server.
///
/// Decoded off the main thread, and down to the size a card can show: a
/// phone's preview is still a couple of thousand pixels across, and the card
/// is a few hundred points wide.
@MainActor
final class InboxPhotoStore: ObservableObject {
    static let shared = InboxPhotoStore()

    @Published private var images: [String: CGImage] = [:]
    @Published private var loading: Set<String> = []
    @Published private var failures: Set<String> = []
    @Published private var opening: Set<String> = []
    @Published private var openFailures: [String: String] = [:]

    /// Most recent first; what falls off the end is let go.
    private var order: [String] = []
    private static let kept = 8
    /// The longest side kept: the tallest the card draws, at 2×, with room.
    nonisolated private static let maxPixel = 1200

    private init() {}

    func image(_ id: String) -> CGImage? { images[id] }
    func failed(_ id: String) -> Bool { failures.contains(id) }
    func isOpening(_ id: String) -> Bool { opening.contains(id) }
    func openFailure(_ id: String) -> String? { openFailures[id] }

    /// Fetches the card's copy, unless it is here or on its way. Safe to call
    /// as often as anything likes.
    func load(_ photo: InboxPhoto, from source: MessageSource) {
        let id = photo.fileID
        guard images[id] == nil, !loading.contains(id), photo.canShowInline else { return }
        loading.insert(id)
        failures.remove(id)
        Task {
            defer { loading.remove(id) }
            do {
                let data = try await Self.fetch(photo, from: source, original: false)
                let decoded = await Task.detached(priority: .userInitiated) {
                    Self.decode(data, maxPixel: Self.maxPixel)
                }.value
                guard let decoded else { throw CocoaError(.fileReadCorruptFile) }
                keep(decoded, for: id)
            } catch {
                failures.insert(id)
            }
        }
    }

    /// The original, in whatever the Mac opens images with. Kept in the
    /// temporary folder rather than memory: it may be tens of megabytes, and
    /// the app that shows it needs a file anyway.
    func openFull(_ photo: InboxPhoto, from source: MessageSource) {
        let id = photo.fileID
        guard !opening.contains(id) else { return }
        openFailures[id] = nil
        let file = Self.localURL(for: photo)
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.open(file)
            return
        }
        opening.insert(id)
        Task {
            defer { opening.remove(id) }
            do {
                NSWorkspace.shared.open(try await originalFile(photo, from: source))
            } catch {
                openFailures[id] = L("Couldn't open the photo")
            }
        }
    }

    /// The original on disk, fetched the first time it is asked for — what
    /// opening the photo and copying it both hand on.
    func originalFile(_ photo: InboxPhoto, from source: MessageSource) async throws -> URL {
        let file = Self.localURL(for: photo)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        let data = try await Self.fetch(photo, from: source, original: true)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        return file
    }

    private func keep(_ image: CGImage, for id: String) {
        images[id] = image
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        while order.count > Self.kept {
            images[order.removeLast()] = nil
        }
    }

    private static func fetch(_ photo: InboxPhoto, from source: MessageSource,
                              original: Bool) async throws -> Data {
        switch source {
        case .mattermost:
            return try await MattermostClient.shared.photoData(photo, original: original)
        case .ato, .whatsapp:
            // Nothing else hands the card a photo yet.
            throw CocoaError(.fileReadUnsupportedScheme)
        }
    }

    /// Where the original goes: the file's own name, behind the start of its
    /// id so two photos both called `image.png` do not open as one.
    private static func localURL(for photo: InboxPhoto) -> URL {
        var name = (photo.name as NSString).lastPathComponent
            .replacingOccurrences(of: ":", with: "-")
        if name.isEmpty || name.hasPrefix(".") { name = "photo" + name }
        if (name as NSString).pathExtension.isEmpty {
            let ext = photo.mimeType.lowercased().hasPrefix("image/")
                ? String(photo.mimeType.dropFirst("image/".count)) : "jpg"
            name += "." + (ext == "jpeg" ? "jpg" : ext)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("Notchy Photos", isDirectory: true)
            .appendingPathComponent("\(photo.fileID.prefix(8))-\(name)")
    }

    /// Down to `maxPixel` on the long side, turned the way the camera meant.
    nonisolated static func decode(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    #if DEBUG
    /// `NOTCHY_SEED_PHOTO=/path/to/image` puts a photo on the Mattermost card
    /// without a server: there is no other way to look at one here. The
    /// image goes straight into the cache under an id no server would send.
    func seedForPreview(path: String, caption: String?) {
        guard let data = FileManager.default.contents(atPath: path),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let image = Self.decode(data, maxPixel: Self.maxPixel)
        else { return }
        var width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        var height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        // Orientations 5–8 are a quarter turn: the server reports the photo
        // as it is shown, so the seed does too.
        if let turn = props[kCGImagePropertyOrientation] as? Int, turn >= 5 { swap(&width, &height) }
        let id = "seedphoto0000000000000000000"
        let photo = InboxPhoto(
            fileID: id, name: (path as NSString).lastPathComponent, mimeType: "image/jpeg",
            pixelWidth: width, pixelHeight: height, hasPreview: true, byteCount: data.count,
            miniPreview: nil, caption: caption?.isEmpty == false ? caption : nil, more: 0
        )
        keep(image, for: id)
        // Where `openFull` looks first, so a click on the seed opens it too.
        let original = Self.localURL(for: photo)
        try? FileManager.default.createDirectory(at: original.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: original, options: .atomic)
        MessageInbox.shared.ingest(InboxMessage(
            id: "seed-photo-\(Int(Date().timeIntervalSince1970))",
            source: .mattermost, kind: .directMessage, sender: "maria.eduarda",
            channel: nil, conversationID: nil, body: MattermostClient.cardBody(for: photo),
            timestamp: Date(), link: nil, photo: photo, text: photo.caption
        ))
        NotificationCenter.default.post(name: .showMessageCard, object: nil)
    }
    #endif
}
