//
//  MessagePasteboard.swift
//  Notchy
//
//  How a copied message is laid out on the clipboard, so whatever it is
//  pasted into finds a form it takes.
//
//  AppKit and ImageIO only, and its own file, so scripts/test-message-copy.sh
//  can write to a pasteboard of its own and read back what another app would
//  see — without the inbox, the clients or the user's clipboard.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

enum MessagePasteboard {

    static func writeText(_ text: String, to board: NSPasteboard = .general) {
        board.clearContents()
        board.setString(text, forType: .string)
    }

    /// A photo the way Finder hands a file on and the way an image editor
    /// hands an image on, at once — each app takes the form it understands:
    ///
    /// - the file itself, under the name it was sent with, for Finder, Mail,
    ///   Messages and every chat that takes an attachment;
    /// - its bytes as they are (JPEG, HEIC…), for anything that reads that
    ///   type;
    /// - TIFF and PNG for everything else, made only if an app asks: a phone
    ///   photo as TIFF is tens of megabytes nobody may want;
    /// - what was written with it, as text, for a field that only takes
    ///   words — or the file's name when nothing was, which is what Finder
    ///   puts there too, rather than a path into the temporary folder.
    ///
    /// The post's other files — the rest of an album, a PDF sent with the
    /// photo — follow it as files, one item each, the way Finder copies
    /// several: an app that takes one image takes the first, one that takes
    /// files takes them all.
    ///
    /// Returns what makes the TIFF and PNG, which has to be kept for as long
    /// as the clipboard may ask it — until the next copy.
    @discardableResult
    static func writePhoto(_ file: URL, caption: String?, alongside: [URL] = [],
                           to board: NSPasteboard = .general) throws -> PhotoPasteProvider {
        let item = NSPasteboardItem()
        item.setString(file.absoluteString, forType: .fileURL)
        if let type = UTType(filenameExtension: file.pathExtension), type.conforms(to: .image),
           type != .tiff, type != .png {
            let bytes = try Data(contentsOf: file, options: .mappedIfSafe)
            item.setData(bytes, forType: NSPasteboard.PasteboardType(type.identifier))
        }
        let provider = PhotoPasteProvider(file: file)
        item.setDataProvider(provider, forTypes: [.tiff, .png])
        item.setString(caption ?? file.lastPathComponent, forType: .string)

        board.clearContents()
        guard board.writeObjects([item] + alongside.map(fileItem)) else { throw CocoaError(.fileWriteUnknown) }
        return provider
    }

    /// Files the way Finder copies them, one item each — with, as the text,
    /// `text` when there is some (a voice message's transcript, what was
    /// written with a PDF), so a field that takes only words gets those
    /// rather than a file name; the first file's name when there is none,
    /// which is what Finder puts there too.
    ///
    /// The words go on the first item alone. An app pasting text off several
    /// items may join them all, and "the invoice" followed by two file names
    /// is not what was sent.
    static func writeFiles(_ files: [URL], text: String?, to board: NSPasteboard = .general) {
        guard let first = files.first else { return }
        let items = files.map(fileItem)
        items[0].setString(text ?? first.lastPathComponent, forType: .string)
        board.clearContents()
        board.writeObjects(items)
    }

    private static func fileItem(_ file: URL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(file.absoluteString, forType: .fileURL)
        return item
    }
}

/// Makes a copied photo into TIFF or PNG when, and only when, an app pasting
/// it asks for one of those — turned the way the camera meant, at full size.
///
/// AppKit calls it on the main thread, synchronously, while the other app
/// waits; it touches nothing but the file it was given.
final class PhotoPasteProvider: NSObject, NSPasteboardItemDataProvider {
    private let file: URL

    init(file: URL) {
        self.file = file
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        let format: UTType = type == .png ? .png : .tiff
        guard let data = Self.render(file, as: format) else { return }
        item.setData(data, forType: type)
    }

    static func render(_ file: URL, as format: UTType) -> Data? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        // A "thumbnail" as large as the photo: the ImageIO call that applies
        // the EXIF orientation, which a phone photo almost always carries.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, format.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
