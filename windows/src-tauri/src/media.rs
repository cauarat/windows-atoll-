// Now Playing — the Windows side of MusicController / NowPlayingController.
//
// The Mac reads MediaRemote through a vendored adapter; Windows has the same
// idea in the box as GSMTC (GlobalSystemMediaTransportControls), the thing that
// draws the volume-key flyout. Both answer the same question — whatever is
// playing, whoever is playing it — so the island gets the same card from both.
//
// Nothing runs until the Now Playing pill is on, the way the Mac only starts its
// reader from `activeIntegrations`. Nothing leaves the machine: GSMTC is a local
// API and the artwork is the one the player already handed the system.
//
// Linux has no GSMTC. The equivalent is MPRIS over D-Bus, which would mean a new
// dependency, so for now Linux reports nothing and the card shows its empty
// state — see `backend` at the bottom of this file.

use std::time::Duration;

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};

use crate::island::WINDOW_LABEL;

/// How often the session is asked. A second is what the clock needs; the island
/// extrapolates between samples the way `PlaybackState.estimatedTime` does, so
/// this is not the frame rate of the scrubber.
const EVERY: Duration = Duration::from_millis(1000);

/// The pill this belongs to — a contract value, like every other pill id.
pub const MUSIC_PILL: &str = "integration_music";

/// What the island receives.
///
/// `elapsed` is where playback had got to when it was sampled, not now. The
/// island advances it against its own clock while `isPlaying`, which is why one
/// second between samples is enough.
#[derive(Serialize, Clone, Default, PartialEq, Debug)]
#[serde(rename_all = "camelCase")]
pub struct MediaState {
    pub has_track: bool,
    pub is_playing: bool,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub elapsed: f64,
    pub duration: f64,
    /// The application it is coming from, in words.
    pub source_name: String,
    /// Its raw id, kept so the island can tell two sources apart without
    /// matching on a display name that is localised.
    pub source_id: String,
    /// A complete `data:` URL, or empty when the player sent no art.
    pub artwork: String,
}

impl MediaState {
    /// Everything except where it has got to.
    ///
    /// A new sample every second must not mean an event every second: the title
    /// and the artwork are unchanged all song, and the artwork is tens of
    /// kilobytes. Only a real change is worth waking the island for.
    fn same_track_as(&self, other: &Self) -> bool {
        self.has_track == other.has_track
            && self.is_playing == other.is_playing
            && self.title == other.title
            && self.artist == other.artist
            && self.album == other.album
            && self.source_id == other.source_id
            && (self.duration - other.duration).abs() < 0.5
            && self.artwork == other.artwork
    }
}

fn emit(app: &AppHandle, state: &MediaState) {
    let _ = app.emit_to(WINDOW_LABEL, "media", state.clone());
}

/// True when the user has the Now Playing pill on and the app is not paused.
///
/// The same question `messages::pill_enabled` asks, and for the same reason: a
/// pill that is off reads nothing at all.
fn enabled(app: &AppHandle) -> bool {
    app.try_state::<crate::Shared>()
        .map(|shared| {
            let settings = shared.settings.lock().unwrap();
            settings.enabled && settings.active_integrations.iter().any(|x| x == MUSIC_PILL)
        })
        .unwrap_or(false)
}

/// Polls the session on a thread of its own.
///
/// A plain thread rather than a tokio task: every GSMTC call blocks on a COM
/// apartment, which is not something to do on the async runtime the message
/// sockets share.
pub fn start(app: AppHandle) {
    let started = std::thread::Builder::new().name("media-poll".into()).spawn(move || {
        backend::init_thread();

        let mut last = MediaState::default();
        let mut was_enabled = false;
        let mut sampled_at = std::time::Instant::now();

        loop {
            std::thread::sleep(EVERY);

            if !enabled(&app) {
                // Switched off while something was up: clear the card once,
                // rather than leaving yesterday's song on it forever.
                if was_enabled {
                    was_enabled = false;
                    last = MediaState::default();
                    emit(&app, &last);
                }
                continue;
            }
            was_enabled = true;

            // The previous sample goes in so the thumbnail is only read when the
            // track it belongs to has actually changed.
            let next = backend::read(&last).unwrap_or_default();

            // A position jump is a seek, and the island cannot extrapolate its
            // way to one. Measured against the real gap rather than `EVERY`:
            // the loop is a second of sleep plus however long the session took
            // to answer, and assuming the nominal figure reports a slow machine
            // as seeking.
            let now = std::time::Instant::now();
            let gap = now.duration_since(sampled_at).as_secs_f64();
            sampled_at = now;
            let expected = if last.is_playing {
                last.elapsed + gap
            } else {
                last.elapsed
            };
            let jumped = (next.elapsed - expected).abs() > 1.5;

            if !next.same_track_as(&last) || jumped {
                emit(&app, &next);
            }
            last = next;
        }
    });
    if let Err(err) = started {
        crate::log::line(format!("thread media-poll failed to start — {err}"));
    }
}

/// Play, pause, skip or seek — whatever the session is.
///
/// Off the calling thread, because every one of these blocks on a COM apartment
/// and a transport button must not be able to stall the window while a player
/// takes its time answering. Nothing waits for the result: the next poll is what
/// reports whether it worked, which is the same thing the card would show.
#[tauri::command]
pub fn media_command(app: AppHandle, action: String, position: Option<f64>) {
    if !enabled(&app) {
        return;
    }
    let started = std::thread::Builder::new().name("media-command".into()).spawn(move || {
        backend::init_thread();
        backend::command(&action, position);
    });
    if let Err(err) = started {
        crate::log::line(format!("thread media-command failed to start — {err}"));
    }
}

// MARK: – Windows

#[cfg(windows)]
mod backend {
    use super::MediaState;

    use windows::Media::Control::{
        GlobalSystemMediaTransportControlsSessionManager as Manager,
        GlobalSystemMediaTransportControlsSessionPlaybackStatus as Status,
    };
    use windows::Storage::Streams::DataReader;
    use windows::Win32::System::Com::{CoInitializeEx, COINIT_MULTITHREADED};

    /// A `TimeSpan` counts 100-nanosecond ticks.
    const TICKS_PER_SECOND: f64 = 10_000_000.0;

    pub fn init_thread() {
        // Ignored on purpose: `RPC_E_CHANGED_MODE` means the apartment is
        // already initialised, which is not a failure for us.
        unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
        }
    }

    pub fn read(previous: &MediaState) -> Option<MediaState> {
        match read_inner(previous) {
            Ok(state) => Some(state),
            Err(err) => {
                // Nothing playing is the overwhelmingly common "error" here —
                // `GetCurrentSession` fails outright when there is no session —
                // so this is not worth a log line every second.
                let _ = err;
                None
            }
        }
    }

    fn read_inner(previous: &MediaState) -> windows::core::Result<MediaState> {
        let manager = Manager::RequestAsync()?.get()?;
        let session = manager.GetCurrentSession()?;

        let props = session.TryGetMediaPropertiesAsync()?.get()?;
        let title = props.Title().map(|s| s.to_string()).unwrap_or_default();
        let artist = props.Artist().map(|s| s.to_string()).unwrap_or_default();
        let album = props
            .AlbumTitle()
            .map(|s| s.to_string())
            .unwrap_or_default();

        let timeline = session.GetTimelineProperties()?;
        let elapsed =
            timeline.Position().map(|t| t.Duration).unwrap_or(0) as f64 / TICKS_PER_SECOND;
        let end = timeline.EndTime().map(|t| t.Duration).unwrap_or(0) as f64 / TICKS_PER_SECOND;
        let start = timeline.StartTime().map(|t| t.Duration).unwrap_or(0) as f64 / TICKS_PER_SECOND;

        let playing = session
            .GetPlaybackInfo()
            .and_then(|info| info.PlaybackStatus())
            .map(|status| status == Status::Playing)
            .unwrap_or(false);

        let source_id = session
            .SourceAppUserModelId()
            .map(|s| s.to_string())
            .unwrap_or_default();

        // Artwork is tens of kilobytes and unchanged all song, so reading and
        // base64-encoding it every second would be a megabyte a minute spent to
        // produce the same string. The track's own identity is already known
        // here, which is enough to decide.
        //
        // Only when there is something to keep: a thumbnail that failed to open
        // once — a player that publishes art a moment after the track — would
        // otherwise stay missing for the rest of the song. An empty one is
        // retried, which costs a `Thumbnail()` that returns nothing quickly.
        let keep_artwork = previous.has_track
            && !previous.artwork.is_empty()
            && previous.title == title
            && previous.artist == artist
            && previous.album == album
            && previous.source_id == source_id;

        Ok(MediaState {
            has_track: !title.is_empty() || !artist.is_empty(),
            is_playing: playing,
            artwork: if keep_artwork {
                previous.artwork.clone()
            } else {
                artwork(&props).unwrap_or_default()
            },
            title,
            artist,
            album,
            elapsed: (elapsed - start).max(0.0),
            duration: (end - start).max(0.0),
            source_name: source_name(&source_id),
            source_id,
        })
    }

    /// The thumbnail the player handed the system, as a `data:` URL.
    fn artwork(
        props: &windows::Media::Control::GlobalSystemMediaTransportControlsSessionMediaProperties,
    ) -> Option<String> {
        let reference = props.Thumbnail().ok()?;
        let stream = reference.OpenReadAsync().ok()?.get().ok()?;
        let size = stream.Size().ok()?;
        // Artwork is tens of kilobytes; anything far past that is not artwork,
        // and it would be read into memory and base64'd every time it changed.
        if size == 0 || size > 4 * 1024 * 1024 {
            return None;
        }
        let input = stream.GetInputStreamAt(0).ok()?;
        let reader = DataReader::CreateDataReader(&input).ok()?;
        reader.LoadAsync(size as u32).ok()?.get().ok()?;
        let mut bytes = vec![0u8; size as usize];
        reader.ReadBytes(&mut bytes).ok()?;

        let mime = if bytes.starts_with(&[0x89, b'P', b'N', b'G']) {
            "image/png"
        } else {
            "image/jpeg"
        };
        Some(format!(
            "data:{mime};base64,{}",
            crate::claude::base64_for(&bytes)
        ))
    }

    /// An AUMID turned into something worth showing a person.
    ///
    /// They come in two shapes: a bare executable (`Spotify.exe`), or a packaged
    /// identity (`Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic`).
    /// Neither reads as a name on its own, and the handful below cover almost
    /// everything anyone plays music through.
    fn source_name(aumid: &str) -> String {
        if aumid.is_empty() {
            return String::new();
        }
        let lower = aumid.to_ascii_lowercase();
        for (needle, name) in [
            ("spotify", "Spotify"),
            ("chrome", "Google Chrome"),
            ("msedge", "Microsoft Edge"),
            ("firefox", "Firefox"),
            ("brave", "Brave"),
            ("opera", "Opera"),
            ("zunemusic", "Media Player"),
            ("zunevideo", "Media Player"),
            ("vlc", "VLC"),
            ("itunes", "iTunes"),
            ("applemusic", "Apple Music"),
            ("foobar2000", "foobar2000"),
            ("mpv", "mpv"),
            ("winamp", "Winamp"),
        ] {
            if lower.contains(needle) {
                return name.to_string();
            }
        }

        // Unknown: take the recognisable half. `Family_hash!App` keeps the
        // family, `thing.exe` loses the extension.
        let head = aumid.split('!').next().unwrap_or(aumid);
        let head = head.split('_').next().unwrap_or(head);
        let head = head.rsplit('\\').next().unwrap_or(head);
        let head = head.strip_suffix(".exe").unwrap_or(head);
        let head = head.rsplit('.').next().unwrap_or(head);
        if head.is_empty() {
            aumid.to_string()
        } else {
            head.to_string()
        }
    }

    pub fn command(action: &str, position: Option<f64>) -> bool {
        fn run(action: &str, position: Option<f64>) -> windows::core::Result<bool> {
            let manager = Manager::RequestAsync()?.get()?;
            let session = manager.GetCurrentSession()?;
            let done = match action {
                "play" => session.TryPlayAsync()?.get()?,
                "pause" => session.TryPauseAsync()?.get()?,
                "playpause" => session.TryTogglePlayPauseAsync()?.get()?,
                "next" => session.TrySkipNextAsync()?.get()?,
                "previous" => session.TrySkipPreviousAsync()?.get()?,
                "seek" => {
                    let seconds = position.unwrap_or(0.0).max(0.0);
                    let ticks = (seconds * TICKS_PER_SECOND) as i64;
                    session.TryChangePlaybackPositionAsync(ticks)?.get()?
                }
                _ => false,
            };
            Ok(done)
        }
        run(action, position).unwrap_or(false)
    }

    #[cfg(test)]
    mod tests {
        use super::source_name;

        #[test]
        fn names_the_players_people_use() {
            assert_eq!(source_name("Spotify.exe"), "Spotify");
            assert_eq!(source_name("chrome.exe"), "Google Chrome");
            assert_eq!(
                source_name("Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic"),
                "Media Player"
            );
        }

        #[test]
        fn falls_back_to_the_recognisable_half() {
            assert_eq!(source_name("Something.exe"), "Something");
            assert_eq!(source_name("Acme.Player_9abc!App"), "Player");
            assert_eq!(source_name(""), "");
        }
    }
}

// MARK: – Everywhere else

/// Linux, and anything else the Tauri app is built for.
///
/// GSMTC is Windows-only and the Linux equivalent is MPRIS over D-Bus, which is
/// a dependency this app does not have and CLAUDE.md asks not to take without a
/// reason. Until it does, the card shows what it shows with nothing playing,
/// which is a true answer rather than a broken one.
#[cfg(not(windows))]
mod backend {
    use super::MediaState;

    pub fn init_thread() {}

    pub fn read(_previous: &MediaState) -> Option<MediaState> {
        None
    }

    pub fn command(_action: &str, _position: Option<f64>) -> bool {
        false
    }
}
