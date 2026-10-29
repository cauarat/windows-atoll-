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
/// from the pill, so the ClickMassa bot keeps ClickMassa's colour whatever it
/// wears and the pill border still matches the creature inside it.
struct CharacterSettingsView: View {
    @ObservedObject var state: AppState

    /// Empty means the default, which covers every pill with no character of
    /// its own — and Mochi itself when nobody in particular is speaking.
    @State private var editing: String = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)
    private let bodyColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    /// Classic first, then the six.
    private var bodies: [MochiShape?] { [nil] + MochiShape.allCases.map(Optional.some) }

    private var current: MochiCharacter {
        editing.isEmpty ? state.defaultCharacter
                        : (state.pillCharacters[editing] ?? state.defaultCharacter)
    }

    private var currentColor: String {
        PillCatalog.definition(for: editing)?.color ?? "#F5F6F8"
    }

    /// Whose face is on the bench. The picker that chooses it sits at the top
    /// of a panel that scrolls, so by the time you reach the grids it is gone —
    /// and every tile you click writes to whoever is still selected up there.
    /// Each section says the name instead of making you scroll back.
    private var editingName: String {
        editing.isEmpty ? "everyone else"
                        : (PillCatalog.definition(for: editing)?.name ?? editing)
    }

    /// The pills with a face of their own, in the picker's order.
    ///
    /// They are the reason editing the default can look like it did nothing:
    /// `AppState.character(for:)` hands back a pill's own character before it
    /// ever reaches `defaultCharacter`, so these stay exactly as they are while
    /// everything else changes.
    private var overriding: [PillDefinition] {
        PillCatalog.available.filter { !$0.comingSoon && state.pillCharacters[$0.id] != nil }
    }

    /// A section heading, with the name of whoever it is editing.
    private func sectionLabel(_ title: String) -> some View {
        (Text(loc: title) + Text("  for \(editingName)").foregroundColor(.secondary.opacity(0.65)))
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
    }

    private func write(_ character: MochiCharacter) {
        if editing.isEmpty {
            state.defaultCharacter = character
        } else {
            state.pillCharacters[editing] = character
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            offSwitch

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(loc: "Give each pill its own face. The colour still comes from the pill, "
                         + "so you always know who is talking.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker("Character for", selection: $editing) {
                        Text("Everyone else (default)").tag("")
                        ForEach(PillCatalog.available.filter { !$0.comingSoon }, id: \.id) { def in
                            Text(loc: def.name).tag(def.id)
                        }
                    }

                    sectionLabel("Body")

                    bodyRow

                    Divider()

                    sectionLabel("Face")

                    grid

                    Divider()

                    sectionLabel("Wearing and eyes")

                    Picker("Wearing", selection: Binding(
                        get: { current.accessory },
                        set: { write(MochiCharacter(accessory: $0, eye: current.eye, shape: current.shape)) }
                    )) {
                        Text("Nothing").tag(MochiAccessory?.none)
                        ForEach(MochiAccessory.allCases, id: \.self) { item in
                            Text(loc: item.label).tag(MochiAccessory?.some(item))
                        }
                    }

                    Picker("Eyes", selection: Binding(
                        get: { current.eye },
                        set: { write(MochiCharacter(accessory: current.accessory, eye: $0, shape: current.shape)) }
                    )) {
                        Text("As they come").tag(MochiEye?.none)
                        ForEach(MochiEye.allCases, id: \.self) { item in
                            Text(loc: item.label).tag(MochiEye?.some(item))
                        }
                    }

                    if !editing.isEmpty && state.pillCharacters[editing] != nil {
                        Button("Use the default for this one") {
                            state.pillCharacters.removeValue(forKey: editing)
                        }
                        .font(.system(size: 11))
                    }

                    // The default is not the last word, and nothing else here says
                    // so: a pill with a face of its own keeps it, so changing the
                    // default above leaves that pill in the notch exactly as it
                    // was. That is the whole "I changed it and nothing happened".
                    if editing.isEmpty && !overriding.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text(loc: "Keeping a face of their own, so the default above "
                                 + "does not reach them: "
                                 + overriding.map(\.name).joined(separator: ", ") + ".")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button("Give them the default too") {
                                for pill in overriding {
                                    state.pillCharacters.removeValue(forKey: pill.id)
                                }
                            }
                            .font(.system(size: 11))
                        }
                    }
                }
                .padding(6)
            }
            .disabled(state.hideCharacters)
            .opacity(state.hideCharacters ? 0.4 : 1)
        }
    }

    /// The whole feature, off.
    ///
    /// Above the picker because it is the question that comes first: whether
    /// there is a character at all, before whose and which. The grids below
    /// stay on screen while it is on, dimmed and inert — you should be able to
    /// see what you have put away.
    private var offSwitch: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Hide the characters", isOn: $state.hideCharacters)

                Text(loc: "Mochi and the little ones stop appearing, and every card closes the "
                     + "gap it was leaving for a face. Nothing else changes: the player, "
                     + "your messages, the timer, the pills and the agents all carry on. "
                     + "He still rides the compact bar, and still comes out to catch a "
                     + "file you drop on the notch.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
        }
    }

    /// Classic plus the six bodies, each wearing whatever face is chosen now.
    ///
    /// Its own row rather than more tiles in the grid: body and face are
    /// independent, and folding them together would mean 7 x 18 tiles to say
    /// the same thing.
    private var bodyRow: some View {
        LazyVGrid(columns: bodyColumns, spacing: 6) {
            ForEach(Array(bodies.enumerated()), id: \.offset) { _, shape in
                let chosen = current.shape == shape
                Button(action: {
                    write(MochiCharacter(accessory: current.accessory, eye: current.eye, shape: shape))
                }) {
                    VStack(spacing: 1) {
                        CharacterPreviewView(
                            character: MochiCharacter(accessory: current.accessory,
                                                      eye: current.eye, shape: shape),
                            colorHex: currentColor,
                            size: 42)
                        Text(loc: shape?.label ?? "Classic")
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

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(CharacterCatalog.presets, id: \.id) { preset in
                // The face only. The body is the row above, so a Frog wearing
                // Royal is still Royal and the grid still says so.
                let chosen = preset.character.accessory == current.accessory
                          && preset.character.eye == current.eye
                Button(action: {
                    write(MochiCharacter(accessory: preset.character.accessory,
                                         eye: preset.character.eye,
                                         shape: current.shape))
                }) {
                    VStack(spacing: 1) {
                        CharacterPreviewView(
                            character: MochiCharacter(accessory: preset.character.accessory,
                                                      eye: preset.character.eye,
                                                      shape: current.shape),
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
