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
    /// Returns what makes the TIFF and PNG, which has to be kept for as long
    /// as the clipboard may ask it — until the next copy.
    @discardableResult
    static func writePhoto(_ file: URL, caption: String?,
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
        guard board.writeObjects([item]) else { throw CocoaError(.fileWriteUnknown) }
        return provider
    }

    /// A file the way Finder copies one — with, as the text, `text` when
    /// there is some (a voice message's transcript), so a field that takes
    /// only words gets those rather than a file name.
    static func writeFile(_ file: URL, text: String?, to board: NSPasteboard = .general) {
        let item = NSPasteboardItem()
        item.setString(file.absoluteString, forType: .fileURL)
        item.setString(text ?? file.lastPathComponent, forType: .string)
        board.clearContents()
        board.writeObjects([item])
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
