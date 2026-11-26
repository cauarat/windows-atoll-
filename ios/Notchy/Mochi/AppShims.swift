import AVFoundation
import SwiftUI
import UIKit

// MARK: - The Mac app's sound engine and AppKit names, on the iPhone
//
// MacShims.swift has what the Mochi files expect from CoreGraphics and SwiftUI; this file has what
// the shared files expect from the rest of the Mac app, done with UIKit and AVFoundation.

/// The Mac's sound engine, for the phone: the Mac's sounds, the same pool of three players each, the
/// same default volume. Plays only while the app is in front and the user left sounds on; mixes with
/// whatever else is playing and respects the silent switch (the ambient session).
@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "phoneSounds") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "phoneSounds") }
    }
    var volume: Float = 0.12 {
        didSet { players.values.forEach { $0.forEach { $0.volume = volume } } }
    }

    private var players: [String: [AVAudioPlayer]] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        preload()
    }

    /// Only the sounds the phone plays: Mochi's (BotEngine) and the chat's (PhoneStore). A name not
    /// listed here plays nothing, so a new `play` call needs its name added.
    private func preload() {
        let names = ["slap", "annoyed", "greet", "send", "pop"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "sounds") else { continue }
            var pool: [AVAudioPlayer] = []
            for _ in 0..<3 {
                if let p = try? AVAudioPlayer(contentsOf: url) {
                    p.volume = volume
                    p.prepareToPlay()
                    pool.append(p)
                }
            }
            if !pool.isEmpty { players[name] = pool }
        }
    }

    func play(_ name: String) {
        guard enabled, UIApplication.shared.applicationState == .active, let pool = players[name] else { return }
        let player = pool.first { !$0.isPlaying } ?? pool[0]
        player.currentTime = 0
        player.volume = volume
        player.play()
    }
}

// MARK: - ChatMarkdownView (shared) opens links and copies code

/// `NSWorkspace.shared.open(_:)`, as UIApplication does it.
final class NSWorkspace: Sendable {
    static let shared = NSWorkspace()
    @MainActor func open(_ url: URL) { UIApplication.shared.open(url) }
}

/// `NSPasteboard.general` for the one thing the shared views do with it: copy a string.
final class NSPasteboard: Sendable {
    struct PasteboardType: Sendable { static let string = PasteboardType() }
    static let general = NSPasteboard()
    @MainActor func clearContents() {}
    @MainActor func setString(_ string: String, forType: PasteboardType) { UIPasteboard.general.string = string }
}
