import Foundation

/// Where the app is allowed to run from, and what to do when it is somewhere
/// else — decided from paths alone, with nothing that touches disk.
///
/// A download opened straight from its disk image is the single most common way
/// Notchy ends up broken in a way nobody can see. macOS runs a quarantined
/// bundle from a randomised read-only copy under `/AppTranslocation/`, so:
/// Accessibility is granted to a path that will not exist tomorrow, Sparkle
/// refuses the update outright (`SURunningTranslocated`), and — worst, because
/// it is silent — `HookServer.serverThread()` unlinks `nb.sock` and binds its
/// own, which takes Claude Code off the copy in /Applications and gives it to
/// the one on the image.
///
/// None of that is visible from the island. It looks like a working app that
/// has stopped hearing from the agent.
///
/// Kept pure so it can be tested: the alert, the copy and the relaunch cannot be
/// driven from a script on this machine, so a rule left inside them is a rule
/// only ever checked by dragging a .dmg around by hand. The half that does touch
/// AppKit is `InstallRelocator`.
enum InstallLocation {

    // MARK: - Where it is

    /// The places a bundle can be, as far as this decision cares.
    enum Place: Equatable {
        /// `/Applications/Notchy.app` — where it belongs.
        case applications
        /// `~/Applications/Notchy.app` — equally fine; macOS treats it the same,
        /// and it is where a standard account without write access to
        /// `/Applications` has to put things.
        case userApplications
        /// Inside a folder in either of the above. Updates and the hook both
        /// look at the top level.
        case applicationsSubfolder
        /// macOS is running a throwaway copy because the bundle was opened
        /// while still quarantined.
        case translocated
        case downloads
        case desktop
        /// A mounted disk image, or anything else read-only.
        case readOnlyVolume
        /// A build directory, another volume, another user's home. Someone who
        /// put it there meant to, so it is left alone.
        case elsewhere
    }

    /// Where a move would put it.
    enum Destination: Equatable { case applications, userApplications }

    /// What the app should do about where it finds itself.
    enum Verdict: Equatable {
        /// Carry on launching. The overwhelmingly common answer.
        case stay
        /// Another copy is already running from a proper location. Bring that
        /// one forward and quit, rather than fighting it over the socket.
        case handOverToRunningCopy(bundlePath: String)
        case offerMove(from: Place, to: Destination)
        /// In the right folder under the wrong name. Moving it would not help;
        /// only the person who renamed it can undo that.
        case warnRenamed(actualName: String)
    }

    /// Everything the decision needs, so that none of it is read from the world
    /// inside the function being tested.
    struct Input: Equatable {
        var bundlePath: String
        /// `Notchy.app`, read from the bundle rather than written down: this
        /// project has been renamed once already.
        var expectedBundleName: String
        var home: String
        /// `statfs().f_flags & MNT_RDONLY`, not a guess from the path. An
        /// external drive someone keeps apps on is writable and stays untouched.
        var isReadOnlyVolume: Bool
        var applicationsWritable: Bool
        var isDebugBuild: Bool
        var isCI: Bool
        /// `CFBundleVersion`, so that "not now" lasts until the next version
        /// rather than for ever.
        var version: String
        var promptedForVersion: String?
        /// Another live process with this bundle id, if there is one.
        var otherCopyBundlePath: String?

        init(bundlePath: String,
             expectedBundleName: String,
             home: String,
             isReadOnlyVolume: Bool = false,
             applicationsWritable: Bool = true,
             isDebugBuild: Bool = false,
             isCI: Bool = false,
             version: String = "0",
             promptedForVersion: String? = nil,
             otherCopyBundlePath: String? = nil) {
            self.bundlePath = bundlePath
            self.expectedBundleName = expectedBundleName
            self.home = home
            self.isReadOnlyVolume = isReadOnlyVolume
            self.applicationsWritable = applicationsWritable
            self.isDebugBuild = isDebugBuild
            self.isCI = isCI
            self.version = version
            self.promptedForVersion = promptedForVersion
            self.otherCopyBundlePath = otherCopyBundlePath
        }
    }

    // MARK: - The cheap question, asked on every single launch

    /// Is this copy already where it belongs, under the name it should have?
    ///
    /// Two string comparisons. A settled copy — which is nearly every launch —
    /// never gets as far as a `statfs`, a scan of running applications or a
    /// read of user defaults.
    static func isSettled(bundlePath: String, home: String, expectedBundleName: String) -> Bool {
        let path = normalise(bundlePath)
        guard (path as NSString).lastPathComponent == expectedBundleName else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        return parent == "/Applications" || parent == home + "/Applications"
    }

    // MARK: - Reading the path

    static func place(bundlePath: String, home: String, isReadOnlyVolume: Bool) -> Place {
        let path = normalise(bundlePath)
        let parent = (path as NSString).deletingLastPathComponent

        // First, and it has to be: a translocated bundle also sits on a
        // read-only mount, so testing the mount first would hide it.
        if path.contains("/AppTranslocation/") { return .translocated }

        if parent == "/Applications" { return .applications }
        if parent == home + "/Applications" { return .userApplications }
        if parent.hasPrefix("/Applications/") { return .applicationsSubfolder }
        if parent.hasPrefix(home + "/Applications/") { return .applicationsSubfolder }

        // Prefix, not equality: a .dmg often unpacks into a folder of its own,
        // and `~/Downloads/Notchy 0.1.11/Notchy.app` is the same mistake.
        if parent == home + "/Downloads" || parent.hasPrefix(home + "/Downloads/") { return .downloads }
        if parent == home + "/Desktop"   || parent.hasPrefix(home + "/Desktop/")   { return .desktop }

        if isReadOnlyVolume { return .readOnlyVolume }
        return .elsewhere
    }

    // MARK: - The decision

    static func decide(_ input: Input) -> Verdict {
        // Never a developer, and never CI. These are inputs rather than `#if`
        // because `swiftc` does not define DEBUG when it compiles this file for
        // the test, so a `#if` here would make the test assert a branch that no
        // user ever runs.
        if input.isDebugBuild || input.isCI { return .stay }

        let here = place(bundlePath: input.bundlePath,
                         home: input.home,
                         isReadOnlyVolume: input.isReadOnlyVolume)
        let name = (normalise(input.bundlePath) as NSString).lastPathComponent
        let alreadySaidNo = input.promptedForVersion == input.version

        switch here {
        case .applications, .userApplications:
            guard name == input.expectedBundleName else {
                return alreadySaidNo ? .stay : .warnRenamed(actualName: name)
            }
            return .stay

        case .elsewhere:
            // A build directory, `/opt`, a second volume. Deliberate; leave it.
            return .stay

        case .translocated, .downloads, .desktop, .readOnlyVolume, .applicationsSubfolder:
            // Someone opened the copy on the image while the real one is
            // already running. Wake that one instead of racing it for the
            // socket — the reopen is what the double-click was asking for.
            if let other = input.otherCopyBundlePath,
               isSettled(bundlePath: other, home: input.home, expectedBundleName: input.expectedBundleName) {
                return .handOverToRunningCopy(bundlePath: other)
            }
            if alreadySaidNo { return .stay }
            return .offerMove(from: here, to: destination(applicationsWritable: input.applicationsWritable))
        }
    }

    // MARK: - Where a move goes

    static func destination(applicationsWritable: Bool) -> Destination {
        applicationsWritable ? .applications : .userApplications
    }

    static func movePath(to destination: Destination, home: String, bundleName: String) -> String {
        switch destination {
        case .applications:     return "/Applications/" + bundleName
        case .userApplications: return home + "/Applications/" + bundleName
        }
    }

    // MARK: -

    /// A trailing slash changes nothing about where a bundle is, and
    /// `NSString.deletingLastPathComponent` would otherwise hand back the
    /// bundle itself as its own parent.
    private static func normalise(_ path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
