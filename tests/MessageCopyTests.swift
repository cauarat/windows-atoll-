import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Copy on a message card: what it copies, what the files it writes are
/// called, and what an app pasting them finds on the clipboard.
///
/// The clipboard half writes to a pasteboard of its own, never the user's.
/// `--dump` writes the rule the TypeScript twin is checked against.
@main
enum MessageCopyTests {

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

    static let photo = InboxPhoto(fileID: "abc", name: "IMG_1.jpg", mimeType: "image/jpeg",
                                  pixelWidth: 40, pixelHeight: 20, hasPreview: true, byteCount: 1000,
                                  miniPreview: nil, caption: "boleto em anexo", more: 0)
    static let audio = InboxAudio(attachmentID: "a1", storageFileID: "s1", fileName: "audio.ogg",
                                  contentType: "audio/ogg", duration: 3, transcript: .ready("oi"))

    /// The photo's and the voice note's own entries in the message's files,
    /// as the services list them — and two files the card does not draw.
    static let photoFile = InboxFile(fileID: "abc", name: "IMG_1.jpg", mimeType: "image/jpeg", byteCount: 1000)
    static let audioFile = InboxFile(fileID: "s1", name: "audio.ogg", mimeType: "audio/ogg", byteCount: 5120)
    static let pdf = InboxFile(fileID: "f1", name: "boleto.pdf", mimeType: "application/pdf", byteCount: 80213)
    static let sheet = InboxFile(fileID: "f2", name: "notas.xlsx",
                                 mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                                 byteCount: 9000)

    /// The message's files: the photo's and the voice note's own when there
    /// is one, then `extra` of the others.
    static func files(photo: Bool, audio: Bool, extra: Int) -> [InboxFile] {
        (photo ? [photoFile] : []) + (audio ? [audioFile] : []) + Array([pdf, sheet].prefix(extra))
    }

    static func copy(_ text: String?, _ photo: InboxPhoto?, _ audio: InboxAudio?,
                     _ files: [InboxFile] = []) -> MessageCopy? {
        MessageCopy.content(text: text, photo: photo, audio: audio, files: files)
    }

    static func kind(_ text: String?, _ photo: InboxPhoto?, _ audio: InboxAudio?,
                     _ files: [InboxFile] = []) -> String {
        copy(text, photo, audio, files)?.kind ?? "none"
    }

    /// Every combination the card can hold — the rows the TypeScript twin
    /// must answer the same way: what it copies, and how many files.
    static let texts: [String?] = [nil, "", "  \n", "G-569619"]

    static func dump() {
        for text in texts {
            for hasPhoto in [false, true] {
                for hasAudio in [false, true] {
                    for extra in 0...2 {
                        let encoded = text.map { $0.replacingOccurrences(of: "\n", with: "\\n") } ?? "<nil>"
                        let content = copy(text, hasPhoto ? photo : nil, hasAudio ? audio : nil,
                                           files(photo: hasPhoto, audio: hasAudio, extra: extra))
                        print("\(encoded)\t\(hasPhoto)\t\(hasAudio)\t\(extra)\t"
                              + "\(content?.kind ?? "none")\t\(content?.fileCount ?? 0)")
                    }
                }
            }
        }
    }

    static func main() {
        if CommandLine.arguments.contains("--dump") { dump(); return }

        print("What is copied")

        check("words are copied as they were written",
              "\(MessageCopy.content(text: "G-569619", photo: nil, audio: nil) ?? .text("?"))",
              "\(MessageCopy.text("G-569619"))")
        check("a photo is copied as the photo, caption and all", kind("boleto em anexo", photo, nil), "photo")
        check("a voice message is copied as the audio", kind(nil, nil, audio), "voice")
        check("…words beside it do not make it text", kind("oi", nil, audio), "voice")
        check("a file the service has not described has nothing to copy", kind(nil, nil, nil), "none")
        check("blank words are nothing to copy", kind(" \n", nil, nil), "none")
        check("a PDF alone is copied as the file", "\(copy(nil, nil, nil, [pdf]).map { "\($0)" } ?? "nil")",
              "\(MessageCopy.files([pdf], text: nil))")
        check("…with what was written beside it",
              "\(copy("segue o boleto", nil, nil, [pdf, sheet]).map { "\($0)" } ?? "nil")",
              "\(MessageCopy.files([pdf, sheet], text: "segue o boleto"))")
        check("…but not blank words", "\(copy(" \n", nil, nil, [pdf]).map { "\($0)" } ?? "nil")",
              "\(MessageCopy.files([pdf], text: nil))")
        check("an album copies every photo, the one shown first",
              "\(copy(nil, photo, nil, [photoFile, sheet, pdf]).map { "\($0)" } ?? "nil")",
              "\(MessageCopy.photo(photo, alongside: [sheet, pdf]))")
        check("…which is the photo alone when it came alone",
              "\(copy(nil, photo, nil, [photoFile]).map { "\($0)" } ?? "nil")",
              "\(MessageCopy.photo(photo, alongside: []))")
        check("a voice note's own file does not make it files", kind(nil, nil, audio, [audioFile]), "voice")
        check("files count what goes on the clipboard",
              [copy("x", nil, nil), copy(nil, photo, nil, [photoFile, pdf]), copy(nil, nil, audio, [audioFile]),
               copy(nil, nil, nil, [pdf, sheet])].map { "\($0?.fileCount ?? -1)" }.joined(separator: ","),
              "0,2,1,2")

        print("Where a copied file goes")

        let folder = URL(fileURLWithPath: "/tmp/Notchy Files", isDirectory: true)
        check("under its own name, in a folder named by its id",
              MessageCopy.localFile(id: "f1", name: "boleto.pdf", in: folder).path,
              "/tmp/Notchy Files/f1/boleto.pdf")
        check("a name with a path is only its last part",
              MessageCopy.localFile(id: "f1", name: "../../etc/passwd", in: folder).path,
              "/tmp/Notchy Files/f1/passwd")
        check("an id cannot climb out of the folder",
              MessageCopy.localFile(id: "../..", name: "a.pdf", in: folder).path,
              "/tmp/Notchy Files/file/a.pdf")
        check("no name at all", MessageCopy.localFile(id: "f1", name: " ", in: folder).lastPathComponent, "File")

        print("What the voice message's file is called")

        let mp3 = Data([0x49, 0x44, 0x33, 0x04, 0, 0, 0, 0, 0, 0])
        let ogg = Data("OggS".utf8) + Data(repeating: 0, count: 8)
        let m4a = Data([0, 0, 0, 0x20]) + Data("ftypM4A ".utf8)
        let adts = Data([0xFF, 0xF1, 0x50, 0x80])
        let bareMP3 = Data([0xFF, 0xFB, 0x90, 0x64])
        let wav = Data("RIFF".utf8) + Data([0, 0, 0, 0]) + Data("WAVE".utf8)
        let webm = Data([0x1A, 0x45, 0xDF, 0xA3, 0, 0])
        let junk = Data([1, 2, 3, 4, 5, 6])

        check("an MP3 Ato named .ogg is called .mp3", MessageCopy.audioFileName("audio.ogg", data: mp3), "audio.mp3")
        check("an Ogg keeps its name", MessageCopy.audioFileName("voice.ogg", data: ogg), "voice.ogg")
        check("an .mp4 holding M4A audio is left alone", MessageCopy.audioFileName("rec.mp4", data: m4a), "rec.mp4")
        check("no extension gains one", MessageCopy.audioFileName("nota", data: mp3), "nota.mp3")
        check("no name at all", MessageCopy.audioFileName("", data: ogg), "Voice message.ogg")
        check("a path is only its last part", MessageCopy.audioFileName("../../etc/x.ogg", data: ogg), "x.ogg")
        check("unknown bytes keep the name they came with", MessageCopy.audioFileName("a.opus", data: junk), "a.opus")
        check("ADTS is AAC", MessageCopy.audioExtension(of: adts) ?? "nil", "aac")
        check("a bare MPEG frame is MP3", MessageCopy.audioExtension(of: bareMP3) ?? "nil", "mp3")
        check("WAV", MessageCopy.audioExtension(of: wav) ?? "nil", "wav")
        check("WebM", MessageCopy.audioExtension(of: webm) ?? "nil", "webm")
        check("nothing is nothing", MessageCopy.audioExtension(of: Data()) ?? "nil", "nil")
        check("a name the file system refuses is cleaned",
              MessageCopy.safeFileName("a:b?c*.ogg"), "a-b-c-.ogg")

        clipboard()

        print("")
        if failures == 0 { print("All good.") } else { print("\(failures) failed."); exit(1) }
    }

    // MARK: - What another app finds

    static func clipboard() {
        let board = NSPasteboard(name: NSPasteboard.Name("fr.notchy.tests.message-copy.\(getpid())"))
        defer { board.releaseGlobally() }
        board.clearContents()
        guard board.setString("probe", forType: .string) else {
            // A runner with no pasteboard server. Said out loud: a half of the
            // suite that quietly stops running is worse than none.
            print("\n  ! no pasteboard here — the clipboard half did NOT run")
            return
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchy-copy-tests-\(getpid())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        print("Words")

        MessagePasteboard.writeText("G-569619", to: board)
        check("paste as text", board.string(forType: .string) ?? "nil", "G-569619")

        print("A photo")

        // 40 wide and 20 high as stored, turned a quarter by its EXIF — a
        // phone held upright. Whatever is pasted must be 20 by 40.
        let jpeg = dir.appendingPathComponent("IMG_1.jpg")
        writeJPEG(to: jpeg, width: 40, height: 20, orientation: 6)
        do {
            let provider = try MessagePasteboard.writePhoto(jpeg, caption: "boleto em anexo", to: board)
            let types = Set((board.types ?? []).map(\.rawValue))
            for type in ["public.file-url", "public.jpeg", "public.tiff", "public.png", "public.utf8-plain-text"] {
                check("offers \(type)", "\(types.contains(type))", "true")
            }
            let urls = board.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
            check("the file is the original", urls.first?.standardizedFileURL.path ?? "nil",
                  jpeg.standardizedFileURL.path)
            check("the JPEG is its bytes as they are",
                  "\(board.data(forType: NSPasteboard.PasteboardType("public.jpeg")) == (try? Data(contentsOf: jpeg)))",
                  "true")
            check("text is the caption", board.string(forType: .string) ?? "nil", "boleto em anexo")
            check("TIFF is made on demand, turned upright", size(board.data(forType: .tiff)), "20×40")
            check("PNG too", size(board.data(forType: .png)), "20×40")
            check("an image view can take it", "\(NSImage(pasteboard: board) != nil)", "true")
            withExtendedLifetime(provider) {}
        } catch {
            check("the photo was written", "\(error)", "no error")
        }

        let bare = dir.appendingPathComponent("print.png")
        writePNG(to: bare)
        do {
            let provider = try MessagePasteboard.writePhoto(bare, caption: nil, to: board)
            check("a photo alone gives its name as the text, as Finder does",
                  board.string(forType: .string) ?? "nil", "print.png")
            withExtendedLifetime(provider) {}
        } catch {
            check("the PNG was written", "\(error)", "no error")
        }

        print("An album")

        let second = dir.appendingPathComponent("IMG_2.jpg")
        writeJPEG(to: second, width: 8, height: 8, orientation: 1)
        let report = dir.appendingPathComponent("boleto.pdf")
        try? Data("%PDF-1.4\n".utf8).write(to: report)
        do {
            let provider = try MessagePasteboard.writePhoto(jpeg, caption: "boleto em anexo",
                                                            alongside: [second, report], to: board)
            check("one item a file, as Finder copies several", "\(board.pasteboardItems?.count ?? 0)", "3")
            check("the photo shown first, the rest after it", names(board), "IMG_1.jpg,IMG_2.jpg,boleto.pdf")
            check("text is still the caption, once", strings(board), "boleto em anexo")
            check("an image view still takes the first", size(board.data(forType: .tiff)), "20×40")
            withExtendedLifetime(provider) {}
        } catch {
            check("the album was written", "\(error)", "no error")
        }

        print("A voice message")

        let clip = dir.appendingPathComponent("audio.mp3")
        try? Data([0x49, 0x44, 0x33]).write(to: clip)
        MessagePasteboard.writeFiles([clip], text: "oi, tudo bem?", to: board)
        check("the file", names(board), "audio.mp3")
        check("text is what was said", board.string(forType: .string) ?? "nil", "oi, tudo bem?")
        MessagePasteboard.writeFiles([clip], text: nil, to: board)
        check("…or its name before there is a transcript", board.string(forType: .string) ?? "nil", "audio.mp3")

        print("Files")

        let sheet = dir.appendingPathComponent("notas.xlsx")
        try? Data("PK".utf8).write(to: sheet)
        MessagePasteboard.writeFiles([report], text: nil, to: board)
        check("a PDF is the file, under its own name", names(board), "boleto.pdf")
        check("…and its name is the text, as Finder gives it", board.string(forType: .string) ?? "nil", "boleto.pdf")
        MessagePasteboard.writeFiles([report, sheet], text: "segue o boleto", to: board)
        check("two files are two items", "\(board.pasteboardItems?.count ?? 0)", "2")
        check("…in the order they were sent", names(board), "boleto.pdf,notas.xlsx")
        check("…with what was written, once, as the text", strings(board), "segue o boleto")
        check("what Finder pastes is the file itself",
              (board.readObjects(forClasses: [NSURL.self]) as? [URL])?.first?.standardizedFileURL.path ?? "nil",
              report.standardizedFileURL.path)
        let before = board.changeCount
        MessagePasteboard.writeFiles([], text: "x", to: board)
        check("no files leaves the clipboard alone", "\(board.changeCount == before)", "true")
    }

    /// The names of the files on the board, in order — what Finder pastes.
    static func names(_ board: NSPasteboard) -> String {
        ((board.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []).map(\.lastPathComponent)
            .joined(separator: ",")
    }

    /// Every item's text, joined — what an app that reads them all would get.
    static func strings(_ board: NSPasteboard) -> String {
        (board.pasteboardItems ?? []).compactMap { $0.string(forType: .string) }.joined(separator: "|")
    }

    static func size(_ data: Data?) -> String {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return "nil" }
        return "\(props[kCGImagePropertyPixelWidth] as? Int ?? 0)×\(props[kCGImagePropertyPixelHeight] as? Int ?? 0)"
    }

    static func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func writeJPEG(to url: URL, width: Int, height: Int, orientation: Int) {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image(width: width, height: height),
                                   [kCGImagePropertyOrientation: orientation] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    static func writePNG(to url: URL) {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image(width: 8, height: 8), nil)
        CGImageDestinationFinalize(destination)
    }
}
