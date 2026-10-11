// Sparkle is for the GitHub build only: the App Store updates its own apps
// and rejects a bundle that carries a second update mechanism. This fork has
// no App Store build, so the flag is never set — the guard is here so that
// stays true by construction rather than by memory. An App Store build would
// also have to drop the package from project.yml, not just this code.
#if !APPSTORE

import Foundation
import Sparkle

/// Staying up to date, on the GitHub build.
///
/// Sparkle does the work: it reads the appcast named by `SUFeedURL`, checks
/// every six hours, and when it finds something newer it puts up its own window
/// with the release notes and an Install button. Nothing downloads or restarts
/// without that click — Coucou answers Claude Code permission requests over a
/// Unix socket, and a restart nobody asked for drops whichever one is waiting
/// in it, leaving a session hanging on a card that no longer exists.
///
/// What it verifies, before anything is unpacked: the EdDSA signature against
/// `SUPublicEDKey` in Info.plist, and that the new bundle's Developer ID
/// signature matches the running one. An altered download fails both, so the
/// worst a hijacked release page can do is serve a file that gets thrown away.
///
/// The request itself carries nothing: no identifier, no install count, no
/// usage. Sparkle can send an anonymous system profile and that is deliberately
/// left off — see `SUEnableSystemProfiling`, which is absent, meaning false.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    /// Mirrors Sparkle's own stored preference rather than keeping a second
    /// copy in AppState: two switches for one behaviour is how they end up
    /// disagreeing after an update changes one of them.
    @Published var automatic: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automatic }
    }

    private init() {
        // startingUpdater: true begins the six-hourly schedule described in
        // Info.plist. It only ever checks; installing stays behind a click.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automatic = controller.updater.automaticallyChecksForUpdates
    }

    /// Greyed while a check is already running, which is the only time Sparkle
    /// turns one down.
    var canCheck: Bool { controller.updater.canCheckForUpdates }

    /// The version this copy is, for the row that says so.
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Opens Sparkle's own window, which answers either way: it says you are up
    /// to date as readily as it offers a new version, and a click deserves an
    /// answer whichever it is.
    func check() {
        controller.updater.checkForUpdates()
    }
}

#endif
