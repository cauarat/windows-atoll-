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
    /// Copies the message — what a click on the photo does when there is
    /// something to copy. Seeing it full size then moves to the enlarge mark
    /// in its corner; with nothing to copy, a click opens it, as it always did.
    var onCopy: (() -> Void)? = nil
    /// Where copying it stands, said in the corner the enlarge mark uses —
    /// which steps aside meanwhile.
    var copyStatus: CopyStatus? = nil
    /// Whether a GIF plays. Only while the card is on screen: the island
    /// builds every view at once, and one playing behind a hidden island
    /// would be the CPU it must not use. Held on its frame otherwise.
    var animates: Bool = false

    @ObservedObject private var store = InboxPhotoStore.shared
    @State private var hovering = false

    private static let corner: CGFloat = 10

    var body: some View {
        let size = photo.displaySize(maxWidth: maxWidth)
        Button {
            if let onCopy { onCopy() } else { store.openFull(photo, from: source) }
        } label: {
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
        // Its own button, over the photo rather than inside it: a click on
        // the photo copies, and this is where seeing it whole went.
        .overlay(alignment: .topTrailing) {
            if onCopy != nil, copyStatus == nil { enlarge }
        }
        .copyStatus(copyStatus, inset: 6)
        .onHover { hovering = $0 }
        .help(onCopy != nil ? L("Click to copy") : L("Click to see it full size"))
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
        if let animation = store.animation(photo.fileID) {
            // Redrawn when the frame changes and not between: the shortest
            // frame is how often that can be.
            TimelineView(.animation(minimumInterval: animation.shortestDelay, paused: !animates)) { timeline in
                Image(decorative: animation.frame(at: timeline.date), scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
        } else if let image = store.image(photo.fileID) {
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
                            } else if onCopy != nil {
                                Text("Click to copy")
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
                // With Copy on the photo, the mark is a button of its own,
                // drawn over the photo by `enlarge`.
                if onCopy != nil {
                    EmptyView()
                } else if store.isOpening(photo.fileID) {
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

    /// The enlarge mark as a button: the original, in whatever the Mac opens
    /// images with. Shown under the pointer, while the original is on its
    /// way, and whenever there is no photo drawn to copy from.
    private var enlarge: some View {
        let id = photo.fileID
        let shown = store.isOpening(id) || hovering
            || (store.image(id) == nil && (store.failed(id) || !photo.canShowInline))
        return Button { store.openFull(photo, from: source) } label: {
            badge {
                if store.isOpening(id) {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(L("See it full size"))
        .padding(6)
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
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
    /// The frames of the ones that move; `images` holds their first.
    @Published private var animations: [String: InboxAnimation] = [:]
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
    func animation(_ id: String) -> InboxAnimation? { animations[id] }
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
                    Self.decodeShown(data, maxPixel: Self.maxPixel)
                }.value
                guard let decoded else { throw CocoaError(.fileReadCorruptFile) }
                keep(decoded.still, animation: decoded.animation, for: id)
                // A picture written into a message has no preview: what was
                // just fetched is the original, and opening or copying it
                // need not fetch it again.
                if photo.remoteURL != nil { Self.keepOriginal(data, of: photo) }
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

    private func keep(_ image: CGImage, animation: InboxAnimation? = nil, for id: String) {
        images[id] = image
        animations[id] = animation
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        while order.count > Self.kept {
            let gone = order.removeLast()
            images[gone] = nil
            animations[gone] = nil
        }
    }

    private static func keepOriginal(_ data: Data, of photo: InboxPhoto) {
        let file = localURL(for: photo)
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
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

    /// Where the original goes: under the file's own name — what a copy of it
    /// pastes into Finder as — in a folder named by its id, so two photos
    /// both called `image.png` do not open as one.
    private static func localURL(for photo: InboxPhoto) -> URL {
        var name = (photo.name as NSString).lastPathComponent
            .replacingOccurrences(of: ":", with: "-")
        if name.isEmpty || name.hasPrefix(".") { name = "photo" + name }
        if (name as NSString).pathExtension.isEmpty {
            let ext = photo.mimeType.lowercased().hasPrefix("image/")
                ? String(photo.mimeType.dropFirst("image/".count)) : "jpg"
            name += "." + (ext == "jpeg" ? "jpg" : ext)
        }
        return MessageCopy.localFile(
            id: photo.fileID, name: name,
            in: FileManager.default.temporaryDirectory.appendingPathComponent("Notchy Photos", isDirectory: true),
            fallback: "photo.jpg"
        )
    }

    /// What the card draws: the still, and every frame when there is more
    /// than one — a GIF, or an animated PNG or WebP. Only those: a scanned
    /// TIFF's pages and a HEIC's extra images are not frames, and the card
    /// shows the first as it always did.
    nonisolated static func decodeShown(_ data: Data, maxPixel: Int)
        -> (still: CGImage, animation: InboxAnimation?)? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           CGImageSourceGetCount(source) > 1,
           let type = CGImageSourceGetType(source) as String?,
           InboxAnimation.types.contains(type),
           let animation = InboxAnimation.decode(source) {
            return (animation.frames[0], animation)
        }
        return decode(data, maxPixel: maxPixel).map { ($0, nil) }
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
              let shown = Self.decodeShown(data, maxPixel: Self.maxPixel)
        else { return }
        var width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        var height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        // Orientations 5–8 are a quarter turn: the server reports the photo
        // as it is shown, so the seed does too.
        if let turn = props[kCGImagePropertyOrientation] as? Int, turn >= 5 { swap(&width, &height) }
        let id = "seedphoto0000000000000000000"
        let name = (path as NSString).lastPathComponent
        let photo = InboxPhoto(
            fileID: id, name: name,
            mimeType: (name as NSString).pathExtension.lowercased() == "gif" ? "image/gif" : "image/jpeg",
            pixelWidth: width, pixelHeight: height, hasPreview: true, byteCount: data.count,
            miniPreview: nil, caption: caption?.isEmpty == false ? caption : nil, more: 0
        )
        keep(shown.still, animation: shown.animation, for: id)
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

// MARK: - Pictures that move

/// A GIF — or an animated PNG or WebP — on the card: every frame, decoded
/// once and off the main thread, and how long each one stays.
///
/// Played by `InboxPhotoView` from a `TimelineView` that only ticks when a
/// frame changes, and only while the card is on screen.
struct InboxAnimation: Sendable {
    let frames: [CGImage]
    /// Seconds, one per frame.
    let delays: [Double]
    /// How many times it plays; 0 is for ever, which is what nearly every
    /// GIF asks for.
    let loops: Int
    /// When it started playing: it starts from its first frame, not from
    /// wherever the clock happens to be in its loop.
    let start: Date

    let duration: Double
    let shortestDelay: Double

    init(frames: [CGImage], delays: [Double], loops: Int, start: Date = Date()) {
        self.frames = frames
        self.delays = delays
        self.loops = loops
        self.start = start
        duration = delays.reduce(0, +)
        shortestDelay = delays.min() ?? 0.1
    }

    /// The frame on screen at `date`.
    func frame(at date: Date) -> CGImage {
        frames[Self.index(at: date.timeIntervalSince(start), delays: delays, duration: duration, loops: loops)]
    }

    nonisolated static func index(at elapsed: Double, delays: [Double], duration: Double, loops: Int) -> Int {
        guard delays.count > 1, duration > 0 else { return 0 }
        // Played out: held on the last frame, as a browser does.
        if loops > 0, elapsed >= duration * Double(loops) { return delays.count - 1 }
        var into = max(0, elapsed).truncatingRemainder(dividingBy: duration)
        for (index, delay) in delays.enumerated() {
            if into < delay { return index }
            into -= delay
        }
        return delays.count - 1
    }

    /// The formats whose several images are frames to play, by ImageIO's
    /// type identifier.
    nonisolated static let types: Set<String> = ["com.compuserve.gif", "public.png", "org.webmproject.webp"]

    /// At most this many frames; a longer one plays its first this many.
    nonisolated static let maxFrames = 400
    /// Every frame together holds no more pixels than this — 32 MB — so a
    /// long GIF is kept smaller rather than a short one blurrier.
    nonisolated static let pixelBudget = 8_000_000
    /// The longest side a frame is kept at: the tallest the card draws, at 2x.
    nonisolated static let maxPixel = 600

    /// How long a frame stays, as a browser reads it: a delay of 10 ms or
    /// less — which old encoders wrote meaning "as fast as you can" — is
    /// 100 ms, so the GIF plays at the speed everyone else sees it at.
    nonisolated static func browserDelay(_ seconds: Double?) -> Double {
        guard let seconds, seconds > 0.0105 else { return 0.1 }
        return seconds
    }

    /// Every frame of a picture that has more than one, scaled to fit both
    /// `maxPixel` and the budget, and drawn whole — composited by ImageIO and
    /// decoded here, so the main thread only ever shows a ready bitmap.
    nonisolated static func decode(_ source: CGImageSource) -> InboxAnimation? {
        let count = min(CGImageSourceGetCount(source), maxFrames)
        guard count > 1 else { return nil }
        let side = max(64, min(maxPixel, Int((Double(pixelBudget) / Double(count)).squareRoot())))

        var frames: [CGImage] = []
        var delays: [Double] = []
        frames.reserveCapacity(count)
        delays.reserveCapacity(count)
        for index in 0..<count {
            guard let full = CGImageSourceCreateImageAtIndex(source, index, nil),
                  let frame = redraw(full, side: side) else { return nil }
            frames.append(frame)
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            delays.append(browserDelay(delay(in: properties)))
        }
        let container = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        return InboxAnimation(frames: frames, delays: delays, loops: loopCount(in: container))
    }

    private nonisolated static func delay(in properties: [CFString: Any]?) -> Double? {
        let found: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
        ]
        for (dictionary, unclamped, clamped) in found {
            guard let values = properties?[dictionary] as? [CFString: Any] else { continue }
            if let seconds = values[unclamped] as? Double, seconds > 0 { return seconds }
            return values[clamped] as? Double
        }
        return nil
    }

    private nonisolated static func loopCount(in properties: [CFString: Any]?) -> Int {
        let found: [(CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFLoopCount),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGLoopCount),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPLoopCount),
        ]
        for (dictionary, key) in found {
            if let values = properties?[dictionary] as? [CFString: Any] {
                return max(0, values[key] as? Int ?? 0)
            }
        }
        return 0
    }

    /// `image` as a plain bitmap no longer than `side` on its long side.
    private nonisolated static func redraw(_ image: CGImage, side: Int) -> CGImage? {
        let long = max(image.width, image.height)
        let scale = long > side ? Double(side) / Double(long) : 1
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
