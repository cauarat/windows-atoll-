// Preferences, stored as plain JSON in settings.json under platform::config_dir().
// No secret ever lands here — API keys live in the OS keychain (see secrets.rs).

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

/// One button on the island's border. `action` is a pill id or the id of a
/// built-in — both opaque here, and resolved by the island.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EdgeButton {
    pub action: String,
    /// "left", "right" or "bottom".
    pub side: String,
}

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
    /// Seconds the compact island waits, with nothing happening, before it folds
    /// away. The other end of `always_visible`: with that on nothing folds and
    /// this is never read, which is why the two sit together in the settings
    /// window.
    ///
    /// Carried here since the first build and read by nobody until now — the
    /// fold was a hard-coded minute in the state machine, on both platforms, and
    /// the field the Mac's "Hide after" box wrote to went nowhere.
    #[serde(default = "default_absence_interval")]
    pub absence_interval: f64,
    /// Standby: once the island has folded away, leave it folded until a message
    /// arrives. The wake strip stops taking the mouse, so nothing but a message
    /// brings Mochi back.
    ///
    /// A bare `#[serde(default)]` is right here, unlike `enabled` above: `false`
    /// is the wanted default, so a settings.json written before this field
    /// existed loads unchanged and keeps waking on hover.
    #[serde(default)]
    pub standby: bool,
    /// Always visible: the island never folds away. Once it has nothing left to
    /// say it rests as the compact bar in its corner instead of retracting into
    /// the screen edge, so Mochi is where it was left rather than somewhere to
    /// be found again. The opposite end of `standby`, and the settings window
    /// puts one out when the other goes on.
    ///
    /// Defaulted explicitly to `true`, like `enabled` above: a bare
    /// `#[serde(default)]` gives `false`, which would quietly leave everyone
    /// who already has a settings.json on the old one-minute fold.
    #[serde(default = "default_always_visible")]
    pub always_visible: bool,
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
    /// What the Home tab shows: "automatic", "ato", "mattermost",
    /// "timer" or "claudeCode". Defaulted explicitly, like the fields above, so
    /// a settings.json written before it existed still loads.
    #[serde(default = "default_home_content")]
    pub home_content: String,
    /// Which language every string is shown in: "system", "en", "es" or
    /// "pt-BR". The same key and the same spellings as the Mac preference --
    /// see NotchBuddy/Sources/App/AppLanguage.swift. "system" asks the OS.
    #[serde(default = "default_language")]
    pub language: String,
    /// Which character each pill wears, keyed by pill id, and the one everything
    /// else gets. Stored as `"accessory:eye"`, with `-` for absent — Rust never
    /// draws a Mochi, so it only has to carry these from one side to the other
    /// and a flat string keeps it that way.
    ///
    /// Defaulted explicitly, like the fields above, so a settings.json written
    /// before they existed still loads.
    #[serde(default)]
    pub pill_characters: HashMap<String, String>,
    #[serde(default = "default_character")]
    pub default_character: String,
    /// Whether the characters are drawn at all.
    ///
    /// Not the master switch: everything the island does it goes on doing, and
    /// only the faces go. Rust carries it across like the two above — the gate
    /// itself lives in the front end, which is the only side that draws.
    #[serde(default)]
    pub hide_characters: bool,
    /// How far the player's two round buttons jump, in seconds. Carried across
    /// like `hide_characters` above — only the front end draws them.
    ///
    /// Defaulted explicitly and not with a bare `#[serde(default)]`, which
    /// would give 0 for a number and hand everyone whose settings.json
    /// predates these fields two buttons that go nowhere.
    #[serde(default = "default_skip_seconds")]
    pub skip_back_seconds: u32,
    #[serde(default = "default_skip_seconds")]
    pub skip_forward_seconds: u32,
    /// What a second click on a message pill opens: "website", or the path to
    /// an application. One click opens the island either way. A path here,
    /// where macOS stores a bundle identifier — the same setting in each
    /// platform's own way of naming an app.
    #[serde(default = "default_open_target")]
    pub mattermost_open_target: String,
    #[serde(default = "default_open_target")]
    pub ato_open_target: String,
    #[serde(default = "default_open_target")]
    pub whatsapp_open_target: String,
    pub autostart: bool,
    pub hooks_installed: bool,
    /// Claude model used by the chat. Changeable in the settings window.
    /// Defaulted explicitly so a settings.json written by an older build still loads.
    #[serde(default = "default_model")]
    pub model: String,
    /// Which buttons hang off the island's border, and on which side.
    ///
    /// `None` means "not chosen yet" and is filled from the active pills on
    /// first use, so an install that predates the ring arrives with a sensible
    /// one instead of an empty border.
    #[serde(default)]
    pub island_edge_buttons: Option<Vec<EdgeButton>>,
    /// The page the globe on the island opens, in a window of its own.
    ///
    /// Defaulted explicitly, like the fields above, so a settings.json written
    /// before it existed still loads.
    #[serde(default = "default_site_url")]
    pub site_url: String,
    /// Whether the chat tab opens ChatGPT's website instead of the built-in
    /// chat. Off by default, exactly as `useWebChat` is on the Mac.
    #[serde(default)]
    pub web_chat: bool,
    /// Whether the message card grows to hold the whole message instead of
    /// clamping it to two lines. Off by default, exactly as `messageFullBody`
    /// is on the Mac. Rust only carries it: the front end does the measuring.
    #[serde(default)]
    pub message_full_body: bool,
    /// Snow on the island's floor, from 15 November to 6 January.
    ///
    /// Defaulted explicitly to `true`, like `always_visible`: a bare
    /// `#[serde(default)]` gives `false`, and everyone who already has a
    /// settings.json would get a season they had to go and find. Rust only
    /// carries it — the front end draws the snow and keeps the dates.
    #[serde(default = "default_island_snow")]
    pub island_snow: bool,
    /// Christmas music as the greeting plays, from 15 November to 6 January.
    ///
    /// Defaulted to `true` for the same reason the snow is. Only the start
    /// with the greeting hangs on it: the Christmas album on the player plays
    /// the music whenever it is clicked. Rust only carries it.
    #[serde(default = "default_christmas_music")]
    pub christmas_music: bool,
    /// The Agenda tab: today's meetings from Actuar's commercial panel, and a
    /// heads-up before each. Off by default — it is an Actuar tool, and most
    /// people have no panel to read. Rust only carries these four; the island
    /// keeps the clock.
    #[serde(default)]
    pub agenda_enabled: bool,
    /// Minutes before a meeting to open the island: 5, 10, 15, 30 or 60.
    #[serde(default = "default_agenda_lead_minutes")]
    pub agenda_lead_minutes: u32,
    /// Which processes give a heads-up. Both are always listed.
    #[serde(default = "default_true")]
    pub agenda_notify_onboarding: bool,
    #[serde(default = "default_true")]
    pub agenda_notify_backoffice: bool,
    /// Whether Coucou looks for a new release on its own, every six hours.
    ///
    /// On by default: an app nobody can tell is out of date is an app that
    /// never gets fixed. Off, the only check that ever happens is the one you
    /// click in Settings, and Coucou reaches no service you did not configure.
    #[serde(default = "default_auto_update")]
    pub auto_update: bool,
    /// Whether a global shortcut closes the island, whichever app has the
    /// keyboard. Off by default, as the Mac's is: a registered shortcut takes
    /// its keys away from every other app, so nobody gets one unasked.
    #[serde(default)]
    pub close_shortcut_enabled: bool,
    /// That shortcut, in the form the global-shortcut plugin parses —
    /// "Ctrl+Alt+X". Recorded by the settings window (core/shortcut.ts).
    #[serde(default = "default_close_shortcut")]
    pub close_shortcut: String,
}

/// The Mac's ⌃⌥X, in the keys a PC has.
pub fn default_close_shortcut() -> String {
    "Ctrl+Alt+X".into()
}

fn default_auto_update() -> bool {
    true
}

/// On. A Mochi that folds itself away after a minute is one you have to go and
/// wake every time you want it, and the corner it rests in is its own.
fn default_always_visible() -> bool {
    true
}

fn default_island_snow() -> bool {
    true
}

fn default_christmas_music() -> bool {
    true
}

fn default_agenda_lead_minutes() -> u32 {
    15
}

fn default_true() -> bool {
    true
}

/// Three minutes, which is what the Mac's settings window has been promising all
/// along while the fold ran on a hard-coded minute underneath it.
fn default_absence_interval() -> f64 {
    180.0
}

fn default_enabled() -> bool {
    true
}

/// Ten seconds each way, which is what the video players everyone already
/// uses default to.
fn default_skip_seconds() -> u32 {
    10
}

/// The web page, which is what every service has. An app is opt-in, because
/// only some of them are one and the path differs per machine.
fn default_open_target() -> String {
    "website".to_string()
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

/// Every pill that can be switched on — `PillCatalog.available` minus the one
/// that loads whether or not it was chosen.
///
/// Here rather than only in the island because `load()` filters what it reads
/// against it: seven pills were deleted when the Mac was cut down to what it is
/// used for, and anyone upgrading has their ids in settings.json.
/// The pill that loads whether or not it was switched on, because the hook
/// relay needs somewhere to put a session that just arrived — it is a pill like
/// any other to the ring, and it is never in `active_integrations`.
pub const ALWAYS_LOADED_PILL: &str = "integration_claude";

pub const KNOWN_PILLS: [&str; 5] = [
    "integration_notifications",
    "integration_mattermost",
    "integration_ato",
    "integration_music",
    "integration_whatsapp",
];

/// The four a fresh install switches on. WhatsApp is not among them: it is
/// switched on by connecting it, and there are only four slots.
const DEFAULT_PILLS: [&str; 4] = [
    "integration_notifications",
    "integration_mattermost",
    "integration_ato",
    "integration_music",
];

/// What a fresh install starts with, and what an upgrade whose every pill was
/// deleted falls back to — `AppState.defaultActiveIntegrations`.
fn default_active_integrations() -> Vec<String> {
    DEFAULT_PILLS.iter().map(|id| (*id).to_string()).collect()
}

/// The two messaging integrations taking turns.
fn default_home_content() -> String {
    "automatic".to_string()
}

/// Follow whatever the operating system was asked for.
fn default_language() -> String {
    "system".to_string()
}

/// Classic Mochi: nothing on its head, nothing special about its eyes.
fn default_character() -> String {
    "-:-".to_string()
}

/// The same page `NotchSite.url` opens on the Mac.
fn default_site_url() -> String {
    "https://caus-macbook-pro.tail8e18f9.ts.net/".to_string()
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
            standby: false,
            always_visible: true,
            active_integrations: default_active_integrations(),
            screen: "primary".into(),
            position: default_position(),
            home_content: default_home_content(),
            language: default_language(),
            pill_characters: HashMap::new(),
            default_character: default_character(),
            hide_characters: false,
            skip_back_seconds: default_skip_seconds(),
            skip_forward_seconds: default_skip_seconds(),
            mattermost_open_target: default_open_target(),
            ato_open_target: default_open_target(),
            whatsapp_open_target: default_open_target(),
            // On by default: Coucou is a thing that lives in the tray, and one
            // that is gone after every reboot until someone remembers it is not
            // living there at all. Anyone with a settings.json keeps their choice.
            autostart: true,
            hooks_installed: false,
            model: default_model(),
            island_edge_buttons: None,
            site_url: default_site_url(),
            web_chat: false,
            message_full_body: false,
            island_snow: true,
            christmas_music: true,
            agenda_enabled: false,
            agenda_lead_minutes: default_agenda_lead_minutes(),
            agenda_notify_onboarding: true,
            agenda_notify_backoffice: true,
            auto_update: true,
            close_shortcut_enabled: false,
            close_shortcut: default_close_shortcut(),
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
    // Deleting catalog entries is not free for anyone who already has the app.
    // Every id someone had could have just been deleted, and an empty list
    // persisted over their choices would leave an island with no pills at all —
    // so empty after the filter means "seed the survivors" rather than "none".
    // ClickMassa is gone and Ato took its conversations: whoever had its pill
    // on gets Ato's in the same slot, rather than a slot that silently empties.
    // The same for a Home pinned to it.
    for id in settings.active_integrations.iter_mut() {
        if id == "integration_clickmassa" {
            *id = "integration_ato".to_string();
        }
    }
    if settings.home_content == "clickmassa" {
        settings.home_content = "ato".to_string();
    }
    settings
        .active_integrations
        .retain(|id| KNOWN_PILLS.contains(&id.as_str()));
    if settings.active_integrations.is_empty() {
        settings.active_integrations = default_active_integrations();
    }
    // The ring was never filtered at all on the Mac when the seven pills went,
    // and a deleted pill left a grey button labelled with its raw id that did
    // nothing when clicked. A built-in is not a pill, so it is kept whatever
    // the catalog says.
    if let Some(buttons) = settings.island_edge_buttons.as_mut() {
        buttons.retain(|b| {
            !b.action.starts_with("integration_")
                || b.action == ALWAYS_LOADED_PILL
                || KNOWN_PILLS.contains(&b.action.as_str())
        });
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
