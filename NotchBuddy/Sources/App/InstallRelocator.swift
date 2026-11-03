import AppKit
import Darwin

/// The side of `InstallLocation` that touches the world: it asks, it copies, it
/// relaunches. The rule it acts on lives next door and is tested; this part
/// cannot be, because it needs a disk image and a pair of hands.
@MainActor
enum InstallRelocator {

    enum Outcome { case carryOn, stopHere }

    /// Key under which "not now" is remembered. Holds a version string rather
    /// than a flag, so the question comes back once after an update and not on
    /// every single launch in between.
    private static let declinedKey = "installLocationPromptedVersion"

    // MARK: - The cheap question

    /// Is there anything at all to decide? Two string comparisons, no UI, and
    /// safe to ask from `applicationDidFinishLaunching`.
    ///
    /// It has to be separate from `runAtLaunch()` because that one can put a
    /// modal on screen, and a modal cannot run from inside `finishLaunching`:
    /// `NSApp` is not running yet at that point, so `runModal()` returns its
    /// default answer — the first button — without ever drawing the alert. It
    /// did exactly that, and moved the app without anyone having clicked
    /// anything, which is the opposite of what this is for.
    static func needsAttention() -> Bool {
        !InstallLocation.isSettled(bundlePath: Bundle.main.bundleURL.resolvingSymlinksInPath().path,
                                   home: NSHomeDirectory(),
                                   expectedBundleName: expectedBundleName())
    }

    // MARK: - The whole of it

    /// Must be called from a turn of the run loop, not from `finishLaunching`.
    /// See `needsAttention()`.
    static func runAtLaunch() -> Outcome {
        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let path = bundleURL.path
        let home = NSHomeDirectory()
        let expected = expectedBundleName()

        // Nearly every launch stops here, on two string comparisons: no statfs,
        // no scan of running applications, no read of user defaults.
        if InstallLocation.isSettled(bundlePath: path, home: home, expectedBundleName: expected) {
            return .carryOn
        }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let input = InstallLocation.Input(
            bundlePath: path,
            expectedBundleName: expected,
            home: home,
            isReadOnlyVolume: isOnReadOnlyVolume(path),
            applicationsWritable: access("/Applications", W_OK) == 0,
            isDebugBuild: isDebugBuild,
            isCI: ProcessInfo.processInfo.environment["CI"] != nil,
            version: version,
            promptedForVersion: UserDefaults.standard.string(forKey: declinedKey),
            otherCopyBundlePath: otherRunningCopy())

        switch InstallLocation.decide(input) {
        case .stay:
            return .carryOn

        case .handOverToRunningCopy(let other):
            // Someone double-clicked the copy on the image while the installed
            // one is already running. Both would answer the same hook socket,
            // and the newer one wins by unlinking it. Send the reopen to the
            // real copy instead — which is what the double-click meant — and go.
            appendAppLog("install.log", "another copy is running from \(other); handing over and quitting")
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: other),
                                               configuration: NSWorkspace.OpenConfiguration(),
                                               completionHandler: nil)
            quitShortly()
            return .stopHere

        case .warnRenamed(let actualName):
            UserDefaults.standard.set(version, forKey: declinedKey)
            let alert = NSAlert()
            alert.messageText = L("Notchy has been renamed.")
            alert.informativeText = String(
                format: L("This copy is called “%@”. Updates and the Claude Code hook both look for Notchy.app, so rename it back in the Finder."),
                actualName)
            show(alert)
            return .carryOn

        case .offerMove(let from, let to):
            return offerMove(from: from, to: to, bundleURL: bundleURL,
                             home: home, expected: expected, version: version)
        }
    }

    // MARK: - Asking

    private static func offerMove(from: InstallLocation.Place,
                                  to: InstallLocation.Destination,
                                  bundleURL: URL,
                                  home: String,
                                  expected: String,
                                  version: String) -> Outcome {
        let alert = NSAlert()
        alert.messageText = from == .applicationsSubfolder
            ? L("Move Notchy to the top of your Applications folder?")
            : L("Move Notchy to your Applications folder?")

        var body: String
        switch from {
        case .readOnlyVolume:        body = L("Notchy is running from the disk image it arrived in.")
        case .downloads:             body = L("Notchy is running from your Downloads folder.")
        case .desktop:               body = L("Notchy is running from your Desktop.")
        case .translocated:          body = L("macOS is running Notchy from a temporary copy, because it was opened before it was moved.")
        case .applicationsSubfolder: body = ""
        default:                     body = ""
        }
        let shared = from == .applicationsSubfolder
            ? L("Notchy is in a folder inside Applications. Updates and the Claude Code hook both look for it at the top level, so moving it up takes a second and settles both.")
            : L("Notchy keeps its permissions, answers Claude Code and updates itself only from Applications. Moving it there takes a second; the copy you opened is left where it is.")
        body = body.isEmpty ? shared : body + " " + shared
        if to == .userApplications {
            body += " " + L("/Applications cannot be written to from this account, so Notchy goes in your own Applications folder instead.")
        }
        alert.informativeText = body

        alert.addButton(withTitle: L("Move to Applications"))   // .alertFirstButtonReturn, and the default
        alert.addButton(withTitle: L("Not now"))

        let answer = show(alert)
        appendAppLog("install.log", "offered to move from \(from) to \(to); answer \(answer.rawValue)")
        guard answer == .alertFirstButtonReturn else {
            UserDefaults.standard.set(version, forKey: declinedKey)
            return .carryOn
        }

        let target = InstallLocation.movePath(to: to, home: home, bundleName: expected)
        do {
            try move(bundleURL, to: target)
        } catch {
            let failed = NSAlert()
            failed.messageText = L("Notchy could not move itself.")
            failed.informativeText = L("Drag it into Applications in the Finder and open it from there.")
                + "\n\n" + error.localizedDescription
            show(failed)                       // no addButton: macOS supplies a localized OK
            appendAppLog("install.log", "move to \(target) failed: \(error.localizedDescription)")
            return .carryOn                    // a failed move must not leave them with no app
        }

        ejectSourceVolume(of: bundleURL)
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: target),
                                           configuration: newInstanceConfiguration(),
                                           completionHandler: nil)
        quitShortly()
        return .stopHere
    }

    // MARK: - Moving

    private static func move(_ source: URL, to target: String) throws {
        let fm = FileManager.default
        let staging = target + ".new"
        let previous = target + ".old"
        try? fm.removeItem(atPath: staging)
        try? fm.removeItem(atPath: previous)

        // ditto rather than FileManager.copyItem: this bundle is ad-hoc signed,
        // and an ad-hoc signature is a hash of the bytes. Reproduce it exactly
        // or the copy arrives "damaged" — and the Accessibility grant, which is
        // keyed to that same hash, survives the move precisely because of it.
        guard runTool("/usr/bin/ditto", [source.path, staging]) == 0 else {
            throw NSError(domain: "InstallRelocator", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "ditto could not copy the application."])
        }

        if fm.fileExists(atPath: target) {
            try fm.moveItem(atPath: target, toPath: previous)
        }
        do { try fm.moveItem(atPath: staging, toPath: target) }
        catch {
            // Put back whatever was there before giving up.
            if fm.fileExists(atPath: previous) { try? fm.moveItem(atPath: previous, toPath: target) }
            try? fm.removeItem(atPath: staging)
            throw error
        }
        try? fm.removeItem(atPath: previous)

        // The copy carries the quarantine flag from the download it came out
        // of, and without clearing it the relaunch below meets exactly the
        // refusal this whole feature exists to get the user past. Scoped to the
        // one bundle just written, after an explicit click — the same command
        // docs/download.html has always told people to run by hand. Logged,
        // because it is a security-relevant action and should be auditable.
        runTool("/usr/bin/xattr", ["-d", "-r", "com.apple.quarantine", target])
        runTool("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                ["-f", target])
        appendAppLog("install.log", "moved from \(source.path) to \(target); quarantine cleared on the copy")
    }

    /// Ejects the image the app was opened from, once it is no longer the one
    /// running. Nothing is deleted — the download stays where the user put it.
    private static func ejectSourceVolume(of source: URL) {
        let origin = translocationOrigin(of: source) ?? source
        guard let mount = mountPoint(of: origin.path), mount.hasPrefix("/Volumes/") else { return }
        try? NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: mount))
    }

    // MARK: - Asking the system where it put us

    private static func isOnReadOnlyVolume(_ path: String) -> Bool {
        var s = statfs()
        guard statfs(path, &s) == 0 else { return false }
        return (s.f_flags & UInt32(MNT_RDONLY)) != 0
    }

    private static func mountPoint(of path: String) -> String? {
        var s = statfs()
        guard statfs(path, &s) == 0 else { return nil }
        return withUnsafePointer(to: s.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    /// The real location of a translocated bundle.
    ///
    /// `SecTranslocateCreateOriginalPathForURL` is exported by Security.framework
    /// but ships no header in the SDK, so Swift cannot see it without this.
    /// Only the eject uses it: when it fails, nothing is lost. The *detection*
    /// deliberately does not — it uses the same `/AppTranslocation/` path test
    /// Sparkle uses in `SUHost.m`, so the two can never disagree about what
    /// counts as translocated.
    private static func translocationOrigin(of url: URL) -> URL? {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        typealias Fn = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        var err: Unmanaged<CFError>?
        // CF_RETURNS_RETAINED
        return unsafeBitCast(symbol, to: Fn.self)(url as CFURL, &err)?.takeRetainedValue() as URL?
    }

    private static func otherRunningCopy() -> String? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != me }
            .compactMap { $0.bundleURL?.resolvingSymlinksInPath().path }
            .first
    }

    private static func expectedBundleName() -> String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
        return (name.map { $0 + ".app" }) ?? "Notchy.app"
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: -

    /// `LSUIElement` plus `.accessory` means a panel opens behind whatever is
    /// frontmost, which for a modal nobody asked for would be invisible.
    @discardableResult
    private static func show(_ alert: NSAlert) -> NSApplication.ModalResponse {
        // A modal before NSApp is running answers itself with the first button.
        // runAtLaunch() is only ever called from a run-loop turn, so this
        // should not happen — but the failure is silent and it moves files, so
        // it is worth refusing outright rather than trusting the caller.
        guard NSApp.isRunning else {
            appendAppLog("install.log", "refused to show an alert before the app was running")
            return .cancel
        }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    private static func newInstanceConfiguration() -> NSWorkspace.OpenConfiguration {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        return config
    }

    /// A moment for LaunchServices to start the copy at the new path before
    /// this process goes away. Main queue: a closure written in a `@MainActor`
    /// type belongs nowhere else.
    private static func quitShortly() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
    }

    @discardableResult
    private static func runTool(_ path: String, _ arguments: [String]) -> Int32 {
        guard FileManager.default.isExecutableFile(atPath: path) else { return -1 }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return -1 }
        task.waitUntilExit()
        return task.terminationStatus
    }
}
