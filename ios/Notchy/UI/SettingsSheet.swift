import SwiftUI

// MARK: - Settings on the phone
//
// Few, because the computer owns the real ones: which computer this is, whether Mochi talks, and
// unpairing.

struct SettingsSheet: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("phoneSounds") private var sounds = true
    @State private var confirmUnpair = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        MiniMochi(state: store.isConnected ? .idle : .sleeping, size: 40)
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
                } header: {
                    Text("Your computer")
                }

                Section {
                    Toggle("Sounds", isOn: $sounds)
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
}
