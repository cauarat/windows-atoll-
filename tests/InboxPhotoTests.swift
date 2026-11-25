import Foundation

/// Which of a Mattermost post's files is the photo on the card, and how large
/// the card draws it.
///
/// The size is the part worth pinning: the window, the card and Mochi each ask
/// for it separately, and the Windows card has to grow by the same number.
/// `--dump` writes the sizes the TypeScript twin is checked against.
@main
enum InboxPhotoTests {

    static var failures = 0

    static func check(_ label: String, _ got: String, _ expected: String) {
        if got == expected { print("  ✓ \(label)") }
        else {
            print("  ✗ \(label)")
            print("    got:      \(got)")
            print("    expected: \(expected)")
            failures += 1
        }
    }

    static func photo(_ w: Int, _ h: Int, caption: String? = nil) -> InboxPhoto {
        InboxPhoto(fileID: "abc", name: "p.jpg", mimeType: "image/jpeg",
                   pixelWidth: w, pixelHeight: h, hasPreview: true, byteCount: 1000,
                   miniPreview: nil, caption: caption, more: 0)
    }

    /// The column the card really has with Mochi beside it — 640 less the
    /// 116 and 16 gutters and the card's 10 either side.
    static func size(_ p: InboxPhoto, _ width: CGFloat = 488) -> String {
        let s = p.displaySize(maxWidth: width)
        return "\(Int(s.width))×\(Int(s.height))"
    }

    static func files(_ json: String) -> [MattermostFileInfo] {
        (try? JSONDecoder().decode([MattermostFileInfo].self, from: Data(json.utf8))) ?? []
    }

    /// Widths the card really has (with Mochi, without), and photo shapes
    /// from tiny to panorama — the rows the TypeScript twin must reproduce.
    static let widths: [CGFloat] = [488, 588]
    static let shapes: [(Int, Int)] = [
        (4032, 3024), (3024, 4032), (1920, 1080), (1080, 1920), (1000, 1000),
        (8000, 1000), (300, 200), (40, 40), (1170, 2532), (0, 0), (0, 500),
    ]

    static func dump() {
        for width in widths {
            for (w, h) in shapes {
                let s = photo(w, h).displaySize(maxWidth: width)
                print("\(w)\t\(h)\t\(Int(width))\t\(Int(s.width))\t\(Int(s.height))")
            }
        }
    }

    static func main() {
        if CommandLine.arguments.contains("--dump") { dump(); return }

        print("Which files are photos")

        check("a jpg is", "\(InboxPhoto.isPhoto(name: "a.jpg", extension: "jpg", mimeType: "image/jpeg"))", "true")
        check("HEIC from an iPhone is, whatever its case",
              "\(InboxPhoto.isPhoto(name: "IMG_1.HEIC", extension: nil, mimeType: nil))", "true")
        check("an SVG is not", "\(InboxPhoto.isPhoto(name: "logo.svg", extension: "svg", mimeType: "image/svg+xml"))", "false")
        check("a PDF is not", "\(InboxPhoto.isPhoto(name: "a.pdf", extension: "pdf", mimeType: "application/pdf"))", "false")
        check("no extension: the MIME type decides",
              "\(InboxPhoto.isPhoto(name: "pasted", extension: "", mimeType: "image/png"))", "true")
        check("…and an extension outranks a wrong MIME type",
              "\(InboxPhoto.isPhoto(name: "notes.txt", extension: "txt", mimeType: "image/png"))", "false")

        print("A post's files")

        let mixed = files("""
            [{"id":"f1","name":"spec.pdf","extension":"pdf","mime_type":"application/pdf","size":10},
             {"id":"f2","name":"IMG_2034.jpg","extension":"jpg","mime_type":"image/jpeg","size":2400000,
              "width":4032,"height":3024,"has_preview_image":true,"mini_preview":"AAEC"},
             {"id":"f3","name":"other.png","extension":"png","mime_type":"image/png","width":10,"height":10}]
            """)
        let picked = InboxPhoto.mattermost(files: mixed, caption: "olha isso")
        check("the first photo is the one shown, not the first file", picked?.fileID ?? "nil", "f2")
        check("its size comes along", "\(picked?.pixelWidth ?? 0)×\(picked?.pixelHeight ?? 0)", "4032×3024")
        check("the rest are counted", "\(picked?.more ?? -1)", "1")
        check("the caption is kept", picked?.caption ?? "nil", "olha isso")
        check("the mini preview is decoded", "\(picked?.miniPreview?.count ?? 0)", "3")
        check("no caption is nil, not empty",
              InboxPhoto.mattermost(files: mixed, caption: "")?.caption ?? "nil", "nil")
        check("a post of documents has no photo",
              "\(InboxPhoto.mattermost(files: files(#"[{"id":"f1","name":"a.pdf"}]"#), caption: "") == nil)", "true")
        let sparse = InboxPhoto.mattermost(files: files(#"[{"id":"f9","name":"x.png"}]"#), caption: "")
        check("an old server's sparse FileInfo still makes a photo", sparse?.fileID ?? "nil", "f9")
        check("…drawn at the fallback shape", sparse.map { size($0) } ?? "nil", "400×300")

        let all = InboxFile.mattermost(files: mixed)
        check("every file on the post is kept for Copy, in order, documents too",
              all.map { "\($0.fileID):\($0.name)" }.joined(separator: ","),
              "f1:spec.pdf,f2:IMG_2034.jpg,f3:other.png")
        check("…with its type and size", "\(all[0].mimeType) \(all[0].byteCount)", "application/pdf 10")
        check("…and an id that cannot go in a URL is left out",
              "\(InboxFile.mattermost(files: files(#"[{"id":"../x","name":"a.pdf"},{"id":""}]"#)).count)", "0")

        print("Ids that may go in a URL")

        check("a Mattermost id may", "\(InboxPhoto.isMattermostID("8xk3mbhq7jfo5ce6t1c4rb9kpa"))", "true")
        check("a path may not", "\(InboxPhoto.isMattermostID("../../users/me"))", "false")
        check("nothing may not", "\(InboxPhoto.isMattermostID(""))", "false")

        print("A GIF is drawn from the original")

        let gifFile = InboxPhoto(fileID: "g1", name: "dance.gif", mimeType: "image/gif",
                                 pixelWidth: 480, pixelHeight: 270, hasPreview: true,
                                 byteCount: 3_000_000, miniPreview: nil, caption: nil, more: 0)
        check("a GIF is one", "\(gifFile.isGIF)", "true")
        check("its preview is a still JPEG, so the card fetches it whole", "\(gifFile.cardShowsOriginal)", "true")
        check("a JPEG with a preview keeps the preview", "\(photo(4032, 3024).cardShowsOriginal)", "false")
        let hugeGIF = InboxPhoto(fileID: "g2", name: "huge.gif", mimeType: "image/gif",
                                 pixelWidth: 480, pixelHeight: 270, hasPreview: true,
                                 byteCount: 40_000_000, miniPreview: nil, caption: nil, more: 0)
        check("…but one past the inline limit keeps its preview", "\(hugeGIF.cardShowsOriginal)", "false")

        print("A picture written into the message")

        let giphy = "https://media0.giphy.com/media/lxxOGaDRk4f7R5TkBd/200.gif?cid=2475d0be&ep=v1_gifs_search&rid=200.gif&ct=g"
        let picker = "![Speed Wow GIF by STRAPPED!](\(giphy))"
        let found = InboxPhoto.markdownImages(in: picker)
        check("the GIF picker's Markdown is found", "\(found.count)", "1")
        check("…with its address whole, query and all", found.first?.url ?? "nil", giphy)
        check("…and its alt text", found.first?.alt ?? "nil", "Speed Wow GIF by STRAPPED!")
        check("a title after the address is allowed",
              InboxPhoto.markdownImages(in: #"![a](https://x.io/a.png "hi")"#).first?.url ?? "nil", "https://x.io/a.png")
        check("a plain link is not a picture", "\(InboxPhoto.markdownImages(in: "[a](https://x.io/a.png)").count)", "0")
        check("nor is anything but http(s)",
              "\(InboxPhoto.markdownImages(in: "![a](file:///etc/passwd) ![b](javascript:x)").count)", "0")
        check("an unclosed one is left as text", "\(InboxPhoto.markdownImages(in: "![a](https://x.io/a.png").count)", "0")
        check("two are both found, in order",
              InboxPhoto.markdownImages(in: "![a](https://x.io/1.gif) and ![b](https://x.io/2.gif)").map(\.url).joined(separator: ","),
              "https://x.io/1.gif,https://x.io/2.gif")

        let images: [String: MattermostImageInfo] = [giphy: MattermostImageInfo(width: 356, height: 200, format: "gif")]
        let post = "8xk3mbhq7jfo5ce6t1c4rb9kpa"
        let gif = InboxPhoto.mattermostImage(message: picker, postID: post, images: images, embeds: [])
        check("the picker's GIF is the photo", gif?.photo.remoteURL ?? "nil", giphy)
        check("…keyed by the post", gif?.photo.fileID ?? "nil", "img" + post)
        check("…sized by what the server measured", "\(gif?.photo.pixelWidth ?? 0)×\(gif?.photo.pixelHeight ?? 0)", "356×200")
        check("…a GIF", "\(gif?.photo.isGIF ?? false)", "true")
        check("…named by its alt text", gif?.photo.name ?? "nil", "Speed Wow GIF by STRAPPED!.gif")
        check("…with nothing written beside it", gif.map { "\($0.text ?? "nil")|\($0.photo.caption ?? "nil")" } ?? "none", "nil|nil")
        check("…drawn at its own size", gif.map { size($0.photo) } ?? "nil", "356×200")

        let worded = InboxPhoto.mattermostImage(message: "olha isso \(picker)", postID: post, images: images, embeds: [])
        check("words beside it become the caption", worded?.photo.caption ?? "nil", "olha isso")
        let unmeasured = InboxPhoto.mattermostImage(message: "![](https://x.io/p?id=3)", postID: post, images: [:], embeds: [])
        check("no format and no extension: tried, at the fallback shape",
              unmeasured.map { "\($0.photo.name) \($0.photo.mimeType.isEmpty) \(size($0.photo))" } ?? "nil", "image true 400×300")
        check("an SVG is left as text",
              "\(InboxPhoto.mattermostImage(message: "![](https://x.io/logo.svg)", postID: post, images: [:], embeds: []) == nil)", "true")
        check("…even behind an address that does not say so",
              "\(InboxPhoto.mattermostImage(message: "![](https://x.io/logo)", postID: post, images: ["https://x.io/logo": MattermostImageInfo(width: 1, height: 1, format: "svg")], embeds: []) == nil)", "true")
        check("a post id that cannot be a key gives nothing",
              "\(InboxPhoto.mattermostImage(message: picker, postID: "../x", images: images, embeds: []) == nil)", "true")
        let more = InboxPhoto.mattermostImage(message: "![a](https://x.io/1.gif)\n![b](https://x.io/2.gif)", postID: post, images: [:], embeds: [])
        check("the second picture is counted, and neither is left as text",
              more.map { "\($0.photo.remoteURL ?? "") +\($0.photo.more) \($0.text ?? "nil")" } ?? "nil", "https://x.io/1.gif +1 nil")

        let bare = "https://media.tenor.com/abc/tenor.gif"
        let linked = InboxPhoto.mattermostImage(message: "kkk \(bare)", postID: post, images: [:],
                                                embeds: [MattermostEmbed(type: "opengraph", url: "https://x.io"),
                                                         MattermostEmbed(type: "image", url: bare)])
        check("a bare link the server saw as a picture is one", linked?.photo.remoteURL ?? "nil", bare)
        check("…and the link itself is not left in the caption", linked?.text ?? "nil", "kkk")
        check("a plain message has none",
              "\(InboxPhoto.mattermostImage(message: "oi", postID: post, images: [:], embeds: []) == nil)", "true")

        print("Where it is fetched from")

        let server = URL(string: "https://chat.example.com")!
        check("through the server's image route, the address encoded whole",
              InboxPhoto.mattermostImageRoute(for: "https://x.io/a.gif?b=1&c=2", base: server)?.absoluteString ?? "nil",
              "https://chat.example.com/api/v4/image?url=https%3A%2F%2Fx.io%2Fa.gif%3Fb%3D1%26c%3D2")
        check("a server under a path keeps it",
              InboxPhoto.mattermostImageRoute(for: "https://x.io/a.gif", base: URL(string: "https://example.com/mm")!)?.absoluteString ?? "nil",
              "https://example.com/mm/api/v4/image?url=https%3A%2F%2Fx.io%2Fa.gif")
        let proxied = "https://chat.example.com/api/v4/image?url=https%3A%2F%2Fx.io%2Fa.gif"
        check("the server's own proxy address is used as it is",
              InboxPhoto.mattermostImageRoute(for: proxied, base: server)?.absoluteString ?? "nil", proxied)
        check("another of the server's own addresses still goes through the route",
              InboxPhoto.mattermostImageRoute(for: "https://chat.example.com/api/v4/users/me", base: server)?.path ?? "nil",
              "/api/v4/image")
        check("a look-alike host is not the server",
              InboxPhoto.mattermostImageRoute(for: "https://chat.example.com.evil.io/api/v4/image?url=x", base: server)?.host ?? "nil",
              "chat.example.com")
        check("nothing but http(s) is fetched",
              "\(InboxPhoto.mattermostImageRoute(for: "file:///etc/passwd", base: server) == nil)", "true")

        print("How large the card draws it")

        check("landscape stops at the height cap", size(photo(4032, 3024)), "400×300")
        check("portrait too, narrower", size(photo(3024, 4032)), "225×300")
        check("a wide one fills the width", size(photo(1920, 1080)), "488×275")
        check("never larger than the photo", size(photo(300, 200)), "300×200")
        check("a tiny one is still something to click", size(photo(40, 40)), "72×72")
        check("a panorama keeps the minimum height", size(photo(8000, 1000)), "488×72")
        check("no Mochi, more room", size(photo(1920, 1080), 588), "533×300")

        print("How much body it takes")

        let plain = photo(4032, 3024)
        check("a photo alone is its own height",
              "\(Int(plain.bodyHeight(maxWidth: 488, captionHeight: 30)))", "300")
        check("a caption adds its lines and the gap",
              "\(Int(photo(4032, 3024, caption: "oi").bodyHeight(maxWidth: 488, captionHeight: 15)))", "321")

        print("")
        if failures == 0 { print("All good.") } else { print("\(failures) failed."); exit(1) }
    }
}
