// "Version x.y.z is here" — the updater's notification card.
//
// Ports `UpdateCardView` (NotchBuddy/Sources/App/UpdateCardView.swift): the
// 108 px gutter for Mochi, a who line, one title, one grey line, the buttons,
// and on the right an arrow in an indigo ring over "this version → that one".
// Indigo is the wash no other notification uses.
//
// Two states the Mac never shows, because Sparkle downloads before the card
// appears: "Downloading…" with a bar (a candy cane at Christmas), and a failure. One the Mac shows only as
// a Sparkle window: "manual", for a copy that cannot replace itself.

import { h, svg, dot } from "./dom";
import { ICONS } from "./icons";
import { btn, card, type ViewActions, type ViewHost } from "./views";
import { Updates, type UpdateOffer } from "../core/updates";
import { reducedMotion } from "../core/hydrationText";
import { isFestiveSeason } from "../mochi/character";
import { t } from "../core/i18n";

const INDIGO = "#818CF8";

// ── The confetti ──────────────────────────────────────────────────────────────
// `UpdateConfetti` in UpdateCardView.swift, number for number: 64 pieces from a
// fixed hash, each one's place solved from the time since the click (drag and
// gravity), so nothing is stepped. A canvas behind the words, inside the card,
// drawn by its own animation frames for the 2.5 s it lasts and no longer.

const CONFETTI_S = 2.5;
const COLOURS = ["#818CF8", "#A5B4FC", "#F472B6", "#FBBF24", "#34D399", "#22D3EE", "#F5F6F8", "#FB7185"];

interface Piece {
  vx: number; vy: number; w: number; h: number;
  spin: number; turn: number; flip: number; phase: number;
  round: boolean; color: string;
}

/** The Swift side's splitmix hash, so both platforms throw the same burst. */
function unit(i: number, salt: number): number {
  let x = (BigInt(i + 1) * 0x9E3779B97F4A7C15n + BigInt(salt) * 0xBF58476D1CE4E5B9n) & 0xFFFFFFFFFFFFFFFFn;
  x ^= x >> 31n;
  x = (x * 0x94D049BB133111EBn) & 0xFFFFFFFFFFFFFFFFn;
  x ^= x >> 29n;
  return Number(x % 10000n) / 10000;
}

const PIECES: Piece[] = Array.from({ length: 64 }, (_, i) => {
  const angle = unit(i, 1) * 2 * Math.PI;
  const speed = 160 + unit(i, 2) * 300;
  const round = unit(i, 3) < 0.22;
  return {
    vx: Math.cos(angle) * speed * 1.4, vy: Math.sin(angle) * speed - 140,
    w: round ? 6 : 5 + unit(i, 4) * 4, h: round ? 6 : 9 + unit(i, 5) * 5,
    spin: unit(i, 6) * 360, turn: (unit(i, 7) - 0.5) * 900,
    flip: 5 + unit(i, 8) * 9, phase: unit(i, 9) * 6,
    round, color: COLOURS[i % COLOURS.length],
  };
});

function buildConfetti(): { el: HTMLCanvasElement; fire(): void } {
  const el = h("canvas", { class: "upd-confetti", "aria-hidden": "true" });
  let frame = 0;
  const draw = (start: number) => (now: number) => {
    const ctx = el.getContext("2d");
    const t = (now - start) / 1000;
    const w = el.clientWidth, hgt = el.clientHeight;
    if (!ctx || t >= CONFETTI_S) {
      ctx?.clearRect(0, 0, el.width, el.height);
      frame = 0;
      return;
    }
    const dpr = window.devicePixelRatio || 1;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, hgt);
    // The numbers are for a 160 px card; the throw is scaled to this one.
    const k = hgt / 160;
    const ox = w / 2, oy = hgt * 0.55;
    const dragX = 1.5, dragY = 1.1, gravity = 430 * k;
    const fade = t > 1.8 ? Math.max(0, 1 - (t - 1.8) / 0.7) : Math.min(1, t / 0.05);
    ctx.globalAlpha = fade;
    for (const p of PIECES) {
      const x = ox + (p.vx * k / dragX) * (1 - Math.exp(-dragX * t));
      const y = oy + (gravity / dragY) * t + ((p.vy * k - gravity / dragY) * (1 - Math.exp(-dragY * t))) / dragY;
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(((p.spin + p.turn * t) * Math.PI) / 180);
      ctx.scale(Math.cos(t * p.flip + p.phase), 1);
      ctx.fillStyle = p.color;
      ctx.beginPath();
      if (p.round) ctx.ellipse(0, 0, p.w / 2, p.h / 2, 0, 0, Math.PI * 2);
      else ctx.roundRect(-p.w / 2, -p.h / 2, p.w, p.h, 1.5);
      ctx.fill();
      ctx.restore();
    }
    frame = requestAnimationFrame(draw(start));
  };
  return {
    el,
    fire() {
      if (reducedMotion()) return;
      cancelAnimationFrame(frame);
      const dpr = window.devicePixelRatio || 1;
      el.width = Math.round(el.clientWidth * dpr);
      el.height = Math.round(el.clientHeight * dpr);
      const start = performance.now();
      frame = requestAnimationFrame(draw(start));
    },
  };
}

export function buildUpdate(actions: ViewActions): ViewHost {
  const title = h("div", { class: "title upd-title" });
  const sub = h("div", { class: "sub upd-sub" });

  const confetti = buildConfetti();
  const updateNow = btn(t("Update now"), "primary", () => { confetti.fire(); Updates.install(); });
  const openPage = btn(t("Open the download page"), "primary", () => Updates.install());
  const later = () => { actions.blip(); Updates.later(); actions.collapse(); };
  const offerRow = h("div", { class: "actions" }, updateNow, btn(t("Later"), "secondary", later));
  const manualRow = h("div", { class: "actions" }, openPage, btn(t("Later"), "secondary", later));

  const fill = h("div", { class: "upd-fill" });
  const percent = h("span", { class: "upd-percent" });
  const progressRow = h("div", { class: "upd-progress" }, h("div", { class: "upd-track" }, fill), percent);

  const jump = h("span", { class: "upd-jump" });
  const wrap = h("div", { class: "upd-wrap" },
    h("div", { class: "upd-text" },
      h("div", { class: "upd-who" }, dot(INDIGO, 7), h("b", { text: "Notchy" }), h("span", { text: t("new version") })),
      h("div", { class: "upd-body" }, title, sub, offerRow, manualRow, progressRow)),
    h("div", { class: "upd-side", "aria-hidden": "true" },
      h("div", { class: "upd-ring" }, svg(ICONS.arrowUp, 20)),
      jump),
  );
  const el = h("div", { class: "view update" }, card("indigo", confetti.el, wrap));

  const show = (row: HTMLElement, on: boolean) => { row.style.display = on ? "" : "none"; };

  return {
    el,
    sync() {
      const offer: UpdateOffer | null = Updates.offer;
      if (!offer) return;
      jump.textContent = Updates.current ? `${Updates.current} → ${offer.version}` : offer.version;
      show(offerRow, offer.kind === "available");
      show(manualRow, offer.kind === "manual" || offer.kind === "failed");
      show(progressRow, offer.kind === "downloading");
      switch (offer.kind) {
        case "available":
          title.textContent = t("Version %@ is here", offer.version);
          sub.textContent = t("It takes a few seconds, and Notchy comes right back.");
          break;
        case "manual":
          title.textContent = t("Version %@ is here", offer.version);
          sub.textContent = t("This copy can't install it by itself.");
          break;
        case "downloading": {
          // At Christmas the bar is a candy cane: red and white stripes that
          // roll while it fills. Only here, where the bar is — the Mac has none,
          // because Sparkle downloads before the card appears.
          progressRow.classList.toggle("cane", isFestiveSeason());
          title.textContent = t("Downloading %@…", offer.version);
          sub.textContent = t("Notchy restarts by itself when it's done.");
          // No Content-Length is reported as 0: an empty bar, not a made-up number.
          const pct = Math.round(offer.progress * 100);
          fill.style.width = `${pct}%`;
          percent.textContent = `${pct}%`;
          break;
        }
        case "restarting":
          title.textContent = t("Restarting…");
          sub.textContent = t("Back in a moment, on %@.", offer.version);
          break;
        case "failed":
          title.textContent = t("The update didn't install.");
          sub.textContent = offer.error;
          break;
      }
    },
  };
}
