// Clipboard history: what was copied, kept while the app runs.
//
// The history lives in memory and is never written down. Clipboard contents are
// the most sensitive thing this app could hold — passwords on their way to a
// login box, tokens, private messages — so nothing that merely passed through
// touches the disk. Favourites are the exception, because being able to keep
// something is the point of marking it; marking is the act that consents to it
// being stored, and they go to the config directory with 0600.
//
// Polling, because no platform offers a usable "the clipboard changed" signal
// that works for a background app on both Windows and Linux. Twice a second is
// below noticing. Entries are compared against the last one seen rather than
// read blindly, so nothing is added when nothing changed.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager};

/// Enough to scroll, not enough to grow without bound.
const MAX_ENTRIES: usize = 60;
/// Images are held decoded, so a cap on how many is a cap on memory.
const MAX_IMAGES: usize = 12;
/// Bigger than this and it is a document being moved, not a snippet worth
/// keeping. Skipped rather than truncated: half a copied file is worse than none.
const MAX_TEXT: usize = 20_000;

#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ClipEntry {
    pub id: String,
    /// "text" or "image".
    pub kind: String,
    /// The text. Empty for an image.
    pub body: String,
    /// An image's thumbnail, raw RGBA base64'd, for the webview to draw on a
    /// canvas. Raw rather than PNG so no encoder has to be carried, and a
    /// thumbnail rather than the original so a 1920×1080 screenshot is not sent
    /// over IPC as eleven megabytes of base64.
    pub thumb: String,
    pub thumb_w: u32,
    pub thumb_h: u32,
    /// The original's size, for the label.
    pub bytes: usize,
    /// Unix milliseconds.
    pub copied_at: i64,
    pub favourite: bool,
}

#[derive(Default)]
pub struct Clipboard {
    entries: Mutex<Vec<ClipEntry>>,
    watching: Mutex<bool>,
}

impl Clipboard {
    pub fn new() -> Self {
        Self {
            entries: Mutex::new(load_favourites()),
            watching: Mutex::new(false),
        }
    }

    pub fn entries(&self) -> Vec<ClipEntry> {
        self.entries.lock().unwrap().clone()
    }

    pub fn is_watching(&self) -> bool {
        *self.watching.lock().unwrap()
    }

    pub fn set_watching(&self, on: bool) {
        *self.watching.lock().unwrap() = on;
    }

    /// Adds what was just copied, unless it is what is already at the top.
    ///
    /// Copying the same thing twice moves it up rather than filling the list
    /// with it — including when it was copied from the island itself.
    fn add(&self, kind: &str, body: String, bytes: usize) -> bool {
        let mut entries = self.entries.lock().unwrap();
        if let Some(idx) = entries.iter().position(|e| e.kind == kind && e.body == body) {
            let mut existing = entries.remove(idx);
            existing.copied_at = now_ms();
            entries.insert(0, existing);
            return true;
        }
        entries.insert(
            0,
            ClipEntry {
                id: next_id(),
                kind: kind.to_string(),
                body,
                thumb: String::new(),
                thumb_w: 0,
                thumb_h: 0,
                bytes,
                copied_at: now_ms(),
                favourite: false,
            },
        );
        trim(&mut entries);
        true
    }

    /// Images carry a thumbnail instead of a body.
    fn add_image(&self, thumb: String, w: u32, h: u32, bytes: usize) {
        let mut entries = self.entries.lock().unwrap();
        if let Some(idx) = entries.iter().position(|e| e.kind == "image" && e.bytes == bytes) {
            let mut existing = entries.remove(idx);
            existing.copied_at = now_ms();
            entries.insert(0, existing);
            return;
        }
        entries.insert(
            0,
            ClipEntry {
                id: next_id(),
                kind: "image".to_string(),
                body: String::new(),
                thumb,
                thumb_w: w,
                thumb_h: h,
                bytes,
                copied_at: now_ms(),
                favourite: false,
            },
        );
        trim(&mut entries);
    }

    pub fn toggle_favourite(&self, id: &str) {
        let mut entries = self.entries.lock().unwrap();
        if let Some(entry) = entries.iter_mut().find(|e| e.id == id) {
            entry.favourite = !entry.favourite;
        }
        save_favourites(&entries);
    }

    pub fn remove(&self, id: &str) {
        let mut entries = self.entries.lock().unwrap();
        entries.retain(|e| e.id != id);
        save_favourites(&entries);
    }

    /// Forgets everything, favourites and what was written down with them.
    pub fn clear(&self) {
        let mut entries = self.entries.lock().unwrap();
        entries.clear();
        save_favourites(&entries);
    }
}

/// Drops the oldest, and the oldest images sooner. Favourites are kept.
fn trim(entries: &mut Vec<ClipEntry>) {
    let mut images = 0;
    let mut kept: Vec<ClipEntry> = Vec::with_capacity(entries.len());
    for entry in entries.iter() {
        if entry.favourite {
            kept.push(entry.clone());
            continue;
        }
        if entry.kind == "image" {
            images += 1;
            if images > MAX_IMAGES {
                continue;
            }
        }
        if kept.len() >= MAX_ENTRIES {
            continue;
        }
        kept.push(entry.clone());
    }
    *entries = kept;
}

/// Ids come from a counter, not from the clock and the length: two things
/// copied in the same millisecond would otherwise collide.
fn next_id() -> String {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    format!("clip-{}", NEXT.fetch_add(1, Ordering::Relaxed))
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

// ── Favourites on disk ────────────────────────────────────────────────────────

fn favourites_path() -> std::path::PathBuf {
    crate::platform::config_dir().join("clipboard-favourites.json")
}

/// Only text favourites are written down.
///
/// An image favourite would mean carrying raw pixels in a JSON file, which is
/// both enormous and the wrong place for it. It stays for the session, as the
/// history does. The Mac build keeps images too, as PNGs beside the index.
fn save_favourites(entries: &[ClipEntry]) {
    let keep: Vec<&ClipEntry> = entries
        .iter()
        .filter(|e| e.favourite && e.kind == "text")
        .collect();
    let dir = crate::platform::config_dir();
    if crate::platform::ensure_private_dir(&dir).is_err() {
        return;
    }
    match serde_json::to_vec(&keep) {
        Ok(json) => {
            if let Err(err) = std::fs::write(favourites_path(), json) {
                crate::log::line(format!("clipboard: could not save favourites — {err}"));
            }
        }
        Err(err) => crate::log::line(format!("clipboard: could not encode favourites — {err}")),
    }
}

fn load_favourites() -> Vec<ClipEntry> {
    std::fs::read(favourites_path())
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Vec<ClipEntry>>(&bytes).ok())
        .unwrap_or_default()
}

// ── The poller ────────────────────────────────────────────────────────────────

/// Watches the clipboard while the user has asked for it.
///
/// One thread, parked on a sleep rather than a condvar: unlike the cursor poll
/// this is twice a second, so the thread costs nothing measurable even when it
/// has nothing to do, and the simpler shape is worth more than the microseconds.
pub fn spawn(app: AppHandle) {
    std::thread::spawn(move || {
        let mut board = match arboard::Clipboard::new() {
            Ok(b) => b,
            Err(err) => {
                crate::log::line(format!("clipboard: unavailable — {err}"));
                return;
            }
        };
        let mut last_text: Option<String> = None;
        let mut last_image: Option<usize> = None;

        loop {
            std::thread::sleep(Duration::from_millis(500));

            let Some(shared) = app.try_state::<crate::Shared>() else { continue };
            if !shared.clipboard.is_watching() {
                continue;
            }

            if let Ok(text) = board.get_text() {
                if !text.trim().is_empty() && text.len() <= MAX_TEXT && Some(&text) != last_text.as_ref()
                {
                    last_text = Some(text.clone());
                    last_image = None;
                    shared.clipboard.add("text", text, 0);
                    let _ = app.emit("clipboard-changed", ());
                    continue;
                }
                if !text.trim().is_empty() {
                    continue;
                }
            }

            if let Ok(image) = board.get_image() {
                let bytes = image.bytes.len();
                if last_image != Some(bytes) {
                    last_image = Some(bytes);
                    last_text = None;
                    let (thumb, w, h) = thumbnail(&image);
                    shared.clipboard.add_image(thumb, w, h, bytes);
                    let _ = app.emit("clipboard-changed", ());
                }
            }
        }
    });
}

/// A small RGBA copy for the row's icon.
///
/// Nearest neighbour, which is all a 40 px square needs and costs no dependency.
fn thumbnail(image: &arboard::ImageData) -> (String, u32, u32) {
    const MAX: usize = 40;
    let (sw, sh) = (image.width.max(1), image.height.max(1));
    let scale = (sw.max(sh) as f64 / MAX as f64).max(1.0);
    let (tw, th) = (((sw as f64 / scale) as usize).max(1), ((sh as f64 / scale) as usize).max(1));

    let mut out = Vec::with_capacity(tw * th * 4);
    for y in 0..th {
        let sy = ((y as f64 * scale) as usize).min(sh - 1);
        for x in 0..tw {
            let sx = ((x as f64 * scale) as usize).min(sw - 1);
            let i = (sy * sw + sx) * 4;
            if i + 3 < image.bytes.len() {
                out.extend_from_slice(&image.bytes[i..i + 4]);
            } else {
                out.extend_from_slice(&[0, 0, 0, 0]);
            }
        }
    }
    (base64(&out), tw as u32, th as u32)
}

/// Base64 by hand rather than another dependency for sixty lines of table.
fn base64(bytes: &[u8]) -> String {
    const SET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
        out.push(SET[(n >> 18 & 63) as usize] as char);
        out.push(SET[(n >> 12 & 63) as usize] as char);
        out.push(if chunk.len() > 1 { SET[(n >> 6 & 63) as usize] as char } else { '=' });
        out.push(if chunk.len() > 2 { SET[(n & 63) as usize] as char } else { '=' });
    }
    out
}

/// Puts an entry back on the clipboard.
///
/// Text only. Putting an image back would mean keeping every original's pixels
/// in memory for the one time somebody wants it again, and the thumbnail the
/// row shows is far too small to be worth pasting.
pub fn write_back(entry: &ClipEntry) -> bool {
    if entry.kind != "text" {
        return false;
    }
    let Ok(mut board) = arboard::Clipboard::new() else { return false };
    board.set_text(entry.body.clone()).is_ok()
}
