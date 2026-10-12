import AppKit
import Combine

/// What was copied, and when.
struct ClipEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case text(String)
        case image(NSImage, bytes: Int)

        var isImage: Bool { if case .image = self { return true }; return false }
    }

    let id: UUID
    let kind: Kind
    let copiedAt: Date
    var favourite: Bool

    /// What the row says. For text, the first line, trimmed.
    var title: String {
        switch kind {
        case .text(let s):
            let line = s.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
            return line.isEmpty ? "Blank" : line
        case .image(_, let bytes):
            return "Image (\(ClipEntry.size(bytes)))"
        }
    }

    /// The quiet second line: what kind of thing this is.
    var subtitle: String {
        switch kind {
        case .text(let s):
            if s.hasPrefix("http://") || s.hasPrefix("https://") { return "Link" }
            let lines = s.split(separator: "\n").count
            return lines > 1 ? "Text · \(lines) lines" : "Text"
        case .image:
            return "Image"
        }
    }

    /// Matching is on the whole text, not the one-line title: two snippets that
    /// start the same are still two snippets.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        switch kind {
        case .text(let s): return s.localizedCaseInsensitiveContains(query)
        case .image:       return title.localizedCaseInsensitiveContains(query)
        }
    }

    static func size(_ bytes: Int) -> String {
        bytes >= 1_048_576
            ? String(format: "%.1f MB", Double(bytes) / 1_048_576)
            : "\(max(1, bytes / 1024)) KB"
    }

    /// "21m ago", the way the reference reads.
    static func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86_400 { return "\(s / 3600)h ago" }
        return "\(s / 86_400)d ago"
    }
}

/// Everything copied since launch.
///
/// **The history is in memory only, and deliberately.** Clipboard contents are
/// the most sensitive thing this app could hold — passwords on their way to a
/// login box, tokens, private messages — so nothing that merely passed through
/// is written anywhere, and the history goes when the app does.
///
/// Favourites are the exception, because being able to keep something is the
/// point of marking it. They are written to Application Support in a directory
/// created 0700, with the file 0600, the same discipline `appendAppLog` uses.
/// Marking something a favourite is the act that consents to it being stored.
///
/// Shaped like `MessageInbox`: `@MainActor`, `ObservableObject`, `.shared`,
/// bounded, de-duplicated.
@MainActor
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    /// Enough to scroll, not enough to grow without bound.
    private static let maxEntries = 60
    /// Images are held decoded, so a cap on how many is a cap on memory.
    private static let maxImages = 12
    /// Bigger than this and it is a file being moved, not a snippet worth
    /// keeping. Skipped rather than truncated: half a copied document is worse
    /// than none of it.
    private static let maxTextLength = 20_000

    @Published private(set) var entries: [ClipEntry] = []
    /// Off by default. Watching what someone copies is not something to start
    /// doing because the app was launched.
    @Published private(set) var watching = false

    private var lastChangeCount = NSPasteboard.general.changeCount
    private var poll: Timer?

    private init() {
        entries = Self.loadFavourites()
    }

    var favourites: [ClipEntry] { entries.filter(\.favourite) }

    // MARK: – Watching

    func start() {
        guard poll == nil else { return }
        watching = true
        lastChangeCount = NSPasteboard.general.changeCount
        // NSPasteboard has no change notification; `changeCount` polling is the
        // only way. Twice a second is below noticing and costs one integer read.
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.capture() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    func stop() {
        poll?.invalidate()
        poll = nil
        watching = false
    }

    func setWatching(_ on: Bool) { on ? start() : stop() }

    // MARK: – Entries

    private func capture() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChangeCount else { return }
        lastChangeCount = board.changeCount

        if let text = board.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard text.count <= Self.maxTextLength else { return }
            add(.text(text))
            return
        }
        if let data = board.data(forType: .tiff) ?? board.data(forType: .png),
           let image = NSImage(data: data) {
            add(.image(image, bytes: data.count))
        }
    }

    private func add(_ kind: ClipEntry.Kind) {
        // Copying the same thing twice moves it to the top rather than filling
        // the list with it — including when it was copied from here.
        if let idx = entries.firstIndex(where: { same($0.kind, kind) }) {
            var existing = entries.remove(at: idx)
            existing = ClipEntry(id: existing.id, kind: existing.kind,
                                 copiedAt: Date(), favourite: existing.favourite)
            entries.insert(existing, at: 0)
            return
        }
        entries.insert(ClipEntry(id: UUID(), kind: kind, copiedAt: Date(), favourite: false), at: 0)
        trim()
    }

    private func same(_ a: ClipEntry.Kind, _ b: ClipEntry.Kind) -> Bool {
        switch (a, b) {
        case let (.text(x), .text(y)): return x == y
        // Two images are compared by size alone: comparing pixels on every copy
        // would cost more than the duplicate it would catch.
        case let (.image(_, x), .image(_, y)): return x == y
        default: return false
        }
    }

    /// Drops the oldest, and the oldest images sooner. Favourites are kept.
    private func trim() {
        var images = 0
        var kept: [ClipEntry] = []
        for entry in entries {
            if entry.favourite { kept.append(entry); continue }
            if entry.kind.isImage {
                images += 1
                if images > Self.maxImages { continue }
            }
            if kept.count >= Self.maxEntries { continue }
            kept.append(entry)
        }
        entries = kept
    }

    // MARK: – Actions

    /// Puts it back on the pasteboard. The change this causes is recognised as a
    /// duplicate, so it moves to the top instead of appearing twice.
    func copy(_ entry: ClipEntry) {
        let board = NSPasteboard.general
        board.clearContents()
        switch entry.kind {
        case .text(let s):
            board.setString(s, forType: .string)
        case .image(let image, _):
            board.writeObjects([image])
        }
        lastChangeCount = board.changeCount
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            let moved = entries.remove(at: idx)
            entries.insert(moved, at: 0)
        }
        SoundEngine.shared.play("blip")
    }

    func toggleFavourite(_ entry: ClipEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx].favourite.toggle()
        saveFavourites()
    }

    func remove(_ entry: ClipEntry) {
        entries.removeAll { $0.id == entry.id }
        if entry.favourite { saveFavourites() }
    }

    /// Clears the history. Favourites go too — this is the button that means
    /// "forget what I copied", and leaving some of it behind would be a lie. It
    /// takes what was written to disk with it.
    func clear() {
        entries.removeAll()
        saveFavourites()
    }

    // MARK: – Favourites on disk

    /// `Application Support/Notchy/clipboard`, created 0700.
    private static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchy/clipboard")
    }
    private static var indexFile: URL { dir.appendingPathComponent("favourites.json") }

    /// What a favourite looks like on disk. Images are kept beside this file as
    /// PNGs named by id, rather than inlined — a base64 blob in a JSON index
    /// would make the whole thing unreadable and rewrite every image on every
    /// change.
    private struct StoredFavourite: Codable {
        let id: UUID
        let copiedAt: Date
        let text: String?
        let imageBytes: Int?
    }

    private func saveFavourites() {
        let fm = FileManager.default
        let dir = Self.dir
        let keep = entries.filter(\.favourite)

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700 as NSNumber], ofItemAtPath: dir.path)

            var stored: [StoredFavourite] = []
            for entry in keep {
                switch entry.kind {
                case .text(let s):
                    stored.append(StoredFavourite(id: entry.id, copiedAt: entry.copiedAt,
                                                  text: s, imageBytes: nil))
                case .image(let image, let bytes):
                    let file = dir.appendingPathComponent("\(entry.id.uuidString).png")
                    if !fm.fileExists(atPath: file.path), let png = Self.png(from: image) {
                        try png.write(to: file, options: [.atomic, .completeFileProtection])
                        try? fm.setAttributes([.posixPermissions: 0o600 as NSNumber],
                                              ofItemAtPath: file.path)
                    }
                    stored.append(StoredFavourite(id: entry.id, copiedAt: entry.copiedAt,
                                                  text: nil, imageBytes: bytes))
                }
            }

            // Images belonging to favourites that are gone go with them.
            let live = Set(keep.map { "\($0.id.uuidString).png" })
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where
                name.hasSuffix(".png") && !live.contains(name) {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }

            let data = try JSONEncoder().encode(stored)
            try data.write(to: Self.indexFile, options: [.atomic, .completeFileProtection])
            try? fm.setAttributes([.posixPermissions: 0o600 as NSNumber],
                                  ofItemAtPath: Self.indexFile.path)
        } catch {
            // Losing a favourite is a disappointment, not a failure worth
            // interrupting anyone over.
            appendAppLog("island.log", "clipboard: could not save favourites — \(error)")
        }
    }

    private static func loadFavourites() -> [ClipEntry] {
        guard let data = try? Data(contentsOf: indexFile),
              let stored = try? JSONDecoder().decode([StoredFavourite].self, from: data)
        else { return [] }

        return stored.compactMap { item in
            if let text = item.text {
                return ClipEntry(id: item.id, kind: .text(text),
                                 copiedAt: item.copiedAt, favourite: true)
            }
            let file = dir.appendingPathComponent("\(item.id.uuidString).png")
            guard let bytes = item.imageBytes,
                  let png = try? Data(contentsOf: file),
                  let image = NSImage(data: png)
            else { return nil }
            return ClipEntry(id: item.id, kind: .image(image, bytes: bytes),
                             copiedAt: item.copiedAt, favourite: true)
        }
    }

    private static func png(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
