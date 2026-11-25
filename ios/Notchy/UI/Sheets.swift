import SwiftUI

// MARK: - One session, up close
//
// What the island shows when a pill is opened: Mochi in the pill's colour, every step the computer
// sent (the current one shimmering), the agent's last line once it stopped, and the files it changed;
// a file opens its diff, read from the island on request.

struct SessionSheet: View {
    @EnvironmentObject private var store: PhoneStore
    let pillId: String

    var body: some View {
        let session = store.sessions.first { $0.pillId == pillId }
        ZStack {
            Color.black.ignoresSafeArea()
            if let session {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            SizedMochi(state: session.state, color: session.pillId == "integration_claude" ? nil : session.color,
                                       character: session.character, diameter: 54)
                                .frame(width: 90, height: 90)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: session.project ?? session.agent)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(IslandPalette.text)
                                HStack(spacing: 6) {
                                    Circle().fill(Color(hex: session.color ?? "#C0C4CC")).frame(width: 7, height: 7)
                                    Text(verbatim: session.agent).font(.system(size: 12.5)).foregroundColor(IslandPalette.secondary)
                                    Text(session.state.phoneLabel).font(.system(size: 12.5)).foregroundColor(IslandPalette.tertiary)
                                }
                                Text(verbatim: session.updatedAt.formatted(.relative(presentation: .named)))
                                    .font(.system(size: 11))
                                    .foregroundColor(IslandPalette.faint)
                            }
                            Spacer()
                        }

                        if let last = session.finalLine {
                            section("Last line") {
                                Text(verbatim: last)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundColor(IslandPalette.text)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        let steps = session.steps.isEmpty ? (session.statusText.isEmpty ? [] : [session.statusText]) : session.steps
                        if !steps.isEmpty {
                            section("Steps") {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                                        TickerRow(text: step, current: i == steps.count - 1 && session.state.isBusy)
                                    }
                                }
                            }
                        } else if !store.caps.contains("details") {
                            hint("Turn on “Show session details on the phone” in Notchy's Settings on your computer to see every step here.")
                        }

                        if !session.files.isEmpty {
                            section("Files changed") {
                                VStack(spacing: 0) {
                                    ForEach(session.files.reversed()) { file in
                                        Button { store.openDiff(pillId: session.pillId, file: file) } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: file.isNew ? "doc.badge.plus" : "doc.text")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(IslandPalette.secondary)
                                                    .frame(width: 18)
                                                Text(verbatim: file.name)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(Color(hex: "#C9CDD4"))
                                                    .lineLimit(1).truncationMode(.middle)
                                                Spacer(minLength: 6)
                                                LineCounts(added: file.added, removed: file.removed)
                                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundColor(IslandPalette.faint)
                                            }
                                            .padding(.vertical, 9)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(PressStyle())
                                    }
                                }
                            }
                        } else if !store.caps.contains("diffs") {
                            hint("Turn on “Show the files an agent changed on the phone” on your computer to read diffs here.")
                        }
                    }
                    .padding(20)
                }
            } else {
                Text("This session has ended.").foregroundColor(IslandPalette.secondary)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(IslandPalette.tertiary)
                .textCase(.uppercase)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(wash: nil))
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundColor(IslandPalette.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - A file's diff (DiffCardView)

struct DiffSheet: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let d = store.diff {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(verbatim: d.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(IslandPalette.text)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        LineCounts(added: d.added, removed: d.removed, size: 11)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 10)

                    if d.gone {
                        note("Your computer no longer has this change.")
                    } else if d.tooLarge {
                        note("Diff too large")
                    } else if d.loading {
                        HStack { Spacer(); ProgressView().tint(IslandPalette.secondary); Spacer() }.padding(.top, 30)
                    } else if d.rows.isEmpty {
                        note("No changes")
                    } else {
                        ScrollView([.vertical]) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(d.rows.enumerated()), id: \.offset) { _, row in
                                    DiffLineRow(row: row)
                                }
                                if d.truncated {
                                    note("The rest of this diff is on your computer.")
                                        .padding(.top, 8)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 20)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundColor(IslandPalette.tertiary)
            .padding(.horizontal, 16)
    }
}

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
                    MiniMochi(state: .sleeping, color: nil, character: MochiCharacter(), size: 54)
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
                                    MiniMochi(state: .idle, color: nil, character: MochiCharacter(), size: 54)
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
