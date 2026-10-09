import Foundation

/// The shape an eye is drawn as at this instant.
///
/// An *expression*, not an identity: the state table, the emote table and the
/// mailbox morph all pick one of these, and they change many times a minute.
/// Which pair of eyes a Mochi *has* is `MochiEye`, in MochiCharacter.swift —
/// the two meet in `MochiCharacter.resolve(_:)`.
///
/// Lives in its own file, away from the engine that draws it, so the resolution
/// rule can be compiled and tested without an app.
enum EyeShape: String {
    case pill, wide, dot, line, flat, happy, closed, spiral, heart, star, tired, wink, cup

    /// True for the two shapes that mean "nothing in particular is happening".
    ///
    /// `pill` is every calm state; `wide` is `approval`, which is calm but
    /// looking at you. These are the only two a character's own eyes replace —
    /// everything else is the bot expressing something and must survive.
    var isNeutral: Bool { self == .pill || self == .wide }
}
