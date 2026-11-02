import AppKit
import AVFoundation
import SwiftUI

/// The files staged on a reply, as chips above the box.
///
/// Only drawn when something is attached, so a text-only reply is the card it
/// has always been. The chip follows the context pill the prompt view already
/// uses for a dropped file — same pill shape, same muted type — with a cross
/// added, because unlike that one this set is still being edited.
struct ReplyAttachmentsRow: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(state.replyAttachments) { attachment in
                        ReplyAttachmentChip(attachment: attachment) {
                            // Whatever is playing stops with the chip it
                            // belongs to; a voice note outliving its own row
                            // is a sound with no way to stop it.
                            if AttachmentPlayer.shared.playingID == attachment.id {
                                AttachmentPlayer.shared.stop()
                            }
                            ReplyAttachmentStore.remove(attachment, state: state)
                        }
                    }
                }
            }
            .frame(height: 26)

            if let notice = state.replyNotice {
                Text(notice)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#FF8D97"))
                    .lineLimit(1)
            }
        }
    }
}

/// One staged file.
struct ReplyAttachmentChip: View {
    let attachment: ReplyAttachment
    let remove: () -> Void

    @State private var thumbnail: NSImage?
    @State private var hovering = false
    /// Read off the file for an audio clip, so the chip can say `0:07` where
    /// a picture says how big it is. Nil until it has been.
    @State private var duration: TimeInterval?
    @ObservedObject private var player = AttachmentPlayer.shared

    var body: some View {
        HStack(spacing: 5) {
            preview
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 3))

            Text(attachment.name)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#E7E9EC"))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 104, alignment: .leading)

            // A voice note is a length, not a weight. Nobody has ever wanted
            // to know how many kilobytes they just said.
            Text(duration.map { VoiceNote.durationLabel(seconds: $0) } ?? attachment.sizeLabel)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#6B7079"))
                .fixedSize()

            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(hex: hovering ? "#F5F6F8" : "#8E939C"))
            }
            .buttonStyle(.plain)
            .help("Remove \(attachment.name)")
        }
        .padding(.leading, 5)
        .padding(.trailing, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(hovering ? 0.12 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .task(id: attachment.id) { loadThumbnail() }
    }

    @ViewBuilder
    private var preview: some View {
        // On an audio chip the slot that shows a picture becomes the control
        // that plays it — which is the whole of "hear it before you send it",
        // and costs the row no width it did not already have.
        if attachment.kind == .audio {
            Button { player.toggle(attachment) } label: {
                Image(systemName: player.playingID == attachment.id ? "pause.fill" : "play.fill")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "#E7E9EC"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(player.playingID == attachment.id ? L("Pause") : L("Play"))
        } else if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#8E939C"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The fallback when there is no picture to show — and for an image, what
    /// stands in for the half-second before there is.
    private var symbol: String {
        switch attachment.kind {
        case .image:    return "photo"
        case .pdf:      return "doc.richtext"
        case .document: return "doc.text"
        case .audio:    return "waveform"
        case .other:    return "paperclip"
        }
    }

    /// An image shows itself; everything else borrows the icon the Finder
    /// already has for it, the same way the upload canvas does.
    private func loadThumbnail() {
        let size = NSSize(width: 32, height: 32)
        if attachment.kind == .audio {
            // The chip draws its own control, so there is no icon to fetch —
            // only the length to put beside it.
            duration = try? AVAudioPlayer(contentsOf: attachment.url).duration
            return
        }
        if attachment.kind == .image, let image = NSImage(contentsOf: attachment.url) {
            image.size = size
            thumbnail = image
            return
        }
        let icon = NSWorkspace.shared.icon(forFile: attachment.url.path)
        icon.size = size
        thumbnail = icon
    }
}

/// The paperclip inside the reply bar.
///
/// Lives in the bar rather than above it so the card needs no extra row until
/// a file is actually attached.
struct AttachButton: View {
    @ObservedObject var state: AppState
    @State private var hovering = false

    var body: some View {
        Button { ReplyAttachmentStore.pickFiles(state: state) } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: hovering ? "#F5F6F8" : "#8E939C"))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Attach files")
    }
}
