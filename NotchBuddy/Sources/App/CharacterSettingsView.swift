import SwiftUI

/// A character, drawn once and left alone — one tile of the picker grid.
///
/// Deliberately static: no `TimelineView`, no ticker. These are identity
/// swatches, not animations, and eighteen live engines breathing away in a
/// settings window would burn a core for nothing.
struct CharacterPreviewView: View {
    let character: MochiCharacter
    let colorHex: String
    var size: CGFloat = 54

    var body: some View {
        Canvas { context, canvasSize in
            let engine = BotEngine()
            engine.bodyColor = cgColorFromHex(colorHex)
            engine.character = character
            engine.setState(.idle, force: true)
            // One update so the idle pose settles, then pinned facing you with
            // its eyes open: a swatch should show the character, not a mood.
            engine.update(dt: 0.6)
            engine.yaw = 0; engine.pitch = 0; engine.roll = 0; engine.tilt = 0
            engine.open = 1; engine.sx = 1; engine.sy = 1; engine.ox = 0; engine.oy = 0
            engine.draw(context: context, size: canvasSize)
        }
        // The engine draws the body at 60 % of its canvas, and a crown needs
        // the rest.
        .frame(width: size / 0.6, height: size / 0.6)
    }
}

/// Who each pill is.
///
/// Pick whose character you are changing, click one of the eighteen, or set the
/// accessory and the eyes yourself. The colour is not here on purpose: it comes
/// from the pill, so the ClickMassa bot stays cyan whatever it wears and the
/// pill border still matches the creature inside it.
struct CharacterSettingsView: View {
    @ObservedObject var state: AppState

    /// Empty means the default, which covers every pill with no character of
    /// its own — and Mochi itself when nobody in particular is speaking.
    @State private var editing: String = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    private var current: MochiCharacter {
        editing.isEmpty ? state.defaultCharacter
                        : (state.pillCharacters[editing] ?? state.defaultCharacter)
    }

    private var currentColor: String {
        PillCatalog.definition(for: editing)?.color ?? "#F5F6F8"
    }

    private func write(_ character: MochiCharacter) {
        if editing.isEmpty {
            state.defaultCharacter = character
        } else {
            state.pillCharacters[editing] = character
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Give each pill its own face. The colour still comes from the pill, "
                     + "so you always know who is talking.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Character for", selection: $editing) {
                    Text("Everyone else (default)").tag("")
                    ForEach(PillCatalog.available.filter { !$0.comingSoon }, id: \.id) { def in
                        Text(def.name).tag(def.id)
                    }
                }

                grid

                Divider()

                Picker("Wearing", selection: Binding(
                    get: { current.accessory },
                    set: { write(MochiCharacter(accessory: $0, eye: current.eye)) }
                )) {
                    Text("Nothing").tag(MochiAccessory?.none)
                    ForEach(MochiAccessory.allCases, id: \.self) { item in
                        Text(item.label).tag(MochiAccessory?.some(item))
                    }
                }

                Picker("Eyes", selection: Binding(
                    get: { current.eye },
                    set: { write(MochiCharacter(accessory: current.accessory, eye: $0)) }
                )) {
                    Text("As they come").tag(MochiEye?.none)
                    ForEach(MochiEye.allCases, id: \.self) { item in
                        Text(item.label).tag(MochiEye?.some(item))
                    }
                }

                if !editing.isEmpty && state.pillCharacters[editing] != nil {
                    Button("Use the default for this one") {
                        state.pillCharacters.removeValue(forKey: editing)
                    }
                    .font(.system(size: 11))
                }
            }
            .padding(6)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(CharacterCatalog.presets, id: \.id) { preset in
                let chosen = preset.character == current
                Button(action: { write(preset.character) }) {
                    VStack(spacing: 1) {
                        CharacterPreviewView(character: preset.character,
                                             colorHex: currentColor,
                                             size: 46)
                        Text(preset.name)
                            .font(.system(size: 9.5))
                            .foregroundColor(chosen ? Color(hex: "#CFE3F7") : .secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity)
                    .background(chosen ? Color(hex: "#16222E") : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(chosen ? Color(hex: "#3B9EFF") : Color.white.opacity(0.08),
                                    lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
