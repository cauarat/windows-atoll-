// Staying up to date.
//
// Coucou asks GitHub whether a newer release exists — once a minute and a half
// after launch, then every six hours. Nothing is downloaded and nothing
// restarts until somebody clicks. That is deliberate: this app answers Claude
// Code permission requests over a named pipe, and a silent restart would drop
// whichever one was waiting in it, leaving a session hanging on a dialog that
// no longer exists.
//
// The request carries nothing. It is a plain GET for a small JSON file on the
// releases page — no identifier, no install count, no version history. It is
// also the only call in the app that reaches a service the user did not
// configure themselves, which is why Settings can switch it off.
//
// Every package the updater will install is signed with the private half of
// the key whose public half is `pubkey` in tauri.conf.json. A download that is
// unsigned, altered, or signed with anything else is refused before it is run,
// so the worst a hijacked releases page can do is serve a file that fails
// verification and leave the installed copy alone.

use std::sync::Mutex;
use std::time::Duration;

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_updater::UpdaterExt;

use crate::log;

/// Where anyone the updater cannot help is sent instead.
const RELEASES_URL: &str = "https://github.com/cauarat/windows-atoll-/releases";

/// Late enough that it never competes with the island's first paint or with
/// staging the hook relay, both of which happen in the first seconds.
const FIRST_CHECK: Duration = Duration::from_secs(90);

/// Six hours. A character in the notch has no reason to ask more often, and
/// anyone in a hurry has Check now in Settings.
const EVERY: Duration = Duration::from_secs(6 * 60 * 60);

#[derive(Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Phase {
    /// Nothing known yet — the state at launch, before the first check.
    Idle,
    Checking,
    UpToDate,
    Available,
    Downloading,
    /// Installed, waiting for the restart that picks it up.
    Ready,
    Error,
}

/// What the settings window and the tray menu both draw from.
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateState {
    pub phase: Phase,
    /// The version on offer, once there is one.
    pub version: Option<String>,
    /// Release notes, as the manifest carries them.
    pub notes: Option<String>,
    /// 0…1 while the package is coming down.
    pub progress: f64,
    pub error: Option<String>,
    /// Whether this copy can replace itself — see `installable`.
    pub installable: bool,
    pub release_url: &'static str,
}

impl Default for UpdateState {
    fn default() -> Self {
        Self {
            phase: Phase::Idle,
            version: None,
            notes: None,
            progress: 0.0,
            error: None,
            installable: installable(),
            release_url: RELEASES_URL,
        }
    }
}

/// Whether this copy can replace itself in place.
///
/// The NSIS installer leaves its uninstaller beside coucou.exe. The portable
/// .zip has no such file, and running the installer over it would put a second
/// copy in %LOCALAPPDATA% while the one on screen stayed old — so those builds
/// are offered the releases page instead of a button that quietly makes things
/// worse. A deleted uninstall.exe only costs someone the one-click path.
#[cfg(windows)]
fn installable() -> bool {
    std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.join("uninstall.exe").is_file()))
        .unwrap_or(false)
}

/// Only an AppImage carries its own updater. A .deb or .rpm belongs to the
/// package manager, and overwriting it behind apt's or dnf's back would leave
/// the two disagreeing about what is installed. `APPIMAGE` is set by the
/// AppImage runtime itself, which is precisely the question being asked.
#[cfg(target_os = "linux")]
fn installable() -> bool {
    std::env::var_os("APPIMAGE").is_some()
}

#[cfg(not(any(windows, target_os = "linux")))]
fn installable() -> bool {
    false
}

#[derive(Default)]
pub struct Updates(Mutex<UpdateState>);

pub fn state(app: &AppHandle) -> UpdateState {
    app.try_state::<Updates>()
        .map(|updates| updates.0.lock().unwrap().clone())
        .unwrap_or_default()
}

/// The tray's one update row, or nothing when there is nothing to say.
///
/// A download in progress deliberately shows no row: the percentage belongs in
/// the settings window, and a menu that rebuilt itself on every chunk would
/// close itself under the pointer.
pub fn menu_item(state: &UpdateState) -> Option<String> {
    let version = state.version.as_deref()?;
    match state.phase {
        Phase::Available if state.installable => Some(format!("Update to {version}…")),
        Phase::Available => Some(format!("Version {version} is out — open the page…")),
        Phase::Ready => Some(format!("Restart to finish updating to {version}")),
        _ => None,
    }
}

/// Stores the new state, repaints the tray if its one row changed, and tells
/// both windows.
fn set(app: &AppHandle, next: UpdateState) {
    let mut tray_changed = false;
    if let Some(updates) = app.try_state::<Updates>() {
        let mut slot = updates.0.lock().unwrap();
        tray_changed = menu_item(&slot) != menu_item(&next);
        *slot = next.clone();
    }
    if tray_changed {
        // Every other caller of tray::refresh is already on the main thread —
        // a menu click, or a settings command. This one is not: it runs on the
        // background task doing the checking, and a GTK menu rebuilt from the
        // wrong thread is how Linux ends up with a tray icon that stops
        // responding.
        let handle = app.clone();
        let _ = app.run_on_main_thread(move || {
            crate::tray::refresh(&handle, crate::is_enabled(&handle));
        });
    }
    let _ = app.emit("update-state", next);
}

/// Only the window hears about the download; see `menu_item` for why the tray
/// stays out of it.
fn progress(app: &AppHandle, fraction: f64) {
    let next = {
        let Some(updates) = app.try_state::<Updates>() else { return };
        let mut slot = updates.0.lock().unwrap();
        // One event per whole percent. A 40 MB installer arrives in several
        // thousand chunks and the window has nothing new to draw for most of
        // them.
        let same = (fraction * 100.0) as u32 == (slot.progress * 100.0) as u32;
        if same && fraction < 1.0 {
            return;
        }
        slot.progress = fraction;
        slot.clone()
    };
    let _ = app.emit("update-state", next);
}

fn fail(app: &AppHandle, message: String) {
    log::line(format!("update: {message}"));
    set(app, UpdateState { phase: Phase::Error, error: Some(message), ..UpdateState::default() });
}

/// One round trip to the releases page.
///
/// The version comparison is the plugin's, not ours: `check()` hands back
/// `None` when the manifest is not newer than this build.
async fn look(app: &AppHandle) -> Result<Option<(String, Option<String>)>, String> {
    let updater = app.updater().map_err(|err| err.to_string())?;
    let found = updater.check().await.map_err(|err| err.to_string())?;
    Ok(found.map(|update| (update.version.clone(), update.body.clone())))
}

/// Runs a check and stores what it found.
///
/// `manual` is the difference between somebody clicking Check now and the
/// six-hourly look. A click deserves an answer either way — "you are up to
/// date", or why the check failed. The background one stays quiet about both:
/// a character in the notch has no business announcing that GitHub was briefly
/// unreachable.
pub async fn check_now(app: AppHandle, manual: bool) {
    let before = state(&app);
    // Never interrupt a download, or undo an install that is waiting for its
    // restart, by overwriting the state from underneath it.
    if matches!(before.phase, Phase::Downloading | Phase::Ready) {
        return;
    }
    set(&app, UpdateState { phase: Phase::Checking, ..before });

    match look(&app).await {
        Ok(Some((version, notes))) => {
            log::line(format!("update {version} available"));
            set(
                &app,
                UpdateState {
                    phase: Phase::Available,
                    version: Some(version),
                    notes,
                    ..UpdateState::default()
                },
            );
        }
        Ok(None) => set(
            &app,
            UpdateState {
                phase: if manual { Phase::UpToDate } else { Phase::Idle },
                ..UpdateState::default()
            },
        ),
        Err(err) if manual => fail(&app, err),
        Err(err) => {
            log::line(format!("update check: {err}"));
            set(&app, UpdateState::default());
        }
    }
}

/// Downloads the package and hands over to it.
///
/// It looks again rather than keeping the `Update` from the last check: the
/// settings window may have been open for hours, and the manifest worth
/// installing is the one that is current now.
pub async fn install(app: AppHandle) {
    let before = state(&app);
    // Already installed and waiting: finishing it means restarting, which is
    // what the button says by then ("Restart now").
    if before.phase == Phase::Ready {
        app.restart();
    }
    if !before.installable || before.phase == Phase::Downloading {
        return;
    }
    set(&app, UpdateState { phase: Phase::Downloading, progress: 0.0, ..before });

    let updater = match app.updater() {
        Ok(updater) => updater,
        Err(err) => return fail(&app, err.to_string()),
    };
    let update = match updater.check().await {
        Ok(Some(update)) => update,
        // It went away between the check and the click — a release pulled, or
        // a manifest rolled back. Nothing to install, and nothing is wrong.
        Ok(None) => {
            return set(&app, UpdateState { phase: Phase::UpToDate, ..UpdateState::default() })
        }
        Err(err) => return fail(&app, err.to_string()),
    };

    let version = update.version.clone();
    let notes = update.body.clone();
    let mut downloaded = 0usize;
    let ticker = app.clone();
    let result = update
        .download_and_install(
            move |chunk, total| {
                downloaded += chunk;
                // No Content-Length means no honest percentage; the window
                // shows an indeterminate bar rather than a made-up number.
                let fraction = total
                    .filter(|total| *total > 0)
                    .map(|total| (downloaded as f64 / total as f64).clamp(0.0, 1.0))
                    .unwrap_or(0.0);
                progress(&ticker, fraction);
            },
            || {},
        )
        .await;

    match result {
        Ok(()) => {
            log::line(format!("update {version} installed, restarting"));
            set(
                &app,
                UpdateState {
                    phase: Phase::Ready,
                    version: Some(version),
                    notes,
                    progress: 1.0,
                    ..UpdateState::default()
                },
            );
            // Windows rarely reaches this line: the NSIS installer closes this
            // process and starts the new one itself. An AppImage has the new
            // bytes on disk by now and only a restart picks them up.
            app.restart();
        }
        Err(err) => fail(&app, err.to_string()),
    }
}

/// The tray row. An installable build starts the download and opens the window
/// so the progress has somewhere to show; everything else gets the page.
pub fn from_tray(app: &AppHandle) {
    let current = state(app);
    match current.phase {
        Phase::Ready => app.restart(),
        _ if current.installable => {
            crate::show_settings_window(app);
            let handle = app.clone();
            tauri::async_runtime::spawn(async move { install(handle).await });
        }
        _ => crate::platform::open_url(current.release_url),
    }
}

/// Whether the six-hourly check is wanted. Missing state means no: a network
/// call nobody asked for is the wrong thing to default to.
fn wanted(app: &AppHandle) -> bool {
    app.try_state::<crate::Shared>()
        .map(|shared| shared.settings.lock().unwrap().auto_update)
        .unwrap_or(false)
}

pub fn start(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(FIRST_CHECK).await;
        loop {
            // Off means off: no polling, no sound, and nothing asked of GitHub
            // either. The Settings switch is a second, narrower no, for people
            // who want Coucou running and the checks gone.
            if crate::is_enabled(&app) && wanted(&app) {
                check_now(app.clone(), false).await;
            }
            tokio::time::sleep(EVERY).await;
        }
    });
}
