import CoreGraphics
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

    /// A click on a pill's button, remembered until the island it opened
    /// goes away.
    struct Click: Equatable, Sendable {
        /// Which pill's button it landed on.
        var pill: String
        /// Where the pointer was, in screen coordinates.
        var pointer: CGPoint

        init(pill: String, pointer: CGPoint) {
            self.pill = pill
            self.pointer = pointer
        }
    }

    /// How far the pointer may drift between the two clicks and still be the
    /// same pair — for the second click that misses the button because the
    /// button moved. The slop a hand resting on a trackpad has, and no more.
    static let pointerSlop: CGFloat = 6

    /// Whether this click should also open the service behind `pill`.
    ///
    /// What makes it the second click is the island, not a stopwatch: the
    /// first click's memory is kept while the island it opened is on screen
    /// and dropped when that closes, so "the pill I am already looking at,
    /// clicked again" is the whole rule.
    ///
    /// It used to be a click within 0.45 s, which is to say a double click at
    /// the system's own pace, and that is why Mattermost opened only
    /// sometimes. Two unhurried clicks are the ordinary way to click a thing
    /// twice, and this pill invites them: the first click opens the message
    /// list, the island grows, and anyone watching it waits to see what
    /// happened before clicking again. Every one of those pairs opened the
    /// island twice and the app never.
    ///
    /// - Parameters:
    ///   - pill: the pill being clicked now.
    ///   - last: the click still outstanding, if the island is still up.
    static func opensTarget(pill: String, last: Click?) -> Bool {
        guard let last else { return false }
        // A different pill is a fresh first click, however fast it followed.
        return last.pill == pill
    }

    /// Whether a click that landed on the island itself, rather than on the
    /// pill's button, is the second half of that pair.
    ///
    /// Opening a view resizes the island and the ring hangs off its edge, so
    /// the disc slides out from under a pointer that never moved and the
    /// second click lands on the island instead. The island is a large target
    /// and a click anywhere on it is plainly not a second click — one from a
    /// pointer that has not moved since the first one is, which is the same
    /// thing macOS itself asks of a double click.
    static func opensTarget(landingAt pointer: CGPoint, last: Click?) -> Bool {
        guard let last else { return false }
        return abs(pointer.x - last.pointer.x) <= pointerSlop
            && abs(pointer.y - last.pointer.y) <= pointerSlop
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
