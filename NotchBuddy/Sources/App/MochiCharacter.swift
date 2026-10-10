import Foundation

/// Who a Mochi is: what sits on its head and what kind of eyes it has.
///
/// Separate from everything the bot *does*. The state machine, the emotes and
/// the mailbox morph go on driving the face exactly as before; this only says
/// what the face looks like when none of them is saying anything. That
/// separation is the whole design — see `resolve(_:)`.
///
/// The colour is deliberately not here. A Mochi's colour comes from the pill it
/// belongs to, so the ClickMassa bot stays cyan whichever character it wears and
/// the pill border still matches the creature inside it.
struct MochiCharacter: Equatable, Codable {
    var accessory: MochiAccessory?
    var eye: MochiEye?

    /// Classic Mochi: no hat, no particular eyes. Draws byte-identically to the
    /// app before characters existed, which is what makes this feature free for
    /// anyone who never opens the picker.
    init(accessory: MochiAccessory? = nil, eye: MochiEye? = nil) {
        self.accessory = accessory
        self.eye = eye
    }

    var isClassic: Bool { accessory == nil && eye == nil }

    // MARK: – The rule

    /// What this character does with the eye shape the animation asked for.
    ///
    /// Two kinds of eyes, and the difference is not cosmetic:
    ///
    /// - `dot`, `glossy`, `pixel`, `sleepy` **are** the eye, so they only apply
    ///   while nothing is being expressed. The moment the bot is dizzy, asleep,
    ///   delighted or winking, its own eyes take over and the character steps
    ///   aside.
    /// - `visor` and `shades` are **worn over** the eyes, and the same rule
    ///   would be a bug: eyewear does not come off because you got dizzy. They
    ///   are always drawn, and the shape the animation asked for is drawn inside
    ///   the lens as a glint — the spiral still spins, the sleeping arcs still
    ///   close, you just watch it happen through the lens.
    func resolve(_ shape: EyeShape) -> EyeResolution {
        guard let eye else { return .plain(shape) }
        if eye.isSpanning { return .behindLens(shape, eye) }
        return shape.isNeutral ? .character(eye, wide: shape == .wide) : .plain(shape)
    }
}

/// The outcome of `MochiCharacter.resolve(_:)` — what the engine should draw.
enum EyeResolution: Equatable {
    /// Draw the shape as the engine always has.
    case plain(EyeShape)
    /// Draw the character's own eyes. `wide` carries `approval`'s enlargement,
    /// which is that state's only eye cue and must not be lost.
    case character(MochiEye, wide: Bool)
    /// Draw the lens, with `shape` inside it as a glint.
    case behindLens(EyeShape, MochiEye)
}

// MARK: - Accessories

/// What a Mochi wears. Nil is bare-headed.
enum MochiAccessory: String, CaseIterable, Codable {
    case catEars, horns, antenna, sprout, sparkles, bow, crown, beret

    var label: String {
        switch self {
        case .catEars:  return "Cat ears"
        case .horns:    return "Horns"
        case .antenna:  return "Antenna"
        case .sprout:   return "Sprout"
        case .sparkles: return "Sparkles"
        case .bow:      return "Bow"
        case .crown:    return "Crown"
        case .beret:    return "Beret"
        }
    }

    /// Drawn before the body, so the silhouette swallows the base and the thing
    /// looks like it grew there rather than being stuck on.
    var isBehind: Bool {
        switch self {
        case .catEars, .horns, .antenna, .sprout: return true
        case .sparkles, .bow, .crown, .beret:     return false
        }
    }
}

// MARK: - Eyes

/// The kind of eyes a Mochi has.
enum MochiEye: String, CaseIterable, Codable {
    case dot, glossy, pixel, sleepy
    case visor, shades

    var label: String {
        switch self {
        case .dot:    return "Dots"
        case .glossy: return "Big and glossy"
        case .pixel:  return "Pixels"
        case .sleepy: return "Sleepy"
        case .visor:  return "Visor"
        case .shades: return "Sunglasses"
        }
    }

    /// True for the eyes that are worn rather than grown: one piece across both
    /// sockets, always on, never replaced by an expression.
    var isSpanning: Bool { self == .visor || self == .shades }

    /// What the expression is drawn in when it happens behind a lens. The
    /// ordinary ink would be invisible against the dark glass.
    var glintHex: String {
        switch self {
        case .visor:  return "#DFF4FF"
        case .shades: return "#FFD9A0"
        default:      return "#FFFFFF"
        }
    }
}

// MARK: - Presets

/// A named (accessory, eyes) pair — one tile of the picker grid.
///
/// Nothing but a shortcut. Settings resolves a preset to a `MochiCharacter` and
/// stores that, never the preset id, so picking a tile and then changing one of
/// the two pickers needs no second code path and no "custom" sentinel.
struct CharacterPreset: Equatable {
    let id: String
    let name: String
    let character: MochiCharacter
}

enum CharacterCatalog {
    /// The eighteen, in grid order.
    static let presets: [CharacterPreset] = [
        .init(id: "plain",    name: "Plain",    character: .init(accessory: nil,       eye: .dot)),
        .init(id: "kitty",    name: "Kitty",    character: .init(accessory: .catEars,  eye: .dot)),
        .init(id: "horned",   name: "Horned",   character: .init(accessory: .horns,    eye: .glossy)),
        .init(id: "beacon",   name: "Beacon",   character: .init(accessory: .antenna,  eye: .pixel)),
        .init(id: "sprout",   name: "Sprout",   character: .init(accessory: .sprout,   eye: .visor)),
        .init(id: "sparkle",  name: "Sparkle",  character: .init(accessory: .sparkles, eye: .glossy)),

        .init(id: "bow",      name: "Bow",      character: .init(accessory: .bow,      eye: .dot)),
        .init(id: "royal",    name: "Royal",    character: .init(accessory: .crown,    eye: .glossy)),
        .init(id: "beret",    name: "Beret",    character: .init(accessory: .beret,    eye: .pixel)),
        .init(id: "ghost",    name: "Ghost",    character: .init(accessory: nil,       eye: .visor)),
        .init(id: "coolcat",  name: "Cool Cat", character: .init(accessory: .catEars,  eye: .shades)),
        .init(id: "imp",      name: "Imp",      character: .init(accessory: .horns,    eye: .dot)),

        .init(id: "blip",     name: "Blip",     character: .init(accessory: .antenna,  eye: .glossy)),
        .init(id: "seedling", name: "Seedling", character: .init(accessory: .sprout,   eye: .pixel)),
        .init(id: "stardust", name: "Stardust", character: .init(accessory: .sparkles, eye: .visor)),
        .init(id: "dapper",   name: "Dapper",   character: .init(accessory: .bow,      eye: .shades)),
        .init(id: "majesty",  name: "Majesty",  character: .init(accessory: .crown,    eye: .dot)),
        .init(id: "grumpy",   name: "Grumpy",   character: .init(accessory: .beret,    eye: .sleepy)),
    ]

    /// The preset this character came from, if any — for marking the grid.
    static func preset(matching character: MochiCharacter) -> CharacterPreset? {
        presets.first { $0.character == character }
    }
}

// MARK: - Storage

extension MochiCharacter {
    /// `"accessory:eye"`, with `-` for absent. The form the Windows settings
    /// file stores, so Rust can relay a character it knows nothing about.
    var storageString: String {
        "\(accessory?.rawValue ?? "-"):\(eye?.rawValue ?? "-")"
    }

    /// Tolerant on purpose. A settings file written by a later build — or by
    /// hand — must leave Mochi looking like Mochi, never throw and never take
    /// the island down with it.
    init(storage: String) {
        let parts = storage.split(separator: ":", omittingEmptySubsequences: false)
        self.init(accessory: parts.count > 0 ? MochiAccessory(rawValue: String(parts[0])) : nil,
                  eye:       parts.count > 1 ? MochiEye(rawValue: String(parts[1]))       : nil)
    }
}
