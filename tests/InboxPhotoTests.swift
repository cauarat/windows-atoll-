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
