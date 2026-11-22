// SVG paths standing in for the SF Symbols used by the macOS island.
// Drawn on a 24×24 grid so they read at the same optical size.
//
// The island header's symbols — house.fill, doc.on.clipboard,
// square.grid.2x2, globe, calendar, drop.fill, timer, gearshape,
// speaker.wave.2, speaker.slash and the header's xmark — are drawn from the
// Mac's own render of each at the header's size (13 pt, regular; gearshape
// and the speaker 14 pt), measured offscreen at 16x: the ink box, every
// stroke's weight, the radii, the gear's eight teeth. They are built from
// those numbers out of lines and arcs, not traced, and their ink sits where
// the Mac's sits in its frame — the frame's centre is the grid's. Each fills
// without holes going wrong under the non-zero rule, so `svg()` draws them
// as they are, and the ring and Settings, which draw some of them too, get
// the Mac's shape at their own sizes.
//
// HEADER_PX, below, is the box each has to be drawn in for its ink to
// measure what the Mac's does in the header.

export const ICONS = {
  // house.fill: the roof a stroke on its own with a chimney on its right
  // slope, the house below it filled, the door cut out of it.
  house: "M12.76 2.78l9.48 7.92a.76.76 0 0 1 .1 1.06a.76.76 0 0 1-1.07.1L11.79 3.94a.05.05 0 0 0-.06 0L2.24 11.86a.76.76 0 0 1-1.06-.1a.76.76 0 0 1 .09-1.06l9.49-7.92a1.57 1.57 0 0 1 2 0zM19.88 5.06v4.65l-2.27-1.9V5.06a.61.61 0 0 1 .61-.61h1.05a.61.61 0 0 1 .61.61zM19.71 12.38v7.14a1.85 1.85 0 0 1-1.85 1.85H5.66a1.85 1.85 0 0 1-1.85-1.85v-7.14a.43.43 0 0 1 .15-.32l7.25-6.05a.85.85 0 0 1 1.09 0l7.25 6.05a.43.43 0 0 1 .16.32zM14.19 19.69v-5.33a.43.43 0 0 0-.43-.43H9.74a.43.43 0 0 0-.42.43v5.33a.21.21 0 0 0 .21.22h4.44a.21.21 0 0 0 .22-.22z",
  // The chat tab's mark: a bubble with sparkles, the same drawing as
  // NotchBuddy/Sources/App/ChatSparkleIcon.swift, which is where it is
  // maintained — this is that shape flattened onto the 24 grid. Drawn 16 px
  // rather than 13 like the symbols beside it, because three of its four
  // corners are the sparkle hanging off the top right.
  chatSparkle: "M15.98 4.29C15.82 4.35 15.65 4.39 15.5 4.39C14.64 4.39 14.04 5.06 14.04 5.85C14.04 6.59 14.56 7.23 15.34 7.3L15.5 7.31C16.51 7.31 17.98 8.78 17.98 9.79C17.98 10.65 18.65 11.25 19.44 11.25C19.83 11.25 20.19 11.1 20.46 10.85L20.46 14.64C20.46 16.01 20.46 16.7 20.23 17.44C19.93 18.25 19.3 18.88 18.49 19.18C17.75 19.41 17.06 19.41 15.69 19.41L9.78 19.41L6.32 22.53C6.17 22.67 5.97 22.74 5.76 22.74C5.3 22.74 4.92 22.37 4.92 21.9L4.92 19.41L4.77 19.41C3.4 19.41 2.71 19.41 1.97 19.18C1.16 18.88 0.53 18.25 0.23 17.44C0 16.7 0 16.01 0 14.64L0 9.06C0 7.69 0 7 0.23 6.26C0.53 5.45 1.16 4.82 1.97 4.52C2.71 4.29 3.4 4.29 4.77 4.29L15.69 4.29C15.79 4.29 15.89 4.29 15.98 4.29ZM9.73 8.3C9.73 9.56 8.15 11.14 6.89 11.14C6.26 11.14 6.26 12.08 6.89 12.08C8.15 12.08 9.73 13.66 9.73 14.92C9.73 15.55 10.67 15.55 10.67 14.92C10.67 13.66 12.25 12.08 13.51 12.08C14.14 12.08 14.14 11.14 13.51 11.14C12.25 11.14 10.67 9.56 10.67 8.3C10.67 7.67 9.73 7.67 9.73 8.3ZM20 1.91C20 3.41 21.88 5.29 23.38 5.29C24.13 5.29 24.13 6.41 23.38 6.41C21.88 6.41 20 8.29 20 9.79C20 10.54 18.88 10.54 18.88 9.79C18.88 8.29 17 6.41 15.5 6.41C14.75 6.41 14.75 5.29 15.5 5.29C17 5.29 18.88 3.41 18.88 1.91C18.88 1.16 20 1.16 20 1.91Z",
  // plus
  plus: "M11 4h2v7h7v2h-7v7h-2v-7H4v-2h7V4z",
  // square.grid.2x2: four rounded squares, outlined.
  grid: "M10.74 3.07v5.61a2.07 2.07 0 0 1-2.07 2.07H3.06A2.07 2.07 0 0 1 .99 8.68V3.07A2.07 2.07 0 0 1 3.06 1h5.61a2.07 2.07 0 0 1 2.07 2.07zM3.06 9.12h5.61a.44.44 0 0 0 .44-.44V3.07a.44.44 0 0 0-.44-.44H3.06a.44.44 0 0 0-.44.44v5.61a.44.44 0 0 0 .44.44zM10.74 14.75v5.61a2.07 2.07 0 0 1-2.07 2.07H3.06A2.07 2.07 0 0 1 .99 20.36v-5.61a2.07 2.07 0 0 1 2.07-2.07h5.61a2.07 2.07 0 0 1 2.07 2.07zM3.06 20.8h5.61a.44.44 0 0 0 .44-.44v-5.61a.44.44 0 0 0-.44-.44H3.06a.44.44 0 0 0-.44.44v5.61a.44.44 0 0 0 .44.44zM22.42 3.07v5.61a2.07 2.07 0 0 1-2.07 2.07h-5.61a2.07 2.07 0 0 1-2.07-2.07V3.07A2.07 2.07 0 0 1 14.74 1h5.61a2.07 2.07 0 0 1 2.07 2.07zM14.74 9.12h5.61a.44.44 0 0 0 .44-.44V3.07a.44.44 0 0 0-.44-.44h-5.61a.44.44 0 0 0-.44.44v5.61a.44.44 0 0 0 .44.44zM22.42 14.75v5.61a2.07 2.07 0 0 1-2.07 2.07h-5.61a2.07 2.07 0 0 1-2.07-2.07v-5.61a2.07 2.07 0 0 1 2.07-2.07h5.61a2.07 2.07 0 0 1 2.07 2.07zM14.74 20.8h5.61a.44.44 0 0 0 .44-.44v-5.61a.44.44 0 0 0-.44-.44h-5.61a.44.44 0 0 0-.44.44v5.61a.44.44 0 0 0 .44.44z",
  heart: "M12 20.3l-1.45-1.32C5.4 14.33 2 11.25 2 7.5 2 4.72 4.2 2.6 7 2.6c1.57 0 3.08.73 4 1.88a5.27 5.27 0 0 1 4-1.88c2.8 0 5 2.12 5 4.9 0 3.75-3.4 6.83-8.55 11.49L12 20.3z",
  search: "M10.5 3.2a7.3 7.3 0 1 0 4.42 13.1l4.39 4.4 1.49-1.5-4.4-4.38A7.3 7.3 0 0 0 10.5 3.2zm0 2a5.3 5.3 0 1 1 0 10.6 5.3 5.3 0 0 1 0-10.6z",
  trash: "M9.5 3h5l.8 1.4H19v1.8H5V4.4h3.7L9.5 3zM6.4 7.6h11.2l-.9 12.1a1.4 1.4 0 0 1-1.4 1.3H8.7a1.4 1.4 0 0 1-1.4-1.3L6.4 7.6zm3 2v8.6h1.6V9.6H9.4zm3.6 0v8.6h1.6V9.6H13z",
  // doc.on.clipboard: a filled board behind, a page outlined in front with
  // its corner folded, the page's inside cut out of both. The ring's
  // clipboard disc is the same symbol on the Mac.
  clipboard: "M21.72 2.55v14.07a2.55 2.55 0 0 1-2.55 2.55H17.1v2.22a2.55 2.55 0 0 1-2.55 2.55H4.8a2.55 2.55 0 0 1-2.55-2.55V7.35A2.55 2.55 0 0 1 4.8 4.8h2.07V2.55A2.55 2.55 0 0 1 9.42 0h9.75a2.55 2.55 0 0 1 2.55 2.55zM17.2 2.6a.67.67 0 0 0-.66-.66h-4.49a.67.67 0 0 0-.66.66a.67.67 0 0 0 .66.67h4.49a.67.67 0 0 0 .66-.67zM15.57 21.39v-7.8H9.9a1.5 1.5 0 0 1-1.5-1.5V6.33H4.8A1.02 1.02 0 0 0 3.78 7.35v14.04A1.02 1.02 0 0 0 4.8 22.41h9.75a1.02 1.02 0 0 0 1.02-1.02zM15.06 11.91L10.08 6.84a.15.15 0 0 0-.16-.03a.15.15 0 0 0-.1.14v4.99a.22.22 0 0 0 .23.23h4.9a.15.15 0 0 0 .14-.1a.15.15 0 0 0-.03-.16z",
  // gearshape: eight flat-topped teeth on a base circle, outlined, and a ring
  // for the hole. The ring's and Settings' gear is the same symbol on the Mac.
  gear: "M8.92 4.23l.44-1.98a1.58 1.58 0 0 1 1.55-1.24h2.18a1.58 1.58 0 0 1 1.55 1.24l.44 1.98a8.36 8.36 0 0 1 .24.1l1.71-1.09A1.58 1.58 0 0 1 19 3.45L20.55 5a1.58 1.58 0 0 1 .21 1.97L19.67 8.68a8.36 8.36 0 0 1 .1.24l1.98.44a1.58 1.58 0 0 1 1.24 1.55v2.18a1.58 1.58 0 0 1-1.24 1.55l-1.98.44a8.36 8.36 0 0 1-.1.24l1.09 1.71A1.58 1.58 0 0 1 20.55 19L19 20.55a1.58 1.58 0 0 1-1.97.21l-1.71-1.09a8.36 8.36 0 0 1-.24.1l-.44 1.98a1.58 1.58 0 0 1-1.55 1.24h-2.18a1.58 1.58 0 0 1-1.55-1.24l-.44-1.98a8.36 8.36 0 0 1-.24-.1L6.97 20.76A1.58 1.58 0 0 1 5 20.55L3.45 19a1.58 1.58 0 0 1-.21-1.97l1.09-1.71a8.36 8.36 0 0 1-.1-.24l-1.98-.44a1.58 1.58 0 0 1-1.24-1.55v-2.18A1.58 1.58 0 0 1 2.25 9.36l1.98-.44a8.36 8.36 0 0 1 .1-.24L3.24 6.97A1.58 1.58 0 0 1 3.45 5L5 3.45a1.58 1.58 0 0 1 1.97-.21L8.68 4.33a8.36 8.36 0 0 1 .24-.1zM9.31 5.78a1.58 1.58 0 0 1-1.48-.12L6.12 4.57L4.57 6.12L5.66 7.83a1.58 1.58 0 0 1 .12 1.48a6.78 6.78 0 0 0-.08.2a1.58 1.58 0 0 1-1.13.96l-1.98.44v2.18l1.98.44a1.58 1.58 0 0 1 1.13.96a6.78 6.78 0 0 0 .08.2a1.58 1.58 0 0 1-.12 1.48L4.57 17.88l1.55 1.55l1.71-1.09a1.58 1.58 0 0 1 1.48-.12a6.78 6.78 0 0 0 .2.08a1.58 1.58 0 0 1 .96 1.13l.44 1.98h2.18l.44-1.98a1.58 1.58 0 0 1 .96-1.13a6.78 6.78 0 0 0 .2-.08a1.58 1.58 0 0 1 1.48.12l1.71 1.09l1.55-1.55l-1.09-1.71a1.58 1.58 0 0 1-.12-1.48a6.78 6.78 0 0 0 .08-.2a1.58 1.58 0 0 1 1.13-.96l1.98-.44v-2.18l-1.98-.44a1.58 1.58 0 0 1-1.13-.96a6.78 6.78 0 0 0-.08-.2a1.58 1.58 0 0 1 .12-1.48l1.09-1.71L17.88 4.57L16.17 5.66a1.58 1.58 0 0 1-1.48.12a6.78 6.78 0 0 0-.2-.08a1.58 1.58 0 0 1-.96-1.13l-.44-1.98h-2.18l-.44 1.98A1.58 1.58 0 0 1 9.51 5.7a6.78 6.78 0 0 0-.2.08zM12 8.11A3.89 3.89 0 0 1 15.89 12A3.89 3.89 0 0 1 12 15.89A3.89 3.89 0 0 1 8.11 12A3.89 3.89 0 0 1 12 8.11zM12 9.69A2.31 2.31 0 0 0 9.69 12A2.31 2.31 0 0 0 12 14.31A2.31 2.31 0 0 0 14.31 12A2.31 2.31 0 0 0 12 9.69z",
  // speaker.wave.2: the speaker outlined, two waves.
  speakerOn: "M2.86 8.02h3.16L10.8 3.69a1.28 1.28 0 0 1 1.37-.22a1.28 1.28 0 0 1 .76 1.17v14.83a1.28 1.28 0 0 1-.76 1.17a1.28 1.28 0 0 1-1.37-.22L6.02 16.09H2.86a1.83 1.83 0 0 1-1.83-1.83V9.85A1.83 1.83 0 0 1 2.86 8.02zM6.99 14.92l4.42 4.01V5.18l-4.42 4a1.37 1.37 0 0 1-.91.36H2.86a.31.31 0 0 0-.31.31v4.41a.31.31 0 0 0 .31.31h3.22a1.37 1.37 0 0 1 .91.35zM17.44 8.06a8.04 8.04 0 0 1 0 7.97a.76.76 0 0 1-1.04.28a.76.76 0 0 1-.29-1.04a6.51 6.51 0 0 0 0-6.45a.76.76 0 0 1 .29-1.05a.76.76 0 0 1 1.04.29zM21.07 5.44a12.5 12.5 0 0 1 0 13.21a.76.76 0 0 1-1.05.25a.76.76 0 0 1-.25-1.06a10.98 10.98 0 0 0 0-11.6a.76.76 0 0 1 .25-1.05a.76.76 0 0 1 1.05.25z",
  // speaker.slash: the same speaker, struck through and cut away either side
  // of the stroke.
  speakerOff: "M9.85 6.4l5.42-4.9a1.49 1.49 0 0 1 1.6-.26a1.49 1.49 0 0 1 .89 1.36v11.71zM15.99 12.54V3.23L11.1 7.66zM17.58 20.54a1.49 1.49 0 0 1-1.05.78a1.49 1.49 0 0 1-1.26-.37L9.71 15.92H6.04a2.13 2.13 0 0 1-2.13-2.13V8.66a2.13 2.13 0 0 1 .46-1.33zM10.85 14.56l5.14 4.66v-.28L5.68 8.63a.36.36 0 0 0-.01.03v5.13a.36.36 0 0 0 .37.36h3.74a1.59 1.59 0 0 1 1.07.41zM3.09 1.62L22.68 21.24a.87.87 0 0 1 0 1.23a.87.87 0 0 1-1.24 0L1.86 2.85a.87.87 0 0 1 0-1.23a.87.87 0 0 1 1.23 0z",
  // arrow.up.right
  arrowUpRight: "M8.5 7h8.5v8.5h-2V10.4l-7.1 7.1-1.4-1.4 7.1-7.1H8.5V7z",
  // chevron.right
  chevronRight: "M9 5.5 15.5 12 9 18.5",
  // calendar: a rounded page, its top band solid, ten dots in rows of three,
  // four and three. The Agenda's header draws the same symbol on the Mac.
  calendar: "M22.73 4.93v14.02a2.88 2.88 0 0 1-2.88 2.88H4.2a2.88 2.88 0 0 1-2.87-2.88V4.93A2.88 2.88 0 0 1 4.2 2.05h15.65a2.88 2.88 0 0 1 2.88 2.88zM21 18.92V8.16a1.18 1.18 0 0 0-1.18-1.18H4.24A1.18 1.18 0 0 0 3.05 8.16v10.76A1.18 1.18 0 0 0 4.24 20.1h15.58A1.18 1.18 0 0 0 21 18.92zM11.05 9.7v.66a.47.47 0 0 1-.48.48h-.66a.47.47 0 0 1-.48-.48V9.7a.47.47 0 0 1 .48-.48h.66a.47.47 0 0 1 .48.48zM14.62 9.7v.66a.47.47 0 0 1-.48.48h-.66a.47.47 0 0 1-.48-.48V9.7a.47.47 0 0 1 .48-.48h.66a.47.47 0 0 1 .48.48zM18.19 9.7v.66a.47.47 0 0 1-.48.48h-.66a.47.47 0 0 1-.48-.48V9.7a.47.47 0 0 1 .48-.48h.66a.47.47 0 0 1 .48.48zM7.47 13.2v.67a.47.47 0 0 1-.47.47h-.67a.47.47 0 0 1-.48-.47v-.67a.47.47 0 0 1 .48-.48H7a.47.47 0 0 1 .47.48zM11.05 13.2v.67a.47.47 0 0 1-.48.47h-.66a.47.47 0 0 1-.48-.47v-.67a.47.47 0 0 1 .48-.48h.66a.47.47 0 0 1 .48.48zM14.62 13.2v.67a.47.47 0 0 1-.48.47h-.66a.47.47 0 0 1-.48-.47v-.67a.47.47 0 0 1 .48-.48h.66a.47.47 0 0 1 .48.48zM18.19 13.2v.67a.47.47 0 0 1-.48.47h-.66a.47.47 0 0 1-.48-.47v-.67a.47.47 0 0 1 .48-.48h.66a.47.47 0 0 1 .48.48zM7.47 16.72v.66a.47.47 0 0 1-.47.48h-.67a.47.47 0 0 1-.48-.48v-.66a.47.47 0 0 1 .48-.48H7a.47.47 0 0 1 .47.48zM11.05 16.72v.66a.47.47 0 0 1-.48.48h-.66a.47.47 0 0 1-.48-.48v-.66a.47.47 0 0 1 .48-.48h.66a.47.47 0 0 1 .48.48zM14.62 16.72v.66a.47.47 0 0 1-.48.48h-.66a.47.47 0 0 1-.48-.48v-.66a.47.47 0 0 1 .48-.48h.66a.47.47 0 0 1 .48.48z",
  // arrow.clockwise, drawn as a stroke (svg(..., { stroke: 2 })).
  refresh: "M19 12a7 7 0 1 1-2.05-4.95M19 4.6v3.6h-3.6",
  chevronLeft: "M15 5.5 8.5 12 15 18.5",
  // checkmark
  check: "M5 12.5 9.5 17 19 7.5",
  // arrow.up (send)
  arrowUp: "M12 4.5 5.5 11l1.5 1.5 4-4V19.5h2V8.5l4 4L18.5 11 12 4.5z",
  // exclamationmark
  bang: "M11 4h2v10h-2V4zm0 12.2h2v2.2h-2v-2.2z",
  // xmark, heavy — the small close buttons on cards, which the Mac sets
  // semibold to heavy.
  xmark: "M6.4 5 12 10.6 17.6 5 19 6.4 13.4 12 19 17.6 17.6 19 12 13.4 6.4 19 5 17.6 10.6 12 5 6.4 6.4 5z",
  // xmark at 13 pt regular: the header's close, thinner than the one above.
  xmarkRegular: "M3.04 1.32L21.96 20.24a1.18 1.18 0 0 1 0 1.68a1.18 1.18 0 0 1-1.68 0L1.36 3a1.18 1.18 0 0 1 0-1.68a1.18 1.18 0 0 1 1.68 0zM21.96 3L3.04 21.92a1.18 1.18 0 0 1-1.68 0a1.18 1.18 0 0 1 0-1.68L20.28 1.32a1.18 1.18 0 0 1 1.68 0a1.18 1.18 0 0 1 0 1.68z",
  // timer: a dial open between twelve and where the hand points, a stem down
  // from twelve, the hand tapering from a disc at the centre. The ring's
  // timer disc is the same symbol on the Mac.
  timer: "M4.05 5.08a.87.87 0 0 1 1.23-.09a.87.87 0 0 1 .09 1.23a8.74 8.74 0 0 0-.51 10.82a8.74 8.74 0 0 0 10.4 3a8.74 8.74 0 0 0 5.33-9.42a8.74 8.74 0 0 0-7.93-7.38v2.39a.75.75 0 0 1-.75.75a.75.75 0 0 1-.75-.75V1.97a.49.49 0 0 1 .47-.49A10.48 10.48 0 0 1 22.14 9.49a10.48 10.48 0 0 1-5.69 11.92A10.48 10.48 0 0 1 3.62 18.29A10.48 10.48 0 0 1 4.05 5.08zM10.62 12.9L6.98 7.76a.57.57 0 0 1 .06-.73a.57.57 0 0 1 .73-.06l5.14 3.64a1.65 1.65 0 0 1 .66 1.68a1.65 1.65 0 0 1-1.27 1.27a1.65 1.65 0 0 1-1.68-.66z",
  // ellipsis
  ellipsis: "M6 10.4a1.6 1.6 0 1 0 0 3.2 1.6 1.6 0 0 0 0-3.2zm6 0a1.6 1.6 0 1 0 0 3.2 1.6 1.6 0 0 0 0-3.2zm6 0a1.6 1.6 0 1 0 0 3.2 1.6 1.6 0 0 0 0-3.2z",
  // star.fill
  star: "M12 3.2l2.6 5.55 5.9.82-4.3 4.3 1.05 6.13L12 17.1l-5.25 2.9L7.8 13.87 3.5 9.57l5.9-.82L12 3.2z",
  // square.stack.fill
  stack: "M5 8h14v11.5H5V8zm1.8-3h10.4v1.6H6.8V5zm1.6-2.6h7.2V4H8.4V2.4z",
  // doc.text
  doc: "M6.5 2.6h7l4 4v14.8h-11V2.6zm6.6 1.6v3.3h3.3l-3.3-3.3zM8.6 11h6.8v1.5H8.6V11zm0 3.4h6.8v1.5H8.6v-1.5z",

  // Transport, on the Now Playing card.
  // backward.fill
  backward: "M11.4 12L20 6.4v11.2L11.4 12zm-8 0L12 6.4v11.2L3.4 12z",
  // mic.fill — recording a voice note on the reply bar.
  mic: "M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3zM6.2 11.4H4.6a7.4 7.4 0 0 0 6.6 7.35V22h1.6v-3.25a7.4 7.4 0 0 0 6.6-7.35h-1.6a5.8 5.8 0 0 1-11.6 0z",
  // stop.fill — and stopping one.
  stop: "M6.6 6.6h10.8v10.8H6.6V6.6z",
  // play.fill
  play: "M7.5 5.2l11 6.8-11 6.8V5.2z",
  // pause.fill
  pause: "M7 5.4h3.4v13.2H7V5.4zm6.6 0H17v13.2h-3.4V5.4z",
  // forward.fill
  forward: "M12.6 12L4 17.6V6.4L12.6 12zm8 0L12 17.6V6.4L20.6 12z",
  // music.note — the stand-in when a player sends no artwork.
  musicNote: "M9.4 17.2a2.6 2.6 0 1 1-1.8-2.47V5.6l10-2.2v9.9a2.6 2.6 0 1 1-1.8-2.47V7.3l-6.4 1.4v8.5z",
  // snowflake — drawn with a stroke, for the Christmas album's badge.
  snowflake: "M12 2.5v19M3.8 7.25l16.4 9.5M3.8 16.75l16.4-9.5M9.4 4.2 12 6.3l2.6-2.1M9.4 19.8 12 17.7l2.6 2.1",
  // speaker.wave.2.fill / speaker.slash.fill
  speakerSmall: "M4 9.4h3.4L11.6 6v12L7.4 14.6H4V9.4z",

  // The AI Agents mark: three four-pointed stars with concave waists, the same
  // geometry as SparklesShape.swift — every centre, radius and waist is a
  // fraction of the glyph's own box, so it stays the drawing at any size.
  sparkles: "M13.55 6.53Q14.38 14.39 21.82 15.26Q14.38 16.14 13.55 24Q12.72 16.14 5.29 15.26Q12.72 14.39 13.55 6.53ZM6.27 3.79Q6.68 7.55 10.35 7.97Q6.68 8.39 6.27 12.14Q5.86 8.39 2.18 7.97Q5.86 7.55 6.27 3.79ZM11.41 0Q11.63 2.1 13.55 2.33Q11.63 2.56 11.41 4.66Q11.2 2.56 9.27 2.33Q11.2 2.1 11.41 0Z",
  // dollarsign.circle
  dollar: "M12 2.6a9.4 9.4 0 1 0 0 18.8 9.4 9.4 0 0 0 0-18.8zm0 1.8a7.6 7.6 0 1 1 0 15.2 7.6 7.6 0 0 1 0-15.2zm-.9 2.2v1.2c-1.4.2-2.4 1.1-2.4 2.4 0 1.5 1.1 2.1 2.6 2.5 1.2.3 1.6.6 1.6 1.2 0 .6-.5 1-1.4 1-1 0-1.7-.4-1.8-1.2H7.9c.1 1.4 1.1 2.3 2.6 2.5v1.2h1.8v-1.2c1.5-.2 2.5-1.1 2.5-2.5 0-1.4-.9-2.1-2.6-2.5-1.2-.3-1.6-.6-1.6-1.1 0-.6.5-1 1.3-1 .9 0 1.5.4 1.6 1.1h1.8c-.1-1.3-1-2.2-2.4-2.4V6.6h-1.8z",
  // chart.bar
  chart: "M3.6 19.4h16.8v1.8H3.6v-1.8zm1.2-7.2h3v6h-3v-6zm5.2-6h3v12h-3v-12zm5.2 3h3v9h-3v-9z",
  // folder
  folder: "M3 5.4h6.3l1.6 2h10.1v11.2H3V5.4zm1.8 1.8v9.6h14.4V9.2h-9.2l-1.6-2H4.8z",

  // bell.fill — the Notifications pill, over both message services.
  bell: "M12 2.4a1.3 1.3 0 0 1 1.3 1.3v.6a5.9 5.9 0 0 1 4.6 5.75v3.3l1.5 2.6a1 1 0 0 1-.87 1.5H5.47a1 1 0 0 1-.87-1.5l1.5-2.6v-3.3A5.9 5.9 0 0 1 10.7 4.3v-.6A1.3 1.3 0 0 1 12 2.4zm0 17.9a2.4 2.4 0 0 1-2.3-1.7h4.6a2.4 2.4 0 0 1-2.3 1.7z",
  // chevron.left.forwardslash.chevron.right — the Claude Code pill.
  code: "M8.3 6.2 2.9 11.6a.6.6 0 0 0 0 .85l5.4 5.4 1.4-1.4-4.7-4.45 4.7-4.4-1.4-1.4zm7.4 0-1.4 1.4 4.7 4.4-4.7 4.45 1.4 1.4 5.4-5.4a.6.6 0 0 0 0-.85l-5.4-5.4zM13.6 4.4l-3.1 15.2-1.85-.38L11.75 4l1.85.4z",
  // message.fill — the two message pills, each in its own colour.
  bubble: "M12 3.2c-5 0-9 3.3-9 7.4 0 2.3 1.25 4.35 3.2 5.7-.15 1.3-.75 2.5-1.7 3.4 1.7-.2 3.3-.85 4.6-1.85 .93.23 1.9.35 2.9.35 5 0 9-3.3 9-7.6S17 3.2 12 3.2z",

  // globe — the site the island can put on screen: a ring, the axis, the
  // equator, both meridians as one ellipse, and two parallels bowed towards
  // the equator.
  globe: "M11.96 1.48A10.47 10.47 0 0 1 22.43 11.95A10.47 10.47 0 0 1 11.96 22.42A10.47 10.47 0 0 1 1.49 11.95A10.47 10.47 0 0 1 11.96 1.48zM11.96 2.87a9.08 9.08 0 0 0-9.08 9.08a9.08 9.08 0 0 0 9.08 9.09a9.08 9.08 0 0 0 9.08-9.09a9.08 9.08 0 0 0-9.08-9.08zM12.64 2.18v19.55a.68.68 0 0 1-.68.68a.68.68 0 0 1-.68-.68V2.18a.68.68 0 0 1 .68-.68a.68.68 0 0 1 .68.68zM2.18 11.27h19.56a.68.68 0 0 1 .68.68a.68.68 0 0 1-.68.68H2.18a.68.68 0 0 1-.68-.68a.68.68 0 0 1 .68-.68zM11.96 1.97a5.17 9.99 0 0 1 5.17 9.98a5.17 9.99 0 0 1-5.17 9.99a5.17 9.99 0 0 1-5.17-9.99a5.17 9.99 0 0 1 5.17-9.98zM11.96 3.32a3.81 8.63 0 0 0-3.81 8.63a3.81 8.63 0 0 0 3.81 8.63a3.81 8.63 0 0 0 3.81-8.63a3.81 8.63 0 0 0-3.81-8.63zM19.62 6.06a15.18 15.18 0 0 1-15.32 0a.68.68 0 0 1-.25-.93a.68.68 0 0 1 .93-.25a13.82 13.82 0 0 0 13.95 0a.68.68 0 0 1 .93.25a.68.68 0 0 1-.24.93zM4.3 17.85a15.18 15.18 0 0 1 15.32 0a.68.68 0 0 1 .24.93a.68.68 0 0 1-.93.24a13.82 13.82 0 0 0-13.95 0a.68.68 0 0 1-.93-.24a.68.68 0 0 1 .25-.93z",

  // drop.fill — the Hydration tab: a round bottom, a rounded tip, sides that
  // bulge a little.
  drop: "M12.46 1.28a30.46 30.46 0 0 1 6.53 11.99a7.45 7.45 0 0 1-2.87 8.1a7.45 7.45 0 0 1-8.59 0a7.45 7.45 0 0 1-2.88-8.1A30.46 30.46 0 0 1 11.19 1.28A.85.85 0 0 1 11.82 1a.85.85 0 0 1 .64.28z",
  // arrow.uturn.backward, drawn as a stroke — taking back a glass.
  undo: "M9 14 4 9l5-5M4 9h10.5a5.5 5.5 0 0 1 0 11H11",
  // moon.fill — a rest day in the streak.
  moon: "M20.5 14.6A8.6 8.6 0 0 1 9.4 3.5a8.6 8.6 0 1 0 11.1 11.1z",

  // Attach, on the reply box.
  paperclip: "M16.4 6.6v8.9a4.4 4.4 0 0 1-8.8 0V6.1a2.8 2.8 0 0 1 5.6 0v9a1.2 1.2 0 0 1-2.4 0V7h-1.6v8.1a2.8 2.8 0 0 0 5.6 0v-9a4.4 4.4 0 0 0-8.8 0v9.4a6 6 0 0 0 12 0V6.6h-1.6z",
} as const;

/**
 * The size, in px, of the 24-unit box that shows each header glyph at the
 * size the Mac's symbol has in the island header: its ink box within a few
 * hundredths of a point of the Mac's (dev/header-preview.html draws the
 * row). Centred on the button's frame, as SwiftUI centres the symbol in it.
 */
export const HEADER_PX = {
  house: 16.91,
  chatSparkle: 16,
  clipboard: 16,
  grid: 13.09,
  globe: 14.83,
  calendar: 14.19,
  drop: 14.18,
  timer: 14.83,
  gear: 15.95,
  speakerOn: 16.65,
  speakerOff: 14.31,
  xmarkRegular: 11.32,
} as const satisfies Partial<Record<keyof typeof ICONS, number>>;
