// Inline SVG stand-ins for the SF Symbols the Mac Settings window draws. SF
// Symbols cannot ship on Windows, so each is redrawn here to read like the
// symbol at the size the Mac uses it (in a sidebar tile; the borderless glyph
// buttons and popup chevrons of the controls).
//
// Every glyph is drawn in `currentColor`, so a tile sets `color: #fff` and a
// borderless button inherits the secondary text colour.

const NS = "http://www.w3.org/2000/svg";

/** Holes need a mask, and a mask needs an id that no other copy shares. */
let maskSeq = 0;

type Draw = (mask: string) => string;

const STROKE = 'fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"';

// ── Sidebar tiles ─────────────────────────────────────────────────────────────
//
// SettingsSidebarRow asks for 11pt semibold, but List(.sidebar) draws its
// icons larger, and not all by the same factor — the capsule is rounder than
// the bubbles are wide. So each glyph keeps the box its ink fills in the Mac
// captures (characters-light.png and hydration-dark.png agree to the quarter
// point, in Small, Medium and Large sidebar sizes alike): where it sits in the
// 20x20 tile and how big it is. Each is drawn so its ink spans its viewBox
// exactly.

interface TileGlyph {
  /** The ink's left and top in the tile, and its width and height, px. */
  ink: readonly [number, number, number, number];
  viewBox: string;
  draw: Draw;
}

/** A four-pointed star with concave sides — SparklesShape's, as views/icons.ts draws it. */
function star(cx: number, cy: number, rx: number, ry: number): string {
  const n = (v: number) => +v.toFixed(3);
  const wx = rx * 0.1;
  const wy = ry * 0.1;
  return `M${n(cx)} ${n(cy - ry)}Q${n(cx + wx)} ${n(cy - wy)} ${n(cx + rx)} ${n(cy)}`
    + `Q${n(cx + wx)} ${n(cy + wy)} ${n(cx)} ${n(cy + ry)}Q${n(cx - wx)} ${n(cy + wy)} ${n(cx - rx)} ${n(cy)}`
    + `Q${n(cx - wx)} ${n(cy - wy)} ${n(cx)} ${n(cy - ry)}Z`;
}

/** The two bubbles: the front one, outlined in the mask to part it from the back one. */
const FRONT_BUBBLE = "M8.05 2.65H14A2 2 0 0 1 16 4.65V8.5A2 2 0 0 1 14 10.5H13.55V11.9"
  + "C13.55 12.45 13.2 12.7 12.85 12.45L10.3 10.5H8.05A2 2 0 0 1 6.05 8.5V4.65A2 2 0 0 1 8.05 2.65Z";
const BACK_BUBBLE = "M2.2 0H9.75A2.2 2.2 0 0 1 11.95 2.2V7.1A2.2 2.2 0 0 1 9.75 9.3H6.05L3.5 11.35"
  + "C3.15 11.65 2.7 11.5 2.7 11V9.3H2.2A2.2 2.2 0 0 1 0 7.1V2.2A2.2 2.2 0 0 1 2.2 0Z";

const TILE_GLYPHS: Record<string, TileGlyph> = {
  // Eight rounded teeth around a ring, the hole punched by a mask.
  "gearshape.fill": {
    ink: [2.5, 3, 14.5, 14.5],
    viewBox: "1.6 1.6 20.8 20.8",
    draw: (m) => {
      const teeth = Array.from({ length: 8 }, (_, i) =>
        `<rect x="9.7" y="1.6" width="4.6" height="5.4" rx="1.1" transform="rotate(${i * 45} 12 12)"/>`).join("");
      return `<mask id="${m}"><rect width="24" height="24" fill="#fff"/><circle cx="12" cy="12" r="3.4" fill="#000"/></mask>`
        + `<g fill="currentColor" mask="url(#${m})"><circle cx="12" cy="12" r="7.9"/>${teeth}</g>`;
    },
  },
  "square.grid.2x2.fill": {
    ink: [3.5, 4, 12.5, 12.5],
    viewBox: "0 0 12.5 12.5",
    draw: () => '<g fill="currentColor">'
      + '<rect width="5.75" height="5.75" rx="1.5"/><rect x="6.75" width="5.75" height="5.75" rx="1.5"/>'
      + '<rect y="6.75" width="5.75" height="5.75" rx="1.5"/><rect x="6.75" y="6.75" width="5.75" height="5.75" rx="1.5"/></g>',
  },
  // Round ends, not a long pill: 17.5 across and 13 high.
  "capsule.fill": {
    ink: [1, 4, 17.5, 13],
    viewBox: "0 0 17.5 13",
    draw: () => '<rect width="17.5" height="13" rx="6.5" fill="currentColor"/>',
  },
  "circle.grid.cross.fill": {
    ink: [2, 2.5, 16, 16],
    viewBox: "1.7 1.7 20.6 20.6",
    draw: () => '<g fill="currentColor">'
      + '<circle cx="12" cy="5.6" r="3.9"/><circle cx="5.6" cy="12" r="3.9"/>'
      + '<circle cx="18.4" cy="12" r="3.9"/><circle cx="12" cy="18.4" r="3.9"/></g>',
  },
  // A big star low on the right, a middling one on the left, a small one on top.
  "sparkles": {
    ink: [4, 3.5, 11.5, 14],
    viewBox: "0 0 10.2 12.4",
    draw: () => `<path fill="currentColor" d="${star(5.9, 8.2, 4.3, 4.2)}${star(2.1, 4.3, 2, 2.05)}${star(4.72, 1.45, 1, 1.45)}"/>`,
  },
  // The back bubble's tail down on the left, the front one's down on the right.
  "bubble.left.and.bubble.right.fill": {
    ink: [0, 2, 19.5, 15.5],
    viewBox: "0 0 16 12.55",
    draw: (m) => `<mask id="${m}"><rect x="-1" y="-1" width="18" height="15" fill="#fff"/>`
      + `<path d="${FRONT_BUBBLE}" fill="#000" stroke="#000" stroke-width="1.7" stroke-linejoin="round"/></mask>`
      + `<g fill="currentColor"><path mask="url(#${m})" d="${BACK_BUBBLE}"/><path d="${FRONT_BUBBLE}"/></g>`,
  },
  // A knob out on the right, a socket cut into the left, the top edge plain.
  "puzzlepiece.extension.fill": {
    ink: [2, 4, 16.5, 13],
    viewBox: "0 0 13 10.65",
    draw: (m) => `<mask id="${m}"><rect x="-1" y="-1" width="15" height="12.65" fill="#fff"/>`
      + '<circle cx="2.43" cy="5.3" r="1.44" fill="#000"/><rect x="-1" y="4.65" width="3.43" height="1.3" fill="#000"/></mask>'
      + `<g fill="currentColor" mask="url(#${m})"><rect width="10.1" height="10.65" rx="1.7"/>`
      + '<circle cx="11.25" cy="5.35" r="1.75"/></g>',
  },
  // A disc with two round eyes and a short smile cut out of it.
  "face.smiling.inverse": {
    ink: [3, 3.5, 14, 14],
    viewBox: "0 0 14 14",
    draw: (m) => `<mask id="${m}"><rect width="14" height="14" fill="#fff"/>`
      + '<circle cx="4.9" cy="5" r="0.75" fill="#000"/><circle cx="9.1" cy="5" r="0.75" fill="#000"/>'
      + '<path d="M4.95 9Q7 10.7 9.05 9" fill="none" stroke="#000" stroke-width="1" stroke-linecap="round"/></mask>'
      + `<circle cx="7" cy="7" r="7" fill="currentColor" mask="url(#${m})"/>`,
  },
  // Six rounded bars, low, tall, tallest, middling, tall, low: SF Symbols'
  // waveform measured at 96pt (bars 7.5 wide every 15.85, heights 22, 61, 99,
  // 49.25, 78, 30), and its ink in the Dictation tile of a Mac capture.
  "waveform": {
    ink: [3.5, 3, 12.5, 14.5],
    viewBox: "12 8 86.75 99",
    draw: () => '<g fill="currentColor">'
      + '<rect x="12" y="46.5" width="7.5" height="22" rx="3.75"/>'
      + '<rect x="27.75" y="27" width="7.75" height="61" rx="3.75"/>'
      + '<rect x="43.75" y="8" width="7.5" height="99" rx="3.75"/>'
      + '<rect x="59.5" y="33" width="7.5" height="49.25" rx="3.75"/>'
      + '<rect x="75.5" y="18.5" width="7.5" height="78" rx="3.75"/>'
      + '<rect x="91.25" y="42.5" width="7.5" height="30" rx="3.75"/></g>',
  },
  "drop.fill": {
    ink: [5, 3.5, 9.5, 14],
    viewBox: "5.4 2.2 13.2 19",
    draw: () => '<path fill="currentColor" d="M12 2.2c-.5 0-.9.3-1.2.7C8.3 6.6 5.4 10.9 5.4 14.6a6.6 6.6 0 0 0 13.2 0c0-3.7-2.9-8-5.4-11.7-.3-.4-.7-.7-1.2-.7z"/>',
  },
};

// ── Controls ──────────────────────────────────────────────────────────────────
//
// In a 24x24 box, drawn at whatever size the control asks for.

const SYMBOL_DRAW: Record<string, Draw> = {
  // Sized against island-layout-light.png and island-content-dark.png: at 13px
  // the chevrons span 11x6 and minus.circle 13, as the ring editor's do; at 12
  // the stepper's chevrons are its 11px; at 11 the plus is "+ Add"'s.
  "chevron.up": () => `<path ${STROKE} stroke-width="2.2" d="M2.6 16.2l9.4-9.4 9.4 9.4"/>`,
  "chevron.down": () => `<path ${STROKE} stroke-width="2.2" d="M2.6 7.8l9.4 9.4 9.4-9.4"/>`,
  "chevron.up.chevron.down": () =>
    `<path ${STROKE} stroke-width="2.2" d="M8 9.5l4-4 4 4M8 14.5l4 4 4-4"/>`,
  "minus.circle": () =>
    `<circle cx="12" cy="12" r="10.9" ${STROKE} stroke-width="1.9"/><path ${STROKE} stroke-width="2" d="M5.6 12h12.8"/>`,
  "plus": () => `<path ${STROKE} stroke-width="2.4" d="M12 2.6v18.8M2.6 12h18.8"/>`,
  "checkmark": () => `<path ${STROKE} stroke-width="3" d="M5 12.5l4.5 4.5L19 7"/>`,
};

/** Every symbol name this module can draw: the sidebar's tiles, then the controls' glyphs. */
export const SYMBOL_NAMES: readonly string[] = [...Object.keys(TILE_GLYPHS), ...Object.keys(SYMBOL_DRAW)];

/**
 * A control's SF Symbol as an inline SVG, `size` px square, drawn in
 * `currentColor`. An unknown name draws nothing (an empty SVG of the same
 * size), never throws.
 */
export function symbol(name: string, size = 12): SVGSVGElement {
  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("width", String(size));
  svg.setAttribute("height", String(size));
  svg.setAttribute("aria-hidden", "true");
  svg.setAttribute("class", "sym");
  const draw = SYMBOL_DRAW[name];
  if (draw) svg.innerHTML = draw(`sym-mask-${++maskSeq}`);
  return svg;
}

// ── Symbols that are not square ──────────────────────────────────────────────
//
// SF Symbols the panes draw beside text, in the Mac's own shape: each in the
// box AppKit gives the symbol at 96pt — measured with
// NSImage(systemSymbolName:) — and scaled to the point size asked for, so at
// 12pt calendar is 15x13 and phone.bubble.fill 16x14.4, and at 11pt music.note
// is 9.4x12.8.

const BOXED: Record<string, { w: number; h: number; body: () => string }> = {
  /** A rounded page with its top band filled, and ten dots in three rows. */
  "calendar": {
    w: 118,
    h: 104,
    body: () => {
      const dots = [
        [50.5, 43], [66, 43], [82, 43],
        [35, 59], [50.5, 59], [66, 59], [82, 59],
        [35, 74.5], [50.5, 74.5], [66, 74.5],
      ].map(([x, y]) => `<circle cx="${x}" cy="${y}" r="3.5"/>`).join("");
      return '<g fill="currentColor"><path fill-rule="evenodd" d="'
        + "M26 9H91A14 14 0 0 1 105 23V82A14 14 0 0 1 91 96H26A14 14 0 0 1 12 82V23A14 14 0 0 1 26 9Z"
        + "M25.5 29.5H91.5A6 6 0 0 1 97.5 35.5V81.5A6 6 0 0 1 91.5 87.5H25.5A6 6 0 0 1 19.5 81.5"
        + `V35.5A6 6 0 0 1 25.5 29.5Z"/>${dots}</g>`;
    },
  },
  /** A rounded bubble, its tail down on the left, a handset cut out of it. */
  "phone.bubble.fill": {
    w: 128,
    h: 115,
    body: () => '<path fill="currentColor" fill-rule="evenodd" d="'
      // The bubble and its tail.
      + "M28 9H99A16 16 0 0 1 115 25V72A16 16 0 0 1 99 88H62L44.6 105.4"
      + "C42.4 107.6 38.4 107.4 36.8 105.6C36.2 104.9 36 104 36 103V88H28"
      + "A16 16 0 0 1 12 72V25A16 16 0 0 1 28 9Z"
      // The handset: earpiece top left, mouthpiece bottom right.
      + "M46 23.6C48.5 23.2 50.8 24.6 52.4 27L55.6 32C57.1 34.4 56.9 37 55.2 39.2L52.8 43.2"
      + "C53.6 47.5 59 54.2 66.6 58.4L69.6 56.6C72.6 54.8 77.4 54.8 80.4 56.6L84.6 59.6"
      + "C87.8 62 88.2 66.4 85.4 69.4L82.6 71.8C80 74 75.2 74 70.6 72.2"
      + "C59.8 68.4 46.4 56.6 40.6 44.6C38.4 40 38.4 33.4 40 29.8L41.4 27.2"
      + 'C42.6 25 44.2 23.9 46 23.6Z"/>',
  },
  /** One eighth note: the head low on the left, its stem, a flag rising to the right. */
  "music.note": {
    w: 82,
    h: 112,
    body: () => '<g fill="currentColor">'
      + '<path d="M36 18.4C36 16.8 37 15.6 38.6 15.2L63.4 9C66.4 8.3 69 10.2 69 13.2V28.6'
      + 'C69 30.9 67.7 32.6 65.4 33.2L42.4 39V88H36Z"/>'
      + '<ellipse cx="27.2" cy="88.6" rx="15.4" ry="13.2" transform="rotate(-18 27.2 88.6)"/></g>',
  },
};

/**
 * `calendar`, `phone.bubble.fill` or `music.note` at `pointSize` (the Mac's
 * `.font(.system(size:))`), in `currentColor`, in the box AppKit draws it in.
 */
export function boxedSymbol(
  name: "calendar" | "phone.bubble.fill" | "music.note", pointSize: number,
): SVGSVGElement {
  const { w, h, body } = BOXED[name];
  const scale = pointSize / 96;
  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
  svg.setAttribute("width", String(w * scale));
  svg.setAttribute("height", String(h * scale));
  svg.setAttribute("aria-hidden", "true");
  svg.innerHTML = body();
  return svg;
}

/**
 * The sidebar's icon: a `color` tile, 20x20 with a 5px radius, the symbol in
 * white on it, where and as big as the Mac draws it — SettingsSidebarRow's
 * Label icon. An unknown name is a bare tile.
 */
export function symbolTile(name: string, color: string): HTMLElement {
  const tile = document.createElement("span");
  tile.className = "sym-tile";
  tile.style.background = color;
  const glyph = TILE_GLYPHS[name];
  if (glyph) {
    const [x, y, w, h] = glyph.ink;
    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", glyph.viewBox);
    svg.setAttribute("width", String(w));
    svg.setAttribute("height", String(h));
    // The box is the Mac's ink; a drawing a hair off its proportions meets it
    // rather than falling short of it on one side.
    svg.setAttribute("preserveAspectRatio", "none");
    svg.setAttribute("aria-hidden", "true");
    svg.style.left = `${x}px`;
    svg.style.top = `${y}px`;
    svg.innerHTML = glyph.draw(`sym-mask-${++maskSeq}`);
    tile.append(svg);
  }
  return tile;
}
