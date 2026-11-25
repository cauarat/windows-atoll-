// "Version x.y.z is here" — the updater's notification card.
//
// Ports `UpdateCardView` (NotchBuddy/Sources/App/UpdateCardView.swift): the
// 108 px gutter for Mochi, a who line, one title, one grey line, the buttons,
// and on the right an arrow in an indigo ring over "this version → that one".
// Indigo is the wash no other notification uses.
//
// Two states the Mac never shows, because Sparkle downloads before the card
// appears: "Downloading…" with a bar, and a failure. One the Mac shows only as
// a Sparkle window: "manual", for a copy that cannot replace itself.

import { h, svg, dot } from "./dom";
import { ICONS } from "./icons";
import { btn, card, type ViewActions, type ViewHost } from "./views";
import { Updates, type UpdateOffer } from "../core/updates";
import { t } from "../core/i18n";

const INDIGO = "#818CF8";

export function buildUpdate(actions: ViewActions): ViewHost {
  const title = h("div", { class: "title upd-title" });
  const sub = h("div", { class: "sub upd-sub" });

  const updateNow = btn(t("Update now"), "primary", () => Updates.install());
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
  const el = h("div", { class: "view update" }, card("indigo", wrap));

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
