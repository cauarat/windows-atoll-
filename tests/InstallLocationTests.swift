import Foundation

/// Where Notchy is allowed to run from, and what it does when it is somewhere
/// else. Written down here because none of it can be checked from a script on
/// this machine: the alert, the copy and the relaunch all need a .dmg, a Finder
/// and a pair of hands.
@main
enum InstallLocationTests {
    static var failures = 0

    static func check(_ label: String, _ got: String, _ expected: String) {
        if got == expected { print("  ✓ \(label)") }
        else {
            print("  ✗ \(label)")
            print("    got:      \(got)")
            print("    expected: \(expected)")
            failures += 1
        }
    }

    static let home = "/Users/mochi"
    static let app = "Notchy.app"

    static func place(_ path: String, readOnly: Bool = false) -> String {
        "\(InstallLocation.place(bundlePath: path, home: home, isReadOnlyVolume: readOnly))"
    }

    static func verdict(_ path: String,
                        readOnly: Bool = false,
                        writable: Bool = true,
                        debug: Bool = false,
                        ci: Bool = false,
                        version: String = "0.1.12",
                        prompted: String? = nil,
                        other: String? = nil) -> String {
        let input = InstallLocation.Input(bundlePath: path,
                                          expectedBundleName: app,
                                          home: home,
                                          isReadOnlyVolume: readOnly,
                                          applicationsWritable: writable,
                                          isDebugBuild: debug,
                                          isCI: ci,
                                          version: version,
                                          promptedForVersion: prompted,
                                          otherCopyBundlePath: other)
        return "\(InstallLocation.decide(input))"
    }

    static func main() {
        print("")
        print("Where the bundle sits, from the path alone")
        check("/Applications is the place", place("/Applications/Notchy.app"),
              "\(InstallLocation.Place.applications)")
        check("so is the one in your own home", place("\(home)/Applications/Notchy.app"),
              "\(InstallLocation.Place.userApplications)")
        check("a folder inside Applications is not", place("/Applications/Utilities/Notchy.app"),
              "\(InstallLocation.Place.applicationsSubfolder)")
        check("nor one inside your own Applications", place("\(home)/Applications/Dev/Notchy.app"),
              "\(InstallLocation.Place.applicationsSubfolder)")
        check("Downloads", place("\(home)/Downloads/Notchy.app"),
              "\(InstallLocation.Place.downloads)")
        check("a folder the .dmg unpacked into is still Downloads",
              place("\(home)/Downloads/Notchy 0.1.11/Notchy.app"),
              "\(InstallLocation.Place.downloads)")
        check("the Desktop", place("\(home)/Desktop/Notchy.app"),
              "\(InstallLocation.Place.desktop)")
        check("a mounted image is read-only, and that is how it is known",
              place("/Volumes/Notchy/Notchy.app", readOnly: true),
              "\(InstallLocation.Place.readOnlyVolume)")
        check("translocation wins over the read-only mount it sits on",
              place("/private/var/folders/5k/xx/X/AppTranslocation/0A1B/d/Notchy.app", readOnly: true),
              "\(InstallLocation.Place.translocated)")
        check("another user's Applications is not yours",
              place("/Users/someone-else/Applications/Notchy.app"),
              "\(InstallLocation.Place.elsewhere)")
        check("a build directory is somewhere someone meant",
              place("\(home)/Library/Developer/Xcode/DerivedData/x/Build/Products/Release/Notchy.app"),
              "\(InstallLocation.Place.elsewhere)")
        check("a trailing slash changes nothing", place("/Applications/Notchy.app/"),
              "\(InstallLocation.Place.applications)")

        print("")
        print("A copy that is already where it belongs costs nothing")
        check("settled", "\(InstallLocation.isSettled(bundlePath: "/Applications/Notchy.app", home: home, expectedBundleName: app))", "true")
        check("settled in your own Applications too",
              "\(InstallLocation.isSettled(bundlePath: "\(home)/Applications/Notchy.app", home: home, expectedBundleName: app))", "true")
        check("not settled under another name",
              "\(InstallLocation.isSettled(bundlePath: "/Applications/Notchy 2.app", home: home, expectedBundleName: app))", "false")
        check("not settled on the image",
              "\(InstallLocation.isSettled(bundlePath: "/Volumes/Notchy/Notchy.app", home: home, expectedBundleName: app))", "false")

        print("")
        print("Nothing ever fires for a developer")
        check("a Debug build on the image stays put", verdict("/Volumes/Notchy/Notchy.app", readOnly: true, debug: true),
              "\(InstallLocation.Verdict.stay)")
        check("so does anything on CI", verdict("\(home)/Downloads/Notchy.app", ci: true),
              "\(InstallLocation.Verdict.stay)")
        check("and a Debug build in /Applications, which is where install-mac.sh puts it",
              verdict("/Applications/Notchy.app", debug: true),
              "\(InstallLocation.Verdict.stay)")
        check("a Release build run from DerivedData is left alone",
              verdict("\(home)/Library/Developer/Xcode/DerivedData/x/Build/Products/Release/Notchy.app"),
              "\(InstallLocation.Verdict.stay)")

        print("")
        print("A bad location offers the move")
        for (label, path, ro) in [("the disk image", "/Volumes/Notchy/Notchy.app", true),
                                  ("Downloads", "\(home)/Downloads/Notchy.app", false),
                                  ("the Desktop", "\(home)/Desktop/Notchy.app", false)] {
            check(label, verdict(path, readOnly: ro),
                  "\(InstallLocation.Verdict.offerMove(from: ro ? .readOnlyVolume : (path.contains("Desktop") ? .desktop : .downloads), to: .applications))")
        }
        check("a translocated copy", verdict("/private/var/folders/5k/xx/X/AppTranslocation/0A1B/d/Notchy.app", readOnly: true),
              "\(InstallLocation.Verdict.offerMove(from: .translocated, to: .applications))")
        check("a folder inside Applications", verdict("/Applications/Utilities/Notchy.app"),
              "\(InstallLocation.Verdict.offerMove(from: .applicationsSubfolder, to: .applications))")

        print("")
        print("…and your own Applications when /Applications is not writable")
        check("the destination follows the permission", verdict("\(home)/Downloads/Notchy.app", writable: false),
              "\(InstallLocation.Verdict.offerMove(from: .downloads, to: .userApplications))")
        check("which is where the copy would land",
              InstallLocation.movePath(to: .userApplications, home: home, bundleName: app),
              "\(home)/Applications/Notchy.app")
        check("and otherwise", InstallLocation.movePath(to: .applications, home: home, bundleName: app),
              "/Applications/Notchy.app")

        print("")
        print("“Not now” is remembered, for this version only")
        check("asked and declined, this version", verdict("\(home)/Downloads/Notchy.app", version: "0.1.12", prompted: "0.1.12"),
              "\(InstallLocation.Verdict.stay)")
        check("declined on the version before, so ask again",
              verdict("\(home)/Downloads/Notchy.app", version: "0.1.12", prompted: "0.1.11"),
              "\(InstallLocation.Verdict.offerMove(from: .downloads, to: .applications))")

        print("")
        print("A copy already running from Applications takes over")
        check("hand the reopen to it and quit",
              verdict("/Volumes/Notchy/Notchy.app", readOnly: true, other: "/Applications/Notchy.app"),
              "\(InstallLocation.Verdict.handOverToRunningCopy(bundlePath: "/Applications/Notchy.app"))")
        check("but not to another copy that is itself on the image",
              verdict("\(home)/Downloads/Notchy.app", other: "/Volumes/Notchy/Notchy.app"),
              "\(InstallLocation.Verdict.offerMove(from: .downloads, to: .applications))")

        print("")
        print("A renamed bundle in the right place is told, not moved")
        check("renamed in /Applications", verdict("/Applications/Notchy 2.app"),
              "\(InstallLocation.Verdict.warnRenamed(actualName: "Notchy 2.app"))")
        check("renamed in Downloads is simply moved, which fixes the name",
              verdict("\(home)/Downloads/Flow.app"),
              "\(InstallLocation.Verdict.offerMove(from: .downloads, to: .applications))")
        check("and the rename is said once per version too",
              verdict("/Applications/Notchy 2.app", version: "0.1.12", prompted: "0.1.12"),
              "\(InstallLocation.Verdict.stay)")

        print("")
        if failures == 0 { print("All install location tests passed.") }
        else { print("\(failures) failure(s)."); exit(1) }
    }
}
