import Foundation

// What the retired hook relay leaves behind (AppSupport.retireHookRelay).
// Someone who registered nb-hook in ~/.claude/settings.json by hand still has
// it there; the relay has to keep finishing at once, and must not appear for
// anyone who never had it. Compiled by scripts/test-app-support.sh.

nonisolated(unsafe) var failures = 0
func check(_ condition: Bool, _ what: String) {
    if condition { print("  ✓ \(what)") } else { failures += 1; print("  ✗ \(what)") }
}

/// Runs a file the way a hook runs it, with a payload on stdin.
func run(_ path: String) -> (status: Int32, output: String, seconds: Double) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    let input = Pipe(), output = Pipe()
    p.standardInput = input
    p.standardOutput = output
    p.standardError = output
    let start = Date()
    do { try p.run() } catch { return (-1, "\(error)", 0) }
    input.fileHandleForWriting.write(Data(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash"}"#.utf8))
    try? input.fileHandleForWriting.close()
    p.waitUntilExit()
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return (p.terminationStatus, text, Date().timeIntervalSince(start))
}

@main
enum AppSupportTests {
    static func main() {
        let fm = FileManager.default

        print("AppSupport — an install that had the relay")
        let dir = fm.temporaryDirectory.appendingPathComponent("notchy-app-support-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let relay = dir.appendingPathComponent("nb-hook")
        try? "#!/bin/sh\n/usr/bin/python3 \"$(dirname \"$0\")/nb-hook.py\" \"$@\"\n".write(to: relay, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o644 as NSNumber], ofItemAtPath: relay.path)
        try? "import sys\n".write(to: dir.appendingPathComponent("nb-hook.py"), atomically: true, encoding: .utf8)
        try? Data().write(to: dir.appendingPathComponent("nb.sock"))

        AppSupport.retireHookRelay(in: dir)

        check(fm.fileExists(atPath: relay.path), "nb-hook is still there for the hook that names it")
        check((try? String(contentsOf: relay, encoding: .utf8)) == AppSupport.retiredRelay, "and is the no-op script")
        check(fm.isExecutableFile(atPath: relay.path), "and is executable, even though it was not")
        check(!fm.fileExists(atPath: dir.appendingPathComponent("nb-hook.py").path), "nb-hook.py is gone")
        check(!fm.fileExists(atPath: dir.appendingPathComponent("nb.sock").path), "nb.sock is gone")
        let result = run(relay.path)
        check(result.status == 0, "it exits 0")
        check(result.output.isEmpty, "it says nothing, so the agent decides as if Notchy were not there")
        check(result.seconds < 1, "it finishes at once (\(String(format: "%.2f", result.seconds)) s)")

        AppSupport.retireHookRelay(in: dir)
        check((try? String(contentsOf: relay, encoding: .utf8)) == AppSupport.retiredRelay, "a second launch leaves it as it is")

        print("AppSupport — an install that never had it")
        let clean = fm.temporaryDirectory.appendingPathComponent("notchy-app-support-\(UUID().uuidString)")
        try? fm.createDirectory(at: clean, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: clean) }
        AppSupport.retireHookRelay(in: clean)
        check(!fm.fileExists(atPath: clean.appendingPathComponent("nb-hook").path), "no relay is created")

        print("")
        if failures == 0 { print("All app support tests passed.") }
        else { print("\(failures) failure(s)."); exit(1) }
    }
}
