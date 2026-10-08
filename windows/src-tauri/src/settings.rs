// Preferences, stored as plain JSON in settings.json under platform::config_dir().
// No secret ever lands here — API keys live in the OS keychain (see secrets.rs).

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    /// The master switch. False means Coucou is off: no island, no pollers, no
    /// sound, and the hook relay answers at once so Claude Code never waits.
    ///
    /// Defaulted explicitly, like `model` below. A bare `#[serde(default)]`
    /// gives `false` for a bool, which would switch the app off for everyone
    /// whose settings.json predates this field.
    #[serde(default = "default_enabled")]
    pub enabled: bool,
    pub sound_enabled: bool,
    pub sound_volume: f64,
    /// Seconds a notification holds the island open before folding away.
    /// Counted from the end of the open animation, so it is readable throughout.
    pub auto_close_interval: f64,
    pub absence_interval: f64,
    pub active_integrations: Vec<String>,
    /// "primary" = the main display, "cursor" = whichever display the mouse is on.
    pub screen: String,
    /// Where on that display the island sits: "top-left", "top-centre",
    /// "top-right", "bottom-left", "bottom-centre" or "bottom-right".
    ///
    /// Defaulted explicitly, like `enabled` and `model`: a settings.json written
    /// before this field existed must still load, and it must land on the same
    /// bottom-right corner a fresh install gets.
    #[serde(default = "default_position")]
    pub position: String,
    pub autostart: bool,
    pub hooks_installed: bool,
    /// Claude model used by the chat. Changeable in the settings window.
    /// Defaulted explicitly so a settings.json written by an older build still loads.
    #[serde(default = "default_model")]
    pub model: String,
}

fn default_enabled() -> bool {
    true
}

/// Seconds a notification stays open. Was 15 while the same number also governed
/// how long the island lingered after the mouse left; now the island follows the
/// pointer and this only has to be long enough to read a notification.
pub const DEFAULT_AUTO_CLOSE: f64 = 5.0;

/// The two values this field has defaulted to before it meant "how long a
/// notification stays up". Nobody chose them, so they are not worth keeping, and
/// leaving a 15 s notification in place would read as the bug this replaced.
const SUPERSEDED_AUTO_CLOSE: [f64; 2] = [15.0, 60.0];

fn default_position() -> String {
    "bottom-right".to_string()
}

fn default_model() -> String {
    crate::claude::DEFAULT_MODEL.to_string()
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            enabled: true,
            sound_enabled: true,
            sound_volume: 0.12,
            auto_close_interval: DEFAULT_AUTO_CLOSE,
            absence_interval: 180.0,
            active_integrations: vec![
                "integration_resend".into(),
                "integration_n8n".into(),
                "integration_vercel".into(),
                "integration_github".into(),
            ],
            screen: "primary".into(),
            position: default_position(),
            autostart: false,
            hooks_installed: false,
            model: default_model(),
        }
    }
}

pub use crate::platform::{config_dir, local_dir};

pub fn hook_exe_path() -> PathBuf {
    local_dir().join("bin").join(crate::platform::HOOK_EXE)
}

fn settings_path() -> PathBuf {
    config_dir().join("settings.json")
}

pub fn load() -> Settings {
    let mut settings = match std::fs::read(settings_path()) {
        Ok(bytes) => serde_json::from_slice(&bytes).unwrap_or_default(),
        Err(_) => Settings::default(),
    };
    if SUPERSEDED_AUTO_CLOSE.contains(&settings.auto_close_interval) {
        settings.auto_close_interval = DEFAULT_AUTO_CLOSE;
    }
    settings
}

pub fn save(settings: &Settings) -> std::io::Result<()> {
    let dir = config_dir();
    crate::platform::ensure_private_dir(&dir)?;
    let json = serde_json::to_vec_pretty(settings)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    std::fs::write(settings_path(), json)
}
