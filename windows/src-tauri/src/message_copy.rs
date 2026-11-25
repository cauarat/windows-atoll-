//! Copy, on a message card: what the sender sent, on the clipboard, ready to
//! paste anywhere — the twin of `MessageCopier` and `MessagePasteboard` on
//! the Mac. Their words, their photo whole, their voice message and their
//! PDF as files; never what the card says about them.
//!
//! The clipboard here takes one kind of thing per copy, the way arboard
//! writes it: words as text, a photo as the image, a voice message or a
//! post's files as the files. The Mac lays a photo down as the file, the
//! image and its caption at once, and files with what was written beside
//! them — `docs/parity/README.md` lists the difference.

use std::path::{Path, PathBuf};

use crate::i18n;
use crate::message_proto::MessageFile;

fn say(english: &str) -> String {
    i18n::t(&i18n::current(), english)
}

/// Words, as they were written.
pub fn copy_text(text: &str) -> Result<(), String> {
    let mut board = arboard::Clipboard::new().map_err(|err| err.to_string())?;
    board.set_text(text.to_string()).map_err(|err| err.to_string())
}

/// A Mattermost photo, the original — as the image, turned the way the camera
/// meant, so it pastes into a chat, a document or an editor alike. A format
/// this build cannot read (HEIC, WebP, GIF) goes as the file instead, which
/// every chat and the file manager still take.
pub async fn copy_photo(file_id: String, name: String, mime_type: String, remote_url: Option<String>)
    -> Result<(), String> {
    let failed = || say("Couldn't copy the photo");
    let file = crate::mattermost::original_photo_file(file_id, &name, &mime_type, remote_url)
        .await
        .map_err(|_| failed())?;
    // Decoding a phone photo and encoding it twice over is a second's work:
    // not on the thread the island's commands share.
    tauri::async_runtime::spawn_blocking(move || put_photo(&file))
        .await
        .map_err(|_| failed())?
        .map_err(|_| failed())
}

/// An Ato voice message, as the audio file — named the way it was sent, with
/// the extension its bytes say it really has.
pub async fn copy_voice(storage_file_id: String, file_name: String) -> Result<(), String> {
    let failed = || say("Couldn't copy the audio");
    let bytes = crate::ato::voice_note_bytes(storage_file_id.clone())
        .await
        .map_err(|_| failed())?;
    let file = local_file(
        &storage_file_id,
        &audio_file_name(&file_name, &bytes),
        &std::env::temp_dir().join("Notchy Audio"),
        "Voice message",
    );
    write_file(&file, &bytes).map_err(|_| failed())?;
    tauri::async_runtime::spawn_blocking(move || put_files(vec![file]))
        .await
        .map_err(|_| failed())?
        .map_err(|_| failed())
}

/// Files the card does not draw — a PDF, a spreadsheet — or every file of a
/// post with several photos, each under the name it was sent with, so
/// pasting them into Explorer or a file manager gives those names.
///
/// `source` is the service they came from: "mattermost" or "ato". Each is
/// fetched the first time it is copied and the same file is handed on after
/// that — a service's file never changes under its id.
pub async fn copy_files(source: String, files: Vec<MessageFile>) -> Result<(), String> {
    let failed = || {
        say(if files.len() == 1 { "Couldn't copy the file" } else { "Couldn't copy the files" })
    };
    if files.is_empty() {
        return Err(failed());
    }
    let folder = std::env::temp_dir().join("Notchy Files");
    let mut paths: Vec<PathBuf> = Vec::with_capacity(files.len());
    for file in &files {
        let path = local_file(&file.file_id, &file.name, &folder, "File");
        if !path.exists() {
            let bytes = match source.as_str() {
                "mattermost" => crate::mattermost::file_bytes(file.file_id.clone()).await,
                "ato" => crate::ato::file_bytes(file.file_id.clone()).await,
                // WhatsApp hands the card no files.
                _ => Err(String::new()),
            }
            .map_err(|_| failed())?;
            write_file(&path, &bytes).map_err(|_| failed())?;
        }
        paths.push(path);
    }
    tauri::async_runtime::spawn_blocking(move || put_files(paths))
        .await
        .map_err(|_| failed())?
        .map_err(|_| failed())
}

fn put_photo(file: &Path) -> Result<(), String> {
    let mut board = arboard::Clipboard::new().map_err(|err| err.to_string())?;
    match decode(file) {
        Some(image) => board.set_image(image).map_err(|err| err.to_string()),
        None => board.set().file_list(&[file]).map_err(|err| err.to_string()),
    }
}

fn put_files(files: Vec<PathBuf>) -> Result<(), String> {
    let mut board = arboard::Clipboard::new().map_err(|err| err.to_string())?;
    board.set().file_list(&files).map_err(|err| err.to_string())
}

/// The photo's pixels, upright: a phone photo is stored sideways with an EXIF
/// note saying so, and pasted as stored it would land on its side.
fn decode(file: &Path) -> Option<arboard::ImageData<'static>> {
    use image::ImageDecoder;
    let mut decoder = image::ImageReader::open(file).ok()?.with_guessed_format().ok()?.into_decoder().ok()?;
    let orientation = decoder.orientation().unwrap_or(image::metadata::Orientation::NoTransforms);
    let mut picture = image::DynamicImage::from_decoder(decoder).ok()?;
    picture.apply_orientation(orientation);
    let rgba = picture.into_rgba8();
    Some(arboard::ImageData {
        width: rgba.width() as usize,
        height: rgba.height() as usize,
        bytes: rgba.into_raw().into(),
    })
}

// ── Where a copied file goes ─────────────────────────────────────────────────

/// Where a file is written to be copied: in a folder of its own, named by its
/// id, under the name it was sent with — so pasting it gives that name, and
/// two files both called `scan.pdf` are still two files. One with no usable
/// name is called `fallback`. `MessageCopy.localFile` on the Mac.
pub fn local_file(id: &str, name: &str, folder: &Path, fallback: &str) -> PathBuf {
    let mut own = safe_file_name(name);
    if own.is_empty() {
        own = fallback.to_string();
    }
    let mut key = safe_file_name(id);
    if key.is_empty() {
        key = "file".to_string();
    }
    folder.join(key).join(own)
}

/// Writes a file whole or not at all: beside it first, then moved over, so a
/// copy cut short never leaves half a PDF that the next copy takes as done.
pub fn write_file(file: &Path, bytes: &[u8]) -> std::io::Result<()> {
    if let Some(dir) = file.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let mut partial = file.as_os_str().to_owned();
    partial.push(".part");
    let partial = PathBuf::from(partial);
    std::fs::write(&partial, bytes)?;
    std::fs::rename(&partial, file)
}

// ── The voice message's file ─────────────────────────────────────────────────

/// What the copied audio is called: the name it was sent with, with the
/// extension its bytes say it really has. Ato has been seen naming MP3s
/// `.ogg`, which a player that sniffs forgives and nothing else does.
/// `MessageCopy.audioFileName` on the Mac — the tests below are its cases.
pub fn audio_file_name(name: &str, bytes: &[u8]) -> String {
    let mut base = safe_file_name(name);
    if base.is_empty() {
        base = "Voice message".to_string();
    }
    let Some(real) = audio_extension(bytes) else { return base };
    let path = Path::new(&base);
    let own: String = path.extension().and_then(|ext| ext.to_str()).unwrap_or("").to_lowercase();
    if own == real || (real == "m4a" && ["mp4", "m4a", "aac"].contains(&own.as_str())) {
        return base;
    }
    let stem: String = if own.is_empty() {
        base.clone()
    } else {
        path.file_stem().and_then(|stem| stem.to_str()).unwrap_or("").to_string()
    };
    format!("{}.{real}", if stem.is_empty() { "Voice message" } else { stem.as_str() })
}

/// The audio container the first bytes name, or None for one this does not
/// know — whose name is then left as it came.
pub fn audio_extension(bytes: &[u8]) -> Option<&'static str> {
    let has = |what: &[u8], at: usize| bytes.len() >= at + what.len() && &bytes[at..at + what.len()] == what;
    if has(b"OggS", 0) {
        return Some("ogg");
    }
    if has(b"ID3", 0) {
        return Some("mp3");
    }
    if has(b"RIFF", 0) && has(b"WAVE", 8) {
        return Some("wav");
    }
    if has(b"ftyp", 4) {
        return Some("m4a");
    }
    if has(&[0x1A, 0x45, 0xDF, 0xA3], 0) {
        return Some("webm");
    }
    if has(b"fLaC", 0) {
        return Some("flac");
    }
    if has(b"#!AMR", 0) {
        return Some("amr");
    }
    // A bare frame header: eleven bits set. ADTS — AAC without a container —
    // is the one whose layer bits are zero.
    if bytes.len() >= 2 && bytes[0] == 0xFF && bytes[1] & 0xE0 == 0xE0 {
        return Some(if bytes[1] & 0x06 == 0 { "aac" } else { "mp3" });
    }
    None
}

/// The last path component, with nothing a file system refuses and no leading
/// dot — the name a file is written under in the temporary folder.
pub fn safe_file_name(name: &str) -> String {
    let last: &str = name.rsplit(['/', '\\']).next().unwrap_or("");
    let cleaned: String = last
        .chars()
        .map(|c| if c.is_control() || ":<>\"|?*".contains(c) { '-' } else { c })
        .collect();
    cleaned.trim_matches(|c: char| c == '.' || c.is_whitespace()).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    const MP3: &[u8] = &[0x49, 0x44, 0x33, 0x04, 0, 0, 0, 0, 0, 0];
    const OGG: &[u8] = b"OggS\0\0\0\0\0\0\0\0";
    const M4A: &[u8] = b"\0\0\0\x20ftypM4A ";
    const JUNK: &[u8] = &[1, 2, 3, 4, 5, 6];

    #[test]
    fn names_the_audio_by_what_it_is() {
        assert_eq!(audio_file_name("audio.ogg", MP3), "audio.mp3");
        assert_eq!(audio_file_name("voice.ogg", OGG), "voice.ogg");
        assert_eq!(audio_file_name("rec.mp4", M4A), "rec.mp4");
        assert_eq!(audio_file_name("nota", MP3), "nota.mp3");
        assert_eq!(audio_file_name("", OGG), "Voice message.ogg");
        assert_eq!(audio_file_name("../../etc/x.ogg", OGG), "x.ogg");
        assert_eq!(audio_file_name("a.opus", JUNK), "a.opus");
    }

    #[test]
    fn sniffs_the_containers() {
        assert_eq!(audio_extension(&[0xFF, 0xF1, 0x50, 0x80]), Some("aac"));
        assert_eq!(audio_extension(&[0xFF, 0xFB, 0x90, 0x64]), Some("mp3"));
        assert_eq!(audio_extension(b"RIFF\0\0\0\0WAVE"), Some("wav"));
        assert_eq!(audio_extension(&[0x1A, 0x45, 0xDF, 0xA3, 0, 0]), Some("webm"));
        assert_eq!(audio_extension(&[]), None);
    }

    #[test]
    fn cleans_names_the_file_system_refuses() {
        assert_eq!(safe_file_name("a:b?c*.ogg"), "a-b-c-.ogg");
    }

    #[test]
    fn a_copied_file_keeps_its_own_name_in_a_folder_named_by_its_id() {
        let folder = Path::new("/tmp/Notchy Files");
        assert_eq!(local_file("f1", "boleto.pdf", folder, "File"), folder.join("f1").join("boleto.pdf"));
        assert_eq!(local_file("f1", "../../etc/passwd", folder, "File"), folder.join("f1").join("passwd"));
        assert_eq!(local_file("../..", "a.pdf", folder, "File"), folder.join("file").join("a.pdf"));
        assert_eq!(local_file("f1", " ", folder, "File"), folder.join("f1").join("File"));
    }
}
