import AppKit
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

            Text(attachment.sizeLabel)
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
        if let thumbnail {
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
        case .other:    return "paperclip"
        }
    }

    /// An image shows itself; everything else borrows the icon the Finder
    /// already has for it, the same way the upload canvas does.
    private func loadThumbnail() {
        let size = NSSize(width: 32, height: 32)
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
