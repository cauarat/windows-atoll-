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
    /// Retired. The Mac has no such thing, the settings window no longer offers
    /// it (docs/parity W-15), and version 1 of `migrate` switched it off for
    /// everyone — nobody could have switched it off again. The field stays so
    /// the front end, which writes the whole object back, and a hand-edited
    /// settings.json still load; the island still honours it.
    ///
    /// A bare `#[serde(default)]` is right here, unlike `enabled` above: `false`
    /// is the wanted default, so a settings.json written before this field
    /// existed loads unchanged and keeps waking on hover.
    #[serde(default)]
    pub standby: bool,
    /// Always visible: the island never folds away. Once it has nothing left to
    /// say it rests as the compact bar in its corner instead of retracting into
    /// the screen edge, so Mochi is where it was left rather than somewhere to
    /// be found again. "Never", beside "Hide after … s without movement", in
    /// Settings › General.
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
    /// What the Home tab shows: "notifications", "automatic", "ato",
    /// "mattermost", "whatsapp", "timer" or "claudeCode" — HomeContent.swift's
    /// cases. Defaulted explicitly, like the fields above, so a settings.json
    /// written before it existed still loads.
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
    /// Dictation: hold a key, speak, let go — or the card's Record button. The
    /// speech model runs in dictation-service/, at `dictation_service_url`.
    /// Off until asked for, as on the Mac.
    #[serde(default)]
    pub dictation_enabled: bool,
    /// Where dictation-service/ listens.
    #[serde(default = "default_dictation_service_url")]
    pub dictation_service_url: String,
    /// The key held to dictate: "rightCtrl", "rightAlt" or "off". The Mac holds
    /// fn, which on a PC the keyboard keeps to itself; a lone Alt opens the
    /// focused app's menu bar, so the right Ctrl is the default.
    #[serde(default = "default_dictation_hold_key")]
    pub dictation_hold_key: String,
    /// "paste" where the cursor is, or "copy" to the clipboard only.
    #[serde(default = "default_dictation_insert")]
    pub dictation_insert: String,
    /// What Mochi calls the user, in the launch greeting and in the chat: the
    /// name typed in the welcome or under Settings › General, trimmed. Empty
    /// means the account's own first name, when it has one worth greeting —
    /// the front end decides that (core/greetingName.ts) and hands the chat
    /// the answer, so Rust only carries this.
    ///
    /// A bare `#[serde(default)]` is right: empty is the wanted default, and
    /// without one every settings.json written before this field existed would
    /// fail to parse and `load()` would reset all of it.
    #[serde(default)]
    pub user_name: String,
    /// Which welcome this install has been through: `ONBOARDING_VERSION` once
    /// it has been finished, skipped or closed, 0 before. A bare
    /// `#[serde(default)]` on purpose — everyone whose settings.json predates
    /// it comes in at 0, and so sees the welcome once.
    #[serde(default)]
    pub onboarding_version: u32,
    /// Which of `migrate`'s steps this settings.json has been through:
    /// `SETTINGS_VERSION` once it is current. Rust's alone — `save_settings`
    /// keeps this value whatever a page sends back, since a page that booted
    /// before a migration would otherwise undo it.
    ///
    /// A bare `#[serde(default)]` on purpose, as for `onboarding_version`: a
    /// settings.json from before this field reads as version 0 and is brought
    /// up to date once, while `Settings::default()` starts current.
    #[serde(default)]
    pub settings_version: u32,
}

/// What a finished welcome is stamped with, in `onboarding_version`.
///
/// Must match `OnboardingGate.version` in NotchBuddy/Sources/App/Onboarding.swift
/// and `ONBOARDING_VERSION` in windows/src/core/onboarding.ts. Raise all three
/// together when the welcome gains a screen everybody should see: whoever
/// finished an older one is shown the new one, once.
pub const ONBOARDING_VERSION: u32 = 1;

impl Settings {
    /// Whether the welcome is still owed — the twin of `shouldShowOnboarding`
    /// in core/onboarding.ts, which the settings window asks to decide whether
    /// it opens on the welcome. Not while Notchy is off: the welcome ends by
    /// opening the island, and an island that is off cannot.
    pub fn onboarding_pending(&self) -> bool {
        self.enabled && self.onboarding_version < ONBOARDING_VERSION
    }
}

/// The Mac's ⌃⌥X, in the keys a PC has.
pub fn default_close_shortcut() -> String {
    "Ctrl+Alt+X".into()
}

fn default_dictation_service_url() -> String {
    "http://127.0.0.1:8765".into()
}

fn default_dictation_hold_key() -> String {
    "rightCtrl".into()
}

fn default_dictation_insert() -> String {
    "paste".into()
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

/// A pill this build offers — `PillCatalog.available`: a known one, and Now
/// Playing only where what is playing can be read (`media::AVAILABLE`).
fn pill_available(id: &str) -> bool {
    KNOWN_PILLS.contains(&id) && (crate::media::AVAILABLE || id != crate::media::MUSIC_PILL)
}

/// Every message service as one queue — `HomeContent.defaultChoice` on the Mac.
fn default_home_content() -> String {
    "notifications".to_string()
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
            // Off, as the Mac's "Launch at Mac startup" is on a fresh install:
            // starting with the system is something to ask for, not something
            // to find out about. Only a fresh install starts here. A settings.json
            // keeps its choice, and an install without one keeps whatever the
            // OS already has registered (`autostart_at_launch`), so an older
            // build's registration is never undone by the new default.
            autostart: false,
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
            dictation_enabled: false,
            dictation_service_url: default_dictation_service_url(),
            dictation_hold_key: default_dictation_hold_key(),
            dictation_insert: default_dictation_insert(),
            user_name: String::new(),
            onboarding_version: 0,
            settings_version: SETTINGS_VERSION,
        }
    }
}

/// The built-ins that were tabs in the island's header and now hang off its
/// inner edge — `MOVED_FROM_HEADER` in edgeRing.ts.
const MOVED_FROM_HEADER: [&str; 2] = ["hydration", "agenda"];

/// What a current settings.json is stamped with in `settings_version`, and what
/// `migrate` brings an older one up to. Raise it with each step added there.
pub const SETTINGS_VERSION: u32 = 2;

/// Brings settings written by an older build up to `SETTINGS_VERSION`, one step
/// at a time, stamping the version as it goes — so each step runs once per
/// install, and running this again finds nothing to do.
///
/// Returns the line to log when a step ran, None when there was nothing to do.
///
/// Only for what has to *change*: a field that is merely new needs a
/// `#[serde(default)]`, not a step here.
pub fn migrate(settings: &mut Settings) -> Option<String> {
    let from = settings.settings_version;
    if from >= SETTINGS_VERSION {
        return None;
    }
    let mut changes = Vec::new();
    if settings.settings_version < 1 {
        // 1 — Settings redrawn as the Mac's (docs/parity, phase 1).
        //
        // Standby left the window, so whoever had it on could not turn it off
        // again.
        if settings.standby {
            settings.standby = false;
            changes.push("standby off");
        }
        // Home's default became Notifications, the Mac's. "automatic" was the
        // old default, and having chosen it cannot be told apart from never
        // having been asked — so it moves with the default.
        if settings.home_content == "automatic" {
            settings.home_content = "notifications".to_string();
            changes.push("Home: automatic → notifications");
        }
        settings.settings_version = 1;
    }
    if settings.settings_version < 2 {
        // 2 — Water and the calendar left the header for the ring, as on the
        // Mac. A ring somebody already arranged gets whichever it lacks in the
        // row, the way a fresh one is dealt them (`edgeRing.ts`'s
        // `addingMoved`); a ring never arranged is dealt them already.
        if let Some(buttons) = settings.island_edge_buttons.as_mut() {
            for action in MOVED_FROM_HEADER {
                if !buttons.iter().any(|b| b.action == action) {
                    buttons.push(EdgeButton { action: action.to_string(), side: "bottom".to_string() });
                    changes.push(if action == "hydration" { "ring: + hydration" } else { "ring: + agenda" });
                }
            }
        }
        settings.settings_version = 2;
    }
    let to = settings.settings_version;
    Some(if changes.is_empty() {
        format!("settings.json v{from} → v{to}: nothing to change")
    } else {
        format!("settings.json v{from} → v{to}: {}", changes.join(", "))
    })
}

/// Whether Notchy should launch at startup, decided once at launch from what
/// settings.json says and what the OS has registered.
///
/// `stored` is None when there was no settings.json to read — a first run, or
/// a file that no longer parses. The OS is the answer then: nothing registered
/// on a fresh install, so it starts off as the Mac does; and the registration
/// an older build made, whose default was on, is kept rather than undone by a
/// default nobody chose. Otherwise the stored choice wins, as it always has.
pub fn autostart_at_launch(stored: Option<bool>, registered: bool) -> bool {
    stored.unwrap_or(registered)
}

pub use crate::platform::{config_dir, local_dir};

pub fn hook_exe_path() -> PathBuf {
    local_dir().join("bin").join(crate::platform::HOOK_EXE)
}

fn settings_path() -> PathBuf {
    config_dir().join("settings.json")
}

pub fn load() -> Settings {
    load_from_disk().0
}

/// `load`, and whether the settings came from settings.json: false for a first
/// run and for a file that no longer parses, where the defaults stand in for
/// choices nobody made here (see `autostart_at_launch`).
///
/// A file written by an older build is migrated here, once: the migrated
/// settings are saved straight away and the change is logged.
pub fn load_from_disk() -> (Settings, bool) {
    let parsed = std::fs::read(settings_path())
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Settings>(&bytes).ok());
    let from_file = parsed.is_some();
    let mut settings = parsed.unwrap_or_default();
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
    // `AppState.loadIntegrationTasks`: only pills this build offers. Now
    // Playing is in the defaults, and on Linux, which cannot play it, it would
    // hold one of the four slots behind a row the page never shows.
    settings.active_integrations.retain(|id| pill_available(id));
    if settings.active_integrations.is_empty() {
        settings.active_integrations = default_active_integrations();
        settings.active_integrations.retain(|id| pill_available(id));
    }
    // The ring was never filtered at all on the Mac when the seven pills went,
    // and a deleted pill left a grey button labelled with its raw id that did
    // nothing when clicked. A built-in is not a pill, so it is kept whatever
    // the catalog says.
    if let Some(buttons) = settings.island_edge_buttons.as_mut() {
        buttons.retain(|b| {
            !b.action.starts_with("integration_")
                || b.action == ALWAYS_LOADED_PILL
                || pill_available(&b.action)
        });
    }
    // Last, so what is written back is the file as it now reads. Saved at
    // once: a step that runs is a step that has run, whatever happens next.
    //
    // Written by the first load of a run only — the one `run()` makes before
    // any other thread exists. A later load (the tray's language, a pill's
    // second click) still reads the file migrated, but never writes it: one
    // racing a save from the settings window must not put back what that save
    // just changed, and a write that failed once is not logged on every read.
    if from_file {
        if let Some(line) = migrate(&mut settings) {
            if !MIGRATION_WRITTEN.swap(true, std::sync::atomic::Ordering::SeqCst) {
                crate::log::line(&line);
                if let Err(err) = save(&settings) {
                    crate::log::line(format!("could not save migrated settings: {err}"));
                }
            }
        }
    }
    (settings, from_file)
}

/// Whether this run has already written a migration back — see `load_from_disk`.
static MIGRATION_WRITTEN: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

pub fn save(settings: &Settings) -> std::io::Result<()> {
    let dir = config_dir();
    crate::platform::ensure_private_dir(&dir)?;
    let json = serde_json::to_vec_pretty(settings)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    std::fs::write(settings_path(), json)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A settings.json written before the welcome existed — no `userName`, no
    /// `onboardingVersion` — keeps every choice in it, and owes the welcome.
    /// A field without its `#[serde(default)]` fails this by resetting
    /// everything to the defaults, which is what `load()` does with a file
    /// that does not parse.
    #[test]
    fn a_settings_file_from_before_the_welcome_still_loads() {
        let mut old = serde_json::to_value(Settings::default()).unwrap();
        let fields = old.as_object_mut().unwrap();
        assert!(fields.remove("userName").is_some());
        assert!(fields.remove("onboardingVersion").is_some());
        fields.insert("soundVolume".into(), serde_json::json!(0.05));
        fields.insert("language".into(), serde_json::json!("pt-BR"));

        let loaded: Settings = serde_json::from_value(old).unwrap();
        assert_eq!(loaded.sound_volume, 0.05);
        assert_eq!(loaded.language, "pt-BR");
        assert_eq!(loaded.user_name, "");
        assert_eq!(loaded.onboarding_version, 0);
        assert!(loaded.onboarding_pending());
    }

    /// A settings.json from before the version existed, as the last build
    /// before Settings looked like the Mac's wrote it.
    fn before_version_1() -> Settings {
        let mut old = serde_json::to_value(Settings::default()).unwrap();
        let fields = old.as_object_mut().unwrap();
        assert!(fields.remove("settingsVersion").is_some());
        fields.insert("standby".into(), serde_json::json!(true));
        fields.insert("alwaysVisible".into(), serde_json::json!(false));
        fields.insert("homeContent".into(), serde_json::json!("automatic"));
        fields.insert("autostart".into(), serde_json::json!(true));
        serde_json::from_value(old).unwrap()
    }

    #[test]
    fn a_settings_file_without_a_version_reads_as_version_0() {
        let old = before_version_1();
        assert_eq!(old.settings_version, 0);
        // And a fresh install is current, so it has nothing to migrate.
        assert_eq!(Settings::default().settings_version, SETTINGS_VERSION);
        assert_eq!(migrate(&mut Settings::default()), None);
    }

    #[test]
    fn version_1_turns_standby_off_and_moves_home_to_notifications() {
        let mut s = before_version_1();
        let line = migrate(&mut s).expect("an old file is migrated");
        assert!(!s.standby);
        assert_eq!(s.home_content, "notifications");
        assert_eq!(s.settings_version, SETTINGS_VERSION);
        // Logged, with what changed.
        assert!(line.contains("v0 → v2"), "{line}");
        assert!(line.contains("standby off"), "{line}");
        assert!(line.contains("automatic → notifications"), "{line}");
        // Nothing else moves: not the choices beside it, not autostart.
        assert!(!s.always_visible);
        assert!(s.autostart);
    }

    #[test]
    fn a_migration_runs_once() {
        let mut s = before_version_1();
        assert!(migrate(&mut s).is_some());
        let once = serde_json::to_value(&s).unwrap();
        // The page picks automatic again, on purpose this time; the next
        // launch must not take it away.
        s.home_content = "automatic".to_string();
        s.standby = true;
        assert_eq!(migrate(&mut s), None);
        assert_eq!(s.home_content, "automatic");
        assert!(s.standby);
        s.home_content = "notifications".to_string();
        s.standby = false;
        assert_eq!(serde_json::to_value(&s).unwrap(), once);
    }

    #[test]
    fn version_1_keeps_a_home_somebody_pinned() {
        let mut s = before_version_1();
        s.home_content = "ato".to_string();
        s.standby = false;
        let line = migrate(&mut s).expect("still stamped");
        assert_eq!(s.home_content, "ato");
        assert_eq!(s.settings_version, SETTINGS_VERSION);
        assert!(line.contains("nothing to change"), "{line}");
    }

    #[test]
    fn version_2_hangs_water_and_the_calendar_on_an_arranged_ring() {
        let button = |action: &str, side: &str| EdgeButton { action: action.into(), side: side.into() };
        let mut s = Settings::default();
        s.settings_version = 1;
        s.island_edge_buttons = Some(vec![button("clipboard", "left"), button("agenda", "right")]);
        let line = migrate(&mut s).expect("a v1 file is migrated");
        let ring: Vec<(String, String)> = s.island_edge_buttons.unwrap()
            .into_iter().map(|b| (b.action, b.side)).collect();
        // Only what was missing, in the row; the calendar stays where it was put.
        assert_eq!(ring, vec![
            ("clipboard".into(), "left".into()),
            ("agenda".into(), "right".into()),
            ("hydration".into(), "bottom".into()),
        ]);
        assert!(line.contains("ring: + hydration"), "{line}");
        assert!(!line.contains("ring: + agenda"), "{line}");

        // A ring never arranged stays unarranged: the defaults deal them.
        let mut fresh = Settings::default();
        fresh.settings_version = 1;
        fresh.island_edge_buttons = None;
        migrate(&mut fresh);
        assert!(fresh.island_edge_buttons.is_none());
    }

    #[test]
    fn a_file_from_a_newer_build_is_left_alone() {
        let mut s = Settings::default();
        s.settings_version = SETTINGS_VERSION + 1;
        s.standby = true;
        assert_eq!(migrate(&mut s), None);
        assert!(s.standby);
        assert_eq!(s.settings_version, SETTINGS_VERSION + 1);
    }

    #[test]
    fn launch_at_startup_starts_off_but_never_undoes_a_registration() {
        // A fresh install: no settings.json, nothing registered.
        assert!(!autostart_at_launch(None, false));
        // No settings.json, but an older build (default on) registered it.
        assert!(autostart_at_launch(None, true));
        // A settings.json always wins, either way.
        assert!(autostart_at_launch(Some(true), false));
        assert!(!autostart_at_launch(Some(false), true));
    }

    #[test]
    fn the_welcome_is_owed_once_and_never_while_off() {
        let mut s = Settings::default();
        assert!(s.onboarding_pending());
        s.enabled = false;
        assert!(!s.onboarding_pending());
        s.enabled = true;
        s.onboarding_version = ONBOARDING_VERSION;
        assert!(!s.onboarding_pending());
    }
}

// Held to tests/fixtures/settings-defaults.json, with the Mac and the front end.
// `#[path]` because a child of settings.rs would be looked for in src/settings/.
#[cfg(test)]
#[path = "settings_defaults_test.rs"]
mod defaults_test;
