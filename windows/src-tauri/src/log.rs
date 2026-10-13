// Small append-only log at %LOCALAPPDATA%\Coucou\coucou.log (Windows) or
// ~/.local/share/coucou/coucou.log (Linux) — the equivalent of nbLog() in
// HookServer.swift. Nothing leaves the machine.

use std::io::Write;

use crate::{platform, settings};

pub fn line(message: impl AsRef<str>) {
    let t = platform::local_time();
    let stamp = format!(
        "{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
        t.year, t.month, t.day, t.hour, t.minute, t.second
    );
    let dir = settings::local_dir();
    if platform::ensure_private_dir(&dir).is_err() {
        return;
    }
    let path = dir.join("coucou.log");
    // Keep it from growing forever, but never at the cost of the evidence: an
    // app that dies and relaunches writes a fresh `started` every time, and
    // deleting the file outright used to take the crash before it with them.
    // One generation back is enough to read a death that happened an hour ago.
    if std::fs::metadata(&path).map(|m| m.len() > 1_000_000).unwrap_or(false) {
        let _ = std::fs::rename(&path, dir.join("coucou.log.1"));
    }
    let mut options = std::fs::OpenOptions::new();
    options.create(true).append(true);
    // Readable by us only, like the macOS log.
    #[cfg(unix)]
    std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);
    if let Ok(mut file) = options.open(path) {
        let _ = writeln!(file, "{stamp} {}", message.as_ref());
    }
}

/// Writes a panic to the log before the process goes.
///
/// The release profile is `panic = "abort"` and the binary is built with
/// `windows_subsystem = "windows"` and `strip = true`, so a panic on any of the
/// background threads ends the process with no console, no dialog, no line here
/// and no symbols in the crash dump — the app simply vanishes, which is exactly
/// what "it closes by itself" looks like from the user's chair. The hook still
/// runs under `abort`, so this is the one chance to say what happened.
///
/// Must be installed before anything is spawned, and must not panic itself: a
/// panic in here is a double panic, which aborts with less to show than before.
/// Everything it touches ignores its own errors.
pub fn install_panic_hook() {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        // The payload is a `&str` for `panic!("literal")` and a `String` once
        // anything is formatted into it. Neither downcast allocates on failure.
        let message = info
            .payload()
            .downcast_ref::<&str>()
            .map(|s| (*s).to_string())
            .or_else(|| info.payload().downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "(no message)".to_string());
        let where_ = info
            .location()
            .map(|l| format!("{}:{}:{}", l.file(), l.line(), l.column()))
            .unwrap_or_else(|| "unknown".to_string());
        // Without the thread name there is no telling the cursor poll from the
        // clipboard watcher from the media loop, which is most of the answer.
        let thread = std::thread::current();
        let who = thread.name().unwrap_or("unnamed").to_string();
        line(format!("panic [{who}] {where_} — {message}"));
        // Debug builds have a console; leave what it used to print alone.
        previous(info);
    }));
}
