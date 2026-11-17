import SwiftUI

/// Puts the Christmas parts on screen.
///
/// Everything a Mochi can wear in December is drawn once, per body, by
/// `scripts/generate-mochi-festive.mjs` — the header of that file is the
/// format — and arrives here as `MochiFestiveData.json`. Nothing in this file
/// knows what a Santa hat looks like. It decodes the document, turns path
/// strings into `Path`s, resolves the handful of colours that depend on who is
/// wearing the part, and fills and strokes. `BotEngine` and `AtoBotRenderer`
/// decide where and in which order.
///
/// The model (`MochiFestive`, in MochiCharacter.swift) is four ids and knows
/// nothing of this file, so the character tests go on compiling without it.
@MainActor
enum MochiFestiveArt {

    // MARK: - The document

    struct Document: Decodable, Sendable {
        let catalog: Catalog
        let bodies: [String: Body]
    }

    struct Catalog: Decodable, Sendable {
        /// `[id, English name]`, in picker order. The name is the i18n key.
        let heads, eyes, textures, extras: [[String]]
        let presets: [Preset]
    }

    struct Preset: Decodable, Sendable {
        let id, name: String
        let head, eyes, texture, extra: String?

        var festive: MochiFestive { MochiFestive(head: head, eyes: eyes, texture: texture, extra: extra) }
    }

    struct Body: Decodable, Sendable {
        let eye: Eye
        let clip: String
        let heads: [String: Head]
        let eyes: [String: Eyes]
        let textures: [String: [RawPrim]]
        let extras: [String: Extra]
    }

    /// Where an eye sits at rest, at R = 100, and how big the body's eyes are.
    struct Eye: Decodable, Sendable { let x, y, s: Double }
    struct Head: Decodable, Sendable { let b, f: [RawPrim] }
    struct Eyes: Decodable, Sendable { let l, r, over: [RawPrim] }
    struct Extra: Decodable, Sendable { let a, z: [RawPrim] }

    struct RawPrim: Decodable, Sendable {
        let d: String
        let f, s: String?
        let w, o: Double?
        let c: Int?
        let k: String?
    }

    /// Decoded the first time anything asks, and never again.
    ///
    /// A document that does not decode is an empty one: nobody wears anything
    /// and the picker has nothing to offer. The generator's own test is what
    /// keeps that from happening; here it must only never be a crash.
    static let document: Document = {
        (try? JSONDecoder().decode(Document.self, from: Data(MochiFestiveData.json.utf8)))
            ?? Document(catalog: Catalog(heads: [], eyes: [], textures: [], extras: [], presets: []),
                        bodies: [:])
    }()

    static var catalog: Catalog { document.catalog }

    // MARK: - Parts, ready to draw

    /// A colour that is only known once somebody is wearing the part.
    enum Paint: Equatable {
        case fixed(Color)
        /// The wearer's own colour times this.
        case skin(CGFloat)
        case ink, glint, flake, flakeEdge
    }

    /// What a lit prim's opacity follows. See `level(_:at:)`.
    enum Light: String { case bulbA, bulbB, glowA, glowB, lit, shineA, shineB }

    struct Prim {
        let path: Path
        let fill: Paint?
        let stroke: Paint?
        let width: CGFloat
        let opacity: Double
        /// Drawn inside the body's outline only.
        let clipped: Bool
        let light: Light?
    }

    /// Everything one character has on, for one body.
    ///
    /// Any list may be empty, and an id the data does not have — from a later
    /// build's settings file, say — is an empty list rather than an error.
    struct Outfit {
        var headBehind: [Prim] = []
        var headFront: [Prim] = []
        var eyeLeft: [Prim] = []
        var eyeRight: [Prim] = []
        var eyeOver: [Prim] = []
        var texture: [Prim] = []
        var extraFace: [Prim] = []
        var extraTop: [Prim] = []

        /// Whether these eyes replace the wearer's own.
        var hasEyes = false
        /// Glasses: `eyeOver` stays on through every expression, as a visor does.
        var eyesAreWorn = false
        /// Whether there is something on the head, which then stands in for
        /// the character's accessory.
        var hasHead = false
        /// Where the right eye rests, at R = 100. The left is its mirror.
        var eyeRest = CGPoint.zero
        var textureID: String?
    }

    private struct PartKey: Hashable {
        let body: String
        let slot: UInt8
        let id: String
    }

    private static var parts: [PartKey: [Prim]] = [:]
    private static var clips: [String: Path] = [:]

    /// What `festive` comes to on `body`: `"classic"`, a `MochiShape` raw value,
    /// or `"ato"`. Nil when there is nothing to draw, which is the fast path
    /// every undecorated Mochi takes.
    static func outfit(_ festive: MochiFestive?, body: String) -> Outfit? {
        guard let festive, !festive.isEmpty, let table = document.bodies[body] else { return nil }
        var o = Outfit()
        if let id = festive.head, let head = table.heads[id] {
            o.hasHead = true
            o.headBehind = prims(body, 0, id, head.b)
            o.headFront = prims(body, 1, id, head.f)
        }
        if let id = festive.eyes, let eyes = table.eyes[id] {
            o.hasEyes = true
            o.eyesAreWorn = id == "treeGlasses" || id == "wreathGlasses"
            o.eyeLeft = prims(body, 2, id, eyes.l)
            o.eyeRight = prims(body, 3, id, eyes.r)
            o.eyeOver = prims(body, 4, id, eyes.over)
        }
        if let id = festive.texture, let texture = table.textures[id] {
            o.textureID = id
            o.texture = prims(body, 5, id, texture)
        }
        if let id = festive.extra, let extra = table.extras[id] {
            o.extraFace = prims(body, 6, id, extra.a)
            o.extraTop = prims(body, 7, id, extra.z)
        }
        o.eyeRest = CGPoint(x: table.eye.x, y: table.eye.y)
        return o
    }

    /// The body's outline as the generator saw it, at R = 100 — for a wearer
    /// with no outline of its own to clip to.
    static func clip(body: String) -> Path? {
        if let hit = clips[body] { return hit }
        guard let table = document.bodies[body] else { return nil }
        let path = parse(table.clip)
        clips[body] = path
        return path
    }

    private static func prims(_ body: String, _ slot: UInt8, _ id: String, _ raw: [RawPrim]) -> [Prim] {
        let key = PartKey(body: body, slot: slot, id: id)
        if let hit = parts[key] { return hit }
        let made = raw.map { p in
            Prim(path: parse(p.d), fill: paint(p.f), stroke: paint(p.s),
                 width: CGFloat(p.w ?? 0), opacity: p.o ?? 1,
                 clipped: (p.c ?? 0) != 0, light: p.k.flatMap(Light.init(rawValue:)))
        }
        parts[key] = made
        return made
    }

    private static func paint(_ token: String?) -> Paint? {
        guard let token, !token.isEmpty, token != "none" else { return nil }
        if token.hasPrefix("#") { return .fixed(Color(hex: token)) }
        if token.hasPrefix("@skin:") { return .skin(CGFloat(Double(token.dropFirst(6)) ?? 1)) }
        switch token {
        case "@ink":       return .ink
        case "@glint":     return .glint
        case "@flake":     return .flake
        case "@flakeEdge": return .flakeEdge
        default:           return nil
        }
    }

    // MARK: - Paths

    /// An SVG path of the only kind the generator writes: `M`, `L`, `Q`, `C`
    /// and `Z`, absolute, numbers separated by spaces and commands by nothing —
    /// `M-76 4C-70.4 -68.4 …Z`.
    ///
    /// Over the bytes rather than through `Scanner` or `Double(_:)`: there are
    /// a few hundred kilobytes of these, and every number is a sign, digits and
    /// at most one decimal point. Anything else is skipped, never trusted and
    /// never looped on.
    nonisolated static func parse(_ d: String) -> Path {
        var path = Path()
        var nums: [CGFloat] = []
        nums.reserveCapacity(6)
        let bytes = Array(d.utf8)
        let n = bytes.count
        var i = 0

        func isDigit(_ b: UInt8) -> Bool { b >= 48 && b <= 57 }
        func isLetter(_ b: UInt8) -> Bool { (b >= 65 && b <= 90) || (b >= 97 && b <= 122) }

        while i < n {
            let command = bytes[i]
            i += 1
            guard isLetter(command) else { continue }

            nums.removeAll(keepingCapacity: true)
            while i < n, !isLetter(bytes[i]) {
                let b = bytes[i]
                guard b == 45 || b == 46 || isDigit(b) else { i += 1; continue }
                var negative = false
                if b == 45 { negative = true; i += 1 }
                var mantissa = 0.0, scale = 1.0
                while i < n, isDigit(bytes[i]) {
                    mantissa = mantissa * 10 + Double(bytes[i] - 48)
                    i += 1
                }
                if i < n, bytes[i] == 46 {
                    i += 1
                    while i < n, isDigit(bytes[i]) {
                        mantissa = mantissa * 10 + Double(bytes[i] - 48)
                        scale *= 10
                        i += 1
                    }
                }
                nums.append(CGFloat(negative ? -mantissa / scale : mantissa / scale))
            }

            func point(_ at: Int) -> CGPoint { CGPoint(x: nums[at], y: nums[at + 1]) }
            switch command {
            case 77:   // M — and, as in SVG, any further pairs are lines
                var at = 0
                while at + 1 < nums.count {
                    if at == 0 { path.move(to: point(at)) } else { path.addLine(to: point(at)) }
                    at += 2
                }
            case 76:   // L
                var at = 0
                while at + 1 < nums.count { path.addLine(to: point(at)); at += 2 }
            case 81:   // Q
                var at = 0
                while at + 3 < nums.count {
                    path.addQuadCurve(to: point(at + 2), control: point(at))
                    at += 4
                }
            case 67:   // C
                var at = 0
                while at + 5 < nums.count {
                    path.addCurve(to: point(at + 4), control1: point(at), control2: point(at + 2))
                    at += 6
                }
            case 90:   // Z
                path.closeSubpath()
            default:
                break
            }
        }
        return path
    }

    // MARK: - Colours

    /// The colours a part takes from whoever is wearing it.
    struct Palette {
        /// The wearer's own colour, 0…1 — what `@skin:K` multiplies.
        var skin: (CGFloat, CGFloat, CGFloat)
        var ink: Color
        var glint: Color
        var flake: Color
        /// Nil is "do not draw it": the edge exists only under a white flake on
        /// a frosted pale body, where the flake would otherwise disappear.
        var flakeEdge: Color?

        /// A Mochi's.
        ///
        /// - Parameters:
        ///   - body: the body's colour — the pill's, or the island bot's own.
        ///   - ink: the engine's eye ink.
        ///   - texture: the texture it has on, which changes what its skin is
        ///     (a gingerbread Mochi's ears are gingerbread) and whether a blue
        ///     snowflake would still show.
        static func mochi(body: (CGFloat, CGFloat, CGFloat), ink: Color, texture: String?) -> Palette {
            let pale = 0.299 * body.0 + 0.587 * body.1 + 0.114 * body.2 >= 0.75
            let frost = texture == "frost", ginger = texture == "gingerbread"
            return Palette(
                skin: ginger ? rgb("#B5743A") : body,
                ink: ink,
                glint: .white,
                flake: pale && !frost && !ginger ? Color(hex: "#3FA9F5") : .white,
                flakeEdge: pale && frost ? Color(hex: "#5FAEE6") : nil)
        }

        /// Ato's: a white face on a blue orb, so the ink is white and the glint
        /// is the orb's blue. `skin` is whatever the orb's front layer is this
        /// frame, which is its blue until Ato goes offline and grey.
        static func ato(skinHex: String) -> Palette {
            Palette(skin: rgb(skinHex), ink: .white, glint: Color(hex: "#1B2FEB"),
                    flake: .white, flakeEdge: nil)
        }

        fileprivate func color(_ paint: Paint) -> Color? {
            switch paint {
            case .fixed(let c): return c
            case .skin(let k):
                return Color(red: Double(skin.0 * k), green: Double(skin.1 * k), blue: Double(skin.2 * k))
            case .ink:       return ink
            case .glint:     return glint
            case .flake:     return flake
            case .flakeEdge: return flakeEdge
            }
        }
    }

    nonisolated static func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return (1, 1, 1) }
        return (CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255)
    }

    // MARK: - Lights

    /// A lit prim's opacity at `t` seconds, on whatever clock the caller draws by.
    ///
    /// The string lights are two sets that take turns over 2.2 s — each state
    /// held, with a short ease between — and the tree star breathes over 1.8.
    nonisolated static func level(_ light: Light, at t: Double) -> Double {
        func smooth(_ x: Double) -> Double {
            let v = min(1, max(0, x))
            return v * v * (3 - 2 * v)
        }
        func turn() -> Double {
            let p = 2.2
            let u = (t.truncatingRemainder(dividingBy: p) + p).truncatingRemainder(dividingBy: p) / p
            if u < 0.42 { return 1 }
            if u < 0.5  { return 1 - smooth((u - 0.42) / 0.08) }
            if u < 0.92 { return 0 }
            return smooth((u - 0.92) / 0.08)
        }
        func breath() -> Double { 0.5 - 0.5 * cos(2 * .pi * t / 1.8) }

        switch light {
        case .bulbA:  return 0.3 + 0.7 * turn()
        case .bulbB:  return 0.3 + 0.7 * (1 - turn())
        case .glowA:  return 0.3 * turn()
        case .glowB:  return 0.3 * (1 - turn())
        case .lit:    return 0.6 + 0.4 * breath()
        case .shineA: return 0.08 + 0.32 * breath()
        case .shineB: return 0.28 + 0.52 * breath()
        }
    }

    // MARK: - Drawing

    /// Fills and strokes `prims`.
    ///
    /// Both contexts are already in the data's units — origin at the body's
    /// centre, y down, the body's radius 100. `clipped` is the same context
    /// with the body's outline as its clip, for the prims that ask for it; the
    /// caller makes it, because only the caller knows what the body looks like
    /// this frame.
    ///
    /// - Parameters:
    ///   - time: seconds, for the lit prims. Nil draws them at the opacity the
    ///     data gives them, which is what a still wants.
    ///   - alpha: multiplied into everything, for a part that is fading.
    static func draw(_ prims: [Prim], plain: GraphicsContext, clipped: GraphicsContext,
                     palette: Palette, time: Double?, alpha: Double = 1) {
        guard alpha > 0.004 else { return }
        for prim in prims {
            var opacity = prim.opacity
            if let light = prim.light, let time { opacity = level(light, at: time) }
            opacity *= alpha
            guard opacity > 0.004 else { continue }
            let ctx = prim.clipped ? clipped : plain
            if let fill = prim.fill, let color = palette.color(fill) {
                ctx.fill(prim.path, with: .color(color.opacity(opacity)))
            }
            if let stroke = prim.stroke, prim.width > 0, let color = palette.color(stroke) {
                ctx.stroke(prim.path, with: .color(color.opacity(opacity)),
                           style: StrokeStyle(lineWidth: prim.width, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
