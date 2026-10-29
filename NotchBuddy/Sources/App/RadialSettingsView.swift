import SwiftUI

/// The wheel's settings.
struct RadialSettingsView: View {
    @ObservedObject var state: AppState
    @State private var trusted = RadialChordTap.isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Use the radial menu", isOn: $state.radialEnabled)
                    Text(loc: "Press the left and right mouse buttons together to open a wheel of "
                         + "shortcuts around the pointer. Flick toward one and let go, or let "
                         + "go without moving and click instead.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if state.radialEnabled { permissionRow }

                    Text(loc: "A trackpad cannot press both buttons at once, so this needs a mouse "
                         + "with two of them.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
            }

            GroupBox("What is on the wheel") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc: "Between \(RadialGeometry.minWedges) and \(RadialGeometry.maxWedges). "
                         + "Something unavailable stays in place and greys out rather than "
                         + "disappearing — the wheel is only quick while the same flick keeps "
                         + "meaning the same thing.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Array(state.radialSlots.enumerated()), id: \.offset) { i, slot in
                        slotRow(i, slot)
                    }

                    if state.radialSlots.count < RadialGeometry.maxWedges {
                        Menu {
                            ForEach(RadialAction.allCases) { a in
                                Button(a.title) { state.radialSlots.append(a.rawValue) }
                            }
                        } label: { Label("Add", systemImage: "plus") }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .padding(.top, 2)
                    }
                }
                .padding(6)
            }
        }
        .onAppear { trusted = RadialChordTap.isTrusted }
    }

    /// What the app actually knows about the permission, rather than a guess.
    @ViewBuilder private var permissionRow: some View {
        let ok = trusted && !state.radialTapFailed
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: ok ? "#34D399" : "#F5A524"))
                .frame(width: 8, height: 8)
            Text(ok ? "Accessibility granted."
                    : "Notchy needs Accessibility to see both buttons at once — and to stop "
                      + "the right-click menu appearing behind the wheel.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if !ok {
                Button("Open Settings") { RadialChordTap.openAccessibilitySettings() }
                    .font(.system(size: 11))
            }
        }
        .onChange(of: state.radialEnabled) { _, on in
            // Asked only when the feature is turned on: macOS shows this once
            // per app, so asking at launch would spend it on somebody who never
            // wanted the wheel.
            if on { trusted = RadialChordTap.requestTrust() }
        }
    }

    private func slotRow(_ i: Int, _ slot: String) -> some View {
        let action = RadialAction(rawValue: slot)
        return HStack(spacing: 8) {
            Image(systemName: action?.icon ?? "questionmark")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 16)
            Picker("", selection: Binding(
                get: { slot },
                set: { state.radialSlots[i] = $0 }
            )) {
                ForEach(RadialAction.allCases) { Text(loc: $0.title).tag($0.rawValue) }
            }
            .labelsHidden()
            Spacer()
            Button {
                guard i > 0 else { return }
                state.radialSlots.swapAt(i, i - 1)
            } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
            Button {
                guard i < state.radialSlots.count - 1 else { return }
                state.radialSlots.swapAt(i, i + 1)
            } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
            Button {
                guard state.radialSlots.count > RadialGeometry.minWedges else { return }
                state.radialSlots.remove(at: i)
            } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .disabled(state.radialSlots.count <= RadialGeometry.minWedges)
        }
    }
}
