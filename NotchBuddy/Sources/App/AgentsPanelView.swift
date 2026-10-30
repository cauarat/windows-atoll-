import SwiftUI

#if !APPSTORE

/// The panel's contents: who you are signed in as, how much of the plan is
/// left, and what is running.
struct AgentsPanelView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var store = AgentsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.12)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    accountCard
                    sessionsCard
                }
                .padding(14)
            }
        }
        .background(Color(hex: "#0B0C0E"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.08), lineWidth: 1))
        .task { await store.refresh() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundColor(Color(hex: "#E07950"))
            Text("AI Agents")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button { AgentsPanelController.shared.close() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: – Account

    @ViewBuilder private var accountCard: some View {
        card("Account") {
            if store.account.isSignedIn {
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: "#34D399")).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.account.label)
                            .font(.system(size: 12, weight: .medium))
                        if let org = store.account.organization {
                            Text(org).font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                if let fetched = store.account.profileFetched {
                    Text("Claude Code last refreshed this \(relative(fetched)).")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6E737C"))
                }
                // The honest part. A file saying somebody signed in is not the
                // same as a token that still works, and there is no way to tell
                // the difference without using the token — which is not ours.
                Text(loc: "This is the account Claude Code recorded on this Mac. "
                     + "Whether its sign-in is still valid is not something Notchy can see.")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#6E737C"))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: "#8E939C")).frame(width: 8, height: 8)
                    Text("No Claude Code account found on this Mac.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Text(loc: "Run `claude login` in a terminal. Notchy never handles your "
                     + "token — it stays in the Keychain where Claude Code puts it.")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#6E737C"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: – Sessions

    @ViewBuilder private var sessionsCard: some View {
        card("Running here") {
            if store.sessions.isEmpty {
                Text("No Claude Code sessions running.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.sessions) { s in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: s.status == "working" ? "#F5A524" : "#34D399"))
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.name ?? s.project)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(s.cwd)
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#6E737C"))
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        Spacer()
                        Text(s.status)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: – Shape

    @ViewBuilder
    private func card(_ title: String, @ViewBuilder _ body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color(hex: "#6E737C"))
            body()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(hex: IslandConst.cardHex))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Color.white.opacity(0.05), lineWidth: 1))
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }
}

#endif
