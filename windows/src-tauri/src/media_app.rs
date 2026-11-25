// The application behind what is playing: its icon, for the corner of the Now
// Playing card's artwork, and the app itself, for the pill's second click.
//
// The Mac reads both off the bundle id MediaRemote reports —
// `NSWorkspace.icon(forFile:)` and `NSRunningApplication.activate`. GSMTC
// reports an AppUserModelID instead, which comes in two shapes:
//
// - a packaged app's identity, `Family_hash!App` (Media Player, Apple Music,
//   anything from the Store). Windows answers for those itself: `AppInfo` has
//   the logo, `IApplicationActivationManager` brings the app up.
// - a desktop app's own name for itself: `Spotify.exe`, `Chrome`, `MSEdge`, and
//   for Firefox a hash. Nothing maps those back to a program, so the running
//   process whose executable matches is found, and its icon and windows are
//   read from there.
//
// Honest in the way the Mac's is: a tab playing in a browser shows the
// browser's icon, because the browser is what the system says is playing.

/// That application's icon as a PNG `data:` URL, or `None` to draw the note.
pub fn icon(aumid: &str) -> Option<String> {
    imp::icon(aumid)
}

/// Brings that application forward — the window holding `title` first, the way
/// the Mac goes for the tab that is playing rather than the browser. Whether
/// anything came up.
pub fn open(aumid: &str, title: &str) -> bool {
    imp::open(aumid, title)
}

/// The executables a desktop AUMID stands for. Lower case, as the process list
/// is compared.
#[cfg_attr(not(windows), allow(dead_code))]
fn executables(aumid: &str) -> Vec<String> {
    let lower = aumid.to_ascii_lowercase();
    if lower.ends_with(".exe") {
        // A full path is sometimes what an app registers itself as.
        let name = lower.rsplit(['\\', '/']).next().unwrap_or(&lower);
        return vec![name.to_string()];
    }
    // The browsers name themselves, and Firefox by a hash of its install path.
    for (needle, exe) in [
        ("chrome", "chrome.exe"),
        ("msedge", "msedge.exe"),
        ("firefox", "firefox.exe"),
        ("308046b0af4a39cb", "firefox.exe"),
        ("brave", "brave.exe"),
        ("opera", "opera.exe"),
        ("vivaldi", "vivaldi.exe"),
        ("spotify", "spotify.exe"),
        ("vlc", "vlc.exe"),
        ("itunes", "itunes.exe"),
    ] {
        if lower.contains(needle) {
            return vec![exe.to_string()];
        }
    }
    // Otherwise the last word of a dotted id, `Company.App` → `app.exe`.
    let head = lower.split('!').next().unwrap_or(&lower);
    let last = head.rsplit('.').next().unwrap_or(head);
    if last.is_empty() {
        Vec::new()
    } else {
        vec![format!("{last}.exe")]
    }
}

#[cfg(windows)]
mod imp {
    use std::io::Cursor;

    use windows::core::{BOOL, HSTRING, PCWSTR, PWSTR};
    use windows::ApplicationModel::AppInfo;
    use windows::Foundation::Size;
    use windows::Storage::Streams::DataReader;
    use windows::Win32::Foundation::{CloseHandle, HWND, LPARAM};
    use windows::Win32::Graphics::Gdi::{
        DeleteObject, GetDC, GetDIBits, ReleaseDC, BITMAPINFO, BITMAPINFOHEADER, BI_RGB, DIB_RGB_COLORS,
        HGDIOBJ,
    };
    use windows::Win32::Storage::FileSystem::FILE_FLAGS_AND_ATTRIBUTES;
    use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_LOCAL_SERVER};
    use windows::Win32::System::Diagnostics::ToolHelp::{
        CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS,
    };
    use windows::Win32::System::Threading::{
        OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION,
    };
    use windows::Win32::UI::Shell::{
        ApplicationActivationManager, IApplicationActivationManager, SHGetFileInfoW, AO_NONE, SHFILEINFOW,
        SHGFI_ICON, SHGFI_LARGEICON,
    };
    use windows::Win32::UI::WindowsAndMessaging::{
        DestroyIcon, EnumWindows, GetIconInfo, GetWindow, GetWindowTextLengthW, GetWindowTextW,
        GetWindowThreadProcessId, IsIconic, IsWindowVisible, SetForegroundWindow, ShowWindow, GW_OWNER,
        ICONINFO, SW_RESTORE,
    };

    /// A packaged identity rather than a program's own name.
    fn packaged(aumid: &str) -> bool {
        aumid.contains('!')
    }

    // ── Icon ──────────────────────────────────────────────────────────────────

    pub fn icon(aumid: &str) -> Option<String> {
        if aumid.is_empty() {
            return None;
        }
        let png = if packaged(aumid) { packaged_logo(aumid) } else { exe_icon(aumid) }?;
        Some(format!("data:image/png;base64,{}", crate::claude::base64_for(&png)))
    }

    /// The Store's own logo for the app, at the size the badge draws it — 32
    /// pixels, so it stays sharp at 200 %.
    fn packaged_logo(aumid: &str) -> Option<Vec<u8>> {
        let info = AppInfo::GetFromAppUserModelId(&HSTRING::from(aumid)).ok()?;
        let reference = info.DisplayInfo().ok()?.GetLogo(Size { Width: 32.0, Height: 32.0 }).ok()?;
        let stream = reference.OpenReadAsync().ok()?.get().ok()?;
        let size = stream.Size().ok()?;
        if size == 0 || size > 1024 * 1024 {
            return None;
        }
        let reader = DataReader::CreateDataReader(&stream.GetInputStreamAt(0).ok()?).ok()?;
        reader.LoadAsync(size as u32).ok()?.get().ok()?;
        let mut bytes = vec![0u8; size as usize];
        reader.ReadBytes(&mut bytes).ok()?;
        // A logo can be any image type; the card wants something an <img> takes
        // without asking, and everything the Store ships decodes here.
        let picture = image::load_from_memory(&bytes).ok()?;
        encode_png(picture.to_rgba8())
    }

    /// The program's own icon, read off the executable of the running process.
    fn exe_icon(aumid: &str) -> Option<Vec<u8>> {
        let path = running_executables(aumid).into_iter().next()?.1;
        let wide: Vec<u16> = path.encode_utf16().chain(std::iter::once(0)).collect();
        let mut info = SHFILEINFOW::default();
        let got = unsafe {
            SHGetFileInfoW(
                PCWSTR(wide.as_ptr()),
                FILE_FLAGS_AND_ATTRIBUTES(0),
                Some(&mut info),
                std::mem::size_of::<SHFILEINFOW>() as u32,
                SHGFI_ICON | SHGFI_LARGEICON,
            )
        };
        if got == 0 || info.hIcon.is_invalid() {
            return None;
        }
        let png = icon_png(info.hIcon);
        unsafe {
            let _ = DestroyIcon(info.hIcon);
        }
        png
    }

    /// An HICON's colour bitmap as RGBA, then PNG.
    fn icon_png(icon: windows::Win32::UI::WindowsAndMessaging::HICON) -> Option<Vec<u8>> {
        let mut parts = ICONINFO::default();
        unsafe { GetIconInfo(icon, &mut parts) }.ok()?;
        let colour = parts.hbmColor;
        let mask = parts.hbmMask;
        let pixels = (|| {
            if colour.is_invalid() {
                return None;
            }
            let read = |bitmap| -> Option<(u32, u32, Vec<u8>)> {
                let mut header = BITMAPINFO {
                    bmiHeader: BITMAPINFOHEADER {
                        biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
                        ..Default::default()
                    },
                    ..Default::default()
                };
                let dc = unsafe { GetDC(None) };
                // First call: the size.
                let sized = unsafe { GetDIBits(dc, bitmap, 0, 0, None, &mut header, DIB_RGB_COLORS) };
                if sized == 0 || header.bmiHeader.biWidth <= 0 {
                    unsafe { ReleaseDC(None, dc) };
                    return None;
                }
                let w = header.bmiHeader.biWidth as u32;
                let h = header.bmiHeader.biHeight.unsigned_abs();
                header.bmiHeader.biBitCount = 32;
                header.bmiHeader.biCompression = BI_RGB.0;
                // Negative: rows top to bottom.
                header.bmiHeader.biHeight = -(h as i32);
                let mut buf = vec![0u8; (w * h * 4) as usize];
                let rows = unsafe {
                    GetDIBits(dc, bitmap, 0, h, Some(buf.as_mut_ptr().cast()), &mut header, DIB_RGB_COLORS)
                };
                unsafe { ReleaseDC(None, dc) };
                (rows > 0).then_some((w, h, buf))
            };
            let (w, h, mut bgra) = read(colour)?;
            // Old icons carry no alpha and keep their shape in the mask instead.
            if bgra.chunks(4).all(|p| p[3] == 0) {
                if let Some((mw, mh, m)) = read(mask) {
                    if mw == w && mh >= h {
                        for (p, q) in bgra.chunks_mut(4).zip(m.chunks(4)) {
                            p[3] = if q[0] == 0 { 255 } else { 0 };
                        }
                    }
                }
            }
            for p in bgra.chunks_mut(4) {
                p.swap(0, 2);
            }
            image::RgbaImage::from_raw(w, h, bgra)
        })();
        unsafe {
            if !colour.is_invalid() {
                let _ = DeleteObject(HGDIOBJ(colour.0));
            }
            if !mask.is_invalid() {
                let _ = DeleteObject(HGDIOBJ(mask.0));
            }
        }
        encode_png(pixels?)
    }

    fn encode_png(picture: image::RgbaImage) -> Option<Vec<u8>> {
        let mut out = Vec::new();
        picture.write_to(&mut Cursor::new(&mut out), image::ImageFormat::Png).ok()?;
        Some(out)
    }

    // ── Processes and windows ─────────────────────────────────────────────────

    /// The running processes whose executable the AUMID names: pid and path.
    fn running_executables(aumid: &str) -> Vec<(u32, String)> {
        let wanted = super::executables(aumid);
        if wanted.is_empty() {
            return Vec::new();
        }
        let mut found = Vec::new();
        let Ok(snapshot) = (unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) }) else {
            return found;
        };
        let mut entry = PROCESSENTRY32W {
            dwSize: std::mem::size_of::<PROCESSENTRY32W>() as u32,
            ..Default::default()
        };
        let mut more = unsafe { Process32FirstW(snapshot, &mut entry) }.is_ok();
        while more {
            let len = entry.szExeFile.iter().position(|&c| c == 0).unwrap_or(entry.szExeFile.len());
            let name = String::from_utf16_lossy(&entry.szExeFile[..len]).to_ascii_lowercase();
            if wanted.contains(&name) {
                if let Some(path) = image_path(entry.th32ProcessID) {
                    found.push((entry.th32ProcessID, path));
                }
            }
            more = unsafe { Process32NextW(snapshot, &mut entry) }.is_ok();
        }
        unsafe {
            let _ = CloseHandle(snapshot);
        }
        found
    }

    fn image_path(pid: u32) -> Option<String> {
        let process = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) }.ok()?;
        let mut buf = [0u16; 1024];
        let mut len = buf.len() as u32;
        let ok = unsafe { QueryFullProcessImageNameW(process, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut len) };
        unsafe {
            let _ = CloseHandle(process);
        }
        ok.ok()?;
        Some(String::from_utf16_lossy(&buf[..len as usize]))
    }

    /// A visible top-level window of one of `pids`, with its title.
    struct Search {
        pids: Vec<u32>,
        windows: Vec<(HWND, String)>,
    }

    unsafe extern "system" fn collect(hwnd: HWND, data: LPARAM) -> BOOL {
        let search = unsafe { &mut *(data.0 as *mut Search) };
        let mut pid = 0u32;
        unsafe { GetWindowThreadProcessId(hwnd, Some(&mut pid)) };
        let owned = unsafe { GetWindow(hwnd, GW_OWNER) }.map(|o| !o.is_invalid()).unwrap_or(false);
        if search.pids.contains(&pid) && unsafe { IsWindowVisible(hwnd) }.as_bool() && !owned {
            let len = unsafe { GetWindowTextLengthW(hwnd) };
            if len > 0 {
                let mut buf = vec![0u16; len as usize + 1];
                let got = unsafe { GetWindowTextW(hwnd, &mut buf) };
                search.windows.push((hwnd, String::from_utf16_lossy(&buf[..got.max(0) as usize])));
            }
        }
        true.into()
    }

    // ── Bringing it up ────────────────────────────────────────────────────────

    pub fn open(aumid: &str, title: &str) -> bool {
        if aumid.is_empty() {
            return false;
        }
        if packaged(aumid) {
            return activate_packaged(aumid);
        }
        let pids: Vec<u32> = running_executables(aumid).into_iter().map(|(pid, _)| pid).collect();
        if pids.is_empty() {
            return false;
        }
        let mut search = Search { pids, windows: Vec::new() };
        unsafe {
            let _ = EnumWindows(Some(collect), LPARAM(&mut search as *mut Search as isize));
        }
        // A browser's window is titled after its active tab, so the one
        // playing — when it is the tab in front — says the track's name.
        let needle = title.trim().to_lowercase();
        let pick = search
            .windows
            .iter()
            .find(|(_, t)| !needle.is_empty() && t.to_lowercase().contains(&needle))
            .or_else(|| search.windows.first());
        let Some(&(hwnd, _)) = pick else { return false };
        unsafe {
            if IsIconic(hwnd).as_bool() {
                let _ = ShowWindow(hwnd, SW_RESTORE);
            }
            // The click on the island is the last input this process received,
            // which is what lets it hand the foreground on.
            SetForegroundWindow(hwnd).as_bool()
        }
    }

    fn activate_packaged(aumid: &str) -> bool {
        let Ok(manager) = (unsafe {
            CoCreateInstance::<_, IApplicationActivationManager>(&ApplicationActivationManager, None, CLSCTX_LOCAL_SERVER)
        }) else {
            return false;
        };
        unsafe { manager.ActivateApplication(&HSTRING::from(aumid), PCWSTR::null(), AO_NONE) }.is_ok()
    }
}

#[cfg(not(windows))]
mod imp {
    pub fn icon(_aumid: &str) -> Option<String> {
        None
    }

    pub fn open(_aumid: &str, _title: &str) -> bool {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::executables;

    #[test]
    fn a_desktop_aumid_names_its_program() {
        assert_eq!(executables("Spotify.exe"), ["spotify.exe"]);
        assert_eq!(executables("C:\\Program Files\\VideoLAN\\VLC\\vlc.exe"), ["vlc.exe"]);
        assert_eq!(executables("Chrome"), ["chrome.exe"]);
        assert_eq!(executables("MSEdge"), ["msedge.exe"]);
        assert_eq!(executables("308046B0AF4A39CB"), ["firefox.exe"]);
        assert_eq!(executables("Company.Player"), ["player.exe"]);
    }
}
