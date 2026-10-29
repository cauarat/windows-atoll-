import SwiftUI

#if !APPSTORE

/// The AI Agents section.
struct AgentsSettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = AgentsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show AI Agents", isOn: $state.showAgentsPanel)
                    Text(loc: "A panel with the Claude account this Mac is signed in as, how much "
                         + "of the plan is left, and which Claude Code sessions are running. "
                         + "Put it on the island's border under Dynamic Island, or on the "
                         + "radial menu.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if state.showAgentsPanel {
                        Button("Open AI Agents") { AgentsPanelController.shared.open() }
                            .font(.system(size: 11))
                    }
                }
                .padding(6)
            }

            GroupBox("What it reads") {
                VStack(alignment: .leading, spacing: 8) {
                    line("~/.claude.json", "The account summary Claude Code keeps — the name "
                         + "on the account, the organisation if there is one, and whether a "
                         + "subscription was seen. Nothing else in that file is looked at.")
                    line("~/.claude/sessions", "One small file per running session: its folder, "
                         + "its status and its process. The `.key` file beside each one is a "
                         + "socket secret and is never opened.")
                    line("Your login token", "Never. It is in the Keychain, where Claude Code "
                         + "put it, and Notchy has no reason to go near it.")

                    Text(loc: "None of this is written down, and none of it leaves the Mac. "
                         + "Turn the toggle off and nothing is read at all.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .padding(6)
            }

            if state.showAgentsPanel {
                GroupBox("Right now") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: store.account.isSignedIn ? "#34D399" : "#8E939C"))
                                .frame(width: 8, height: 8)
                            Text(store.account.isSignedIn
                                 ? store.account.label
                                 : "No Claude Code account found on this Mac.")
                                .font(.system(size: 12))
                            Spacer()
                        }
                        // The limit, stated rather than implied: a recorded
                        // sign-in is not a working one, and the only way to
                        // tell would be to use the token.
                        Text(store.account.isSignedIn
                             ? "Whether that sign-in still works is not something Notchy can "
                               + "see — it would have to use the token to find out."
                             : "Run `claude login` in a terminal to sign in.")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6E737C"))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(store.sessions.count == 1
                             ? "1 session running."
                             : "\(store.sessions.count) sessions running.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(6)
                }
                .task { await store.refresh() }
            }
        }
    }

    private func line(_ what: String, _ why: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(what)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            Text(loc: why)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#6E737C"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#endif
