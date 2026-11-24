//
//  InboxPhoto.swift
//  Notchy
//
//  A photo on an inbox card: enough to lay it out before it has arrived,
//  fetch it, and open it whole.
//
//  Foundation only and its own file, so scripts/test-inbox-photo.sh can
//  compile it alone — the same reason InboxAudio is apart from the inbox.
//

import Foundation

struct InboxPhoto: Equatable, Sendable {
    /// The service's own id for the file — what the preview and the original
    /// are fetched by.
    let fileID: String
    let name: String
    let mimeType: String
    /// As the service measured them; zero when it did not say. Known before a
    /// byte of the photo is here, which is what lets the card be the right
    /// height from the moment it opens rather than jumping when it loads.
    let pixelWidth: Int
    let pixelHeight: Int
    /// Whether the server keeps a smaller copy for showing. Fetched instead
    /// of the original when it does: a phone photo is several megabytes, and
    /// the card is a few hundred points wide.
    let hasPreview: Bool
    /// The original's size.
    let byteCount: Int
    /// A few hundred bytes of tiny JPEG the server sends with the post, drawn
    /// blurred while the photo itself is on its way.
    let miniPreview: Data?
    /// What was written with it. Nil when the photo came alone, and then the
    /// photo is the whole message.
    let caption: String?
    /// Other photos on the same post. The card shows the first and says how
    /// many more there are; the rest are a click away in the service.
    let more: Int

    // MARK: - Which files are photos

    /// What the card can draw. Raster only: an SVG is an image to a browser
    /// and a security question to everyone else, and a PSD is not a photo.
    static let extensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff",
    ]

    /// By extension first — it is what the sender's machine named it by — and
    /// by MIME type when there is none.
    static func isPhoto(name: String, extension ext: String?, mimeType: String?) -> Bool {
        let own = (ext?.isEmpty == false ? ext! : (name as NSString).pathExtension).lowercased()
        if !own.isEmpty { return extensions.contains(own) }
        guard let mime = mimeType?.lowercased(), mime.hasPrefix("image/") else { return false }
        return extensions.contains(String(mime.dropFirst("image/".count)))
    }

    /// The most fetched to show a photo the server made no preview of. Past
    /// this the card keeps its placeholder: a 40 MB TIFF is not worth a
    /// notification's bandwidth, and the click still opens it.
    static let maxInlineBytes = 25 * 1024 * 1024

    /// Whether the card fetches anything at all.
    var canShowInline: Bool { hasPreview || byteCount <= Self.maxInlineBytes }

    // MARK: - Layout

    /// The tallest a photo gets on the card. Tall enough to see what it is
    /// without opening it, short enough that the card stays a notification:
    /// with the rows around it the island is about 430 high, well inside the
    /// 650 the ChatGPT view already takes.
    static let maxHeight: CGFloat = 300
    /// The shortest, so a panorama is still something to click.
    static let minHeight: CGFloat = 72
    /// Between the photo and what was written with it.
    static let captionGap: CGFloat = 6
    /// The shape assumed when the service gave no size: a phone held sideways.
    static let fallbackAspect: CGFloat = 4.0 / 3.0

    /// The box the photo is drawn in on a card `maxWidth` wide.
    ///
    /// Whole points, so the window, the card and Mochi — each of which asks
    /// separately — get the same number. Never larger than the photo itself
    /// at one point a pixel: a small image blown up to fill the card looks
    /// broken rather than bigger.
    func displaySize(maxWidth: CGFloat) -> CGSize {
        let known = pixelWidth > 0 && pixelHeight > 0
        let aspect = known ? CGFloat(pixelWidth) / CGFloat(pixelHeight) : Self.fallbackAspect
        var height = min(Self.maxHeight, maxWidth / aspect)
        if known { height = min(height, CGFloat(pixelHeight)) }
        height = max(height, Self.minHeight)
        let width = min(maxWidth, height * aspect)
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    /// How much of the card's body the photo and its caption take, given how
    /// tall the caption measures. The card's own two lines are not taken off
    /// here; `MessageBodyMetrics.overflow` does that.
    func bodyHeight(maxWidth: CGFloat, captionHeight: CGFloat) -> CGFloat {
        let picture = displaySize(maxWidth: maxWidth).height
        guard let caption, !caption.isEmpty else { return picture }
        return picture + Self.captionGap + captionHeight
    }
}

// MARK: - Mattermost

/// One of a post's files, as `metadata.files` carries it — Mattermost's
/// `FileInfo`. Every field but the id is optional: servers have added them
/// over the years, and a missing one must cost the photo, not the message.
struct MattermostFileInfo: Decodable, Equatable, Sendable {
    let id: String
    let name: String?
    let `extension`: String?
    let size: Int?
    let mime_type: String?
    let width: Int?
    let height: Int?
    let has_preview_image: Bool?
    /// Base64 in the JSON.
    let mini_preview: String?
}

extension InboxPhoto {
    /// The first photo among a post's files, or nil when none is one.
    ///
    /// `caption` is the post's own text, already trimmed; empty means none.
    static func mattermost(files: [MattermostFileInfo], caption: String) -> InboxPhoto? {
        let photos = files.filter {
            !$0.id.isEmpty && isPhoto(name: $0.name ?? "", extension: $0.extension, mimeType: $0.mime_type)
        }
        guard let first = photos.first else { return nil }
        return InboxPhoto(
            fileID: first.id,
            name: first.name ?? "photo",
            mimeType: first.mime_type ?? "",
            pixelWidth: max(0, first.width ?? 0),
            pixelHeight: max(0, first.height ?? 0),
            hasPreview: first.has_preview_image ?? false,
            byteCount: max(0, first.size ?? 0),
            miniPreview: first.mini_preview.flatMap { Data(base64Encoded: $0) },
            caption: caption.isEmpty ? nil : caption,
            more: photos.count - 1
        )
    }

    /// Whether `id` is something that can go in a Mattermost API path as it
    /// is. Their ids are 26 lowercase letters and digits; anything else came
    /// from somewhere it should not have.
    static func isMattermostID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
        }
    }
}
