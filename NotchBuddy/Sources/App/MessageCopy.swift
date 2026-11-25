//
//  MessageCopy.swift
//  Notchy
//
//  What Copy on a message card puts on the clipboard: what the sender sent —
//  their words, their photo, their voice message, their PDF — and never what
//  the card says about it. "📷 Photo" and "📎 Sent a file" are the card talking.
//
//  Foundation only and its own file, so scripts/test-message-copy.sh can
//  compile it beside InboxPhoto, InboxAudio and InboxFile and nothing else.
//

import Foundation

enum MessageCopy: Equatable, Sendable {
    /// Words, and nothing else came with them.
    case text(String)
    /// The photo, whole — with what was written beside it, which the photo
    /// carries as its caption — and the post's other files after it: the
    /// rest of an album, a PDF sent with it.
    case photo(InboxPhoto, alongside: [InboxFile])
    /// The voice message itself, as the audio file.
    case voice(InboxAudio)
    /// Files the card does not draw — a PDF, a spreadsheet — each under the
    /// name it was sent with, and what was written with them, if anything.
    case files([InboxFile], text: String?)

    /// What there is to copy, or nil when there is nothing real to hand on.
    ///
    /// The voice message and the photo come first, in the order the card
    /// draws them; then the files the card only says arrived. They are what
    /// was sent, and any words are beside them. `text` is the sender's own —
    /// `InboxMessage.text`, not `body`. `files` is every file on the message,
    /// the photo's own among them.
    static func content(text: String?, photo: InboxPhoto?, audio: InboxAudio?,
                        files: [InboxFile] = []) -> MessageCopy? {
        let words = text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        if let audio { return .voice(audio) }
        if let photo { return .photo(photo, alongside: files.filter { $0.fileID != photo.fileID }) }
        if !files.isEmpty { return .files(files, text: words) }
        return words.map(MessageCopy.text)
    }

    /// Which of the four it is, as the TypeScript twin names it.
    var kind: String {
        switch self {
        case .text:  return "text"
        case .photo: return "photo"
        case .voice: return "voice"
        case .files: return "files"
        }
    }

    /// How many files go on the clipboard — what the TypeScript twin is
    /// checked against beside the kind.
    var fileCount: Int {
        switch self {
        case .text:                      return 0
        case .photo(_, let alongside):   return 1 + alongside.count
        case .voice:                     return 1
        case .files(let files, _):       return files.count
        }
    }

    // MARK: - Where a copied file goes

    /// Where a file is written to be copied: in a folder of its own, named
    /// by its id, under the name it was sent with — so pasting it into
    /// Finder gives that name, and two files both called `scan.pdf` are
    /// still two files. One with no usable name is called `fallback`.
    static func localFile(id: String, name: String, in folder: URL, fallback: String = "File") -> URL {
        var own = safeFileName(name)
        if own.isEmpty { own = fallback }
        var key = safeFileName(id)
        if key.isEmpty { key = "file" }
        return folder.appendingPathComponent(key, isDirectory: true).appendingPathComponent(own)
    }

    // MARK: - The voice message's file

    /// What the copied audio is called: the name it was sent with, with the
    /// extension its bytes say it really has.
    ///
    /// A file pasted into a chat or a folder goes by its name, and Ato has
    /// been seen naming MP3s `.ogg` — which is fine for a player that sniffs,
    /// and a file nothing else will open. A name with nothing usable in it
    /// becomes "Voice message".
    static func audioFileName(_ name: String, data: Data) -> String {
        var base = safeFileName(name)
        if base.isEmpty { base = "Voice message" }
        guard let real = audioExtension(of: data) else { return base }
        let own = (base as NSString).pathExtension.lowercased()
        if own == real || (real == "m4a" && ["mp4", "m4a", "aac"].contains(own)) { return base }
        let stem = own.isEmpty ? base : (base as NSString).deletingPathExtension
        return "\(stem.isEmpty ? "Voice message" : stem).\(real)"
    }

    /// The audio container the first bytes name, or nil for one this does
    /// not know — whose name is then left as it came.
    static func audioExtension(of data: Data) -> String? {
        let head = [UInt8](data.prefix(12))
        func has(_ bytes: [UInt8], at offset: Int = 0) -> Bool {
            head.count >= offset + bytes.count && Array(head[offset..<offset + bytes.count]) == bytes
        }
        func has(_ ascii: String, at offset: Int = 0) -> Bool { has(Array(ascii.utf8), at: offset) }

        if has("OggS") { return "ogg" }
        if has("ID3") { return "mp3" }
        if has("RIFF") && has("WAVE", at: 8) { return "wav" }
        if has("ftyp", at: 4) { return "m4a" }
        if has([0x1A, 0x45, 0xDF, 0xA3]) { return "webm" }
        if has("fLaC") { return "flac" }
        if has("#!AMR") { return "amr" }
        // A bare frame header: eleven bits set. ADTS — AAC without a
        // container — is the one whose layer bits are zero.
        if head.count >= 2, head[0] == 0xFF, head[1] & 0xE0 == 0xE0 {
            return head[1] & 0x06 == 0 ? "aac" : "mp3"
        }
        return nil
    }

    /// The last path component, with nothing a file system refuses and no
    /// leading dot — the name a file is written under in the temporary folder.
    static func safeFileName(_ name: String) -> String {
        let last = name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        let refused: (Character) -> Bool = { character in
            ":<>\"|?*".contains(character)
                || character.unicodeScalars.contains { $0.properties.generalCategory == .control }
        }
        let cleaned = String(last.map { refused($0) ? "-" : $0 })
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
    }
}
