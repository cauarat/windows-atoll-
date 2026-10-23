// Island window: placement on the chosen display, the two window sizes
// (full panel / invisible wake strip), click-through and the cursor poll.
//
// There is no notch on a PC, so the island is a black shape drawn against one
// edge of the chosen display — bottom right by default, next to the clock —
// inside a borderless, transparent, always-on-top window that never takes focus.
// Which of the six spots it uses is the `position` preference.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, Monitor, PhysicalPosition, PhysicalSize, WebviewWindow};

use crate::platform::{self, cursor_physical, left_button_down};

/// Logical size of the full window — the largest island view, like the macOS
/// panel. The height holds the AI Agents dashboard, which is the one view that
/// breaks the 160 law; the window is transparent and click-through everywhere
/// the island is not, so what is not the island is never seen. Kept in step
/// with `PANEL_W`/`PANEL_H` in src/core/layout.ts.
pub const PANEL_W: f64 = 760.0;
pub const PANEL_H: f64 = 620.0;
/// Logical size of the invisible strip that wakes the island when it is hidden.
pub const STRIP_W: f64 = 240.0;
pub const STRIP_H: f64 = 6.0;

pub const WINDOW_LABEL: &str = "island";

/// Margin around the island that still counts as "on the island", in logical px.
/// Wider than the macOS 6 pt because a click must never be swallowed.
const HIT_MARGIN: f64 = 14.0;

/// How far a bottom-anchored island is lifted off the edge, in logical px.
///
/// Not a design inset — it is invisible at 2 px. An auto-hidden taskbar is not
/// subtracted from the work area, so without this the wake strip would land in
/// the very bottom row of the screen, which is the row that pops the taskbar
/// back out. Mochi would then be woken and immediately covered.
const BOTTOM_GAP: f64 = 2.0;

/// Clear air between the island's card and a page anchored to it, in logical px.
///
/// Not nothing, so the two read as two surfaces of one thing rather than as one
/// block that does not line up; not much, so they still read as one thing.
const PAGE_GAP: f64 = 8.0;

/// What a page window asks for, and the least it will accept, in logical px.
/// Width is never asked for: a page takes the island's own, so the two line up.
const PAGE_H: f64 = 560.0;
const PAGE_MIN_H: f64 = 320.0;

/// The screen edge the island hugs and retracts into.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Edge {
    Top,
    Bottom,
}

/// Where along that edge it sits.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Align {
    Left,
    Centre,
    Right,
}

/// Splits the `position` preference into its two axes. Anything unknown — an
/// empty string, a value from a newer build — falls back to the default rather
/// than leaving the island somewhere nobody can reach it.
pub fn parse_position(position: &str) -> (Edge, Align) {
    let (edge, align) = position.split_once('-').unwrap_or(("bottom", "right"));
    let edge = match edge {
        "top" => Edge::Top,
        _ => Edge::Bottom,
    };
    let align = match align {
        "left" => Align::Left,
        // Both spellings, so a settings.json hand-edited either way still works.
        "centre" | "center" => Align::Centre,
        _ => Align::Right,
    };
    (edge, align)
}

/// Prefix of a dropped point, as written into `Settings::position`.
pub const FREE_PREFIX: &str = "free:";

/// The island's resting footprint in logical px — what a drop is aiming with.
/// `COMPACT_W` and `NOTCH_H` in src/core/layout.ts.
const REST_W: f64 = 288.0;
const REST_H: f64 = 32.0;

/// How near an edge a drop still counts as on that edge, in logical px.
/// The front end magnetises the drop itself; this is here so the two agree.
const MAGNET: f64 = 48.0;

/// Where the island was put: one of the six spots, or anywhere at all.
///
/// Holding the resting island for two seconds unsticks it, and where it lands
/// is kept as a fraction of the display's work area rather than as pixels —
/// the same pair on another display is the same place, so the island reappears
/// where it was put on whichever screen the cursor is on.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Placement {
    Preset(Edge, Align),
    /// The island's resting centre, as a fraction of the work area.
    Free { fx: f64, fy: f64 },
}

/// Reads either form. `free:0.734,0.882` is a dropped point; anything else goes
/// through `parse_position`, which already lands on the default when it does
/// not recognise what it was given.
pub fn parse_placement(position: &str) -> Placement {
    if let Some(rest) = position.strip_prefix(FREE_PREFIX) {
        if let Some((a, b)) = rest.split_once(',') {
            if let (Ok(fx), Ok(fy)) = (a.trim().parse::<f64>(), b.trim().parse::<f64>()) {
                if fx.is_finite() && fy.is_finite() {
                    return Placement::Free { fx: fx.clamp(0.0, 1.0), fy: fy.clamp(0.0, 1.0) };
                }
            }
        }
    }
    let (edge, align) = parse_position(position);
    Placement::Preset(edge, align)
}

/// Writes a dropped point the way `parse_placement` reads it.
pub fn format_free(fx: f64, fy: f64) -> String {
    let r = |n: f64| (n.clamp(0.0, 1.0) * 10_000.0).round() / 10_000.0;
    format!("{FREE_PREFIX}{},{}", r(fx), r(fy))
}

/// Window origin and island offsets for a dropped point, in logical pixels
/// relative to the work area.
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct FreeGeometry {
    pub win_x: f64,
    pub win_y: f64,
    pub off_x: f64,
    pub off_y: f64,
    /// Which of the island's own edges is pinned: `Top` grows down, `Bottom` up.
    pub grow: Edge,
}

/// Mirrors `freeGeometry` in src/core/anchor.ts, which has the long version of
/// why. The two have to land on the same pixel: this places the window, that
/// draws the island inside it, and the rect handed back decides click-through.
pub fn free_geometry(fx: f64, fy: f64, area_w: f64, area_h: f64) -> FreeGeometry {
    let cx = (fx * area_w).clamp(REST_W / 2.0, (area_w - REST_W / 2.0).max(REST_W / 2.0));
    let cy = (fy * area_h).clamp(REST_H / 2.0, (area_h - REST_H / 2.0).max(REST_H / 2.0));
    let grow = if cy < area_h / 2.0 { Edge::Top } else { Edge::Bottom };
    let edge_y = if grow == Edge::Top { cy - REST_H / 2.0 } else { cy + REST_H / 2.0 };
    let win_x = fit_window(cx - PANEL_W / 2.0, area_w, PANEL_W);
    let raw_y = if grow == Edge::Top { edge_y } else { edge_y - PANEL_H };
    let win_y = fit_window(raw_y, area_h, PANEL_H);
    FreeGeometry { win_x, win_y, off_x: cx - win_x, off_y: edge_y - win_y, grow }
}

/// A window larger than the display pins to the near corner rather than drifting.
fn fit_window(v: f64, area: f64, size: f64) -> f64 {
    if size >= area {
        0.0
    } else {
        v.clamp(0.0, area - size)
    }
}

/// The preset a drop lands on, or None to keep it free. Mirrors `nearestPreset`
/// in src/core/anchor.ts: both axes have to agree, because snapping on the edge
/// alone would quietly take away free placement along that edge.
pub fn nearest_preset(fx: f64, fy: f64, area_w: f64, area_h: f64) -> Option<String> {
    let edge = match hug_of(fy, area_h)? {
        Edge::Top => "top",
        Edge::Bottom => "bottom",
    };
    let x = fx * area_w;
    let align = if x - REST_W / 2.0 <= MAGNET {
        "left"
    } else if area_w - (x + REST_W / 2.0) <= MAGNET {
        "right"
    } else if (x - area_w / 2.0).abs() <= MAGNET {
        "centre"
    } else {
        return None;
    };
    Some(format!("{edge}-{align}"))
}

/// What a drop at `cx`, `cy` — the island's resting centre in work-area logical
/// pixels — is stored as: one of the six names when it lands on one, else a point.
pub fn position_for_drop(cx: f64, cy: f64, area_w: f64, area_h: f64) -> String {
    let fx = if area_w > 0.0 { cx / area_w } else { 0.5 };
    let fy = if area_h > 0.0 { cy / area_h } else { 0.5 };
    nearest_preset(fx, fy, area_w, area_h).unwrap_or_else(|| format_free(fx, fy))
}

/// The screen edge a dropped point is near enough to hug, or None out in the open.
pub fn hug_of(fy: f64, area_h: f64) -> Option<Edge> {
    let y = fy * area_h;
    if y - REST_H / 2.0 <= MAGNET {
        Some(Edge::Top)
    } else if area_h - (y + REST_H / 2.0) <= MAGNET {
        Some(Edge::Bottom)
    } else {
        None
    }
}

#[derive(Serialize, Clone)]
pub struct CursorPayload {
    pub x: f64,
    pub y: f64,
}

#[derive(Serialize, Clone)]
pub struct ScreenInfo {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub scale: f64,
    /// The work area — the display less whatever the taskbar keeps — in the
    /// same logical pixels. A dropped point is a fraction *of this*, so the
    /// front end needs it to draw the island where Rust put the window.
    pub work_x: f64,
    pub work_y: f64,
    pub work_width: f64,
    pub work_height: f64,
}

/// The island shape in window-logical coordinates, pushed by the front end.
/// The poll thread owns the click-through decision so it lands in the same 16 ms
/// tick as the cursor read — an IPC round trip here loses clicks.
#[derive(Clone, Copy, Default)]
pub struct IslandRect {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

/// A drag in flight.
///
/// `grab` is the cursor's offset from the window origin in physical pixels,
/// fixed at the moment the island came unstuck — carrying the offset rather
/// than re-reading it is what keeps the island still under the pointer instead
/// of creeping toward one corner over a long drag.
#[derive(Clone, Copy)]
pub struct DragGrab {
    /// Window origin when the island came unstuck, physical px. What the page
    /// moves the island by on Wayland is measured from here.
    pub origin_x: i32,
    pub origin_y: i32,
    pub grab_x: i32,
    pub grab_y: i32,
    /// The island's resting centre inside the window, logical px. Handed over by
    /// the front end at the start, because only it knows what it has drawn.
    pub centre_x: f64,
    pub centre_y: f64,
}

/// Wakes / parks the cursor poll thread so a hidden island costs literally nothing.
pub struct PollGate {
    active: Mutex<bool>,
    cv: Condvar,
    pub collapsed: AtomicBool,
    /// Standby: while folded away, the island takes no mouse at all, so only a
    /// message can bring it back. Mirrors `Settings::standby`.
    pub standby: AtomicBool,
    pub rect: Mutex<IslandRect>,
    /// Mirrors the window flag so we only call into the OS when it changes.
    ignoring: AtomicBool,
    /// Set while the island has been picked up and is following the cursor.
    pub drag: Mutex<Option<DragGrab>>,
}

impl PollGate {
    pub fn new() -> Self {
        Self {
            active: Mutex::new(false),
            cv: Condvar::new(),
            collapsed: AtomicBool::new(true),
            standby: AtomicBool::new(false),
            rect: Mutex::new(IslandRect::default()),
            ignoring: AtomicBool::new(false),
            drag: Mutex::new(None),
        }
    }

    pub fn set_rect(&self, rect: IslandRect) {
        *self.rect.lock().unwrap() = rect;
    }

    /// Records the flag we just pushed to the window, so the next poll tick
    /// compares against what is really there rather than what it last set.
    pub fn note_ignoring(&self, ignoring: bool) {
        self.ignoring.store(ignoring, Ordering::Relaxed);
    }

    /// True when the island is folded away and standby says to leave it that way.
    pub fn asleep(&self) -> bool {
        self.standby.load(Ordering::Relaxed) && self.collapsed.load(Ordering::Relaxed)
    }

    pub fn set_active(&self, on: bool) {
        let mut guard = self.active.lock().unwrap();
        *guard = on;
        self.cv.notify_all();
    }

    fn wait_until_active(&self) {
        let mut guard = self.active.lock().unwrap();
        while !*guard {
            guard = self.cv.wait(guard).unwrap();
        }
    }

    fn is_active(&self) -> bool {
        *self.active.lock().unwrap()
    }
}

pub fn window(app: &AppHandle) -> Option<WebviewWindow> {
    app.get_webview_window(WINDOW_LABEL)
}

fn monitor_contains(m: &Monitor, x: f64, y: f64) -> bool {
    let p = m.position();
    let s = m.size();
    x >= p.x as f64
        && x < (p.x + s.width as i32) as f64
        && y >= p.y as f64
        && y < (p.y + s.height as i32) as f64
}

/// The display the island lives on: the primary one, or the one under the cursor.
fn target_monitor(app: &AppHandle, pref: &str) -> Option<Monitor> {
    let monitors = app.available_monitors().ok()?;
    if pref == "cursor" {
        if let Some((cx, cy)) = cursor_physical() {
            if let Some(m) = monitors.iter().find(|m| monitor_contains(m, cx, cy)) {
                return Some(m.clone());
            }
        }
    }
    app.primary_monitor()
        .ok()
        .flatten()
        .or_else(|| monitors.into_iter().next())
}

pub fn screen_info(app: &AppHandle, pref: &str) -> ScreenInfo {
    match target_monitor(app, pref) {
        Some(m) => {
            let scale = m.scale_factor();
            let p = m.position();
            let s = m.size();
            let a = m.work_area();
            ScreenInfo {
                x: p.x as f64 / scale,
                y: p.y as f64 / scale,
                width: s.width as f64 / scale,
                height: s.height as f64 / scale,
                scale,
                work_x: a.position.x as f64 / scale,
                work_y: a.position.y as f64 / scale,
                work_width: a.size.width as f64 / scale,
                work_height: a.size.height as f64 / scale,
            }
        }
        None => ScreenInfo {
            x: 0.0,
            y: 0.0,
            width: 1920.0,
            height: 1080.0,
            scale: 1.0,
            work_x: 0.0,
            work_y: 0.0,
            work_width: 1920.0,
            work_height: 1080.0,
        },
    }
}

/// The rectangle the island is placed inside, in physical pixels.
///
/// At the top that is the whole display, exactly as it has always been: the
/// island sits against the very edge of the screen, over a taskbar docked up
/// there, the way the Mac island sits in the notch.
///
/// At the bottom it is the work area instead, so the island rests on top of the
/// taskbar rather than covering the clock and the tray — which is the whole
/// point of putting it down there.
fn placement_area(m: &Monitor, edge: Edge) -> (i32, i32, i32, i32) {
    match edge {
        Edge::Top => {
            let p = m.position();
            let s = m.size();
            (p.x, p.y, s.width as i32, s.height as i32)
        }
        Edge::Bottom => {
            let a = m.work_area();
            (a.position.x, a.position.y, a.size.width as i32, a.size.height as i32)
        }
    }
}

/// Where a page window goes so it reads as part of the island rather than as a
/// browser that opened: the width of the island's card, lined up with it, and
/// filling the room on the far side of it.
///
/// The far side, because which side that is depends on the corner. A page below
/// a bottom-anchored island would be off the screen, and one above a
/// top-anchored island would be behind the taskbar.
///
/// `card` is what the page itself reports through `set_island_rect`, in logical
/// coordinates inside the island's window — so this follows the island
/// wherever it is and whatever view it is showing, with no second copy of that
/// arithmetic to keep in step.
///
/// None when there is not enough room to be worth showing, or while the island
/// is folded away and has no card to hang off.
pub fn page_placement(
    app: &AppHandle,
    pref: &str,
    position: &str,
    card: IslandRect,
) -> Option<(i32, i32, u32, u32)> {
    if card.w < 1.0 || card.h < 1.0 {
        return None;
    }
    let win = window(app)?;
    let m = target_monitor(app, pref)?;
    let scale = m.scale_factor();
    // Which side the page hangs off follows the island's own pinned edge, which
    // for a dropped point is the half of the screen it has room to grow into.
    let (edge, ay, ah) = match parse_placement(position) {
        Placement::Preset(edge, _) => {
            let (_, ay, _, ah) = placement_area(&m, edge);
            (edge, ay, ah)
        }
        Placement::Free { fx, fy } => {
            let a = m.work_area();
            let g = free_geometry(fx, fy, a.size.width as f64 / scale, a.size.height as f64 / scale);
            (g.grow, a.position.y, a.size.height as i32)
        }
    };
    let origin = win.outer_position().ok()?;

    let x = origin.x + (card.x * scale).round() as i32;
    let w = (card.w * scale).round().max(1.0) as u32;

    let card_top = origin.y + (card.y * scale).round() as i32;
    let card_bottom = card_top + (card.h * scale).round() as i32;
    let (y, h) = page_span(edge, (card_top, card_bottom), (ay, ay + ah), scale)?;
    Some((x, y, w, h))
}

/// The vertical half of `page_placement`, with everything already in physical
/// pixels and the monitor and window already read.
///
/// Split out because this is the part that is easy to get backwards — above for
/// a bottom-anchored island, below for a top-anchored one — and because it can
/// then be checked without a screen.
fn page_span(edge: Edge, card: (i32, i32), area: (i32, i32), scale: f64) -> Option<(i32, u32)> {
    let (card_top, card_bottom) = card;
    let (area_top, area_bottom) = area;
    let gap = (PAGE_GAP * scale).round() as i32;
    let want = (PAGE_H * scale).round() as i32;

    let (y, h) = match edge {
        Edge::Top => {
            let top = card_bottom + gap;
            (top, (area_bottom - top).max(0).min(want))
        }
        Edge::Bottom => {
            let bottom = card_top - gap;
            let h = (bottom - area_top).max(0).min(want);
            (bottom - h, h)
        }
    };
    if h < (PAGE_MIN_H * scale).round() as i32 {
        return None;
    }
    Some((y, h as u32))
}

/// Places and sizes the window. `collapsed` picks the wake strip instead of the panel.
pub fn apply_geometry(app: &AppHandle, pref: &str, position: &str, collapsed: bool) {
    let Some(win) = window(app) else { return };
    let Some(m) = target_monitor(app, pref) else { return };

    let scale = m.scale_factor();

    let (x, y, pw, ph) = match parse_placement(position) {
        Placement::Preset(edge, align) => {
            let (lw, lh) = if collapsed { (STRIP_W, STRIP_H) } else { (PANEL_W, PANEL_H) };
            let pw = (lw * scale).round().max(1.0) as u32;
            let ph = (lh * scale).round().max(1.0) as u32;

            let (ax, ay, aw, ah) = placement_area(&m, edge);
            let x = match align {
                Align::Left => ax,
                Align::Centre => ax + (aw - pw as i32) / 2,
                Align::Right => ax + aw - pw as i32,
            };
            let y = match edge {
                Edge::Top => ay,
                Edge::Bottom => ay + ah - ph as i32 - (BOTTOM_GAP * scale).round() as i32,
            };

            // Wayland places a layer surface itself and ignores set_position, so
            // the anchor is how the island moves there. A no-op everywhere else.
            platform::set_layer_anchor(&win, edge, align);
            (x, y, pw, ph)
        }
        Placement::Free { fx, fy } => {
            // A floating island takes the work area whichever half it is in. It
            // is not pressed into a bezel, so there is nothing to be gained by
            // covering the taskbar and a row of pixels to lose if it does — and
            // a drop near enough an edge to want the bezel became a preset.
            let a = m.work_area();
            let (aw, ah) = (a.size.width as f64 / scale, a.size.height as f64 / scale);
            let g = free_geometry(fx, fy, aw, ah);

            // Folding away depends on whether there is an edge to fold into.
            //
            // Dropped along one, the island retracts into it and leaves the
            // invisible wake strip, exactly as a named corner does. Out in the
            // open there is no bezel to disappear behind, so it stays as the
            // resting pill where it was put — small enough that the window
            // still parks the cursor poll, and visible enough to find again
            // and pick up. The page decides the same way, in `drawMode`.
            let cx = g.win_x + g.off_x;
            let hugging = hug_of(fy, ah);
            let (lw, lh, lx, ly) = match (collapsed, hugging) {
                (false, _) => (PANEL_W, PANEL_H, g.win_x, g.win_y),
                (true, Some(edge)) => {
                    let y = if edge == Edge::Top { 0.0 } else { ah - STRIP_H };
                    (STRIP_W, STRIP_H, cx - STRIP_W / 2.0, y)
                }
                (true, None) => {
                    let top = if g.grow == Edge::Top { g.off_y } else { g.off_y - REST_H };
                    (REST_W, REST_H, cx - REST_W / 2.0, g.win_y + top)
                }
            };

            platform::set_layer_free(&win, lx, ly);
            (
                a.position.x + (lx * scale).round() as i32,
                a.position.y + (ly * scale).round() as i32,
                (lw * scale).round().max(1.0) as u32,
                (lh * scale).round().max(1.0) as u32,
            )
        }
    };

    // GTK never sizes a non-resizable window below its natural size (200 px
    // here), so on Linux the 6 px wake strip would stay a 200 px block. tao
    // re-applies the config's `resizable: false` after the first configure, so
    // this is asked every time, just before the resize. Undecorated, the window
    // still offers the user nothing to resize it by. (Found by @YossiYad, #44.)
    #[cfg(target_os = "linux")]
    let _ = win.set_resizable(true);
    let _ = win.set_size(PhysicalSize::new(pw, ph));
    let _ = win.set_position(PhysicalPosition::new(x, y));
    // Moving across displays can rescale the window: re-assert the physical size.
    let _ = win.set_size(PhysicalSize::new(pw, ph));
    let _ = win.set_always_on_top(true);
}

// ── Picking the island up ─────────────────────────────────────────────────────
//
// Holding the resting island unsticks it; from then on the window follows the
// pointer until the button comes up. On Windows the poll thread owns the move,
// for the reason written above `IslandRect`: it already reads the cursor and
// the button sixty times a second, and an IPC round trip per frame would show
// as the island lagging behind the pointer. Where there is no global cursor
// (Wayland) the page drives it instead, through `drag_island`.

/// Picks the island up.
///
/// Both points are in the window's own logical pixels: `centre` is the resting
/// island's centre as the page has drawn it, `pointer` is where the press
/// landed. Window coordinates rather than screen ones because that is what both
/// platforms can say without guessing — Windows reads them off the cursor poll,
/// Wayland off the DOM event — and the window origin here turns them into the
/// screen pixels the rest of the drag works in.
pub fn begin_drag(app: &AppHandle, gate: &PollGate, centre: (f64, f64), pointer: (f64, f64)) {
    let Some(win) = window(app) else { return };
    let Ok(origin) = win.outer_position() else { return };
    let scale = win.scale_factor().unwrap_or(1.0);
    *gate.drag.lock().unwrap() = Some(DragGrab {
        origin_x: origin.x,
        origin_y: origin.y,
        grab_x: (pointer.0 * scale).round() as i32,
        grab_y: (pointer.1 * scale).round() as i32,
        centre_x: centre.0,
        centre_y: centre.1,
    });
    // A picked-up island keeps the mouse wherever the pointer goes. Without
    // this the first frame that leaves the island shape would hand the drag to
    // whatever is underneath and the island would be dropped mid-air.
    set_ignore_cursor(app, false);
    gate.note_ignoring(false);
}

/// Moves a picked-up island so the grabbed point sits under `cursor`, in
/// physical screen pixels. The Windows path: the poll thread already has them.
pub fn drag_to(app: &AppHandle, gate: &PollGate, cursor: (f64, f64)) {
    let grab = { *gate.drag.lock().unwrap() };
    let Some(grab) = grab else { return };
    place_window(app, cursor.0.round() as i32 - grab.grab_x, cursor.1.round() as i32 - grab.grab_y);
}

/// Puts the window at a point in physical screen pixels, by whichever of the
/// two routes this system has: coordinates, or — on Wayland, where a layer
/// surface is placed by the compositor and `set_position` is ignored — margins
/// off the top-left of its output.
fn place_window(app: &AppHandle, x: i32, y: i32) {
    let Some(win) = window(app) else { return };
    let _ = win.set_position(PhysicalPosition::new(x, y));
    if let Some(m) = win.current_monitor().ok().flatten() {
        let a = m.work_area();
        let scale = m.scale_factor();
        platform::set_layer_free(
            &win,
            (x - a.position.x) as f64 / scale,
            (y - a.position.y) as f64 / scale,
        );
    }
}

/// Moves a picked-up island by how far the pointer has travelled since the
/// press, in logical pixels. The Wayland path, where there is no global cursor
/// to read: a delta, because the window keeps moving out from under the
/// pointer, so its own coordinates say nothing about where the hand went.
pub fn drag_by(app: &AppHandle, gate: &PollGate, dx: f64, dy: f64) {
    let grab = { *gate.drag.lock().unwrap() };
    let Some(grab) = grab else { return };
    let Some(win) = window(app) else { return };
    let scale = win.scale_factor().unwrap_or(1.0);
    place_window(
        app,
        grab.origin_x + (dx * scale).round() as i32,
        grab.origin_y + (dy * scale).round() as i32,
    );
}

/// Puts the island down: works out where it landed, writes it to the settings
/// and places the window there properly.
///
/// Dropping on another display switches `screen` to "cursor". The point is kept
/// as a fraction, so from then on the island shows up at the same spot on
/// whichever display the pointer is on — which is what dropping it over there
/// was asking for.
pub fn finish_drag(app: &AppHandle) {
    let Some(shared) = app.try_state::<crate::Shared>() else { return };
    let grab = { shared.gate.drag.lock().unwrap().take() };
    let Some(grab) = grab else { return };
    let Some(win) = window(app) else { return };
    let Ok(origin) = win.outer_position() else { return };
    let scale = win.scale_factor().unwrap_or(1.0);

    // Where the resting island ended up, in physical screen pixels.
    let cx = origin.x as f64 + grab.centre_x * scale;
    let cy = origin.y as f64 + grab.centre_y * scale;

    let Ok(monitors) = app.available_monitors() else { return };
    let Some(m) = monitors.iter().find(|m| monitor_contains(m, cx, cy)).cloned().or_else(|| {
        // Dropped in the gap between two displays, or off the end of one: keep
        // the island on the display it was already on rather than nowhere.
        let pref = shared.settings.lock().unwrap().screen.clone();
        target_monitor(app, &pref)
    }) else {
        return;
    };

    let a = m.work_area();
    let m_scale = m.scale_factor();
    let area_w = a.size.width as f64 / m_scale;
    let area_h = a.size.height as f64 / m_scale;
    let position = position_for_drop(
        (cx - a.position.x as f64) / m_scale,
        (cy - a.position.y as f64) / m_scale,
        area_w,
        area_h,
    );

    // Read before the write lock, never inside it: resolving the preference
    // goes back out to the monitor list, and this mutex is held all over.
    let pref = { shared.settings.lock().unwrap().screen.clone() };
    // Landed somewhere other than the display the preference points at: the
    // island is meant to be over there now, so let it follow the cursor.
    let moved_display = !same_monitor(app, &pref, &m);
    let settings = {
        let mut s = shared.settings.lock().unwrap();
        s.position = position;
        if moved_display {
            s.screen = "cursor".into();
        }
        s.clone()
    };
    if let Err(err) = crate::settings::save(&settings) {
        crate::log::line(format!("could not save the island's new place — {err}"));
    }
    let collapsed = shared.gate.collapsed.load(Ordering::Relaxed);
    apply_geometry(app, &settings.screen, &settings.position, collapsed);
    refresh_click_through(app, &shared.gate);
    let _ = app.emit("settings-changed", settings);
}

/// Whether the display the island was dropped on is the one `screen` already
/// means, so the preference is only rewritten when the drop really moved it.
fn same_monitor(app: &AppHandle, pref: &str, dropped: &Monitor) -> bool {
    match target_monitor(app, pref) {
        Some(m) => m.position() == dropped.position() && m.size() == dropped.size(),
        None => true,
    }
}

/// Position, size, work area and scale of the monitor the island lives on. Any
/// change here means the island has to be placed again — the work area included,
/// because a bottom-anchored island rests on the taskbar, so moving it, resizing
/// it or turning auto-hide on moves the island too.
type ScreenKey = (i32, i32, u32, u32, i32, i32, u32, u32, u64);

fn current_screen_key(app: &AppHandle) -> Option<ScreenKey> {
    let pref = app
        .try_state::<crate::Shared>()
        .map(|s| s.settings.lock().unwrap().screen.clone())
        .unwrap_or_else(|| "primary".into());
    let m = target_monitor(app, &pref)?;
    let p = m.position();
    let size = m.size();
    let a = m.work_area();
    Some((
        p.x,
        p.y,
        size.width,
        size.height,
        a.position.x,
        a.position.y,
        a.size.width,
        a.size.height,
        m.scale_factor().to_bits(),
    ))
}

/// Emits `cursor` (window-logical coordinates) at ~60 Hz while the island is
/// visible. Parked on a condvar the rest of the time.
pub fn spawn_cursor_poll(app: AppHandle, gate: Arc<PollGate>) {
    let started = std::thread::Builder::new().name("cursor-poll".into()).spawn(move || {
        let mut was_down = false;
        // Remembered across wakes so a display change while hidden is noticed the
        // moment the island comes back.
        let mut last_screen: Option<ScreenKey> = None;
        // Without a cursor to read (Linux) the loop only watches the display
        // layout, and twice a second is plenty for that: waking at 60 Hz just to
        // find no cursor costs CPU for nothing.
        let (period, screen_every) = if platform::CURSOR_POLL { (16, 30) } else { (500, 1) };
        loop {
            gate.wait_until_active();
            let mut last = (f64::MIN, f64::MIN);
            let mut ticks: u32 = 0;
            while gate.is_active() {
                std::thread::sleep(Duration::from_millis(period));

                // Monitors get plugged in, unplugged, rearranged and rescaled, and
                // an island pinned to coordinates that no longer exist is an island
                // nobody can reach. Checked about twice a second — the cursor poll
                // is already running, so this costs one monitor query.
                ticks = ticks.wrapping_add(1);
                if ticks % screen_every == 0 {
                    let now = current_screen_key(&app);
                    if now.is_some() && now != last_screen {
                        let first = last_screen.is_none();
                        last_screen = now;
                        if !first {
                            crate::log::line("display layout changed — repositioning".to_string());
                            // With the screen, not bare: a dropped point is a
                            // fraction of the work area, so the page cannot
                            // draw the island until it knows the new one.
                            let pref = app
                                .try_state::<crate::Shared>()
                                .map(|s| s.settings.lock().unwrap().screen.clone())
                                .unwrap_or_else(|| "primary".into());
                            let info = screen_info(&app, &pref);
                            let _ = app.emit_to(WINDOW_LABEL, "screen-changed", info);
                        }
                    }
                }

                let Some(win) = window(&app) else { continue };
                let Ok(origin) = win.outer_position() else { continue };
                let scale = win.scale_factor().unwrap_or(1.0);
                let Some((cx, cy)) = cursor_physical() else { continue };

                // A picked-up island follows the pointer from here, ahead of the
                // move filter below: a drag that creeps a pixel at a time is
                // still a drag, and it must not be the one thing that stutters.
                let dragging = { gate.drag.lock().unwrap().is_some() };
                if dragging {
                    if left_button_down() {
                        drag_to(&app, &gate, (cx, cy));
                        continue;
                    }
                    let handle = app.clone();
                    let _ = app.run_on_main_thread(move || finish_drag(&handle));
                    continue;
                }

                let x = (cx - origin.x as f64) / scale;
                let y = (cy - origin.y as f64) / scale;
                let size = match win.inner_size() {
                    Ok(s) => (s.width as f64 / scale, s.height as f64 / scale),
                    Err(_) => (PANEL_W, PANEL_H),
                };
                if (x - last.0).abs() < 1.0 && (y - last.1).abs() < 1.0 {
                    continue;
                }
                last = (x, y);

                // Click-through: the window only takes the mouse over the island
                // shape. A small entry margin means the flag is already off by the
                // time a moving cursor reaches a button.
                let r = *gate.rect.lock().unwrap();
                let on_island = r.w > 0.0
                    && x >= r.x - HIT_MARGIN
                    && x <= r.x + r.w + HIT_MARGIN
                    && y >= r.y - HIT_MARGIN
                    && y <= r.y + r.h + HIT_MARGIN;

                // A file being dragged has to be able to find us. WS_EX_TRANSPARENT
                // — what click-through is on Windows — hides the window from
                // WindowFromPoint, so OLE finds no drop target and shows the "no
                // drop" cursor. macOS has no such problem: AppKit delivers drags to
                // registered destinations whatever ignoresMouseEvents says. So while
                // a button is held anywhere over the panel, the whole panel takes
                // the mouse, which also makes the drop zone as forgiving as the Mac's.
                // A press may be the start of a drag: make sure the drop target is
                // ours before the file arrives.
                let down = left_button_down();
                if down && !was_down {
                    let handle = app.clone();
                    let _ = app.run_on_main_thread(move || platform::unblock_webview_drops(&handle));
                }
                was_down = down;

                let dragging = down
                    && x >= 0.0
                    && x <= size.0
                    && y >= 0.0
                    && y <= size.1;

                let accept = on_island || dragging;
                if gate.ignoring.load(Ordering::Relaxed) == accept {
                    gate.ignoring.store(!accept, Ordering::Relaxed);
                    let _ = win.set_ignore_cursor_events(!accept);
                }

                let _ = win.emit("cursor", CursorPayload { x, y });
            }
        }
    });
    if let Err(err) = started {
        crate::log::line(format!("thread cursor-poll failed to start — {err}"));
    }
}

/// Re-applies click-through after the window or the island changed shape.
///
/// With the cursor poll (Windows) the window takes the mouse again and the next
/// tick decides from the cursor. Without it (Linux) the input region is set to
/// the island itself, or to the whole wake strip while collapsed.
///
/// In standby neither hands the strip anything: the point of the mode is that
/// hovering the edge does nothing and only a message reopens the island.
pub fn refresh_click_through(app: &AppHandle, gate: &PollGate) {
    let asleep = gate.asleep();
    if platform::CURSOR_POLL {
        set_ignore_cursor(app, asleep);
        gate.note_ignoring(asleep);
        return;
    }
    let Some(win) = window(app) else { return };
    let region = if gate.collapsed.load(Ordering::Relaxed) {
        // The wake strip itself, never "the whole window": if the window ever
        // fails to shrink to the strip, the rest of it must not swallow clicks
        // meant for whatever sits under that edge of the screen. The collapsed
        // window *is* the strip, wherever it is anchored, so this stays right.
        if asleep {
            Some((0.0, 0.0, 0.0, 0.0))
        } else {
            Some((0.0, 0.0, STRIP_W, STRIP_H))
        }
    } else {
        let r = *gate.rect.lock().unwrap();
        if r.w <= 0.0 {
            // Nothing drawn yet: nothing takes the mouse.
            Some((0.0, 0.0, 0.0, 0.0))
        } else {
            let x0 = (r.x - HIT_MARGIN).max(0.0);
            let y0 = (r.y - HIT_MARGIN).max(0.0);
            let x1 = r.x + r.w + HIT_MARGIN;
            let y1 = r.y + r.h + HIT_MARGIN;
            Some((x0, y0, x1 - x0, y1 - y0))
        }
    };
    platform::set_input_region(&win, region);
}

pub fn set_ignore_cursor(app: &AppHandle, ignore: bool) {
    if let Some(win) = window(app) {
        let _ = win.set_ignore_cursor_events(ignore);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The third port of the anchor arithmetic.
    ///
    /// Swift and TypeScript are checked against each other by
    /// scripts/test-island-anchor.sh; this holds the same table so Rust cannot
    /// be the one that drifts. Where it does, the window goes one place and the
    /// page draws the island in another — an island that is not where it looks.
    mod anchor {
        use super::*;

        /// A 1080p screen with a 40 px taskbar, the same as the Swift suite.
        const AREA_W: f64 = 1920.0;
        const AREA_H: f64 = 1040.0;

        #[test]
        fn the_six_corners_still_snap() {
            for (x, y, want) in [
                (150.0, 16.0, "top-left"),
                (960.0, 16.0, "top-centre"),
                (1770.0, 16.0, "top-right"),
                (150.0, 1024.0, "bottom-left"),
                (960.0, 1024.0, "bottom-centre"),
                (1770.0, 1024.0, "bottom-right"),
            ] {
                assert_eq!(position_for_drop(x, y, AREA_W, AREA_H), want);
            }
        }

        #[test]
        fn the_open_field_stays_where_it_was_dropped() {
            assert_eq!(position_for_drop(700.0, 500.0, AREA_W, AREA_H), "free:0.3646,0.4808");
            assert_eq!(position_for_drop(1200.0, 900.0, AREA_W, AREA_H), "free:0.625,0.8654");
        }

        /// The thing the magnet must not do: snapping on the edge alone would
        /// quietly take away free placement along that edge.
        #[test]
        fn an_edge_alone_does_not_snap() {
            let p = position_for_drop(600.0, 16.0, AREA_W, AREA_H);
            assert_eq!(p, "free:0.3125,0.0154");
            assert_eq!(hug_of(0.0154, AREA_H), Some(Edge::Top));
        }

        #[test]
        fn a_point_from_a_newer_build_falls_back_rather_than_vanishing() {
            assert_eq!(parse_placement("free:banana"), Placement::Preset(Edge::Bottom, Align::Right));
            assert_eq!(parse_placement("free:2,-1"), Placement::Free { fx: 1.0, fy: 0.0 });
        }

        #[test]
        fn the_island_grows_away_from_the_half_it_was_dropped_in() {
            let high = free_geometry(0.5, 0.25, AREA_W, AREA_H);
            assert_eq!(high.grow, Edge::Top);
            assert_eq!(high.win_x, (1920.0 - PANEL_W) / 2.0);
            assert_eq!(high.win_x + high.off_x, 960.0);

            let low = free_geometry(0.5, 0.75, AREA_W, AREA_H);
            assert_eq!(low.grow, Edge::Bottom);
            assert_eq!(low.win_y + low.off_y - REST_H / 2.0, 0.75 * AREA_H);
        }

        /// A window pinned at the edge of the work area, never hanging off it.
        #[test]
        fn the_window_never_leaves_the_work_area() {
            assert_eq!(free_geometry(0.02, 0.5, AREA_W, AREA_H).win_x, 0.0);
            let right = free_geometry(0.98, 0.5, AREA_W, AREA_H);
            assert_eq!(right.win_x, AREA_W - PANEL_W);
        }
    }

    /// A 1080p screen with no taskbar, and a 474-tall card against one edge.
    const AREA: (i32, i32) = (0, 1080);

    #[test]
    fn a_page_hangs_off_the_far_side_of_the_card() {
        // Top-anchored: the card is at the top, so the page goes below it.
        let (y, h) = page_span(Edge::Top, (0, 474), AREA, 1.0).unwrap();
        assert_eq!(y, 474 + PAGE_GAP as i32);
        assert_eq!(h, PAGE_H as u32);

        // Bottom-anchored: there is nothing below, so it goes above — and ends
        // where the card begins, less the gap.
        let (y, h) = page_span(Edge::Bottom, (606, 1080), AREA, 1.0).unwrap();
        assert_eq!(y + h as i32, 606 - PAGE_GAP as i32);
        assert_eq!(h, PAGE_H as u32);
    }

    #[test]
    fn it_never_leaves_the_work_area() {
        // A card low down on a short screen: the page takes the room that is
        // left rather than running off the top.
        let (y, h) = page_span(Edge::Bottom, (400, 874), (0, 900), 1.0).unwrap();
        assert_eq!(y, 0);
        assert_eq!(h, (400 - PAGE_GAP as i32) as u32);

        // A work area that starts below zero — a taskbar at the top — is where
        // an off-by-one would put the page behind it.
        let (y, _) = page_span(Edge::Bottom, (900, 1040), (48, 1080), 1.0).unwrap();
        assert!(y >= 48);
    }

    #[test]
    fn too_little_room_is_no_page_at_all() {
        // Less than PAGE_MIN_H between the card and the far edge.
        assert!(page_span(Edge::Bottom, (200, 674), AREA, 1.0).is_none());
        assert!(page_span(Edge::Top, (0, 874), AREA, 1.0).is_none());
    }

    #[test]
    fn the_gap_and_the_floor_scale_with_the_display() {
        // At 200% everything doubles, the minimum included: a page that fits on
        // a 1080p screen does not fit in the same logical room at 2x.
        let (y, h) = page_span(Edge::Top, (0, 100), (0, 2160), 2.0).unwrap();
        assert_eq!(y, 100 + (PAGE_GAP * 2.0) as i32);
        assert_eq!(h, (PAGE_H * 2.0) as u32);
        assert!(page_span(Edge::Top, (0, 100), (0, 740), 2.0).is_none());
    }
}
