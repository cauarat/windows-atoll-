import SwiftUI

/// Home, when it is holding a message.
///
/// The difference from `MessageView` is which message, and that is the whole
/// point. `MessageView` shows `inbox.active` — the newest **unread** — so it
/// empties the moment you answer. This shows the newest from a source whether
/// or not it has been read, so the notification is still here when you come
/// back to Home after it has folded away.
struct HomeMessageView: View {
    @ObservedObject var state: AppState
    let content: HomeContent

    @ObservedObject private var inbox = MessageInbox.shared

    @State private var text: String = ""
    @State private var sending = false
    @State private var failure: String?
    @State private var shownID: String?
    @FocusState private var focused: Bool

    private var message: InboxMessage? {
        MessageInbox.resolveHomeMessage(for: content,
                                        last: inbox.lastBySource,
                                        lastSource: inbox.lastSource)
    }

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            if let message {
                VStack(alignment: .leading, spacing: 6) {
                    whoRow(message)
                    Text(failure ?? message.body)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: failure == nil ? "#9398A1" : "#FF8D97"))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !state.replyAttachments.isEmpty {
                        ReplyAttachmentsRow(state: state)
                    }
                    replyRow(message)
                }
                // 16, not 116: Mochi moved into the who-row, so the gutter is
                // the message's now. Same change as the card this mirrors.
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .onAppear { resetIfNew(message) }
                .onChange(of: message.id) { _, _ in resetIfNew(message) }
            } else {
                Text(emptyLine)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .padding(.leading, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onDisappear { release() }
    }

    private var emptyLine: String {
        switch content {
        case .clickMassa: return "Nothing from ClickMassa yet."
        case .mattermost: return "Nothing from Mattermost yet."
        default:          return "No messages yet."
        }
    }

    // MARK: – Rows

    private func whoRow(_ message: InboxMessage) -> some View {
        HStack(spacing: 6) {
            MessageMochi(source: message.source)
            Text(message.sender.isEmpty ? message.source.displayName : message.sender)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
                .lineLimit(1)
            Text(origin(message))
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#8E939C"))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(message.timeAgo())
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
                .fixedSize()
        }
    }

    private func replyRow(_ message: InboxMessage) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                // Absent for a source that cannot carry a file.
                if canAttach(message) {
                    AttachButton(state: state)
                }

                TextField("Reply to \(message.sender.isEmpty ? message.source.displayName : message.sender)…",
                          text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focused)
                    .disabled(sending || message.conversationID == nil)
                    .onSubmit { send(message) }

                Button { send(message) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#0B0C0E"))
                }
                .buttonStyle(SendButtonStyle())
                .disabled(!canSend || sending)
                .opacity(sending ? 0.4 : 1)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(focused ? 0.12 : 0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(hex: "#22C55E"),
                                  lineWidth: state.replyDragOver ? 1.5 : 0)
            )
            // Asking for the keyboard first, in the same turn, is what makes the
            // click land: the island's panel never takes it on its own.
            .simultaneousGesture(TapGesture().onEnded {
                NotificationCenter.default.post(name: .islandWantsKeyboard, object: nil)
                focused = true
            })

            if message.link != nil {
                SecondaryButton("Open") { open(message) }
            }
        }
        .onChange(of: focused) { _, isFocused in
            state.isReplying = isFocused
            state.isPinned = isFocused
        }
    }

    // MARK: – Behaviour

    private func origin(_ message: InboxMessage) -> String {
        if let channel = message.channel, !channel.isEmpty { return "in \(channel)" }
        return "\(message.source.displayName) · direct"
    }

    private func resetIfNew(_ message: InboxMessage) {
        guard shownID != message.id else { return }
        shownID = message.id
        text = ""
        failure = nil
        sending = false
        // Files staged for the last sender must not ride along to the next.
        ReplyAttachmentStore.clear(state: state)
    }

    private func release() {
        focused = false
        state.isReplying = false
        state.isPinned = false
        ReplyAttachmentStore.clear(state: state)
    }

    private func open(_ message: InboxMessage) {
        guard let link = message.link else { return }
        NSWorkspace.shared.open(link)
    }

    /// Sends, and stays put. Unlike the notification card this never collapses
    /// the island afterwards — you opened Home yourself, so nothing should take
    /// it away.
    /// Whether this message's source can carry files at all.
    private func canAttach(_ message: InboxMessage) -> Bool {
        message.conversationID != nil && message.source.supportsAttachments
    }

    /// Words or files; neither alone is required, but one of them is.
    private var canSend: Bool {
        !text.trimmed.isEmpty || !state.replyAttachments.isEmpty
    }

    private func send(_ message: InboxMessage) {
        let body = text.trimmed
        let attachments = state.replyAttachments
        guard !body.isEmpty || !attachments.isEmpty,
              !sending, let conversation = message.conversationID else { return }
        sending = true
        failure = nil
        _ = conversation
        Task {
            do {
                try await MessageInbox.shared.reply(to: message, text: body,
                                                    attachments: attachments)
                await MainActor.run {
                    sending = false
                    text = ""
                    ReplyAttachmentStore.clear(state: state)
                    SoundEngine.shared.play("send")
                }
            } catch {
                await MainActor.run {
                    sending = false
                    failure = error.localizedDescription
                }
            }
        }
    }
}
