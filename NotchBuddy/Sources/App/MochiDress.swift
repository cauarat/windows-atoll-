import SwiftUI

/// Dresses a Mochi that `BotEngine` is not drawing.
///
/// The island bot goes through the engine and wears its character for free.
/// The greeting (`GreetingCanvasView`) and the upload sequence
/// (`UploadCanvasView`) do not: each has its own hand-tuned Mochi, with its
/// own superellipse, its own eye spacing and its own choreography, and neither
/// knew `MochiCharacter` existed. Before this they drew classic Mochi whatever
/// the user had picked, which reads as a setting that refused to save.
///
/// Rather than port accessories and eyes into two more renderers — three
/// copies that would drift apart the first time one was touched — this poses a
/// throwaway engine over the caller's Mochi and asks it for the parts. The
/// caller keeps its body, its timing and its pixels; it only borrows what the
/// character adds.
///
/// Classic Mochi is the empty case all the way down: `isDressed` is false,
/// every call returns without drawing, and the caller's frames come out exactly
/// as they did before any of this existed.
@MainActor
struct MochiDress {
    let character: MochiCharacter

    /// Nil for classic Mochi, which is the case that matters: these renderers
    /// build a dress every frame, and a classic one must not cost an
    /// allocation for a creature that is going to look the same either way.
    private let engine: BotEngine?

    /// - Parameters:
    ///   - character: who this Mochi is.
    ///   - bodyColor: the pill's colour, for the parts of an accessory that are
    ///     made of Mochi rather than of hat.
    ///   - isMini: borrowed by the engine for its ink and its level of detail.
    ///   - morph: how far along the mailbox morph the caller is, 0 for a Mochi
    ///     that is staying one. The engine fades an accessory out over this and
    ///     lerps the body towards the box, so the upload sequence gets the same
    ///     rule the island bot has always had: a mailbox wears nothing.
    init(character: MochiCharacter, bodyColor: CGColor? = nil,
         isMini: Bool = false, morph: CGFloat = 0) {
        self.character = character
        guard !character.isClassic else { self.engine = nil; return }
        let e = BotEngine()
        e.character = character
        e.bodyColor = bodyColor
        e.isMini = isMini
        // Flat and still. These renderers drive their own pose, and a hat that
        // tried to follow the engine's idle sway would drift off a head that
        // was never swaying.
        e.yaw = 0; e.pitch = 0; e.roll = 0; e.tilt = 0
        e.morph = morph
        self.engine = e
    }

    /// False for classic Mochi, when every call here is a no-op.
    var isDressed: Bool { engine != nil }

    /// Whether the character brings eyes, and so whether the caller should skip
    /// drawing its own pair.
    var hasOwnEyes: Bool { engine?.hasOwnEyes ?? false }

    /// The silhouette this character calls for, centred on the origin and
    /// scaled so it spans `rx` by `ry`. Nil for classic, and for anything the
    /// caller should keep drawing itself.
    ///
    /// The engine's shaped outline is a table in units of R, so it comes out
    /// round; the callers' bodies are wider than they are tall. Scaling to
    /// their aspect is what keeps a Heart or a Frog recognisably the one from
    /// the picker instead of a squashed stranger.
    func bodyPath(rx: CGFloat, ry: CGFloat) -> Path? {
        guard let path = engine?.characterBodyPath(R: ry) else { return nil }
        return path.applying(CGAffineTransform(scaleX: rx / ry, y: 1))
    }

    /// Ears, horns, antenna, sprout — before the body, so it swallows their
    /// base and they look grown rather than stuck on.
    func drawBehind(into ctx: inout GraphicsContext, at centre: CGPoint,
                    rx: CGFloat, ry: CGFloat) {
        guard let engine else { return }
        var c = ctx
        c.translateBy(x: centre.x, y: centre.y)
        engine.drawAccessoryBehind(ctx: c, R: ry, rx: rx, ry: ry)
    }

    /// Crown, bow, beret, sparkles — after the body, which they have to
    /// overhang to read as worn. `bodyPath` is in the caller's canvas
    /// coordinates, as the beret needs it to sit on the real silhouette.
    func drawFront(into ctx: inout GraphicsContext, at centre: CGPoint,
                   bodyPath: Path, rx: CGFloat, ry: CGFloat) {
        guard let engine else { return }
        var c = ctx
        c.translateBy(x: centre.x, y: centre.y)
        engine.drawAccessoryFront(ctx: c, bodyPath: bodyPath, R: ry, rx: rx, ry: ry)
    }

    /// The character's eyes, at the caller's own eye positions.
    ///
    /// `half` is the gap from the centre of the face to the centre of one eye,
    /// and `offset` is where the pair is looking — both the caller's numbers,
    /// so the eyes land where that renderer has always put them.
    ///
    /// Returns false when the character has no eyes of its own, which is the
    /// caller's cue to draw its own pair.
    @discardableResult
    func drawEyes(into ctx: inout GraphicsContext, at centre: CGPoint,
                  half: CGFloat, offset: CGPoint,
                  w: CGFloat, h: CGFloat, open: CGFloat,
                  rx: CGFloat, ry: CGFloat,
                  clippedTo body: Path,
                  glint: EyeShape = .pill) -> Bool {
        guard let engine, hasOwnEyes else { return false }
        var c = ctx
        c.clip(to: body)
        c.translateBy(x: centre.x, y: centre.y)
        let slots: [(sd: CGFloat, slot: BotEngine.EyeSlot?)] = [
            (-1, .init(x: -half + offset.x, y: offset.y, fx: 1, fy: 1)),
            ( 1, .init(x:  half + offset.x, y: offset.y, fx: 1, fy: 1)),
        ]
        return engine.drawCharacterEyes(into: &c, slots: slots, w: w, h: h, open: open,
                                        R: ry, rx: rx, glint: glint)
    }
}
