import Foundation

/// What a reply will and will not carry.
///
/// The intake rules are the part worth pinning: they decide what a user sees
/// refused after a drop, and they are the only place a count, a size and a
/// duplicate are weighed against each other. `--dump` writes the
/// extension-to-kind catalogue the TypeScript twin is checked against.
@main
enum ReplyAttachmentTests {

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

    static func file(_ name: String, _ bytes: Int = 1024) -> AttachmentCandidate {
        AttachmentCandidate(url: URL(fileURLWithPath: "/tmp/\(name)"), byteCount: bytes)
    }

    static func names(_ result: AttachmentIntake.Result) -> String {
        result.accepted.map(\.name).joined(separator: ",")
    }

    static func refusals(_ result: AttachmentIntake.Result) -> String {
        result.rejected.map(\.message).joined(separator: " | ")
    }

    static func main() {
        if CommandLine.arguments.contains("--dump") { dump(); return }

        print("Attachment kinds")

        check("png is an image", AttachmentKind(extension: "png").rawValue, "image")
        check("…and so is HEIC, whatever its case", AttachmentKind(extension: "HEIC").rawValue, "image")
        check("pdf stands alone", AttachmentKind(extension: "pdf").rawValue, "pdf")
        check("docx is a document", AttachmentKind(extension: "docx").rawValue, "document")
        check("a binary is just a file", AttachmentKind(extension: "zip").rawValue, "other")
        check("no extension at all", AttachmentKind(extension: "").rawValue, "other")

        print("Sizes, as a chip says them")

        check("bytes stay bytes", ReplyAttachment(url: URL(fileURLWithPath: "/tmp/a"), byteCount: 512).sizeLabel, "512 B")
        check("a kilobyte", ReplyAttachment(url: URL(fileURLWithPath: "/tmp/a"), byteCount: 2048).sizeLabel, "2.0 KB")
        check("a big one loses the decimal", ReplyAttachment(url: URL(fileURLWithPath: "/tmp/a"), byteCount: 15 * 1024 * 1024).sizeLabel, "15 MB")

        print("Intake — the ordinary case")

        let two = AttachmentIntake.accept([file("spec.pdf"), file("shot.png")], existing: [])
        check("both land", names(two), "spec.pdf,shot.png")
        check("nothing is refused", refusals(two), "")

        print("Intake — what gets turned away")

        let dupe = AttachmentIntake.accept([file("spec.pdf")], existing: two.accepted)
        check("the same file twice", refusals(dupe), "spec.pdf is already attached.")
        check("…and it does not land", names(dupe), "")

        let sameGesture = AttachmentIntake.accept([file("a.png"), file("a.png")], existing: [])
        check("the same file twice in one drop", names(sameGesture), "a.png")

        let big = AttachmentIntake.accept([file("huge.mov", 21 * 1024 * 1024)], existing: [])
        check("over the per-file ceiling", refusals(big), "huge.mov is over 20 MB.")

        let folder = AttachmentIntake.accept(
            [AttachmentCandidate(url: URL(fileURLWithPath: "/tmp/Docs"), byteCount: 0, isRegularFile: false)],
            existing: [])
        check("a folder", refusals(folder), "Docs is a folder.")

        print("Intake — the ceilings")

        let many = (1...12).map { file("f\($0).txt") }
        let capped = AttachmentIntake.accept(many, existing: [])
        check("ten at most", "\(capped.accepted.count)", "10")
        check("and says so once, not twice", refusals(capped), "That is more than 10 files.")

        // Four at 15 MB is 60 MB: the fourth is the one that cannot fit.
        let heavy = (1...4).map { file("v\($0).mov", 15 * 1024 * 1024) }
        let total = AttachmentIntake.accept(heavy, existing: [])
        check("the total ceiling holds", "\(total.accepted.count)", "3")
        check("…and names the one that broke it", refusals(total), "v4.mov would take the reply over 50 MB.")

        print("Intake — a refusal never costs an acceptance")

        let mixed = AttachmentIntake.accept([file("huge.mov", 99 * 1024 * 1024), file("fine.txt")], existing: [])
        check("the good one still lands", names(mixed), "fine.txt")

        print("Multipart — the exact bytes on the wire")

        var form = MultipartBody(boundary: "BOUND")
        form.addField(name: "channel_id", value: "c123")
        form.addFile(name: "files", filename: "a.txt",
                     mimeType: "text/plain", contents: Data("hi".utf8))
        let wire = String(decoding: form.finished(), as: UTF8.self)

        check("the whole body, byte for byte", wire,
              "--BOUND\r\n"
              + "Content-Disposition: form-data; name=\"channel_id\"\r\n\r\n"
              + "c123\r\n"
              + "--BOUND\r\n"
              + "Content-Disposition: form-data; name=\"files\"; filename=\"a.txt\"\r\n"
              + "Content-Type: text/plain\r\n\r\n"
              + "hi\r\n"
              + "--BOUND--\r\n")

        check("the content type carries the boundary", form.contentType,
              "multipart/form-data; boundary=BOUND")

        // A quote would close the header early and let the rest be read as
        // something else; a newline would end it outright.
        check("a quote in a filename", MultipartBody.escape("a\"b.txt"), "ab.txt")
        check("a newline in a filename", MultipartBody.escape("a\nb.txt"), "ab.txt")

        var binary = MultipartBody(boundary: "B")
        binary.addFile(name: "files", filename: "x.bin",
                       mimeType: "application/octet-stream",
                       contents: Data([0x00, 0xFF, 0x0D, 0x0A]))
        // The payload must appear verbatim: a NUL must not truncate it and the
        // bare CRLF inside it must not be mistaken for a part separator.
        let bytes = [UInt8](binary.finished())
        let payload: [UInt8] = [0x00, 0xFF, 0x0D, 0x0A]
        let carriesPayload = bytes.indices.contains { i in
            i + payload.count <= bytes.count && Array(bytes[i..<i + payload.count]) == payload
        }
        check("raw bytes survive untouched", carriesPayload ? "kept" : "mangled", "kept")
        check("…and the body still closes properly",
              String(decoding: binary.finished().suffix(7), as: UTF8.self), "--B--\r\n")

        print("MIME types")

        check("png", AttachmentKind.mimeType(forExtension: "PNG"), "image/png")
        check("pdf", AttachmentKind.mimeType(forExtension: "pdf"), "application/pdf")
        check("something unknown", AttachmentKind.mimeType(forExtension: "xyz"),
              "application/octet-stream")

        print("Sources — who can take a file")

        check("Mattermost can", "\(MessageSource.mattermost.supportsAttachments)", "true")
        check("ClickMassa cannot", "\(MessageSource.clickMassa.supportsAttachments)", "false")

        // A source added without an answer would not compile, but one added
        // with the wrong answer should still be visible here.
        for source in MessageSource.allCases where source.supportsAttachments {
            if !source.supportsReply {
                print("  ✗ \(source.rawValue) takes files but cannot reply")
                failures += 1
            }
        }

        print("")
        if failures == 0 { print("All reply attachment tests passed.") }
        else { print("\(failures) failure(s)."); exit(1) }
    }

    /// The catalogue the TypeScript twin is diffed against.
    static func dump() {
        for (kind, extensions) in AttachmentKind.catalogue {
            print("kind\t\(kind.rawValue)\t\(extensions.joined(separator: ","))")
        }
        print("limit\tmaxCount\t\(AttachmentLimits.maxCount)")
        print("limit\tmaxBytesPerFile\t\(AttachmentLimits.maxBytesPerFile)")
        print("limit\tmaxTotalBytes\t\(AttachmentLimits.maxTotalBytes)")
        for source in MessageSource.allCases {
            print("source\t\(source.rawValue)\t\(source.supportsAttachments)")
        }
    }
}
