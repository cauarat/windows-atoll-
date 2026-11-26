import SwiftUI

// MARK: - The phone's island
//
// The top of the screen is the island, hanging from the Dynamic Island the way it hangs from the
// notch on the Mac: black, rounded below, Mochi on the left, a card on the right that says whether
// the phone has reached its computer. The header has the island's tabs: Home and Chat, then Settings
// and sound on the right.

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
    @AppStorage("phoneSounds") private var sounds = true
    /// How tall the island came out, measured, so the toast sits right under it whatever card it holds.
    @State private var measured: CGFloat = 220

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color(hex: "#0E0F11").ignoresSafeArea()

                // Nothing is listed under the island; the scroll view is there for pull to refresh,
                // which tries the link again.
                ScrollView {
                    Color.clear.frame(height: max(0, measured - geo.safeAreaInsets.top + 6))
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
        .background(IslandShape(cornerRadius: 34, topRadius: 0).fill(Color.black))
        .clipShape(IslandShape(cornerRadius: 34, topRadius: 0))
        .background(GeometryReader { g in Color.clear.preference(key: IslandHeightKey.self, value: g.size.height) })
        .onPreferenceChange(IslandHeightKey.self) { h in measured = h }
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: tab)
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
        HStack(alignment: .center, spacing: 0) {
            SizedMochi(state: store.isConnected ? .idle : .sleeping, diameter: 62)
                .frame(width: 104)
            Group {
                if store.isConnected {
                    ConnectedCard()
                } else {
                    ConnectingCard()
                }
            }
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .transition(.opacity)
        }
        .padding(.vertical, 6)
        .padding(.bottom, 8)
    }
}

// MARK: - Island cards

/// Connected: the computer this phone reached, by name.
private struct ConnectedCard: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Connected")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(IslandPalette.text)
            Text(verbatim: store.computerName)
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

private struct IslandHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 220
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
