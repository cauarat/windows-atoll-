import Foundation

/// `~/Library/Application Support/Notchy`, where the app keeps what it writes
/// for itself.
///
/// It used to hang off the hook server, which was the first thing to need it.
/// The hook server went with the coding agents; the folder, and the inbox in
/// it, did not.
enum AppSupport {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchy")
    }

    /// Where a dropped, pasted or recorded file is copied before it goes anywhere.
    static var inbox: URL { directory.appendingPathComponent("inbox") }

    /// At launch: the folder exists and only its owner can read it, because the
    /// inbox holds whatever the user dropped on the island.
    static func prepare() {
        let fm = FileManager.default
        let dir = directory
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o700 as NSNumber], ofItemAtPath: dir.path)
        retireHookRelay(in: dir)
        #if APPSTORE
        // The sandboxed build kept its socket at the container's root.
        try? fm.removeItem(atPath: NSHomeDirectory() + "/nb.sock")
        #endif
    }

    /// What `nb-hook` becomes: a clean exit, and nothing else — except for a
    /// status line.
    ///
    /// The plan-usage relay put `nb-hook --statusline` in front of whatever
    /// status line the user already had, kept in `statusline-previous.json`,
    /// and ran that one for them. It still has to, or their status line goes
    /// blank. `plutil` reads the saved command so no Python is started; the
    /// payload on stdin goes through to it as it always did.
    static let retiredRelay = """
        #!/bin/sh
        # Notchy no longer shows coding agents. This stays so a hook still
        # registered in ~/.claude/settings.json finishes at once. Remove the
        # hook entries that name this file, then this file, whenever you like.
        case " $* " in
        *" --statusline "*)
            # The status line you had before Notchy's, run as it always was.
            prev="$(dirname "$0")/statusline-previous.json"
            if [ -f "$prev" ]; then
                cmd=$(/usr/bin/plutil -extract command raw -o - "$prev" 2>/dev/null)
                if [ -n "$cmd" ]; then /bin/sh -c "$cmd"; fi
            fi
            ;;
        esac
        exit 0

        """

    /// What the hook server left behind, made harmless.
    ///
    /// Notchy no longer listens to Claude Code, Codex, Cursor or Gemini CLI, but
    /// anyone who registered `nb-hook` in `~/.claude/settings.json` still has it
    /// there, and that file is the user's: it is never rewritten without asking.
    /// So the relay it names stays where it is, cut down to a script that
    /// finishes at once — no Python started, no socket tried — and the agent
    /// carries on exactly as if Notchy were not installed. Deleting it instead
    /// would turn every hooked event into an error in the agent's terminal.
    ///
    /// Only a relay that is already there is rewritten; a new install gets none.
    /// The Python half and the socket have nothing left to do and go;
    /// `statusline-previous.json` stays, because the relay still reads it.
    static func retireHookRelay(in dir: URL) {
        let fm = FileManager.default
        let relay = dir.appendingPathComponent("nb-hook")
        if fm.fileExists(atPath: relay.path) {
            if (try? String(contentsOf: relay, encoding: .utf8)) != retiredRelay {
                try? retiredRelay.write(to: relay, atomically: true, encoding: .utf8)
            }
            // Executable whatever it was, or the agent reports a failed hook.
            try? fm.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: relay.path)
        }
        try? fm.removeItem(at: dir.appendingPathComponent("nb-hook.py"))
        try? fm.removeItem(at: dir.appendingPathComponent("nb.sock"))
    }
}
