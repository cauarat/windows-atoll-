import SwiftUI

// MARK: - Settings on the phone
//
// Few, because the computer owns the real ones: which computer this is, whether Mochi talks, which
// notifications come, whether he goes to the Lock Screen, and unpairing.

struct SettingsSheet: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("phoneSounds") private var sounds = true
    @AppStorage("notifyFinished") private var notifyFinished = true
    @AppStorage(LiveActivityController.enabledKey) private var lockScreen = true
    @State private var confirmUnpair = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        MiniMochi(state: store.isConnected ? .idle : .sleeping, color: nil, character: MochiCharacter(), size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: store.computerName.isEmpty ? "—" : store.computerName)
                                .font(.system(size: 15, weight: .semibold))
                            Text(store.isConnected ? "Connected" : "Not connected")
                                .font(.system(size: 12))
                                .foregroundColor(store.isConnected ? IslandPalette.added : IslandPalette.secondary)
                        }
                    }
                    if let c = store.computer {
                        LabeledContent("Address") { Text(verbatim: "\(c.host):\(c.port)").monospaced().font(.system(size: 12)) }
                    }
                    if store.isConnected {
                        LabeledContent("Shared by your computer") {
                            Text(verbatim: sharedSummary).font(.system(size: 12)).multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text("Your computer")
                }

                Section {
                    Toggle("Sounds", isOn: $sounds)
                    Toggle("Notify me when an agent finishes", isOn: $notifyFinished)
                    Toggle("Mochi on the Lock Screen", isOn: $lockScreen)
                        .onChange(of: lockScreen) { _, on in if !on { LiveActivityController.shared.end() } }
                } footer: {
                    Text("Permission requests and questions always notify you. With no push server in between, notifications come while Notchy is open or was just put away.")
                }

                Section {
                    Button("Unpair this phone", role: .destructive) { confirmUnpair = true }
                } footer: {
                    Text("Notchy talks only to your computer, over your local network. No account, no server, no analytics.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: "#0E0F11"))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Unpair this phone?", isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button("Unpair", role: .destructive) {
                    store.unpair()
                    dismiss()
                }
            } message: {
                Text("To pair again, show the pairing code in Notchy's Settings on your computer and scan it.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var sharedSummary: String {
        var parts: [String] = [String(localized: "Agents")]
        if store.caps.contains("details") { parts.append(String(localized: "Steps")) }
        if store.caps.contains("diffs") { parts.append(String(localized: "Diffs")) }
        if store.caps.contains("answers") { parts.append(String(localized: "Questions")) }
        if store.caps.contains("chat") { parts.append(String(localized: "Chat")) }
        return parts.joined(separator: ", ")
    }
}
