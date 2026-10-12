import Foundation

/// A file staged on a reply, before it is sent.
///
/// Deliberately separate from `DroppedFile`, which belongs to the upload →
/// choose flow and is singular because that flow asks one question about one
/// file. A reply carries several, and it carries them only until it is sent,
/// so nothing here is persisted.
///
/// Everything in this file is pure over its arguments — no FileManager, no
/// AppKit — because the test runners compile a short closed list of sources
/// and nothing that imports SwiftUI can be among them. The app layer reads
/// sizes off the disk and hands them in.
struct ReplyAttachment: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let byteCount: Int
    let kind: AttachmentKind

    init(id: UUID = UUID(), url: URL, byteCount: Int) {
        self.id = id
        self.url = url
        self.name = url.lastPathComponent
        self.byteCount = byteCount
        self.kind = AttachmentKind(extension: url.pathExtension)
    }

    /// What the upload declares the bytes to be.
    ///
    /// A wrong answer here is cosmetic on Mattermost — it sniffs the content
    /// anyway — but `application/octet-stream` for a PNG makes the preview in
    /// the other person's client disappear, so the common types are named.
    var mimeType: String { AttachmentKind.mimeType(forExtension: url.pathExtension) }

    /// Rounded the way a file size is spoken rather than computed — the chip
    /// has room for "2.4 MB" and none for "2,411,724 bytes".
    var sizeLabel: String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(byteCount)
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return unit == 0
            ? "\(byteCount) B"
            : String(format: value < 10 ? "%.1f %@" : "%.0f %@", value, units[unit])
    }
}

// MARK: - Kind

/// What the chip should look like, and nothing more.
///
/// The image and pdf lists match `ClaudeService.readFileAsBlock` so a file that
/// shows an image chip here is the same set the Claude path can read inline.
/// `document` exists only to pick an icon; it is not a claim that anything can
/// parse the file.
enum AttachmentKind: String, CaseIterable, Sendable {
    case image, pdf, document, other

    init(extension ext: String) {
        switch ext.lowercased() {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "bmp":
            self = .image
        case "pdf":
            self = .pdf
        case "txt", "md", "csv", "json", "yaml", "yml", "xml", "rtf",
             "doc", "docx", "xls", "xlsx", "ppt", "pptx",
             "pages", "numbers", "key":
            self = .document
        default:
            self = .other
        }
    }

    /// Every extension this kind claims, sorted — the catalogue the parity
    /// check dumps so the TypeScript twin cannot quietly gain or lose one.
    static var catalogue: [(AttachmentKind, [String])] {
        var byKind: [AttachmentKind: [String]] = [:]
        for ext in knownExtensions {
            byKind[AttachmentKind(extension: ext), default: []].append(ext)
        }
        return AttachmentKind.allCases.map { ($0, (byKind[$0] ?? []).sorted()) }
    }

    /// The handful worth naming. Anything else is bytes, and says so.
    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        case "heic":        return "image/heic"
        case "heif":        return "image/heif"
        case "tiff":        return "image/tiff"
        case "bmp":         return "image/bmp"
        case "pdf":         return "application/pdf"
        case "txt":         return "text/plain"
        case "md":          return "text/markdown"
        case "csv":         return "text/csv"
        case "json":        return "application/json"
        case "xml":         return "application/xml"
        case "yaml", "yml": return "application/yaml"
        case "rtf":         return "application/rtf"
        case "zip":         return "application/zip"
        default:            return "application/octet-stream"
        }
    }

    static let knownExtensions = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "bmp",
        "pdf",
        "txt", "md", "csv", "json", "yaml", "yml", "xml", "rtf",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key",
    ]
}

// MARK: - Limits

/// What a reply will carry.
///
/// Mattermost's own ceiling is a server setting this app cannot read, so
/// `maxBytesPerFile` is a client-side guess that keeps a mistake cheap rather
/// than a promise about what the server accepts. A refusal from the server is
/// still shown as it comes back.
enum AttachmentLimits {
    static let maxCount = 10
    static let maxBytesPerFile = 20 * 1024 * 1024
    static let maxTotalBytes = 50 * 1024 * 1024
}

// MARK: - Intake

/// Why a file was turned away, in words the card shows unchanged — the same
/// bargain `MessageInbox.ReplyError` makes.
enum AttachmentRejection: Equatable, Sendable {
    case tooMany
    case tooLarge(name: String)
    case wouldExceedTotal(name: String)
    case duplicate(name: String)
    case notAFile(name: String)

    var message: String {
        switch self {
        case .tooMany:
            return "That is more than \(AttachmentLimits.maxCount) files."
        case .tooLarge(let name):
            return "\(name) is over 20 MB."
        case .wouldExceedTotal(let name):
            return "\(name) would take the reply over 50 MB."
        case .duplicate(let name):
            return "\(name) is already attached."
        case .notAFile(let name):
            return "\(name) is a folder."
        }
    }
}

/// A file offered to the reply box, with its size already read.
struct AttachmentCandidate: Equatable, Sendable {
    let url: URL
    let byteCount: Int
    /// False for a directory. The caller knows; this file does not look.
    var isRegularFile: Bool = true
}

enum AttachmentIntake {
    struct Result: Equatable, Sendable {
        var accepted: [ReplyAttachment] = []
        var rejected: [AttachmentRejection] = []
    }

    /// Decides which of `candidates` join `existing`.
    ///
    /// Order matters and is deliberate: a file is checked against what is
    /// already staged *and* against the ones accepted earlier in the same drop,
    /// so dropping the same file twice in one gesture is caught too.
    ///
    /// `ids` lets a test pin the identifiers; the app passes nothing and gets
    /// fresh ones.
    static func accept(_ candidates: [AttachmentCandidate],
                       existing: [ReplyAttachment],
                       ids: [UUID] = []) -> Result {
        var result = Result()
        var staged = existing
        var total = existing.reduce(0) { $0 + $1.byteCount }
        var nextID = ids.makeIterator()

        for candidate in candidates {
            let name = candidate.url.lastPathComponent

            guard candidate.isRegularFile else {
                result.rejected.append(.notAFile(name: name))
                continue
            }
            guard staged.count < AttachmentLimits.maxCount else {
                // One complaint, however many are left — a drop of thirty
                // should not produce thirty lines in a card with one.
                if !result.rejected.contains(.tooMany) { result.rejected.append(.tooMany) }
                continue
            }
            guard !staged.contains(where: { $0.url == candidate.url }) else {
                result.rejected.append(.duplicate(name: name))
                continue
            }
            guard candidate.byteCount <= AttachmentLimits.maxBytesPerFile else {
                result.rejected.append(.tooLarge(name: name))
                continue
            }
            guard total + candidate.byteCount <= AttachmentLimits.maxTotalBytes else {
                result.rejected.append(.wouldExceedTotal(name: name))
                continue
            }

            let attachment = ReplyAttachment(id: nextID.next() ?? UUID(),
                                             url: candidate.url,
                                             byteCount: candidate.byteCount)
            staged.append(attachment)
            result.accepted.append(attachment)
            total += candidate.byteCount
        }

        return result
    }
}
