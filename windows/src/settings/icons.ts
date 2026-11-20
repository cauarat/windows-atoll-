// Inline SVG stand-ins for the SF Symbols the Mac Settings window draws. SF
// Symbols cannot ship on Windows, so each is redrawn here to read like the
// symbol at the size the Mac uses it (11pt semibold in a sidebar tile; the
// borderless glyph buttons and popup chevrons of the controls).
//
// Every glyph is drawn in a 24x24 box in `currentColor`, so a tile sets
// `color: #fff` and a borderless button inherits the secondary text colour.

const NS = "http://www.w3.org/2000/svg";

/** Holes need a mask, and a mask needs an id that no other copy shares. */
let maskSeq = 0;

type Draw = (mask: string) => string;

const STROKE = 'fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"';

/** Eight teeth around a ring, the hole punched by a mask. */
const gear: Draw = (m) => {
  const teeth = Array.from({ length: 8 }, (_, i) =>
    `<rect x="10.1" y="1.6" width="3.8" height="5.2" rx="1.1" transform="rotate(${i * 45} 12 12)"/>`).join("");
  return `<mask id="${m}"><rect width="24" height="24" fill="#fff"/><circle cx="12" cy="12" r="3.3" fill="#000"/></mask>`
    + `<g fill="currentColor" mask="url(#${m})"><circle cx="12" cy="12" r="7.6"/>${teeth}</g>`;
};

const SYMBOL_DRAW: Record<string, Draw> = {
  // ── Sidebar ──
  "gearshape.fill": gear,
  "square.grid.2x2.fill": () =>
    '<g fill="currentColor">'
    + '<rect x="3" y="3" width="8" height="8" rx="2.2"/><rect x="13" y="3" width="8" height="8" rx="2.2"/>'
    + '<rect x="3" y="13" width="8" height="8" rx="2.2"/><rect x="13" y="13" width="8" height="8" rx="2.2"/></g>',
  "capsule.fill": () =>
    '<rect x="1.5" y="6" width="21" height="12" rx="6" fill="currentColor"/>',
  "circle.grid.cross.fill": () =>
    '<g fill="currentColor">'
    + '<circle cx="12" cy="5.6" r="3.9"/><circle cx="5.6" cy="12" r="3.9"/>'
    + '<circle cx="18.4" cy="12" r="3.9"/><circle cx="12" cy="18.4" r="3.9"/></g>',
  "sparkles": () =>
    '<g fill="currentColor">'
    // The big four-pointed star, lower right, and a small one upper left.
    + '<path d="M14 5.5c.55 3.9 2.35 5.95 6.5 6.5-4.15.55-5.95 2.6-6.5 6.5-.55-3.9-2.35-5.95-6.5-6.5 4.15-.55 5.95-2.6 6.5-6.5z"/>'
    + '<path d="M6 2c.3 2 1.1 2.75 3 3-1.9.25-2.7 1-3 3-.3-2-1.1-2.75-3-3 1.9-.25 2.7-1 3-3z"/>'
    + '<path d="M6.5 15.5c.2 1.35.75 1.85 2 2-1.25.15-1.8.65-2 2-.2-1.35-.75-1.85-2-2 1.25-.15 1.8-.65 2-2z"/></g>',
  "bubble.left.and.bubble.right.fill": (m) =>
    `<mask id="${m}"><rect width="24" height="24" fill="#fff"/>`
    + '<path d="M9.2 9.6h9.6a3.2 3.2 0 0 1 3.2 3.2v4.1a3.2 3.2 0 0 1-3.2 3.2h-.4l.6 2.6-3.9-2.6h-2.7a3.2 3.2 0 0 1-3.2-3.2v-4.1a3.2 3.2 0 0 1 3.2-3.2z" fill="#000" stroke="#000" stroke-width="2.6"/></mask>'
    + `<g fill="currentColor"><path mask="url(#${m})" d="M5 3h9.4a3.2 3.2 0 0 1 3.2 3.2v4.4a3.2 3.2 0 0 1-3.2 3.2H8.6l-4.1 2.8.7-2.8H5a3.2 3.2 0 0 1-3.2-3.2V6.2A3.2 3.2 0 0 1 5 3z"/>`
    + '<path d="M9.6 10.4h9.2a2.6 2.6 0 0 1 2.6 2.6v3.8a2.6 2.6 0 0 1-2.6 2.6h-.9l.6 2.6-3.9-2.6H9.6A2.6 2.6 0 0 1 7 16.8V13a2.6 2.6 0 0 1 2.6-2.6z"/></g>',
  "puzzlepiece.extension.fill": () =>
    '<path fill="currentColor" d="M4.5 6.5h4a2.6 2.6 0 1 1 5.2 0h4a1.8 1.8 0 0 1 1.8 1.8v3.4a2.6 2.6 0 1 1 0 5.2v2.3a1.8 1.8 0 0 1-1.8 1.8H4.5a1.8 1.8 0 0 1-1.8-1.8v-3.6a2.4 2.4 0 1 0 0-4.8V8.3a1.8 1.8 0 0 1 1.8-1.8z"/>',
  "face.smiling.inverse": (m) =>
    `<mask id="${m}"><rect width="24" height="24" fill="#fff"/>`
    + '<ellipse cx="9" cy="10" rx="1.3" ry="1.7" fill="#000"/><ellipse cx="15" cy="10" rx="1.3" ry="1.7" fill="#000"/>'
    + '<path d="M7.8 14.2c1 1.6 2.5 2.4 4.2 2.4s3.2-.8 4.2-2.4" fill="none" stroke="#000" stroke-width="1.7" stroke-linecap="round"/></mask>'
    + `<circle cx="12" cy="12" r="9.6" fill="currentColor" mask="url(#${m})"/>`,
  "drop.fill": () =>
    '<path fill="currentColor" d="M12 2.2c-.5 0-.9.3-1.2.7C8.3 6.6 5.4 10.9 5.4 14.6a6.6 6.6 0 0 0 13.2 0c0-3.7-2.9-8-5.4-11.7-.3-.4-.7-.7-1.2-.7z"/>',

  // ── Controls ──
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

/** Every symbol name this module can draw. */
export const SYMBOL_NAMES: readonly string[] = Object.keys(SYMBOL_DRAW);

/**
 * An SF Symbol as an inline SVG, `size` px square, drawn in `currentColor`.
 * An unknown name draws nothing (an empty SVG of the same size), never throws.
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
// Two SF Symbols the panes draw beside text, in the Mac's own shape: each in
// the box AppKit gives the symbol at 96pt — measured with
// NSImage(systemSymbolName:) — and scaled to the point size asked for, so at
// 12pt calendar is 15x13 and phone.bubble.fill 16x14.4.

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
};

/**
 * `calendar` or `phone.bubble.fill` at `pointSize` (the Mac's
 * `.font(.system(size:))`), in `currentColor`, in the box AppKit draws it in.
 */
export function boxedSymbol(name: "calendar" | "phone.bubble.fill", pointSize: number): SVGSVGElement {
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
 * white on it — SettingsSidebarRow's Label icon.
 */
export function symbolTile(name: string, color: string): HTMLElement {
  const tile = document.createElement("span");
  tile.className = "sym-tile";
  tile.style.background = color;
  tile.append(symbol(name, 13));
  return tile;
}
