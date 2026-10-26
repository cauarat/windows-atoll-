// Where the island sits on screen, and what that means inside the window.
//
// Rust places the window against the chosen edge of the display (see
// island.rs); this decides where the island is drawn inside it, which way it
// grows, and which corners are square. The two halves have to agree: the rect
// pushed back to Rust is what decides click-through.
//
// Two kinds of position live here. Six names put the island against an edge,
// which is what Settings offers. A dropped point puts it anywhere — see
// "Free placement" below. `anchorFor` turns either into the one shape the rest
// of the island reads, so nothing downstream has to know which it was given.

export type IslandPosition =
  | "top-left"
  | "top-centre"
  | "top-right"
  | "bottom-left"
  | "bottom-centre"
  | "bottom-right";

/** Next to the clock, where the notifications already are. */
export const DEFAULT_POSITION: IslandPosition = "bottom-right";

export const POSITIONS: ReadonlyArray<readonly [IslandPosition, string]> = [
  ["top-left", "Top left"],
  ["top-centre", "Top centre"],
  ["top-right", "Top right"],
  ["bottom-left", "Bottom left"],
  ["bottom-centre", "Bottom centre"],
  ["bottom-right", "Bottom right"],
];

export type Edge = "top" | "bottom";
export type Align = "left" | "centre" | "right";

/** Mirrors `island::parse_position`: anything unknown falls back to the default. */
export function edgeOf(p: string): Edge {
  return p.startsWith("top-") ? "top" : "bottom";
}

export function alignOf(p: string): Align {
  if (p.endsWith("-left")) return "left";
  // Both spellings, so a hand-edited settings.json still works.
  if (p.endsWith("-centre") || p.endsWith("-center")) return "centre";
  return "right";
}

// ── Free placement ────────────────────────────────────────────────────────────
//
// A list of six is a poor answer to "put Mochi there". Holding the resting
// island for two seconds unsticks it, and where it is dropped is kept as a
// *fraction* of the display's work area rather than as pixels.
//
// Fractions, because of what they do across displays: the same pair on a screen
// of another size or another scale is the same place, so the island reappears
// where it was put on whichever display the cursor is on. Pixels would need one
// position per monitor and would land somewhere else the moment one is resized.
//
// The stored string stays a single field — `free:0.734,0.882` — because
// `parse_position` and `edgeOf` already fall back to the default on anything
// they do not recognise. An older build reading a dropped point lands in the
// bottom-right corner instead of losing the island.

/** Prefix that tells a dropped point from one of the six names. */
export const FREE_PREFIX = "free:";

/**
 * How near an edge a drop still counts as *on* that edge, in logical px.
 *
 * Inside it the island hugs the edge the way it always has — square corners
 * bleeding into the bezel, growing out of it, clear of the taskbar. That look
 * is most of what the island is, so it is worth a band this wide to land on.
 */
export const MAGNET = 48;

/**
 * The two sizes the free arithmetic needs, so the same rules can answer for a
 * Mac as well: there the resting island is the notch, which every display
 * measures for itself, and the panel is its own size.
 */
export interface Metrics {
  restW: number;
  restH: number;
  panelW: number;
  panelH: number;
}

/**
 * The PC island's own numbers — `COMPACT_W`, `NOTCH_H`, `PANEL_W`, `PANEL_H` in
 * core/layout.ts. Passed in rather than imported: this file is compiled on its
 * own by the parity suite, and the Mac's resting island is the notch, which
 * every display measures for itself.
 */
export const METRICS: Metrics = { restW: 288, restH: 32, panelW: 760, panelH: 620 };

/** Where a dropped island rests: its centre, as a fraction of the work area. */
export interface FreePoint {
  fx: number;
  fy: number;
}

export function isFree(p: string): boolean {
  return p.startsWith(FREE_PREFIX);
}

function clamp(n: number, lo: number, hi: number): number {
  return n < lo ? lo : n > hi ? hi : n;
}

function clamp01(n: number): number {
  return clamp(n, 0, 1);
}

/** `free:0.734,0.882` → the point. Anything malformed reads as not-free. */
export function parseFree(p: string): FreePoint | null {
  if (!isFree(p)) return null;
  const parts = p.slice(FREE_PREFIX.length).split(",");
  if (parts.length !== 2) return null;
  const fx = Number(parts[0]);
  const fy = Number(parts[1]);
  if (!Number.isFinite(fx) || !Number.isFinite(fy)) return null;
  return { fx: clamp01(fx), fy: clamp01(fy) };
}

/** Four decimals: a pixel on an 8K display, and short enough to read in a file. */
export function formatFree(fx: number, fy: number): string {
  const r = (n: number) => String(Math.round(clamp01(n) * 10_000) / 10_000);
  return `${FREE_PREFIX}${r(fx)},${r(fy)}`;
}

/**
 * The edge a free point is near enough to hug, or null out in the open.
 *
 * Kept apart from `nearestPreset` on purpose: an island dropped along the top
 * edge but nowhere near left, centre or right is still a free island — it just
 * hugs the edge while it is there instead of floating a hair below it.
 */
export function hugOf(
  fy: number, areaH: number, m: Metrics = METRICS, magnet = MAGNET,
): Edge | null {
  const y = fy * areaH;
  if (y - m.restH / 2 <= magnet) return "top";
  if (areaH - (y + m.restH / 2) <= magnet) return "bottom";
  return null;
}

/**
 * The preset a drop lands on, or null to keep it free.
 *
 * Both axes have to agree. Snapping on the edge alone would quietly take away
 * free placement along that edge, which is the thing being added.
 */
export function nearestPreset(
  fx: number, fy: number, areaW: number, areaH: number,
  m: Metrics = METRICS, magnet = MAGNET,
): IslandPosition | null {
  const edge = hugOf(fy, areaH, m, magnet);
  if (edge == null) return null;
  const x = fx * areaW;
  let align: Align | null = null;
  if (x - m.restW / 2 <= magnet) align = "left";
  else if (areaW - (x + m.restW / 2) <= magnet) align = "right";
  else if (Math.abs(x - areaW / 2) <= magnet) align = "centre";
  if (align == null) return null;
  return `${edge}-${align}` as IslandPosition;
}

/**
 * What a drop at `cx`, `cy` — the island's resting centre, in work-area logical
 * pixels — should be stored as: one of the six names when it lands on one, else
 * the point itself.
 */
export function positionForDrop(
  cx: number, cy: number, areaW: number, areaH: number,
  m: Metrics = METRICS, magnet = MAGNET,
): string {
  const fx = areaW > 0 ? cx / areaW : 0.5;
  const fy = areaH > 0 ? cy / areaH : 0.5;
  return nearestPreset(fx, fy, areaW, areaH, m, magnet) ?? formatFree(fx, fy);
}

/** Window origin and island offsets for a dropped point, in work-area pixels. */
export interface FreeGeometry {
  /** Window origin inside the work area. Rust adds the area's own origin. */
  winX: number;
  winY: number;
  /** The island's resting centre x, inside the window. */
  offX: number;
  /** The island's anchored edge y, inside the window. */
  offY: number;
  /** Which of the island's own edges is pinned: "top" grows down, "bottom" up. */
  grow: Edge;
}

/**
 * The whole of free placement, as one pure function — because Rust mirrors it
 * in `island::free_geometry` and the two have to land on the same pixel.
 *
 * The island grows away from the half it was dropped in, so a point near the
 * bottom unfolds upward into the room that is there rather than off the screen.
 * The window is clamped to the work area; the island is then clamped inside the
 * window by `islandX`/`islandY`, which is what makes a wide view slide inward
 * near an edge instead of hanging off it.
 */
export function freeGeometry(
  fx: number, fy: number, areaW: number, areaH: number, m: Metrics = METRICS,
): FreeGeometry {
  const halfW = m.restW / 2;
  const halfH = m.restH / 2;
  const cx = clamp(fx * areaW, halfW, Math.max(halfW, areaW - halfW));
  const cy = clamp(fy * areaH, halfH, Math.max(halfH, areaH - halfH));
  const grow: Edge = cy < areaH / 2 ? "top" : "bottom";
  const edgeY = grow === "top" ? cy - halfH : cy + halfH;
  const winX = fitWindow(cx - m.panelW / 2, areaW, m.panelW);
  const winY = fitWindow(grow === "top" ? edgeY : edgeY - m.panelH, areaH, m.panelH);
  return { winX, winY, offX: cx - winX, offY: edgeY - winY, grow };
}

/** A window larger than the display pins to the near corner rather than drifting. */
function fitWindow(v: number, area: number, size: number): number {
  return size >= area ? 0 : clamp(v, 0, area - size);
}

// ── What the island reads ─────────────────────────────────────────────────────

/** A position resolved against a display: the one shape the island draws from. */
export interface IslandAnchor {
  /** The island's own pinned edge. "top" grows down, "bottom" grows up. */
  edge: Edge;
  align: Align;
  /** The screen edge it is pressed against, or null when it floats free. */
  hug: Edge | null;
  /** Set for a dropped point; null for one of the six names. */
  free: FreeGeometry | null;
}

/**
 * Resolves a stored position against the work area it will be placed in.
 *
 * `areaW`/`areaH` are only read for a dropped point, so the six names still
 * answer before the first `ScreenInfo` arrives.
 */
export function anchorFor(
  p: string, areaW: number, areaH: number, m: Metrics = METRICS,
): IslandAnchor {
  const pt = parseFree(p);
  if (pt == null) {
    const edge = edgeOf(p);
    return { edge, align: alignOf(p), hug: edge, free: null };
  }
  const free = freeGeometry(pt.fx, pt.fy, areaW, areaH, m);
  return { edge: free.grow, align: "centre", hug: hugOf(pt.fy, areaH, m), free };
}

/** Island x inside the window, for an island `w` wide. */
/**
 * Where the island is drawn inside the window, given whether that window *is*
 * the resting bar — see `foldFor` in core/fold.ts, and `Fold::Bar` in island.rs.
 *
 * A boolean rather than the fold itself so this file goes on importing nothing:
 * it is compiled on its own by the parity suite.
 *
 * "Is", not "is about to be". The window and the island's offsets inside it
 * change in opposite directions — the bar's 0,0 is the very screen pixel the
 * panel's offsets land the island on — and the resize is an IPC round trip
 * away, so for its length only one of the two pairs is right.
 */
export function islandOrigin(
  a: IslandAnchor,
  windowIsBar: boolean,
  w: number,
  h: number,
): { x: number; y: number } {
  // The window is the bar, so the island fills it and there is nothing left to
  // place it inside. Anywhere else it takes its anchor within the panel's
  // frame — the wake strip included, where the island has retracted to nothing
  // and those offsets land outside the window, which is as invisible as a
  // retracted island is meant to be.
  if (windowIsBar) return { x: 0, y: 0 };
  return { x: islandX(a, w), y: islandY(a, h) };
}

export function islandX(a: IslandAnchor, w: number, m: Metrics = METRICS): number {
  if (a.free) return clamp(a.free.offX - w / 2, 0, Math.max(0, m.panelW - w));
  switch (a.align) {
    case "left":
      return 0;
    case "centre":
      return (m.panelW - w) / 2;
    case "right":
      return m.panelW - w;
  }
}

/**
 * Island y inside the window, for an island `h` tall.
 *
 * At the bottom this is rewritten on every animation frame as `h` changes, which
 * is what makes the island grow upward out of the edge and retract back into it.
 */
export function islandY(a: IslandAnchor, h: number, m: Metrics = METRICS): number {
  if (a.free) {
    const y = a.edge === "top" ? a.free.offY : a.free.offY - h;
    return clamp(y, 0, Math.max(0, m.panelH - h));
  }
  return a.edge === "top" ? 0 : m.panelH - h;
}

/**
 * Square against the edge it retracts into, rounded on the other side — and
 * rounded the whole way round once it is out in the open, where there is no
 * bezel for a square corner to disappear into.
 */
export function radiusCss(a: IslandAnchor, r: number): string {
  if (a.hug == null) return `${r}px`;
  return a.hug === "top" ? `0 0 ${r}px ${r}px` : `${r}px ${r}px 0 0`;
}
