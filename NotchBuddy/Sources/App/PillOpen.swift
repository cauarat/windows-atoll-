import Foundation

/// The two decisions behind clicking a pill, kept apart from the clicking.
///
/// A single click opens the island and nothing else; a second click on the
/// same pill also opens the service behind it. Neither decision needs AppKit,
/// a window or a pointer, which is the point: the island cannot be driven
/// from a script on this machine, so anything left inside the click handler
/// can only be checked by hand.
enum PillOpen {

    // MARK: - Was that a second click?

    /// How long a second click still counts as part of the first.
    ///
    /// Comfortably over the system's own double-click interval at its fastest
    /// setting, and short enough that two deliberate visits a second apart are
    /// two single clicks.
    static let doubleClickWindow: TimeInterval = 0.45

    /// Whether this click should also open the service.
    ///
    /// The first click is never held back waiting to find out — it opens the
    /// island at once and this answers false. Only the second one, on the same
    /// pill and inside the window, answers true. Asking the other way round
    /// (wait, then decide) would put the window's delay in front of every
    /// single click, which is the common one.
    ///
    /// - Parameters:
    ///   - pill: the pill being clicked now.
    ///   - lastPill: the pill clicked before this one, if any.
    ///   - lastClick: when that was.
    ///   - now: the time of this click.
    static func opensTarget(pill: String,
                            lastPill: String?,
                            lastClick: Date?,
                            now: Date) -> Bool {
        guard let lastPill, let lastClick else { return false }
        // A different pill is a fresh first click, however fast it followed.
        guard lastPill == pill else { return false }
        let gap = now.timeIntervalSince(lastClick)
        // A clock that went backwards is not a double click.
        return gap >= 0 && gap <= doubleClickWindow
    }

    // MARK: - And what does "the service" mean?

    /// What a second click should do for a message service.
    enum Target: Equatable {
        /// Hand this URL to the browser.
        case website(URL)
        /// Bring this application up, launching it if it is not running.
        case application(bundleID: String)
        /// Nothing is configured, so there is nothing to open.
        case nothing
    }

    /// The stored setting's value for "open the website rather than an app".
    /// Anything else in that setting is read as a bundle identifier.
    static let websiteSetting = "website"

    /// Resolve a service's second-click target.
    ///
    /// - Parameters:
    ///   - setting: `websiteSetting`, a bundle identifier, or empty for the
    ///     default.
    ///   - installedBundleID: the same identifier, but only when it actually
    ///     resolves to an application on this Mac; nil when it does not.
    ///   - serverURL: the service's configured address, already normalized.
    ///
    /// An app that was chosen and has since been uninstalled falls back to the
    /// website rather than doing nothing: a click that silently does nothing
    /// is indistinguishable from a broken one.
    static func target(setting: String,
                       installedBundleID: String?,
                       serverURL: URL?) -> Target {
        let wantsApp = !setting.isEmpty && setting != websiteSetting
        if wantsApp, let installedBundleID { return .application(bundleID: installedBundleID) }
        if let serverURL { return .website(serverURL) }
        // Asked for an app that is gone, with no address to fall back to.
        if wantsApp { return .nothing }
        return .nothing
    }
}
