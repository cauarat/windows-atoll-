import SwiftUI

// MARK: - Chat (PromptView)

struct ChatPanel: View {
    @EnvironmentObject private var store: PhoneStore
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !store.caps.contains("chat") {
                Spacer()
                VStack(spacing: 10) {
                    MiniMochi(state: .sleeping, size: 54)
                    Text("Chat from the phone is off")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(IslandPalette.text)
                    Text("On your computer, turn on “Let the phone chat with my AI providers” in Notchy's Settings → General → Phone. Your keys stay there.")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "#9398A1"))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 30)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if store.chat.isEmpty {
                                VStack(spacing: 8) {
                                    MiniMochi(state: .idle, size: 54)
                                    Text("Ask Mochi anything.")
                                        .font(.system(size: 13))
                                        .foregroundColor(IslandPalette.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                            }
                            ForEach(store.chat) { entry in
                                bubble(entry).id(entry.id)
                            }
                            if store.chatRunningId != nil && store.chat.last?.role == .user {
                                TypingDots().id("typing")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: store.chat) { _, _ in
                        withAnimation { proxy.scrollTo(store.chat.last?.id, anchor: .bottom) }
                    }
                }
                composer
            }
        }
    }

    @ViewBuilder private func bubble(_ entry: PhoneStore.ChatEntry) -> some View {
        switch entry.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(verbatim: entry.text)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#F1F2F4"))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        case .assistant:
            ChatMarkdownView(markdown: entry.text)
        case .error:
            Text(verbatim: entry.text)
                .font(.system(size: 12.5))
                .foregroundColor(Color(hex: "#FF8D97"))
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(store.chatModels) { m in
                        Button { store.chatModelId = m.id } label: {
                            if m.id == store.chatModelId { Label(m.label, systemImage: "checkmark") } else { Text(verbatim: m.label) }
                        }
                    }
                    Divider()
                    Button(role: .destructive) { store.newChat() } label: { Label("New chat", systemImage: "square.and.pencil") }
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: store.chatModels.first { $0.id == store.chatModelId }?.label ?? "—")
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                    .font(.system(size: 11))
                    .foregroundColor(IslandPalette.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            HStack(spacing: 8) {
                TextField("Ask Mochi…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.system(size: 14))
                    .foregroundColor(IslandPalette.text)
                    .focused($focused)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                if store.chatRunningId != nil {
                    roundButton("stop.fill") { store.cancelChat() }
                } else {
                    roundButton("arrow.up") {
                        store.sendChat(draft)
                        draft = ""
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canChat)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(hex: "#0B0C0E"))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(hex: "#F5F6F8")))
        }
        .buttonStyle(PressStyle())
    }
}
