// The output volume — the Windows side of `SystemVolume.swift`.
//
// Deliberately the smallest thing that answers the question, as on the Mac. Not
// a mixer: no per-application levels, no picking another output. One number for
// the default output, the one the keyboard's volume keys and the taskbar's
// slider move, so the Now Playing card's slider and those never disagree.
//
// Windows has the same idea as CoreAudio's default output device:
// IMMDeviceEnumerator's default render endpoint, and its IAudioEndpointVolume.
// No endpoint at all — nothing plugged in, the audio service stopped — is the
// honest "no volume", which the card reads as "do not show a slider", exactly as
// the Mac does for an output with no volume of its own.
//
// Linux has no reader yet: PulseAudio or PipeWire would be a new dependency, so
// the card hides the row there.

use serde::Serialize;

/// What the card is told: the level, 0…1, and whether the output is muted.
#[derive(Serialize, Clone, Copy, Debug, PartialEq)]
pub struct Volume {
    pub level: f32,
    pub muted: bool,
}

/// The default output's volume, or `None` when there is none to set.
///
/// Off the calling thread: every call is a COM round trip to the audio
/// service, and a command must not hold the window while it answers.
#[tauri::command]
pub async fn volume_get() -> Option<Volume> {
    off_thread(backend::get).await.flatten()
}

/// Sets the level. Moving the slider off zero also un-mutes, as on the Mac: a
/// slider that moves and changes nothing is worse than no slider.
#[tauri::command]
pub async fn volume_set(level: f32) {
    let level = clamp(level);
    off_thread(move || backend::set_level(level)).await;
}

/// Mutes or un-mutes the default output.
#[tauri::command]
pub async fn volume_set_muted(muted: bool) {
    off_thread(move || backend::set_muted(muted)).await;
}

fn clamp(level: f32) -> f32 {
    if level.is_finite() {
        level.clamp(0.0, 1.0)
    } else {
        0.0
    }
}

async fn off_thread<T: Send + 'static>(f: impl FnOnce() -> T + Send + 'static) -> Option<T> {
    tauri::async_runtime::spawn_blocking(move || {
        backend::init_thread();
        f()
    })
    .await
    .ok()
}

// MARK: – Windows

#[cfg(windows)]
mod backend {
    use super::{clamp, Volume};

    use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
    use windows::Win32::Media::Audio::{eConsole, eRender, IMMDeviceEnumerator, MMDeviceEnumerator};
    use windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CLSCTX_ALL, COINIT_MULTITHREADED};

    pub fn init_thread() {
        // Ignored on purpose, as in media.rs: an apartment that is already
        // initialised is not a failure.
        unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
        }
    }

    /// Asked for afresh every time rather than kept: the default output moves
    /// when headphones go in, and an endpoint kept from before would be the
    /// speakers' volume while the sound comes out of the headphones.
    fn endpoint() -> windows::core::Result<IAudioEndpointVolume> {
        unsafe {
            let enumerator: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
            let device = enumerator.GetDefaultAudioEndpoint(eRender, eConsole)?;
            device.Activate::<IAudioEndpointVolume>(CLSCTX_ALL, None)
        }
    }

    pub fn get() -> Option<Volume> {
        let volume = endpoint().ok()?;
        unsafe {
            let level = volume.GetMasterVolumeLevelScalar().ok()?;
            let muted = volume.GetMute().map(|b| b.as_bool()).unwrap_or(false);
            Some(Volume { level: clamp(level), muted })
        }
    }

    pub fn set_level(level: f32) {
        let Ok(volume) = endpoint() else { return };
        unsafe {
            let _ = volume.SetMasterVolumeLevelScalar(level, std::ptr::null());
            if level > 0.0 {
                let _ = volume.SetMute(false, std::ptr::null());
            }
        }
    }

    pub fn set_muted(muted: bool) {
        let Ok(volume) = endpoint() else { return };
        unsafe {
            let _ = volume.SetMute(muted, std::ptr::null());
        }
    }
}

// MARK: – Elsewhere

#[cfg(not(windows))]
mod backend {
    use super::Volume;

    pub fn init_thread() {}

    pub fn get() -> Option<Volume> {
        None
    }

    pub fn set_level(_level: f32) {}

    pub fn set_muted(_muted: bool) {}
}

#[cfg(test)]
mod tests {
    use super::clamp;

    #[test]
    fn a_level_stays_between_silent_and_full() {
        assert_eq!(clamp(-0.2), 0.0);
        assert_eq!(clamp(0.4), 0.4);
        assert_eq!(clamp(1.7), 1.0);
        assert_eq!(clamp(f32::NAN), 0.0);
    }
}
