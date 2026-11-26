import AVFoundation
import SwiftUI
import UIKit

// MARK: - The Mac app's sound engine and AppKit names, for the iPhone app only
//
// Separate from MacShims.swift because the widget extension compiles that one too, and an extension
// may not touch UIApplication.shared.

/// The Mac's sound engine, for the phone: the same 28 sounds, the same pool of three players each, the
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

    private func preload() {
        let names = ["peek","open","close","hover","blip","slap","annoyed","dizzy","greet",
                     "work","finish","error","approval","question","approve","gulp","tick",
                     "send","love","pop","proud","wink","yawn","attach","think","search",
                     "rate","sleep"]
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
