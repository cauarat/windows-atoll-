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
            engine.festiveStill = true
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

/// One tile of a character picker: the creature, its name under it, and the blue
/// ring when it is the one chosen.
///
/// Shared by the Characters page and the welcome's look screen, so the two
/// pickers cannot drift apart. Generic over the preview so the welcome can show
/// Ato's orb in the same frame; the Characters page uses the Mochi initialiser
/// below, which draws exactly what it always has.
struct CharacterTile<Preview: View>: View {
    /// A catalogue key, translated here where it is drawn.
    let name: String
    let chosen: Bool
    /// Long names — the Christmas parts — may shrink a little before they are cut.
    var shrinksName = false
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                preview()
                Text(loc: name)
                    .font(.system(size: 9.5))
                    .foregroundColor(chosen ? Color(hex: "#CFE3F7") : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(shrinksName ? 0.8 : 1)
                    .padding(.horizontal, shrinksName ? 2 : 0)
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

extension CharacterTile where Preview == CharacterPreviewView {
    /// A Mochi wearing `character`, in `colorHex`.
    init(character: MochiCharacter, colorHex: String, name: String, chosen: Bool,
         size: CGFloat = 46, shrinksName: Bool = false, action: @escaping () -> Void) {
        self.init(name: name, chosen: chosen, shrinksName: shrinksName, action: action) {
            CharacterPreviewView(character: character, colorHex: colorHex, size: size)
        }
    }
}

/// Ato, still, in the frame a `CharacterPreviewView` gives a Mochi — a picker
/// tile for the one pill that is not one. All it can wear is Christmas.
struct AtoCharacterPreviewView: View {
    let festive: MochiFestive?
    var size: CGFloat = 54

    /// At rest, eyes open: the pose `AtoLogo` draws.
    private static let scene = AtoBot.scene(AtoBot.poseAt(.idle, 0))

    var body: some View {
        Canvas { context, canvasSize in
            AtoBotView.draw((scene: Self.scene, motion: .identity), in: context,
                            size: canvasSize, festive: festive)
        }
        .frame(width: size / 0.6, height: size / 0.6)
    }
}

/// Who each pill is.
///
/// Pick whose character you are changing, click one of the eighteen, or set the
/// accessory and the eyes yourself. The colour is not here on purpose: it comes
/// from the pill, so the Mattermost bot keeps Mattermost's colour whatever it
/// wears and the pill border still matches the creature inside it.
///
/// Ato is not a Mochi at all but Ato's own mascot (`AtoBotView`), and the body,
/// the faces and the two pickers have nothing to say to an orb. It is in the
/// list for the one thing it can wear, Christmas, and only while there is
/// Christmas to pick or to take off.
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
        L(key: editing.isEmpty ? "everyone else"
                               : (PillCatalog.definition(for: editing)?.name ?? editing))
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

    // MARK: Christmas

    private var isAto: Bool { editing == MessageSource.ato.pillID }

    /// Whether Christmas is on offer today. Always in a debug build, so the
    /// block can be worked on in any month.
    private var christmasOpen: Bool {
        #if DEBUG
        return true
        #else
        return MochiFestive.isInSeason(Date())
        #endif
    }

    private var currentFestive: MochiFestive { current.festive ?? MochiFestive() }

    /// The block is there in season — and, out of it, for anyone still wearing
    /// something, because a hat nobody can take off until next December is a
    /// trap rather than a season.
    private var showsChristmas: Bool { christmasOpen || !currentFestive.isEmpty }

    /// Who the picker lists. Ato only while the block has something for it.
    private var pickable: [PillDefinition] {
        let ato = MessageSource.ato.pillID
        return PillCatalog.available.filter { def in
            guard !def.comingSoon else { return false }
            guard def.id == ato else { return true }
            return editing == ato || christmasOpen
                || !(state.character(for: ato).festive?.isEmpty ?? true)
        }
    }

    private func write(festive: MochiFestive) {
        var character = current
        character.festive = festive.orNil
        write(character)
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
                        ForEach(pickable, id: \.id) { def in
                            Text(loc: def.name).tag(def.id)
                        }
                    }

                    // An orb has no body to swap, no face to choose and
                    // nothing to wear but Christmas.
                    if !isAto {
                        sectionLabel("Body")

                        bodyRow

                        Divider()

                        sectionLabel("Face")

                        grid

                        Divider()

                        sectionLabel("Wearing and eyes")

                        Picker("Wearing", selection: Binding(
                            get: { current.accessory },
                            set: { write(MochiCharacter(accessory: $0, eye: current.eye, shape: current.shape,
                                                        festive: current.festive)) }
                        )) {
                            Text("Nothing").tag(MochiAccessory?.none)
                            ForEach(MochiAccessory.allCases, id: \.self) { item in
                                Text(loc: item.label).tag(MochiAccessory?.some(item))
                            }
                        }

                        Picker("Eyes", selection: Binding(
                            get: { current.eye },
                            set: { write(MochiCharacter(accessory: current.accessory, eye: $0, shape: current.shape,
                                                        festive: current.festive)) }
                        )) {
                            Text("As they come").tag(MochiEye?.none)
                            ForEach(MochiEye.allCases, id: \.self) { item in
                                Text(loc: item.label).tag(MochiEye?.some(item))
                            }
                        }
                    }

                    if showsChristmas {
                        if !isAto { Divider() }

                        christmas
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
                            // The list of names is run-time, so it goes in as a
                            // value rather than being glued onto the key.
                            Text(L("Keeping a face of their own, so the default above does not reach them: \(overriding.map(\.name).joined(separator: ", "))."))
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
                CharacterTile(character: MochiCharacter(accessory: current.accessory,
                                                        eye: current.eye, shape: shape),
                              colorHex: currentColor,
                              name: shape?.label ?? "Classic",
                              chosen: current.shape == shape,
                              size: 42) {
                    write(MochiCharacter(accessory: current.accessory, eye: current.eye, shape: shape,
                                         festive: current.festive))
                }
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(CharacterCatalog.presets, id: \.id) { preset in
                // The face only. The body is the row above, so a Frog wearing
                // Royal is still Royal and the grid still says so.
                CharacterTile(character: MochiCharacter(accessory: preset.character.accessory,
                                                        eye: preset.character.eye,
                                                        shape: current.shape),
                              colorHex: currentColor,
                              name: preset.name,
                              chosen: preset.character.accessory == current.accessory
                                   && preset.character.eye == current.eye) {
                    write(MochiCharacter(accessory: preset.character.accessory,
                                         eye: preset.character.eye,
                                         shape: current.shape,
                                         festive: current.festive))
                }
            }
        }
    }

    // MARK: - Christmas

    /// Everything a character can put on for Christmas, on top of whatever it
    /// already is.
    ///
    /// Its own block rather than more entries in the two pickers above: those
    /// say who a pill is all year, and this comes off in January. Five rows —
    /// twelve outfits ready to wear, then the four parts they are made of, each
    /// with a way back to nothing.
    private var christmas: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sectionLabel("Christmas")

                if christmasOpen {
                    Text("Until January 6")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(Color(hex: "#CFE3F7"))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: "#16222E")))
                        .overlay(Capsule().stroke(Color(hex: "#3B9EFF").opacity(0.55), lineWidth: 1))
                }
            }

            festiveRow("Ready-made") {
                ForEach(MochiFestiveArt.catalog.presets, id: \.id) { preset in
                    festiveTile(preset.name, wearing: preset.festive,
                                chosen: currentFestive == preset.festive)
                }
            }

            partRow("Head", MochiFestiveArt.catalog.heads, \.head)
            partRow("Eyes", MochiFestiveArt.catalog.eyes, \.eyes)
            partRow("Texture", MochiFestiveArt.catalog.textures, \.texture)
            partRow("Extra", MochiFestiveArt.catalog.extras, \.extra)
        }
    }

    private func festiveRow<Tiles: View>(_ title: String,
                                         @ViewBuilder tiles: () -> Tiles) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(loc: title)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary.opacity(0.8))

            LazyVGrid(columns: columns, spacing: 6) { tiles() }
        }
    }

    /// One of the four parts: nothing, then what the catalogue offers, in the
    /// catalogue's order. Each tile changes that part and leaves the other
    /// three as they are.
    private func partRow(_ title: String, _ options: [[String]],
                         _ part: WritableKeyPath<MochiFestive, String?>) -> some View {
        festiveRow(title) {
            festiveTile("None", wearing: with(part, nil),
                        chosen: (currentFestive[keyPath: part] ?? "").isEmpty)

            ForEach(options.filter { $0.count == 2 }, id: \.first) { option in
                festiveTile(option[1], wearing: with(part, option[0]),
                            chosen: currentFestive[keyPath: part] == option[0])
            }
        }
    }

    private func with(_ part: WritableKeyPath<MochiFestive, String?>, _ id: String?) -> MochiFestive {
        var festive = currentFestive
        festive[keyPath: part] = id
        return festive
    }

    /// A tile in the style of the two grids above it, showing whoever is on the
    /// bench wearing `festive`.
    private func festiveTile(_ name: String, wearing festive: MochiFestive, chosen: Bool) -> some View {
        Button(action: { write(festive: festive) }) {
            VStack(spacing: 1) {
                if isAto {
                    AtoCharacterPreviewView(festive: festive.orNil, size: 46)
                } else {
                    CharacterPreviewView(
                        character: MochiCharacter(accessory: current.accessory, eye: current.eye,
                                                  shape: current.shape, festive: festive.orNil),
                        colorHex: currentColor,
                        size: 46)
                }
                // These names run longer than the faces' — "Peppermint eyes",
                // and longer still in Portuguese — so they may shrink a little
                // before they are cut.
                Text(loc: name)
                    .font(.system(size: 9.5))
                    .foregroundColor(chosen ? Color(hex: "#CFE3F7") : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 2)
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
