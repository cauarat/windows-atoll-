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
    /// Where the picture lives when it is not one of the post's files: one
    /// written into the message — `![Speed Wow GIF](https://media0.giphy.com/…/200.gif)`,
    /// which is what Mattermost's GIF picker sends — or a bare link to one.
    /// Nil for a file. `fileID` is then only the cache's key for it.
    var remoteURL: String? = nil

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

    /// A GIF, by its type or its name — what the list says instead of "Photo",
    /// and the one kind whose server preview cannot stand in for it.
    var isGIF: Bool {
        mimeType.lowercased() == "image/gif" || (name as NSString).pathExtension.lowercased() == "gif"
    }

    /// Whether the card is drawn from the original rather than the server's
    /// preview: when there is no preview, and for a GIF, whose preview is a
    /// still JPEG of its first frame — a GIF small enough is fetched whole, so
    /// that it moves. One whose size the server did not say keeps the preview.
    var cardShowsOriginal: Bool {
        !hasPreview || (isGIF && byteCount > 0 && byteCount <= Self.maxInlineBytes)
    }

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

extension InboxFile {
    /// Every file on a post, photos included, in the order the post lists
    /// them — what Copy hands on. One whose id could not go in an API path is
    /// left out: it could not be fetched anyway.
    static func mattermost(files: [MattermostFileInfo]) -> [InboxFile] {
        files.filter { InboxPhoto.isMattermostID($0.id) }.map {
            InboxFile(fileID: $0.id, name: $0.name ?? "", mimeType: $0.mime_type ?? "",
                      byteCount: max(0, $0.size ?? 0))
        }
    }
}

// MARK: - Pictures written into a Mattermost message

/// What the server measured of a picture a post links to — an entry of
/// `metadata.images`, keyed by the picture's address. All optional, for the
/// same reason as `MattermostFileInfo`.
struct MattermostImageInfo: Decodable, Equatable, Sendable {
    let width: Int?
    let height: Int?
    /// "gif", "png", "jpeg"… as the server's decoder named it.
    let format: String?
}

/// One of `metadata.embeds`. A bare link to a picture comes as `type: "image"`.
struct MattermostEmbed: Decodable, Equatable, Sendable {
    let type: String?
    let url: String?
}

/// A picture written into a message's text as Markdown.
struct MarkdownImage: Equatable {
    let alt: String
    let url: String
    /// Where the whole `![…](…)` sits in the text, in characters — what is
    /// taken out of it to leave what was written beside the picture.
    let start: Int
    let end: Int
}

extension InboxPhoto {
    /// Every `![alt](url)` in `text` — with an optional `"title"` after the
    /// address, as CommonMark allows — whose address is http or https.
    ///
    /// A hand-written scanner rather than a pattern, so the Rust twin
    /// (`message_proto::markdown_images`) can be the same steps, character for
    /// character. Character offsets, not string indices, for the same reason.
    static func markdownImages(in text: String) -> [MarkdownImage] {
        let chars = Array(text)
        var found: [MarkdownImage] = []
        var i = 0
        while i + 1 < chars.count {
            guard chars[i] == "!", chars[i + 1] == "[" else { i += 1; continue }
            let start = i
            // The alt text: up to the first `]`, on one line.
            var j = i + 2
            while j < chars.count, chars[j] != "]", chars[j] != "\n" { j += 1 }
            guard j + 1 < chars.count, chars[j] == "]", chars[j + 1] == "(" else { i += 2; continue }
            let alt = String(chars[(i + 2)..<j])
            j += 2
            while j < chars.count, chars[j] == " " { j += 1 }
            // The address: up to whitespace or the closing parenthesis.
            let urlStart = j
            while j < chars.count, chars[j] != ")", !chars[j].isWhitespace { j += 1 }
            let url = String(chars[urlStart..<j])
            while j < chars.count, chars[j] == " " { j += 1 }
            // An optional title, in double quotes.
            if j < chars.count, chars[j] == "\"" {
                j += 1
                while j < chars.count, chars[j] != "\"", chars[j] != "\n" { j += 1 }
                if j < chars.count, chars[j] == "\"" { j += 1 }
                while j < chars.count, chars[j] == " " { j += 1 }
            }
            guard j < chars.count, chars[j] == ")", isWebAddress(url) else { i += 2; continue }
            found.append(MarkdownImage(alt: alt.trimmingCharacters(in: .whitespaces), url: url,
                                       start: start, end: j + 1))
            i = j + 1
        }
        return found
    }

    /// http or https, with a host. Anything else is not fetched, whatever the
    /// message says.
    static func isWebAddress(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        let rest: Substring
        if lower.hasPrefix("https://") { rest = lower.dropFirst(8) }
        else if lower.hasPrefix("http://") { rest = lower.dropFirst(7) }
        else { return false }
        guard let first = rest.first else { return false }
        return first != "/" && first != "?" && first != "#"
    }

    /// The extension the address's path ends in, lowercased; "" when none.
    static func pathExtension(ofAddress raw: String) -> String {
        var path = Substring(raw)
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = path[..<cut] }
        let last = path.split(separator: "/", omittingEmptySubsequences: false).last ?? ""
        guard let dot = last.lastIndex(of: "."), dot != last.startIndex else { return "" }
        return String(last[last.index(after: dot)...]).lowercased()
    }

    /// The picture on a post that has no photo among its files: the first one
    /// written into the message as Markdown — a GIF from the picker, mostly —
    /// or, failing that, the first bare link the server recognised as one.
    /// Nil when there is none the card can draw.
    ///
    /// `text` is what was written beside it: the message with every picture
    /// taken out, trimmed — nil when the picture was all there was. It becomes
    /// the caption, and what Copy hands on.
    static func mattermostImage(message: String, postID: String,
                                images: [String: MattermostImageInfo],
                                embeds: [MattermostEmbed]) -> (photo: InboxPhoto, text: String?)? {
        guard isMattermostID(postID) else { return nil }
        let drawable: (String) -> Bool = { url in
            let ext = pathExtension(ofAddress: url)
            let format = images[url]?.format?.lowercased() ?? ""
            // Known to be something else — an SVG, mostly — is left as text.
            if !format.isEmpty { return extensions.contains(format) }
            return ext.isEmpty || extensions.contains(ext)
        }

        let chars = Array(message)
        let pictures = markdownImages(in: message).filter { drawable($0.url) }
        let url: String
        var alt = ""
        let others: Int
        let rest: String
        if let first = pictures.first {
            url = first.url
            alt = first.alt
            others = pictures.count - 1
            var kept: [Character] = []
            var at = 0
            for picture in pictures {
                kept += chars[at..<picture.start]
                at = picture.end
            }
            kept += chars[at...]
            rest = String(kept)
        } else {
            let links = embeds.compactMap { embed -> String? in
                guard embed.type == "image", let url = embed.url, isWebAddress(url), drawable(url) else { return nil }
                return url
            }
            guard let first = links.first else { return nil }
            url = first
            others = links.count - 1
            rest = message.replacingOccurrences(of: first, with: "")
        }
        let text = rest.trimmingCharacters(in: .whitespacesAndNewlines)

        let info = images[url]
        let format = (info?.format?.lowercased()).flatMap { $0.isEmpty ? nil : $0 }
        let ext = pathExtension(ofAddress: url)
        let kind = format ?? (extensions.contains(ext) ? ext : nil)
        let fileExt = kind.map { $0 == "jpeg" ? "jpg" : $0 }
        // Named by its alt text — "Speed Wow GIF by STRAPPED!" says more than
        // Giphy's "200.gif" — which is what a copy of it pastes as.
        let base = alt.isEmpty ? "image" : alt
        let photo = InboxPhoto(
            fileID: "img" + postID,
            name: fileExt.map { "\(base).\($0)" } ?? base,
            mimeType: kind.map { "image/" + ($0 == "jpg" ? "jpeg" : $0) } ?? "",
            pixelWidth: max(0, info?.width ?? 0),
            pixelHeight: max(0, info?.height ?? 0),
            hasPreview: false,
            byteCount: 0,
            miniPreview: nil,
            caption: text.isEmpty ? nil : text,
            more: max(0, others),
            remoteURL: url
        )
        return (photo, text.isEmpty ? nil : text)
    }
}

extension InboxPhoto {
    /// Where a picture written into a message is asked for first: the
    /// server's own `/api/v4/image?url=…`.
    ///
    /// That route fetches the picture through the server's image proxy when
    /// the administrator runs one, so a server that wants its users' Macs
    /// kept off Giphy keeps them off. Without a proxy, Mattermost 9.3 and later
    /// refuse the route with a 400 (MM-54477) and older ones redirect to the
    /// picture — the token is not sent along; the 400 is what
    /// `directImageURL` is for. An address that already is that route on this
    /// server — what a server with the proxy on writes into posts — is used
    /// as it is.
    static func mattermostImageRoute(for raw: String, base: URL) -> URL? {
        guard isWebAddress(raw), let target = URL(string: raw), target.host != nil else { return nil }
        if sameOrigin(target, base), target.path.hasSuffix("/api/v4/image") { return target }
        guard var route = URLComponents(url: base.appendingPathComponent("api/v4/image"),
                                        resolvingAgainstBaseURL: false),
              let encoded = raw.addingPercentEncoding(withAllowedCharacters: urlUnreserved)
        else { return nil }
        // Encoded by hand: `queryItems` leaves `&` and `=` alone, and the
        // picture's own query — Giphy's `?cid=…&rid=…` — would come apart.
        route.percentEncodedQuery = "url=" + encoded
        return route.url
    }

    /// Scheme, host and port all the same.
    static func sameOrigin(_ a: URL, _ b: URL?) -> Bool {
        guard let b else { return false }
        func port(_ url: URL) -> Int? { url.port ?? (url.scheme?.lowercased() == "http" ? 80 : 443) }
        return a.scheme?.lowercased() == b.scheme?.lowercased()
            && a.host?.lowercased() == b.host?.lowercased()
            && port(a) == port(b)
    }

    /// Where a written picture comes from when the server refuses the route:
    /// where it lives, the way Mattermost's own apps load it from a server
    /// without an image proxy. Another host only over HTTPS — and the caller
    /// sends it nothing of the session; the server itself as any request
    /// there. The route has nowhere else to go, so it has none.
    static func directImageURL(for raw: String, base: URL) -> URL? {
        guard isWebAddress(raw), let target = URL(string: raw), target.host?.isEmpty == false else {
            return nil
        }
        if sameOrigin(target, base) { return target.path.hasSuffix("/api/v4/image") ? nil : target }
        return target.scheme?.lowercased() == "https" ? target : nil
    }

    /// RFC 3986's unreserved characters: all a query value may carry as it is.
    private static let urlUnreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
