import Foundation

/// The engine asks for sounds (a poke, a greeting); a Live Activity is silent.
@MainActor
final class SoundEngine {
    static let shared = SoundEngine()
    func play(_ name: String) {}
}
