// Putting ChatGPT and the site on the island — the island's half of the page
// host contract with src-tauri.
//
// On the Mac each page is a WKWebView inside the island's own view tree:
// clipped to its card, faded and scaled with it, hidden behind an opacity of
// zero until it has loaded. Here the page is a native webview Rust lays over
// the card — a child of the island's window on Windows, a borderless window
// glued over the same rect on Linux — and nothing drawn in HTML can sit on top
// of it. So the island draws everything around and under the page (the header
// row, the card, the dots, the copy when it cannot load), and this decides when
// the page itself goes over that card:
//
// - only once the island has stopped moving and the card has finished fading
//   in, because a native page cannot follow a spring frame by frame — the
//   Mac's page fades in after it loads, and this is the same moment seen from
//   the other side;
// - away at the start of anything that would move it, before its first frame:
//   another view, a fold, a shrink;
// - placed again when the window, its scale or the island's place changes
//   under it.
//
// Rust decides whether a placed page is on screen yet: it shows it once it is
// "ready", and on its own if that comes later, unless it was hidden first.

import { Bridge, type PageLabel } from "../core/bridge";
import { pageStateCount, setPageState } from "../core/pageState";

interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** The card's own stroke: the page goes inside it, so the hairline stays drawn. */
const STROKE = 1;

const near = (a: Rect, b: Rect) =>
  Math.abs(a.x - b.x) < 0.5 && Math.abs(a.y - b.y) < 0.5
  && Math.abs(a.w - b.w) < 0.5 && Math.abs(a.h - b.h) < 0.5;

/**
 * Whether the card is where it is going to stay: nothing between it and the
 * island is still fading or scaling in. A view arrives on a 0.16 s delay and a
 * spring that overshoots, and a rect read in the middle of that would put the
 * page a few pixels off a card that is still moving.
 */
function still(card: HTMLElement): boolean {
  for (let el: HTMLElement | null = card; el && el.id !== "island"; el = el.parentElement) {
    const cs = getComputedStyle(el);
    if (cs.opacity !== "1") return false;
    if (cs.transform !== "none" && cs.transform !== "matrix(1, 0, 0, 1, 0, 0)") return false;
  }
  return true;
}

export class PageHost {
  /** The page the island is showing, or null on every card. */
  private current: PageLabel | null = null;
  /**
   * Where the island was when its page was last placed, or null while no page
   * is placed: the island moving off that spot is what takes the page off.
   */
  private placed: Rect | null = null;
  /** Placed again on the next still frame even if nothing moved: the scale did. */
  private again = false;

  /**
   * `cardFor` finds the card a page goes over — a `.page-card` in its view;
   * `wake` starts the island's frame loop, which may have gone to sleep.
   */
  constructor(
    private cardFor: (label: PageLabel) => HTMLElement | null,
    private wake: () => void,
  ) {
    // The window, or the scale it is drawn at, changed under a page that is
    // up: Rust works in physical pixels, so the same CSS rect lands elsewhere.
    window.addEventListener("resize", () => this.refresh());
    this.watchScale();
  }

  /**
   * The island changed view or mode. Synchronous, from wherever that happened,
   * so a page that is leaving is told to go before the first frame of the
   * animation that takes it away.
   */
  sync(want: PageLabel | null) {
    if (want === this.current) return;
    if (this.current && this.placed) void Bridge.pageHide(this.current);
    this.placed = null;
    this.again = false;
    this.current = want;
  }

  /**
   * Every page away at once: the island folding, the close shortcut, Escape.
   * The view that asked for one is left to `sync`, which is told next.
   */
  hideAll() {
    this.placed = null;
    this.again = false;
    void Bridge.pageHideAll();
  }

  /** Place the page again on the next still frame — the window or its scale moved. */
  refresh() {
    if (!this.current) return;
    this.again = true;
    this.wake();
  }

  /** A page is waiting to be placed: the frame loop has to keep running for it. */
  get pending(): boolean {
    return this.current != null && (this.placed == null || this.again);
  }

  /**
   * One frame. `island` is the island's rect as drawn this frame, `settling`
   * whether it is still on its way somewhere.
   */
  frame(island: Rect, settling: boolean) {
    const label = this.current;
    if (label == null) return;
    if (this.placed && !near(this.placed, island)) {
      if (settling) {
        // The island is on its way somewhere and the page cannot follow it.
        // It goes now and comes back once the island is still again.
        void Bridge.pageHide(label);
        this.placed = null;
        return;
      }
      // It jumped — another corner, another display: straight to the new spot.
      this.again = true;
    }
    if (this.placed && !this.again) return;
    if (settling) return;
    const card = this.cardFor(label);
    if (!card || !still(card)) return;
    const r = card.getBoundingClientRect();
    const rect: Rect = {
      x: r.left + STROKE,
      y: r.top + STROKE,
      w: r.width - STROKE * 2,
      h: r.height - STROKE * 2,
    };
    if (rect.w <= 0 || rect.h <= 0) return;
    // Placed for the first time on this screen, or again because something
    // moved under it: either way Rust is told where.
    this.placed = { ...island };
    this.again = false;
    const count = pageStateCount(label);
    void Bridge.pageShow(label, rect.x, rect.y, rect.w, rect.h).then((state) => {
      // Only if no event has said something newer since.
      if (state && pageStateCount(label) === count) setPageState(state);
    });
  }

  /**
   * `devicePixelRatio` changes without a resize when the window moves to a
   * display of another scale. A media query on the current ratio is the one
   * thing that fires for it, and it has to be asked again for the new one.
   */
  private watchScale() {
    const ratio = window.devicePixelRatio || 1;
    const query = window.matchMedia?.(`(resolution: ${ratio}dppx)`);
    query?.addEventListener("change", () => {
      this.refresh();
      this.watchScale();
    }, { once: true });
  }
}
