import SwiftUI

// MARK: - The phone's island
//
// The top of the screen is the island, hanging from the Dynamic Island the way it hangs from the
// notch on the Mac: black, rounded below, Mochi on the left, the island's own cards on the right —
// the session in focus with its ticker, a permission request with Deny and Allow, Claude's question.
// The agents are listed under it, one card per pill, as the island's pill column lists them. The
// header has the island's tabs: Home and Chat, then Settings and sound on the right.

enum PhoneTab { case home, chat }

struct MainView: View {
    @EnvironmentObject private var store: PhoneStore
    @State private var tab: PhoneTab = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["NOTCHY_DEMO"] == "chat" { return .chat }
        #endif
        return .home
    }()
    @State private var showSettings = false
    @State private var sheetSession: SessionInfo?
    @AppStorage("phoneSounds") private var sounds = true
    /// How tall the island came out, measured, so the list starts right under it whatever card it holds.
    @State private var measured: CGFloat = 220

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color(hex: "#0E0F11").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 10) {
                        Color.clear.frame(height: max(0, measured - geo.safeAreaInsets.top + 6))
                        if tab == .home { agents }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
                }
                .scrollDisabled(tab == .chat)
                .refreshable { store.retry() }

                island(geo)

                if let toast = store.toast {
                    Text(verbatim: toast)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(IslandPalette.text)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(Color(hex: "#1D1F23")))
                        .overlay(Capsule().stroke(Color.white.opacity(0.06)))
                        .padding(.top, max(0, measured - geo.safeAreaInsets.top + 12))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(store) }
        .sheet(item: $sheetSession) { s in SessionSheet(pillId: s.pillId).environmentObject(store) }
        .sheet(isPresented: Binding(get: { store.diff != nil }, set: { if !$0 { store.closeDiff() } })) {
            DiffSheet().environmentObject(store)
        }
    }

    // MARK: The island

    private func island(_ geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geo.safeAreaInsets.top)
            header
                .frame(height: 40)
            switch tab {
            case .home:
                // As tall as its card, like the island on the Mac.
                islandBody
                    .frame(minHeight: 122)
                    .fixedSize(horizontal: false, vertical: true)
            case .chat:
                ChatPanel()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: geo.size.width - 8)
        .frame(height: tab == .chat ? geo.size.height + geo.safeAreaInsets.top - 12 : nil, alignment: .top)
        .background(
            ZStack {
                IslandShape(cornerRadius: 34, topRadius: 0).fill(Color.black)
                // The card's wash, rising from below: amber while a command waits, cyan for a question.
                RadialGradient(gradient: Gradient(stops: [
                    .init(color: CardBackground(wash: islandWash).washColor, location: 0),
                    .init(color: .clear, location: 0.7),
                ]), center: UnitPoint(x: 0.5, y: 1.3), startRadius: 0, endRadius: 320)
                .clipShape(IslandShape(cornerRadius: 34, topRadius: 0))
                .animation(.easeInOut(duration: 0.3), value: islandWash)
            }
        )
        .clipShape(IslandShape(cornerRadius: 34, topRadius: 0))
        .background(GeometryReader { g in Color.clear.preference(key: IslandHeightKey.self, value: g.size.height) })
        .onPreferenceChange(IslandHeightKey.self) { h in measured = h }
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: tab)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: store.approval)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: store.question)
    }

    private var islandWash: CardBackground.Wash? {
        guard tab == .home else { return nil }
        if store.approval != nil { return .amber }
        if store.question != nil { return .cyan }
        switch store.sessions.first(where: { $0.pillId == store.focusedPillId })?.state {
        case .finished: return .green
        case .error: return .red
        default: return nil
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                TabButton(mark: Image(systemName: "house.fill"), isOn: tab == .home) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tab = .home }
                }
                TabButton(mark: ChatSparkleIcon(), isOn: tab == .chat) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tab = .chat }
                }
            }
            .padding(.leading, 10)
            Spacer()
            ConnectionDot()
            HStack(spacing: 4) {
                iconButton(sounds ? "speaker.wave.2" : "speaker.slash") { sounds.toggle() }
                iconButton("gearshape") { showSettings = true }
            }
            .padding(.trailing, 12)
        }
    }

    private func iconButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 14))
                .foregroundColor(IslandPalette.secondary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var islandBody: some View {
        let focus = store.sessions.first { $0.pillId == store.focusedPillId }
        let botState: BotState = store.approval != nil ? .approval : store.question != nil ? .question
            : store.isConnected ? (focus?.state ?? .idle) : .sleeping
        HStack(alignment: .center, spacing: 0) {
            SizedMochi(state: botState, color: botColor(focus), character: focus?.character ?? MochiCharacter(), diameter: 62)
                .frame(width: 104)
            Group {
                if let approval = store.approval {
                    ApprovalCard(request: approval)
                } else if let question = store.question {
                    QuestionCard(request: question)
                } else if !store.isConnected {
                    ConnectingCard()
                } else if let focus {
                    FocusCard(session: focus) { sheetSession = focus }
                } else {
                    EmptyCard()
                }
            }
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .transition(.opacity)
        }
        .padding(.vertical, 6)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: store.approval)
        .animation(.easeInOut(duration: 0.2), value: store.question)
    }

    /// Claude Code wears the state's colours; a pill with a brand colour of its own wears that.
    private func botColor(_ s: SessionInfo?) -> String? {
        guard let s, let c = s.color, s.pillId != "integration_claude", c.uppercased() != "#F5F6F8" else { return nil }
        return c
    }

    // MARK: The agents

    @ViewBuilder private var agents: some View {
        if !store.sessions.isEmpty {
            HStack {
                Text("Agents")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(IslandPalette.secondary)
                Spacer()
                if !store.computerName.isEmpty {
                    Text(verbatim: store.computerName)
                        .font(.system(size: 11))
                        .foregroundColor(IslandPalette.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            ForEach(store.sessions) { s in
                AgentRow(session: s, focused: s.pillId == store.focusedPillId)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { store.focusedPillId = s.pillId }
                        sheetSession = s
                    }
            }
        } else if store.isConnected {
            Text("No agent sessions on your computer yet. Start Claude Code there and it shows up here.")
                .font(.system(size: 12.5))
                .foregroundColor(IslandPalette.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 30)
                .padding(.horizontal, 30)
        }
    }
}

// MARK: - Island cards

private struct ApprovalCard: View {
    @EnvironmentObject private var store: PhoneStore
    let request: ApprovalRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            AgentWho(name: store.agentName(request.pillId), color: color, label: String(localized: "needs permission"))
            ScrollView(.vertical, showsIndicators: false) {
                CodeBlock(text: request.command.isEmpty ? request.tool : request.command)
            }
            .frame(maxHeight: 64)
            .fixedSize(horizontal: false, vertical: true)
            if request.truncated {
                Text("Command is longer than shown. Allow it on your computer.")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#F5A524"))
            }
            HStack(spacing: 8) {
                SecondaryButton("Deny") { Task { await store.decide(allow: false) } }
                if !request.truncated {
                    PrimaryButton("Allow", systemImage: "faceid") { Task { await store.decide(allow: true) } }
                }
            }
        }
    }

    private var color: String? { store.sessions.first { $0.pillId == request.pillId }?.color }
}

private struct QuestionCard: View {
    @EnvironmentObject private var store: PhoneStore
    let request: QuestionRequest
    @State private var index = 0
    @State private var picks: [[String]] = []

    var body: some View {
        let qi = min(index, request.questions.count - 1)
        let item = request.questions[qi]
        let isLast = qi == request.questions.count - 1
        let current = qi < picks.count ? picks[qi] : []
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                AgentWho(name: nil, label: String(localized: "\(store.agentName(request.pillId)) is asking"))
                Spacer(minLength: 4)
                if request.questions.count > 1 {
                    Text(verbatim: "\(qi + 1)/\(request.questions.count)")
                        .font(.system(size: 10))
                        .foregroundColor(IslandPalette.tertiary)
                }
            }
            Text(verbatim: item.question)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(IslandPalette.text)
                .lineLimit(2)
            ChipFlowLayout(spacing: 6) {
                    ForEach(Array(item.options.enumerated()), id: \.offset) { _, opt in
                        let selected = current.contains(opt.label)
                        if item.multiSelect {
                            Button {
                                toggle(qi, opt.label)
                            } label: {
                                Text(verbatim: opt.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(selected ? Color(hex: "#22D3EE").opacity(0.22) : Color.white.opacity(0.07))
                                    .foregroundColor(selected ? Color(hex: "#67E8F9") : Color(hex: "#C5C8CD"))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color(hex: "#22D3EE").opacity(0.55) : Color.white.opacity(0.1), lineWidth: 1))
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                        } else {
                            SecondaryButton(verbatim: opt.label) { pick(qi, opt.label, isLast: isLast) }
                        }
                    }
            }
            if item.multiSelect {
                PrimaryButton(isLast ? "Send" : "Next") { proceed(qi, isLast: isLast) }
                    .disabled(current.isEmpty)
                    .opacity(current.isEmpty ? 0.4 : 1)
            }
        }
        .onAppear { reset() }
        .onChange(of: request.fingerprint) { _, _ in reset() }
    }

    private func reset() {
        index = 0
        picks = Array(repeating: [], count: request.questions.count)
    }

    private func toggle(_ qi: Int, _ label: String) {
        guard qi < picks.count else { return }
        if let i = picks[qi].firstIndex(of: label) { picks[qi].remove(at: i) } else { picks[qi].append(label) }
    }

    private func pick(_ qi: Int, _ label: String, isLast: Bool) {
        guard qi < picks.count else { return }
        picks[qi] = [label]
        proceed(qi, isLast: isLast)
    }

    private func proceed(_ qi: Int, isLast: Bool) {
        if isLast {
            let answer = picks
            Task { await store.answer(answer) }
        } else {
            withAnimation { index = qi + 1 }
        }
    }
}

private struct FocusCard: View {
    let session: SessionInfo
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: session.color ?? "#C0C4CC")).frame(width: 7, height: 7)
                Text(verbatim: session.project ?? session.agent)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(IslandPalette.text)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(verbatim: session.project == nil ? "" : session.agent)
                    .font(.system(size: 11))
                    .foregroundColor(IslandPalette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if session.stepCount > 1 {
                    Text(verbatim: "\(min(session.stepIndex + 1, session.stepCount))/\(session.stepCount)")
                        .font(.system(size: 11))
                        .foregroundColor(IslandPalette.tertiary)
                        .fixedSize()
                }
                Button(action: open) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(hex: "#5F646D"))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(tickerLines.enumerated()), id: \.offset) { i, line in
                    TickerRow(text: line, current: i == tickerLines.count - 1 && session.state.isBusy)
                }
            }
            .padding(.top, 2)
            if session.state == .finished, let last = session.finalLine {
                Text(verbatim: last)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(IslandPalette.text)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }

    /// The last two steps, as the island's ticker shows them, or what the pill is doing.
    private var tickerLines: [String] {
        let steps = session.steps.isEmpty ? (session.statusText.isEmpty ? [] : [session.statusText]) : session.steps
        if steps.isEmpty { return [String(localized: "Waiting for the next prompt")] }
        return Array(steps.suffix(session.state == .finished ? 1 : 2))
    }
}

private struct EmptyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Nothing running right now.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(IslandPalette.text)
            Text("Start Claude Code on your computer and Mochi follows it from here.")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#9398A1"))
        }
    }
}

private struct ConnectingCard: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(IslandPalette.text)
            Text(detail)
                .font(.system(size: 12.5))
                .foregroundColor(Color(hex: "#9398A1"))
                .fixedSize(horizontal: false, vertical: true)
            if store.status == .unauthorized {
                SecondaryButton("Pair again") { store.unpair() }
            } else {
                SecondaryButton("Try again") { store.retry() }
            }
        }
    }

    private var title: String {
        switch store.status {
        case .unauthorized: return String(localized: "Not paired any more")
        case .connecting: return String(localized: "Connecting to \(store.computerName)…")
        default: return String(localized: "Looking for \(store.computerName)…")
        }
    }

    private var detail: String {
        switch store.status {
        case .unauthorized:
            return String(localized: "Your computer made a new pairing code. Scan it again from Settings → General → Phone.")
        default:
            return String(localized: "Same Wi-Fi as your computer? Notchy must be running there, with the phone link on.")
        }
    }
}

private struct ConnectionDot: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        Circle()
            .fill(store.isConnected ? IslandPalette.added : (store.status == .unauthorized ? IslandPalette.removed : Color(hex: "#F5A524")))
            .frame(width: 6, height: 6)
            .padding(.trailing, 6)
            .accessibilityLabel(Text(store.isConnected ? "Connected" : "Not connected"))
    }
}

// MARK: - A pill

struct AgentRow: View {
    let session: SessionInfo
    var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            MiniMochi(state: session.state, color: session.color, character: session.character, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: session.project ?? session.agent)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(IslandPalette.text)
                        .lineLimit(1)
                    if session.project != nil {
                        Text(verbatim: session.agent)
                            .font(.system(size: 12))
                            .foregroundColor(IslandPalette.secondary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 5) {
                    Text(session.state.phoneLabel)
                        .font(.system(size: 12))
                        .foregroundColor(stateColor)
                    if !session.statusText.isEmpty && session.state.isBusy {
                        Text(verbatim: "· " + session.statusText)
                            .font(.system(size: 12))
                            .foregroundColor(IslandPalette.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 4)
            if !session.files.isEmpty {
                let added = session.files.reduce(0) { $0 + $1.added }
                let removed = session.files.reduce(0) { $0 + $1.removed }
                LineCounts(added: added, removed: removed, size: 10)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(IslandPalette.faint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(CardBackground(wash: wash))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(focused ? 0.12 : 0), lineWidth: 1))
        .contentShape(Rectangle())
    }

    private var wash: CardBackground.Wash? {
        switch session.state {
        case .approval: return .amber
        case .question: return .cyan
        case .error: return .red
        case .finished: return .green
        default: return nil
        }
    }

    private var stateColor: Color {
        switch session.state {
        case .working: return Color(hex: "#7CC0FF")
        case .thinking: return Color(hex: "#C4B5FD")
        case .searching: return Color(hex: "#A5B4FC")
        case .approval: return Color(hex: "#F5A524")
        case .question: return Color(hex: "#67E8F9")
        case .error: return Color(hex: "#FF8D97")
        case .finished: return Color(hex: "#6EE7B7")
        default: return IslandPalette.tertiary
        }
    }
}

extension BotState {
    var isBusy: Bool { [.working, .thinking, .searching].contains(self) }
}

private struct IslandHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 220
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
