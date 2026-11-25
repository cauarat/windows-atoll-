// Sparkle is for the GitHub build only: the App Store updates its own apps
// and rejects a bundle that carries a second update mechanism. This fork has
// no App Store build, so the flag is never set — the guard is here so that
// stays true by construction rather than by memory. An App Store build would
// also have to drop the package from project.yml, not just this code.
#if !APPSTORE

import AppKit
import Sparkle

extension Notification.Name {
    /// A new version is waiting: the island opens on the update card.
    static let updateOffered = Notification.Name("updateOffered")
}

/// Staying up to date, on the GitHub build.
///
/// Sparkle reads the appcast named by `SUFeedURL` once an hour. When it finds
/// something newer it downloads it in the background and verifies it, and then
/// — instead of Sparkle's own window — the notch says so: a card with the
/// version and an Update now button. One click installs and relaunches.
///
/// It never restarts on its own. Coucou answers Claude Code permission requests
/// over a Unix socket, and a restart nobody asked for drops whichever one is
/// waiting in it, leaving a session hanging on a card that no longer exists.
/// Later is a real answer: Sparkle installs what it downloaded the next time
/// Notchy quits, so the update still lands, just not under anyone's work.
///
/// What it verifies, before anything is unpacked: the EdDSA signature against
/// `SUPublicEDKey` in Info.plist, or a Developer ID signature matching the
/// running one. An altered download fails both, so the worst a hijacked release
/// page can do is serve a file that gets thrown away.
///
/// The request itself carries nothing: no identifier, no install count, no
/// usage. Sparkle can send an anonymous system profile and that is deliberately
/// left off — see `SUEnableSystemProfiling`, which is absent, meaning false.
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    /// What the notch card has to say.
    enum Offer: Equatable {
        /// Downloaded and verified: one click installs it and relaunches.
        case ready(version: String)
        /// Found, but Sparkle did not fetch it by itself — automatic downloads
        /// are off, or installing needs an administrator. The click brings
        /// Sparkle's own window forward with this version in it.
        case available(version: String)
        /// The click happened; Notchy is about to quit and come back.
        case restarting(version: String)

        var version: String {
            switch self {
            case .ready(let version), .available(let version), .restarting(let version):
                return version
            }
        }
    }

    /// The version on offer, if there is one. Settings reads it too.
    @Published private(set) var offer: Offer?

    /// Answered with Later. The card stops opening by itself and opening the
    /// island by hand finds Home again; Settings keeps the button.
    @Published private(set) var deferred = false

    /// Mirrors Sparkle's own stored preference rather than keeping a second
    /// copy in AppState: two switches for one behaviour is how they end up
    /// disagreeing after an update changes one of them.
    @Published var automatic: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automatic }
    }

    private var controller: SPUStandardUpdaterController!

    /// Sparkle's "install now and relaunch", handed over once the download is
    /// verified. Nil until then, and for an update Sparkle did not download.
    private var installNow: (() -> Void)?

    private override init() {
        automatic = true
        super.init()
        // Not started until `controller` is set: starting can call back into
        // the delegate, which is this object.
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        automatic = controller.updater.automaticallyChecksForUpdates
        // Background downloads are what make the card a one-click install.
        // Info.plist turns them on, but Sparkle keeps its own copy in the
        // defaults once its window's checkbox has been seen, and every build
        // before this one shipped with it off — so it is switched on once,
        // here. Anyone who unticks it in Sparkle's window afterwards keeps
        // that; the card then opens Sparkle's window instead.
        let migrated = "updater.downloadsInBackground.v1"
        if !UserDefaults.standard.bool(forKey: migrated) {
            controller.updater.automaticallyDownloadsUpdates = true
            UserDefaults.standard.set(true, forKey: migrated)
        }
        controller.startUpdater()
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
        NSApp.activate(ignoringOtherApps: true)
        controller.updater.checkForUpdates()
    }

    /// The card's Update now, and Settings' "Update to …".
    func install() {
        if previewing {
            if let offer { self.offer = .restarting(version: offer.version) }
            return
        }
        switch offer {
        case .ready(let version):
            guard let installNow else { return check() }
            offer = .restarting(version: version)
            // A beat for the card to say "Restarting…", and for the confetti
            // the click set off to fall, before the app goes — so the island
            // emptying reads as the update, not as a crash.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { installNow() }
        case .available:
            // Sparkle already holds this update in a session it has not shown;
            // asking it to check brings that session's window forward.
            check()
        case .restarting:
            break
        case nil:
            check()
        }
    }

    /// The card's Later.
    func later() {
        deferred = true
        NotificationCenter.default.post(name: .islandCollapse, object: nil)
    }

    /// Whether opening the island by hand should land on the card: a version is
    /// waiting and nobody has said Later to it.
    var awaitsAnswer: Bool { offer != nil && !deferred }

    /// A made-up offer for screenshots (`NOTCHY_SEED_UPDATE`), with no
    /// download and no install behind it.
    private var previewing = false

    func preview(_ kind: String) {
        previewing = true
        let version = "9.9.9"
        switch kind {
        case "available": announce(.available(version: version))
        case "restarting":
            announce(.ready(version: version))
            offer = .restarting(version: version)
        case "click":
            // The card, then Update now once the greeting has handed the island
            // over to it — for looking at the confetti.
            announce(.ready(version: version))
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { self.install() }
        default: announce(.ready(version: version))
        }
    }

    private func announce(_ next: Offer) {
        // The same version announced twice — a second scheduled look finding
        // what the first already offered — is not news.
        let news = offer?.version != next.version
        offer = next
        guard news else { return }
        deferred = false
        NotificationCenter.default.post(name: .updateOffered, object: nil)
    }
}

// MARK: - Sparkle's side

extension Updater: SPUUpdaterDelegate {
    /// The download is in and verified. Taking the install over (returning
    /// true) is what keeps Sparkle's window away: it waits for the card's
    /// click, and installs on quit if the click never comes.
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        installNow = immediateInstallHandler
        announce(.ready(version: item.displayVersionString))
        return true
    }
}

// Sparkle calls these on the main thread, but the protocol is not marked as
// such; `@preconcurrency` lets the main-actor methods stand in for it and
// checks the thread when they run.
extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    /// What lets a scheduled update skip Sparkle's window.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// A check the hourly schedule ran, not one somebody clicked: the notch
    /// announces it instead of a window popping up over
    /// whatever the user is doing. Notchy has no Dock icon, so Sparkle's window
    /// would arrive from nowhere.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // Sparkle showing it itself means somebody asked (Check for updates):
        // its window is the answer, and a card on top would be a second one.
        guard !handleShowingUpdate else { return }
        announce(.available(version: update.displayVersionString))
    }

    /// Sparkle's window has the user's attention now; the card's job is done.
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        if case .available = offer { deferred = true }
    }

    /// The session ended without an install — dismissed, skipped, or failed.
    /// A downloaded update is not affected: that one is ours until quit.
    func standardUserDriverWillFinishUpdateSession() {
        if case .available = offer { offer = nil }
    }
}

#endif
