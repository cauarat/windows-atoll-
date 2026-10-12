import AppKit
import Foundation

/// Staging files on a reply: taking them in, showing why one was refused, and
/// letting them go again.
///
/// The rules live in `ReplyAttachment.swift`, which knows nothing of disks or
/// panels so it can be tested. This is the half that touches the machine —
/// it reads sizes, copies pasted images somewhere real, and runs the picker.
enum ReplyAttachmentStore {

    // MARK: - Taking files in

    /// Stages whatever of `urls` the rules allow, and says so when some are
    /// turned away.
    @MainActor
    static func attach(urls: [URL], state: AppState) {
        guard !urls.isEmpty else { return }

        let candidates = urls.map { url -> AttachmentCandidate in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            return AttachmentCandidate(url: url,
                                       byteCount: values?.fileSize ?? 0,
                                       isRegularFile: !(values?.isDirectory ?? false))
        }

        let result = AttachmentIntake.accept(candidates, existing: state.replyAttachments)

        if !result.accepted.isEmpty {
            state.replyAttachments.append(contentsOf: result.accepted)
            SoundEngine.shared.play("attach")
        }
        // One line, however many were refused: the card has room for a
        // sentence, not a list.
        state.replyNotice = result.rejected.first?.message
    }

    @MainActor
    static func remove(_ attachment: ReplyAttachment, state: AppState) {
        state.replyAttachments.removeAll { $0.id == attachment.id }
        if state.replyAttachments.isEmpty { state.replyNotice = nil }
    }

    /// Clears everything staged — on send, and on dismissing the card.
    @MainActor
    static func clear(state: AppState) {
        state.replyAttachments = []
        state.replyNotice = nil
        state.replyDragOver = false
    }

    // MARK: - Paste

    /// Whether the pasteboard holds something a reply could carry.
    ///
    /// Checked before swallowing a ⌘V so an ordinary text paste still reaches
    /// the field it was meant for.
    @MainActor
    static func pasteboardHasFiles(_ board: NSPasteboard = .general) -> Bool {
        if let urls = board.readObjects(forClasses: [NSURL.self],
                                        options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return true
        }
        return board.data(forType: .tiff) != nil || board.data(forType: .png) != nil
    }

    /// Stages whatever the pasteboard is holding.
    ///
    /// A copied *file* arrives as a URL and needs nothing. A copied *image* —
    /// a screenshot, a crop — has no file behind it, so one is written into
    /// the inbox and everything downstream sees a URL like any other.
    @MainActor
    static func attachPasteboard(_ board: NSPasteboard = .general, state: AppState) {
        if let urls = board.readObjects(forClasses: [NSURL.self],
                                        options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            attach(urls: urls, state: state)
            return
        }

        guard let data = board.data(forType: .png) ?? board.data(forType: .tiff),
              let url = writeToInbox(data: data, preferredName: "Pasted image")
        else { return }
        attach(urls: [url], state: state)
    }

    /// Writes pasted bytes into the same inbox a dropped file is copied to, so
    /// nothing downstream has to care where a file came from.
    ///
    /// PNG is written as it arrives; TIFF is re-encoded, because a pasted
    /// screenshot that lands on a server as a 12 MB TIFF helps nobody.
    @MainActor
    private static func writeToInbox(data: Data, preferredName: String) -> URL? {
        let inbox = HookServer.supportDir.appendingPathComponent("inbox")
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        var payload = data
        if data.count >= 2, data.prefix(2) != Data([0x89, 0x50]) {
            // Not a PNG — go through NSImage to get one.
            guard let image = NSImage(data: data),
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { return nil }
            payload = png
        }

        let stamp = Self.stampFormatter.string(from: Date())
        let url = inbox.appendingPathComponent("\(preferredName) \(stamp).png")
        do {
            try payload.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Seconds included: two screenshots pasted in the same minute are two
    /// files, not one overwriting the other.
    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()

    // MARK: - Picker

    /// Opens a file picker, holding the card open across it.
    ///
    /// `isPickingFile` is the whole point: the panel takes the keyboard, which
    /// drops `isReplying`, and without the flag the auto-close timer would
    /// fold the card away behind the panel and throw the draft out with it.
    @MainActor
    static func pickFiles(state: AppState) {
        state.isPickingFile = true

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Attach"
        panel.message = "Attach to your reply"

        panel.begin { response in
            Task { @MainActor in
                defer { state.isPickingFile = false }
                guard response == .OK else { return }
                attach(urls: panel.urls, state: state)
                // The panel took the keyboard on its way in; the card needs it
                // back or the next keystroke goes nowhere.
                NotificationCenter.default.post(name: .islandWantsKeyboard, object: nil)
            }
        }
    }
}
