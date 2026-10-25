// The master switch the pollers answer to.
//
// This file used to hold seven of them — Stripe, GitHub, Vercel, n8n, Resend,
// Notion, Cal.com — ported one for one from the Swift pollers. The Mac dropped
// all seven ("Cut Coucou down to what it is used for"), and what stands for an
// integration here now is Claude Code, the two message services and the player,
// each of which owns its own connection in its own module.
//
// What is left is the one thing they all shared: a flag every long-running task
// checks before it reaches the network, kept in step with `settings.enabled`.

use std::sync::atomic::{AtomicBool, Ordering};

/// Mirrors the master switch for the message clients and the player, which run
/// off the app handle and check this on every pass.
///
/// It used to be the whole of Pause — set from the tray, never written to disk,
/// so a restart undid it. Now `apply_master` keeps it in step with
/// `settings.enabled`, which is what actually persists.
pub static PAUSED: AtomicBool = AtomicBool::new(false);

pub fn apply_master(enabled: bool) {
    PAUSED.store(!enabled, Ordering::Relaxed);
}
