import Foundation

/// Who a Mochi is: what sits on its head and what kind of eyes it has.
///
/// Separate from everything the bot *does*. The state machine, the emotes and
/// the mailbox morph go on driving the face exactly as before; this only says
/// what the face looks like when none of them is saying anything. That
/// separation is the whole design — see `resolve(_:)`.
///
/// The colour is deliberately not here. A Mochi's colour comes from the pill it
/// belongs to, so the Mattermost bot keeps Mattermost's colour whichever
/// character it wears and the pill border still matches the creature inside it.
struct MochiCharacter: Equatable, Codable {
    var accessory: MochiAccessory?
    var eye: MochiEye?
    /// What it is shaped like. `nil` is classic Mochi, drawn by the superellipse
    /// it always was.
    ///
    /// Optional, and that is load-bearing rather than tidy. `pillCharacters` is
    /// persisted as an encoded `[String: MochiCharacter]`, and Swift synthesises
    /// `decodeIfPresent` for an Optional but plain `decode` for anything else —
    /// so a non-Optional `shape`, default value or not, would throw
    /// `keyNotFound` on every blob written before this existed, and the `try?`
    /// around the load would swallow it and silently wipe every pill's
    /// character. Optional decodes those blobs as classic, which is also what
    /// they mean.
    var shape: MochiShape?
    /// What it has on for Christmas, over all of the above. `nil` is nothing.
    ///
    /// Optional for the reason `shape` is: every character stored before this
    /// existed has no such key, and has to go on decoding.
    var festive: MochiFestive?

    /// Classic Mochi: no hat, no particular eyes. Draws byte-identically to the
    /// app before characters existed, which is what makes this feature free for
    /// anyone who never opens the picker.
    init(accessory: MochiAccessory? = nil, eye: MochiEye? = nil, shape: MochiShape? = nil,
         festive: MochiFestive? = nil) {
        self.accessory = accessory
        self.eye = eye
        self.shape = shape
        self.festive = festive
    }

    var isClassic: Bool {
        accessory == nil && eye == nil && shape == nil && (festive?.isEmpty ?? true)
    }

    // MARK: – The rule

    /// What this character does with the eye shape the animation asked for.
    ///
    /// Two kinds of eyes, and the difference is not cosmetic:
    ///
    /// - `dot`, `glossy`, `pixel`, `sleepy` **are** the eye, so they only apply
    ///   while nothing is being expressed. The moment the bot is dizzy, asleep,
    ///   delighted or winking, its own eyes take over and the character steps
    ///   aside — but only for as long as that lasts. A permanent override is
    ///   not an expression; see `resting`.
    /// - `visor` and `shades` are **worn over** the eyes, and the same rule
    ///   would be a bug: eyewear does not come off because you got dizzy. They
    ///   are always drawn, and the shape the animation asked for is drawn inside
    ///   the lens as a glint — the spiral still spins, the sleeping arcs still
    ///   close, you just watch it happen through the lens.
    /// `resting` says the shape is how this bot always looks rather than
    /// something it is expressing — an eye override that never expires. Those
    /// are identity too, and the character's own eyes replace them exactly as
    /// they replace a neutral shape. Without it a pill with a permanent eye
    /// would ignore its character for good.
    func resolve(_ shape: EyeShape, resting: Bool = false) -> EyeResolution {
        guard let eye else { return .plain(shape) }
        if eye.isSpanning { return .behindLens(shape, eye) }
        return (resting || shape.isNeutral) ? .character(eye, wide: shape == .wide)
                                            : .plain(shape)
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

// MARK: - Christmas

/// What a Mochi has on for Christmas: one thing on its head, a pair of eyes, a
/// pattern on its body and one extra.
///
/// Strings, not enums. The parts are drawn by `scripts/generate-mochi-festive.mjs`
/// and these are its ids, so a part added there needs nothing added here — and
/// an id this build has never heard of is carried through and simply not drawn,
/// which is what a settings file from a later build should do to an older one.
///
/// Sits on top of a character rather than inside its other three axes: the
/// accessory, the eyes and the body a Mochi had before December are all still
/// there underneath, and come back when this is taken off.
struct MochiFestive: Equatable, Codable, Sendable {
    var head: String?
    var eyes: String?
    var texture: String?
    var extra: String?

    init(head: String? = nil, eyes: String? = nil, texture: String? = nil, extra: String? = nil) {
        self.head = head
        self.eyes = eyes
        self.texture = texture
        self.extra = extra
    }

    /// Wearing nothing. An empty id counts as none, so a hand-edited file
    /// cannot produce a Mochi that is festive and bare at once.
    var isEmpty: Bool {
        [head, eyes, texture, extra].allSatisfy { $0?.isEmpty ?? true }
    }

    /// This, or nil when it is nothing — the form a character stores, so that
    /// "took everything off" and "never wore any" compare equal.
    var orNil: MochiFestive? { isEmpty ? nil : self }

    /// `"head.eyes.texture.extra"`, with `-` for absent.
    var storageString: String {
        [head, eyes, texture, extra].map { ($0?.isEmpty ?? true) ? "-" : $0! }.joined(separator: ".")
    }

    /// Tolerant, like the character's own: short, long or empty all parse.
    init(storage: String) {
        let parts = storage.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        func part(_ i: Int) -> String? {
            guard i < parts.count, !parts[i].isEmpty, parts[i] != "-" else { return nil }
            return parts[i]
        }
        self.init(head: part(0), eyes: part(1), texture: part(2), extra: part(3))
    }

    /// Whether the picker offers Christmas today: 15 November to 6 January,
    /// both included, by the user's own calendar. It opens in the middle of
    /// November, when the lights go up, rather than on the first of December.
    ///
    /// Only the picker asks. A Mochi already wearing something goes on wearing
    /// it in July — taking a hat off somebody's character because the date
    /// changed would be the app editing their settings.
    static func isInSeason(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.month, .day], from: date)
        guard let month = c.month, let day = c.day else { return false }
        return month == 12 || (month == 11 && day >= 15) || (month == 1 && day <= 6)
    }
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
    ///
    /// Compares the face only. The presets name an accessory and a pair of eyes;
    /// the body is a separate axis with its own row of tiles, so a Frog wearing
    /// Royal is still Royal. Comparing whole characters here would leave the
    /// grid showing nothing selected the moment anyone picked a shape.
    static func preset(matching character: MochiCharacter) -> CharacterPreset? {
        presets.first { $0.character.accessory == character.accessory
                     && $0.character.eye == character.eye }
    }
}

// MARK: - Storage

extension MochiCharacter {
    /// `"accessory:eye:shape"`, with `-` for absent. The form the Windows
    /// settings file stores, so Rust can relay a character it knows nothing
    /// about.
    ///
    /// The third field is an append, not a new format: a two-field string from
    /// an older settings file still parses, and an older build reading a
    /// three-field one ignores the tail and draws a classic body.
    ///
    /// Christmas is a fourth field, appended the same way and only when there
    /// is something in it — `catEars:dot:pointy:santaHat.jolly.-.beard` — so a
    /// character that wears none stores exactly the string it always did.
    var storageString: String {
        let base = "\(accessory?.rawValue ?? "-"):\(eye?.rawValue ?? "-"):\(shape?.rawValue ?? "-")"
        guard let festive, !festive.isEmpty else { return base }
        return base + ":" + festive.storageString
    }

    /// Tolerant on purpose. A settings file written by a later build — or by
    /// hand — must leave Mochi looking like Mochi, never throw and never take
    /// the island down with it.
    init(storage: String) {
        let parts = storage.split(separator: ":", omittingEmptySubsequences: false)
        self.init(accessory: parts.count > 0 ? MochiAccessory(rawValue: String(parts[0])) : nil,
                  eye:       parts.count > 1 ? MochiEye(rawValue: String(parts[1]))       : nil,
                  shape:     parts.count > 2 ? MochiShape(rawValue: String(parts[2]))     : nil,
                  festive:   parts.count > 3 ? MochiFestive(storage: String(parts[3])).orNil : nil)
    }
}
